# Interior Pro - Wall Merge Tool

module InteriorPro
  class WallMergeTool

    STATE_PICK_EXISTING        = 1
    STATE_PICK_FIRST_TOUCHING  = 2
    STATE_PICK_SECOND_TOUCHING = 3

    def activate
      @state = STATE_PICK_EXISTING
      @existing_wall = nil
      @first_touching = nil
      @second_touching = nil
      update_status_bar
    end

    def deactivate(view)
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      entity = ph.best_picked

      return unless entity.is_a?(Sketchup::Group) &&
                    entity.get_attribute('InteriorPro', 'type') == 'wall'

      case @state
      when STATE_PICK_EXISTING
        @existing_wall = entity
        @state = STATE_PICK_FIRST_TOUCHING
        update_status_bar
      when STATE_PICK_FIRST_TOUCHING
        @first_touching = entity
        @state = STATE_PICK_SECOND_TOUCHING
        update_status_bar
      when STATE_PICK_SECOND_TOUCHING
        @second_touching = entity
        detect_both_contacts
        reset
      end
    end

    def onCancel(reason, view)
      reset
    end

    def reset
      @state = STATE_PICK_EXISTING
      @existing_wall = nil
      @first_touching = nil
      @second_touching = nil
      update_status_bar
    end

    def update_status_bar
      msg = case @state
            when STATE_PICK_EXISTING        then 'Click the existing wall to cut'
            when STATE_PICK_FIRST_TOUCHING  then 'Click first wall that touches the existing wall'
            when STATE_PICK_SECOND_TOUCHING then 'Click second wall that touches the existing wall'
            end
      Sketchup.set_status_text(msg, SB_PROMPT)
    end

    private

    def detect_both_contacts
      ex_drawn  = read_drawn_line(@existing_wall)
      ex_thick  = @existing_wall.get_attribute('InteriorPro', 'thickness').to_f
      ex_anchor = @existing_wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      _, ex_h_anchor = parse_anchor(ex_anchor)

      unless ex_drawn && ex_thick > 0
        UI.messagebox("Existing wall is missing required attributes.")
        return
      end

      edges = compute_outer_edges(ex_drawn[0], ex_drawn[1], ex_thick, ex_h_anchor)
      unless edges
        UI.messagebox("Existing wall is too short to compute outer edges.")
        return
      end

      r1 = detect_contact_point(@first_touching,  ex_drawn, edges)
      r2 = detect_contact_point(@second_touching, ex_drawn, edges)

      if r1.nil? || r2.nil?
        UI.messagebox("A touching wall is missing required attributes.")
        return
      end

      if r1[:contact] && r2[:contact]
        perform_split(r1, r2, ex_drawn)
      else
        left_edge, right_edge = edges
        UI.messagebox(
          "No contact within 0.5\" tolerance:\n\n" \
          "Existing wall thickness: #{ex_thick}\"\n" \
          "Existing wall h_anchor:  #{ex_h_anchor}\n\n" \
          "Existing LEFT outer edge:\n" \
          "  (#{left_edge[0].x.round(3)}, #{left_edge[0].y.round(3)}) -> " \
          "(#{left_edge[1].x.round(3)}, #{left_edge[1].y.round(3)})\n\n" \
          "Existing RIGHT outer edge:\n" \
          "  (#{right_edge[0].x.round(3)}, #{right_edge[0].y.round(3)}) -> " \
          "(#{right_edge[1].x.round(3)}, #{right_edge[1].y.round(3)})\n\n" \
          "First touching wall [#{r1[:contact] ? 'OK' : 'MISS'}]:\n" \
          "  start -> LEFT #{r1[:d_left_start].round(4)}\"  RIGHT #{r1[:d_right_start].round(4)}\"\n" \
          "  end   -> LEFT #{r1[:d_left_end].round(4)}\"  RIGHT #{r1[:d_right_end].round(4)}\"\n\n" \
          "Second touching wall [#{r2[:contact] ? 'OK' : 'MISS'}]:\n" \
          "  start -> LEFT #{r2[:d_left_start].round(4)}\"  RIGHT #{r2[:d_right_start].round(4)}\"\n" \
          "  end   -> LEFT #{r2[:d_left_end].round(4)}\"  RIGHT #{r2[:d_right_end].round(4)}\""
        )
      end
    end

    # Splits @existing_wall into two new walls at the two contact positions.
    # Skips zero-length stubs; aborts if any contact lies outside the wall span;
    # leaves connected_windows orphaned by design.
    def perform_split(r1, r2, ex_drawn)
      pos1, pos2 = r1[:position], r2[:position]
      pos1, pos2 = pos2, pos1 if pos1 > pos2

      ex_start_world = ex_drawn[0]
      ex_end_world   = ex_drawn[1]
      wall_vec = ex_end_world - ex_start_world
      wall_len = wall_vec.length
      if wall_len < 0.001
        UI.messagebox("Existing wall has zero length.")
        return
      end
      unit = wall_vec.clone
      unit.normalize!

      tol = 0.001
      if pos1 < -tol || pos2 > wall_len + tol
        UI.messagebox(
          "Cannot split: a contact projects outside the existing wall span.\n\n" \
          "Existing wall length: #{wall_len.round(3)}\"\n" \
          "Contact 1 position:   #{pos1.round(3)}\"\n" \
          "Contact 2 position:   #{pos2.round(3)}\""
        )
        return
      end

      build_a = pos1 > tol
      build_b = pos2 < wall_len - tol

      unless build_a || build_b
        UI.messagebox("Cannot split: both contacts coincide with the existing wall's endpoints.")
        return
      end

      contact1 = Geom::Point3d.new(
        ex_start_world.x + unit.x * pos1,
        ex_start_world.y + unit.y * pos1,
        ex_start_world.z
      )
      contact2 = Geom::Point3d.new(
        ex_start_world.x + unit.x * pos2,
        ex_start_world.y + unit.y * pos2,
        ex_start_world.z
      )

      ad = @existing_wall.attribute_dictionary('InteriorPro').to_h
      original_id   = ad['id'].to_s
      original_mark = ad['mark'].to_s
      attrs = {
        thickness:         ad['thickness'],
        height:            ad['height'],
        anchor:            ad['anchor'],
        wall_type:         ad['wall_type'],
        exterior_material: ad['exterior_material'],
        interior_material: ad['interior_material']
      }

      model = Sketchup.active_model
      model.start_operation('Merge Walls', true)
      begin
        wt = InteriorPro::WallTool.new
        wt.wall_category = ad['wall_category'] || 'exterior'

        group_a = build_a ? wt.build_wall_group(ex_start_world, contact1, attrs, model) : nil
        raise "build_wall_group failed for wall A" if build_a && !group_a
        normalize_to_identity(group_a) if group_a

        group_b = build_b ? wt.build_wall_group(contact2, ex_end_world, attrs, model) : nil
        raise "build_wall_group failed for wall B" if build_b && !group_b
        normalize_to_identity(group_b) if group_b

        group_a.set_attribute('InteriorPro', 'id', original_id + 'A') if group_a
        group_b.set_attribute('InteriorPro', 'id', original_id + 'B') if group_b
        unless original_mark.empty?
          group_a.set_attribute('InteriorPro', 'mark', original_mark) if group_a
          group_b.set_attribute('InteriorPro', 'mark', original_mark) if group_b
        end

        @existing_wall.erase!

        # Bake the touching walls too: if either has a non-identity transformation,
        # its raw attributes are in its own local frame and would mismatch the
        # new walls' parent-frame attributes inside find_neighbor_at/apply_miter.
        normalize_to_identity(@first_touching)
        normalize_to_identity(@second_touching)

        [group_a, group_b, @first_touching, @second_touching].uniq.each do |w|
          next unless w && w.valid?
          wt.join_corners(w, model, allow_centerline_fallback: true)
        end

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Split failed: #{e.message}")
      end
    end

    # Returns a hash with all 4 distances and, if smallest <= 0.5, the chosen
    # endpoint/side/position along the existing wall. Returns nil if the
    # touching wall lacks attributes.
    def detect_contact_point(touching_wall, ex_drawn, edges)
      left_edge, right_edge = edges
      new_drawn = read_drawn_line(touching_wall)
      return nil unless new_drawn

      new_start = new_drawn[0]
      new_end   = new_drawn[1]

      d_left_start  = point_to_line_distance(new_start, left_edge[0],  left_edge[1])
      d_right_start = point_to_line_distance(new_start, right_edge[0], right_edge[1])
      d_left_end    = point_to_line_distance(new_end,   left_edge[0],  left_edge[1])
      d_right_end   = point_to_line_distance(new_end,   right_edge[0], right_edge[1])

      candidates = [
        [d_left_start,  'start', 'left',  new_start],
        [d_right_start, 'start', 'right', new_start],
        [d_left_end,    'end',   'left',  new_end],
        [d_right_end,   'end',   'right', new_end]
      ]
      best = candidates.min_by { |c| c[0] }

      result = {
        d_left_start:  d_left_start,
        d_right_start: d_right_start,
        d_left_end:    d_left_end,
        d_right_end:   d_right_end,
        contact:       false
      }

      if best[0] <= 0.5
        ex_start = ex_drawn[0]
        wall_vec = ex_drawn[1] - ex_start
        unit = wall_vec.clone
        unit.normalize!
        position = (best[3] - ex_start).dot(unit)

        result[:contact]  = true
        result[:endpoint] = best[1]
        result[:side]     = best[2]
        result[:position] = position
        result[:distance] = best[0]
      end

      result
    end

    # If group has a non-identity transformation, bake it into the stored
    # attributes (start_x/y, end_x/y, corners_xy) AND into the inner geometry,
    # then reset the transformation to identity. After this, the group's
    # attributes are in the parent's coordinate frame, so find_neighbor_at and
    # apply_miter (which read raw attributes) compare endpoints in a single
    # frame across the new walls and the existing/touching walls.
    def normalize_to_identity(group)
      return unless group && group.valid?
      xform = group.transformation
      return if xform.identity?

      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      if sx && sy && ex && ey
        s = Geom::Point3d.new(sx, sy, 0).transform(xform)
        e = Geom::Point3d.new(ex, ey, 0).transform(xform)
        group.set_attribute('InteriorPro', 'start_x', s.x.to_f)
        group.set_attribute('InteriorPro', 'start_y', s.y.to_f)
        group.set_attribute('InteriorPro', 'end_x',   e.x.to_f)
        group.set_attribute('InteriorPro', 'end_y',   e.y.to_f)
      end

      flat = group.get_attribute('InteriorPro', 'corners_xy')
      if flat.is_a?(Array) && flat.length == 8
        new_flat = []
        4.times do |i|
          p = Geom::Point3d.new(flat[i * 2], flat[i * 2 + 1], 0).transform(xform)
          new_flat << p.x.to_f << p.y.to_f
        end
        group.set_attribute('InteriorPro', 'corners_xy', new_flat)
      end

      group.entities.transform_entities(xform, group.entities.to_a)
      group.transformation = Geom::Transformation.new
    end

    # start_x/y and end_x/y are stored LOCAL to the wall group's transformation.
    # Transform to world space so downstream geometry math (distance, projection)
    # works across walls that share a parent.
    def read_drawn_line(wall_group)
      sx = wall_group.get_attribute('InteriorPro', 'start_x')
      sy = wall_group.get_attribute('InteriorPro', 'start_y')
      ex = wall_group.get_attribute('InteriorPro', 'end_x')
      ey = wall_group.get_attribute('InteriorPro', 'end_y')
      return nil unless sx && sy && ex && ey
      xform = wall_group.transformation
      [
        Geom::Point3d.new(sx, sy, 0).transform(xform),
        Geom::Point3d.new(ex, ey, 0).transform(xform)
      ]
    end

    # Returns [[left_start, left_end], [right_start, right_end]].
    # Mirrors centerline derivation from window_tool.rb#cut_window_opening:
    # build_wall_group offsets the drawn line by +n*thickness (h_anchor=left)
    # or -n*thickness (right), so centerline = drawn + n*center_offset where
    # center_offset is +t/2, -t/2, or 0 for left/right/center respectively.
    # Outer edges = centerline +/- n*(thickness/2).
    def compute_outer_edges(drawn_start, drawn_end, thickness, h_anchor)
      wall_vec = drawn_end - drawn_start
      return nil if wall_vec.length < 0.1

      unit = wall_vec.clone
      unit.normalize!
      n = Geom::Vector3d.new(-unit.y, unit.x, 0)

      center_offset = case h_anchor
                      when 'left'  then thickness / 2.0
                      when 'right' then -thickness / 2.0
                      else 0.0
                      end

      cs = Geom::Point3d.new(
        drawn_start.x + n.x * center_offset,
        drawn_start.y + n.y * center_offset,
        0
      )
      ce = Geom::Point3d.new(
        drawn_end.x + n.x * center_offset,
        drawn_end.y + n.y * center_offset,
        0
      )

      half = thickness / 2.0
      left  = [
        Geom::Point3d.new(cs.x + n.x * half, cs.y + n.y * half, 0),
        Geom::Point3d.new(ce.x + n.x * half, ce.y + n.y * half, 0)
      ]
      right = [
        Geom::Point3d.new(cs.x - n.x * half, cs.y - n.y * half, 0),
        Geom::Point3d.new(ce.x - n.x * half, ce.y - n.y * half, 0)
      ]
      [left, right]
    end

    # Perpendicular distance from point to the infinite 2D line through a-b.
    def point_to_line_distance(point, a, b)
      line_vec = b - a
      len = line_vec.length
      return point.distance(a) if len < 1e-9
      to_pt = point - a
      cross_z = line_vec.x * to_pt.y - line_vec.y * to_pt.x
      cross_z.abs / len
    end

    def parse_anchor(anchor)
      if anchor == 'center'
        ['center', 'center']
      else
        parts = anchor.split('-')
        [parts[0] || 'bottom', parts[1] || 'center']
      end
    end

  end
end

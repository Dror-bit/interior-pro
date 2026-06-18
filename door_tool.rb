# Interior Pro - Door Tool
# Cuts a door opening through a wall and (for French Hinged) builds a real body.
# Modeled on WindowTool, but the opening sits on the wall floor + an optional
# threshold offset instead of being measured down from a header height.

module InteriorPro
  class DoorTool

    attr_accessor :door_type, :width, :height, :frame_width, :interior_depth,
                  :floor_offset, :swing_direction, :swing_side, :slide_direction,
                  :handle_type, :preset_name

    def initialize
      @door_type       = 'French Hinged'
      @width           = 36.0
      @height          = 80.0
      @frame_width     = 1.5
      @interior_depth  = 1.0
      @floor_offset    = 0.0
      @swing_direction = 'left'
      @swing_side      = 'auto'
      @slide_direction = 'left'
      @handle_type     = 'lever'
      @preset_name     = ''
    end

    def activate
      Sketchup.set_status_text(
        "Door Tool: hover over a wall and click to cut opening. Press Escape to exit.",
        SB_PROMPT
      )
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      wall, _ = find_wall_under_cursor(view, x, y)
      view.tooltip = wall ? "Click to place #{@width}\" x #{@height}\" door opening" : ''
    end

    def onLButtonDown(flags, x, y, view)
      wall, picked_point, picked_face = find_wall_under_cursor(view, x, y)
      unless wall
        Sketchup.set_status_text("No wall under cursor. Hover over a wall to place a door.", SB_PROMPT)
        return
      end
      cut_door_opening(wall, picked_point, picked_face)
    end

    def onCancel(reason, view)
      Sketchup.active_model.select_tool(nil)
    end

    def onKeyDown(key, repeat, flags, view)
      onCancel(0, view) if key == 27
    end

    private

    def find_wall_under_cursor(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      return [nil, nil, nil] if ph.count == 0

      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        wall = path.find { |e|
          e.is_a?(Sketchup::Group) && e.valid? &&
            e.get_attribute('InteriorPro', 'type') == 'wall'
        }
        next unless wall

        leaf = ph.leaf_at(i)
        face = leaf.is_a?(Sketchup::Face) ? leaf : nil
        point = world_pick_point(view, x, y, ph, i)
        return [wall, point, face] if point
      end
      [nil, nil, nil]
    end

    # PickHelper has no picked_point method. Recover the 3D world-space pick
    # by intersecting the view's pickray with the leaf face's plane (transformed
    # from the group's local space to world space).
    def world_pick_point(view, x, y, ph, index)
      leaf = ph.leaf_at(index)
      if leaf.is_a?(Sketchup::Face)
        transform = ph.transformation_at(index)
        ray = view.pickray(x, y)
        plane_pt = leaf.vertices.first.position.transform(transform)
        plane_normal = leaf.normal.transform(transform)
        pt = Geom.intersect_line_plane(ray, [plane_pt, plane_normal])
        return pt if pt
      end
      # Fallback for non-face leaves (edge picks, etc.)
      ip = Sketchup::InputPoint.new
      ip.pick(view, x, y)
      ip.valid? ? ip.position : nil
    end

    def cut_door_opening(wall_group, picked_point, picked_face = nil)
      sx = wall_group.get_attribute('InteriorPro', 'start_x')
      sy = wall_group.get_attribute('InteriorPro', 'start_y')
      ex = wall_group.get_attribute('InteriorPro', 'end_x')
      ey = wall_group.get_attribute('InteriorPro', 'end_y')
      thickness = wall_group.get_attribute('InteriorPro', 'thickness').to_f
      wall_height = wall_group.get_attribute('InteriorPro', 'height').to_f
      anchor = wall_group.get_attribute('InteriorPro', 'anchor') || 'bottom-center'

      unless sx && sy && ex && ey && thickness > 0 && wall_height > 0
        UI.messagebox("Wall is missing required attributes.")
        return
      end

      drawn_start = Geom::Point3d.new(sx, sy, 0)
      drawn_end = Geom::Point3d.new(ex, ey, 0)
      wall_vec = drawn_end - drawn_start
      wall_length = wall_vec.length
      if wall_length < 0.1
        UI.messagebox("Wall is too short.")
        return
      end

      unit = wall_vec.clone
      unit.normalize!
      n = Geom::Vector3d.new(-unit.y, unit.x, 0)

      v_anchor, h_anchor = parse_anchor(anchor)

      # Adjust drawn line to true centerline based on horizontal anchor (same
      # convention as build_wall_group / WindowTool).
      center_offset = case h_anchor
                      when 'left'  then thickness / 2.0
                      when 'right' then -thickness / 2.0
                      else 0.0
                      end
      cline_start = Geom::Point3d.new(
        drawn_start.x + n.x * center_offset,
        drawn_start.y + n.y * center_offset,
        0
      )

      # Floor of wall (bottom z) depends on vertical anchor.
      floor_z = case v_anchor
                when 'top'    then -wall_height
                when 'center' then -wall_height / 2.0
                else 0.0
                end
      ceiling_z = floor_z + wall_height

      # Project picked point (XY) onto centerline.
      click_xy = Geom::Point3d.new(picked_point.x, picked_point.y, 0)
      to_click = click_xy - cline_start
      t = to_click.dot(unit)
      n_offset = to_click.dot(n)
      clicked_side = n_offset >= 0 ? 1 : -1

      # Validate fit along wall length.
      half_w = @width / 2.0
      if t - half_w < 0 || t + half_w > wall_length
        UI.messagebox(
          "Door does not fit in wall.\n\n" \
          "Wall length: #{wall_length.round(2)}\"\n" \
          "Door width: #{@width}\"\n" \
          "Click position: #{t.round(2)}\" from wall start\n" \
          "Need at least #{half_w}\" from each end."
        )
        return
      end

      # Vertical positioning: door sits on the floor, raised by the threshold /
      # floor offset, and grows upward by its height.
      door_bot_z = floor_z + @floor_offset
      door_top_z = door_bot_z + @height
      if door_top_z > ceiling_z + 0.001
        UI.messagebox(
          "Door does not fit in wall height.\n\n" \
          "Floor offset (#{@floor_offset}\") + door height (#{@height}\") " \
          "exceeds wall height (#{wall_height}\")."
        )
        return
      end

      # cx/cy retained for the downstream door group transformation.
      n_side = clicked_side * (thickness / 2.0)
      cx = cline_start.x + unit.x * t + n.x * n_side
      cy = cline_start.y + unit.y * t + n.y * n_side
      ux = unit.x * half_w
      uy = unit.y * half_w
      fx = picked_point.x
      fy = picked_point.y
      outward = Geom::Vector3d.new(n.x * clicked_side, n.y * clicked_side, 0)

      model = Sketchup.active_model
      model.start_operation('Cut Door Opening', true)
      begin
        local_xform = wall_group.transformation.inverse
        local_picked = picked_point.transform(local_xform)
        local_outward = outward.transform(local_xform)

        # Step 1: prefer pick_helper's actual side face; fall back to a search.
        target_face = nil
        if picked_face && picked_face.valid? &&
           picked_face.parent == wall_group.entities.parent &&
           picked_face.normal.parallel?(local_outward)
          target_face = picked_face
        end
        target_face ||= wall_group.entities.grep(Sketchup::Face).find do |f|
          next false unless f.normal.parallel?(local_outward)
          proj = local_picked.project_to_plane(f.plane)
          next false unless local_picked.distance(proj) < 0.01
          f.classify_point(proj) == Sketchup::Face::PointInside
        end
        unless target_face
          model.abort_operation
          UI.messagebox("Could not identify a wall side face under the click.")
          return
        end

        # Step 2: build opening corners on target_face's exact plane.
        target_plane = target_face.plane
        local_corners = [
          Geom::Point3d.new(fx - ux, fy - uy, door_bot_z),
          Geom::Point3d.new(fx + ux, fy + uy, door_bot_z),
          Geom::Point3d.new(fx + ux, fy + uy, door_top_z),
          Geom::Point3d.new(fx - ux, fy - uy, door_top_z)
        ].map { |p| p.transform(local_xform).project_to_plane(target_plane) }
        ordered = clicked_side >= 0 ?
          [local_corners[0], local_corners[3], local_corners[2], local_corners[1]] :
          [local_corners[0], local_corners[1], local_corners[2], local_corners[3]]

        # Step 3: add 4 edges as a closed inner loop -> splits the face.
        new_edges = []
        4.times do |i|
          new_edges << wall_group.entities.add_line(ordered[i], ordered[(i + 1) % 4])
        end
        new_edges.each(&:find_faces)

        # Step 4: locate the resulting inner sub-face by its centroid.
        loop_center = Geom::Point3d.new(
          (ordered[0].x + ordered[2].x) / 2.0,
          (ordered[0].y + ordered[2].y) / 2.0,
          (ordered[0].z + ordered[2].z) / 2.0
        )
        new_face = wall_group.entities.grep(Sketchup::Face).find do |f|
          f.valid? &&
            f.normal.parallel?(local_outward) &&
            f.classify_point(loop_center) == Sketchup::Face::PointInside
        end
        unless new_face
          model.abort_operation
          UI.messagebox("Door opening loop did not yield an inner sub-face.")
          return
        end

        # Step 5: pushpull that exact face through the wall thickness.
        new_face.reverse! if new_face.normal.dot(local_outward) < 0
        sign = new_face.normal.dot(local_outward) > 0 ? -1 : 1
        new_face.pushpull(sign * thickness)

        model.commit_operation
        Sketchup.set_status_text(
          "Door opening cut. Click another wall or press Escape to exit.",
          SB_PROMPT
        )
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Error cutting opening: #{e.message}")
        puts "[DoorTool] cut error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        return
      end

      # Door group + attributes + wall back-link. Own operation so a failure
      # here cannot roll back the wall cut above.
      door_group = nil
      model.start_operation('Door Data', true)
      begin
        door_group = wall_group.parent.entities.add_group
        door_group.name = 'InteriorPro_Door'
        door_group.entities.add_cpoint(Geom::Point3d.new(0, 0, 0))
        door_group.transformation = Geom::Transformation.new(
          Geom::Point3d.new(cx, cy, (door_bot_z + door_top_z) / 2.0)
        )

        door_id      = generate_door_id
        host_wall_id = wall_group.get_attribute('InteriorPro', 'id')
        area_sqft    = (@width * @height) / 144.0

        door_group.set_attribute('InteriorPro', 'type',                   'door')
        door_group.set_attribute('InteriorPro', 'id',                     door_id)
        door_group.set_attribute('InteriorPro', 'mark',                   '')
        door_group.set_attribute('InteriorPro', 'door_type',              @door_type)
        door_group.set_attribute('InteriorPro', 'preset_name',            @preset_name)
        door_group.set_attribute('InteriorPro', 'width_in',               @width.to_f)
        door_group.set_attribute('InteriorPro', 'height_in',              @height.to_f)
        door_group.set_attribute('InteriorPro', 'frame_width_in',         @frame_width.to_f)
        door_group.set_attribute('InteriorPro', 'interior_depth_in',      @interior_depth.to_f)
        door_group.set_attribute('InteriorPro', 'floor_offset_in',        @floor_offset.to_f)
        door_group.set_attribute('InteriorPro', 'swing_direction',        @swing_direction)
        door_group.set_attribute('InteriorPro', 'swing_side',             @swing_side)
        door_group.set_attribute('InteriorPro', 'slide_direction',        @slide_direction)
        door_group.set_attribute('InteriorPro', 'handle_type',            @handle_type)
        door_group.set_attribute('InteriorPro', 'area_sqft',              area_sqft)
        door_group.set_attribute('InteriorPro', 'host_wall_id',           host_wall_id)
        door_group.set_attribute('InteriorPro', 'position_along_wall_in', t.to_f)
        door_group.set_attribute('InteriorPro', 'clicked_side',           clicked_side)
        door_group.set_attribute('InteriorPro', 'bottom_z',               door_bot_z.to_f)
        door_group.set_attribute('InteriorPro', 'top_z',                  door_top_z.to_f)
        door_group.set_attribute('InteriorPro', 'created_at',             Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
        door_group.set_attribute('InteriorPro', 'plugin_version',         '0.1')

        connected = (wall_group.get_attribute('InteriorPro', 'connected_doors') || []).dup
        connected << door_id
        wall_group.set_attribute('InteriorPro', 'connected_doors', connected)

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[DoorTool] door data error (cut succeeded): #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end

      # Build a real body for French Hinged only. Other types are opening + data
      # only for now. Own operation so a failure cannot roll back the cut/data.
      if @door_type == 'French Hinged' && door_group && door_group.valid?
        build_french_hinged_body(door_group, unit, n, thickness, clicked_side)
      end

      # Convert the door group into a ComponentInstance so each door is a
      # reusable, named definition. Own operation for the same isolation reason.
      if door_group && door_group.valid?
        model.start_operation('Door To Component', true)
        begin
          saved_attrs = {}
          dict = door_group.attribute_dictionary('InteriorPro', false)
          dict.each_pair { |k, v| saved_attrs[k] = v } if dict

          comp = door_group.to_component
          definition = comp.definition

          saved_attrs.each do |k, v|
            comp.set_attribute('InteriorPro', k, v)
          end

          d_id = saved_attrs['id'] || comp.get_attribute('InteriorPro', 'id')
          definition.name = "InteriorPro_Door_#{d_id}"
          comp.name = 'InteriorPro_Door'

          model.commit_operation
        rescue => e
          model.abort_operation rescue nil
          puts "[DoorTool] door to_component error (cut succeeded): #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        end
      end
    end

    # Builds a double French (glazed) door: a jamb ring around the opening plus
    # two glazed leaves hinged at the side jambs, swung open by SWING_ANGLE.
    def build_french_hinged_body(door_group, unit, n, thickness, clicked_side)
      model = Sketchup.active_model
      model.start_operation('Build French Hinged Body', true)
      begin
        frame_mat = get_or_create_material(model, 'InteriorPro_Door_Frame',
                                           Sketchup::Color.new(245, 245, 240), 1.0)
        glass_mat = get_or_create_material(model, 'InteriorPro_Glass',
                                           Sketchup::Color.new(180, 180, 180), 0.4)

        half_w = @width / 2.0
        half_h = @height / 2.0

        jamb_width = (@frame_width && @frame_width > 0) ? @frame_width : 1.5
        leaf_depth = 1.5

        # Jamb ring inner bounds (the clear opening the leaves fill).
        iw = half_w - jamb_width   # inner half-width
        ih = half_h - jamb_width   # inner half-height

        ents = door_group.entities

        # ---- Jamb: fixed frame ring around the opening, extruded past both
        # wall faces (front = outside, back = inside). Mirrors WindowTool jamb.
        jamb_front_out = 0.5
        jamb_back_in   = (@interior_depth && @interior_depth > 0) ? @interior_depth : 1.0
        jamb_outer_v   = clicked_side * jamb_front_out
        jamb_inner_v   = -clicked_side * (leaf_depth + jamb_back_in)

        jamb_grp = ents.add_group
        jamb_grp.name = 'Jamb'
        jents = jamb_grp.entities

        jamb_outer = [
          local_uvw(-half_w, jamb_outer_v, -half_h, unit, n),
          local_uvw( half_w, jamb_outer_v, -half_h, unit, n),
          local_uvw( half_w, jamb_outer_v,  half_h, unit, n),
          local_uvw(-half_w, jamb_outer_v,  half_h, unit, n)
        ]
        jamb_inner = [
          local_uvw(-iw, jamb_outer_v, -ih, unit, n),
          local_uvw( iw, jamb_outer_v, -ih, unit, n),
          local_uvw( iw, jamb_outer_v,  ih, unit, n),
          local_uvw(-iw, jamb_outer_v,  ih, unit, n)
        ]
        jamb_face = jents.add_face(jamb_outer)
        if jamb_face
          jamb_hole = jents.add_face(jamb_inner)
          jamb_hole.erase! if jamb_hole
          jamb_depth = jamb_inner_v - jamb_outer_v
          jamb_depth = -jamb_depth if jamb_face.normal.dot(n) < 0
          jamb_face.pushpull(jamb_depth)
          jamb_grp.material = frame_mat
        end

        # ---- Two leaves. Each fills half the inner opening, hinged at its
        # outer (jamb) edge and swung open about a vertical axis.
        meeting_gap = 0.125            # small gap at the meeting stiles
        leaf_front_v = -clicked_side * 0.0           # outer face of leaf at v = 0
        leaf_back_v  = -clicked_side * leaf_depth    # toward the inside

        # Resolve swing side: which n-direction the leaves open toward.
        #   inward/auto -> toward the room (-clicked_side), outward -> +clicked_side
        open_sign_n = (@swing_side == 'outward') ? clicked_side : -clicked_side
        angle = SWING_ANGLE

        # Left leaf: spans u in [-iw, -meeting_gap], hinged at u = -iw.
        left_leaf = build_leaf(ents, -iw, -meeting_gap, ih, leaf_front_v, leaf_back_v,
                               jamb_width, unit, n, clicked_side, frame_mat, glass_mat,
                               @handle_type, -meeting_gap, 'left')
        rotate_leaf(left_leaf, -iw, open_sign_n * angle, unit)

        # Right leaf: spans u in [meeting_gap, iw], hinged at u = iw.
        right_leaf = build_leaf(ents, meeting_gap, iw, ih, leaf_front_v, leaf_back_v,
                                jamb_width, unit, n, clicked_side, frame_mat, glass_mat,
                                @handle_type, meeting_gap, 'right')
        rotate_leaf(right_leaf, iw, -open_sign_n * angle, unit)

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[DoorTool] french hinged body error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # Builds one glazed leaf (frame ring + glass pane + optional handle) as its
    # own group, flat in the wall plane. Returns the group.
    def build_leaf(parent_ents, u0, u1, ih, vf, vb, stile_w, unit, n,
                   clicked_side, frame_mat, glass_mat, handle_type, handle_u, side)
      leaf = parent_ents.add_group
      leaf.name = "Leaf_#{side}"
      le = leaf.entities

      outer = [
        local_uvw(u0, vf, -ih, unit, n),
        local_uvw(u1, vf, -ih, unit, n),
        local_uvw(u1, vf,  ih, unit, n),
        local_uvw(u0, vf,  ih, unit, n)
      ]
      # Inner hole (glazed area) inset by the stile width.
      hu0 = u0 + stile_w
      hu1 = u1 - stile_w
      hh  = ih - stile_w
      inner = [
        local_uvw(hu0, vf, -hh, unit, n),
        local_uvw(hu1, vf, -hh, unit, n),
        local_uvw(hu1, vf,  hh, unit, n),
        local_uvw(hu0, vf,  hh, unit, n)
      ]
      face = le.add_face(outer)
      if face
        hole = le.add_face(inner)
        hole.erase! if hole
        depth = vb - vf
        depth = -depth if face.normal.dot(n) < 0
        face.pushpull(depth)
        leaf.material = frame_mat
      end

      # Glass pane at mid-depth, filling the inner hole.
      vmid = (vf + vb) / 2.0
      glass = [
        local_uvw(hu0, vmid, -hh, unit, n),
        local_uvw(hu1, vmid, -hh, unit, n),
        local_uvw(hu1, vmid,  hh, unit, n),
        local_uvw(hu0, vmid,  hh, unit, n)
      ]
      gface = le.add_face(glass)
      if gface
        gface.material = glass_mat
        gface.back_material = glass_mat
      end

      build_handle(le, handle_u, vb, unit, n, clicked_side, frame_mat, handle_type, side)
      leaf
    end

    # Small protruding handle on the interior face near the meeting stile.
    def build_handle(le, handle_u, vb, unit, n, clicked_side, mat, handle_type, side)
      return if handle_type == 'none'

      # Place slightly inboard of the meeting stile, at mid height.
      hu = handle_u - (side == 'left' ? 2.0 : -2.0)
      protrude = -clicked_side * 1.5
      v_face = vb                    # interior face of the leaf
      v_tip  = vb + protrude

      # Handle footprint varies by type.
      case handle_type
      when 'knob'
        du, dw = 1.0, 1.0
      when 'pull'
        du, dw = 0.75, 6.0
      else # 'lever'
        du, dw = 3.0, 0.75
      end

      # Build the handle in its OWN group. Its base face lands on v = vb, the
      # same plane as the leaf's back face. If drawn directly into the leaf's
      # entities (le), pushpull would merge the two coplanar faces and DELETE
      # the original face, so a later hface.material= would hit a deleted
      # element. A separate group has no coplanar neighbour to merge with, and
      # we set the material on the GROUP (always valid) rather than the face.
      hgrp = le.add_group
      hgrp.name = "Handle_#{side}"
      corners = [
        local_uvw(hu - du / 2.0, v_face, -dw / 2.0, unit, n),
        local_uvw(hu + du / 2.0, v_face, -dw / 2.0, unit, n),
        local_uvw(hu + du / 2.0, v_face,  dw / 2.0, unit, n),
        local_uvw(hu - du / 2.0, v_face,  dw / 2.0, unit, n)
      ]
      hface = hgrp.entities.add_face(corners)
      return unless hface
      depth = v_tip - v_face
      depth = -depth if hface.normal.dot(n) < 0
      hface.pushpull(depth)
      hgrp.material = mat
    end

    # Rotates a leaf group about a vertical axis at its hinge u-position.
    def rotate_leaf(leaf_group, hinge_u, angle, unit)
      return unless leaf_group && leaf_group.valid?
      hinge_pt = Geom::Point3d.new(hinge_u * unit.x, hinge_u * unit.y, 0)
      rot = Geom::Transformation.rotation(hinge_pt, Z_AXIS, angle)
      leaf_group.transformation = rot
    end

    def local_uvw(u, v, w, unit, n)
      Geom::Point3d.new(u * unit.x + v * n.x, u * unit.y + v * n.y, w)
    end

    def get_or_create_material(model, name, color, alpha = 1.0)
      mat = model.materials[name]
      if mat.nil?
        mat = model.materials.add(name)
        mat.color = color
        mat.alpha = alpha
      end
      mat
    end

    def parse_anchor(anchor)
      if anchor == 'center'
        ['center', 'center']
      else
        parts = anchor.split('-')
        [parts[0] || 'bottom', parts[1] || 'center']
      end
    end

    def generate_door_id
      require 'securerandom'
      SecureRandom.uuid
    rescue StandardError
      "door-#{Time.now.to_f}-#{rand(1_000_000)}"
    end

    SWING_ANGLE = 35.degrees

  end
end

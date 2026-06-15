# Interior Pro - Window Tool (Step 2: cuts opening through wall, no body yet)

module InteriorPro
  class WindowTool

    attr_accessor :window_type, :width, :height, :header_height,
                  :frame_width, :install_window, :exterior_trim,
                  :interior_casing, :preset_name, :interior_depth

    def initialize
      @window_type = 'Single Hung'
      @width = 36.0
      @height = 48.0
      @header_height = 80.0
      @frame_width = 1.5
      @interior_depth = 1.0
      @install_window = true
      @exterior_trim = false
      @interior_casing = false
      @preset_name = ''
    end

    def activate
      Sketchup.set_status_text(
        "Window Tool: hover over a wall and click to cut opening. Press Escape to exit.",
        SB_PROMPT
      )
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      wall, _ = find_wall_under_cursor(view, x, y)
      view.tooltip = wall ? "Click to place #{@width}\" x #{@height}\" window opening" : ''
    end

    def onLButtonDown(flags, x, y, view)
      wall, picked_point, picked_face = find_wall_under_cursor(view, x, y)
      unless wall
        Sketchup.set_status_text("No wall under cursor. Hover over a wall to place a window.", SB_PROMPT)
        return
      end
      cut_window_opening(wall, picked_point, picked_face)
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

    def cut_window_opening(wall_group, picked_point, picked_face = nil)
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

      # Adjust drawn line to true centerline based on horizontal anchor.
      # build_wall_group offsets the drawn line by +n*thickness (left) or -n*thickness (right).
      # So centerline = drawn_line + n*(thickness/2 for left, -thickness/2 for right, 0 for center).
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
      puts "[WindowTool] clicked_side=#{clicked_side} n_offset=#{n_offset.round(4)} pp=(#{picked_point.x.round(3)}, #{picked_point.y.round(3)}, #{picked_point.z.round(3)}) unit=(#{unit.x.round(4)}, #{unit.y.round(4)}) n=(#{n.x.round(4)}, #{n.y.round(4)})"

      # Validate fit along wall length.
      half_w = @width / 2.0
      if t - half_w < 0 || t + half_w > wall_length
        UI.messagebox(
          "Window does not fit in wall.\n\n" \
          "Wall length: #{wall_length.round(2)}\"\n" \
          "Window width: #{@width}\"\n" \
          "Click position: #{t.round(2)}\" from wall start\n" \
          "Need at least #{half_w}\" from each end."
        )
        return
      end

      # Vertical positioning: header_height measured from wall floor.
      win_top_z = floor_z + @header_height
      win_bot_z = win_top_z - @height
      if win_top_z > ceiling_z + 0.001
        UI.messagebox("Window top (#{@header_height}\" from floor) exceeds wall height (#{wall_height}\").")
        return
      end
      if win_bot_z < floor_z - 0.001
        UI.messagebox(
          "Window bottom is below floor.\n\n" \
          "Header Height (#{@header_height}\") must be at least Window Height (#{@height}\")."
        )
        return
      end

      # cx/cy retained for the downstream placeholder group transformation.
      n_side = clicked_side * (thickness / 2.0)
      cx = cline_start.x + unit.x * t + n.x * n_side
      cy = cline_start.y + unit.y * t + n.y * n_side
      ux = unit.x * half_w
      uy = unit.y * half_w
      fx = picked_point.x
      fy = picked_point.y
      outward = Geom::Vector3d.new(n.x * clicked_side, n.y * clicked_side, 0)

      model = Sketchup.active_model
      model.start_operation('Cut Window Opening', true)
      begin
        local_xform = wall_group.transformation.inverse
        local_picked = picked_point.transform(local_xform)
        local_outward = outward.transform(local_xform)

        # Step 1: Use pick_helper's actual face when it is a wall side face;
        # only fall back to entities-search if pick_helper gave us something
        # else (top/end face, edge pick, or no face at all).
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

        # Step 2: Build opening corners on target_face's exact plane.
        target_plane = target_face.plane
        local_corners = [
          Geom::Point3d.new(fx - ux, fy - uy, win_bot_z),
          Geom::Point3d.new(fx + ux, fy + uy, win_bot_z),
          Geom::Point3d.new(fx + ux, fy + uy, win_top_z),
          Geom::Point3d.new(fx - ux, fy - uy, win_top_z)
        ].map { |p| p.transform(local_xform).project_to_plane(target_plane) }
        ordered = clicked_side >= 0 ?
          [local_corners[0], local_corners[3], local_corners[2], local_corners[1]] :
          [local_corners[0], local_corners[1], local_corners[2], local_corners[3]]

        # Step 3: Add 4 edges as a closed inner loop on target_face. A closed
        # coplanar loop interior to a face deterministically splits the face
        # into a remainder + the inner sub-face. No add_face, no merge.
        new_edges = []
        4.times do |i|
          new_edges << wall_group.entities.add_line(ordered[i], ordered[(i + 1) % 4])
        end
        # Force SketchUp to find/create the new face from the closed loop of edges
        new_edges.each(&:find_faces)

        # Step 4: Locate the resulting inner sub-face (the window) by
        # classify_point on the loop's centroid.
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
          UI.messagebox("Window opening loop did not yield an inner sub-face.")
          return
        end

        # Step 5: Pushpull that exact face through the wall thickness.
        new_face.reverse! if new_face.normal.dot(local_outward) < 0
        sign = new_face.normal.dot(local_outward) > 0 ? -1 : 1
        new_face.pushpull(sign * thickness)
        puts "[WindowTool] xform=#{wall_group.transformation.to_a.map{|v|v.round(3)}} target_face=#{target_face.valid? ? target_face.entityID : 'DELETED'} new_face=#{new_face.valid? ? new_face.entityID : 'INVALID'} normal=#{new_face.valid? ? new_face.normal.to_a.map{|v|v.round(4)} : 'INVALID'} outward=(#{outward.x.round(4)},#{outward.y.round(4)},#{outward.z.round(4)}) sign=#{sign}"

        model.commit_operation
        Sketchup.set_status_text(
          "Window opening cut. Click another wall or press Escape to exit.",
          SB_PROMPT
        )
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Error cutting opening: #{e.message}")
        puts "[WindowTool] cut error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        return
      end

      # Placeholder window group + attributes + wall back-link. Wrapped in its
      # own operation so a failure here cannot roll back the wall cut above.
      model.start_operation('Window Data', true)
      begin
        window_group = wall_group.parent.entities.add_group
        window_group.name = 'InteriorPro_Window'
        window_group.entities.add_cpoint(Geom::Point3d.new(0, 0, 0))
        window_group.transformation = Geom::Transformation.new(
          Geom::Point3d.new(cx, cy, (win_bot_z + win_top_z) / 2.0)
        )

        window_id      = generate_window_id
        host_wall_id   = wall_group.get_attribute('InteriorPro', 'id')
        sill_height_in = @header_height - @height
        area_sqft      = (@width * @height) / 144.0

        window_group.set_attribute('InteriorPro', 'type',                   'window')
        window_group.set_attribute('InteriorPro', 'id',                     window_id)
        window_group.set_attribute('InteriorPro', 'mark',                   '')
        window_group.set_attribute('InteriorPro', 'window_type',            @window_type)
        window_group.set_attribute('InteriorPro', 'preset_name',            @preset_name)
        window_group.set_attribute('InteriorPro', 'width_in',               @width.to_f)
        window_group.set_attribute('InteriorPro', 'height_in',              @height.to_f)
        window_group.set_attribute('InteriorPro', 'frame_width_in',         @frame_width.to_f)
        window_group.set_attribute('InteriorPro', 'interior_depth_in',      @interior_depth.to_f)
        window_group.set_attribute('InteriorPro', 'header_height_in',       @header_height.to_f)
        window_group.set_attribute('InteriorPro', 'sill_height_in',         sill_height_in.to_f)
        window_group.set_attribute('InteriorPro', 'area_sqft',              area_sqft)
        window_group.set_attribute('InteriorPro', 'host_wall_id',           host_wall_id)
        window_group.set_attribute('InteriorPro', 'position_along_wall_in', t.to_f)
        window_group.set_attribute('InteriorPro', 'clicked_side',           clicked_side)
        window_group.set_attribute('InteriorPro', 'bottom_z',               win_bot_z.to_f)
        window_group.set_attribute('InteriorPro', 'top_z',                  win_top_z.to_f)
        window_group.set_attribute('InteriorPro', 'created_at',             Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
        window_group.set_attribute('InteriorPro', 'plugin_version',         '0.1')

        connected = (wall_group.get_attribute('InteriorPro', 'connected_windows') || []).dup
        connected << window_id
        wall_group.set_attribute('InteriorPro', 'connected_windows', connected)

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowTool] window data error (cut succeeded): #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end

      # Build a real window body for supported types. Wrapped in its own
      # operation so a failure here cannot roll back the wall cut or the
      # window_group data above.
      if @window_type == 'Casement' && window_group && window_group.valid?
        build_casement_body(window_group, unit, n, thickness, clicked_side)
      end

      # Convert the window group into a ComponentInstance so each window is a
      # reusable, named definition. Wrapped in its own operation so a failure
      # here cannot roll back the wall cut, the window_group data, or the body.
      if window_group && window_group.valid?
        model.start_operation('Window To Component', true)
        begin
          # Snapshot every InteriorPro attribute before the conversion, since
          # to_component is not guaranteed to carry the instance dictionary
          # over to the new ComponentInstance.
          saved_attrs = {}
          dict = window_group.attribute_dictionary('InteriorPro', false)
          dict.each_pair { |k, v| saved_attrs[k] = v } if dict

          comp = window_group.to_component
          definition = comp.definition

          # Re-apply any attributes the conversion may have dropped, so
          # type='window' and host_wall_id (and the rest) live on the instance.
          saved_attrs.each do |k, v|
            comp.set_attribute('InteriorPro', k, v)
          end

          win_id = saved_attrs['id'] || comp.get_attribute('InteriorPro', 'id')
          definition.name = "InteriorPro_Window_#{win_id}"
          comp.name = 'InteriorPro_Window'

          model.commit_operation
        rescue => e
          model.abort_operation rescue nil
          puts "[WindowTool] window to_component error (cut succeeded): #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        end
      end
    end

    def build_casement_body(window_group, unit, n, thickness, clicked_side)
      model = Sketchup.active_model
      model.start_operation('Build Casement Body', true)
      begin
        frame_mat = get_or_create_material(model, 'InteriorPro_Window_Frame',
                                           Sketchup::Color.new(255, 255, 255), 1.0)
        glass_mat = get_or_create_material(model, 'InteriorPro_Glass',
                                           Sketchup::Color.new(180, 180, 180), 0.4)

        half_w = @width / 2.0
        half_h = @height / 2.0

        # Profile widths (in the plane of the wall) and the air gap between the
        # fixed jamb and the operable sash.
        jamb_width = 1.0
        gap        = 0.0
        sash_width = 1.0

        # Half-extents from the opening edge inward, along u (width) and w (height).
        jo_w = half_w;                     jo_h = half_h                     # jamb outer = opening edge
        ji_w = half_w - jamb_width;        ji_h = half_h - jamb_width        # jamb inner
        so_w = half_w - jamb_width - gap;  so_h = half_h - jamb_width - gap   # sash outer
        si_w = so_w - sash_width;          si_h = so_h - sash_width           # sash inner = glass bound

        # Depths along n. window_group origin sits on the OUTER wall face (v=0);
        # inward (toward the room) is -clicked_side, outward is +clicked_side.
        sash_depth     = 2.0   # sash front at v=0, back at v = -clicked_side * sash_depth
        jamb_front_out = 0.5   # jamb sticks out this far past the sash front (toward outside)
        jamb_back_in   = (@interior_depth && @interior_depth > 0) ? @interior_depth : 1.0   # jamb extends this far past the sash back (toward inside)
        jamb_back  = clicked_side * jamb_front_out                # outer jamb edge (face built here)
        jamb_front = -clicked_side * (sash_depth + jamb_back_in)  # inner jamb edge
        sash_back  = 0.0                               # at the outer face
        sash_front = -clicked_side * 2.0               # 2" deep
        glass_v    = -clicked_side * 1.0               # mid-depth of the sash

        ents = window_group.entities

        # Jamb: fixed outer frame ring (opening edge -> jamb inner bound),
        # extruded past BOTH wall faces.
        jamb_grp = ents.add_group
        jamb_grp.name = 'Jamb'
        jents = jamb_grp.entities

        jamb_outer = [
          local_uvw(-jo_w, jamb_back, -jo_h, unit, n),
          local_uvw( jo_w, jamb_back, -jo_h, unit, n),
          local_uvw( jo_w, jamb_back,  jo_h, unit, n),
          local_uvw(-jo_w, jamb_back,  jo_h, unit, n)
        ]
        jamb_inner = [
          local_uvw(-ji_w, jamb_back, -ji_h, unit, n),
          local_uvw( ji_w, jamb_back, -ji_h, unit, n),
          local_uvw( ji_w, jamb_back,  ji_h, unit, n),
          local_uvw(-ji_w, jamb_back,  ji_h, unit, n)
        ]

        jamb_face = jents.add_face(jamb_outer)
        if jamb_face
          # Add the inner loop, erase the inner face -> ring with a hole.
          jamb_hole = jents.add_face(jamb_inner)
          jamb_hole.erase! if jamb_hole
          # Extrude with the same n-based sign correction so it grows toward +v.
          jamb_depth = jamb_front - jamb_back
          jamb_depth = -jamb_depth if jamb_face.normal.dot(n) < 0
          jamb_face.pushpull(jamb_depth)
          jamb_grp.material = frame_mat
        end

        # Sash: operable inner frame ring (sash outer -> sash inner bound),
        # 2" deep starting at the outer face.
        sash_grp = ents.add_group
        sash_grp.name = 'Sash'
        sents = sash_grp.entities

        sash_outer = [
          local_uvw(-so_w, sash_back, -so_h, unit, n),
          local_uvw( so_w, sash_back, -so_h, unit, n),
          local_uvw( so_w, sash_back,  so_h, unit, n),
          local_uvw(-so_w, sash_back,  so_h, unit, n)
        ]
        sash_inner = [
          local_uvw(-si_w, sash_back, -si_h, unit, n),
          local_uvw( si_w, sash_back, -si_h, unit, n),
          local_uvw( si_w, sash_back,  si_h, unit, n),
          local_uvw(-si_w, sash_back,  si_h, unit, n)
        ]

        sash_face = sents.add_face(sash_outer)
        if sash_face
          sash_hole = sents.add_face(sash_inner)
          sash_hole.erase! if sash_hole
          sash_depth = sash_front - sash_back
          sash_depth = -sash_depth if sash_face.normal.dot(n) < 0
          sash_face.pushpull(sash_depth)
          sash_grp.material = frame_mat
        end

        # Glass pane: single thin face at the sash inner bound, mid-sash depth.
        glass_corners = [
          local_uvw(-si_w, glass_v, -si_h, unit, n),
          local_uvw( si_w, glass_v, -si_h, unit, n),
          local_uvw( si_w, glass_v,  si_h, unit, n),
          local_uvw(-si_w, glass_v,  si_h, unit, n)
        ]
        glass_face = ents.add_face(glass_corners)
        if glass_face
          glass_face.material = glass_mat
          glass_face.back_material = glass_mat
        end

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowTool] casement body error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    def add_frame_box(parent_entities, u1, u2, v1, v2, w1, w2, unit, n, material, name)
      grp = parent_entities.add_group
      grp.name = name
      corners = [
        local_uvw(u1, v1, w1, unit, n),
        local_uvw(u2, v1, w1, unit, n),
        local_uvw(u2, v2, w1, unit, n),
        local_uvw(u1, v2, w1, unit, n)
      ]
      face = grp.entities.add_face(corners)
      return grp unless face
      face.reverse! if face.normal.z < 0
      face.pushpull(w2 - w1)
      grp.material = material
      grp
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

    def generate_window_id
      require 'securerandom'
      SecureRandom.uuid
    rescue StandardError
      "window-#{Time.now.to_f}-#{rand(1_000_000)}"
    end

  end
end

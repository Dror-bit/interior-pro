# Interior Pro - Window Tool (Step 2: cuts opening through wall, no body yet)

module InteriorPro
  class WindowTool

    attr_accessor :window_type, :width, :height, :header_height,
                  :frame_width, :install_window, :exterior_trim,
                  :interior_casing, :preset_name, :interior_depth, :garden_depth,
                  :glass_grid_style, :exterior_casing_style, :interior_casing_style,
                  :arch_rise

    def initialize
      @window_type = 'Single Hung'
      @glass_grid_style = 'none'
      @width = 36.0
      @height = 48.0
      @header_height = 80.0
      @frame_width = 1.5
      @interior_depth = 1.0
      @install_window = true
      @exterior_trim = false
      @interior_casing = false
      @exterior_casing_style = 'none'
      @interior_casing_style = 'none'
      @preset_name = ''
      @garden_depth = 16.0
      @arch_rise = 0.0
    end

    # Effective arch rise for THIS window. Arched only for the 'Arched' type;
    # every other type stays perfectly rectangular. Rise defaults to a clean
    # semicircle (half the width) when the user leaves it blank, and is clamped
    # to [0, half-width] and to leave at least 6" of straight glass below.
    def effective_arch_rise
      return 0.0 unless @window_type.to_s == 'Arched'
      hw = @width / 2.0
      rise = @arch_rise.to_f
      rise = hw if rise <= 0.0
      rise = hw if rise > hw
      max_by_height = [@height.to_f - 6.0, 0.0].max
      rise = max_by_height if rise > max_by_height
      rise
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
      wall, pt, _face = find_wall_under_cursor(view, x, y)
      if wall && pt
        geo = InteriorPro::DoorManager.wall_geometry(wall)
        if geo
          # Project the picked FACE point onto the centerline — exactly how
          # cut_window_opening computes t — so the ghost matches the placement.
          click = Geom::Point3d.new(pt.x, pt.y, 0)
          @preview_wall = wall
          @preview_geo  = geo
          @preview_t    = (click - geo[:cline_start]).dot(geo[:unit])
          view.tooltip = "Click to place #{@width}\" x #{@height}\" window opening"
        end
      else
        @preview_wall = @preview_geo = @preview_t = nil
        view.tooltip = ''
      end
      view.invalidate
    end

    def draw(view)
      return unless @preview_wall && @preview_geo && @preview_t
      corners = preview_ghost_corners(@preview_wall, @preview_geo, @preview_t)
      return unless corners
      half_w = @width / 2.0
      valid = @preview_t - half_w >= 0 && @preview_t + half_w <= @preview_geo[:wall_length]
      front = corners[0, 4]
      back  = corners[4, 4]
      view.line_width = 3
      view.drawing_color = valid ? Sketchup::Color.new(40, 150, 60) : Sketchup::Color.new(200, 40, 40)
      view.draw(GL_LINE_LOOP, front)
      view.draw(GL_LINE_LOOP, back)
      4.times { |i| view.draw(GL_LINES, [front[i], back[i]]) }
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@preview_wall.bounds) if @preview_wall&.valid?
      if @preview_wall && @preview_geo && @preview_t
        c = preview_ghost_corners(@preview_wall, @preview_geo, @preview_t)
        c&.each { |p| bb.add(p) }
      end
      bb
    end

    def preview_ghost_corners(wall, geo, t)
      return nil unless t
      tool = InteriorPro::DoorTool.new
      sill = @header_height - @height
      data = tool.build_opening_data(wall, geo, width: @width, height: @height,
                                     floor_offset: sill, t: t, clicked_side: 1)
      tool.opening_ghost_corners(data)
    rescue StandardError => e
      puts "[WindowTool] preview error: #{e.message}"
      nil
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
      # Levels (2026-08-03): a lifted wall (level 2 / dropped garage) carries
      # its height in the group TRANSFORMATION. The opening cut is local and
      # follows by itself - the window BODY must be lifted explicitly.
      wall_z = wall_group.transformation.origin.z.to_f

      # Project picked point (XY) onto centerline.
      click_xy = Geom::Point3d.new(picked_point.x, picked_point.y, 0)

      # CURVED WALLS (2026-08-11): a curved wall is not a straight ruler.
      # Measure the click ALONG the curve, then swing the local frame round
      # to the flat panel this window will sit in - exactly what doors do.
      # A straight wall goes through none of this.
      wall_sag = 0.0
      curved = false
      begin
        if defined?(InteriorPro::WallTool) && InteriorPro::WallTool.curved_wall?(wall_group)
          wall_sag = InteriorPro::WallTool.wall_sag(wall_group)
          arc = InteriorPro::ArcMath.from_chord_and_sag(drawn_start.x, drawn_start.y,
                                                        drawn_end.x, drawn_end.y, wall_sag)
          if arc
            curved = true
            wall_length = InteriorPro::ArcMath.length(arc)
          end
        end
      rescue StandardError => e
        puts "[WindowTool] curve check: #{e.message}"
      end

      if curved
        t = InteriorPro::WallTool.t_from_point_xy(drawn_start.x, drawn_start.y,
                                                  drawn_end.x, drawn_end.y,
                                                  wall_sag, click_xy.x, click_xy.y)
        t = (click_xy - cline_start).dot(unit) if t.nil?
        pk = InteriorPro::WallTool.opening_pocket(drawn_start.x, drawn_start.y,
                                                  drawn_end.x, drawn_end.y,
                                                  wall_sag, t, @width)
        if pk
          unit = Geom::Vector3d.new(pk[:dir][0], pk[:dir][1], 0)
          n = Geom::Vector3d.new(-unit.y, unit.x, 0)
          cline_start = Geom::Point3d.new(pk[:center][0] - unit.x * t,
                                          pk[:center][1] - unit.y * t, 0)
        end
      else
        t = (click_xy - cline_start).dot(unit)
      end

      to_click = click_xy - cline_start
      n_offset = to_click.dot(n)
      # Always orient the window exterior-out, regardless of which side was
      # clicked: the wall's exterior face is the right perpendicular of the drawn
      # direction (= the -n side, same convention the wall material uses). So the
      # window exterior always lands on the wall exterior, interior on interior.
      click_side_raw = n_offset >= 0 ? 1 : -1
      clicked_side = -1
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

      # NATIVE: register the window as a raised opening (floor_offset = sill) in
      # the wall's shared openings list and rebuild the wall from data. Same
      # mechanism as doors — no direct cut, no boolean. The opening now survives
      # every wall rebuild, and a wall can hold both doors and windows.
      model = Sketchup.active_model
      sill_offset = @header_height - @height
      arch_rise = effective_arch_rise
      model.start_operation('Cut Window Opening', true)
      begin
        InteriorPro::WallTool.append_door_opening!(
          wall_group,
          { t: t, width: @width, height: @height, floor_offset: sill_offset, arch_rise: arch_rise }
        ) || (raise 'Failed to append window opening')
        InteriorPro::WallTool.rebuild_wall_native!(wall_group) ||
          (raise 'Native wall rebuild failed')
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
          Geom::Point3d.new(cx, cy, wall_z + (win_bot_z + win_top_z) / 2.0)
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
        window_group.set_attribute('InteriorPro', 'garden_depth_in',        @garden_depth.to_f)
        window_group.set_attribute('InteriorPro', 'glass_grid_style',        @glass_grid_style.to_s)
        window_group.set_attribute('InteriorPro', 'exterior_casing_style',  @exterior_casing_style.to_s)
        window_group.set_attribute('InteriorPro', 'interior_casing_style',  @interior_casing_style.to_s)
        window_group.set_attribute('InteriorPro', 'header_height_in',       @header_height.to_f)
        window_group.set_attribute('InteriorPro', 'arch_rise_in',           arch_rise.to_f)
        window_group.set_attribute('InteriorPro', 'sill_height_in',         sill_height_in.to_f)
        window_group.set_attribute('InteriorPro', 'area_sqft',              area_sqft)
        window_group.set_attribute('InteriorPro', 'host_wall_id',           host_wall_id)
        window_group.set_attribute('InteriorPro', 'position_along_wall_in', t.to_f)
        window_group.set_attribute('InteriorPro', 'clicked_side',           clicked_side)
        window_group.set_attribute('InteriorPro', 'bottom_z',               (wall_z + win_bot_z).to_f)
        window_group.set_attribute('InteriorPro', 'top_z',                  (wall_z + win_top_z).to_f)
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

      # Build a window body for ALL types so every window is visible. For now
      # this is a generic frame + glass body (the casement builder); per-style
      # details (rails, mullions, operable sash) are refined per type later.
      # Wrapped in its own operation so a failure here cannot roll back the wall
      # cut or the window_group data above.
      if window_group && window_group.valid?
        if arch_rise > 0.01
          build_arched_body(window_group, unit, n, thickness, clicked_side, arch_rise)
        elsif @window_type == 'Garden Window'
          build_garden_body(window_group, unit, n, thickness, clicked_side)
        else
          build_casement_body(window_group, unit, n, thickness, clicked_side)
        end
      end

      # Picture-frame casing (4 sides) on each wall face, same catalog as
      # doors. Own operation so a failure cannot roll back the cut/body.
      if window_group && window_group.valid? &&
         (casing_enabled?(@exterior_casing_style) || casing_enabled?(@interior_casing_style))
        model.start_operation('Window Casing', true)
        begin
          frame_mat = get_or_create_material(model, 'InteriorPro_Window_Frame',
                                             Sketchup::Color.new(255, 255, 255), 1.0)
          half_w = @width / 2.0
          half_h = @height / 2.0
          if casing_enabled?(@exterior_casing_style)
            build_window_casing!(window_group.entities, half_w, half_h,
                                 @exterior_casing_style, 0.0, clicked_side,
                                 unit, n, frame_mat, 'Casing_Exterior')
          end
          if casing_enabled?(@interior_casing_style)
            build_window_casing!(window_group.entities, half_w, half_h,
                                 @interior_casing_style, -clicked_side * thickness,
                                 -clicked_side, unit, n, frame_mat, 'Casing_Interior')
          end
          model.commit_operation
        rescue => e
          model.abort_operation rescue nil
          puts "[WindowTool] casing error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        end
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
          InteriorPro.assign_tag(comp, 'IP/Windows')

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

        # Sliders: panels sit side by side on OFFSET depth tracks (so they pass
        # each other) with a small interlock overlap. Other types tile the
        # interior into a cols x rows grid of sash + glass panes.
        cols, rows = window_grid(@window_type)
        if @window_type == 'XOX Single Hung'
          build_xox_hung_panes(ents, so_w, so_h, sash_width,
                               sash_back, sash_front, glass_v, clicked_side,
                               unit, n, frame_mat, glass_mat)
        elsif ['Slider XO', 'Slider XOX'].include?(@window_type)
          build_slider_panes(ents, cols, so_w, so_h, sash_width,
                             clicked_side, unit, n, frame_mat, glass_mat)
        elsif ['Single Hung', 'Single Hung XL', 'Double Hung'].include?(@window_type)
          build_hung_panes(ents, rows, so_w, so_h, sash_width,
                           clicked_side, unit, n, frame_mat, glass_mat)
        else
          # Casement XX etc.: two hinged sashes with a thin ~1/8" gap between them.
          build_grid_panes(ents, cols, rows, so_w, so_h, sash_width,
                           sash_back, sash_front, glass_v, unit, n, frame_mat, glass_mat, 0.0625)
        end

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowTool] casement body error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # Arched window: frame ring + glass + colonial grid, all following a circular
    # arch across the top. Rectangular below the springline; the top is a smooth
    # arc (semicircle when rise == half the width). Built to match the arched
    # wall hole (same circle) so the frame sits flush in the opening.
    def build_arched_body(window_group, unit, n, thickness, clicked_side, rise)
      model = Sketchup.active_model
      model.start_operation('Build Arched Window', true)
      begin
        frame_mat = get_or_create_material(model, 'InteriorPro_Window_Frame',
                                           Sketchup::Color.new(255, 255, 255), 1.0)
        glass_mat = get_or_create_material(model, 'InteriorPro_Glass',
                                           Sketchup::Color.new(180, 180, 180), 0.4)

        half_w = @width / 2.0
        half_h = @height / 2.0
        fw = (@frame_width && @frame_width > 1.0) ? @frame_width : 1.5   # frame face width in-plane
        rise = [[rise, 0.01].max, half_w].min

        # Outer arch circle (matches the wall hole): apex at +half_h, center on u=0.
        r_out = (half_w * half_w + rise * rise) / (2.0 * rise)
        cw = half_h - r_out
        r_in = r_out - fw                                # inner (glass) arch, concentric

        ents = window_group.entities

        # Depths along n (same convention as build_casement_body).
        jamb_front_out = 0.5
        jamb_back_in   = (@interior_depth && @interior_depth > 0) ? @interior_depth : 1.0
        jamb_back  = clicked_side * jamb_front_out
        jamb_front = -clicked_side * (2.0 + jamb_back_in)
        glass_v    = -clicked_side * 1.0

        # --- Frame ring (jamb): outer arch minus inner arch, extruded through wall.
        outer = arch_outline_uvw(half_w,      -half_h,      cw, r_out, jamb_back, unit, n)
        inner = arch_outline_uvw(half_w - fw, -half_h + fw, cw, r_in,  jamb_back, unit, n)
        jamb_grp = ents.add_group
        jamb_grp.name = 'Jamb'
        of = jamb_grp.entities.add_face(outer)
        if of
          ih = jamb_grp.entities.add_face(inner)
          ih.erase! if ih
          depth = jamb_front - jamb_back
          depth = -depth if of.normal.dot(n) < 0
          of.pushpull(depth)
          jamb_grp.material = frame_mat
        end

        # --- Glass: single arched pane at mid-depth (inner outline), 1/4" thick.
        glass_pts = arch_outline_uvw(half_w - fw, -half_h + fw, cw, r_in, glass_v - 0.125, unit, n)
        gg = ents.add_group
        gg.name = 'Glass'
        gf = gg.entities.add_face(glass_pts)
        if gf
          dd = 0.25
          dd = -dd if gf.normal.dot(n) < 0
          gf.pushpull(dd)
          gg.material = glass_mat
        end

        # --- Colonial grid: vertical mullions (up to the arch) + horizontal rails
        # (straight part only), driven by @glass_grid_style. Always at least a
        # central vertical mullion so the arched top reads like the reference.
        build_arched_grid(ents, half_w - fw, -half_h + fw, cw, r_in, glass_v, unit, n, frame_mat)

        # Smooth the faceted arch surfaces (the reveal) so the segment lines
        # disappear and it reads as one clean curve. soften_casing_edges only
        # softens edges whose two faces meet at a shallow angle (< 50°), so the
        # crisp 90° frame outline and corners stay sharp. Safe here — these are
        # decorative body groups, not the wall solid.
        soften_casing_edges(jamb_grp.entities) if jamb_grp&.valid?
        soften_casing_edges(gg.entities) if gg&.valid?

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowTool] arched body error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # Closed arched outline as world points at depth v: rectangle sides + a
    # circular top on the circle (center u=0, height cw, radius rr). 48 segments
    # so the arc reads smooth.
    def arch_outline_uvw(u_edge, w_bottom, cw, rr, v, unit, n, segs = 48)
      ws = cw + Math.sqrt([rr * rr - u_edge * u_edge, 0.0].max)   # springline w
      th_r = Math.atan2(ws - cw, u_edge)
      th_l = Math::PI - th_r
      pts = [local_uvw(-u_edge, v, w_bottom, unit, n), local_uvw(u_edge, v, w_bottom, unit, n)]
      (0..segs).each do |i|
        th = th_r + (th_l - th_r) * i / segs.to_f
        u = rr * Math.cos(th)
        w = cw + rr * Math.sin(th)
        pts << local_uvw(u, v, w, unit, n)
      end
      pts
    end

    # Grid over the arched glass: vertical bars stop where they meet the inner
    # arch; horizontal rails run across the straight (below-springline) part only.
    def build_arched_grid(ents, u_edge, w_bottom, cw, r_in, glass_v, unit, n, mat)
      cols, rows = parse_window_grid(@glass_grid_style)
      cols = 2 if cols < 2                       # always a central mullion
      mw = 0.375
      hd = 0.1
      grp = ents.add_group
      grp.name = 'Grid'
      ge = grp.entities

      (1...cols).each do |i|
        u = -u_edge + (2.0 * u_edge) * i / cols.to_f
        top_w = cw + Math.sqrt([r_in * r_in - u * u, 0.0].max)   # meets inner arch
        add_muntin_bar(ge, u - mw / 2.0, u + mw / 2.0, w_bottom, top_w, glass_v, hd, unit, n)
      end

      ws_in = cw + Math.sqrt([r_in * r_in - u_edge * u_edge, 0.0].max)   # inner springline
      straight_h = ws_in - w_bottom
      (1...rows).each do |j|
        w = w_bottom + straight_h * j / rows.to_f
        add_muntin_bar(ge, -u_edge, u_edge, w - mw / 2.0, w + mw / 2.0, glass_v, hd, unit, n)
      end
      grp.material = mat
    end

    # Garden window: a small glass box that projects OUTWARD from the wall
    # (front + two trapezoid sides + a slanted top + a bottom shelf). The
    # rectangular hole is cut in the wall as usual; this body sits proud of the
    # exterior face (exterior = negative v, i.e. clicked_side direction).
    def build_garden_body(window_group, unit, n, thickness, clicked_side)
      model = Sketchup.active_model
      model.start_operation('Build Garden Window', true)
      begin
        glass_mat = get_or_create_material(model, 'InteriorPro_Glass',
                                           Sketchup::Color.new(180, 180, 180), 0.4)
        shelf_mat = get_or_create_material(model, 'InteriorPro_Window_Shelf',
                                           Sketchup::Color.new(205, 175, 130), 1.0)
        frame_mat = get_or_create_material(model, 'InteriorPro_Window_Frame',
                                           Sketchup::Color.new(255, 255, 255), 1.0)

        hw = @width / 2.0
        hh = @height / 2.0
        proj = (@garden_depth && @garden_depth > 0) ? @garden_depth : (@width * 0.5)
        out = clicked_side * proj             # projection depth, toward exterior
        front_top = hh - @height * 0.15       # gently sloped top (front a bit lower)

        grp = window_group.entities.add_group
        grp.name = 'GardenWindow'
        ge = grp.entities

        # Each panel: a UNIFORM 2" frame ring with real depth (pushed INWARD into
        # the box) + glass recessed 1/8" behind the outer face.
        glass = lambda do |quad|
          inner = inset_quad_uvw(quad, 2.0)
          box_c = [0.0, out / 2.0, (front_top - hh) / 2.0]
          inw = panel_inward_uvw(quad, box_c)
          wi = Geom::Vector3d.new(inw[0] * unit.x + inw[1] * n.x,
                                  inw[0] * unit.y + inw[1] * n.y, inw[2])
          fgrp = ge.add_group
          fgrp.name = 'Frame'
          of = fgrp.entities.add_face(quad.map { |u, v, w| local_uvw(u, v, w, unit, n) })
          if of
            ih = fgrp.entities.add_face(inner.map { |u, v, w| local_uvw(u, v, w, unit, n) })
            ih.erase! if ih
            of.pushpull((of.normal % wi) >= 0 ? 1.0 : -1.0)
            fgrp.material = frame_mat
          end
          rec = 0.125
          gf = ge.add_face(inner.map { |u, v, w|
            local_uvw(u + inw[0] * rec, v + inw[1] * rec, w + inw[2] * rec, unit, n)
          })
          if gf
            gf.material = glass_mat
            gf.back_material = glass_mat
          end
        end

        # Bottom shelf (solid, ~1" thick) from the wall out to the front.
        shelf = ge.add_face([[-hw, 0, -hh], [hw, 0, -hh], [hw, out, -hh], [-hw, out, -hh]]
                              .map { |u, v, w| local_uvw(u, v, w, unit, n) })
        if shelf
          shelf.pushpull(shelf.normal.z >= 0 ? 1.0 : -1.0)
          ge.grep(Sketchup::Face).each { |f| f.material = frame_mat if f.material.nil? }
        end

        # Front: single pane (no mid rail).
        glass.call([[-hw, out, -hh], [hw, out, -hh], [hw, out, front_top], [-hw, out, front_top]])
        # Left side: lower rectangle + upper trapezoid (mid rail only on the sides).
        glass.call([[-hw, 0, -hh], [-hw, out, -hh], [-hw, out, 0.0], [-hw, 0, 0.0]])
        glass.call([[-hw, 0, 0.0], [-hw, out, 0.0], [-hw, out, front_top], [-hw, 0, hh]])
        # Right side: lower rectangle + upper trapezoid.
        glass.call([[hw, 0, -hh], [hw, out, -hh], [hw, out, 0.0], [hw, 0, 0.0]])
        glass.call([[hw, 0, 0.0], [hw, out, 0.0], [hw, out, front_top], [hw, 0, hh]])
        # Slanted top glass (back-top at the wall down to the front top).
        glass.call([[-hw, 0, hh], [hw, 0, hh], [hw, out, front_top], [-hw, out, front_top]])

        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowTool] garden body error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # Inset a convex, planar quad (points in [u,v,w]) inward by `fw` with mitered
    # corners, so the resulting frame ring has a UNIFORM width. Returns 4 [u,v,w].
    def inset_quad_uvw(quad, fw)
      pts = quad.map { |q| Geom::Point3d.new(q[0], q[1], q[2]) }
      normal = (pts[1] - pts[0]).cross(pts[2] - pts[0])
      return quad if normal.length < 1e-9
      normal.normalize!
      centroid = Geom::Point3d.new(pts.map(&:x).sum / 4.0,
                                   pts.map(&:y).sum / 4.0,
                                   pts.map(&:z).sum / 4.0)
      offset_lines = []
      4.times do |i|
        a = pts[i]
        edge = pts[(i + 1) % 4] - a
        inward = normal.cross(edge)
        return quad if inward.length < 1e-9
        inward.normalize!
        inward.reverse! if (centroid - a) % inward < 0
        offset_lines << [a.offset(inward, fw), edge]
      end
      inner = []
      4.times do |i|
        l0 = offset_lines[(i - 1) % 4]
        l1 = offset_lines[i]
        hit = Geom.intersect_line_line([l0[0], l0[1]], [l1[0], l1[1]])
        inner << (hit || pts[i])
      end
      inner.map { |p| [p.x, p.y, p.z] }
    end

    # Unit normal of a planar quad (uvw), flipped to point toward `box_center`
    # (i.e. into the box interior). Returns [u, v, w].
    def panel_inward_uvw(quad, box_center)
      p0, p1, p2 = quad[0], quad[1], quad[2]
      ax = p1[0] - p0[0]; ay = p1[1] - p0[1]; az = p1[2] - p0[2]
      bx = p2[0] - p0[0]; by = p2[1] - p0[1]; bz = p2[2] - p0[2]
      nx = ay * bz - az * by
      ny = az * bx - ax * bz
      nz = ax * by - ay * bx
      len = Math.sqrt(nx * nx + ny * ny + nz * nz)
      return [0.0, 0.0, 0.0] if len < 1e-9
      nx /= len; ny /= len; nz /= len
      cx = quad.map { |q| q[0] }.sum / 4.0
      cy = quad.map { |q| q[1] }.sum / 4.0
      cz = quad.map { |q| q[2] }.sum / 4.0
      dot = nx * (box_center[0] - cx) + ny * (box_center[1] - cy) + nz * (box_center[2] - cz)
      dot < 0 ? [-nx, -ny, -nz] : [nx, ny, nz]
    end

    # Build one pane: a sash ring (v_back..v_front) + a glass face at glass_v.
    def build_pane(ents, u_lo, u_hi, w_lo, w_hi, gi_lo, gi_hi, gj_lo, gj_hi,
                   v_back, v_front, glass_v, unit, n, frame_mat, glass_mat)
      sg = ents.add_group
      sg.name = 'Sash'
      sf = sg.entities.add_face([
        local_uvw(u_lo, v_back, w_lo, unit, n),
        local_uvw(u_hi, v_back, w_lo, unit, n),
        local_uvw(u_hi, v_back, w_hi, unit, n),
        local_uvw(u_lo, v_back, w_hi, unit, n)
      ])
      if sf
        hole = sg.entities.add_face([
          local_uvw(gi_lo, v_back, gj_lo, unit, n),
          local_uvw(gi_hi, v_back, gj_lo, unit, n),
          local_uvw(gi_hi, v_back, gj_hi, unit, n),
          local_uvw(gi_lo, v_back, gj_hi, unit, n)
        ])
        hole.erase! if hole
        d = v_front - v_back
        d = -d if sf.normal.dot(n) < 0
        sf.pushpull(d)
        sg.material = frame_mat
      end
      # Glass as a 1/4" deep pane centered on glass_v (grids sit inside it).
      gg = ents.add_group
      gg.name = 'Glass'
      gv0 = glass_v - 0.125
      gf = gg.entities.add_face([
        local_uvw(gi_lo, gv0, gj_lo, unit, n),
        local_uvw(gi_hi, gv0, gj_lo, unit, n),
        local_uvw(gi_hi, gv0, gj_hi, unit, n),
        local_uvw(gi_lo, gv0, gj_hi, unit, n)
      ])
      if gf
        dd = 0.25
        dd = -dd if gf.normal.dot(n) < 0
        gf.pushpull(dd)
        gg.material = glass_mat
      end
      build_pane_grid(ents, gi_lo, gi_hi, gj_lo, gj_hi, glass_v, unit, n, frame_mat)
    end

    # Colonial grid muntins on a pane's glass, per @glass_grid_style (e.g. "2x2").
    def parse_window_grid(style)
      return [1, 1] if style.nil? || style.to_s.strip.empty? || style.to_s.downcase == 'none'
      style.to_s =~ /^(\d+)x(\d+)$/i ? [$1.to_i, $2.to_i] : [1, 1]
    end

    def build_pane_grid(ents, u_lo, u_hi, w_lo, w_hi, glass_v, unit, n, mat)
      cols, rows = parse_window_grid(@glass_grid_style)
      return if cols <= 1 && rows <= 1
      mw = 0.375         # muntin width (< 1/2")
      hd = 0.1           # half depth — muntins sit INSIDE the 1/4" glass pane
      grp = ents.add_group
      grp.name = 'Grid'
      ge = grp.entities
      (1...cols).each do |i|
        u = u_lo + (u_hi - u_lo) * i / cols.to_f
        add_muntin_bar(ge, u - mw / 2.0, u + mw / 2.0, w_lo, w_hi, glass_v, hd, unit, n)
      end
      (1...rows).each do |j|
        w = w_lo + (w_hi - w_lo) * j / rows.to_f
        add_muntin_bar(ge, u_lo, u_hi, w - mw / 2.0, w + mw / 2.0, glass_v, hd, unit, n)
      end
      grp.material = mat
    end

    def add_muntin_bar(ge, u0, u1, w0, w1, v, hd, unit, n)
      f = ge.add_face([
        local_uvw(u0, v - hd, w0, unit, n),
        local_uvw(u1, v - hd, w0, unit, n),
        local_uvw(u1, v - hd, w1, unit, n),
        local_uvw(u0, v - hd, w1, unit, n)
      ])
      return unless f
      d = 2.0 * hd
      d = -d if f.normal.dot(n) < 0
      f.pushpull(d)
    end

    # Tile the interior into cols x rows panes (all coplanar). Mullions/rails
    # emerge from the small gap between adjacent panes.
    def build_grid_panes(ents, cols, rows, so_w, so_h, sash_width,
                         sash_back, sash_front, glass_v, unit, n, frame_mat, glass_mat,
                         gap = 0.5)
      cell_w = (2.0 * so_w) / cols
      cell_h = (2.0 * so_h) / rows
      half_mull = gap
      cols.times do |ci|
        rows.times do |ri|
          pu_lo = -so_w + ci * cell_w + (ci > 0 ? half_mull : 0.0)
          pu_hi = -so_w + (ci + 1) * cell_w - (ci < cols - 1 ? half_mull : 0.0)
          pw_lo = -so_h + ri * cell_h + (ri > 0 ? half_mull : 0.0)
          pw_hi = -so_h + (ri + 1) * cell_h - (ri < rows - 1 ? half_mull : 0.0)
          gi_lo = pu_lo + sash_width
          gi_hi = pu_hi - sash_width
          gj_lo = pw_lo + sash_width
          gj_hi = pw_hi - sash_width
          next if (gi_hi - gi_lo) <= 0.1 || (gj_hi - gj_lo) <= 0.1
          build_pane(ents, pu_lo, pu_hi, pw_lo, pw_hi, gi_lo, gi_hi, gj_lo, gj_hi,
                     sash_back, sash_front, glass_v, unit, n, frame_mat, glass_mat)
        end
      end
    end

    # Slider panels: side by side, each on its own depth track (alternating), with
    # a small interlock overlap so adjacent panels pass each other (no big gap).
    def build_slider_panes(ents, cols, so_w, so_h, sash_width,
                           clicked_side, unit, n, frame_mat, glass_mat)
      # Overlap by half a stile so the two meeting stiles land on the SAME X:
      # the front panel occludes the back one -> looks like a single center post.
      interlock = sash_width / 2.0
      # Each panel 1.25" deep on its own stacked track (one proud, one recessed).
      track = clicked_side * 1.25
      step  = (2.0 * so_w) / cols
      gj_lo = -so_h + sash_width
      gj_hi =  so_h - sash_width
      return if (gj_hi - gj_lo) <= 0.1
      cols.times do |i|
        u_lo = -so_w + i * step - (i > 0 ? interlock : 0.0)
        u_hi = -so_w + (i + 1) * step + (i < cols - 1 ? interlock : 0.0)
        t = (cols - 1 - i) % 2   # rightmost panel proud (front), alternating
        v_back  = -track * t
        v_front = v_back - track
        glass_v = v_back - track / 2.0
        gi_lo = u_lo + sash_width
        gi_hi = u_hi - sash_width
        next if (gi_hi - gi_lo) <= 0.1
        build_pane(ents, u_lo, u_hi, -so_h, so_h, gi_lo, gi_hi, gj_lo, gj_hi,
                   v_back, v_front, glass_v, unit, n, frame_mat, glass_mat)
      end
    end

    # Hung windows: sashes stacked vertically on offset depth tracks, bottom
    # sash proud of the top, with a small overlap at the meeting rail.
    def build_hung_panes(ents, rows, so_w, so_h, sash_width,
                         clicked_side, unit, n, frame_mat, glass_mat)
      # Overlap by half a rail so the two meeting rails land on the SAME line.
      interlock = sash_width / 2.0
      track = clicked_side * 1.25
      step  = (2.0 * so_h) / rows
      gi_lo = -so_w + sash_width
      gi_hi =  so_w - sash_width
      return if (gi_hi - gi_lo) <= 0.1
      rows.times do |i|
        w_lo = -so_h + i * step - (i > 0 ? interlock : 0.0)
        w_hi = -so_h + (i + 1) * step + (i < rows - 1 ? interlock : 0.0)
        t = i % 2                          # bottom sash (i=0) proud, top (i=1) back
        v_back  = -track * t
        v_front = v_back - track
        glass_v = v_back - track / 2.0
        gj_lo = w_lo + sash_width
        gj_hi = w_hi - sash_width
        next if (gj_hi - gj_lo) <= 0.1
        build_pane(ents, -so_w, so_w, w_lo, w_hi, gi_lo, gi_hi, gj_lo, gj_hi,
                   v_back, v_front, glass_v, unit, n, frame_mat, glass_mat)
      end
    end

    # Combination window: single-hung on each side + a wide fixed picture in the
    # middle (sides ~25% each, center ~50%).
    def build_xox_hung_panes(ents, so_w, so_h, sash_width,
                             sash_back, sash_front, glass_v, clicked_side,
                             unit, n, frame_mat, glass_mat)
      mull = 0.0   # no gap between sections — adjacent frames touch directly
      side = (2.0 * so_w) * 0.25
      xL0 = -so_w;        xL1 = -so_w + side
      xC0 = xL1;          xC1 =  so_w - side
      xR0 = xC1;          xR1 =  so_w

      # Center fixed picture pane.
      cu_lo = xC0 + mull
      cu_hi = xC1 - mull
      if (cu_hi - cu_lo) > 2 * sash_width + 0.1
        build_pane(ents, cu_lo, cu_hi, -so_h, so_h,
                   cu_lo + sash_width, cu_hi - sash_width,
                   -so_h + sash_width, so_h - sash_width,
                   sash_back, sash_front, glass_v, unit, n, frame_mat, glass_mat)
      end

      # Left + right single-hung columns.
      [[xL0, xL1 - mull], [xR0 + mull, xR1]].each do |u_lo, u_hi|
        hung_column(ents, u_lo, u_hi, so_h, sash_width, clicked_side,
                    unit, n, frame_mat, glass_mat)
      end
    end

    # Two stacked single-hung sashes (offset depth) inside a u-column.
    def hung_column(ents, u_lo, u_hi, so_h, sash_width, clicked_side,
                    unit, n, frame_mat, glass_mat)
      gi_lo = u_lo + sash_width
      gi_hi = u_hi - sash_width
      return if (gi_hi - gi_lo) <= 0.1
      interlock = sash_width / 2.0
      track = clicked_side * 1.25
      2.times do |i|
        w_lo = -so_h + i * so_h - (i > 0 ? interlock : 0.0)
        w_hi = -so_h + (i + 1) * so_h + (i < 1 ? interlock : 0.0)
        t = (i + 1) % 2                 # top sash (i=1) proud/forward, bottom back
        vb = -track * t
        vf = vb - track
        gv = vb - track / 2.0
        gj_lo = w_lo + sash_width
        gj_hi = w_hi - sash_width
        next if (gj_hi - gj_lo) <= 0.1
        build_pane(ents, u_lo, u_hi, w_lo, w_hi, gi_lo, gi_hi, gj_lo, gj_hi,
                   vb, vf, gv, unit, n, frame_mat, glass_mat)
      end
    end

    # Panes per type as [cols, rows].
    def window_grid(type)
      case type.to_s
      when 'Single Hung', 'Single Hung XL', 'Double Hung' then [1, 2]   # horizontal rail
      when 'Slider XO', 'Casement XX'                     then [2, 1]   # one vertical mullion
      when 'Slider XOX'                                   then [3, 1]   # two vertical mullions
      else [1, 1]                                                       # Casement / Awning / Picture / Garden
      end
    end

    # Build divider bars (frame material) across the glass area at even spacings.
    def build_window_dividers(window_group, cols, rows, si_w, si_h, sash_back, sash_front, unit, n, frame_mat)
      grp = window_group.entities.add_group
      grp.name = 'Dividers'
      ents = grp.entities
      bar = 0.5
      depth = sash_front - sash_back

      (1...cols).each do |k|
        u0 = -si_w + (2.0 * si_w) * k / cols
        f = ents.add_face([
          local_uvw(u0 - bar, sash_back, -si_h, unit, n),
          local_uvw(u0 + bar, sash_back, -si_h, unit, n),
          local_uvw(u0 + bar, sash_back,  si_h, unit, n),
          local_uvw(u0 - bar, sash_back,  si_h, unit, n)
        ])
        next unless f
        d = depth
        d = -d if f.normal.dot(n) < 0
        f.pushpull(d)
      end

      (1...rows).each do |k|
        w0 = -si_h + (2.0 * si_h) * k / rows
        f = ents.add_face([
          local_uvw(-si_w, sash_back, w0 - bar, unit, n),
          local_uvw( si_w, sash_back, w0 - bar, unit, n),
          local_uvw( si_w, sash_back, w0 + bar, unit, n),
          local_uvw(-si_w, sash_back, w0 + bar, unit, n)
        ])
        next unless f
        d = depth
        d = -d if f.normal.dot(n) < 0
        f.pushpull(d)
      end

      grp.material = frame_mat
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

    def casing_enabled?(style)
      style.to_s != '' && style.to_s != 'none'
    end

    def ensure_casing_profiles!
      return if defined?(InteriorPro::DoorCasingProfiles)
      load File.join(File.dirname(__FILE__), 'door_casing_profiles.rb')
    end

    WINDOW_CASING_REVEAL = 0.25 unless const_defined?(:WINDOW_CASING_REVEAL, false)
    WINDOW_JAMB_WIDTH = 1.0 unless const_defined?(:WINDOW_JAMB_WIDTH, false)

    # Picture-frame casing around the opening: single closed Follow Me sweep
    # (mitered corners on all 4 sides). Sits on the jamb with a 1/4" reveal.
    # v_wall = wall face plane (v along n); dir_v = protrusion sign along n.
    def build_window_casing!(parent_ents, half_w, half_h, style, v_wall, dir_v, unit, n, mat, name)
      ensure_casing_profiles!
      spec = InteriorPro::DoorCasingProfiles.spec(style.to_s)
      return unless spec
      cw = spec[:width]
      max_d = spec[:depth]
      ov = [WINDOW_JAMB_WIDTH - WINDOW_CASING_REVEAL, 0.0].max
      u_in = half_w - ov
      w_in = half_h - ov
      return if u_in < 1.0 || w_in < 1.0

      grp = parent_ents.add_group
      grp.name = name
      ge = grp.entities

      # Profile on the LEFT leg at mid-height (away from the corners),
      # perpendicular to the leg.
      prof_pts = spec[:profile].map do |u_frac, v_frac|
        local_uvw(-u_in - u_frac * cw, v_wall + dir_v * v_frac * max_d, 0.0, unit, n)
      end
      prof_face = ge.add_face(prof_pts)
      unless prof_face && prof_face.valid?
        grp.erase! if grp.valid?
        return nil
      end

      p_ml = local_uvw(-u_in, v_wall, 0.0,   unit, n)
      p_tl = local_uvw(-u_in, v_wall, w_in,  unit, n)
      p_tr = local_uvw( u_in, v_wall, w_in,  unit, n)
      p_br = local_uvw( u_in, v_wall, -w_in, unit, n)
      p_bl = local_uvw(-u_in, v_wall, -w_in, unit, n)
      path_edges = []
      [[p_ml, p_tl], [p_tl, p_tr], [p_tr, p_br], [p_br, p_bl], [p_bl, p_ml]].each do |a, b|
        e = ge.add_line(a, b)
        path_edges << e if e
      end
      begin
        prof_face.followme(path_edges)
        soften_casing_edges(ge)
      rescue => e
        puts "[WindowTool] casing followme error: #{e.message}"
      ensure
        path_edges.each { |edge| edge.erase! if edge && edge.valid? }
      end
      grp.material = mat
      grp
    end

    def soften_casing_edges(ents, angle_limit = 50.degrees)
      ents.grep(Sketchup::Edge).each do |edge|
        next unless edge.valid?
        faces = edge.faces
        next unless faces.length == 2
        next if faces[0].normal.angle_between(faces[1].normal) > angle_limit
        edge.soft = true
        edge.smooth = true
      end
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

# Interior Pro - Window Tool (Step 2: cuts opening through wall, no body yet)

module InteriorPro
  class WindowTool

    attr_accessor :window_type, :width, :height, :header_height,
                  :frame_width, :install_window, :exterior_trim,
                  :interior_casing, :preset_name

    def initialize
      @window_type = 'Single Hung'
      @width = 36.0
      @height = 48.0
      @header_height = 80.0
      @frame_width = 1.5
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
      wall, picked_point = find_wall_under_cursor(view, x, y)
      unless wall
        Sketchup.set_status_text("No wall under cursor. Hover over a wall to place a window.", SB_PROMPT)
        return
      end
      cut_window_opening(wall, picked_point)
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
      return [nil, nil] if ph.count == 0

      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |entity|
          if entity.is_a?(Sketchup::Group) &&
             entity.valid? &&
             entity.get_attribute('InteriorPro', 'type') == 'wall'
            return [entity, ph.picked_point]
          end
        end
      end
      [nil, nil]
    end

    def cut_window_opening(wall_group, picked_point)
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

      # Compute 4 corners of opening rectangle on the clicked face of the wall.
      n_side = clicked_side * (thickness / 2.0)
      cx = cline_start.x + unit.x * t + n.x * n_side
      cy = cline_start.y + unit.y * t + n.y * n_side
      ux = unit.x * half_w
      uy = unit.y * half_w
      p_bl = Geom::Point3d.new(cx - ux, cy - uy, win_bot_z)
      p_br = Geom::Point3d.new(cx + ux, cy + uy, win_bot_z)
      p_tr = Geom::Point3d.new(cx + ux, cy + uy, win_top_z)
      p_tl = Geom::Point3d.new(cx - ux, cy - uy, win_top_z)

      model = Sketchup.active_model
      model.start_operation('Cut Window Opening', true)
      begin
        new_face = wall_group.entities.add_face(p_bl, p_br, p_tr, p_tl)
        unless new_face
          model.abort_operation
          UI.messagebox("Could not create opening face on wall.")
          return
        end

        # Push opposite to outward direction so the cut goes INTO the wall.
        outward = Geom::Vector3d.new(n.x * clicked_side, n.y * clicked_side, 0)
        sign = new_face.normal.dot(outward) > 0 ? -1 : 1
        new_face.pushpull(sign * thickness)

        model.commit_operation
        Sketchup.set_status_text(
          "Window opening cut. Click another wall or press Escape to exit.",
          SB_PROMPT
        )
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Error cutting opening: #{e.message}")
        puts "[WindowTool] cut error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
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

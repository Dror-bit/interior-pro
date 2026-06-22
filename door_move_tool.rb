# Interior Pro - Door Move Tool
#
# Interactive move-along-wall with a live ghost preview AND exact numeric entry
# (the Measurement Box / VCB).
#
# Flow:
#   1. Click a door  -> it becomes the move target.
#   2. Move the mouse along the wall -> a ghost of the opening follows the
#      cursor (green = fits, red = out of bounds).
#   3. Click again to drop it there, OR type a distance + Enter to move an
#      exact amount in the current drag direction.

module InteriorPro
  class DoorMoveTool

    GREEN = Sketchup::Color.new(40, 150, 60)
    RED   = Sketchup::Color.new(200, 40, 40)

    def activate
      reset_state
      update_status_bar
    end

    def deactivate(view)
      view.invalidate
    end

    def onCancel(_reason, view)
      reset_state
      update_status_bar
      view.invalidate
    end

    def reset_state
      @door = nil
      @wall = nil
      @geo  = nil
      @ctx  = nil
      @new_t = nil
      @valid = false
      @dir = 1
    end

    # --- picking / placing -------------------------------------------------

    def onLButtonDown(flags, x, y, view)
      if @door.nil?
        pick_door(x, y, view)
      else
        commit_move(view)
      end
    end

    def pick_door(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.count > 0 ? ph.path_at(0) : nil
      door = InteriorPro::DoorManager.find_door_in_path(path)
      return unless door

      wall_id = door.get_attribute('InteriorPro', 'host_wall_id')
      wall = InteriorPro::DoorManager.find_wall_by_id(Sketchup.active_model, wall_id)
      geo  = wall ? InteriorPro::DoorManager.wall_geometry(wall) : nil
      unless wall && geo
        UI.messagebox('Host wall not found for this door.')
        return
      end

      @door = door
      @wall = wall
      @geo  = geo
      @ctx  = InteriorPro::DoorManager.opening_context(door, geo)
      @new_t = @ctx[:t]
      @valid = true
      update_status_bar
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      return unless @door
      t = cursor_to_t(x, y, view)
      return unless t
      @new_t = t
      @dir = (t - @ctx[:t]) >= 0 ? 1 : -1
      @valid = position_valid?(t)
      update_status_bar
      view.invalidate
    end

    # Project the cursor ray onto the wall centerline and return distance along it.
    def cursor_to_t(x, y, view)
      ray = view.pickray(x, y)
      line = [@geo[:cline_start], @geo[:unit]]
      pt = Geom.closest_points(line, ray).first
      return nil unless pt
      (pt - @geo[:cline_start]).dot(@geo[:unit])
    end

    def position_valid?(t)
      half_w = @ctx[:half_w]
      t - half_w >= 0 && t + half_w <= @geo[:wall_length]
    end

    # --- measurement box (VCB) --------------------------------------------

    def enableVCB?
      true
    end

    def onUserText(text, view)
      return unless @door
      begin
        dist = text.to_l.to_f
      rescue ArgumentError
        UI.messagebox('Invalid distance.')
        return
      end
      t = @ctx[:t] + @dir * dist
      unless position_valid?(t)
        UI.messagebox('Door does not fit at that distance.')
        return
      end
      @new_t = t
      @valid = true
      commit_move(view)
    end

    # --- commit ------------------------------------------------------------

    def commit_move(view)
      return unless @door && @new_t
      unless @valid
        UI.messagebox('Door does not fit at this position.')
        return
      end
      delta = @new_t - @ctx[:t]
      if delta.abs < 0.001
        reset_state
        update_status_bar
        view.invalidate
        return
      end
      InteriorPro::DoorManager.move_door(@door, delta)
      reset_state
      update_status_bar
      view.invalidate
    end

    # --- preview drawing ---------------------------------------------------

    def draw(view)
      return unless @door && @new_t
      corners = ghost_box_corners(@new_t)
      return unless corners

      front = corners[0, 4]
      back  = corners[4, 4]
      view.line_width = 3
      view.drawing_color = @valid ? GREEN : RED
      view.draw(GL_LINE_LOOP, front)
      view.draw(GL_LINE_LOOP, back)
      4.times { |i| view.draw(GL_LINES, [front[i], back[i]]) }
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@wall.bounds) if @wall&.valid?
      if @new_t
        c = ghost_box_corners(@new_t)
        c&.each { |p| bb.add(p) }
      end
      bb
    end

    # 8 corners of the opening volume at position t: front face (clicked side)
    # then back face (through the wall).
    def ghost_box_corners(t)
      tool = InteriorPro::DoorTool.new
      data = tool.build_opening_data(
        @wall, @geo,
        width: @ctx[:width],
        height: @ctx[:height],
        floor_offset: @ctx[:floor_offset],
        t: t,
        clicked_side: @ctx[:clicked_side]
      )
      fx = data[:fx]; fy = data[:fy]
      ux = data[:ux]; uy = data[:uy]
      bot = data[:door_bot_z]; top = data[:door_top_z]
      ow = data[:outward]
      th = data[:thickness]
      front = [
        Geom::Point3d.new(fx - ux, fy - uy, bot),
        Geom::Point3d.new(fx + ux, fy + uy, bot),
        Geom::Point3d.new(fx + ux, fy + uy, top),
        Geom::Point3d.new(fx - ux, fy - uy, top)
      ]
      back = front.map { |p| p.offset(ow, -th) }
      front + back
    rescue => e
      puts "[DoorMoveTool] ghost error: #{e.message}"
      nil
    end

    def update_status_bar
      if @door.nil?
        Sketchup.set_status_text('Click a door to move it along the wall', SB_PROMPT)
      else
        Sketchup.set_status_text('Move the cursor along the wall, then click to place — or type a distance', SB_PROMPT)
        if @new_t
          Sketchup.set_status_text(format('%.2f"', (@new_t - @ctx[:t]).abs), SB_VCB_VALUE)
          Sketchup.set_status_text('Move distance', SB_VCB_LABEL)
        end
      end
    end

  end
end

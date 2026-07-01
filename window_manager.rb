# Interior Pro - Window Manager
# Edit / move / delete for windows. Windows live in the SAME native openings
# list as doors, so we reuse DoorManager's native helpers + WallTool rebuild.

module InteriorPro
  module WindowManager

    def self.window_entity?(e)
      return false unless e && e.valid?
      return false unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      e.get_attribute('InteriorPro', 'type') == 'window'
    end

    def self.find_window_in_path(path)
      return nil unless path
      path.reverse.find { |e| window_entity?(e) }
    end

    def self.host_wall(window)
      wid = window.get_attribute('InteriorPro', 'host_wall_id')
      InteriorPro::DoorManager.find_wall_by_id(Sketchup.active_model, wid)
    end

    # Remove the window body + its opening from the wall, then rebuild the wall.
    def self.delete_window(window)
      return false unless window_entity?(window)
      wall = host_wall(window)
      t = window.get_attribute('InteriorPro', 'position_along_wall_in').to_f
      model = Sketchup.active_model
      model.start_operation('Delete Window', true)
      begin
        window.erase! if window.valid?
        if wall
          InteriorPro::DoorManager.remove_native_opening!(wall, t)
          InteriorPro::WallTool.rebuild_wall_native!(wall)
        end
        model.commit_operation
        true
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowManager] delete: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        UI.messagebox("Error deleting window: #{e.message}")
        false
      end
    end

    # Slide the window along its wall by delta_t (inches). The opening follows
    # via the native rebuild; the window body is translated to match.
    def self.move_window(window, delta_t)
      return false unless window_entity?(window)
      delta_t = delta_t.to_f
      return true if delta_t.abs < 0.001
      wall = host_wall(window)
      unless wall
        UI.messagebox('Host wall not found.')
        return false
      end
      geo = InteriorPro::DoorManager.wall_geometry(wall)
      return false unless geo
      t = window.get_attribute('InteriorPro', 'position_along_wall_in').to_f
      new_t = t + delta_t
      half_w = window.get_attribute('InteriorPro', 'width_in').to_f / 2.0
      if new_t - half_w < 0 || new_t + half_w > geo[:wall_length]
        UI.messagebox('Window does not fit at this position.')
        return false
      end

      model = Sketchup.active_model
      model.start_operation('Move Window', true)
      begin
        InteriorPro::DoorManager.update_native_opening_t!(wall, t, new_t)
        InteriorPro::WallTool.rebuild_wall_native!(wall)

        vec = Geom::Vector3d.new(geo[:unit].x * delta_t, geo[:unit].y * delta_t, 0)
        window.transform!(Geom::Transformation.translation(vec)) if window.valid?
        window.set_attribute('InteriorPro', 'position_along_wall_in', new_t)
        fx = window.get_attribute('InteriorPro', 'face_x')
        fy = window.get_attribute('InteriorPro', 'face_y')
        window.set_attribute('InteriorPro', 'face_x', fx.to_f + vec.x) unless fx.nil?
        window.set_attribute('InteriorPro', 'face_y', fy.to_f + vec.y) unless fy.nil?

        model.commit_operation
        true
      rescue => e
        model.abort_operation rescue nil
        puts "[WindowManager] move: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        UI.messagebox("Error moving window: #{e.message}")
        false
      end
    end

    # Re-place the window at its current position with new settings: remove the
    # old body + opening, then run the native placement with the new params.
    def self.update_window(window, settings)
      return false unless window_entity?(window)
      wall = host_wall(window)
      unless wall
        UI.messagebox('Host wall not found.')
        return false
      end
      t = window.get_attribute('InteriorPro', 'position_along_wall_in').to_f

      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      thickness = wall.get_attribute('InteriorPro', 'thickness').to_f
      anchor = wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      dx = ex - sx; dy = ey - sy
      len = Math.sqrt(dx * dx + dy * dy)
      return false if len < 0.1
      ux = dx / len; uy = dy / len
      nx = -uy; ny = ux
      hanchor = anchor.split('-')[1] || 'center'
      coff = hanchor == 'left' ? thickness / 2.0 : (hanchor == 'right' ? -thickness / 2.0 : 0.0)
      clx = sx + nx * coff; cly = sy + ny * coff
      # a point on the exterior wall face at parameter t
      px = clx + ux * t + nx * (-thickness / 2.0)
      py = cly + uy * t + ny * (-thickness / 2.0)
      picked = Geom::Point3d.new(px, py, 0)

      model = Sketchup.active_model
      model.start_operation('Edit Window — Remove', true)
      begin
        window.erase! if window.valid?
        InteriorPro::DoorManager.remove_native_opening!(wall, t)
        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Error editing window: #{e.message}")
        return false
      end

      tool = InteriorPro::WindowTool.new
      tool.window_type    = settings['window_type']         if tool.respond_to?(:window_type=)
      tool.width          = settings['width'].to_f          if tool.respond_to?(:width=)
      tool.height         = settings['height'].to_f         if tool.respond_to?(:height=)
      tool.header_height  = settings['header_height'].to_f  if tool.respond_to?(:header_height=)
      tool.frame_width    = settings['frame_width'].to_f    if tool.respond_to?(:frame_width=)
      tool.interior_depth = settings['interior_depth'].to_f if tool.respond_to?(:interior_depth=)
      tool.garden_depth   = settings['garden_depth'].to_f   if settings['garden_depth'] && tool.respond_to?(:garden_depth=)
      tool.glass_grid_style = settings['glass_grid_style']  if settings['glass_grid_style'] && tool.respond_to?(:glass_grid_style=)
      tool.preset_name    = settings['window_type']         if tool.respond_to?(:preset_name=)
      tool.send(:cut_window_opening, wall, picked, nil)   # cut_window_opening is private
      true
    end
  end

  # --- Tools ----------------------------------------------------------------

  class WindowDeleteTool
    def activate
      Sketchup.set_status_text('Click a window to delete it', SB_PROMPT)
    end

    def deactivate(view)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.count > 0 ? ph.path_at(0) : nil
      window = InteriorPro::WindowManager.find_window_in_path(path)
      return unless window
      if UI.messagebox('Delete this window and patch the wall opening?', MB_YESNO) == IDYES
        InteriorPro::WindowManager.delete_window(window)
      end
    end
  end

  class WindowMoveTool
    GREEN = Sketchup::Color.new(40, 150, 60) unless const_defined?(:GREEN, false)
    RED   = Sketchup::Color.new(200, 40, 40) unless const_defined?(:RED, false)

    def activate
      reset_state
      Sketchup.set_status_text('Click a window to move it along the wall', SB_PROMPT)
    end

    def deactivate(view)
      view.invalidate
    end

    def onCancel(_reason, view)
      reset_state
      view.invalidate
    end

    def reset_state
      @window = nil; @wall = nil; @geo = nil; @ctx = nil
      @new_t = nil; @valid = false; @dir = 1
    end

    def onLButtonDown(_flags, x, y, view)
      @window.nil? ? pick_window(x, y, view) : commit(view)
    end

    def pick_window(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.count > 0 ? ph.path_at(0) : nil
      window = InteriorPro::WindowManager.find_window_in_path(path)
      return unless window
      wall = InteriorPro::WindowManager.host_wall(window)
      geo  = wall ? InteriorPro::DoorManager.wall_geometry(wall) : nil
      unless wall && geo
        UI.messagebox('Host wall not found for this window.')
        return
      end
      @window = window
      @wall = wall
      @geo = geo
      @ctx = window_ctx(window)
      @new_t = @ctx[:t]
      @valid = true
      view.invalidate
    end

    def window_ctx(window)
      t    = window.get_attribute('InteriorPro', 'position_along_wall_in').to_f
      w    = window.get_attribute('InteriorPro', 'width_in').to_f
      h    = window.get_attribute('InteriorPro', 'height_in').to_f
      sill = window.get_attribute('InteriorPro', 'sill_height_in').to_f
      cs   = window.get_attribute('InteriorPro', 'clicked_side').to_i
      cs = 1 if cs == 0
      { t: t, half_w: w / 2.0, width: w, height: h, floor_offset: sill, clicked_side: cs }
    end

    def onMouseMove(_flags, x, y, view)
      return unless @window
      ray = view.pickray(x, y)
      hit = Geom.closest_points([@geo[:cline_start], @geo[:unit]], ray).first
      return unless hit
      @new_t = (hit - @geo[:cline_start]).dot(@geo[:unit])
      @dir = (@new_t - @ctx[:t]) >= 0 ? 1 : -1
      @valid = @new_t - @ctx[:half_w] >= 0 && @new_t + @ctx[:half_w] <= @geo[:wall_length]
      view.invalidate
    end

    def enableVCB?
      true
    end

    def onUserText(text, view)
      return unless @window
      begin
        dist = text.to_l.to_f
      rescue ArgumentError
        return
      end
      @new_t = @ctx[:t] + @dir * dist
      @valid = @new_t - @ctx[:half_w] >= 0 && @new_t + @ctx[:half_w] <= @geo[:wall_length]
      commit(view)
    end

    def commit(view)
      return unless @window && @new_t
      unless @valid
        UI.messagebox('Window does not fit at this position.')
        return
      end
      delta = @new_t - @ctx[:t]
      InteriorPro::WindowManager.move_window(@window, delta) if delta.abs >= 0.001
      reset_state
      view.invalidate
    end

    def draw(view)
      return unless @window && @new_t
      corners = ghost_corners(@new_t)
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
        c = ghost_corners(@new_t)
        c&.each { |p| bb.add(p) }
      end
      bb
    end

    def ghost_corners(t)
      tool = InteriorPro::DoorTool.new
      data = tool.build_opening_data(@wall, @geo, width: @ctx[:width], height: @ctx[:height],
                                     floor_offset: @ctx[:floor_offset], t: t,
                                     clicked_side: @ctx[:clicked_side])
      tool.opening_ghost_corners(data)
    rescue StandardError => e
      puts "[WindowMoveTool] ghost error: #{e.message}"
      nil
    end
  end

  class WindowEditTool
    def activate
      sel = Sketchup.active_model.selection.find { |e| InteriorPro::WindowManager.window_entity?(e) }
      if sel
        InteriorPro::WindowLibraryDialog.show_for_edit(sel)
      else
        Sketchup.set_status_text('Click a window to edit its settings', SB_PROMPT)
      end
    end

    def deactivate(view)
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.count > 0 ? ph.path_at(0) : nil
      window = InteriorPro::WindowManager.find_window_in_path(path)
      InteriorPro::WindowLibraryDialog.show_for_edit(window) if window
    end
  end
end

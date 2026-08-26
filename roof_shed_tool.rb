# Interior Pro - Shed Roof Tool (2026-08-26)
# Click a wall to make it the LOW side of a single-slope (shed) roof: the
# roof rises away from it and every other wall is cut vertical. Clicking
# the marked wall again clears the mark and the roof falls back to its
# longest wall. The choice is saved by wall id on the model, so it
# survives every rebuild. Same wall-picking pattern as RoofGableTool.
module InteriorPro
  class RoofShedTool
    def activate
      @preview_wall = nil
      Sketchup.set_status_text('Click the LOW wall - the shed roof rises away from it', SB_PROMPT)
    end

    def deactivate(view)
      @preview_wall = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      w = pick_wall(view, x, y)
      if w != @preview_wall
        @preview_wall = w
        view.invalidate
      end
    end

    def draw(view)
      return unless @preview_wall&.valid?
      flat = @preview_wall.get_attribute('InteriorPro', 'corners_xy')
      return unless flat && flat.length == 8
      t = @preview_wall.transformation
      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0).transform(t) }
      marked = InteriorPro::RoofManager.shed_wall_ids
                                       .include?(@preview_wall.get_attribute('InteriorPro', 'id'))
      # blue = already the low wall, orange = click to make it the low wall
      view.drawing_color = marked ? Sketchup::Color.new(40, 140, 230)
                                  : Sketchup::Color.new(230, 120, 20)
      view.line_width = 3
      view.line_stipple = ''
      view.draw(GL_LINE_LOOP, pts)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@preview_wall.bounds) if @preview_wall&.valid?
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      wall = pick_wall(view, x, y)
      return UI.messagebox('Click an Interior Pro wall') unless wall
      InteriorPro::RoofManager.set_shed_wall!(wall)
      view.invalidate
    rescue StandardError => e
      puts "[RoofShedTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    def onKeyDown(key, _repeat, _flags, view)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    private

    def pick_wall(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end
      nil
    end
  end
end

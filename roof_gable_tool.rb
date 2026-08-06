# Interior Pro - Roof Gable Ends Tool (2026-08-05)
# Click a wall to toggle its roof end between HIP and GABLE. The choice is
# saved by wall id on the model (survives rebuilds) and the roof rebuilds
# itself right away. Same wall-picking pattern as WallDeleteTool.
module InteriorPro
  class RoofGableTool
    def activate
      @preview_wall = nil
      Sketchup.set_status_text('Click a wall to toggle its roof end: hip <-> gable', SB_PROMPT)
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
      marked = InteriorPro::RoofManager.gable_wall_ids
                                       .include?(@preview_wall.get_attribute('InteriorPro', 'id'))
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
      # the click position decides WHICH roof section of a long wall gables
      ip = view.inputpoint(x, y)
      p3 = ip.position
      InteriorPro::RoofManager.toggle_gable_wall!(wall, [p3.x.to_f, p3.y.to_f])
      view.invalidate
    rescue StandardError => e
      puts "[RoofGableTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
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

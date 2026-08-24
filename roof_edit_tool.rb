# Interior Pro - Roof Edit Tool (2026-08-26, step 4 of Edit Roof)
# Click a roof to open the roof panel WITH THAT ROOF'S OWN SETTINGS in it;
# Apply there rebuilds that roof alone. Same click-to-pick pattern as
# RoofGableTool, one type further up: it looks for a 'roof' group.
module InteriorPro
  class RoofEditTool
    def activate
      @preview = nil
      Sketchup.set_status_text('Click a roof to edit it', SB_PROMPT)
    end

    def deactivate(view)
      @preview = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      r = pick_roof(view, x, y)
      if r != @preview
        @preview = r
        view.invalidate
      end
    end

    # Hover feedback: the roof's own eave outline, drawn at its eave
    # height - the same loop the roof was built from (footprint_xy).
    def draw(view)
      return unless @preview&.valid?
      flat = @preview.get_attribute('InteriorPro', 'footprint_xy')
      return unless flat && flat.length >= 6
      z = @preview.get_attribute('InteriorPro', 'eave_z').to_f
      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, z) }
      view.drawing_color = Sketchup::Color.new(40, 140, 230)
      view.line_width = 3
      view.line_stipple = ''
      view.draw(GL_LINE_LOOP, pts)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@preview.bounds) if @preview&.valid?
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      roof = pick_roof(view, x, y)
      return UI.messagebox('Click an Interior Pro roof') unless roof
      InteriorPro::RoofDialog.show(roof)
      view.invalidate
    rescue StandardError => e
      puts "[RoofEditTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    def onKeyDown(key, _repeat, _flags, _view)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    private

    def pick_roof(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'roof'
        end
      end
      nil
    end
  end
end

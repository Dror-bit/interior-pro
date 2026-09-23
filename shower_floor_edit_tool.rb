# encoding: utf-8
# Interior Pro - EDIT A SHOWER FLOOR (2026-09-22, his ask: "כפתור העריכה
# לריצפה הזאת כי אין לי כוח כל פעם למחוק ולייצר חדשה").
#
# Copied from the niche edit tool: hover a shower floor, it is outlined
# in blue; click, and the SAME window it was drawn with opens, filled
# with its own numbers. OK rebuilds it on the SAME loop - ShowerFloor
# .build! already replaces a pad drawn on the same loop, so this tool
# owns no geometry and no window of its own.
module InteriorPro
  class ShowerFloorEditTool < ShowerFloorTool
    BLUE = [40, 110, 200].freeze unless const_defined?(:BLUE, false)

    def activate
      @hit = nil
      @ip = Sketchup::InputPoint.new
      Sketchup.set_status_text('Edit Shower Floor: click a shower floor to change it. Esc = done.', SB_PROMPT)
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onMouseMove(_flags, x, y, view)
      @hit = pick(view, x, y)
      view.tooltip = @hit ? 'Click to edit this shower floor' : ''
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      pad = pick(view, x, y)
      if pad.nil?
        Sketchup.set_status_text('Edit Shower Floor: that is not a shower floor - click inside one.', SB_PROMPT)
        return
      end
      at = lambda { |k| pad.get_attribute('InteriorPro', k) }
      loop_xy = Array(at.call('poly_xy')).map(&:to_f).each_slice(2).to_a
      floor_z = at.call('floor_z').to_f
      # The window opens on THIS floor's numbers, not the last ones typed.
      InteriorPro::ShowerFloorDialog.show(InteriorPro::ShowerFloorDialog.from_pad(pad),
                                          title: 'Edit Shower Floor', button: 'Apply') do |cfg|
        model = Sketchup.active_model
        model.start_operation('InteriorPro Edit Shower Floor', true)
        grp = InteriorPro::ShowerFloor.build!(loop_xy, floor_z, settings: cfg)
        if grp && grp != :no_floor
          model.commit_operation
          Sketchup.set_status_text('Shower floor rebuilt. Click another one, or Esc.', SB_PROMPT)
        else
          model.abort_operation
          UI.messagebox('The shower floor could not be rebuilt - see the Ruby Console for the reason.')
        end
      end
      @hit = nil
      view.invalidate
    end

    # The shower floor under the mouse: the pad whose loop holds the
    # point, nearest in height to where the mouse landed.
    def pick(view, x, y)
      @ip.pick(view, x, y)
      pos = @ip.position
      return nil unless pos
      pads = InteriorPro::ShowerFloor.pads_in_model.select do |g|
        InteriorPro::ShowerFloor.point_in?(Array(g.get_attribute('InteriorPro', 'poly_xy')).map(&:to_f).each_slice(2).to_a, pos.x, pos.y)
      end
      pads.min_by { |g| (g.get_attribute('InteriorPro', 'floor_z').to_f - pos.z.to_f).abs }
    rescue StandardError => e
      puts "[ShowerFloor] edit pick failed: #{e.message}"
      nil
    end

    def draw(view)
      return unless @hit && @hit.valid?
      loop_xy = Array(@hit.get_attribute('InteriorPro', 'poly_xy')).map(&:to_f).each_slice(2).to_a
      z = @hit.bounds.max.z
      pts = loop_xy.map { |px, py| Geom::Point3d.new(px, py, z + 0.1) }
      return if pts.length < 3
      view.drawing_color = Sketchup::Color.new(*BLUE)
      view.line_width = 4
      view.line_stipple = ''
      view.draw(GL_LINE_LOOP, pts)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@hit.bounds) if @hit && @hit.valid?
      bb
    end
  end
end

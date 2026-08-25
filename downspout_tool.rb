# Interior Pro - Downspout Tool (2026-08-29)
#
# Downspouts come up automatically, one per building corner. This is the
# other half the user asked for: "אוטומטי ולחיצה אם אני רוצה להוריד אותם".
#
# Click a PIPE  -> it comes off, and it STAYS off. Erasing it by hand does
#                  not: the next rebuild puts it straight back, because the
#                  roof builds them from the corners every time. What makes
#                  it stick is a key written on the roof group itself.
# Click the ROOF near where one used to be -> it comes back.
#
# Both ways go through build_roof!(replace: roof), so the roof that comes
# out is the roof the panel would have built - no half-edited geometry.
module InteriorPro
  class DownspoutTool
    # How near the click has to be, in plan, to a pipe that was taken off
    # for this to be read as "put that one back".
    RESTORE_TOL = 48.0 unless const_defined?(:RESTORE_TOL, false)

    def activate
      @preview = nil
      Sketchup.set_status_text(
        'Click a downspout to remove it - click the roof where one was to bring it back',
        SB_PROMPT
      )
    end

    def deactivate(view)
      @preview = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      d = pick_type(view, x, y, 'downspout')
      if d != @preview
        @preview = d
        view.invalidate
      end
    end

    def draw(view)
      return unless @preview&.valid?
      bb = @preview.bounds
      view.drawing_color = Sketchup::Color.new(230, 40, 40)
      view.line_width = 3
      view.line_stipple = ''
      c = (0..7).map { |i| bb.corner(i) }
      [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4],
       [0, 4], [1, 5], [2, 6], [3, 7]].each do |a, b|
        view.draw(GL_LINES, [c[a], c[b]])
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@preview.bounds) if @preview&.valid?
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      roof = pick_type(view, x, y, 'roof')
      return UI.messagebox('Click an Interior Pro roof') unless roof
      pipe = pick_type(view, x, y, 'downspout')
      if pipe
        key = pipe.get_attribute('InteriorPro', 'ds_key').to_s
        return UI.messagebox('That pipe has no key on it') if key.empty?
        RoofManager.toggle_downspout!(roof, key, on: false)
      else
        pt = pick_point(view, x, y)
        return UI.messagebox('Click a downspout to remove it') unless pt
        key = RoofManager.nearest_off_key(RoofManager.skip_downspouts(roof),
                                          pt.x, pt.y, RESTORE_TOL)
        return UI.messagebox('No downspout was taken off here') unless key
        RoofManager.toggle_downspout!(roof, key, on: true)
      end
      @preview = nil
      view.invalidate
    rescue StandardError => e
      puts "[DownspoutTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    def onKeyDown(key, _repeat, _flags, _view)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    private

    def pick_type(view, x, y, want)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == want
        end
      end
      nil
    end

    # PickHelper has no picked_point - point_at(index) is the one that works
    # (a lesson this project has already paid for once).
    def pick_point(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        p = ph.point_at(i)
        return p if p
      end
      nil
    end
  end
end

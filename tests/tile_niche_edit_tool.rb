# encoding: utf-8
# Interior Pro - EDIT A NICHE (2026-09-22, his ask: "כפתור עריכה").
#
# The delete tool's hover and pick, and a click opens the SAME window
# the niche was placed with - width, height, depth, height off the floor -
# filled with the niche's own numbers. OK rebuilds it in place, keeping
# its middle. No geometry here: TileNiche.update_at! does it.
module InteriorPro
  class TileNicheEditTool < TileNicheDeleteTool
    BLUE = [40, 110, 200].freeze unless const_defined?(:BLUE, false)

    def activate
      super
      Sketchup.set_status_text('Edit Niche: click a niche to change its sizes. Esc = done.', SB_PROMPT)
    end

    def onMouseMove(flags, x, y, view)
      super
      view.tooltip = @hit ? 'Click to edit this niche' : ''
    end

    def onLButtonDown(_flags, x, y, view)
      hit = pick(view, x, y)
      if hit.nil?
        Sketchup.set_status_text('Edit Niche: that is not a niche - click inside one.', SB_PROMPT)
        return
      end
      wall, idx, n = hit
      f = lambda { |v| Sketchup.format_length(v.to_f) }
      res = UI.inputbox(['Width', 'Height', 'Depth into the wall', 'Height from the floor'],
                        [f.call(n[:w]), f.call(n[:h]), f.call(n[:depth]), f.call(n[:z0])], 'Edit Niche')
      return unless res
      w, h, d, s = res.map { |t| parse_len(t) }
      if w.nil? || h.nil? || d.nil? || s.nil? || w < 1.0 || h < 1.0 || d <= 0.25 || s < 0.0
        UI.messagebox('Type the four sizes, e.g.  12   24   4   48')
        return
      end
      InteriorPro::TileNiche.update_at!(wall, idx, w: w, h: h, depth: d, sill: s)
      @hit = nil
      view.invalidate
    end

    def parse_len(t)
      q = t.to_s.strip.tr('׳', "'").tr('״', '"')
      return nil if q.empty?
      q.to_l.to_f
    rescue StandardError
      nil
    end

    def color
      BLUE
    end
  end
end

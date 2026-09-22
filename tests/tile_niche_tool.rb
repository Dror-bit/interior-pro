# encoding: utf-8
# Interior Pro - THE NICHE TOOL (2026-09-20, rebuilt 2026-09-22)
#
# HIS FLOW, THE WINDOW'S FLOW (2026-09-22, his words: "זה צריך להיות כמו
# החלונות - פותחים את הכפתור ואז יש תפריט לאורך לגובה ולעומק, גובה
# הניצ מהריצפה, ואז ממקמים את הניץ עם ריבוע רפאים"). So:
#   1. the button opens ONE window: width, height, depth, height off the
#      floor - 36 x 18, 4" deep, 42" up the first time (his numbers),
#   2. a GHOST box follows the mouse along the wall face, green where it
#      fits and red where it would run into a wall or out of the top,
#   3. a click cuts it, and the tool stays on for the next one, like the
#      window tool does. Esc leaves.
#
# The first version (two clicks, drag the size) was MY guess at "the same
# mechanism as an area" - he corrected it the same day. The drag is gone.
#
# Every point still comes through TileWallTool#face_point, so the point
# law holds: the ghost's middle locks on the wall's middle, on an
# opening's edge or middle, and the ring shows it. The niche's middle is
# the point he is holding, the height comes from the window.
module InteriorPro
  class TileNicheTool < TileWallTool
    GHOST_OUT = 1.0 unless const_defined?(:GHOST_OUT, false)
    def self.last
      # His numbers (2026-09-22): 36" wide, 18" tall, 42" off the floor.
      @last ||= { w: 36.0, h: 18.0, depth: InteriorPro::TileNiche::DEFAULT_DEPTH, sill: 42.0 }
    end

    # Where the niche would sit, held by its middle. PURE.
    def self.ghost_u0(u_mid, w)
      u_mid.to_f - w.to_f / 2.0
    end

    # Does it fit on the clear run of this face and under the top of the
    # wall? PURE - lo/hi are what TileWall.face_limits gives.
    def self.fits?(u0, w, z0, h, lo, hi, wall_h, eps = 1.0e-6)
      u0.to_f >= lo.to_f - eps && u0.to_f + w.to_f <= hi.to_f + eps &&
        z0.to_f >= -eps && z0.to_f + h.to_f <= wall_h.to_f + eps
    end

    def activate
      s = ask_size
      if s.nil?
        Sketchup.active_model.select_tool(nil)
        return
      end
      # height: nil and run: false keep the parent's drag and corner hop
      # out of it - neither means anything for a niche.
      @cfg = { height: nil, run: false, wrap: false }.merge(s)
      reset
      @fits = false
      status
    end

    def ask_size
      last = InteriorPro::TileNicheTool.last
      f = lambda { |v| Sketchup.format_length(v.to_f) }
      res = UI.inputbox(['Width', 'Height', 'Depth into the wall', 'Height from the floor'],
                        [f.call(last[:w]), f.call(last[:h]), f.call(last[:depth]), f.call(last[:sill])],
                        'Niche')
      return nil unless res
      w, h, d, s = res.map { |t| parse_len(t) }
      if w.nil? || h.nil? || d.nil? || s.nil? || w < 1.0 || h < 1.0 || d <= 0.25 || s < 0.0
        UI.messagebox('Type the four sizes, e.g.  12   24   4   48')
        return nil
      end
      InteriorPro::TileNicheTool.last.merge!(w: w, h: h, depth: d, sill: s)
      { w: w, h: h, depth: d, sill: s }
    end

    def status
      Sketchup.set_status_text(
        "Niche #{Sketchup.format_length(@cfg[:w])} x #{Sketchup.format_length(@cfg[:h])}: " \
        'move along a wall face and click to place it. Green = fits, red = does not. Esc = done.', SB_PROMPT
      )
    end

    # Nothing is typed into this tool - the sizes live in the window.
    def onUserText(_text, _view); end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onMouseMove(_flags, x, y, view)
      @hover = face_point(view, x, y)
      @fits = false
      if @hover && @frame
        u0 = InteriorPro::TileNicheTool.ghost_u0(@hover[:u], @cfg[:w])
        lo, hi = InteriorPro::TileWall.face_limits(@wall, @frame, @hover[:u])
        @fits = InteriorPro::TileNicheTool.fits?(u0, @cfg[:w], @cfg[:sill], @cfg[:h], lo, hi, @hgt)
        view.tooltip = "#{Sketchup.format_length(@cfg[:w])} x #{Sketchup.format_length(@cfg[:h])}, " \
                       "#{Sketchup.format_length(@cfg[:depth])} deep" + (@fits ? '' : ' - does not fit here')
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      p = face_point(view, x, y)
      trace_click(x, y, p)
      if p.nil? || @frame.nil?
        Sketchup.set_status_text('Niche: click on the FACE of an Interior Pro wall.', SB_PROMPT)
        return
      end
      u0 = InteriorPro::TileNicheTool.ghost_u0(p[:u], @cfg[:w])
      lo, hi = InteriorPro::TileWall.face_limits(@wall, @frame, p[:u])
      unless InteriorPro::TileNicheTool.fits?(u0, @cfg[:w], @cfg[:sill], @cfg[:h], lo, hi, @hgt)
        Sketchup.set_status_text('Niche: it does not fit there (red) - move it along the wall.', SB_PROMPT)
        puts "[TileNiche] does not fit: u #{u0.round(2)}..#{(u0 + @cfg[:w]).round(2)} on clear run " \
             "#{lo.round(2)}..#{hi.round(2)}, top #{(@cfg[:sill] + @cfg[:h]).round(2)} of #{@hgt.round(2)}"
        return
      end
      n = InteriorPro::TileNiche.add!(wall: @wall, side: @side, u0: u0, z0: @cfg[:sill],
                                      w: @cfg[:w], h: @cfg[:h], depth: @cfg[:depth])
      UI.messagebox('No niche was cut - see the Ruby Console for the reason.') if n.nil?
      # The wall was just cut - measure its face again on the next move.
      @frame = nil
      @hover = nil
      status
      view.invalidate
    end

    def draw(view)
      if @hover && @frame
        u0 = InteriorPro::TileNicheTool.ghost_u0(@hover[:u], @cfg[:w])
        u1 = u0 + @cfg[:w]
        z0 = @cfg[:sill]
        z1 = z0 + @cfg[:h]
        # IN FRONT OF THE TILE, NOT INSIDE IT (2026-09-22, his words: "הטיל
        # בולט מהקיר טיפה אז לא רואים את הקופסא כי היא נבלעת בתוך הטיל").
        # The tile stands 5/8" off the wall; the ghost's front stands a
        # whole inch off, so it shows on a tiled wall too.
        go = GHOST_OUT
        front = [pt3(u0, z0, go), pt3(u1, z0, go), pt3(u1, z1, go), pt3(u0, z1, go)]
        d = -@cfg[:depth].to_f
        back = [pt3(u0, z0, d), pt3(u1, z0, d), pt3(u1, z1, d), pt3(u0, z1, d)]
        # A GHOST HE CAN SEE (2026-09-22, his ask: "כפתור הרפאים צריך
        # להיות טיפה יותר בולט"): the front is FILLED, see-through, and
        # the outline is thicker.
        col = @fits ? [40, 150, 60] : [200, 40, 40]
        view.drawing_color = Sketchup::Color.new(*col, 70)
        view.draw(GL_QUADS, front)
        view.drawing_color = Sketchup::Color.new(*col)
        view.line_stipple = ''
        view.line_width = 4
        view.draw(GL_LINE_LOOP, front)
        view.line_width = 1
        view.line_stipple = '-'
        view.draw(GL_LINE_LOOP, back)
        4.times { |i| view.draw(GL_LINES, [front[i], back[i]]) }
        draw_ring(view, @hover)
      end
      begin
        @ip.draw(view) if @ip && @ip.valid? && @ip.display?
      rescue StandardError
        nil
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@wall.bounds) if @wall&.valid?
      bb
    end
  end
end

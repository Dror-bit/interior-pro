# encoding: utf-8
# Interior Pro - THE ELECTRICAL TOOL (2026-10-12, step 1)
#
# His words: "כל מה שאני שם על הקיר אני צריך לקבוע לו את הגובה כמובן
# שזה יהיה בקופסת רפאים".
#
#   1. the Electrical button opens the window (ElectricalDialog): outlet or
#      switch (1 to 5), and the height to its middle,
#   2. a GHOST box follows the mouse along a wall face - ONLY sideways, the
#      height is the window's - green where it fits, red on a door, a
#      window, a niche or past the end of the wall,
#   3. a click places it; a typed number + Enter places it that far from
#      the NEARER corner to its middle. The tool stays on; Esc leaves.
#
# INHERITS the plumbing tool (CLAUDE.md: a new tool = a working tool,
# inherited), which inherits the niche and tile tools - the point law, the
# ring, Esc and the typed corner distance come with it. Only what is
# different is here: the window, the parts, the check and the placing.
module InteriorPro
  class ElectricalTool < FixtureTool
    LIB = InteriorPro::ElectricalLibrary unless const_defined?(:LIB, false)
    # THE GHOST STANDS AN INCH OFF THE WALL (CLAUDE.md), or a plate a
    # quarter inch thick disappears into the tile.
    GHOST_OUT = 1.0 unless const_defined?(:GHOST_OUT, false)

    def activate
      unless LIB::USE_ELECTRICAL
        puts '[Electrical] USE_ELECTRICAL is off - nothing to do'
        Sketchup.active_model.select_tool(nil)
        return
      end
      reset
      @fits = false
      if @pcfg.nil?
        InteriorPro::ElectricalDialog.show do |cfg|
          @pcfg = cfg
          setup_size!
          status
        end
      else
        setup_size!
      end
      status
    end

    def setup_size!
      @parts = LIB.layout(Sketchup.active_model, @pcfg)
      @cfg = { parts: @parts.length, height: nil, run: false, wrap: false }
    end

    def label
      k = LIB.kind_ok(@pcfg && @pcfg['kind'])
      return 'Outlet' if k == 'outlet'
      g = LIB.gangs_ok(k, @pcfg['gangs'])
      g == 1 ? 'Switch' : "#{g} switches"
    end

    def status
      if @cfg.nil?
        Sketchup.set_status_text('Electrical: choose in the window first.', SB_PROMPT)
        return
      end
      Sketchup.vcb_label = 'From corner'
      Sketchup.set_status_text(
        "#{label} at #{Sketchup.format_length(@pcfg['height'].to_f)}: move along a wall face and click, " \
        'or type how far from the nearer corner (to its middle) + Enter. Green = fits. Esc = done.', SB_PROMPT
      )
    end

    # The plain wall point (the tile tool's), not the plumbing tool's
    # "only on a tiled area" - an outlet goes on any inside wall face.
    def face_point(view, x, y)
      TileWallTool.instance_method(:face_point).bind(self).call(view, x, y)
    end

    # [fits, lo, hi]. Outside the house = not caught at all (no ghost),
    # like the plumbing tool. On a hole = red, so he sees why.
    def fits_at?(u_line)
      @chk = LIB.check(@wall, @side, @frame, u_line, @parts, @hgt)
      @no_tile = @chk[:outside]
      @on_hole = false
      [@chk[:ok], @chk[:lo], @chk[:hi]]
    end

    def onLButtonDown(_flags, x, y, view)
      return if @cfg.nil?
      p = face_point(view, x, y)
      trace_click(x, y, p)
      if p.nil? || @frame.nil?
        LIB.trace("click #{x},#{y}: no wall face under the mouse")
        Sketchup.set_status_text('Electrical: click on the FACE of an Interior Pro wall.', SB_PROMPT)
        return
      end
      fits_at?(p[:u])
      if @no_tile
        LIB.trace("click #{x},#{y}: wall #{@wall.get_attribute('InteriorPro', 'id').to_s[0, 8]} side #{@side} " \
                  'is the outside of the house - not caught')
        return
      end
      place_at(p[:u], view)
    end

    def place_at(u_mid, view)
      ok, lo, hi = fits_at?(u_mid)
      wid = @wall.get_attribute('InteriorPro', 'id').to_s[0, 8]
      unless ok
        why = @chk[:outside] ? 'outside of the house' : (@chk[:rects].empty? ? 'nothing to place' : 'red: on a door/window/niche or past the wall end')
        Sketchup.set_status_text("Electrical: it does not fit there (#{why}) - move it along the wall.", SB_PROMPT)
        LIB.trace("#{label} NOT placed: wall #{wid} side #{@side} u #{u_mid.round(2)} on #{lo.round(2)}..#{hi.round(2)}, " \
                  "rect #{@chk[:rects].map { |r| r.map { |v| v.round(2) } }.inspect}, #{why}")
        return
      end
      grp = LIB.place!(wall: @wall, side: @side, fr: @frame, u: u_mid, cfg: @pcfg, parts: @parts, outs: @chk[:outs])
      LIB.trace("#{label} #{grp ? 'PLACED' : 'FAILED'}: wall #{wid} side #{@side} u #{u_mid.round(2)} " \
                "height #{@pcfg['height'].to_f.round(2)} turn #{LIB.turn_of(@pcfg)} off the wall #{@chk[:outs].first.to_f.round(3)}")
      UI.messagebox('Nothing was placed - see the Ruby Console for the reason.') if grp.nil?
      status
      view.invalidate
    end

    def draw(view)
      if @cfg && @hover && @frame && @chk
        col = @fits ? [40, 150, 60] : [200, 40, 40]
        @parts.each_with_index do |p, i|
          u0, u1, z0, z1 = @chk[:rects][i] || next
          b0 = @chk[:outs][i].to_f + 0.1
          o = @chk[:outs][i].to_f + [p[:maxy] - p[:miny], GHOST_OUT].max
          back  = [pt3(u0, z0, b0), pt3(u1, z0, b0), pt3(u1, z1, b0), pt3(u0, z1, b0)]
          front = [pt3(u0, z0, o), pt3(u1, z0, o), pt3(u1, z1, o), pt3(u0, z1, o)]
          view.drawing_color = Sketchup::Color.new(*col, 70)
          view.draw(GL_QUADS, front)
          view.drawing_color = Sketchup::Color.new(*col)
          view.line_stipple = ''
          view.line_width = 3
          view.draw(GL_LINE_LOOP, front)
          view.line_width = 1
          view.line_stipple = '-'
          view.draw(GL_LINE_LOOP, back)
          4.times { |k| view.draw(GL_LINES, [front[k], back[k]]) }
        end
        draw_ring(view, @hover)
      end
      begin
        @ip.draw(view) if @ip && @ip.valid? && @ip.display?
      rescue StandardError
        nil
      end
    end
  end
end

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
        InteriorPro::ElectricalDialog.show(group: group) do |cfg|
          @pcfg = cfg
          setup_size!
          status
        end
      else
        setup_size!
      end
      status
    end

    # Which window this button opens (Electrical / Lighting).
    def group
      'electrical'
    end

    def setup_size!
      @parts = LIB.layout(Sketchup.active_model, @pcfg)
      @cfg = { parts: @parts.length, height: nil, run: false, wrap: false }
    end

    def label
      k = LIB.kind_ok(@pcfg && @pcfg['kind'])
      return LIB.kinds[k][:label] unless k == 'switch'
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
                "height #{@pcfg['height'].to_f.round(2)} turn #{LIB.turn_of(@pcfg)}#{LIB.countertop_of(@pcfg) ? ' COUNTERTOP' : ''} off the wall #{@chk[:outs].first.to_f.round(3)}")
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

  # THE LIGHTING BUTTON (2026-10-12, his words: "הם אומנם באותו הסרגל אבל לא
  # בגלריה"): the same tool, its own window with the lighting kinds only.
  class LightingTool < ElectricalTool
    def group
      'lighting'
    end

    # ---- ON THE CEILING (2026-10-12, his pick "1": "קליק על התקרה בתוך
    # החדר, והמנורה נתלית שם" - the distances he sets later in 2D). A
    # ceiling light or fan: the mouse ray meets the first Interior Pro
    # ceiling (from above through it, or from below), or a point the mouse
    # locked onto (corner / middle) with a ceiling over it. The ghost is
    # the box of his file hanging from that spot. A click hangs it.
    def ceiling_mode?
      @pcfg && LIB::USE_CEILING_MOUNT && LIB.ceiling?(@pcfg['kind'])
    end

    def setup_size!
      return super unless ceiling_mode?
      d = LIB.definition_for(Sketchup.active_model, @pcfg['kind'], 1, @pcfg['product'])
      @parts = d ? [{ defn: d }] : []
      @cbox = d ? InteriorPro::FixtureLibrary.visible_bounds(d) : nil
      @ceils = LIB.ceilings
      @cfg = { parts: @parts.length, height: nil, run: false, wrap: false }
      LIB.trace("#{label} #{@pcfg['product']}: #{@ceils.length} ceilings in the model#{d ? '' : ', FILE NOT LOADED'}")
    end

    def status
      return super unless @cfg && ceiling_mode?
      Sketchup.vcb_label = ''
      Sketchup.set_status_text("#{label}: click on the ceiling of a room - it hangs there. Green = on a ceiling. Esc = done.", SB_PROMPT)
    end

    # { c: ceiling, x:, y:, kind: :corner / :middle / nil } or nil
    def ceiling_point(view, x, y)
      @ceils ||= LIB.ceilings
      @ip ||= Sketchup::InputPoint.new
      @ip.pick(view, x, y)
      if @ip.valid? && (@ip.vertex || @ip.degrees_of_freedom.zero?)
        pos = @ip.position
        c = LIB.ceiling_over(@ceils, pos.x.to_f, pos.y.to_f)
        return { c: c, x: pos.x.to_f, y: pos.y.to_f, kind: @ip.vertex ? :corner : :middle } if c
      end
      eye, dir = view.pickray(x, y)
      hit = LIB.ceiling_hit(@ceils, [eye.x, eye.y, eye.z].map(&:to_f), [dir.x, dir.y, dir.z].map(&:to_f))
      hit && { c: hit[0], x: hit[1], y: hit[2], kind: nil }
    end

    def onMouseMove(flags, x, y, view)
      return super unless @cfg && ceiling_mode?
      return if @parts.to_a.empty?
      @chover = ceiling_point(view, x, y)
      view.tooltip = @chover ? '' : 'Not on a ceiling'
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      return super unless @cfg && ceiling_mode?
      h = ceiling_point(view, x, y)
      if h.nil?
        LIB.trace("#{label} click #{x},#{y}: no ceiling under the mouse")
        Sketchup.set_status_text('Lighting: click on the CEILING of a room (no ceiling there - build the ceilings first).', SB_PROMPT)
        return
      end
      cid = h[:c][:grp].get_attribute('InteriorPro', 'id')
      rows, cols = @pcfg['rows'].to_i, @pcfg['cols'].to_i
      if rows * cols > 1 && defined?(InteriorPro::PlanEditor) && InteriorPro::PlanEditor::USE_LIGHT_SPREAD
        # HOW MANY IN THE ROOM (2026-10-13 19:18): spread evenly over the ceiling he clicked, one undo step
        xs = h[:c][:poly].map(&:first)
        ys = h[:c][:poly].map(&:last)
        pts = InteriorPro::PlanEditor.spread_points([xs.min, ys.min, xs.max, ys.max], rows, cols, h[:c][:poly].flatten)
        model = Sketchup.active_model
        model.start_operation('Spread Lights', true)
        hung = 0
        pts.each do |px, py|
          c = LIB.ceiling_over(LIB.ceilings, px, py)
          next unless c
          hung += 1 if LIB.place_on_ceiling!(ceiling: c, x: px, y: py, cfg: @pcfg, op: false)
        end
        model.commit_operation
        @ceils = LIB.ceilings
        LIB.trace("#{label} SPREAD #{rows}x#{cols}: #{hung} of #{pts.length} hung on ceiling #{cid} (#{@pcfg['product']})")
        status
        view.invalidate
        return
      end
      grp = LIB.place_on_ceiling!(ceiling: h[:c], x: h[:x], y: h[:y], cfg: @pcfg)
      # a ceiling built again with a hole is a new group: read them again
      @ceils = LIB.ceilings
      LIB.trace("#{label} #{grp ? 'HUNG' : 'FAILED'}: #{@pcfg['product']} on ceiling #{cid} " \
                "x #{h[:x].round(2)} y #{h[:y].round(2)} z #{h[:c][:z].round(2)}#{h[:kind] ? " locked #{h[:kind]}" : ''}")
      UI.messagebox('Nothing was placed - see the Ruby Console for the reason.') if grp.nil?
      status
      view.invalidate
    end

    def onUserText(text, view)
      return super unless @cfg && ceiling_mode?
      Sketchup.set_status_text('On the ceiling: click where it goes - the distances are set in 2D.', SB_PROMPT)
    end

    def draw(view)
      return super unless @cfg && ceiling_mode?
      if @chover && @cbox
        b = @cbox
        x0, x1 = @chover[:x] + b.min.x, @chover[:x] + b.max.x
        y0, y1 = @chover[:y] + b.min.y, @chover[:y] + b.max.y
        z0, z1 = @chover[:c][:z] + b.min.z, @chover[:c][:z] + b.max.z
        p = ->(xx, yy, zz) { Geom::Point3d.new(xx, yy, zz) }
        top = [p.(x0, y0, z1), p.(x1, y0, z1), p.(x1, y1, z1), p.(x0, y1, z1)]
        bot = [p.(x0, y0, z0), p.(x1, y0, z0), p.(x1, y1, z0), p.(x0, y1, z0)]
        view.drawing_color = Sketchup::Color.new(40, 150, 60, 70)
        view.draw(GL_QUADS, top)
        view.drawing_color = Sketchup::Color.new(40, 150, 60)
        view.line_stipple = ''
        view.line_width = 3
        view.draw(GL_LINE_LOOP, top)
        view.line_width = 1
        view.line_stipple = '-'
        view.draw(GL_LINE_LOOP, bot)
        4.times { |k| view.draw(GL_LINES, [top[k], bot[k]]) }
        # the spot itself, in the lock colour (green corner, cyan middle)
        col = { corner: [0, 170, 0], middle: [0, 170, 200] }[@chover[:kind]] || [40, 150, 60]
        c = p.(@chover[:x], @chover[:y], @chover[:c][:z])
        r = begin
          view.pixels_to_model(6, c)
        rescue StandardError
          1.0
        end
        ring = (0..16).map { |i| a = i * 2.0 * Math::PI / 16.0; p.(c.x + Math.cos(a) * r, c.y + Math.sin(a) * r, c.z) }
        view.drawing_color = Sketchup::Color.new(*col)
        view.line_stipple = ''
        view.line_width = 3
        view.draw(GL_LINE_STRIP, ring)
      end
      begin
        @ip.draw(view) if @ip && @ip.valid? && @ip.display?
      rescue StandardError
        nil
      end
    end
  end
end

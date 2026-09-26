# encoding: utf-8
# Interior Pro - THE PLUMBING TOOL (2026-09-25, step 1)
#
# His words (2026-09-24): "אני רוצה שהמקלחת נגיד תופיע בגובה שיקבע מראש
# ואפשרי למקם אותה גם עם כמו חלון רפאים והיא תזוז רק על הגובה שאני אגדיר
# כמו כן שאפשרי לקבוע לה כמה היא תהיה רחוקה מהפינה".
#
#   1. the Plumbing button opens the window (FixtureDialog): kind,
#      product, height from the floor,
#   2. a GHOST box the size of the product follows the mouse along a wall
#      face - ONLY sideways, the height is the window's - green where it
#      fits, red where it runs into a wall or out of the top,
#   3. a click places it; a typed number + Enter places it that far from
#      the NEARER corner to its middle. The tool stays on; Esc leaves.
#
# INHERITS the niche tool (CLAUDE.md: a new tool = a working tool,
# inherited), so every point comes through TileWallTool#face_point - the
# point law holds and the ring shows where it locked. The ghost stands
# OUT of the wall (a fixture sits on the face), not into it like a niche.
module InteriorPro
  class FixtureTool < TileNicheTool
    def initialize(cfg = nil)
      @pcfg = cfg
    end

    def activate
      unless InteriorPro::FixtureLibrary::USE_FIXTURES
        puts '[Fixture] USE_FIXTURES is off - nothing to do'
        Sketchup.active_model.select_tool(nil)
        return
      end
      reset
      @fits = false
      if @pcfg.nil?
        InteriorPro::FixtureDialog.show do |cfg|
          @pcfg = cfg
          setup_size!
          status
        end
      else
        setup_size!
      end
      status
    end

    # The parts to place (a toilet = one part, a shower set = up to four),
    # each with its own box around its pipe point - FixtureLibrary.layout.
    def setup_size!
      @parts = InteriorPro::FixtureLibrary.layout(Sketchup.active_model, @pcfg)
      @cfg = { parts: @parts.length, height: nil, run: false, wrap: false }
      puts "[Fixture] nothing to place - no part of #{@pcfg['product']} could be loaded" if @parts.empty?
    end

    def status
      if @cfg.nil?
        Sketchup.set_status_text('Plumbing: choose in the window first.', SB_PROMPT)
        return
      end
      Sketchup.vcb_label = 'From corner'
      Sketchup.set_status_text(
        "#{@pcfg['product']}: move along a wall face and click, " \
        'or type how far from the nearer corner (to its line) + Enter. Green = fits. Esc = done.', SB_PROMPT
      )
    end

    def enableVCB?
      true
    end

    # THE TILE UNDER THE MOUSE DECIDES (2026-09-25, his words: "קשה לו
    # להיקלט על קירות מסויימים"). Measured in tile_tool_trace.txt: the same
    # spot on the shower's tile (y 401.88) came back as side "a" one time
    # and side "b" the next - the ray hits the TILE, not the wall, so the
    # wall's side was guessed, and on the wrong side no tile was found.
    # For a shower head the tiled area actually under the cursor now says
    # which wall and which side. No tile under the cursor = nothing caught.
    def face_point(view, x, y)
      p = super
      return p unless @pcfg && InteriorPro::FixtureLibrary.on_tile?(@pcfg['kind'])
      g = tile_area_at(view, x, y)
      return nil if g.nil?
      wall = InteriorPro::TileWall.wall_by_id(g.get_attribute('InteriorPro', 'wall_id'))
      side = g.get_attribute('InteriorPro', 'side').to_s
      return nil unless wall&.valid?
      return p if p && p[:wall].equal?(wall) && p[:side] == side
      fr = InteriorPro::TileWall.frame_for(wall, side)
      return nil if fr.nil?
      @wall = wall
      @side = side
      @frame = fr
      @len = fr[:len]
      @hgt = InteriorPro::TileWall.wall_height(wall)
      @holes = InteriorPro::TileWall.openings_for(wall, fr)
      pos = p ? p[:pos] : (@ip && @ip.position)
      return nil if pos.nil?
      u = (pos.x - fr[:ox]) * fr[:ux] + (pos.y - fr[:oy]) * fr[:uy]
      { u: u, z: pos.z - fr[:floor_z], kind: nil, wall: wall, side: side, pos: pos }
    end

    def tile_area_at(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |e|
          return e if e.is_a?(Sketchup::Group) && e.valid? && e.get_attribute('InteriorPro', 'type') == 'tile_wall'
        end
      end
      nil
    rescue StandardError => e
      puts "[Fixture] tile pick failed: #{e.message}"
      nil
    end

    def limits_at(u)
      InteriorPro::TileWall.face_limits(@wall, @frame, u)
    end

    # Returns [fits, lo, hi]. The one check lives in FixtureLibrary.check,
    # shared with the edit: inside the clear run and under the top, a
    # tiled area under every part of a shower set (it then stands on the
    # tile face - @outs), and no window or niche under any part.
    def fits_at?(u_line)
      @chk = InteriorPro::FixtureLibrary.check(@wall, @side, @frame, u_line, @parts, @pcfg['kind'], @hgt)
      @no_tile = @chk[:no_tile]
      @on_hole = @chk[:on_hole]
      [@chk[:ok], @chk[:lo], @chk[:hi]]
    end

    def onMouseMove(_flags, x, y, view)
      return if @cfg.nil? || @parts.to_a.empty?
      @hover = face_point(view, x, y)
      @fits = false
      if @hover && @frame
        @fits, lo, hi = fits_at?(@hover[:u])
        # NOT EVEN RED (2026-09-25, his words: "עדיף שאפילו לא יהיה אדום ...
        # שהוא בכלל לא יקלוט אותו אלא יקלוט רק את הבפנים"). Off the tile a
        # shower head sees nothing: no ghost, no ring, no tooltip.
        if @no_tile || @on_hole
          @hover = nil
          view.tooltip = ''
          view.invalidate
          return
        end
        cd = InteriorPro::FixtureLibrary.corner_dist(@hover[:u], lo, hi)
        Sketchup.vcb_value = Sketchup.format_length(cd)
        why = @no_tile ? ' - only on a tiled wall, inside' : ' - does not fit here'
        view.tooltip = "#{Sketchup.format_length(cd)} from the corner" + (@fits ? '' : why)
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      return if @cfg.nil?
      p = face_point(view, x, y)
      trace_click(x, y, p)
      if p.nil? || @frame.nil?
        Sketchup.set_status_text('Plumbing: click on the FACE of an Interior Pro wall.', SB_PROMPT)
        return
      end
      # off the tile a shower head does not catch the click at all
      fits_at?(p[:u])
      return if @no_tile || @on_hole
      place_at(p[:u], view)
    end

    # Typed: how far from the NEARER corner (nearer to the mouse) to the
    # middle of the fixture, on the wall the mouse is on.
    def onUserText(text, view)
      return if @cfg.nil?
      if @hover.nil? || @frame.nil?
        UI.messagebox('Move the mouse onto the wall first, near the corner to measure from.')
        return
      end
      dist = parse_len(text)
      if dist.nil? || dist < 0.0
        UI.messagebox('Type how far from the corner, e.g.  18  or  1\'6"')
        return
      end
      lo, hi = limits_at(@hover[:u])
      u = InteriorPro::FixtureLibrary.u_from_corner(dist, lo, hi, @hover[:u])
      place_at(u, view)
    end

    def place_at(u_mid, view)
      ok, lo, hi = fits_at?(u_mid)
      unless ok
        Sketchup.set_status_text(@no_tile ? 'Plumbing: a shower head goes only on a TILED wall, inside the house.' :
                                            'Plumbing: it does not fit there (red) - move it along the wall.', SB_PROMPT)
        puts "[Fixture] does not fit: line #{u_mid.round(2)} on clear run #{lo.round(2)}..#{hi.round(2)}, " \
             "parts #{@chk[:rects].map { |r| r.map { |v| v.round(1) } }.inspect}, wall top #{@hgt.round(2)}"
        return
      end
      inst = InteriorPro::FixtureLibrary.place!(wall: @wall, side: @side, fr: @frame, u: u_mid, cfg: @pcfg,
                                               parts: @parts, outs: @chk[:outs])
      UI.messagebox('Nothing was placed - see the Ruby Console for the reason.') if inst.nil?
      status
      view.invalidate
    end

    def draw(view)
      if @cfg && @hover && @frame && @chk
        col = @fits ? [40, 150, 60] : [200, 40, 40]
        @parts.each_with_index do |p, i|
          u0, u1, z0, z1 = @chk[:rects][i] || next
          b0 = @chk[:outs][i].to_f + 0.1
          o = @chk[:outs][i].to_f + (p[:maxy] - p[:miny])
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
        # the one line the whole set stands on
        if @parts.length > 1
          zs = @chk[:rects].flat_map { |r| [r[2], r[3]] }
          view.drawing_color = Sketchup::Color.new(200, 60, 40)
          view.line_width = 1
          view.line_stipple = '_'
          view.draw(GL_LINES, [pt3(@hover[:u], zs.min, 0.8), pt3(@hover[:u], zs.max, 0.8)])
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

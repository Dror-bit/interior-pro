# encoding: utf-8
# Interior Pro - STRETCH A TILED AREA (2026-09-18)
#
# His words: "ידיות מתיחה לשטח אריחים קיים - קליק על השטח, גרירת קצה,
# בנייה מחדש", and when asked where the handles go he chose FOUR: the
# middle of each side, each one moving that side only. And: "אפשרי גם
# להזין מידה שלוחצים על הידית?" - yes, type a number and Enter.
#
# The tool OWNS NO LAYOUT and BUILDS NO GEOMETRY. It changes the four
# numbers already stored on the area - u0, z0, area_w, area_h - and hands
# the rebuild to TileWall.rebuild_area!, which reads everything else off
# the area itself. So a stretched area cannot drift away from a drawn one.
#
# THE POINT LAW (CLAUDE.md): the move and the click go through the SAME
# method (edge_value), and the ring is drawn where it locked. Green = a
# corner of the wall or of an opening, cyan = a middle, magenta = one of
# the heights a tiler actually asks for.
module InteriorPro
  class TileWallStretchTool
    # Kill switch: false = the button says so and does nothing.
    USE_STRETCH_TOOL = true unless const_defined?(:USE_STRETCH_TOOL, false)

    SNAP_PX   = 10 unless const_defined?(:SNAP_PX, false)
    HANDLE_PX = 6  unless const_defined?(:HANDLE_PX, false)
    GRAB_PX   = 12 unless const_defined?(:GRAB_PX, false)
    MIN_SIDE  = 1.0 unless const_defined?(:MIN_SIDE, false)

    GREEN   = [0, 170, 60].freeze   unless const_defined?(:GREEN, false)
    CYAN    = [0, 160, 190].freeze  unless const_defined?(:CYAN, false)
    MAGENTA = [190, 0, 160].freeze  unless const_defined?(:MAGENTA, false)
    ORANGE  = [235, 120, 0].freeze  unless const_defined?(:ORANGE, false)

    EDGES = %i[u0 u1 z0 z1].freeze unless const_defined?(:EDGES, false)

    def activate
      unless USE_STRETCH_TOOL
        UI.messagebox('Stretch Tile is switched off (USE_STRETCH_TOOL = false).')
        Sketchup.active_model.select_tool(nil)
        return
      end
      clear
      status
    end

    def deactivate(view)
      view.invalidate
    end

    # SKETCHUP ASKS THIS ONCE, WHEN THE TOOL IS PICKED UP - not again while
    # it runs. It used to answer "only while a handle is held", so by the
    # time he had a handle the box was already off and typing a size did
    # nothing unless he kept the mouse button down. It is always on; a
    # number typed with no handle held is simply ignored in onUserText.
    def enableVCB?
      true
    end

    def onCancel(_reason, view)
      if @grab
        @grab = nil
        @hover = nil
      else
        clear
      end
      status
      view.invalidate
    end

    # ---- picking the area ------------------------------------------------

    def onLButtonDown(_flags, x, y, view)
      if @area.nil?
        pick_area(view, x, y)
        status
        view.invalidate
        return
      end
      if @grab.nil?
        e = handle_at(view, x, y)
        if e
          @grab = e
          @hover = nil
        else
          # A click somewhere else picks another area, or drops this one.
          pick_area(view, x, y)
        end
      else
        v = edge_value(view, x, y)
        apply!(@grab, v[:value]) if v
        @grab = nil
        @hover = nil
      end
      status
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      if @grab
        @hover = edge_value(view, x, y)
        if @hover
          Sketchup.vcb_label = across?(@grab) ? 'Width' : 'Height'
          Sketchup.vcb_value = Sketchup.format_length(size_for(@grab, @hover[:value]))
          view.tooltip = Sketchup.format_length(size_for(@grab, @hover[:value]))
        end
      elsif @area
        @over = handle_at(view, x, y)
        view.tooltip = @over ? 'Drag this side' : ''
      end
      view.invalidate
    end

    # A typed number is the NEW SIZE of the area across the side he
    # grabbed - one number, which is what he asked for.
    def onUserText(text, view)
      return if @grab.nil?
      n = parse_len(text)
      if n.nil? || n < MIN_SIDE
        UI.messagebox("Type how wide or how tall the area should be, e.g.  36  or  3'")
        return
      end
      apply!(@grab, value_for_size(@grab, n))
      @grab = nil
      @hover = nil
      status
      view.invalidate
    end

    def parse_len(s)
      t = s.to_s.strip.tr('׳', "'").tr('״', '"').tr(',', '.')
      return nil if t.empty?
      begin
        t.to_l.to_f
      rescue StandardError
        nil
      end
    end

    # ---- the numbers ------------------------------------------------------

    def across?(edge)
      edge == :u0 || edge == :u1
    end

    def u1
      @u0 + @w
    end

    def z1
      @z0 + @h
    end

    # What the area would measure if this side landed on `value`.
    def size_for(edge, value)
      case edge
      when :u0 then u1 - value
      when :u1 then value - @u0
      when :z0 then z1 - value
      else          value - @z0
      end
    end

    # THE TILE CANNOT WALK THROUGH THE WALL (2026-09-18, his words: "אם
    # אורך הקיר הוא 5 ואני לוחץ 8 על המידה הוא לא יכול ללכת מעבר ל-5").
    # So a side never lands outside the wall's own face, whether he
    # dragged it there or typed it. The wall's own length and height are
    # the limit - the same two numbers the drawing tool locks onto.
    # Along the wall the limit is not the wall's stored length - it is the
    # part of the FACE that is not blocked by the wall standing at each
    # corner, worked out by TileWall.face_limits. Up the wall it is simply
    # the floor and the top of the wall.
    def clamp_value(edge, v)
      lo, hi = across?(edge) ? [@u_lo, @u_hi] : [0.0, @hgt]
      v = v.to_f
      return lo if v < lo
      v > hi ? hi : v
    end

    # And the other way round, for a typed size.
    def value_for_size(edge, size)
      case edge
      when :u0 then u1 - size
      when :u1 then @u0 + size
      when :z0 then z1 - size
      else          @z0 + size
      end
    end

    # ---- the one point method: move AND click come through here ----------

    def edge_value(view, x, y)
      return nil unless @frame
      # One InputPoint that lives as long as the tool - see the same note in
      # tile_wall_tool.rb. Without it a corner never really catches.
      @ip ||= Sketchup::InputPoint.new
      ip = @ip
      begin
        ip.pick(view, x, y)
      rescue StandardError
        ip = view.inputpoint(x, y)
      end
      pos = ip.position
      return nil unless pos
      u = (pos.x - @frame[:ox]) * @frame[:ux] + (pos.y - @frame[:oy]) * @frame[:uy]
      z = pos.z - @frame[:floor_z]
      tol = begin
        view.pixels_to_model(SNAP_PX, pos)
      rescue StandardError
        1.0
      end
      raw = across?(@grab) ? u : z
      # A REAL POINT WINS (CLAUDE.md, 2026-09-18): a corner or the end of a
      # line anywhere in the model, projected onto this face, so he can aim
      # at the wall opposite and have the side reach exactly that far.
      if locked_point?(ip)
        stop = clamp_value(@grab, raw)
        return { value: stop, kind: :corner }
      end
      val, kind = snap(raw, across?(@grab) ? u_lines : z_lines, tol)
      stop = clamp_value(@grab, val)
      { value: stop, kind: (stop - val).abs > 1.0e-9 ? :corner : kind }
    end

    # Did SketchUp's own inference land on a real point, not just a spot on
    # a face? A vertex, or a point with no freedom left to move.
    def locked_point?(ip)
      return false if ip.nil?
      return true if ip.respond_to?(:vertex) && ip.vertex
      ip.respond_to?(:degrees_of_freedom) && ip.degrees_of_freedom.zero?
    rescue StandardError
      false
    end

    def u_lines
      out = [[@u_lo, :corner], [@u_hi, :corner], [(@u_lo + @u_hi) / 2.0, :mid]]
      Array(@holes).each do |hh|
        out << [hh[0], :corner] << [hh[2], :corner] << [(hh[0] + hh[2]) / 2.0, :mid]
      end
      out
    end

    def z_lines
      out = [[0.0, :corner], [@hgt, :corner], [@hgt / 2.0, :mid]]
      [36.0, 48.0, 60.0, 72.0, 84.0, 96.0].each { |v| out << [v, :edge] if v < @hgt - 0.5 }
      Array(@holes).each do |hh|
        out << [hh[1], :corner] << [hh[3], :corner] << [(hh[1] + hh[3]) / 2.0, :mid]
      end
      out
    end

    def snap(v, lines, tol)
      best = nil
      lines.each do |val, kind|
        d = (v - val).abs
        next if d > tol
        best = [val, kind, d] if best.nil? || d < best[2]
      end
      best ? [best[0], best[1]] : [v, nil]
    end

    # ---- the handles -------------------------------------------------------

    # The middle of each side, in [u, z] on the face.
    def handle_uz(edge)
      case edge
      when :u0 then [@u0, @z0 + @h / 2.0]
      when :u1 then [u1,  @z0 + @h / 2.0]
      when :z0 then [@u0 + @w / 2.0, @z0]
      else          [@u0 + @w / 2.0, z1]
      end
    end

    def handle_at(view, x, y)
      return nil unless @frame
      EDGES.find do |e|
        u, z = handle_uz(e)
        sc = begin
          view.screen_coords(pt3(u, z))
        rescue StandardError
          nil
        end
        sc && ((sc.x - x)**2 + (sc.y - y)**2) <= GRAB_PX * GRAB_PX
      end
    end

    # ---- drawing -----------------------------------------------------------

    def pt3(u, z)
      x, y, zz = InteriorPro::TileWall.world(@frame, u, z, @depth + 0.05)
      Geom::Point3d.new(x, y, zz)
    end

    def draw(view)
      return unless @frame
      u0 = @u0
      z0 = @z0
      uu = u1
      zz = z1
      if @grab && @hover
        case @grab
        when :u0 then u0 = @hover[:value]
        when :u1 then uu = @hover[:value]
        when :z0 then z0 = @hover[:value]
        else          zz = @hover[:value]
        end
      end
      view.drawing_color = Sketchup::Color.new(*ORANGE)
      view.line_stipple = @grab ? '-' : ''
      view.line_width = 2
      view.draw(GL_LINE_LOOP, [pt3(u0, z0), pt3(uu, z0), pt3(uu, zz), pt3(u0, zz)])

      EDGES.each { |e| draw_handle(view, e, e == @grab || e == @over) }
      draw_ring(view, @hover) if @grab && @hover
      begin
        @ip.draw(view) if @grab && @ip && @ip.valid? && @ip.display?
      rescue StandardError
        nil
      end
    end

    def draw_handle(view, edge, hot)
      u, z = handle_uz(edge)
      c = pt3(u, z)
      r = begin
        view.pixels_to_model(hot ? HANDLE_PX + 2 : HANDLE_PX, c)
      rescue StandardError
        1.0
      end
      du = across?(edge) ? [r, 0.0] : [0.0, r]
      dv = across?(edge) ? [0.0, r] : [r, 0.0]
      pts = [pt3(u - du[0] - dv[0], z - du[1] - dv[1]),
             pt3(u + du[0] - dv[0], z + du[1] - dv[1]),
             pt3(u + du[0] + dv[0], z + du[1] + dv[1]),
             pt3(u - du[0] + dv[0], z - du[1] + dv[1])]
      view.drawing_color = Sketchup::Color.new(*(hot ? ORANGE : [60, 60, 60]))
      view.line_stipple = ''
      view.line_width = hot ? 4 : 2
      view.draw(GL_LINE_LOOP, pts)
    end

    def ring_color(kind)
      case kind
      when :corner then GREEN
      when :mid    then CYAN
      when :edge   then MAGENTA
      end
    end

    def draw_ring(view, hov)
      c = ring_color(hov[:kind])
      return if c.nil?
      u, z = if across?(@grab)
               [hov[:value], @z0 + @h / 2.0]
             else
               [@u0 + @w / 2.0, hov[:value]]
             end
      centre = pt3(u, z)
      r = begin
        view.pixels_to_model(6, centre)
      rescue StandardError
        1.0
      end
      pts = (0..16).map do |i|
        a = i * 2.0 * Math::PI / 16.0
        pt3(u + Math.cos(a) * r, z + Math.sin(a) * r)
      end
      view.drawing_color = Sketchup::Color.new(*c)
      view.line_stipple = ''
      view.line_width = 3
      view.draw(GL_LINE_STRIP, pts)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@area.bounds) if @area&.valid?
      bb.add(@wall.bounds) if @wall&.valid?
      bb
    end

    # ---- picking, and the change ------------------------------------------

    def pick_area(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      found = nil
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |e|
          next unless e.is_a?(Sketchup::Group)
          found = e if e.get_attribute('InteriorPro', 'type') == 'tile_wall'
        end
        break if found
      end
      if found.nil?
        clear
        Sketchup.set_status_text('Stretch Tile: click on a tiled area.', SB_PROMPT)
        return
      end
      load_area(found)
    end

    def load_area(g)
      a = lambda { |k| g.get_attribute('InteriorPro', k) }
      wall = InteriorPro::TileWall.wall_by_id(a.call('wall_id'))
      if wall.nil?
        clear
        UI.messagebox('That tiled area has lost its wall.')
        return
      end
      fr = InteriorPro::TileWall.frame_for(wall, a.call('side'))
      if fr.nil?
        clear
        UI.messagebox('That wall cannot be read - see the Ruby Console.')
        return
      end
      @area = g
      @wall = wall
      @frame = fr
      @u0 = a.call('u0').to_f
      @z0 = a.call('z0').to_f
      @w  = a.call('area_w').to_f
      @h  = a.call('area_h').to_f
      @depth = a.call('tile_depth').to_f
      @depth = InteriorPro::TileWall::DEFAULT_DEPTH if @depth <= 0.0
      @len = fr[:len]
      @hgt = InteriorPro::TileWall.wall_height(wall)
      # The clear run of face the area he picked up is sitting in - past
      # either end of it there is a wall in the way.
      @u_lo, @u_hi = InteriorPro::TileWall.face_limits(wall, fr, @u0 + @w / 2.0)
      @holes = InteriorPro::TileWall.openings_for(wall, fr)
      @grab = nil
      @hover = nil
      @over = nil
    end

    def apply!(edge, value)
      return if @area.nil? || !@area.valid?
      stop = clamp_value(edge, value)
      # WHAT IS LEFT OVER GOES ROUND THE CORNER (2026-09-18). The side
      # itself still stops at the wall - the tile never passes through it -
      # but the length he asked for beyond that is carried onto the face of
      # the wall standing there, and the two runs meet at the corner.
      over = across?(edge) ? (value.to_f - stop).abs : 0.0
      if over > 1.0e-9 && !across?(edge)
        puts "[TileWallStretch] #{Sketchup.format_length(value.to_f)} is past the top or the floor - " \
             "stopped at #{Sketchup.format_length(stop)}"
      end
      value = stop
      nu0 = @u0
      nz0 = @z0
      nw  = @w
      nh  = @h
      case edge
      when :u0
        nu0 = value
        nw = u1 - value
      when :u1
        nw = value - @u0
      when :z0
        nz0 = value
        nh = z1 - value
      else
        nh = value - @z0
      end
      if nw < MIN_SIDE || nh < MIN_SIDE
        Sketchup.set_status_text('Stretch Tile: that would leave nothing to tile.', SB_PROMPT)
        return
      end
      model = Sketchup.active_model
      aid = @area.get_attribute('InteriorPro', 'id').to_s
      # Read the settings BEFORE the rebuild - rebuild_area! erases this
      # group and makes a new one, so the handle in @area goes stale.
      cfg = settings_of(@area)
      model.start_operation('Interior Pro - Stretch Tile Area', true)
      begin
        @area.set_attribute('InteriorPro', 'u0', nu0)
        @area.set_attribute('InteriorPro', 'z0', nz0)
        @area.set_attribute('InteriorPro', 'area_w', nw)
        @area.set_attribute('InteriorPro', 'area_h', nh)
        built = InteriorPro::TileWall.rebuild_area!(@area, false)
        # THE CORNER SQUARE HAS TO COME BACK (2026-09-18, he caught it:
        # "הרסת את הפינה... תחזיר את הריבוע הריק"). This area was laid
        # while the next wall still had no tile on it, so its corner test
        # found nothing to pull back from. Now that the run has carried on,
        # lay it once more - the group was replaced, so it is found again
        # by its id first.
        if built && over > MIN_SIDE && carry_on!(edge, over, cfg)
          mine = InteriorPro::TileWall.areas_in_model.find do |g|
            g.valid? && g.get_attribute('InteriorPro', 'id').to_s == aid
          end
          InteriorPro::TileWall.rebuild_area!(mine, false) if mine
        end
        model.commit_operation
        unless built
          UI.messagebox('Nothing was rebuilt - see the Ruby Console for the reason.')
          clear
          return
        end
      rescue StandardError => e
        model.abort_operation
        puts "[TileWallStretch] failed: #{e.class}: #{e.message}"
        UI.messagebox('The stretch failed - see the Ruby Console.')
        clear
        return
      end
      # build! erases the old group and makes a new one under the same id.
      again = InteriorPro::TileWall.areas_in_model.find do |g|
        g.valid? && g.get_attribute('InteriorPro', 'id').to_s == aid
      end
      again ? load_area(again) : clear
    end

    # Everything a carried-on run needs to look like this one.
    def settings_of(g)
      a = lambda { |k| g.get_attribute('InteriorPro', k) }
      { z0: a.call('z0').to_f, h: a.call('area_h').to_f,
        card_id: a.call('material_card_id'), tile_w: a.call('tile_w').to_f,
        tile_l: a.call('tile_l').to_f, grout: a.call('pattern_grout').to_f,
        grout_color: a.call('pattern_grout_color'), depth: a.call('tile_depth'),
        mode: a.call('tile_mode'), stagger: a.call('pattern_stagger').to_f }
    end

    # CARRY THE RUN ONTO THE NEXT WALL. `over` is how much further he asked
    # for than this face had left. The run picks up on the face of the wall
    # standing at that corner, and EVERY WALL STARTS ITS OWN LAYOUT - his
    # default; carrying the pattern round the corner is the other option and
    # is not built yet.
    def carry_on!(edge, over, cfg)
      lim = edge == :u1 ? @u_hi : @u_lo
      nb = InteriorPro::TileWall.neighbour_at(@wall, @frame, lim)
      if nb.nil?
        puts '[TileWallStretch] there is no wall round that corner to carry on to'
        return false
      end
      room = nb[:dir] > 0 ? nb[:len] - nb[:u_from] : nb[:u_from]
      w = over > room ? room : over
      if w < MIN_SIDE
        puts '[TileWallStretch] the wall round the corner has no room left'
        return false
      end
      nu0 = nb[:dir] > 0 ? nb[:u_from] : nb[:u_from] - w
      wid = nb[:wall].get_attribute('InteriorPro', 'id').to_s
      here = InteriorPro::TileWall.areas_in_model.find do |g|
        next false unless g.valid?
        next false unless g.get_attribute('InteriorPro', 'wall_id').to_s == wid
        next false unless g.get_attribute('InteriorPro', 'side').to_s == nb[:side].to_s
        u0 = g.get_attribute('InteriorPro', 'u0').to_f
        near = nb[:dir] > 0 ? u0 : u0 + g.get_attribute('InteriorPro', 'area_w').to_f
        (near - nb[:u_from]).abs < 1.5
      end
      if here
        here.set_attribute('InteriorPro', 'u0', nu0)
        here.set_attribute('InteriorPro', 'area_w', w)
        here.set_attribute('InteriorPro', 'z0', cfg[:z0])
        here.set_attribute('InteriorPro', 'area_h', cfg[:h])
        InteriorPro::TileWall.rebuild_area!(here, false)
        puts "[TileWallStretch] carried on round the corner onto wall #{wid} - #{w.round(2)} more"
      else
        InteriorPro::TileWall.build!(
          wall: nb[:wall], side: nb[:side], u0: nu0, z0: cfg[:z0],
          w: w, h: cfg[:h], card_id: cfg[:card_id],
          tile_w: cfg[:tile_w], tile_l: cfg[:tile_l], grout: cfg[:grout],
          grout_color: cfg[:grout_color], depth: cfg[:depth], mode: cfg[:mode],
          stagger: cfg[:stagger], wrap_operation: false
        )
        puts "[TileWallStretch] a new run started round the corner on wall #{wid} - #{w.round(2)} wide"
      end
      true
    rescue StandardError => e
      puts "[TileWallStretch] carrying on round the corner failed: #{e.class}: #{e.message}"
      false
    end

    # ---- state --------------------------------------------------------------

    def clear
      @area = nil
      @wall = nil
      @frame = nil
      @holes = nil
      @grab = nil
      @hover = nil
      @over = nil
      @u0 = @z0 = @w = @h = 0.0
      @depth = InteriorPro::TileWall::DEFAULT_DEPTH
      @len = @hgt = 0.0
      @u_lo = @u_hi = 0.0
    end

    def status
      msg = if @area.nil?
              'Stretch Tile: click on a tiled area to pick it up.'
            elsif @grab
              'Stretch Tile: click where that side should go, or type the new size. Esc = let go.'
            else
              'Stretch Tile: click one of the four handles, then click or type the new size.'
            end
      Sketchup.set_status_text(msg, SB_PROMPT)
    end
  end
end

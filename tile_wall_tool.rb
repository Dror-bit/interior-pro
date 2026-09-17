# encoding: utf-8
# Interior Pro - TILE WALL TOOL (2026-09-17)
#
# Two clicks on a wall face mark the rectangle that gets tiled - the
# shower wall, the fireplace face, a backsplash. This is the tool Chief
# Architect calls a Wall Material Region, and it is what he picked:
# "מלבן בגרירה + ידיות מתיחה".
#
# THE POINT LAW (CLAUDE.md): a tool that takes a point from the mouse
# locks onto corners, ends, middles and edges - AND DRAWS WHERE IT
# LOCKED. Both the move and the click go through the SAME method here
# (face_point), so the ring he sees is the point he gets. That is the
# whole bug that rule exists to prevent.
#
# Green = a corner (the wall's own corner, or an opening's corner).
# Cyan  = a middle. Magenta = on an edge, one axis locked. No ring = the
# raw point on the face, nothing locked.
#
# The tool OWNS NO LAYOUT. It works out four numbers - where on the wall,
# how far up, how wide, how tall - and hands them to TileWall.build!,
# which reads the one grid in tile_grid.rb. Openings are taken out there,
# not here.
module InteriorPro
  class TileWallTool
    SNAP_PX = 10 unless const_defined?(:SNAP_PX, false)
    GREEN   = [0, 170, 60].freeze   unless const_defined?(:GREEN, false)
    CYAN    = [0, 160, 190].freeze  unless const_defined?(:CYAN, false)
    MAGENTA = [190, 0, 160].freeze  unless const_defined?(:MAGENTA, false)

    GROUTS   = ['0', '1/16"', '1/8"', '3/16"', '1/4"', '3/8"'].freeze unless const_defined?(:GROUTS, false)
    GROUT_IN = [0.0, 0.0625, 0.125, 0.1875, 0.25, 0.375].freeze unless const_defined?(:GROUT_IN, false)
    # 'Offset' on the dialog, his word (2026-09-17): how far each second
    # course is pushed along. Stack = every row lined up, 1/2 = brickwork.
    BONDS    = ['Stack', '1/2', '1/3', '1/4'].freeze unless const_defined?(:BONDS, false)
    BOND_V   = [0.0, 0.5, 1.0 / 3.0, 0.25].freeze unless const_defined?(:BOND_V, false)
    LINES_ONLY = '(lines only)' unless const_defined?(:LINES_ONLY, false)
    # How far the tile stands off the wall. His number: "ברוב המקלחות
    # הטיל הוא לפחות 5/8 בולט מהקיר" - so 5/8" is the default, and it is
    # what makes the joints real recesses instead of a drawn line.
    DEPTHS   = ['5/8"', '1/2"', '3/8"', '3/4"', '1/4"', '0 (flat)'].freeze unless const_defined?(:DEPTHS, false)
    DEPTH_IN = [0.625, 0.5, 0.375, 0.75, 0.25, 0.0].freeze unless const_defined?(:DEPTH_IN, false)
    # Tile by tile, or the photo repeated across the area so the pattern
    # IN the picture is the tile (star-and-cross, painted cement tiles, a
    # diagonal chequer). His idea, 2026-09-17.
    MODES  = ['Tile by tile', 'Whole image (pattern)'].freeze unless const_defined?(:MODES, false)
    MODE_V = %w[tiles image].freeze unless const_defined?(:MODE_V, false)

    # What he chose last time, so a second area on the same wall is two
    # clicks and no dialog.
    def self.last
      @last ||= { card: nil, grout: 0.125, bond: 0.0, color: 'light',
                  depth: InteriorPro::TileWall::DEFAULT_DEPTH, mode: 'tiles' }
    end

    def activate
      @cfg = ask_settings
      if @cfg.nil?
        Sketchup.active_model.select_tool(nil)
        return
      end
      reset
      status
    end

    def deactivate(view)
      view.invalidate
    end

    def enableVCB?
      true
    end

    def onCancel(_reason, view)
      reset
      status
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      @hover = face_point(view, x, y)
      if @hover
        if @first
          w = (@hover[:u] - @first[:u]).abs
          h = (@hover[:z] - @first[:z]).abs
          Sketchup.vcb_label = 'Width , Height'
          Sketchup.vcb_value = "#{Sketchup.format_length(w)} , #{Sketchup.format_length(h)}"
          view.tooltip = "#{Sketchup.format_length(w)} x #{Sketchup.format_length(h)}"
        else
          view.tooltip = @hover[:kind] ? @hover[:kind].to_s : ''
        end
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      p = face_point(view, x, y)
      if p.nil?
        Sketchup.set_status_text('Tile Wall: click on the FACE of an Interior Pro wall.', SB_PROMPT)
        return
      end
      if @first.nil?
        @first = p
        @wall = p[:wall]
        @side = p[:side]
      else
        build!(@first, p, view)
      end
      status
      view.invalidate
    end

    # Typed size: "60,96" or "5' , 8'" - width then height, measured from
    # the first corner, in the direction the mouse is pointing.
    def onUserText(text, view)
      return if @first.nil?
      a, b = text.to_s.split(/[,;xX]/).map { |s| parse_len(s) }
      if a.nil? || b.nil? || a <= 0.1 || b <= 0.1
        UI.messagebox("Type width and height, e.g.  60,96  or  5',8'")
        return
      end
      du = @hover && @hover[:u] < @first[:u] ? -a : a
      dz = @hover && @hover[:z] < @first[:z] ? -b : b
      build!(@first, { u: @first[:u] + du, z: @first[:z] + dz }, view)
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

    def draw(view)
      return unless @frame
      if @first && @hover
        pts = rect_pts(@first[:u], @first[:z], @hover[:u], @hover[:z])
        view.drawing_color = Sketchup::Color.new(60, 60, 60)
        view.line_stipple = '-'
        view.line_width = 2
        view.draw(GL_LINE_LOOP, pts)
      end
      [@first, @hover].compact.each { |p| draw_ring(view, p) }
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@wall.bounds) if @wall&.valid?
      [@first, @hover].compact.each { |p| bb.add(pt3(p[:u], p[:z])) }
      bb
    end

    # ---- the one point method: move AND click come through here --------

    def face_point(view, x, y)
      ip = view.inputpoint(x, y)
      pos = ip.position
      return nil unless pos
      # Once the first corner is down the face is LOCKED: hovering over
      # another wall must not move the area onto it mid-rectangle.
      wall = @first ? @wall : (pick_wall(view, x, y) || @wall)
      return nil unless wall&.valid?
      fr = (@frame && @wall == wall) ? @frame : nil
      if fr.nil?
        side = side_of(wall, pos)
        return nil if side.nil?
        fr = InteriorPro::TileWall.frame_for(wall, side)
        return nil if fr.nil?
        @frame = fr
        @wall = wall
        @side = side
        @holes = InteriorPro::TileWall.openings_for(wall, fr)
        @len = fr[:len]
        @hgt = InteriorPro::TileWall.wall_height(wall)
      end
      u = (pos.x - fr[:ox]) * fr[:ux] + (pos.y - fr[:oy]) * fr[:uy]
      z = pos.z - fr[:floor_z]
      tol = begin
        view.pixels_to_model(SNAP_PX, pos)
      rescue StandardError
        1.0
      end
      su, ku = snap(u, u_lines, tol)
      sz, kz = snap(z, z_lines, tol)
      kind = if ku && kz
               (ku == :mid || kz == :mid) ? :mid : :corner
             elsif ku || kz
               :edge
             end
      { u: su, z: sz, kind: kind, wall: wall, side: @side }
    end

    def u_lines
      out = [[0.0, :corner], [@len, :corner], [@len / 2.0, :mid]]
      Array(@holes).each do |h|
        out << [h[0], :corner] << [h[2], :corner] << [(h[0] + h[2]) / 2.0, :mid]
      end
      out
    end

    def z_lines
      out = [[0.0, :corner], [@hgt, :corner], [@hgt / 2.0, :mid]]
      # The heights a tiler actually asks for, so he does not have to aim.
      [36.0, 48.0, 60.0, 72.0, 84.0, 96.0].each { |v| out << [v, :edge] if v < @hgt - 0.5 }
      Array(@holes).each do |h|
        out << [h[1], :corner] << [h[3], :corner] << [(h[1] + h[3]) / 2.0, :mid]
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

    def pick_wall(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |e|
          next unless e.is_a?(Sketchup::Group)
          return e if e.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end
      nil
    end

    # Which of the wall's two long faces the click landed on - by
    # measuring, not by guessing from the anchor.
    def side_of(wall, pos)
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      len = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if len < 0.001
      nx = -(ey - sy) / len
      ny = (ex - sx) / len
      off = (pos.x - sx) * nx + (pos.y - sy) * ny
      o_pos, o_neg = InteriorPro::TileWall.side_offsets(
        wall.get_attribute('InteriorPro', 'thickness').to_f,
        InteriorPro::TileWall.h_anchor_of(wall)
      )
      (off - o_pos).abs <= (off - o_neg).abs ? 'a' : 'b'
    end

    # ---- drawing helpers ----------------------------------------------

    def pt3(u, z, out = 0.25)
      x, y, zz = InteriorPro::TileWall.world(@frame, u, z, out)
      Geom::Point3d.new(x, y, zz)
    end

    def rect_pts(u1, z1, u2, z2)
      [pt3(u1, z1), pt3(u2, z1), pt3(u2, z2), pt3(u1, z2)]
    end

    def ring_color(kind)
      case kind
      when :corner then GREEN
      when :mid    then CYAN
      when :edge   then MAGENTA
      end
    end

    def draw_ring(view, p)
      c = ring_color(p[:kind])
      return if c.nil?
      centre = pt3(p[:u], p[:z])
      r = begin
        view.pixels_to_model(6, centre)
      rescue StandardError
        1.0
      end
      pts = (0..16).map do |i|
        a = i * 2.0 * Math::PI / 16.0
        pt3(p[:u] + Math.cos(a) * r, p[:z] + Math.sin(a) * r)
      end
      view.drawing_color = Sketchup::Color.new(*c)
      view.line_stipple = ''
      view.line_width = 3
      view.draw(GL_LINE_STRIP, pts)
    end

    # ---- the build -----------------------------------------------------

    def build!(a, b, view)
      u0 = [a[:u], b[:u]].min
      z0 = [a[:z], b[:z]].min
      w  = (b[:u] - a[:u]).abs
      h  = (b[:z] - a[:z]).abs
      if w < 1.0 || h < 1.0
        Sketchup.set_status_text('Tile Wall: that area is too small - click the other corner further away.', SB_PROMPT)
        return
      end
      grp = InteriorPro::TileWall.build!(
        wall: @wall, side: @side, u0: u0, z0: z0, w: w, h: h,
        card_id: @cfg[:card], grout: @cfg[:grout],
        grout_color: @cfg[:color], stagger: @cfg[:bond],
        depth: @cfg[:depth], mode: @cfg[:mode]
      )
      if grp.nil?
        UI.messagebox('Nothing was tiled - see the Ruby Console for the reason.')
      end
      reset_area
      view.invalidate
    end

    # ---- state ---------------------------------------------------------

    def reset
      @wall = nil
      @side = nil
      @frame = nil
      @holes = nil
      @len = 0.0
      @hgt = 0.0
      reset_area
    end

    def reset_area
      @first = nil
      @hover = nil
    end

    def status
      if @first
        Sketchup.set_status_text(
          'Tile Wall: click the OPPOSITE corner, or type width,height (60,96). Esc = start over.', SB_PROMPT
        )
      else
        Sketchup.set_status_text(
          'Tile Wall: click one corner of the area on a wall face. Green = corner, cyan = middle, magenta = on an edge.', SB_PROMPT
        )
      end
    end

    # ---- the one dialog ------------------------------------------------

    def ask_settings
      cards = begin
        InteriorPro::MaterialLibrary.cards
      rescue StandardError
        []
      end
      names = cards.map { |c| c['name'].to_s }
      last = InteriorPro::TileWallTool.last
      cur = cards.find { |c| c['id'].to_s == last[:card].to_s }
      defaults = [cur ? cur['name'].to_s : (names.first || LINES_ONLY),
                  GROUTS[GROUT_IN.index(last[:grout]) || 2],
                  BONDS[BOND_V.index(last[:bond]) || 0],
                  DEPTHS[DEPTH_IN.index(last[:depth]) || 0],
                  MODES[MODE_V.index(last[:mode].to_s) || 0]]
      lists = [([LINES_ONLY] + names).join('|'), GROUTS.join('|'),
               BONDS.join('|'), DEPTHS.join('|'), MODES.join('|')]
      res = UI.inputbox(['Material', 'Grout', 'Offset', 'Stand-off', 'Layout'],
                        defaults, lists, 'Tile Wall')
      return nil unless res
      card = cards.find { |c| c['name'].to_s == res[0].to_s }
      cfg = { card: card ? card['id'] : nil,
              grout: GROUT_IN[GROUTS.index(res[1].to_s) || 2],
              bond: BOND_V[BONDS.index(res[2].to_s) || 0],
              depth: DEPTH_IN[DEPTHS.index(res[3].to_s) || 0],
              mode: MODE_V[MODES.index(res[4].to_s) || 0],
              color: last[:color] }
      InteriorPro::TileWallTool.last.merge!(cfg)
      cfg
    end
  end
end

# encoding: utf-8
# Interior Pro - TILE ON A WALL (2026-09-17)
#
# His words: "אנחנו רוצים גם כלי לבנות קירות של טיל למקלחות וקירות אחרים
# בבית. הכלי הוא בעיקר לחיתוכים ואחרי זה לשליחה לפריסה בתוכניות."
# And straight after: "צריך לוודא שהקיר של ה-TILE לוקח בחשבון גם את
# החלון על הקיר במידה ויש." So openings are in from step one, not later.
#
# THE RULE THIS FILE EXISTS TO KEEP: there is ONE tile layout in the
# plugin - tile_grid.rb. The floor reads it, the count reads it, and a
# tiled wall reads the SAME one. Nothing here computes a second grid.
# What changes on a wall is only the PLANE the grid is laid on and how
# the area is chosen (a rectangle on one face, minus the openings).
#
# The plane, in one paragraph: a wall is stored as start_x/y -> end_x/y
# plus a thickness and an anchor. `u` runs along the wall from its start,
# `z` runs up from the wall's own floor. Side 'a' is the face on the LEFT
# of start -> end, side 'b' the one on the right. So a tiled area is four
# numbers - u0, z0, width, height - which is exactly what a rectangle
# dragged on the face will hand over, and what a niche will hand over
# later.
#
# EVERYTHING ABOVE `---- the model ----` IS PURE: numbers in, numbers
# out, no SketchUp API, so tests/rt175.rb pins it.
require_relative 'tile_grid'
require_relative 'tile_count'

module InteriorPro
  module TileWall
    EPS = 1.0e-6 unless const_defined?(:EPS, false)
    # How far the tile faces stand off the wall's own face, so SketchUp
    # never has to choose between two coplanar faces.
    FACE_OFF  = 0.06 unless const_defined?(:FACE_OFF, false)
    GROUT_OFF = 0.02 unless const_defined?(:GROUT_OFF, false)
    MAX_CELLS = 20_000 unless const_defined?(:MAX_CELLS, false)
    # A sliver this small is not a tile, it is float noise.
    MIN_PIECE = 0.02 unless const_defined?(:MIN_PIECE, false)

    # ---- the plane (pure) ----------------------------------------------

    # The two side offsets along the LEFT perpendicular of start -> end.
    # Deliberately the same numbers WallTool.anchor_side_offsets gives,
    # written out here so this file needs no SketchUp to be tested.
    def self.side_offsets(thickness, h_anchor)
      t = thickness.to_f
      case h_anchor.to_s
      when 'left'  then [t,       0.0]
      when 'right' then [0.0,     -t]
      else              [t / 2.0, -t / 2.0]
      end
    end

    # The frame of one wall face.
    #   side  'a' = the face on the LEFT of start -> end, 'b' = the right
    # Returns nil for a wall with no length.
    def self.frame(sx, sy, ex, ey, thickness, h_anchor, side, floor_z = 0.0)
      sx = sx.to_f; sy = sy.to_f; ex = ex.to_f; ey = ey.to_f
      dx = ex - sx
      dy = ey - sy
      len = Math.sqrt(dx * dx + dy * dy)
      return nil if len < 0.001
      ux = dx / len
      uy = dy / len
      nx = -uy          # left perpendicular
      ny = ux
      o_pos, o_neg = side_offsets(thickness, h_anchor)
      off  = side.to_s == 'b' ? o_neg : o_pos
      sign = side.to_s == 'b' ? -1.0 : 1.0
      { ox: sx + nx * off, oy: sy + ny * off,
        ux: ux, uy: uy, nx: nx * sign, ny: ny * sign,
        len: len, floor_z: floor_z.to_f, side: side.to_s == 'b' ? 'b' : 'a' }
    end

    # A point on the face, pushed `out` inches away from the wall.
    def self.world(fr, u, z, out = 0.0)
      [fr[:ox] + fr[:ux] * u.to_f + fr[:nx] * out.to_f,
       fr[:oy] + fr[:uy] * u.to_f + fr[:ny] * out.to_f,
       fr[:floor_z] + z.to_f]
    end

    # ---- the area (pure) ------------------------------------------------

    def self.rect(u0, z0, w, h)
      u0 = u0.to_f; z0 = z0.to_f
      [[u0, z0], [u0 + w.to_f, z0], [u0 + w.to_f, z0 + h.to_f], [u0, z0 + h.to_f]]
    end

    # `polys` minus one axis-aligned rectangle. A rectangle cut out of a
    # convex piece leaves up to four convex pieces - left of it, right of
    # it, and the strips under and over it - so everything downstream
    # stays convex and the clipper stays exact.
    def self.subtract_rect(polys, u0, z0, u1, z1)
      tc = InteriorPro::TileCount
      out = []
      keep = lambda { |p| out << p if p && p.length >= 3 && tc.area(p) > MIN_PIECE }
      Array(polys).each do |p|
        next if p.nil? || p.length < 3
        keep.call(tc.clip_half(p, -1.0, 0.0, u0))   # u <= u0
        keep.call(tc.clip_half(p,  1.0, 0.0, -u1))  # u >= u1
        band = tc.clip_half(p, 1.0, 0.0, -u0)
        band = band.length >= 3 ? tc.clip_half(band, -1.0, 0.0, u1) : []
        next if band.length < 3
        keep.call(tc.clip_half(band, 0.0, -1.0, z0)) # z <= z0
        keep.call(tc.clip_half(band, 0.0,  1.0, -z1)) # z >= z1
      end
      out
    end

    # The tiled area: the rectangle he marked, minus every opening that
    # touches it. `holes` is [[u0, z0, u1, z1], ...] in the same frame.
    def self.area_polys(u0, z0, w, h, holes = [])
      polys = [rect(u0, z0, w, h)]
      Array(holes).each do |hu0, hz0, hu1, hz1|
        polys = subtract_rect(polys, hu0.to_f, hz0.to_f, hu1.to_f, hz1.to_f)
        return [] if polys.empty?
      end
      polys
    end

    # ---- the tiles (pure) ------------------------------------------------

    # Every piece of tile that actually gets laid.
    #   area    the polygons from area_polys
    #   u_size  the tile ALONG the wall, v_size the tile UP the wall
    # Each piece: { poly: [[u, z], ...], full: true/false,
    #               cell: [iu, iv], u0:, v0:, cut: [du, dv] or nil }
    # Returns nil if the tile is so small the area needs more than
    # MAX_CELLS of them - same guard the floor has.
    def self.pieces(area, u_size:, v_size:, grout: 0.0, angle: 0.0,
                    ox: 0.0, oy: 0.0, centered: false, stagger: 0.0,
                    limit: MAX_CELLS)
      return [] if area.nil? || area.empty?
      u_size = u_size.to_f
      v_size = v_size.to_f
      return [] if u_size <= 0.01 || v_size <= 0.01
      outline = area.length == 1 ? area.first : bbox_poly(area)
      cells = InteriorPro::TileGrid.cells(outline, u_size: u_size, v_size: v_size,
                                                   grout: grout, angle: angle,
                                                   ox: ox, oy: oy,
                                                   centered: centered,
                                                   stagger: stagger, limit: limit)
      return nil if cells.nil?
      tc = InteriorPro::TileCount
      fr = InteriorPro::TileGrid.degrees(angle)
      cell_area = u_size * v_size
      out = []
      cells.each do |c|
        area.each do |ap|
          piece = tc.clip_convex(ap, c[:quad])
          next if piece.length < 3
          a = tc.area(piece)
          next if a <= cell_area * 0.0005
          if a >= cell_area - EPS * 100
            out << { poly: piece, full: true, cell: [c[:iu], c[:iv]],
                     u0: c[:u0], v0: c[:v0], cut: nil }
          else
            uv = piece.map { |q| InteriorPro::TileGrid.to_uv(q[0], q[1], fr) }
            us = uv.map { |q| q[0] }
            vs = uv.map { |q| q[1] }
            out << { poly: piece, full: false, cell: [c[:iu], c[:iv]],
                     u0: c[:u0], v0: c[:v0],
                     cut: [tc.r16(us.max - us.min), tc.r16(vs.max - vs.min)] }
          end
        end
      end
      out
    end

    # The outline that the grid is stretched over. One rectangle is used
    # as it is; several pieces (an opening split the area) get their
    # common bounding box, so every piece reads the SAME grid - two
    # halves of one wall must not each start their own layout.
    def self.bbox_poly(polys)
      us = []
      vs = []
      polys.each { |p| p.each { |q| us << q[0]; vs << q[1] } }
      [[us.min, vs.min], [us.max, vs.min], [us.max, vs.max], [us.min, vs.max]]
    end

    # How many tiles to buy for this wall - the SAME pairing of cut
    # pieces to offcuts the floor takeoff uses.
    def self.plan(area, u_size:, v_size:, grout: 0.0, angle: 0.0, ox: 0.0,
                  oy: 0.0, centered: false, stagger: 0.0,
                  pct: InteriorPro::TileCount::MIN_REUSE_PCT)
      ps = pieces(area, u_size: u_size, v_size: v_size, grout: grout,
                        angle: angle, ox: ox, oy: oy, centered: centered,
                        stagger: stagger)
      return nil if ps.nil?
      full = ps.count { |p| p[:full] }
      cuts = ps.reject { |p| p[:full] }.map { |p| p[:cut] }
      InteriorPro::TileCount.count(full, cuts, u_size, v_size, pct)
    end

    def self.area_sqft(area)
      Array(area).sum { |p| InteriorPro::TileCount.area(p) } / 144.0
    end

    # ---- the model ------------------------------------------------------
    # From here down the SketchUp API is used.

    TAG = 'IP/TileWalls' unless const_defined?(:TAG, false)

    def self.walls_in_model(model = Sketchup.active_model)
      model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
      end
    end

    def self.wall_by_id(id, model = Sketchup.active_model)
      walls_in_model(model).find { |w| w.get_attribute('InteriorPro', 'id').to_s == id.to_s }
    end

    def self.areas_in_model(model = Sketchup.active_model)
      model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'tile_wall'
      end
    end

    # The frame of one real wall's face. The wall's own floor is MEASURED
    # off its geometry (bounds), not rebuilt from the anchor - one number
    # less to get wrong, and a wall on a second storey reads right.
    def self.frame_for(wall, side)
      return nil unless wall&.valid?
      if InteriorPro::WallTool.respond_to?(:curved_wall?) &&
         InteriorPro::WallTool.curved_wall?(wall)
        puts '[TileWall] this wall is curved - a curved tiled area is not built yet'
        return nil
      end
      a = lambda { |k| wall.get_attribute('InteriorPro', k) }
      fr = frame(a.call('start_x'), a.call('start_y'), a.call('end_x'), a.call('end_y'),
                 a.call('thickness').to_f, h_anchor_of(wall), side,
                 wall.bounds.min.z.to_f)
      puts '[TileWall] wall has no length - nothing to tile' if fr.nil?
      fr
    end

    def self.h_anchor_of(wall)
      anchor = wall.get_attribute('InteriorPro', 'anchor').to_s
      return 'center' if anchor.empty?
      parts = anchor.split('-')
      %w[left right center].include?(parts.last) ? parts.last : 'center'
    end

    def self.wall_height(wall)
      h = wall.get_attribute('InteriorPro', 'height').to_f
      h > 0.01 ? h : (wall.bounds.max.z.to_f - wall.bounds.min.z.to_f)
    end

    # Every opening on this wall, as [u0, z0, u1, z1] on the face -
    # doors from the wall's own list, windows from their own groups
    # (window_tool cuts the hole and records it on the WINDOW, not on the
    # wall, so both have to be read - see CLAUDE.md).
    def self.openings_for(wall, fr, model = Sketchup.active_model)
      out = []
      floor_z = fr[:floor_z]
      begin
        InteriorPro::WallTool.read_door_openings(wall).each do |o|
          w = o[:width].to_f
          next if w <= 0.01
          z0 = o[:floor_offset].to_f
          z1 = z0 + o[:height].to_f + o[:arch_rise].to_f
          out << [o[:t].to_f - w / 2.0, z0, o[:t].to_f + w / 2.0, z1]
        end
      rescue StandardError => e
        puts "[TileWall] could not read the doors: #{e.message}"
      end
      wid = wall.get_attribute('InteriorPro', 'id').to_s
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'window'
        next unless g.get_attribute('InteriorPro', 'host_wall_id').to_s == wid
        w = g.get_attribute('InteriorPro', 'width_in').to_f
        t = g.get_attribute('InteriorPro', 'position_along_wall_in').to_f
        b = g.get_attribute('InteriorPro', 'bottom_z')
        tp = g.get_attribute('InteriorPro', 'top_z')
        if w <= 0.01 || b.nil? || tp.nil?
          puts "[TileWall] window #{g.get_attribute('InteriorPro', 'id')} has no size on the wall - skipped"
          next
        end
        out << [t - w / 2.0, b.to_f - floor_z, t + w / 2.0, tp.to_f - floor_z]
      end
      out
    end

    def self.remove_for_id!(id)
      areas_in_model.each do |g|
        g.erase! if g.valid? && g.get_attribute('InteriorPro', 'id').to_s == id.to_s
      end
    end

    def self.next_id
      @seq = (@seq || 0) + 1
      format('TW%03d', @seq + areas_in_model.length)
    end

    # The floor's own grout colours, so a tiled wall and a tiled floor
    # in the same bathroom cannot end up with two different greys. Read
    # LAZILY: this file is required on its own by tests/rt175.rb, where
    # FloorPattern does not exist.
    FALLBACK_GROUT = { 'light' => [210, 208, 204], 'gray' => [165, 163, 160],
                       'dark' => [92, 90, 88], 'white' => [245, 245, 243] }.freeze unless const_defined?(:FALLBACK_GROUT, false)

    def self.grout_colors
      if defined?(InteriorPro::FloorPattern) &&
         InteriorPro::FloorPattern.const_defined?(:GROUT_COLORS, false)
        return InteriorPro::FloorPattern::GROUT_COLORS
      end
      FALLBACK_GROUT
    end

    def self.grout_material(model, key)
      cols = grout_colors
      k = cols.key?(key.to_s) ? key.to_s : 'light'
      name = "InteriorPro_Grout_#{k.capitalize}"
      m = model.materials[name]
      unless m
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*cols[k])
      end
      m
    end

    # The material card - the picture, the tile size and the V-Ray
    # numbers all come from it, exactly as the floor does it.
    def self.card(id)
      cid = id.to_s
      return nil if cid.empty?
      return nil unless defined?(InteriorPro::MaterialLibrary)
      c = (InteriorPro::MaterialLibrary.cards.find { |x| x['id'].to_s == cid } rescue nil)
      puts "[TileWall] material card '#{cid}' is not in the library" if c.nil?
      c
    end

    # BUILD ONE TILED AREA.
    #
    #   wall     the wall group
    #   side     'a' (left of start -> end) or 'b'
    #   u0, z0   the near corner of the area, along the wall and up from
    #            the wall's own floor, in inches
    #   w, h     how wide and how tall the tiled area is
    #   card_id  a material card; without one the area is drawn as JOINT
    #            LINES only, like a floor with no texture
    #
    # Returns the group, or nil. Nothing is skipped silently.
    def self.build!(wall:, side: 'a', u0: 0.0, z0: 0.0, w: nil, h: nil,
                    card_id: nil, tile_w: nil, tile_l: nil, grout: 0.0,
                    grout_color: 'light', stagger: 0.0, angle: 0.0,
                    ox: 0.0, oy: 0.0, centered: false, id: nil,
                    openings: nil, wrap_operation: true)
      model = Sketchup.active_model
      unless wall&.valid? && wall.get_attribute('InteriorPro', 'type') == 'wall'
        puts '[TileWall] that is not a wall'
        return nil
      end
      fr = frame_for(wall, side)
      return nil unless fr

      w = fr[:len] if w.nil?
      h = wall_height(wall) - z0.to_f if h.nil?
      u0 = u0.to_f; z0 = z0.to_f; w = w.to_f; h = h.to_f
      if w <= 0.1 || h <= 0.1
        puts "[TileWall] the area is empty (#{w.round(2)} x #{h.round(2)})"
        return nil
      end

      c = card(card_id)
      tw = tile_w.to_f
      tl = tile_l.to_f
      img_w = img_l = nil
      if c
        cw = (c['tile_w_inches'] || c['texture_width_inches']).to_f
        ch = (c['tile_l_inches'] || c['texture_height_inches']).to_f
        tw = cw if tw <= 0.25 && cw > 0.25
        tl = ch if tl <= 0.25 && ch > 0.25
        iw = c['texture_width_inches'].to_f
        ih = c['texture_height_inches'].to_f
        img_w = iw if iw > 0.25
        img_l = ih if ih > 0.25
      end
      tw = 12.0 if tw <= 0.25
      tl = tw   if tl <= 0.25
      g = [grout.to_f, 0.0].max
      g = [g, [tw, tl].min * 0.4].min
      st = stagger.to_f
      st = 0.0 if st.negative? || st >= 1.0

      holes = openings.nil? ? openings_for(wall, fr, model) : openings
      area = area_polys(u0, z0, w, h, holes)
      if area.empty?
        puts '[TileWall] the openings cover the whole area - nothing left to tile'
        return nil
      end

      # The tile measured ALONG the wall is `tile_w`, the same way round
      # as the floor (UNIT_W_ALONG_LAYOUT there). One word, in the open.
      ps = pieces(area, u_size: tw, v_size: tl, grout: g, angle: angle,
                        ox: ox, oy: oy, centered: centered, stagger: st)
      if ps.nil?
        puts "[TileWall] a #{tw}x#{tl} tile needs more than #{MAX_CELLS} pieces here - too small"
        return nil
      end
      if ps.empty?
        puts '[TileWall] the grid produced no tiles'
        return nil
      end

      mat = nil
      if c
        mat = (InteriorPro::MaterialLibraryDialog.material_from_card(model, c) rescue nil)
        puts "[TileWall] card '#{c['name']}' gave no material - drawing joint lines only" if mat.nil?
      end

      model.start_operation('Interior Pro - Tile Wall', true) if wrap_operation
      begin
        aid = (id || next_id).to_s
        remove_for_id!(aid)
        grp = model.entities.add_group
        grp.name = 'InteriorPro_TileWall'
        InteriorPro.assign_tag(grp, TAG)
        ge = grp.entities

        if mat && g > 0.02
          emit_area_faces!(ge, fr, area, grout_material(model, grout_color), GROUT_OFF)
        end
        if mat
          emit_tile_faces!(ge, fr, ps, mat, img_w || tw, img_l || tl)
        else
          emit_tile_edges!(ge, fr, ps)
        end

        if ge.length.zero?
          grp.erase!
          model.abort_operation if wrap_operation
          puts '[TileWall] nothing could be drawn'
          return nil
        end

        grp.set_attribute('InteriorPro', 'type', 'tile_wall')
        grp.set_attribute('InteriorPro', 'id', aid)
        grp.set_attribute('InteriorPro', 'wall_id', wall.get_attribute('InteriorPro', 'id'))
        grp.set_attribute('InteriorPro', 'side', fr[:side])
        grp.set_attribute('InteriorPro', 'u0', u0)
        grp.set_attribute('InteriorPro', 'z0', z0)
        grp.set_attribute('InteriorPro', 'area_w', w)
        grp.set_attribute('InteriorPro', 'area_h', h)
        grp.set_attribute('InteriorPro', 'material_card_id', card_id.to_s)
        grp.set_attribute('InteriorPro', 'tile_w', tw)
        grp.set_attribute('InteriorPro', 'tile_l', tl)
        grp.set_attribute('InteriorPro', 'pattern_grout', g)
        grp.set_attribute('InteriorPro', 'pattern_grout_color', grout_color.to_s)
        grp.set_attribute('InteriorPro', 'pattern_stagger', st)
        grp.set_attribute('InteriorPro', 'pattern_angle', angle.to_f)
        grp.set_attribute('InteriorPro', 'pattern_ox', ox.to_f)
        grp.set_attribute('InteriorPro', 'pattern_oy', oy.to_f)
        grp.set_attribute('InteriorPro', 'pattern_center', centered ? true : false)
        model.commit_operation if wrap_operation

        res = InteriorPro::TileCount.count(ps.count { |p| p[:full] },
                                           ps.reject { |p| p[:full] }.map { |p| p[:cut] },
                                           tw, tl)
        puts "[TileWall] #{aid} on wall #{wall.get_attribute('InteriorPro', 'id')} side #{fr[:side]}: " \
             "#{area_sqft(area).round(2)} sqft, #{holes.length} opening(s), " \
             "#{res[:full]} whole + #{res[:cut_pieces]} cut = #{res[:tiles]} tiles to buy"
        grp
      rescue StandardError => e
        model.abort_operation if wrap_operation
        puts "[TileWall] build! failed: #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        nil
      end
    end

    # Rebuild every tiled area from its own stored numbers - so an
    # opening added later, or a card that changed, lands on the wall.
    def self.refresh_all!
      n = 0
      areas_in_model.to_a.each do |g|
        next unless g.valid?
        a = lambda { |k| g.get_attribute('InteriorPro', k) }
        wall = wall_by_id(a.call('wall_id'))
        if wall.nil?
          puts "[TileWall] area #{a.call('id')} lost its wall - erased"
          g.erase!
          next
        end
        ok = build!(wall: wall, side: a.call('side'), u0: a.call('u0').to_f,
                    z0: a.call('z0').to_f, w: a.call('area_w').to_f,
                    h: a.call('area_h').to_f, card_id: a.call('material_card_id'),
                    tile_w: a.call('tile_w').to_f, tile_l: a.call('tile_l').to_f,
                    grout: a.call('pattern_grout').to_f,
                    grout_color: a.call('pattern_grout_color'),
                    stagger: a.call('pattern_stagger').to_f,
                    angle: a.call('pattern_angle').to_f,
                    ox: a.call('pattern_ox').to_f, oy: a.call('pattern_oy').to_f,
                    centered: a.call('pattern_center') ? true : false,
                    id: a.call('id'))
        n += 1 if ok
      end
      puts "[TileWall] #{n} area(s) rebuilt" if n > 0
      n
    end

    # ---- emitters --------------------------------------------------------

    def self.pts3d(fr, poly, out)
      poly.map do |u, z|
        x, y, zz = world(fr, u, z, out)
        Geom::Point3d.new(x, y, zz)
      end
    end

    def self.emit_area_faces!(ge, fr, polys, mat, out)
      polys.each do |p|
        f = begin
          ge.add_face(pts3d(fr, p, out))
        rescue StandardError
          nil
        end
        next unless f
        f.material = mat
        f.back_material = mat
        f.edges.each { |e| e.hidden = true; e.soft = true; e.smooth = true }
      end
    end

    # Each tile piece is a face, painted with the card's picture anchored
    # to the tile's OWN corner - so a photo that holds several tiles
    # shows exactly one of them per tile, the crop the floor already does
    # (HANDOFF_2026-09-17B).
    def self.emit_tile_faces!(ge, fr, pieces, mat, tex_u, tex_v)
      face_fails = 0
      uv_fails = 0
      pieces.each do |p|
        f = begin
          ge.add_face(pts3d(fr, p[:poly], FACE_OFF))
        rescue StandardError
          nil
        end
        if f.nil?
          face_fails += 1
          next
        end
        f.material = mat
        f.back_material = mat
        ox, oy, oz = world(fr, p[:u0], p[:v0], FACE_OFF)
        o  = Geom::Point3d.new(ox, oy, oz)
        pu = Geom::Point3d.new(ox + fr[:ux] * tex_u, oy + fr[:uy] * tex_u, oz)
        pv = Geom::Point3d.new(ox, oy, oz + tex_v)
        begin
          f.position_material(mat, [o,  Geom::Point3d.new(0, 0, 0),
                                    pu, Geom::Point3d.new(1, 0, 0),
                                    pv, Geom::Point3d.new(0, 1, 0)], true)
        rescue StandardError
          uv_fails += 1
        end
        f.edges.each { |e| e.hidden = true; e.soft = true; e.smooth = true }
      end
      puts "[TileWall] #{face_fails} face fail(s), #{uv_fails} uv fail(s)" if face_fails > 0 || uv_fails > 0
    end

    # No material: the joints themselves, which is what a plan sheet
    # needs. The same pieces the count counted, so the drawing and the
    # quantity cannot drift apart.
    def self.emit_tile_edges!(ge, fr, pieces)
      pieces.each do |p|
        pts = pts3d(fr, p[:poly], FACE_OFF)
        pts.each_index do |i|
          a = pts[i]
          b = pts[(i + 1) % pts.length]
          next if a.distance(b) < 0.05
          begin
            ge.add_edges(a, b)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end

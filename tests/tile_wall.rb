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
    # FLUSH (2026-09-17, his second correction: "הגראוט צריך ליישר קו עם
    # הטיל"). Dead level with the tile face. Not zero, because two faces
    # on exactly the same plane flicker against each other in SketchUp -
    # 1/200 of an inch is invisible and keeps them apart.
    GROUT_BACK = 0.005 unless const_defined?(:GROUT_BACK, false)
    MAX_CELLS = 20_000 unless const_defined?(:MAX_CELLS, false)
    # REAL TILE STANDS OFF THE WALL (2026-09-17, his measurement): "ברוב
    # המקלחות הטיל הוא לפחות 5/8 בולט מהקיר" - tile plus thinset. So a
    # tiled area is SOLID by default, not a painted face: the joints are
    # real recesses, which is also why the layout reads as tile at all
    # instead of as one smooth material (that was the complaint).
    DEFAULT_DEPTH = 0.625 unless const_defined?(:DEFAULT_DEPTH, false)
    # Kill switch. false = the old flat faces, nothing solid is built.
    USE_SOLID_TILES = true unless const_defined?(:USE_SOLID_TILES, false)
    # Every tile is its OWN group - CLAUDE.md, the law that crashed
    # SketchUp: two solids touching face to face inside one group get
    # their faces merged, and pushpull into that merge takes the whole
    # program down. Groups are not free, so past this many tiles the area
    # falls back to flat faces and says so.
    MAX_SOLID = 900 unless const_defined?(:MAX_SOLID, false)
    # A sliver this small is not a tile, it is float noise.
    MIN_PIECE = 0.02 unless const_defined?(:MIN_PIECE, false)
    # THE CORNER IS AN EMPTY SQUARE (2026-09-18, his design, in his words:
    # "אני רוצה ששתי הפינות שלהם יפגשו ובאמצע יהיה ריבוע שווה צלעות",
    # "הפינות החיצוניות שלהם"). Two tiled faces that meet in an inside
    # corner stop so that their OUTER corners land on the SAME point, and
    # what is left between them and the wall corner is a square whose side
    # is the tile's own stand-off depth. Nothing overlaps, and no wall has
    # to be picked as the main one. There is no fixed number here: how far
    # an end comes back is the neighbour's tile depth minus how far that
    # end already stands off it, so both spellings of the same corner land
    # on the same square.
    # Kill switch: false = the old dead-tight corner.
    USE_CORNER_GAP = true unless const_defined?(:USE_CORNER_GAP, false)
    # TILE INSIDE THE NICHE, MITRED 45 AT THE OPENING (2026-09-22, his
    # words: "בתוך הניצ צריך להיות אריחים", and the joint: "החיתוך בין
    # הניש לטיל של הקירות החיבור יהיה 45 מעלות"). false = the niche is a
    # bare hole in the tile, exactly as before.
    USE_NICHE_TILES = true unless const_defined?(:USE_NICHE_TILES, false)
    # THE NICHE'S OWN TILE (2026-09-23). false = every niche wears the
    # wall's tile again, whatever is stored on it.
    USE_NICHE_OWN_TILE = true unless const_defined?(:USE_NICHE_OWN_TILE, false)

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

    # Where another wall's face plane crosses THIS face, as a `u` along it.
    # nil when the two are parallel and can never cross. PURE.
    def self.cross_u(fr, f2)
      den = fr[:ux] * f2[:nx] + fr[:uy] * f2[:ny]
      return nil if den.abs < 0.01
      -((fr[:ox] - f2[:ox]) * f2[:nx] + (fr[:oy] - f2[:oy]) * f2[:ny]) / den
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

    # Pull the two ends of an area back by the given amounts. PURE - HOW
    # FAR each end has to come back is worked out by `corner_ends`, down in
    # the model half, and is zero for an end that is not at a corner.
    def self.trim_for_corners(u0, w, lo = 0.0, hi = 0.0)
      l = [lo.to_f, 0.0].max
      h = [hi.to_f, 0.0].max
      [u0.to_f + l, w.to_f - l - h]
    end

    # CARRY THE PATTERN ROUND THE CORNER (2026-09-18). His choice was that
    # every wall starts its own layout BY DEFAULT, "אבל יש גם אופציה
    # לאחד אם רוצים" - one run that wraps, so the tile cut off at the
    # corner carries on as the first piece of the next wall.
    #
    # `used_w` is how much of the run the wall just laid really used. What
    # is left of the tile that was cut there is `size - cut`, so the next
    # wall's grid is pushed by a whole pitch minus that cut. PURE.
    def self.carry_ox(used_w, u_size, grout = 0.0)
      size = u_size.to_f
      return 0.0 if size <= 0.01
      pitch = size + [grout.to_f, 0.0].max
      return 0.0 if pitch <= 0.01
      rem = used_w.to_f % pitch
      return 0.0 if rem < 1.0e-6
      cut = rem > size ? size : rem
      (pitch - cut) % pitch
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

    # ---- one piece per tile, notch and all (pure) -----------------------
    #
    # THE BUG THIS FIXES (2026-09-17): he counted the cuts and said there
    # were far too many. There were. A tile that reached PAST an opening -
    # over it and beside it - was being cut into two separate pieces,
    # because the area had already been broken into convex rectangles and
    # each tile was clipped against each of them. Two solid pieces
    # standing side by side show a seam, so one tile read as two, and the
    # count said two tiles as well.
    #
    # A tile is ONE tile with a notch in it. So: lay the cell's own little
    # grid of the lines that cross it (its edges, the area's edges, the
    # openings' edges), mark which squares survive, and walk the boundary
    # of what is left. One ring comes back for a notched tile, and two
    # only when the tile really is in two separate parts.
    #
    # Axis aligned, which is what a wall layout is. A turned layout
    # (angle != 0) still goes the convex way through `pieces`.
    # A ring that carries island holes - see cut. An Array, so every
    # reader that only wants the corners keeps working.
    class Ring < Array
      attr_accessor :holes
    end

    # Is this rectangle wholly inside the ring's bounding box? Good enough
    # for the cutter: an island hole was already checked against the tile.
    def self.ring_holds?(ring, h)
      us = ring.map { |q| q[0] }
      vs = ring.map { |q| q[1] }
      h[0] >= us.min - EPS && h[2] <= us.max + EPS && h[1] >= vs.min - EPS && h[3] <= vs.max + EPS
    end

    def self.ring_holes(ring)
      ring.respond_to?(:holes) && ring.holes ? ring.holes : []
    end

    # The area of a ring MINUS its holes.
    def self.ring_area(ring)
      tc = InteriorPro::TileCount
      tc.area(ring) - ring_holes(ring).sum { |h| tc.area(h) }
    end

    def self.cut(x0, y0, x1, y1, holes)
      return [] if x1 - x0 <= MIN_PIECE || y1 - y0 <= MIN_PIECE
      hs = Array(holes).map { |h| h.map(&:to_f) }.select do |hx0, hy0, hx1, hy1|
        hx1 > x0 + EPS && hx0 < x1 - EPS && hy1 > y0 + EPS && hy0 < y1 - EPS
      end
      return [[[x0, y0], [x1, y0], [x1, y1], [x0, y1]]] if hs.empty?

      # A HOLE IN THE MIDDLE OF A TILE (2026-09-18, measured with
      # debug_tile_edit.rb: after centring, the whole window sat inside
      # ONE 48x24 tile, and this came back as the tile untouched plus a
      # second "tile" the size of the window - the hole's own outline,
      # chained as a ring of its own, and then BUILT as a tile). His call
      # on the fix, from two choices: ONE whole tile with a hole in it, no
      # seams - not four pieces. So an island hole is taken out of the
      # holes list, the tile is cut for whatever else it meets, and the
      # island is handed back ON the ring as `holes`, for the builder to
      # punch. A Ring is an Array, so everything that only reads corners
      # is untouched; ring_area knows to take the holes off.
      islands, hs = hs.partition do |hx0, hy0, hx1, hy1|
        hx0 > x0 + EPS && hx1 < x1 - EPS && hy0 > y0 + EPS && hy1 < y1 - EPS
      end
      unless islands.empty?
        rings = cut(x0, y0, x1, y1, hs)
        return rings.map do |ring|
          mine = islands.select { |h| ring_holds?(ring, h) }
          next ring if mine.empty?
          r = Ring.new(ring)
          r.holes = mine.map { |hx0, hy0, hx1, hy1| [[hx0, hy0], [hx1, hy0], [hx1, hy1], [hx0, hy1]] }
          r
        end
      end

      xs = ([x0, x1] + hs.flat_map { |h| [h[0], h[2]] }).map { |v| v.clamp(x0, x1) }
      ys = ([y0, y1] + hs.flat_map { |h| [h[1], h[3]] }).map { |v| v.clamp(y0, y1) }
      xs = dedupe(xs)
      ys = dedupe(ys)
      return [] if xs.length < 2 || ys.length < 2

      inside = Array.new(xs.length - 1) { Array.new(ys.length - 1, false) }
      (xs.length - 1).times do |i|
        cx = (xs[i] + xs[i + 1]) / 2.0
        (ys.length - 1).times do |j|
          cy = (ys[j] + ys[j + 1]) / 2.0
          inside[i][j] = hs.none? { |hx0, hy0, hx1, hy1| cx > hx0 && cx < hx1 && cy > hy0 && cy < hy1 }
        end
      end

      segs = []
      on = lambda { |i, j| i >= 0 && j >= 0 && i < inside.length && j < inside[0].length && inside[i][j] }
      (xs.length - 1).times do |i|
        (ys.length - 1).times do |j|
          next unless inside[i][j]
          a = [xs[i], ys[j]]
          b = [xs[i + 1], ys[j]]
          c = [xs[i + 1], ys[j + 1]]
          d = [xs[i], ys[j + 1]]
          segs << [a, b] unless on.call(i, j - 1)
          segs << [b, c] unless on.call(i + 1, j)
          segs << [c, d] unless on.call(i, j + 1)
          segs << [d, a] unless on.call(i - 1, j)
        end
      end
      chain(segs)
    end

    def self.dedupe(vals)
      out = []
      vals.sort.each { |v| out << v if out.empty? || (v - out.last).abs > 1.0e-7 }
      out
    end

    # Boundary segments -> closed rings, with the straight-through points
    # dropped so a plain tile comes back as four corners.
    def self.chain(segs)
      left = segs.dup
      rings = []
      until left.empty?
        seg = left.shift
        ring = [seg[0], seg[1]]
        loop do
          idx = left.index { |a, _b| same?(a, ring.last) }
          break if idx.nil?
          nxt = left.delete_at(idx)
          break if same?(nxt[1], ring.first)
          ring << nxt[1]
        end
        ring = simplify(ring)
        rings << ring if ring.length >= 3
      end
      rings
    end

    def self.same?(a, b)
      (a[0] - b[0]).abs < 1.0e-7 && (a[1] - b[1]).abs < 1.0e-7
    end

    def self.simplify(ring)
      n = ring.length
      return ring if n < 3
      out = []
      n.times do |i|
        p = ring[(i - 1) % n]
        q = ring[i]
        r = ring[(i + 1) % n]
        cross = (q[0] - p[0]) * (r[1] - q[1]) - (q[1] - p[1]) * (r[0] - q[0])
        out << q if cross.abs > 1.0e-9
      end
      out.length >= 3 ? out : ring
    end

    # Every tile over the marked rectangle, openings notched out of the
    # tiles themselves. This is what build! uses.
    def self.pieces_rect(u0, z0, w, h, holes, u_size:, v_size:, grout: 0.0,
                         angle: 0.0, ox: 0.0, oy: 0.0, centered: false,
                         stagger: 0.0, limit: MAX_CELLS)
      u0 = u0.to_f; z0 = z0.to_f; w = w.to_f; h = h.to_f
      if angle.to_f.abs > 1.0e-9
        return pieces(area_polys(u0, z0, w, h, holes), u_size: u_size,
                      v_size: v_size, grout: grout, angle: angle, ox: ox,
                      oy: oy, centered: centered, stagger: stagger, limit: limit)
      end
      return [] if w <= 0.1 || h <= 0.1
      u_size = u_size.to_f
      v_size = v_size.to_f
      return [] if u_size <= 0.01 || v_size <= 0.01
      cells = InteriorPro::TileGrid.cells(rect(u0, z0, w, h), u_size: u_size,
                                          v_size: v_size, grout: grout,
                                          angle: 0.0, ox: ox, oy: oy,
                                          centered: centered, stagger: stagger,
                                          limit: limit)
      return nil if cells.nil?
      tc = InteriorPro::TileCount
      cell_area = u_size * v_size
      out = []
      cells.each do |c|
        cu0 = [c[:u0], u0].max
        cv0 = [c[:v0], z0].max
        cu1 = [c[:u0] + u_size, u0 + w].min
        cv1 = [c[:v0] + v_size, z0 + h].min
        next if cu1 - cu0 <= MIN_PIECE || cv1 - cv0 <= MIN_PIECE
        cut(cu0, cv0, cu1, cv1, holes).each do |ring|
          a = ring_area(ring)
          next if a <= cell_area * 0.0005
          if a >= cell_area - EPS * 100
            out << { poly: ring, full: true, cell: [c[:iu], c[:iv]],
                     u0: c[:u0], v0: c[:v0], cut: nil }
          else
            us = ring.map { |q| q[0] }
            vs = ring.map { |q| q[1] }
            out << { poly: ring, full: false, cell: [c[:iu], c[:iv]],
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

    # ---- the niche (pure) -------------------------------------------------
    #
    # HOW THE MITRE WORKS, in the cross-section through one edge of the
    # niche (along the wall, out from it): the tile of the wall and the
    # tile lining the niche side both stand `dp` thick, and they meet on
    # the diagonal of the dp x dp square at the opening - from the inner
    # corner on the wall face to the OUTER corner on the tile face.
    #   - the wall tile's hole is the niche INSET by dp on its tile face,
    #     and its back loop is moved OUT by dp onto the niche's own edge,
    #   - the lining's front edge is moved FORWARD by dp on its tile face.
    # Both moves stay inside the planes of the other faces, so every face
    # stays flat, and the two bevels land on the same 45 degree plane.
    # The finished opening is the niche inset by dp, a sharp arris all
    # round, no cut edge showing.

    # The niche [u0, z0, u1, z1] brought in by the tile depth.
    def self.niche_inset(nr, dp)
      [nr[0].to_f + dp, nr[1].to_f + dp, nr[2].to_f - dp, nr[3].to_f - dp]
    end

    # Where a vertex on the BACK plane of a wall tile has to move so the
    # edge it sits on at the niche becomes the 45 bevel. [du, dz] or nil
    # for a vertex that is not on the niche's inset edge.
    def self.bevel_shift(u, z, ins, dp, tol = 1.0e-3)
      a0, c0, b0, d0 = ins
      in_u = u >= a0 - tol && u <= b0 + tol
      in_z = z >= c0 - tol && z <= d0 + tol
      du = 0.0
      dz = 0.0
      if in_z
        du = -dp if (u - a0).abs < tol
        du = dp if (u - b0).abs < tol
      end
      if in_u
        dz = -dp if (z - c0).abs < tol
        dz = dp if (z - d0).abs < tol
      end
      du.zero? && dz.zero? ? nil : [du, dz]
    end

    def self.rect_ring(a0, b0, a1, b1)
      [[a0, b0], [a1, b0], [a1, b1], [a0, b1]]
    end

    # The tile spans of a lattice (its tile starts) cut to [lo, hi].
    def self.clip_spans(starts, size, lo, hi)
      starts.map(&:to_f).uniq.sort.map { |s0| [[s0, lo].max, [s0 + size, hi].min] }
            .select { |a, b| b - a > MIN_PIECE }
    end

    # Tiles laid back from the FRONT edge of a lining: a whole tile at the
    # opening, the cut one against the back.
    def self.depth_spans(len, size, grout)
      pitch = size.to_f + [grout.to_f, 0.0].max
      return [] if pitch <= 0.01
      out = []
      a = 0.0
      while a < len - MIN_PIECE
        out << [a, [a + size.to_f, len].min]
        a += pitch
      end
      out.select { |a0, a1| a1 - a0 > MIN_PIECE }
    end

    # THE FIVE LININGS OF ONE NICHE, off the wall's own layout, so the
    # joints run on round the opening the way a tiler lays them:
    #   back          the wall's own cells cut to the niche - its joints are
    #                 the wall's joints, carried straight through
    #   left / right  the wall's ROWS, laid back from the opening
    #   bottom / top  the wall's COLUMNS in the row the edge sits in
    # The back owns the inside corners; sides and top/bottom stop dp short
    # of each other (the corner between them is closed by the mitre).
    # Coordinates are (a, b) on each lining's own frame - see
    # lining_frames. `cells` = TileGrid.cells of the wall area.
    # { key => { pieces: [{poly:, a0:, b0:}], grout: [a0, b0, a1, b1] } }
    # nil when the niche is too small or too shallow to line. PURE.
    def self.niche_lining(cells, tw, tl, g, nr, dp, nd)
      u0, z0, u1, z1 = nr.map(&:to_f)
      tw = tw.to_f
      tl = tl.to_f
      len = nd.to_f - dp
      return nil if len <= MIN_PIECE || u1 - u0 <= 2.0 * dp + MIN_PIECE || z1 - z0 <= 2.0 * dp + MIN_PIECE
      back = []
      Array(cells).each do |c|
        a0 = [c[:u0], u0].max
        a1 = [c[:u0] + tw, u1].min
        b0 = [c[:v0], z0].max
        b1 = [c[:v0] + tl, z1].min
        next if a1 - a0 <= MIN_PIECE || b1 - b0 <= MIN_PIECE
        back << { poly: rect_ring(a0, b0, a1, b1), a0: c[:u0], b0: c[:v0] }
      end
      rows = clip_spans(Array(cells).map { |c| c[:v0] }, tl, z0 + dp, z1 - dp)
      cols_at = lambda do |zz, below|
        row = Array(cells).select do |c|
          below ? (zz >= c[:v0] - 1.0e-6 && zz < c[:v0] + tl + g + 1.0e-6) :
                  (zz > c[:v0] - g - 1.0e-6 && zz <= c[:v0] + tl + 1.0e-6)
        end
        clip_spans(row.map { |c| c[:u0] }, tw, u0 + dp, u1 - dp)
      end
      side_d = depth_spans(len, tw, g)
      tb_d = depth_spans(len, tl, g)
      side = rows.flat_map { |b0, b1| side_d.map { |a0, a1| { poly: rect_ring(a0, b0, a1, b1), a0: a0, b0: b0 } } }
      strip = lambda do |cols|
        cols.flat_map { |b0, b1| tb_d.map { |a0, a1| { poly: rect_ring(a0, b0, a1, b1), a0: a0, b0: b0 } } }
      end
      { back:   { pieces: back, grout: [u0, z0, u1, z1] },
        left:   { pieces: side, grout: [0.0, z0 + dp, len, z1 - dp] },
        right:  { pieces: side.map(&:dup), grout: [0.0, z0 + dp, len, z1 - dp] },
        bottom: { pieces: strip.call(cols_at.call(z0, true)), grout: [0.0, u0 + dp, len, u1 - dp] },
        top:    { pieces: strip.call(cols_at.call(z1, false)), grout: [0.0, u0 + dp, len, u1 - dp] } }
    end

    # The frame of each lining, in world space. A point is
    #   o + a * A + b * B + out * N
    # with N pointing off the niche face INTO the niche, and on the four
    # sides `a` running from the opening (0) back into the wall. PURE.
    def self.lining_frames(fr, nr, nd)
      u0, z0, u1, z1 = nr.map(&:to_f)
      uu = [fr[:ux], fr[:uy], 0.0]
      nn = [fr[:nx], fr[:ny], 0.0]
      zz = [0.0, 0.0, 1.0]
      neg = lambda { |v| v.map { |q| -q } }
      o = lambda { |u, z, out| world(fr, u, z, out) }
      { back:   { o: o.call(0.0, 0.0, -nd.to_f), a: uu, b: zz, n: nn, bevel: false },
        left:   { o: o.call(u0, 0.0, 0.0), a: neg.call(nn), b: zz, n: uu, bevel: true },
        right:  { o: o.call(u1, 0.0, 0.0), a: neg.call(nn), b: zz, n: neg.call(uu), bevel: true },
        bottom: { o: o.call(0.0, z0, 0.0), a: neg.call(nn), b: uu, n: zz, bevel: true },
        top:    { o: o.call(0.0, z1, 0.0), a: neg.call(nn), b: uu, n: neg.call(zz), bevel: true } }
    end

    def self.lining_world(lf, a, b, out = 0.0)
      (0..2).map { |i| lf[:o][i] + lf[:a][i] * a.to_f + lf[:b][i] * b.to_f + lf[:n][i] * out.to_f }
    end

    # A point back in a lining's own (a, b, out). PURE.
    def self.lining_local(lf, x, y, z)
      d = [x - lf[:o][0], y - lf[:o][1], z - lf[:o][2]]
      dot = lambda { |v| d[0] * v[0] + d[1] * v[1] + d[2] * v[2] }
      [dot.call(lf[:a]), dot.call(lf[:b]), dot.call(lf[:n])]
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
      # A NICHE IS A HOLE TOO (2026-09-20). The tile runs AROUND the
      # niche, never over it. Only the niches on the face being tiled -
      # the other side of the same wall knows nothing about them.
      if defined?(InteriorPro::TileNiche)
        out += InteriorPro::TileNiche.holes_for_side(
          InteriorPro::TileNiche.read(wall), fr[:side]
        )
      end
      out
    end

    # Does an end of this area land on ANOTHER tiled area's face? Measured
    # in world space, so it does not matter which wall runs into which, nor
    # which of the two was drawn first. Returns [start end?, far end?].
    #
    # HOW FAR each end of this area has to come back so that its outer
    # corner meets the neighbour's outer corner. Measured in world space,
    # so it does not matter which wall runs into which nor which was drawn
    # first. Returns [inches off the start, inches off the far end], 0.0
    # for an end that is not at a corner at all.
    #
    # `d` is how far this end already stands off the neighbour's own wall
    # face. An end flush against that face (d = 0) is a whole tile depth
    # short; an end already standing on the neighbour's TILE face
    # (d = depth) is exactly where it belongs and does not move.
    def self.corner_ends(wall, fr, u0, w, z0 = 0.0, model = Sketchup.active_model)
      me = wall.get_attribute('InteriorPro', 'id').to_s
      others = []
      areas_in_model(model).each do |g|
        next unless g.valid?
        wid = g.get_attribute('InteriorPro', 'wall_id').to_s
        next if wid == me
        ow = wall_by_id(wid, model)
        next if ow.nil?
        ofr = frame_for(ow, g.get_attribute('InteriorPro', 'side'))
        next if ofr.nil?
        # Only a wall at an angle to this one can make a corner with it.
        next if (fr[:ux] * ofr[:ux] + fr[:uy] * ofr[:uy]).abs > 0.99
        dp = g.get_attribute('InteriorPro', 'tile_depth').to_f
        dp = DEFAULT_DEPTH if dp <= 0.0
        others << { fr: ofr, u0: g.get_attribute('InteriorPro', 'u0').to_f,
                    w: g.get_attribute('InteriorPro', 'area_w').to_f, dp: dp }
      end
      return [0.0, 0.0] if others.empty?
      pull = lambda do |u|
        x, y, = world(fr, u, z0, 0.0)
        best = 0.0
        others.each do |o|
          d = (x - o[:fr][:ox]) * o[:fr][:nx] + (y - o[:fr][:oy]) * o[:fr][:ny]
          next if d < -0.02 || d > o[:dp] + 0.02
          ou = (x - o[:fr][:ox]) * o[:fr][:ux] + (y - o[:fr][:oy]) * o[:fr][:uy]
          pad = o[:dp] + 0.02
          next unless ou >= o[:u0] - pad && ou <= o[:u0] + o[:w] + pad
          need = o[:dp] - d
          best = need if need > best
        end
        best
      end
      [pull.call(u0), pull.call(u0 + w)]
    rescue StandardError => e
      puts "[TileWall] the corner test failed: #{e.message}"
      [0.0, 0.0]
    end

    # The stretch of THIS face that another wall blocks, as [u from, u to],
    # or nil when that wall is not in the way at all. A wall blocks only if
    # it stands out on the side being tiled AND reaches this face - a wall
    # behind it, or one standing free in the middle of the room, does not.
    # PURE.
    def self.blocked_span(fr, sx, sy, ex, ey, thickness, h_anchor)
      fa = frame(sx, sy, ex, ey, thickness, h_anchor, 'a')
      fb = frame(sx, sy, ex, ey, thickness, h_anchor, 'b')
      return nil if fa.nil? || fb.nil?
      ua = cross_u(fr, fa)
      ub = cross_u(fr, fb)
      return nil if ua.nil? || ub.nil?
      d = [[sx, sy], [ex, ey]].map do |x, y|
        (x.to_f - fr[:ox]) * fr[:nx] + (y.to_f - fr[:oy]) * fr[:ny]
      end
      return nil if d.max <= 0.05   # all of it is behind this face
      return nil if d.min > 0.05    # it never reaches this face
      [[ua, ub].min, [ua, ub].max]
    end

    # HOW FAR ALONG THIS FACE HE IS ALLOWED TO GO (2026-09-18, his words:
    # "הטיל לא יכול לעבור דרך קירות", and then, when it still went through:
    # "הקיר עדיין חוצה את קיר הפנים"). Two things get in the way and the
    # first fix only caught one of them:
    #   - the wall that CLOSES the corner at either end, and
    #   - a wall that runs INTO the middle of this one, like the shower
    #     wall - the stored length says nothing about that one at all.
    # So every wall that stands on this face is turned into a blocked
    # stretch of `u`, and what comes back is the clear run that the area
    # he is holding actually sits in.
    def self.face_limits(wall, fr, ref_u = nil, model = Sketchup.active_model)
      lo = 0.0
      hi = fr[:len]
      ref = (ref_u || fr[:len] / 2.0).to_f
      at = lambda { |g, k| g.get_attribute('InteriorPro', k) }
      me = at.call(wall, 'id').to_s
      walls_in_model(model).each do |w2|
        next unless w2.valid?
        next if at.call(w2, 'id').to_s == me
        span = blocked_span(fr, at.call(w2, 'start_x').to_f, at.call(w2, 'start_y').to_f,
                            at.call(w2, 'end_x').to_f, at.call(w2, 'end_y').to_f,
                            at.call(w2, 'thickness').to_f, h_anchor_of(w2))
        next if span.nil?
        a, b = span
        if b <= ref + 1.0e-9
          lo = b if b > lo
        elsif a >= ref - 1.0e-9
          hi = a if a < hi
        else
          # ref sits INSIDE this wall (2026-09-18: the corner vertex the
          # drawing tool starts from stands in the interior wall's body).
          # It used to be skipped in silence and the run went straight
          # through. The nearer face of that wall is the limit.
          puts "[TileWall] face_limits: ref #{ref.round(2)} is inside a wall (#{a.round(2)}..#{b.round(2)}) - stopping at its nearer face"
          if ref - a <= b - ref
            hi = a if a < hi
          else
            lo = b if b > lo
          end
        end
      end
      lo = 0.0 if lo < 0.0
      hi = fr[:len] if hi > fr[:len]
      hi = lo if hi < lo
      [lo, hi]
    rescue StandardError => e
      puts "[TileWall] the face limits could not be worked out: #{e.message}"
      [0.0, fr[:len]]
    end

    # ROUND THE CORNER (2026-09-18, his words: "אני רוצה גם שתהיה אופציה
    # למתוח כמה קירות של טיל אחד אחרי השני והם יתחברו"). Which wall stands
    # at `u_limit` on this face, WHICH OF ITS OWN FACES carries on into the
    # same room, and where on that face the run picks up again.
    #   { wall:, side:, u_from:, dir:, len: }   dir = +1 or -1 along it
    # nil when the face simply ends and there is nothing to carry on to.
    def self.neighbour_at(wall, fr, u_limit, model = Sketchup.active_model)
      at = lambda { |g, k| g.get_attribute('InteriorPro', k) }
      me = at.call(wall, 'id').to_s
      mine = [at.call(wall, 'start_x').to_f, at.call(wall, 'start_y').to_f,
              at.call(wall, 'end_x').to_f, at.call(wall, 'end_y').to_f,
              at.call(wall, 'thickness').to_f, h_anchor_of(wall)]
      walls_in_model(model).each do |w2|
        next unless w2.valid?
        next if at.call(w2, 'id').to_s == me
        x1 = at.call(w2, 'start_x').to_f
        y1 = at.call(w2, 'start_y').to_f
        x2 = at.call(w2, 'end_x').to_f
        y2 = at.call(w2, 'end_y').to_f
        th = at.call(w2, 'thickness').to_f
        anc = h_anchor_of(w2)
        span = blocked_span(fr, x1, y1, x2, y2, th, anc)
        next if span.nil?
        next unless (span[0] - u_limit).abs < 0.51 || (span[1] - u_limit).abs < 0.51
        # The face of it that the tile runs into is the one that crosses
        # this face right where the run stopped - measured, not guessed.
        sd = %w[a b].min_by do |q|
          f = frame(x1, y1, x2, y2, th, anc, q)
          f && cross_u(fr, f) ? (cross_u(fr, f) - u_limit).abs : 1.0e9
        end
        f2 = frame(x1, y1, x2, y2, th, anc, sd)
        next if f2.nil?
        # And the same question the other way round: where does THIS wall
        # block that face, and which way from there is clear?
        back = blocked_span(f2, mine[0], mine[1], mine[2], mine[3], mine[4], mine[5])
        next if back.nil?
        a2, b2 = back
        # WHICH WAY ROUND THE CORNER: THE ROOM DECIDES (2026-09-20, his
        # picture - the run hopped round the corner and landed on the far
        # side of the interior wall, in the next room, so nothing could be
        # drawn at all). THIS wall blocks a2..b2 of that face; the face we
        # are tiling crosses it at ONE of those two ends, and that end is
        # the room we are standing in. Measured, not ordered.
        cu = cross_u(f2, fr)
        if cu
          if (cu - a2).abs <= (cu - b2).abs
            return { wall: w2, side: sd, u_from: a2, dir: -1.0, len: f2[:len] } if a2 > 1.0
          elsif b2 < f2[:len] - 1.0
            return { wall: w2, side: sd, u_from: b2, dir: 1.0, len: f2[:len] }
          end
          next
        end
        if b2 < f2[:len] - 1.0
          return { wall: w2, side: sd, u_from: b2, dir: 1.0, len: f2[:len] }
        elsif a2 > 1.0
          return { wall: w2, side: sd, u_from: a2, dir: -1.0, len: f2[:len] }
        end
      end
      nil
    rescue StandardError => e
      puts "[TileWall] the next wall round the corner could not be found: #{e.message}"
      nil
    end

    # AFTER AN AREA IS BUILT, LAY ITS CORNER NEIGHBOURS AGAIN (2026-09-18,
    # he caught it twice: "שוב שברת את הפינה שצריכה להשאיר את המרובע
    # הריק"). An area laid BEFORE its neighbour existed had nothing to
    # pull back from, so its tile runs into the square. Whoever builds an
    # area calls this afterwards, and the areas on the walls standing at
    # its two ends are laid once more, now that they can see it.
    # WHICH OTHER TILED WALLS SHARE A CORNER WITH THIS AREA (2026-09-20).
    # An area at each of its two ends may butt a perpendicular area. The
    # old code asked neighbour_at, which matches a corner only within
    # 0.51" - but where the LAST tile meets the PREVIOUS tile the two ends
    # sit one tile depth (5/8") apart, so it silently skipped the re-lay
    # and that one corner filled in solid. His picture: one square full,
    # three empty. A corner is a corner when the two areas' ends are within
    # a tile depth of each other in world space, on walls that cross.
    # Returns the wall_ids to lay again. tile_corner_report.txt, rt189.
    def self.corner_neighbour_wall_ids(grp, model = Sketchup.active_model)
      return [] unless grp && grp.valid?
      wall = wall_by_id(grp.get_attribute('InteriorPro', 'wall_id'), model)
      return [] if wall.nil?
      fr = frame_for(wall, grp.get_attribute('InteriorPro', 'side'))
      return [] if fr.nil?
      me = grp.get_attribute('InteriorPro', 'id').to_s
      u0 = grp.get_attribute('InteriorPro', 'u0').to_f
      w  = grp.get_attribute('InteriorPro', 'area_w').to_f
      z0 = grp.get_attribute('InteriorPro', 'z0').to_f
      dp = grp.get_attribute('InteriorPro', 'tile_depth').to_f
      dp = DEFAULT_DEPTH if dp <= 0.0
      mine = [u0, u0 + w].map { |u| xy = world(fr, u, z0, 0.0); [xy[0], xy[1]] }
      reach = dp + 0.6
      ids = []
      areas_in_model(model).each do |og|
        next unless og.valid?
        next if og.get_attribute('InteriorPro', 'id').to_s == me
        owall = wall_by_id(og.get_attribute('InteriorPro', 'wall_id'), model)
        next if owall.nil?
        ofr = frame_for(owall, og.get_attribute('InteriorPro', 'side'))
        next if ofr.nil?
        next if (fr[:ux] * ofr[:ux] + fr[:uy] * ofr[:uy]).abs > 0.99
        ou0 = og.get_attribute('InteriorPro', 'u0').to_f
        ow  = og.get_attribute('InteriorPro', 'area_w').to_f
        oz0 = og.get_attribute('InteriorPro', 'z0').to_f
        theirs = [ou0, ou0 + ow].map { |u| xy = world(ofr, u, oz0, 0.0); [xy[0], xy[1]] }
        near = mine.any? { |mp| theirs.any? { |tp| Math.hypot(mp[0] - tp[0], mp[1] - tp[1]) <= reach } }
        ids << og.get_attribute('InteriorPro', 'wall_id').to_s if near
      end
      ids.uniq
    rescue StandardError => e
      puts "[TileWall] the corner neighbours could not be found: #{e.message}"
      []
    end

    def self.refresh_corner_neighbours!(grp, model = Sketchup.active_model)
      return 0 unless grp && grp.valid?
      wall = wall_by_id(grp.get_attribute('InteriorPro', 'wall_id'), model)
      return 0 if wall.nil?
      fr = frame_for(wall, grp.get_attribute('InteriorPro', 'side'))
      return 0 if fr.nil?
      n = 0
      corner_neighbour_wall_ids(grp, model).each { |wid| n += refresh_wall!(wid) }
      puts "[TileWall] #{n} neighbouring area(s) laid again for the corner square" if n > 0
      n
    rescue StandardError => e
      puts "[TileWall] the corner neighbours could not be laid again: #{e.message}"
      0
    end

    # THE WHOLE SHOWER (2026-09-18, his call: "אבל את כל הקירות של אותה
    # המקלחת", and when asked what that means he chose the CHAIN - every
    # tiled area joined to this one round the corners, wall after wall,
    # not "everything in the room"). One area stands on one face; at each
    # of its two ends neighbour_at says which face round the corner the
    # run carries on to, and an area standing there, starting where the
    # run picks up, is part of the same shower. Then from that one, again.
    #
    # PURE: `areas` is a list of {id:, wall_id:, side:, u0:, w:} and `nb`
    # answers (wall_id, side, u) with {wall_id:, side:, u_from:, dir:} or
    # nil - so tests/rt182.rb pins it without a model. Returns the ids,
    # the one it started from first.
    CHAIN_TOL = 3.0 unless const_defined?(:CHAIN_TOL, false)

    def self.chain_ids(areas, start_id, nb, tol = CHAIN_TOL)
      by_id = {}
      Array(areas).each { |a| by_id[a[:id].to_s] = a }
      seen  = [start_id.to_s]
      queue = [start_id.to_s]
      until queue.empty?
        a = by_id[queue.shift]
        next if a.nil?
        [a[:u0].to_f, a[:u0].to_f + a[:w].to_f].each do |u|
          n = nb.call(a[:wall_id].to_s, a[:side].to_s, u)
          next if n.nil?
          Array(areas).each do |b|
            next if seen.include?(b[:id].to_s)
            next unless b[:wall_id].to_s == n[:wall_id].to_s && b[:side].to_s == n[:side].to_s
            edge = n[:dir].to_f > 0 ? b[:u0].to_f : b[:u0].to_f + b[:w].to_f
            next unless (edge - n[:u_from].to_f).abs <= tol
            seen << b[:id].to_s
            queue << b[:id].to_s
          end
        end
      end
      seen
    end

    # THE SIDES FOLLOW THE WALL HE CENTRED (2026-09-18, his picture: the
    # back wall centred, the two side walls still on their old layout, and
    # the grout lines break at the corners. His words: "שהצדדים ילכו עם
    # הפריסה המתאימה לשינוי הקיר שאני משנה אותו").
    #
    # The joint lattice of the edited area is worked out once (where its
    # first joint sits, same as the grid does), and then walked round the
    # corners: at each corner the tile is cut at `cut` inches, and the
    # next wall gets a shift so that its own lattice carries that tile on
    # - the same rule carry_ox uses for a run that wraps, only now from
    # ANY starting layout, centred or not, and in BOTH directions. From
    # that wall, again, to the next.
    #
    # PURE. `areas` as chain_ids takes them, plus bu0:/bw: (what was
    # really built, after the corner square); the start area also carries
    # ox: and cen_u: (its own centring along the wall). Returns
    # { id => ox } for every OTHER area in the chain - the shift each one
    # needs, measured from its own built edge, with its along-the-wall
    # centring OFF (the lattice is the shift now).
    def self.follow_layout(areas, start_id, nb, u_size, grout = 0.0, tol = CHAIN_TOL)
      size = u_size.to_f
      return {} if size <= 0.01
      pitch = size + [grout.to_f, 0.0].max
      by_id = {}
      Array(areas).each { |a| by_id[a[:id].to_s] = a }
      a0 = by_id[start_id.to_s]
      return {} if a0.nil?
      s0 = InteriorPro::TileGrid.start(a0[:bu0].to_f, a0[:bu0].to_f + a0[:bw].to_f / 2.0,
                                       size, pitch, a0[:ox].to_f, a0[:cen_u])
      out = {}
      seen  = [a0[:id].to_s]
      queue = [[a0[:id].to_s, s0]]
      until queue.empty?
        id, sx = queue.shift
        a = by_id[id]
        [a[:u0].to_f, a[:u0].to_f + a[:w].to_f].each do |u_end|
          n = nb.call(a[:wall_id].to_s, a[:side].to_s, u_end)
          next if n.nil?
          # How far the corner is past the last tile start of this lattice.
          # Unwrap the run round the corner and the next wall's lattice
          # has a tile start exactly that far BEFORE the corner - the same
          # sum whichever way the next wall runs (rt185 does both ways),
          # and a corner that falls in a grout line splits the grout.
          rem = (u_end - sx) % pitch
          rem = 0.0 if rem < 1.0e-6 || (pitch - rem) < 1.0e-6
          Array(areas).each do |b|
            next if seen.include?(b[:id].to_s)
            next unless b[:wall_id].to_s == n[:wall_id].to_s && b[:side].to_s == n[:side].to_s
            edge = n[:dir].to_f > 0 ? b[:u0].to_f : b[:u0].to_f + b[:w].to_f
            next unless (edge - n[:u_from].to_f).abs <= tol
            joint = n[:u_from].to_f - rem
            ox_b = joint - b[:bu0].to_f
            sb = InteriorPro::TileGrid.start(b[:bu0].to_f, b[:bu0].to_f + b[:bw].to_f / 2.0,
                                             size, pitch, ox_b, false)
            out[b[:id].to_s] = ox_b
            seen << b[:id].to_s
            queue << [b[:id].to_s, sb]
          end
        end
      end
      out
    end

    # The area list and the corner lookup, off the model, for chain_ids
    # and follow_layout.
    def self.chain_input(model = Sketchup.active_model)
      groups = areas_in_model(model).select(&:valid?)
      areas = groups.map do |g|
        a = lambda { |k| g.get_attribute('InteriorPro', k) }
        { id: a.call('id').to_s, wall_id: a.call('wall_id').to_s, side: a.call('side').to_s,
          u0: a.call('u0').to_f, w: a.call('area_w').to_f,
          bu0: (a.call('built_u0') || a.call('u0')).to_f,
          bw: (a.call('built_w') || a.call('area_w')).to_f,
          ox: a.call('pattern_ox').to_f,
          cen_u: axis_value(a.call('pattern_center_axis')).include?('u') ? center_value(a.call('pattern_center')) : false }
      end
      nb = lambda do |wall_id, side, u|
        wall = wall_by_id(wall_id, model)
        next nil if wall.nil?
        fr = frame_for(wall, side)
        next nil if fr.nil?
        n = neighbour_at(wall, fr, u, model)
        next nil if n.nil?
        { wall_id: n[:wall].get_attribute('InteriorPro', 'id').to_s, side: n[:side],
          u_from: n[:u_from], dir: n[:dir] }
      end
      [groups, areas, nb]
    end

    # The same, on the model: the area groups joined to `grp`, itself first.
    def self.connected_areas(grp, model = Sketchup.active_model)
      return [grp] unless grp && grp.valid?
      groups, areas, nb = chain_input(model)
      ids = chain_ids(areas, grp.get_attribute('InteriorPro', 'id'), nb)
      ids.map { |id| groups.find { |g| g.get_attribute('InteriorPro', 'id').to_s == id } }.compact
    rescue StandardError => e
      puts "[TileWall] the connected areas could not be walked: #{e.message}"
      [grp]
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
                    depth: nil, mode: 'tiles',
                    ox: 0.0, oy: 0.0, centered: false, center_axis: 'uv', id: nil,
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
      dp = depth.nil? ? DEFAULT_DEPTH : depth.to_f
      dp = 0.0 if dp < 0.02
      dp = [dp, 3.0].min

      # TWO WAYS TO LAY IT (2026-09-17, his call): 'tiles' cuts a solid
      # for every tile - that is what gives real cut pieces and a real
      # count. 'image' lays the marked area as ONE slab and repeats the
      # photo across it at its true size, so the pattern IN the picture is
      # the tile: star-and-cross, a diagonal chequer, painted cement
      # tiles. Drawing those tile by tile would need a shape per tile;
      # the photo already has them. The QUANTITIES are still counted off
      # the real tile size either way, so the order does not change.
      md = mode.to_s == 'image' ? 'image' : 'tiles'
      holes = openings.nil? ? openings_for(wall, fr, model) : openings

      # THE CORNER SQUARE. The numbers he drew are STORED untouched and
      # only the geometry is pulled back, so rebuilding an area can never
      # shrink it a second time.
      bu0 = u0
      bw  = w
      if USE_CORNER_GAP
        lo, hi = corner_ends(wall, fr, u0, w, z0, model)
        if lo > 0.0 || hi > 0.0
          bu0, bw = trim_for_corners(u0, w, lo, hi)
          puts "[TileWall] corner square: back #{lo.round(3)} at the start, " \
               "#{hi.round(3)} at the far end"
        end
      end
      if bw <= 0.1
        puts "[TileWall] the corner square left nothing to tile (#{bw.round(2)} wide)"
        return nil
      end

      # THE NICHES THAT GET TILED INSIDE. Only whole solid tiles, laid
      # straight, with a real card - the mitre is cut out of the tile's own
      # body. Any other niche stays the bare hole it was.
      niches = []
      if USE_NICHE_TILES && md == 'tiles' && USE_SOLID_TILES && dp > 0.02 && c &&
         angle.to_f.abs < 1.0e-9 && defined?(InteriorPro::TileNiche)
        InteriorPro::TileNiche.read(wall).select { |n| n[:side].to_s == fr[:side] }.each do |n|
          nr = [n[:u0], n[:z0], n[:u0] + n[:w], n[:z0] + n[:h]]
          inside = nr[0] >= bu0 - 0.01 && nr[2] <= bu0 + bw + 0.01 &&
                   nr[1] >= z0 - 0.01 && nr[3] <= z0 + h + 0.01
          next unless nr[2] > bu0 && nr[0] < bu0 + bw && nr[3] > z0 && nr[1] < z0 + h
          unless inside
            puts "[TileWall] a niche runs past the edge of this area - left as a bare hole"
            next
          end
          idx = holes.index { |hh| hh.map { |v| v.to_f.round(3) } == nr.map { |v| v.to_f.round(3) } }
          if idx.nil?
            puts '[TileWall] a niche is not among the holes of this wall - left as it is'
            next
          end
          holes = holes.dup
          holes[idx] = niche_inset(nr, dp)
          niches << { r: nr, depth: n[:depth].to_f, tile: n[:tile] }
        end
      end

      area = area_polys(bu0, z0, bw, h, holes)
      if area.empty?
        puts '[TileWall] the openings cover the whole area - nothing left to tile'
        return nil
      end

      # The tile measured ALONG the wall is `tile_w`, the same way round
      # as the floor (UNIT_W_ALONG_LAYOUT there). One word, in the open.
      cen = center_for_grid(centered, center_axis)
      ps = pieces_rect(bu0, z0, bw, h, holes, u_size: tw, v_size: tl, grout: g,
                       angle: angle, ox: ox, oy: oy, centered: cen,
                       stagger: st)
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

        if md == 'image' && mat
          rings = angle.to_f.abs > 1.0e-9 ? area : cut(bu0, z0, bu0 + bw, z0 + h, holes)
          if dp > 0.02 && USE_SOLID_TILES
            emit_slab_solids!(ge, fr, rings, mat, img_w || tw, img_l || tl, dp)
          else
            emit_slab_faces!(ge, fr, rings, mat, img_w || tw, img_l || tl)
          end
        else
          solid = USE_SOLID_TILES && dp > 0.02 && mat
          if solid && ps.length > MAX_SOLID
            puts "[TileWall] #{ps.length} tiles is past #{MAX_SOLID} - built flat instead of solid"
            solid = false
          end
          # THE GROUT IS AT THE TILE'S EDGE (2026-09-17, his correction:
          # "הגראוט צריך להיות בקצה ה-TILE"). Real grout is filled flush
          # with the tile and tooled back a hair - not a plane sitting deep
          # behind it, which is what half the depth looked like.
          if mat
            back = solid ? [dp - GROUT_BACK, GROUT_OFF].max : GROUT_OFF
            emit_area_faces!(ge, fr, area, grout_material(model, grout_color), back)
          end
          if solid
            emit_tile_solids!(ge, fr, ps, mat, img_w || tw, img_l || tl, dp)
            unless niches.empty?
              bev = bevel_niche_tiles!(ge, fr, niches.map { |x| niche_inset(x[:r], dp) }, dp)
              cells = InteriorPro::TileGrid.cells(rect(bu0, z0, bw, h), u_size: tw, v_size: tl,
                                                  grout: g, angle: 0.0, ox: ox, oy: oy,
                                                  centered: cen, stagger: st) || []
              gm = grout_material(model, grout_color)
              lin = 0
              niches.each do |x|
                lin += emit_niche_lining!(ge, fr, x, cells, tw, tl, g, dp, mat,
                                          img_w || tw, img_l || tl, gm)
              end
              msg = "[TileWall] niche: #{niches.length} lined, #{bev} corner(s) of the wall tile bevelled, " \
                    "#{lin} tile(s) inside"
              puts msg
              niche_trace(msg + " | area #{aid} wall #{wall.get_attribute('InteriorPro', 'id').to_s[0, 8]} " \
                          "side #{fr[:side]} tile #{tw}x#{tl} dp #{dp} | " +
                          niches.map { |x| "niche #{x[:r].map { |v| v.round(2) }.inspect} deep #{x[:depth].round(2)}" }.join(' ; '))
            end
          elsif !niches.empty?
            puts '[TileWall] the tiles here are flat, not solid - the niche is left without its lining'
          elsif mat
            emit_tile_faces!(ge, fr, ps, mat, img_w || tw, img_l || tl)
          else
            emit_tile_edges!(ge, fr, ps)
          end
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
        # What the geometry REALLY used, after the corner square came off -
        # this is the number the next wall picks its phase up from.
        grp.set_attribute('InteriorPro', 'built_u0', bu0)
        grp.set_attribute('InteriorPro', 'built_w', bw)
        grp.set_attribute('InteriorPro', 'material_card_id', card_id.to_s)
        grp.set_attribute('InteriorPro', 'tile_w', tw)
        grp.set_attribute('InteriorPro', 'tile_l', tl)
        grp.set_attribute('InteriorPro', 'tile_depth', dp)
        grp.set_attribute('InteriorPro', 'tile_mode', md)
        grp.set_attribute('InteriorPro', 'pattern_grout', g)
        grp.set_attribute('InteriorPro', 'pattern_grout_color', grout_color.to_s)
        grp.set_attribute('InteriorPro', 'pattern_stagger', st)
        grp.set_attribute('InteriorPro', 'pattern_angle', angle.to_f)
        grp.set_attribute('InteriorPro', 'pattern_ox', ox.to_f)
        grp.set_attribute('InteriorPro', 'pattern_oy', oy.to_f)
        grp.set_attribute('InteriorPro', 'pattern_center', center_value(centered))
        grp.set_attribute('InteriorPro', 'pattern_center_axis', axis_value(center_axis))
        model.commit_operation if wrap_operation

        Watch.start! if defined?(Sketchup::ModelObserver)
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
      areas_in_model.to_a.each { |g| n += 1 if rebuild_area!(g) }
      puts "[TileWall] #{n} area(s) rebuilt" if n > 0
      n
    end

    # Rebuild the areas on ONE wall - what the watcher below calls when a
    # window on that wall moves.
    def self.refresh_wall!(wall_id)
      n = 0
      areas_in_model.to_a.each do |g|
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'wall_id').to_s == wall_id.to_s
        n += 1 if rebuild_area!(g)
      end
      n
    end

    # What is centred on the middle of the area: nothing (false), a whole
    # TILE (true), or a GROUT line ('grout'). One spelling for the
    # attribute, the build and the window, so the three cannot disagree.
    def self.center_value(v)
      return 'grout' if v.to_s == 'grout'
      v ? true : false
    end

    # WHICH WAY it is centred: 'uv' both (the default, and what every
    # area drawn before today has), 'u' along the wall only, 'v' up the
    # wall only. Anything else is 'uv'.
    def self.axis_value(v)
      %w[u v uv].include?(v.to_s) ? v.to_s : 'uv'
    end

    # What the grid gets: the centring on the axes he chose, and plain
    # from-the-edge on the other.
    def self.center_for_grid(centered, axis)
      c = center_value(centered)
      ax = axis_value(axis)
      { u: ax.include?('u') ? c : false, v: ax.include?('v') ? c : false }
    end

    def self.rebuild_area!(g, wrap_operation = true)
      return false unless g.valid?
      a = lambda { |k| g.get_attribute('InteriorPro', k) }
      wall = wall_by_id(a.call('wall_id'))
      if wall.nil?
        puts "[TileWall] area #{a.call('id')} lost its wall - erased"
        g.erase!
        return false
      end
      build!(wall: wall, side: a.call('side'), u0: a.call('u0').to_f,
                    z0: a.call('z0').to_f, w: a.call('area_w').to_f,
                    h: a.call('area_h').to_f, card_id: a.call('material_card_id'),
                    tile_w: a.call('tile_w').to_f, tile_l: a.call('tile_l').to_f,
                    grout: a.call('pattern_grout').to_f,
                    grout_color: a.call('pattern_grout_color'),
                    depth: a.call('tile_depth'),
                    mode: a.call('tile_mode'),
                    stagger: a.call('pattern_stagger').to_f,
                    angle: a.call('pattern_angle').to_f,
                    ox: a.call('pattern_ox').to_f, oy: a.call('pattern_oy').to_f,
                    centered: center_value(a.call('pattern_center')),
                    center_axis: axis_value(a.call('pattern_center_axis')),
                    id: a.call('id'), wrap_operation: wrap_operation) ? true : false
    end

    # ---- the watcher ----------------------------------------------------
    #
    # His words (2026-09-17): "אם אני ציירתי טיל על חלון ואני מזיז את
    # החלון הטיל צריך להשתנות בהתאם."
    #
    # It watches instead of hooking into the window and door tools on
    # purpose: a window can also be moved with SketchUp's own Move tool,
    # or by the 2D editor, or undone - and a hook in one tool would miss
    # all of those. So after every committed change we compare a short
    # SIGNATURE of the openings on the walls that carry tiles, and rebuild
    # only the areas whose wall actually changed. Nothing changed = no
    # work, so this costs nothing while he draws.
    #
    # The rebuild is deferred by a timer: building geometry inside a
    # transaction callback is how you crash SketchUp.
    module Watch
      def self.signature(model = Sketchup.active_model)
        tw = InteriorPro::TileWall
        ids = tw.areas_in_model(model).map { |g| g.get_attribute('InteriorPro', 'wall_id').to_s }.uniq
        sig = {}
        ids.each do |wid|
          wall = tw.wall_by_id(wid, model)
          next if wall.nil?
          fr = { floor_z: wall.bounds.min.z.to_f, ox: 0, oy: 0, ux: 0, uy: 0 }
          rows = tw.openings_for(wall, fr, model).map { |r| r.map { |v| (v.to_f * 16.0).round } }
          sig[wid] = rows.sort.to_s + wall.bounds.min.to_a.map { |v| (v.to_f * 16.0).round }.to_s
        end
        sig
      end

      def self.start!(model = Sketchup.active_model)
        return false if model.nil?
        @sig = signature(model)
        return true if @observer && @model == model
        @model = model
        @observer = ModelWatcher.new
        model.add_observer(@observer)
        true
      rescue StandardError => e
        puts "[TileWall] the watcher did not start: #{e.message}"
        false
      end

      def self.stop!
        @model.remove_observer(@observer) if @model && @observer && @model.valid?
        @observer = nil
        @model = nil
      rescue StandardError
        nil
      end

      def self.schedule!
        return if @pending || @busy
        @pending = true
        UI.start_timer(0.1, false) { check! }
      rescue StandardError
        @pending = false
      end

      def self.check!
        @pending = false
        return if @busy
        model = Sketchup.active_model
        return if model.nil?
        now = signature(model)
        old = @sig || {}
        changed = now.keys.select { |k| old[k] != now[k] }
        @sig = now
        return if changed.empty?
        @busy = true
        begin
          changed.each do |wid|
            n = InteriorPro::TileWall.refresh_wall!(wid)
            puts "[TileWall] an opening on wall #{wid} moved - #{n} area(s) re-laid" if n > 0
          end
          @sig = signature(model)
        ensure
          @busy = false
        end
      rescue StandardError => e
        @busy = false
        puts "[TileWall] the watcher failed: #{e.class}: #{e.message}"
      end
    end

    # Defined only where SketchUp is - tests/rt175.rb requires this file
    # on its own, with no SketchUp at all.
    if defined?(Sketchup::ModelObserver)
      class ModelWatcher < Sketchup::ModelObserver
        def onTransactionCommit(_model)
          InteriorPro::TileWall::Watch.schedule!
        end

        def onTransactionUndo(_model)
          InteriorPro::TileWall::Watch.schedule!
        end

        def onTransactionRedo(_model)
          InteriorPro::TileWall::Watch.schedule!
        end
      end
    end

    # ---- emitters --------------------------------------------------------

    # MEASURE, DO NOT GUESS: every niche that gets lined writes one line to
    # niche_trace.txt next to the code, so it can be read without asking
    # him to paste anything.
    def self.niche_trace(line)
      File.open(File.join(__dir__, 'niche_trace.txt'), 'a:UTF-8') do |f|
        f.puts "#{Time.now.strftime('%H:%M:%S')} #{line}"
      end
    rescue StandardError => e
      puts "[TileWall] niche trace failed: #{e.message}"
    end

    # THE WALL TILE'S HALF OF THE MITRE. Every vertex on the BACK plane of
    # a wall tile that sits on a niche's inset edge moves out onto the
    # niche's own edge, so that edge of the tile becomes the 45 bevel.
    # Returns how many vertices moved.
    def self.bevel_niche_tiles!(ge, fr, insets, dp)
      moved = 0
      ge.grep(Sketchup::Group).each do |sub|
        next unless sub.valid?
        verts = []
        vecs = []
        sub.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.each do |v|
          p = v.position
          out = (p.x - fr[:ox]) * fr[:nx] + (p.y - fr[:oy]) * fr[:ny]
          next if out.abs > 1.0e-3
          u = (p.x - fr[:ox]) * fr[:ux] + (p.y - fr[:oy]) * fr[:uy]
          z = p.z - fr[:floor_z]
          sh = nil
          insets.each { |ins| sh ||= bevel_shift(u, z, ins, dp) }
          next if sh.nil?
          verts << v
          vecs << Geom::Vector3d.new(fr[:ux] * sh[0], fr[:uy] * sh[0], sh[1])
        end
        next if verts.empty?
        begin
          sub.entities.transform_by_vectors(verts, vecs)
          moved += verts.length
        rescue StandardError => e
          puts "[TileWall] a tile at the niche could not be bevelled: #{e.message}"
        end
      end
      moved
    end

    # THE NICHE'S OWN TILE - back, both sides, bottom, top. Each tile in its
    # own group (the law that crashed SketchUp), each lining's grout in its
    # own group too. Returns how many tiles were built.
    # Which linings wear the niche's OWN tile: the back only, or all five.
    # PURE.
    def self.own_tile_keys(where)
      where.to_s == 'all' ? %i[back left right bottom top] : %i[back]
    end

    # The niche's own grid: its tile, centred on the niche's back (a tiler
    # centres the back of a niche). PURE.
    def self.niche_own_cells(nr, tw, tl, g)
      u0, z0, u1, z1 = nr.map(&:to_f)
      InteriorPro::TileGrid.cells(rect(u0, z0, u1 - u0, z1 - z0), u_size: tw.to_f, v_size: tl.to_f,
                                  grout: g.to_f, angle: 0.0, ox: 0.0, oy: 0.0, centered: true, stagger: 0.0)
    end

    # The niche's own tile, as the lining needs it: sets, material and the
    # picture size. nil = none stored, switched off, or it cannot be made.
    def self.niche_own(x, dp)
      t = x[:tile]
      return nil unless t && USE_NICHE_OWN_TILE
      c = card(t['card'])
      return nil if c.nil?
      m = (InteriorPro::MaterialLibraryDialog.material_from_card(Sketchup.active_model, c) rescue nil)
      if m.nil?
        puts "[TileWall] the niche's card '#{t['card']}' gave no material - the wall's tile is used"
        return nil
      end
      tw = t['tile_w'].to_f > 0.25 ? t['tile_w'].to_f : (c['tile_w_inches'] || c['texture_width_inches']).to_f
      tl = t['tile_l'].to_f > 0.25 ? t['tile_l'].to_f : (c['tile_l_inches'] || c['texture_height_inches']).to_f
      tw = 12.0 if tw <= 0.25
      tl = tw if tl <= 0.25
      g = [t['grout'].to_f, [tw, tl].min * 0.4].min
      sets = niche_lining(niche_own_cells(x[:r], tw, tl, g), tw, tl, g, x[:r], dp, x[:depth])
      return nil if sets.nil?
      iw = c['texture_width_inches'].to_f
      ih = c['texture_height_inches'].to_f
      { sets: sets, mat: m, tex_u: iw > 0.25 ? iw : tw, tex_v: ih > 0.25 ? ih : tl, keys: own_tile_keys(t['where']) }
    rescue StandardError => e
      puts "[TileWall] the niche's own tile failed - the wall's tile is used: #{e.message}"
      nil
    end

    def self.emit_niche_lining!(ge, fr, x, cells, tw, tl, g, dp, mat, tex_u, tex_v, gmat)
      sets = niche_lining(cells, tw, tl, g, x[:r], dp, x[:depth])
      if sets.nil?
        puts "[TileWall] this niche is too small or too shallow (#{x[:depth].round(2)}\") for tile inside"
        return 0
      end
      own = niche_own(x, dp)
      if own
        own[:keys].each { |k| sets[k] = own[:sets][k] }
        puts "[TileWall] niche: its own tile on #{own[:keys].join(', ')}"
      end
      frames = lining_frames(fr, x[:r], x[:depth])
      built = 0
      fails = 0
      sets.each do |key, set|
        lf = frames[key]
        a0, b0, a1, b1 = set[:grout]
        gg = ge.add_group
        gf = begin
          gg.entities.add_face(rect_ring(a0, b0, a1, b1).map { |a, b| Geom::Point3d.new(*lining_world(lf, a, b, dp - GROUT_BACK)) })
        rescue StandardError
          nil
        end
        if gf
          gf.material = gmat
          gf.back_material = gmat
          gf.edges.each { |e| e.hidden = true }
        else
          gg.erase! if gg.valid?
        end
        set[:pieces].each do |pc|
          mine = own && own[:keys].include?(key)
          km = mine ? own[:mat] : mat
          ku = mine ? own[:tex_u] : tex_u
          kv = mine ? own[:tex_v] : tex_v
          if lining_solid!(ge, lf, pc, dp, km, key == :back ? ku : (key == :left || key == :right ? ku : kv),
                           key == :back ? kv : (key == :left || key == :right ? kv : ku))
            built += 1
          else
            fails += 1
          end
        end
      end
      puts "[TileWall] niche lining: #{fails} tile(s) could not be built" if fails > 0
      built
    end

    def self.lining_solid!(ge, lf, pc, dp, mat, tex_a, tex_b)
      sub = ge.add_group
      pts = pc[:poly].map { |a, b| Geom::Point3d.new(*lining_world(lf, a, b, dp)) }
      f = begin
        sub.entities.add_face(pts)
      rescue StandardError
        nil
      end
      if f.nil?
        sub.erase! if sub.valid?
        return false
      end
      nrm = Geom::Vector3d.new(*lf[:n])
      begin
        f.pushpull(f.normal.dot(nrm) > 0 ? -dp : dp)
      rescue StandardError
        puts '[TileWall] a niche tile could not be pushed out'
      end
      sub.entities.grep(Sketchup::Face).each do |q|
        q.material = mat
        q.back_material = mat
      end
      if f.valid?
        o = Geom::Point3d.new(*lining_world(lf, pc[:a0], pc[:b0], dp))
        pa = Geom::Point3d.new(*lining_world(lf, pc[:a0] + tex_a, pc[:b0], dp))
        pb = Geom::Point3d.new(*lining_world(lf, pc[:a0], pc[:b0] + tex_b, dp))
        begin
          f.position_material(mat, [o, Geom::Point3d.new(0, 0, 0), pa, Geom::Point3d.new(1, 0, 0),
                                    pb, Geom::Point3d.new(0, 1, 0)], true)
        rescue StandardError
          nil
        end
      end
      # THE LINING'S HALF OF THE MITRE: its front edge on the tile face
      # comes forward by dp, onto the same 45 plane as the wall tile.
      if lf[:bevel]
        verts = sub.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.select do |v|
          a, _b, out = lining_local(lf, v.position.x, v.position.y, v.position.z)
          a.abs < 1.0e-3 && (out - dp).abs < 1.0e-3
        end
        unless verts.empty?
          vec = Geom::Vector3d.new(*lf[:a].map { |q| -q * dp })
          begin
            sub.entities.transform_by_vectors(verts, [vec] * verts.length)
          rescue StandardError => e
            puts "[TileWall] a niche tile could not be bevelled: #{e.message}"
          end
        end
      end
      true
    end

    # A face from a ring, with the ring's island holes punched through it:
    # an inner face is drawn on the same plane and erased, which leaves
    # the outer face with an inner loop - SketchUp's own way to a hole.
    # nil when the outer face could not be drawn.
    def self.face_with_holes(ents, fr, ring, out)
      f = begin
        ents.add_face(pts3d(fr, ring, out))
      rescue StandardError
        nil
      end
      return nil if f.nil?
      ring_holes(ring).each do |h|
        begin
          inner = ents.add_face(pts3d(fr, h, out))
          inner.erase! if inner && inner.valid? && !inner.equal?(f)
        rescue StandardError => e
          puts "[TileWall] a hole could not be punched: #{e.message}"
        end
      end
      f.valid? ? f : nil
    end

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

    # THE WHOLE AREA AS ONE SLAB, with the photo repeating across it at
    # its true size - the 'image' way. One group per ring, so a notched
    # area is still one body.
    def self.emit_slab_solids!(ge, fr, rings, mat, tex_u, tex_v, depth)
      Array(rings).each do |ring|
        next if ring.nil? || ring.length < 3
        sub = ge.add_group
        f = face_with_holes(sub.entities, fr, ring, depth)
        if f.nil?
          puts '[TileWall] the slab face could not be built'
          sub.erase! if sub.valid?
          next
        end
        outward = Geom::Vector3d.new(fr[:nx], fr[:ny], 0)
        begin
          f.pushpull(f.normal.dot(outward) > 0 ? -depth : depth)
        rescue StandardError
          puts '[TileWall] the slab could not be pushed out'
        end
        sub.entities.grep(Sketchup::Face).each do |q|
          q.material = mat
          q.back_material = mat
        end
        map_photo!(f, fr, ring, mat, tex_u, tex_v, depth) if f.valid?
      end
    end

    def self.emit_slab_faces!(ge, fr, rings, mat, tex_u, tex_v)
      Array(rings).each do |ring|
        next if ring.nil? || ring.length < 3
        f = face_with_holes(ge, fr, ring, FACE_OFF)
        next if f.nil?
        f.material = mat
        f.back_material = mat
        map_photo!(f, fr, ring, mat, tex_u, tex_v, FACE_OFF)
        f.edges.each { |e| e.hidden = true; e.soft = true; e.smooth = true }
      end
    end

    # The photo at its TRUE size, anchored on the area's own corner, so it
    # repeats across the slab exactly as the tile does on the wall.
    def self.map_photo!(f, fr, ring, mat, tex_u, tex_v, out)
      au = ring.map { |q| q[0] }.min
      av = ring.map { |q| q[1] }.min
      ox, oy, oz = world(fr, au, av, out)
      o  = Geom::Point3d.new(ox, oy, oz)
      pu = Geom::Point3d.new(ox + fr[:ux] * tex_u, oy + fr[:uy] * tex_u, oz)
      pv = Geom::Point3d.new(ox, oy, oz + tex_v)
      f.position_material(mat, [o,  Geom::Point3d.new(0, 0, 0),
                                pu, Geom::Point3d.new(1, 0, 0),
                                pv, Geom::Point3d.new(0, 1, 0)], true)
    rescue StandardError => e
      puts "[TileWall] the photo could not be mapped: #{e.message}"
    end

    # SOLID TILE. Each tile is a little box standing `depth` off the wall,
    # in its OWN group. The picture is anchored to the tile's own corner
    # on the OUTER face, the same crop the floor does, and the four sides
    # get the same material so a cut edge does not flash white.
    def self.emit_tile_solids!(ge, fr, pieces, mat, tex_u, tex_v, depth)
      fails = 0
      pulls = 0
      pieces.each do |p|
        sub = ge.add_group
        f = face_with_holes(sub.entities, fr, p[:poly], depth)
        if f.nil?
          fails += 1
          sub.erase! if sub.valid?
          next
        end
        outward = Geom::Vector3d.new(fr[:nx], fr[:ny], 0)
        dist = f.normal.dot(outward) > 0 ? -depth : depth
        begin
          f.pushpull(dist)
        rescue StandardError
          pulls += 1
        end
        sub.entities.grep(Sketchup::Face).each do |q|
          q.material = mat
          q.back_material = mat
        end
        next unless f.valid?
        ox, oy, oz = world(fr, p[:u0], p[:v0], depth)
        o  = Geom::Point3d.new(ox, oy, oz)
        pu = Geom::Point3d.new(ox + fr[:ux] * tex_u, oy + fr[:uy] * tex_u, oz)
        pv = Geom::Point3d.new(ox, oy, oz + tex_v)
        begin
          f.position_material(mat, [o,  Geom::Point3d.new(0, 0, 0),
                                    pu, Geom::Point3d.new(1, 0, 0),
                                    pv, Geom::Point3d.new(0, 1, 0)], true)
        rescue StandardError
          nil
        end
      end
      puts "[TileWall] solid tiles: #{fails} face fail(s), #{pulls} pushpull fail(s)" if fails > 0 || pulls > 0
    end

    # Each tile piece is a face, painted with the card's picture anchored
    # to the tile's OWN corner - so a photo that holds several tiles
    # shows exactly one of them per tile, the crop the floor already does
    # (HANDOFF_2026-09-17B).
    def self.emit_tile_faces!(ge, fr, pieces, mat, tex_u, tex_v)
      face_fails = 0
      uv_fails = 0
      pieces.each do |p|
        f = face_with_holes(ge, fr, p[:poly], FACE_OFF)
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
        ([p[:poly]] + ring_holes(p[:poly])).each do |ring|
          pts = pts3d(fr, ring, FACE_OFF)
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
end

# Start watching as soon as the plugin loads, and again on reload.
if defined?(Sketchup) && defined?(Sketchup::ModelObserver) &&
   Sketchup.respond_to?(:active_model)
  begin
    InteriorPro::TileWall::Watch.start!
  rescue StandardError => e
    puts "[TileWall] watcher: #{e.message}"
  end
end

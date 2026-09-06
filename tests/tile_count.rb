# encoding: utf-8
# Interior Pro - HOW MANY TILES, NOT HOW MANY SQUARE FEET (2026-09-06)
#
# His words: "יש לי שתי חתיכות אז היא תמזג אותן ותספור לי אותן כחתיכה
# אחת". A 24x48 tile cut in half, with both halves used at two ends of a
# room, is ONE tile bought. Counting cut pieces naively doubles his
# order, and on large-format tile that is the difference between a right
# quote and a wrong one.
#
# And the rule he set for the leftovers: a remainder under 20% of the
# tile is waste - it is not paired with anything - and he wants those
# counted on their own line, "כדי שאני יכול לשאול את הקבלן כמה חתיכות
# לקנות בשביל רק ה-20% האזה".
#
# EVERYTHING HERE IS PURE. Plain numbers in, plain numbers out, no
# SketchUp API - so tests/rt164.rb pins it. The layout is a grid of tile
# cells laid over the room's own outline; a cell is a FULL tile only
# where the room covers the whole of it.
module InteriorPro
  module TileCount
    MIN_REUSE_PCT = 20.0 unless const_defined?(:MIN_REUSE_PCT, false)
    EPS = 1.0e-6 unless const_defined?(:EPS, false)

    # ---- small pure geometry -----------------------------------------

    # The part of `poly` inside the axis-aligned rectangle, by
    # Sutherland-Hodgman. The clipper is a rectangle, which is convex,
    # so this is exact even when the ROOM is L-shaped.
    def self.clip_rect(poly, x0, y0, x1, y1)
      out = poly
      [[1.0, 0.0, -x0], [-1.0, 0.0, x1], [0.0, 1.0, -y0], [0.0, -1.0, y1]].each do |(a, b, c)|
        out = clip_half(out, a, b, c)
        return [] if out.length < 3
      end
      out
    end

    # keep a*x + b*y + c >= 0
    def self.clip_half(poly, a, b, c)
      return [] if poly.nil? || poly.length < 3
      f = lambda { |p| a * p[0] + b * p[1] + c }
      out = []
      poly.each_index do |i|
        p = poly[i]
        q = poly[(i + 1) % poly.length]
        dp = f.call(p)
        dq = f.call(q)
        out << p if dp >= -EPS
        next unless (dp > EPS && dq < -EPS) || (dp < -EPS && dq > EPS)
        t = dp / (dp - dq)
        out << [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]
      end
      out
    end

    def self.area(poly)
      return 0.0 if poly.nil? || poly.length < 3
      s = 0.0
      poly.each_index do |i|
        p = poly[i]
        q = poly[(i + 1) % poly.length]
        s += p[0] * q[1] - q[0] * p[1]
      end
      (s / 2.0).abs
    end

    def self.bbox(poly)
      xs = poly.map { |p| p[0] }
      ys = poly.map { |p| p[1] }
      [xs.min, ys.min, xs.max, ys.max]
    end

    # ---- the layout ---------------------------------------------------

    # Lay a grid of tiles over the room and say what each cell is.
    #   poly    the room outline, in inches
    #   tw, tl  tile width and length, in inches
    #   grout   joint width
    #   ox, oy  where the first joint sits (the start point)
    #   stagger how far each row is pushed along - 0.5 is a running bond
    # Returns [full_count, cuts] where a cut is [w, h] of the piece that
    # actually has to be cut, rounded to 1/16".
    def self.layout(poly, tw, tl, grout: 0.0, ox: 0.0, oy: 0.0, stagger: 0.0)
      return [0, []] if poly.nil? || poly.length < 3 || tw <= 0 || tl <= 0
      x0, y0, x1, y1 = bbox(poly)
      pitch_x = tw + grout
      pitch_y = tl + grout
      cell_area = tw * tl
      full = 0
      cuts = []
      row = ((y0 - oy) / pitch_y).floor
      while oy + row * pitch_y < y1 + EPS
        cy = oy + row * pitch_y
        shift = (stagger.to_f % 1.0) * pitch_x * (row.abs % 2)
        col = ((x0 - ox - shift) / pitch_x).floor
        while ox + shift + col * pitch_x < x1 + EPS
          cx = ox + shift + col * pitch_x
          piece = clip_rect(poly, cx, cy, cx + tw, cy + tl)
          col += 1
          a = area(piece)
          next if a <= cell_area * 0.0005
          if a >= cell_area - EPS * 100
            full += 1
          else
            bx0, by0, bx1, by1 = bbox(piece)
            cuts << [r16(bx1 - bx0), r16(by1 - by0)]
          end
        end
        row += 1
      end
      [full, cuts]
    end

    def self.r16(v)
      (v.to_f * 16.0).round / 16.0
    end

    # ---- the counting he asked for ------------------------------------

    # PURE. Is this piece too small to be worth keeping?
    def self.small?(piece, tw, tl, pct = MIN_REUSE_PCT)
      (piece[0] * piece[1]) < (tw * tl) * (pct.to_f / 100.0)
    end

    # PURE. Does an offcut of ow x oh cover a piece of w x h, either way
    # round? A tile is cut, not stretched, so a piece fits if it is no
    # bigger in both directions.
    def self.fits?(offcut, piece)
      (offcut[0] >= piece[0] - EPS && offcut[1] >= piece[1] - EPS) ||
        (offcut[1] >= piece[0] - EPS && offcut[0] >= piece[1] - EPS)
    end

    # PURE. What is left of a whole tile after cutting `piece` out of it.
    # The bigger of the two rectangles the cut leaves - a tiler keeps one
    # strip, not a pile of confetti.
    def self.offcut(piece, tw, tl)
      side = [(tw - piece[0]) * tl, (tl - piece[1]) * tw]
      side[0] >= side[1] ? [r16(tw - piece[0]), tl] : [tw, r16(tl - piece[1])]
    end

    # THE ANSWER. Cut pieces are matched to offcuts of tiles already cut,
    # biggest piece first - the order matters, and taking the big ones
    # first is what a tiler does. A piece under the threshold is never
    # paired: it takes its own tile and its remainder is waste.
    def self.count(full, cuts, tw, tl, pct = MIN_REUSE_PCT)
      big = []
      small = []
      Array(cuts).each { |c| small?(c, tw, tl, pct) ? small << c : big << c }
      big = big.sort_by { |c| -(c[0] * c[1]) }
      offcuts = []
      from_new = 0
      paired = 0
      big.each do |piece|
        idx = offcuts.index { |o| fits?(o, piece) }
        if idx
          offcuts.delete_at(idx)
          paired += 1
        else
          from_new += 1
          o = offcut(piece, tw, tl)
          offcuts << o unless small?(o, tw, tl, pct)
        end
      end
      { full: full,
        cut_pieces: big.length,
        cut_tiles: from_new,
        paired: paired,
        small_pieces: small.length,
        tiles: full + from_new + small.length,
        pct: pct.to_f }
    end

    # Everything, from a room outline.
    def self.plan(poly, tw, tl, grout: 0.0, ox: 0.0, oy: 0.0, stagger: 0.0,
                  pct: MIN_REUSE_PCT)
      full, cuts = layout(poly, tw, tl, grout: grout, ox: ox, oy: oy,
                                stagger: stagger)
      count(full, cuts, tw, tl, pct)
    end

    # PURE. The lines of the report he reads.
    def self.lines(res, tw, tl)
      [format('tile %gx%g', tw, tl),
       format('  whole tiles            %6d', res[:full]),
       format('  cut pieces             %6d  (from %d tiles, %d taken from offcuts)',
              res[:cut_pieces], res[:cut_tiles], res[:paired]),
       format('  pieces under %g%%       %6d  (each one its own tile)',
              res[:pct], res[:small_pieces]),
       format('  TILES TO BUY           %6d', res[:tiles])]
    end
  end
end

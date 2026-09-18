# encoding: utf-8
# Interior Pro - ONE TILE LAYOUT, READ BY EVERYONE (2026-09-06)
#
# Until today the layout was computed TWICE. floor_pattern.rb drew it
# (and knew about the angle, the centring and the joint); tile_count.rb
# counted it (and knew about none of them). His words: "אני לא רוצה
# ששרטוט הפריסה יהיה רק דומה לרינדור."
#
# So this file is the one calculation. It answers a single question -
# WHERE DOES EVERY TILE SIT - and the drawer, the counter, the elevation
# drawing and later the render all read the answer from here.
#
# EVERYTHING HERE IS PURE. Plain numbers in, plain numbers out, no
# SketchUp API, so tests/rt166.rb pins it.
#
# THE JOINT (decided by him, 2026-09-06): the size you type is THE TILE
# YOU BUY. A 24" tile is 24". The joint is ADDED next to it, so on the
# floor each tile takes up 24 + grout. That is the pitch. (The old
# drawer did the opposite - it kept the pitch at 24 and shrank the tile -
# which meant a bigger joint never moved the layout at all.)
#
# THE TWO AXES ARE NAMED, NOT GUESSED. `u_size` runs along the layout
# direction (the pattern angle); `v_size` runs across it. The caller
# says which of unit_w / unit_l is which - this file never decides that
# for them, because the drawer and the counter disagree about it today
# and that has to be settled in the open, with a number, not in here.
module InteriorPro
  module TileGrid
    EPS = 1.0e-9 unless const_defined?(:EPS, false)
    # Loop tolerance. A cell whose near edge sits ON the far edge of the
    # room is outside it and is not emitted; TOL is only there so float
    # noise cannot turn "exactly on it" into "just inside it".
    TOL = 1.0e-6 unless const_defined?(:TOL, false)
    MAX_CELLS = 60_000 unless const_defined?(:MAX_CELLS, false)

    # ---- the frame -----------------------------------------------------

    # u runs along `angle` (radians), v is 90 degrees counter-clockwise
    # from it. At angle 0 that is plain x and y.
    def self.frame(angle = 0.0)
      a = angle.to_f
      { ux: Math.cos(a), uy: Math.sin(a), vx: -Math.sin(a), vy: Math.cos(a) }
    end

    def self.degrees(deg)
      frame(deg.to_f * Math::PI / 180.0)
    end

# A corner may arrive as [x, y] or as a Geom::Point3d - the drawer
# works in SketchUp points, the counter in plain pairs, and this
# file is read by both.
def self.xy(p)
  return [p[0].to_f, p[1].to_f] if p.is_a?(Array)
  [p.x.to_f, p.y.to_f]
end

    def self.to_uv(x, y, fr)
      [x.to_f * fr[:ux] + y.to_f * fr[:uy], x.to_f * fr[:vx] + y.to_f * fr[:vy]]
    end

    def self.to_xy(u, v, fr)
      [fr[:ux] * u + fr[:vx] * v, fr[:uy] * u + fr[:vy] * v]
    end

    # The area centroid of the outline - the same formula RoomManager
    # uses, written out here so this file needs no SketchUp.
    def self.centroid(poly)
      return [0.0, 0.0] if poly.nil? || poly.empty?
      a = 0.0
      cx = 0.0
      cy = 0.0
      poly.each_index do |i|
        px, py = xy(poly[i])
        qx, qy = xy(poly[(i + 1) % poly.length])
        cross = px * qy - qx * py
        a += cross
        cx += (px + qx) * cross
        cy += (py + qy) * cross
      end
      a /= 2.0
      return xy(poly.first) if a.abs < 1.0e-6
      [cx / (6.0 * a), cy / (6.0 * a)]
    end

    # How far the room reaches along u and along v, plus where its
    # centre lands in the same frame.
    def self.extent(poly, fr)
      us = []
      vs = []
      poly.each do |p|
        px, py = xy(p)
        u, v = to_uv(px, py, fr)
        us << u
        vs << v
      end
      c = centroid(poly)
      cu, cv = to_uv(c[0], c[1], fr)
      { u_min: us.min, u_max: us.max, v_min: vs.min, v_max: vs.max,
        cu: cu, cv: cv }
    end

    # ---- the start point -----------------------------------------------

    # Where the first joint sits, in the frame, at or before the room.
    #   centered  false - the layout starts at the room's own edge
    #             true  - a WHOLE tile is centred on the room's centre
    #   off       ox / oy, how far he pushes the layout from there
    # The answer is always pulled back by whole pitches, so the grid
    # covers the room from its very edge no matter what he types.
    #   centered  'grout' - a JOINT is centred instead: the middle of the
    #             room falls in the middle of a grout line, a whole tile
    #             either side of it (2026-09-18, his ask for the tiled
    #             wall: "סנטר לגראוט ליד סנטר לטיל"). Floors never pass
    #             it today, so nothing there moves.
    def self.start(edge, centre, size, pitch, off, centered)
      s = if centered.to_s == 'grout'
            centre + (pitch - size) / 2.0
          elsif centered
            centre - size / 2.0
          else
            edge
          end
      s += off.to_f
      return s if pitch <= EPS
      s - ((s - edge) / pitch).ceil * pitch
    end

    # ---- the cells ------------------------------------------------------

    # Every tile of the layout over this room.
    #
    #   poly     the room outline, [[x, y], ...], in inches
    #   u_size   the tile measured ALONG the layout direction
    #   v_size   the tile measured ACROSS it
    #   grout    the joint, ADDED next to the tile (pitch = size + grout)
    #   angle    the layout direction, in DEGREES
    #   ox, oy   how far the layout is pushed, along u and along v
    #   centered a whole tile sits on the middle of the room
    #   stagger  how far each second row is pushed along, 0..1 of a
    #            pitch - 0.5 is a running bond. Nothing in the dialog
    #            asks for one today; the drawer's Straight pattern does
    #            half a plank by hand, and this is where that will live.
    #
    # Each cell:
    #   iu, iv   which column and row it is (0 is the first one covered)
    #   u0, v0   its near corner, in the frame
    #   quad     its four corners in the model, [[x, y], ...], the TILE
    #            itself - the joint is the space left between quads
    #
    # Returns nil rather than a huge array if the tile is so small that
    # the room needs more than MAX_CELLS of them.
    def self.cells(poly, u_size:, v_size:, grout: 0.0, angle: 0.0,
                   ox: 0.0, oy: 0.0, centered: false, stagger: 0.0,
                   limit: MAX_CELLS)
      return [] if poly.nil? || poly.length < 3
      u_size = u_size.to_f
      v_size = v_size.to_f
      return [] if u_size <= EPS || v_size <= EPS
      g = [grout.to_f, 0.0].max
      pitch_u = u_size + g
      pitch_v = v_size + g

      fr = degrees(angle)
      ext = extent(poly, fr)
      # ONE WAY OR BOTH (2026-09-18, his ask: "מירכוז כללי, מירכוז אופקי
      # ומירכוז אנכי" - sometimes only the cut at the top or the bottom
      # matters). A Hash {u:, v:} centres each direction on its own; a
      # plain value is both, exactly as before.
      cen_u = centered.is_a?(Hash) ? centered[:u] : centered
      cen_v = centered.is_a?(Hash) ? centered[:v] : centered
      u0 = start(ext[:u_min], ext[:cu], u_size, pitch_u, ox, cen_u)
      v0 = start(ext[:v_min], ext[:cv], v_size, pitch_v, oy, cen_v)

      rows = ((ext[:v_max] - v0) / pitch_v).floor + 1
      cols = ((ext[:u_max] - u0) / pitch_u).floor + 2
      return nil if rows < 0 || cols < 0 || rows * cols > limit

      shift_step = (stagger.to_f % 1.0) * pitch_u
      out = []
      iv = 0
      vv = v0
      while vv < ext[:v_max] - TOL
        shift = (iv.abs % 2).zero? ? 0.0 : shift_step
        uu = u0 - (shift > EPS ? pitch_u : 0.0) + shift
        iu = 0
        while uu < ext[:u_max] - TOL
          out << { iu: iu, iv: iv, u0: uu, v0: vv,
                   quad: [to_xy(uu, vv, fr),
                          to_xy(uu + u_size, vv, fr),
                          to_xy(uu + u_size, vv + v_size, fr),
                          to_xy(uu, vv + v_size, fr)] }
          uu += pitch_u
          iu += 1
        end
        vv += pitch_v
        iv += 1
      end
      out
    end

    # PURE. What one tile covers on the floor, joint included - the
    # number that turns into square feet. He said it in one line:
    # "סקווארפוט זה כולל האריח והגראוט - היחידה היא בלי הגראוט".
    def self.coverage(u_size, v_size, grout = 0.0)
      g = [grout.to_f, 0.0].max
      [u_size.to_f + g, v_size.to_f + g]
    end

    def self.coverage_sqft(u_size, v_size, grout = 0.0)
      cu, cv = coverage(u_size, v_size, grout)
      cu * cv / 144.0
    end
  end
end

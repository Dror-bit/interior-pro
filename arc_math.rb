# Interior Pro - arc_math.rb
#
# Pure 2D circular-arc math. NO SketchUp API, NO Geom, no model access, no
# state. Every method takes plain numbers / arrays and returns plain numbers /
# arrays, so the whole file runs (and is tested) under plain Ruby.
#
# This is the shared foundation for curved walls. Both entry points the user
# asked for feed the SAME representation:
#   * 3-click arc tool     -> from_three_points(a, m, b)
#   * drag the wall middle -> from_chord_and_sag(a, b, sag)
#
# ARC REPRESENTATION (a plain Hash, so it survives attribute round-trips):
#   { cx:, cy:,   # centre
#     r:,         # radius (> 0)
#     a0:, a1:,   # start / end angle, radians, atan2 convention
#     ccw:,       # true = sweep runs counter-clockwise from a0 to a1
#     sweep: }    # sweep magnitude, radians, in (0, 2*PI)
#
# A DEGENERATE arc (the three points are collinear, or the sag is ~0) is NOT an
# arc: the builders return nil. Callers must treat nil as "this wall is
# straight" and fall back to the existing straight-wall path. That is the
# safety valve - nothing curved is ever forced on a straight wall.
#
# SIGN CONVENTION (used everywhere in this file). "Left" always means: turn
# 90 degrees counter-clockwise, i.e. (x, y) -> (-y, x).
#   * SAG is measured against the CHORD: positive sag = the arc bulges to the
#     left of a -> b. That is what the user's drag produces.
#   * OFFSET is measured against the DIRECTION OF TRAVEL along the arc:
#     positive offset = to the left of where you are walking. That is what a
#     wall's two long sides need, and unlike the chord it never becomes
#     ambiguous (see center_side).
# Callers working with SketchUp normals must map their own normal onto this
# once, at the call site, and stay consistent.

module InteriorPro
  module ArcMath
    # Numeric fuzz for "is this zero". Model units are inches.
    EPS = 1e-9 unless const_defined?(:EPS, false)

    # Below this the three points are treated as a straight line.
    COLLINEAR_TOL = 1e-6 unless const_defined?(:COLLINEAR_TOL, false)

    # Default flat-to-curve tolerance for faceting, in inches. 1/8" of bulge
    # between the chord and the true arc reads as smooth at building scale.
    CHORD_TOL = 0.125 unless const_defined?(:CHORD_TOL, false)

    # Facet count guards. MIN keeps a tiny arc from collapsing to one chord;
    # MAX keeps a huge arc from exploding the SketchUp entity count.
    MIN_SEGMENTS = 2 unless const_defined?(:MIN_SEGMENTS, false)
    MAX_SEGMENTS = 96 unless const_defined?(:MAX_SEGMENTS, false)

    TWO_PI = Math::PI * 2.0 unless const_defined?(:TWO_PI, false)

    # ---------------------------------------------------------------- helpers

    # Wrap an angle into [0, 2*PI).
    def self.norm_angle(t)
      v = t % TWO_PI
      v += TWO_PI if v < 0.0
      v
    end

    def self.dist(ax, ay, bx, by)
      Math.sqrt((bx - ax)**2 + (by - ay)**2)
    end

    # Twice the signed area of triangle a-b-c. Positive = c is LEFT of a->b.
    def self.cross2(ax, ay, bx, by, cx, cy)
      (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    end

    # Are the three points on one line? Compares triangle height (not raw
    # cross product) so the test does not get stricter as the points spread.
    def self.collinear?(ax, ay, mx, my, bx, by, tol = COLLINEAR_TOL)
      base = dist(ax, ay, bx, by)
      return true if base < EPS
      (cross2(ax, ay, bx, by, mx, my).abs / base) < tol
    end

    # --------------------------------------------------------------- builders

    # Circle through three points. Returns [cx, cy, r] or nil when collinear.
    def self.circle_through(ax, ay, mx, my, bx, by)
      return nil if collinear?(ax, ay, mx, my, bx, by)

      d = 2.0 * (ax * (my - by) + mx * (by - ay) + bx * (ay - my))
      return nil if d.abs < EPS

      sa = ax * ax + ay * ay
      sm = mx * mx + my * my
      sb = bx * bx + by * by

      cx = (sa * (my - by) + sm * (by - ay) + sb * (ay - my)) / d
      cy = (sa * (bx - mx) + sm * (ax - bx) + sb * (mx - ax)) / d
      r  = dist(cx, cy, ax, ay)
      return nil if r < EPS

      [cx, cy, r]
    end

    # THE 3-CLICK ARC TOOL. a = first click, b = last click, m = the point the
    # arc must pass through (the middle click). Same meaning as the existing
    # Arc tool in the 2D editor, so the two behave identically.
    # Returns an arc Hash, or nil if the three points are in a line.
    def self.from_three_points(ax, ay, mx, my, bx, by)
      c = circle_through(ax, ay, mx, my, bx, by)
      return nil unless c

      cx, cy, r = c
      a0 = Math.atan2(ay - cy, ax - cx)
      am = Math.atan2(my - cy, mx - cx)
      a1 = Math.atan2(by - cy, bx - cx)

      # Decide the direction by asking which way round passes through m.
      tm = norm_angle(am - a0)
      tb = norm_angle(a1 - a0)
      return nil if tb < EPS || (TWO_PI - tb) < EPS   # a and b coincide

      if tm < tb
        { cx: cx, cy: cy, r: r, a0: a0, a1: a1, ccw: true,  sweep: tb }
      else
        { cx: cx, cy: cy, r: r, a0: a0, a1: a1, ccw: false, sweep: TWO_PI - tb }
      end
    end

    # DRAG THE WALL MIDDLE. a and b stay put; sag is how far the middle of the
    # wall was pulled sideways, signed: positive = towards the LEFT of a->b.
    # Returns nil when the pull is ~0 (the wall is still straight).
    def self.from_chord_and_sag(ax, ay, bx, by, sag)
      chord = dist(ax, ay, bx, by)
      return nil if chord < EPS
      return nil if sag.abs < COLLINEAR_TOL

      ux = (bx - ax) / chord
      uy = (by - ay) / chord
      lx = -uy                       # LEFT normal
      ly = ux

      mx = (ax + bx) / 2.0 + lx * sag
      my = (ay + by) / 2.0 + ly * sag
      from_three_points(ax, ay, mx, my, bx, by)
    end

    # --------------------------------------------------------------- queries

    def self.start_point(arc)
      point_at_angle(arc, arc[:a0])
    end

    def self.end_point(arc)
      point_at_angle(arc, arc[:a1])
    end

    def self.point_at_angle(arc, t)
      [arc[:cx] + arc[:r] * Math.cos(t), arc[:cy] + arc[:r] * Math.sin(t)]
    end

    def self.length(arc)
      arc[:r] * arc[:sweep]
    end

    # t = 0 at the start point, 1 at the end point.
    def self.point_at_param(arc, t)
      dir = arc[:ccw] ? 1.0 : -1.0
      point_at_angle(arc, arc[:a0] + dir * arc[:sweep] * t)
    end

    # d = distance measured ALONG the arc from the start point. This is the
    # hook door/window openings need: they already store t as a distance along
    # the wall, so on a curved wall that distance stays meaningful.
    def self.point_at_distance(arc, d)
      point_at_param(arc, d / length(arc))
    end

    # Unit direction of travel at distance d along the arc.
    def self.tangent_at_distance(arc, d)
      dir = arc[:ccw] ? 1.0 : -1.0
      t = arc[:a0] + dir * (d / arc[:r])
      [-Math.sin(t) * dir, Math.cos(t) * dir]
    end

    # Unit LEFT normal (relative to the travel direction) at distance d.
    def self.normal_at_distance(arc, d)
      tx, ty = tangent_at_distance(arc, d)
      [-ty, tx]
    end

    def self.mid_point(arc)
      point_at_param(arc, 0.5)
    end

    # +1 when the centre lies to the LEFT of the DIRECTION OF TRAVEL, -1 right.
    #
    # Deliberately NOT measured against the start->end chord: on a half-circle
    # the centre sits exactly ON the chord, so that test flips sign on floating
    # point noise and a wall's two sides would swap. Travelling counter-
    # clockwise always keeps the centre on your left - that is exact, and it
    # matches how the straight-wall code already derives its normal from the
    # direction of travel.
    def self.center_side(arc)
      arc[:ccw] ? 1 : -1
    end

    # The signed sag that from_chord_and_sag would need to rebuild this arc.
    # Round-trips: from_chord_and_sag(a, b, sag_of(arc)) == arc.
    def self.sag_of(arc)
      sx, sy = start_point(arc)
      ex, ey = end_point(arc)
      chord = dist(sx, sy, ex, ey)
      return 0.0 if chord < EPS
      mx, my = mid_point(arc)
      cross2(sx, sy, ex, ey, mx, my) / chord
    end

    # --------------------------------------------------------------- faceting

    # How many straight chords are needed so no chord bulges more than tol away
    # from the true arc. Clamped to [MIN_SEGMENTS, MAX_SEGMENTS].
    def self.segment_count(arc, tol = CHORD_TOL)
      r = arc[:r]
      return MAX_SEGMENTS if tol <= 0.0
      return MIN_SEGMENTS if tol >= r
      # sagitta of one chord = r * (1 - cos(half segment angle)) <= tol
      half = Math.acos(1.0 - tol / r)
      return MAX_SEGMENTS if half < EPS
      n = (arc[:sweep] / (2.0 * half)).ceil
      n = MIN_SEGMENTS if n < MIN_SEGMENTS
      n = MAX_SEGMENTS if n > MAX_SEGMENTS
      n
    end

    # n + 1 points along the arc, start and end inclusive.
    def self.sample(arc, n)
      n = MIN_SEGMENTS if n < 1
      (0..n).map { |i| point_at_param(arc, i.to_f / n) }
    end

    # The polyline a wall body will actually be built from.
    def self.chord_points(arc, tol = CHORD_TOL)
      sample(arc, segment_count(arc, tol))
    end

    # ---------------------------------------------------------------- offsets

    # A concentric arc pushed sideways by o, where positive o = towards the
    # LEFT of the direction of travel (see center_side). This is how a wall
    # gets its two long sides: one at +thickness/2 and one at -thickness/2
    # (or 0 / -t, exactly like the straight-wall anchor offsets).
    # Returns nil if the offset would swallow the centre (radius <= 0).
    def self.offset(arc, o)
      return arc if o.abs < EPS
      new_r = arc[:r] - o * center_side(arc)
      return nil if new_r <= EPS
      arc.merge(r: new_r)
    end

    # Offset points in one call - the common case for the wall builder.
    def self.offset_points(arc, o, tol = CHORD_TOL)
      off = offset(arc, o)
      return nil unless off
      # Facet the ORIGINAL arc so both sides of a wall get matching vertex
      # counts and the quads between them stay planar.
      n = segment_count(arc, tol)
      sample(off, n)
    end

    # ------------------------------------------------------------ persistence

    # Flat array for a SketchUp attribute dictionary (they store plain types).
    def self.to_a(arc)
      return nil unless arc
      [arc[:cx], arc[:cy], arc[:r], arc[:a0], arc[:a1], arc[:ccw] ? 1 : 0, arc[:sweep]]
    end

    def self.from_a(flat)
      return nil unless flat.is_a?(Array) && flat.length == 7
      r = flat[2].to_f
      s = flat[6].to_f
      return nil if r <= EPS || s <= EPS
      { cx: flat[0].to_f, cy: flat[1].to_f, r: r,
        a0: flat[3].to_f, a1: flat[4].to_f,
        ccw: flat[5].to_i == 1, sweep: s }
    end
  end
end

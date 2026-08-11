# encoding: utf-8
# rt19 — arc_math.rb: the pure 2D arc foundation for curved walls.
# No SketchUp, no model, no geometry: plain numbers in, plain numbers out.
# If this suite is green the maths is trustworthy BEFORE any wall is touched.
require './arc_math'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end
def close_pt(p, x, y, tol = 1e-6); close(p[0], x, tol) && close(p[1], y, tol); end

AM = InteriorPro::ArcMath
PI = Math::PI

# ---------------------------------------------------------------- degenerate

ok('collinear? true on a straight run',  AM.collinear?(0, 0, 50, 0, 100, 0))
ok('collinear? false on a real bulge',  !AM.collinear?(0, 0, 50, 10, 100, 0))
ok('collinear? true when a == b',        AM.collinear?(0, 0, 50, 0, 0, 0))
ok('a long straight wall is still collinear (no scale drift)',
   AM.collinear?(0, 0, 6000, 0, 12000, 0))

ok('from_three_points -> nil when collinear',
   AM.from_three_points(0, 0, 50, 0, 100, 0).nil?)
ok('from_chord_and_sag -> nil when sag is 0',
   AM.from_chord_and_sag(0, 0, 100, 0, 0.0).nil?)
ok('from_chord_and_sag -> nil when a == b',
   AM.from_chord_and_sag(0, 0, 0, 0, 10.0).nil?)
ok('circle_through -> nil when collinear',
   AM.circle_through(0, 0, 50, 0, 100, 0).nil?)

# ------------------------------------------------------- known semicircle

# a=(0,0)  m=(50,50)  b=(100,0)  -> centre (50,0), r=50, half turn.
arc = AM.from_three_points(0, 0, 50, 50, 100, 0)
ok('semicircle: arc is built', !arc.nil?)
ok('semicircle: centre',  close(arc[:cx], 50.0) && close(arc[:cy], 0.0), [arc[:cx], arc[:cy]])
ok('semicircle: radius',  close(arc[:r], 50.0), arc[:r])
ok('semicircle: sweep is PI', close(arc[:sweep], PI), arc[:sweep])
ok('semicircle: start point is a', close_pt(AM.start_point(arc), 0.0, 0.0), AM.start_point(arc))
ok('semicircle: end point is b',   close_pt(AM.end_point(arc), 100.0, 0.0), AM.end_point(arc))
ok('semicircle: midpoint is the click', close_pt(AM.mid_point(arc), 50.0, 50.0), AM.mid_point(arc))
ok('semicircle: length is PI*r', close(AM.length(arc), PI * 50.0), AM.length(arc))

# ------------------------------------------------------ direction of travel

up   = AM.from_three_points(0, 0, 50,  50, 100, 0)   # bulges up   -> left of a->b
down = AM.from_three_points(0, 0, 50, -50, 100, 0)   # bulges down -> right
ok('bulge up and bulge down run opposite ways', up[:ccw] != down[:ccw], [up[:ccw], down[:ccw]])
ok('bulge up: sag is positive (left)',  AM.sag_of(up)   > 0, AM.sag_of(up))
ok('bulge down: sag is negative (right)', AM.sag_of(down) < 0, AM.sag_of(down))
ok('sag magnitude equals the pull', close(AM.sag_of(up).abs, 50.0), AM.sag_of(up))

# Reversing the click order must give the same shape, walked backwards.
rev = AM.from_three_points(100, 0, 50, 50, 0, 0)
ok('reversed clicks: same centre',  close(rev[:cx], up[:cx]) && close(rev[:cy], up[:cy]))
ok('reversed clicks: same radius',  close(rev[:r], up[:r]))
ok('reversed clicks: same sweep',   close(rev[:sweep], up[:sweep]))
ok('reversed clicks: opposite direction', rev[:ccw] != up[:ccw])

# --------------------------------------------------- drag-the-middle round trip

[[0, 0, 100, 0, 12.5], [0, 0, 100, 0, -12.5], [10, 20, -60, 90, 7.0],
 [0, 0, 240, 0, 3.0], [0, 0, 240, 0, 119.0]].each do |ax, ay, bx, by, sag|
  a = AM.from_chord_and_sag(ax, ay, bx, by, sag)
  ok("sag #{sag} on (#{ax},#{ay})->(#{bx},#{by}): arc built", !a.nil?)
  next unless a
  ok("sag #{sag}: endpoints preserved",
     close_pt(AM.start_point(a), ax.to_f, ay.to_f, 1e-6) &&
     close_pt(AM.end_point(a), bx.to_f, by.to_f, 1e-6),
     [AM.start_point(a), AM.end_point(a)])
  ok("sag #{sag}: sag_of round-trips", close(AM.sag_of(a), sag.to_f, 1e-6), AM.sag_of(a))
end

# A sag of exactly half the chord is the semicircle - the widest a wall can go.
half = AM.from_chord_and_sag(0, 0, 100, 0, 50.0)
ok('sag = half chord gives a semicircle', close(half[:sweep], PI), half[:sweep])
# Past half the chord it is a MAJOR arc (more than half a circle), still valid.
major = AM.from_chord_and_sag(0, 0, 100, 0, 80.0)
ok('sag > half chord gives a major arc', major[:sweep] > PI, major[:sweep])
ok('major arc still ends on b', close_pt(AM.end_point(major), 100.0, 0.0), AM.end_point(major))

# The 3-click tool and the drag tool must agree on the same shape.
three = AM.from_three_points(0, 0, 50, 30, 100, 0)
drag  = AM.from_chord_and_sag(0, 0, 100, 0, 30.0)
ok('3-click and drag agree: centre', close(three[:cx], drag[:cx]) && close(three[:cy], drag[:cy]))
ok('3-click and drag agree: radius', close(three[:r], drag[:r]))
ok('3-click and drag agree: direction', three[:ccw] == drag[:ccw])

# ---------------------------------------------------- distance along the arc

# Openings store t as a distance along the wall, so this has to be exact.
ok('distance 0 lands on the start point',
   close_pt(AM.point_at_distance(arc, 0.0), 0.0, 0.0), AM.point_at_distance(arc, 0.0))
ok('full length lands on the end point',
   close_pt(AM.point_at_distance(arc, AM.length(arc)), 100.0, 0.0),
   AM.point_at_distance(arc, AM.length(arc)))
ok('half length lands on the midpoint',
   close_pt(AM.point_at_distance(arc, AM.length(arc) / 2.0), 50.0, 50.0),
   AM.point_at_distance(arc, AM.length(arc) / 2.0))

# Walking the arc in equal steps must cover equal arc distance.
steps = (0..10).map { |i| AM.point_at_distance(arc, AM.length(arc) * i / 10.0) }
gaps  = steps.each_cons(2).map { |p, q| AM.dist(p[0], p[1], q[0], q[1]) }
ok('equal distance steps give equal chords', gaps.max - gaps.min < 1e-6, [gaps.min, gaps.max])

# Tangent and normal are unit, perpendicular, and point the right way.
[0.0, 10.0, AM.length(arc) / 2.0, AM.length(arc)].each do |d|
  t = AM.tangent_at_distance(arc, d)
  n = AM.normal_at_distance(arc, d)
  ok("tangent at #{d.round(2)} is unit", close(Math.sqrt(t[0]**2 + t[1]**2), 1.0), t)
  ok("normal at #{d.round(2)} is unit",  close(Math.sqrt(n[0]**2 + n[1]**2), 1.0), n)
  ok("normal at #{d.round(2)} is perpendicular", close(t[0] * n[0] + t[1] * n[1], 0.0))
end
# The tangent must match the direction you actually move when you step a hair
# further along the arc. (On a half-circle that is straight UP at the start,
# NOT towards b - so compare against real motion, not against the chord.)
[0.0, 30.0, AM.length(arc) - 1.0].each do |d|
  h = 1e-6
  p0 = AM.point_at_distance(arc, d)
  p1 = AM.point_at_distance(arc, d + h)
  mx = (p1[0] - p0[0]) / h
  my = (p1[1] - p0[1]) / h
  t = AM.tangent_at_distance(arc, d)
  ok("tangent at #{d.round(2)} matches real motion along the arc",
     close(t[0], mx, 1e-5) && close(t[1], my, 1e-5), [t, [mx, my]])
end

# ------------------------------------------------------------------ faceting

# Every sampled point must actually sit on the circle.
pts = AM.chord_points(arc)
ok('chord points start at a', close_pt(pts.first, 0.0, 0.0), pts.first)
ok('chord points end at b',   close_pt(pts.last, 100.0, 0.0), pts.last)
ok('every chord point is on the circle',
   pts.all? { |p| close(AM.dist(p[0], p[1], arc[:cx], arc[:cy]), arc[:r], 1e-6) })

# The real promise: no chord bulges further than the tolerance.
def max_sagitta(arc, pts)
  pts.each_cons(2).map do |p, q|
    mx = (p[0] + q[0]) / 2.0
    my = (p[1] + q[1]) / 2.0
    arc[:r] - InteriorPro::ArcMath.dist(mx, my, arc[:cx], arc[:cy])
  end.max
end
ok('faceting honours the 1/8" tolerance', max_sagitta(arc, pts) <= AM::CHORD_TOL + 1e-9,
   max_sagitta(arc, pts))
tight = AM.chord_points(arc, 0.01)
ok('a tighter tolerance honours 0.01"', max_sagitta(arc, tight) <= 0.01 + 1e-9, max_sagitta(arc, tight))
ok('a tighter tolerance uses more segments', tight.length > pts.length, [pts.length, tight.length])

ok('segment count is clamped at the top', AM.segment_count(arc, 1e-9) <= AM::MAX_SEGMENTS)
ok('segment count is clamped at the bottom', AM.segment_count(arc, 1e6) >= AM::MIN_SEGMENTS)
big = AM.from_chord_and_sag(0, 0, 1200, 0, 0.5)   # nearly flat, huge radius
ok('a nearly flat arc still gives at least 2 segments',
   AM.segment_count(big) >= AM::MIN_SEGMENTS, AM.segment_count(big))
ok('sample(n) returns n + 1 points', AM.sample(arc, 7).length == 8)

# --------------------------------------------------------------- wall offsets

# This is what builds the two long sides of a curved wall.
inner = AM.offset(arc,  2.5)
outer = AM.offset(arc, -2.5)
ok('offset left shrinks or grows by exactly 2.5', close((inner[:r] - arc[:r]).abs, 2.5), inner[:r])
ok('the two offsets sit 5 apart', close((inner[:r] - outer[:r]).abs, 5.0), [inner[:r], outer[:r]])
ok('offsets keep the same centre', close(inner[:cx], arc[:cx]) && close(inner[:cy], arc[:cy]))
ok('offset 0 is a no-op', AM.offset(arc, 0.0)[:r] == arc[:r])

# Every point of the offset side is exactly 2.5 from the matching centre line.
ip = AM.offset_points(arc, 2.5)
op = AM.offset_points(arc, -2.5)
ok('both wall sides get the SAME number of points', ip.length == op.length, [ip.length, op.length])
ok('matching side points are exactly the wall thickness apart',
   ip.zip(op).all? { |p, q| close(AM.dist(p[0], p[1], q[0], q[1]), 5.0, 1e-6) })

# A tight curve cannot be offset past its own centre - that must fail loudly.
tightarc = AM.from_chord_and_sag(0, 0, 20, 0, 10.0)     # r = 10, a half circle
inward = AM.center_side(tightarc)   # offsetting this way walks into the centre
ok('offsetting exactly onto the centre returns nil',
   AM.offset(tightarc, inward * 10.0).nil?, AM.offset(tightarc, inward * 10.0))
ok('offsetting past the centre returns nil',
   AM.offset(tightarc, inward * 12.0).nil?, AM.offset(tightarc, inward * 12.0))
ok('offset_points also returns nil there', AM.offset_points(tightarc, inward * 12.0).nil?)
ok('a safe offset on the same tight curve still works', !AM.offset(tightarc, inward * 4.0).nil?)
ok('offsetting the other way always works', !AM.offset(tightarc, -inward * 12.0).nil?)

# center_side must not flip on floating point noise. A half circle is the
# nasty case: its centre sits exactly on the chord.
ok('half circle: centre side is stable', [1, -1].include?(AM.center_side(tightarc)))
ok('half circle: the two sides land on opposite sides of the centre line',
   close(AM.offset(tightarc, 2.0)[:r] + AM.offset(tightarc, -2.0)[:r], 2 * tightarc[:r]),
   [AM.offset(tightarc, 2.0)[:r], AM.offset(tightarc, -2.0)[:r]])
# Nudging a half circle a hair either way must not swap the wall's two sides.
n1 = AM.from_chord_and_sag(0, 0, 20, 0, 9.999)
n2 = AM.from_chord_and_sag(0, 0, 20, 0, 10.001)
ok('a near half circle does not flip sides', AM.center_side(n1) == AM.center_side(n2),
   [AM.center_side(n1), AM.center_side(tightarc), AM.center_side(n2)])

# --------------------------------------------------------------- persistence

flat = AM.to_a(arc)
ok('to_a gives a flat 7-array of plain numbers',
   flat.is_a?(Array) && flat.length == 7 && flat.all? { |v| v.is_a?(Numeric) }, flat)
back = AM.from_a(flat)
ok('from_a round-trips the centre', close(back[:cx], arc[:cx]) && close(back[:cy], arc[:cy]))
ok('from_a round-trips the radius', close(back[:r], arc[:r]))
ok('from_a round-trips the direction', back[:ccw] == arc[:ccw])
ok('from_a round-trips the sweep', close(back[:sweep], arc[:sweep]))
ok('round-tripped arc draws the same midpoint',
   close_pt(AM.mid_point(back), *AM.mid_point(arc)))
ok('to_a(nil) is nil', AM.to_a(nil).nil?)
ok('from_a(nil) is nil', AM.from_a(nil).nil?)
ok('from_a of junk is nil', AM.from_a([1, 2, 3]).nil?)
ok('from_a of a zero radius is nil', AM.from_a([0, 0, 0, 0, 0, 1, 1]).nil?)

# ------------------------------------------------------- real-world sanity

# A 20 ft wall bowed 6 inches - a realistic gentle curve.
wall = AM.from_chord_and_sag(0, 0, 240, 0, 6.0)
ok('20ft wall bowed 6in: radius is ~1203in', close(wall[:r], (120.0**2 + 6.0**2) / 12.0, 1e-6), wall[:r])
ok('20ft wall bowed 6in: arc is a touch longer than the chord',
   AM.length(wall) > 240.0 && AM.length(wall) < 241.0, AM.length(wall))
ok('20ft wall bowed 6in: 5in thick sides never collapse',
   !AM.offset(wall, 2.5).nil? && !AM.offset(wall, -2.5).nil?)
ok('20ft wall bowed 6in: facets stay reasonable',
   AM.segment_count(wall).between?(AM::MIN_SEGMENTS, 24), AM.segment_count(wall))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

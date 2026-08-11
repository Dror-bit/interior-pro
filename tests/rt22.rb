# encoding: utf-8
# rt22 — CORNERS on a curved wall (wall_tool.rb, 2026-08-11).
#
# The user's report: a curved wall did not meet the walls it grew out of -
# they kept square corners and the curve arrived as if it were a straight
# line, leaving a step. The cause: the corner code asked the wall which way
# it runs, and a curved wall answered with the straight line between its
# ends instead of its real direction there (the tangent).
#
# This suite pins the direction a wall reports at each end, and the radial
# end cut that follows from it.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end
def unit?(v, tol = 1e-9); (Math.sqrt(v[0]**2 + v[1]**2) - 1.0).abs < tol; end
def deg(v1, v2)
  c = ((v1[0] * v2[0] + v1[1] * v2[1]) / (Math.sqrt(v1[0]**2 + v1[1]**2) * Math.sqrt(v2[0]**2 + v2[1]**2))).clamp(-1.0, 1.0)
  Math.acos(c) * 180.0 / Math::PI
end

WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

# ------------------------------------------- a straight wall never changes

# THE regression guard. If this ever fails, straight walls have been broken.
[[0, 0, 100, 0], [0, 0, 0, 100], [10, 5, -70, 90], [-3, -4, -3, -400]].each do |sx, sy, ex, ey|
  chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
  want = [(ex - sx) / chord, (ey - sy) / chord]
  %i[start end].each do |side|
    got = WT.corner_direction_xy(sx, sy, ex, ey, 0.0, side)
    ok("straight wall (#{sx},#{sy})->(#{ex},#{ey}) #{side}: direction is unchanged",
       close(got[0], want[0], 1e-12) && close(got[1], want[1], 1e-12), [got, want])
  end
  ok("straight wall: nil sag behaves like zero",
     WT.corner_direction_xy(sx, sy, ex, ey, nil, :start) == want)
  ok("straight wall: a hair of sag still behaves like zero",
     WT.corner_direction_xy(sx, sy, ex, ey, WT::MIN_ARC_SAG / 2, :end) == want)
end
ok('a zero-length wall reports nil, not a crash',
   WT.corner_direction_xy(5, 5, 5, 5, 9.0, :start).nil?)

# ---------------------------------------- a curved wall leans at its ends

sag = 20.0
sx, sy, ex, ey = 0.0, 0.0, 120.0, 0.0
d0 = WT.corner_direction_xy(sx, sy, ex, ey, sag, :start)
d1 = WT.corner_direction_xy(sx, sy, ex, ey, sag, :end)
straight = [1.0, 0.0]

ok('curved wall: the start direction is a unit vector', unit?(d0), d0)
ok('curved wall: the end direction is a unit vector',  unit?(d1), d1)
ok('curved wall: the start direction is NOT the straight line',
   deg(d0, straight) > 1.0, deg(d0, straight))
ok('curved wall: it leans out at the start and back in at the end',
   d0[1] > 0 && d1[1] < 0, [d0, d1])
ok('curved wall: the two ends lean by the same amount, opposite ways',
   close(deg(d0, straight), deg(d1, straight), 1e-9), [deg(d0, straight), deg(d1, straight)])

# The lean must be exactly half the arc's total turn - that is what makes the
# miter land right.
arc = AM.from_chord_and_sag(sx, sy, ex, ey, sag)
ok('curved wall: each end leans by half the total bend',
   close(deg(d0, straight), (arc[:sweep] * 180.0 / Math::PI) / 2.0, 1e-6),
   [deg(d0, straight), (arc[:sweep] * 180.0 / Math::PI) / 2.0])
ok('curved wall: the total turn between the two ends is the whole bend',
   close(deg(d0, d1), arc[:sweep] * 180.0 / Math::PI, 1e-6), deg(d0, d1))

# Bow the other way and the lean mirrors.
m0 = WT.corner_direction_xy(sx, sy, ex, ey, -sag, :start)
ok('bowing the other way mirrors the start lean',
   close(m0[0], d0[0], 1e-12) && close(m0[1], -d0[1], 1e-12), [d0, m0])

# The direction really is the tangent of the arc that gets built.
%i[start end].each do |side|
  d = side == :start ? 0.0 : AM.length(arc)
  t = AM.tangent_at_distance(arc, d)
  got = WT.corner_direction_xy(sx, sy, ex, ey, sag, side)
  ok("#{side}: the reported direction IS the arc's tangent there",
     close(got[0], t[0], 1e-9) && close(got[1], t[1], 1e-9), [got, t])
end

# A gentler bow leans less; a wall that is nearly straight barely leans at all.
gentle = WT.corner_direction_xy(0, 0, 240, 0, 2.0, :start)
strong = WT.corner_direction_xy(0, 0, 240, 0, 60.0, :start)
ok('a gentle bow leans less than a strong one',
   deg(gentle, straight) < deg(strong, straight), [deg(gentle, straight), deg(strong, straight)])
# A 20ft wall bowed only 2" turns about 3.8 degrees end to end, so each end
# leans about 1.9 - small, but NOT nothing. Cutting that corner square to the
# straight line is exactly the step the user saw.
ok('a barely-bowed wall still leans a couple of degrees',
   deg(gentle, straight).between?(1.5, 2.5), deg(gentle, straight))

# It works off-axis too.
ax, ay, bx, by = 10.0, 5.0, -70.0, 90.0
achord = [(bx - ax), (by - ay)]
a0 = WT.corner_direction_xy(ax, ay, bx, by, 15.0, :start)
a1 = WT.corner_direction_xy(ax, ay, bx, by, 15.0, :end)
aarc = AM.from_chord_and_sag(ax, ay, bx, by, 15.0)
ok('diagonal wall: both end directions are unit', unit?(a0) && unit?(a1), [a0, a1])
ok('diagonal wall: each end leans by half the bend',
   close(deg(a0, achord), (aarc[:sweep] * 180.0 / Math::PI) / 2.0, 1e-6),
   [deg(a0, achord), (aarc[:sweep] * 180.0 / Math::PI) / 2.0])

# --------------------------------------------- the end cut is square to it

# A curved wall's ends are cut RADIALLY - square to the wall's own direction
# there. That is what lets the neighbour's miter meet it cleanly.
cor = WT.curved_end_corners_xy(sx, sy, ex, ey, 6.0, 'center', sag)
ok('curved end corners come back as four points', cor.is_a?(Array) && cor.length == 4, cor&.length)
s_pos, e_pos, e_neg, s_neg = cor

start_cut = [s_pos[0] - s_neg[0], s_pos[1] - s_neg[1]]
end_cut   = [e_pos[0] - e_neg[0], e_pos[1] - e_neg[1]]
ok('the start cut is square to the wall direction there',
   close(deg(start_cut, d0), 90.0, 1e-6), deg(start_cut, d0))
ok('the end cut is square to the wall direction there',
   close(deg(end_cut, d1), 90.0, 1e-6), deg(end_cut, d1))
ok('the start cut is NOT square to the straight line (that was the bug)',
   (deg(start_cut, straight) - 90.0).abs > 1.0, deg(start_cut, straight))
ok('both end cuts are exactly one wall thickness wide',
   close(Math.sqrt(start_cut[0]**2 + start_cut[1]**2), 6.0, 1e-6) &&
   close(Math.sqrt(end_cut[0]**2 + end_cut[1]**2), 6.0, 1e-6),
   [Math.sqrt(start_cut[0]**2 + start_cut[1]**2), Math.sqrt(end_cut[0]**2 + end_cut[1]**2)])
ok('the start cut is centred exactly on the drawn start point',
   close((s_pos[0] + s_neg[0]) / 2.0, sx, 1e-9) && close((s_pos[1] + s_neg[1]) / 2.0, sy, 1e-9),
   [(s_pos[0] + s_neg[0]) / 2.0, (s_pos[1] + s_neg[1]) / 2.0])
ok('the end cut is centred exactly on the drawn end point',
   close((e_pos[0] + e_neg[0]) / 2.0, ex, 1e-9) && close((e_pos[1] + e_neg[1]) / 2.0, ey, 1e-9),
   [(e_pos[0] + e_neg[0]) / 2.0, (e_pos[1] + e_neg[1]) / 2.0])

# The corner order must match the straight builder's, or a miter would be
# written into the wrong two slots and the wall would tear.
inst = WT.new
st = Struct.new(:x, :y)
plain = inst.perpendicular_corners_xy(st.new(sx, sy), st.new(ex, ey), 6.0, 'center')
ok('corner ORDER matches the straight builder (s_pos, e_pos, e_neg, s_neg)',
   (cor[0][1] > 0) == (plain[0][1] > 0) && (cor[3][1] < 0) == (plain[3][1] < 0),
   [cor, plain])

ok('an impossible curve gives nil end corners, not junk',
   WT.curved_end_corners_xy(0, 0, 20, 0, 30.0, 'center', 10.0).nil?)
ok('a straight wall gives nil end corners (it uses the straight builder)',
   WT.curved_end_corners_xy(0, 0, 120, 0, 6.0, 'center', 0.0).nil?)

# -------------------------------------------------- centreline offset rule

ok('centre anchor: the centreline sits on the drawn line',
   close(WT.centerline_offset('center', 6.0), 0.0))
ok('left anchor: the centreline sits half a thickness to the left',
   close(WT.centerline_offset('left', 6.0), 3.0))
ok('right anchor: the centreline sits half a thickness to the right',
   close(WT.centerline_offset('right', 6.0), -3.0))
ok('an unknown anchor falls back to centred', close(WT.centerline_offset('wat', 6.0), 0.0))

# ------------------------------------------ the miter really is written in

# apply_corner_overrides takes the built curve and swaps in whatever the four
# stored corners say - that is how a miter reaches a curved wall. The curve
# itself in between must survive untouched.
fp = WT.curved_footprint_xy(sx, sy, ex, ey, 6.0, 'center', sag)
n = fp.length / 2
fake = Object.new
def fake.get_attribute(_d, _k); [-1.0, -2.0, -3.0, -4.0, -5.0, -6.0, -7.0, -8.0]; end
out = WT.apply_corner_overrides(fp, fake)
ok('the four ends are replaced by the stored corners',
   out[0] == [-1.0, -2.0] && out[n - 1] == [-3.0, -4.0] &&
   out[n] == [-5.0, -6.0] && out[(2 * n) - 1] == [-7.0, -8.0],
   [out[0], out[n - 1], out[n], out[(2 * n) - 1]])
ok('the curve in between is left exactly as it was',
   (1..(n - 2)).all? { |i| out[i] == fp[i] } &&
   ((n + 1)..((2 * n) - 2)).all? { |i| out[i] == fp[i] })
ok('the point count does not change', out.length == fp.length, [fp.length, out.length])

junk = Object.new
def junk.get_attribute(_d, _k); nil; end
ok('no stored corners -> the curve is used as-is', WT.apply_corner_overrides(fp, junk) == fp)
bad = Object.new
def bad.get_attribute(_d, _k); [1, 2, 3]; end
ok('a broken corners list -> the curve is used as-is', WT.apply_corner_overrides(fp, bad) == fp)

# ------------------------------------ a corner that is not really a corner

# The user's arch: a wall bowed into nearly a half circle springs off a
# straight wall. At the spring point the curve is running the SAME way as the
# straight wall, so there is no corner - and cutting one sent the end racing
# off into a long spike. That case must be recognised and squared off.
def dir(deg_angle)
  r = deg_angle * Math::PI / 180.0
  [Math.cos(r), Math.sin(r)]
end

ok('dead straight run: no corner to cut', WT.corner_too_straight?(dir(0), dir(0)))
ok('half a degree of turn: still no corner', WT.corner_too_straight?(dir(0), dir(0.5)))
ok('half a degree the other way: still no corner', WT.corner_too_straight?(dir(0), dir(-0.5)))
ok('two degrees: still no corner', WT.corner_too_straight?(dir(0), dir(2.0)))
ok('a hairpin doubling back: no sane corner either', WT.corner_too_straight?(dir(0), dir(179.5)))
ok('five degrees IS a corner', !WT.corner_too_straight?(dir(0), dir(5.0)))
ok('a square corner IS a corner', !WT.corner_too_straight?(dir(0), dir(90.0)))
ok('a square corner the other way IS a corner', !WT.corner_too_straight?(dir(0), dir(-90.0)))
ok('a 45 degree corner IS a corner', !WT.corner_too_straight?(dir(0), dir(45.0)))
ok('it does not care which way the pair is rotated',
   WT.corner_too_straight?(dir(137), dir(137.4)) && !WT.corner_too_straight?(dir(137), dir(190)))
ok('the threshold is a small but real angle',
   WT::COLLINEAR_CORNER_DEG > 0.5 && WT::COLLINEAR_CORNER_DEG < 15.0, WT::COLLINEAR_CORNER_DEG)

# THE user's arch, with real numbers: a 120" opening bowed into a half circle.
# At its spring point the curve runs straight down - exactly the way the wall
# below it runs - so the corner must be recognised as no corner at all.
half = 60.0                       # sag = half the chord => half circle
arch_start_dir = WT.corner_direction_xy(0, 0, 120, 0, half, :start)
ok("the arch springs at 90 degrees to its own chord",
   close(deg(arch_start_dir, [1.0, 0.0]), 90.0, 1e-6), deg(arch_start_dir, [1.0, 0.0]))
# The wall it springs from runs straight down into the corner; the arch
# leaves the corner going straight up. Same line -> no corner.
leg_into_corner = [0.0, 1.0]      # the straight leg arriving, pointing up
ok('the arch meeting its straight leg is NOT a corner to cut',
   WT.corner_too_straight?(leg_into_corner, arch_start_dir),
   [leg_into_corner, arch_start_dir])

# A gently bowed wall meeting a wall at right angles IS still a real corner
# and must keep its miter.
gentle_dir = WT.corner_direction_xy(0, 0, 240, 0, 6.0, :start)
ok('a gently bowed wall still miters into a wall at right angles',
   !WT.corner_too_straight?([0.0, 1.0], gentle_dir), gentle_dir)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

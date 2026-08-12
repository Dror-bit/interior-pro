# encoding: utf-8
# rt30 — the miter reach cap on corners with a curve in them (2026-08-12).
#
# The user's model: an arc replacing one wall of a room. At each end the
# arc's tangent runs almost PARALLEL to the straight wall it meets, so the
# face lines crossed 22" and 64" away from the 5"-thick wall ends. The wall
# looked torn in the 2D editor, and the same stored corners_xy broke the 3D
# build. Past a sane reach the corner must give up on the miter and square
# both ends off - the curve then simply flows past the wall end.
#
# Straight-to-straight corners never come through this check (it sits behind
# curved_corner in apply_miter); rt22 pins that guard's surroundings.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

WT = InteriorPro::WallTool

# ------------------------------------------------------------ the constant

ok('the reach cap factor exists', WT.const_defined?(:CURVE_MITER_REACH))
ok('and is a sane multiple of the combined thickness',
   WT::CURVE_MITER_REACH >= 1.0 && WT::CURVE_MITER_REACH <= 3.0, WT::CURVE_MITER_REACH)

# --------------------------------------- the exact numbers from the model

# Two 5" walls -> cap = (5+5) * 1.5 = 15".
E = [0.0, 0.0].freeze
def pts_at(d); [[d, 0.0], [0.0, 0.0]]; end

ok('a right-angle miter (reach 7.07") keeps its miter',
   !WT.curve_miter_too_far?(pts_at(7.07), E, E, 5.0, 5.0))
ok('a 45-degree miter (reach ~12") keeps its miter',
   !WT.curve_miter_too_far?(pts_at(12.0), E, E, 5.0, 5.0))
ok("the user's 22.61\" spike is refused",
   WT.curve_miter_too_far?(pts_at(22.61), E, E, 5.0, 5.0))
ok("the user's 64.46\" spike is refused",
   WT.curve_miter_too_far?(pts_at(64.46), E, E, 5.0, 5.0))
ok('exactly on the cap still passes (not torn)',
   !WT.curve_miter_too_far?(pts_at(15.0), E, E, 5.0, 5.0))
ok('a hair past the cap is refused',
   WT.curve_miter_too_far?(pts_at(15.01), E, E, 5.0, 5.0))

# One far point out of the four combinations is enough to refuse.
ok('one bad point among the candidates is enough',
   WT.curve_miter_too_far?([[3.0, 0.0], [40.0, 0.0]], E, E, 5.0, 5.0))
ok('measured against EITHER wall end',
   WT.curve_miter_too_far?([[3.0, 0.0]], E, [-40.0, 0.0], 5.0, 5.0))

# Thicker walls may reach further before it reads as a tear.
ok('thicker walls get a proportionally longer leash',
   !WT.curve_miter_too_far?(pts_at(22.61), E, E, 8.0, 8.0))

# Nonsense thickness can never sneak a spike through.
ok('zero thickness refuses everything', WT.curve_miter_too_far?(pts_at(0.1), E, E, 0.0, 0.0))

# ------------------------------ the real geometry produces those reaches

# Rebuild the user's top corner purely: wall A runs into the corner along
# (1, 0); the arc leaves along its end tangent. Both 5" thick, faces offset
# 2.5" each side of the centreline. Where the two outside faces cross is the
# miter point apply_miter would use.
def face_cross(u1, u2, off1, off2)
  n1 = [-u1[1], u1[0]]
  n2 = [-u2[1], u2[0]]
  p1 = [n1[0] * off1, n1[1] * off1]
  p2 = [n2[0] * off2, n2[1] * off2]
  det = (u1[0] * -u2[1]) - (u1[1] * -u2[0])
  return nil if det.abs < 1e-12
  rx = p2[0] - p1[0]
  ry = p2[1] - p1[1]
  t1 = ((rx * -u2[1]) - (ry * -u2[0])) / det
  [p1[0] + u1[0] * t1, p1[1] + u1[1] * t1]
end

# wall7 from the trace: 191" tall chord, sag -60 -> end tangent ~25 degrees
# off the neighbour's line. Even measured from the CENTRELINE corner the
# miter lands over two thicknesses out; from the drawn ends (what the code
# measures, and what the trace showed) it was 22.61" - refused above.
tan7 = WT.corner_direction_xy(3099.5, 843.0, 3099.5, 1034.0, -60.0, :end)
u_a  = [1.0, 0.0]
m = face_cross(u_a, tan7, 2.5, 2.5)
reach = Math.sqrt(m[0]**2 + m[1]**2)
ok('the 60"-sag arc really miters over two thicknesses away (the thin spike)',
   reach > 10.0 && reach < 40.0, reach)

# wall3 from the trace: 292.5" chord, sag -125 -> tangent ~8.6 degrees.
tan3 = WT.corner_direction_xy(3273.5, 1228.5, 3273.5, 1521.0, -125.12, :start)
m3 = face_cross([-1.0, 0.0], tan3, 2.5, 2.5)
reach3 = Math.sqrt(m3[0]**2 + m3[1]**2)
ok('the near-parallel arc miters even further away', reach3 > 25.0, reach3)
ok('and the cap refuses it too', WT.curve_miter_too_far?([m3], E, E, 5.0, 5.0), reach3)

# A curve meeting a wall at a REAL right angle keeps its miter: gentle bow,
# square corner - the everyday case must not lose its point.
gentle = WT.corner_direction_xy(0.0, 0.0, 240.0, 0.0, 6.0, :start)
mg = face_cross([0.0, 1.0], gentle, 2.5, 2.5)
reachg = Math.sqrt(mg[0]**2 + mg[1]**2)
ok('a gently bowed wall meeting a square corner keeps its miter',
   !WT.curve_miter_too_far?([mg], E, E, 5.0, 5.0), reachg)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt25 — putting a DOOR on a curved wall (2026-08-11).
#
# The hole was already being cut in the right place, but the door itself was
# landing in the middle of the room. Every piece of door code works out where
# a door goes with one line:
#
#     cline_start + unit * t + n * n_side
#
# which quietly assumes the wall is a straight ruler. On a curve it is not.
# Two things fix that, and both are pinned here:
#   * a click has to be measured ALONG the curve, not along the straight line
#   * the ruler gets swung round to the flat panel the door sits in, so that
#     the very same line, with the very same t, lands in the right place
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'
require './door_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
DM = InteriorPro::DoorManager
AM = InteriorPro::ArcMath

SX = 0.0; SY = 0.0; EX = 240.0; EY = 0.0
SAG = 30.0
ARC = AM.from_chord_and_sag(SX, SY, EX, EY, SAG)
LEN = AM.length(ARC)

# ------------------------------- a click turns into a distance along the wall

# Straight wall: unchanged, plain projection.
[[0.0, 0.0], [60.0, 0.0], [240.0, 0.0], [120.0, 55.0]].each do |px, py|
  ok("straight wall: a click at (#{px},#{py}) reads as #{px}\"",
     close(WT.t_from_point_xy(0, 0, 240, 0, 0.0, px, py), px, 1e-9),
     WT.t_from_point_xy(0, 0, 240, 0, 0.0, px, py))
end
ok('straight wall: nil sag behaves the same',
   close(WT.t_from_point_xy(0, 0, 240, 0, nil, 60, 10), 60.0, 1e-9))
ok('a zero-length wall reports nothing', WT.t_from_point_xy(7, 7, 7, 7, 5.0, 1, 1).nil?)

# Curved wall: a point ON the curve reads back as exactly where it came from.
[0.0, 1.0, LEN * 0.25, LEN * 0.5, LEN * 0.75, LEN - 1.0, LEN].each do |d|
  p = AM.point_at_distance(ARC, d)
  got = WT.t_from_point_xy(SX, SY, EX, EY, SAG, p[0], p[1])
  ok("curved wall: a click #{d.round(1)}\" along reads back as #{d.round(1)}\"",
     close(got, d, 1e-6), [got, d])
end

# It must measure ALONG the curve - which is more than the straight distance.
mid = AM.point_at_distance(ARC, LEN / 2.0)
ok('the middle of the curve is half the CURVE, not half the straight line',
   close(WT.t_from_point_xy(SX, SY, EX, EY, SAG, mid[0], mid[1]), LEN / 2.0, 1e-6))
ok('and that is more than half the straight line', LEN / 2.0 > 120.0, LEN / 2.0)

# Clicking off the wall still reads sensibly: a point out along the radius
# reads as the same place, because it is the ANGLE that matters.
[0.3, 0.6].each do |f|
  d = LEN * f
  p = AM.offset_point_at_distance(ARC, d, 4.0)     # 4" off to one side
  q = AM.offset_point_at_distance(ARC, d, -4.0)    # 4" off to the other
  ok("a click #{f} along but off the face still reads #{d.round(1)}\"",
     close(WT.t_from_point_xy(SX, SY, EX, EY, SAG, p[0], p[1]), d, 1e-6) &&
     close(WT.t_from_point_xy(SX, SY, EX, EY, SAG, q[0], q[1]), d, 1e-6))
end

# Clicking past an end gets pulled back to that end, never wrapped round.
past_end = AM.point_at_angle(ARC, ARC[:a1] + (ARC[:ccw] ? 0.05 : -0.05))
past_start = AM.point_at_angle(ARC, ARC[:a0] - (ARC[:ccw] ? 0.05 : -0.05))
ok('a click past the far end is pulled back to the far end',
   close(WT.t_from_point_xy(SX, SY, EX, EY, SAG, past_end[0], past_end[1]), LEN, 1e-6))
ok('a click past the near end is pulled back to the start',
   close(WT.t_from_point_xy(SX, SY, EX, EY, SAG, past_start[0], past_start[1]), 0.0, 1e-6))
ok('the reading is never negative and never past the end',
   [past_start, past_end, mid].all? do |p|
     v = WT.t_from_point_xy(SX, SY, EX, EY, SAG, p[0], p[1])
     v >= -1e-9 && v <= LEN + 1e-6
   end)

# ------------------------------------------- the ruler swings to the panel

def wall_stub(sag)
  g = Sketchup.active_model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', "cw#{sag}")
  g.set_attribute('InteriorPro', 'start_x', SX); g.set_attribute('InteriorPro', 'start_y', SY)
  g.set_attribute('InteriorPro', 'end_x', EX);   g.set_attribute('InteriorPro', 'end_y', EY)
  g.set_attribute('InteriorPro', 'thickness', 6.0)
  g.set_attribute('InteriorPro', 'height', 96.0)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  g.set_attribute('InteriorPro', 'arc_sag', sag) unless sag.zero?
  g
end

Sketchup.reset_model!
straight_wall = wall_stub(0.0)
curved_wall = wall_stub(SAG)

sgeo = DM.wall_geometry(straight_wall)
cgeo = DM.wall_geometry(curved_wall)
ok('a straight wall is not marked as curved', sgeo[:curved] == false)
ok('a curved wall IS marked as curved', cgeo[:curved] == true)
ok('a straight wall measures its straight length', close(sgeo[:wall_length], 240.0, 1e-9))
ok('a curved wall measures the length OF THE CURVE', close(cgeo[:wall_length], LEN, 1e-6))
ok('and that is longer than the straight line', cgeo[:wall_length] > sgeo[:wall_length])
ok('a curved wall remembers its bow', close(cgeo[:sag], SAG, 1e-9))

# A straight wall must get its geo back completely untouched. THE guard.
[0.0, 40.0, 120.0, 240.0].each do |t|
  ok("straight wall: geo_at(#{t}) changes nothing", DM.geo_at(sgeo, t, 36.0).equal?(sgeo))
end
ok('nil geo is handled', DM.geo_at(nil, 10, 36).nil?)

# The whole point: the same old formula, with the same t, must now land in the
# middle of the flat panel the door sits in.
[LEN * 0.25, LEN * 0.5, LEN * 0.75].each do |t|
  g = DM.geo_at(cgeo, t, 36.0)
  pk = WT.opening_pocket(SX, SY, EX, EY, SAG, t, 36.0)
  x = g[:cline_start].x + g[:unit].x * t
  y = g[:cline_start].y + g[:unit].y * t
  ok("at #{t.round(1)}\": the old formula lands on the panel's middle",
     close(x, pk[:center][0], 1e-9) && close(y, pk[:center][1], 1e-9),
     [[x, y], pk[:center]])
  ok("at #{t.round(1)}\": the ruler points along the panel",
     close(g[:unit].x, pk[:dir][0], 1e-9) && close(g[:unit].y, pk[:dir][1], 1e-9),
     [g[:unit].x, g[:unit].y, pk[:dir]])
  ok("at #{t.round(1)}\": the ruler is a unit vector",
     close(Math.sqrt(g[:unit].x**2 + g[:unit].y**2), 1.0, 1e-9))
  ok("at #{t.round(1)}\": across-the-wall is square to along-the-wall",
     close((g[:unit].x * g[:n].x) + (g[:unit].y * g[:n].y), 0.0, 1e-9))
  ok("at #{t.round(1)}\": nothing else about the wall changed",
     g[:thickness] == cgeo[:thickness] && g[:wall_height] == cgeo[:wall_height] &&
     g[:floor_z] == cgeo[:floor_z] && g[:n_side] == cgeo[:n_side])
end

# Doors at different places along the curve must face different ways.
g1 = DM.geo_at(cgeo, LEN * 0.25, 36.0)
g2 = DM.geo_at(cgeo, LEN * 0.75, 36.0)
ok('two doors on the same curve face different ways',
   (g1[:unit].x - g2[:unit].x).abs > 0.05 || (g1[:unit].y - g2[:unit].y).abs > 0.05,
   [[g1[:unit].x, g1[:unit].y], [g2[:unit].x, g2[:unit].y]])
gm = DM.geo_at(cgeo, LEN / 2.0, 36.0)
ok('a door in the middle of this curve faces straight along it',
   close(gm[:unit].x.abs, 1.0, 1e-6), [gm[:unit].x, gm[:unit].y])

# A door that cannot fit leaves the geo alone rather than inventing a place.
ok('an impossible door leaves the ruler alone',
   DM.geo_at(cgeo, 1.0, 36.0).equal?(cgeo))
ok('a door with no width still gets a usable ruler',
   !DM.geo_at(cgeo, LEN / 2.0, 0.0).nil?)

# The door's centre must sit where the hole was actually cut.
tt = LEN / 2.0
gg = DM.geo_at(cgeo, tt, 36.0)
pkk = WT.opening_pocket(SX, SY, EX, EY, SAG, tt, 36.0)
cx = gg[:cline_start].x + gg[:unit].x * tt + gg[:n].x * gg[:n_side]
cy = gg[:cline_start].y + gg[:unit].y * tt + gg[:n].y * gg[:n_side]
ok('the door body sits half a wall off the panel centre, like on a straight wall',
   close(AM.dist(cx, cy, pkk[:center][0], pkk[:center][1]), 3.0, 1e-9),
   AM.dist(cx, cy, pkk[:center][0], pkk[:center][1]))
ok('and it sits square to the panel, not to the straight line',
   close(((cx - pkk[:center][0]) * pkk[:dir][0]) + ((cy - pkk[:center][1]) * pkk[:dir][1]), 0.0, 1e-9))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

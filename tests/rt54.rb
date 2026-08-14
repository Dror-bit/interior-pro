# encoding: utf-8
# rt54 - setting the angle at a corner (2026-08-14).
#
# The second half of what the user asked for. He could only tell a corner was
# not square by building the 3D; the drawing shows him the degrees now, and
# this is how he fixes them: say 90, and the wall swings round the corner until
# it is 90.
#
# The decision behind the code: turning a wall is the SAME operation as
# changing its length - one end stays put, the other goes somewhere new. So
# there is no second copy of the corner-partner, opening, rebuild and re-join
# work; stretch_wall! takes an `aim` and does the move for both.
require './sketchup_stub'
require 'json'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PE = InteriorPro::PlanEditor

def wall!(m, id, sx, sy, ex, ey, th = 5.0)
  g = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy,
    'end_x' => ex, 'end_y' => ey, 'thickness' => th,
    'anchor' => 'bottom-left', 'wall_category' => 'exterior' }
    .each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end

def pts(g)
  %w[start_x start_y end_x end_y].map { |k| g.get_attribute('InteriorPro', k).to_f }
end

# The angle at the shared corner, read back off the model the way the drawing
# reads it: both walls pointing away from the corner.
def angle_at(g1, e1, g2, e2)
  a = pts(g1)
  b = pts(g2)
  p = e1 == :start ? [a[0], a[1]] : [a[2], a[3]]
  va = e1 == :start ? [a[2] - p[0], a[3] - p[1]] : [a[0] - p[0], a[1] - p[1]]
  vb = e2 == :start ? [b[2] - p[0], b[3] - p[1]] : [b[0] - p[0], b[1] - p[1]]
  la = Math.hypot(*va)
  lb = Math.hypot(*vb)
  dot = (va[0] * vb[0] + va[1] * vb[1]) / (la * lb)
  Math.acos([-1.0, [1.0, dot].min].max) * 180 / Math::PI
end

def length_of(g)
  a = pts(g)
  Math.hypot(a[2] - a[0], a[3] - a[1])
end

# ------------------------------------------------------- an L, slightly out
Sketchup.reset_model!
m = Sketchup.active_model
base = wall!(m, 'base', 0, 0, 120, 0)          # along x
arm  = wall!(m, 'arm', 120, 0, 122, 96)        # nearly up, about 1.2 degrees out
was = angle_at(arm, :start, base, :end)
ok('the corner starts out not quite square', (was - 90).abs > 0.5 && (was - 90).abs < 3, was)
len_was = length_of(arm)

ok('turning it returns true', PE.send(:turn_wall!, arm, base, :start, 90.0) != false)
ok('the corner is now exactly ninety',
   (angle_at(arm, :start, base, :end) - 90).abs < 1e-6,
   angle_at(arm, :start, base, :end))
ok('the wall kept its length - it turned, it did not stretch',
   (length_of(arm) - len_was).abs < 1e-6, [length_of(arm), len_was])
ok('the corner itself did not move', pts(arm)[0, 2] == [120.0, 0.0], pts(arm)[0, 2])
ok('and the wall it was measured against did not move',
   pts(base) == [0.0, 0.0, 120.0, 0.0], pts(base))

# it went the short way round, not out the other side
ok('it tidied up towards where it already pointed, not the mirror image',
   pts(arm)[3] > 0, pts(arm))

# ---------------------------------------------------------- other angles
Sketchup.reset_model!
m = Sketchup.active_model
b2 = wall!(m, 'b2', 0, 0, 120, 0)
a2 = wall!(m, 'a2', 120, 0, 200, 60)
[45.0, 30.0, 135.0, 120.0, 90.0].each do |want|
  PE.send(:turn_wall!, a2, b2, :start, want)
  got = angle_at(a2, :start, b2, :end)
  ok("it can be set to #{want.to_i} degrees", (got - want).abs < 1e-6, got)
end

# ------------------------------------------- turning about the OTHER end
Sketchup.reset_model!
m = Sketchup.active_model
b3 = wall!(m, 'b3', 0, 0, 120, 0)
a3 = wall!(m, 'a3', 200, 90, 120, 0)           # its END sits on the corner
PE.send(:turn_wall!, a3, b3, :end, 90.0)
ok('a wall joined by its END turns just the same',
   (angle_at(a3, :end, b3, :end) - 90).abs < 1e-6, angle_at(a3, :end, b3, :end))
ok('and it is the free end that moved',
   pts(a3)[2, 2] == [120.0, 0.0], pts(a3)[2, 2])

# --------------------------------------------------------- refusing nonsense
Sketchup.reset_model!
m = Sketchup.active_model
b4 = wall!(m, 'b4', 0, 0, 120, 0)
a4 = wall!(m, 'a4', 120, 0, 120, 96)
before = pts(a4)
[0.0, 180.0, -30.0, 400.0].each do |bad|
  ok("#{bad.to_i} degrees is refused", PE.send(:turn_wall!, a4, b4, :start, bad) == false)
end
ok('and nothing moved while it was refusing', pts(a4) == before, pts(a4))

ok('a wall already at that angle is left alone',
   PE.send(:turn_wall!, a4, b4, :start, 90.0) == false)
ok('two walls that do not touch are refused',
   PE.send(:turn_wall!, a4, wall!(m, 'far', 900, 900, 1000, 900), :start, 45.0) == false)
ok('a missing wall is refused, not crashed on',
   PE.send(:turn_wall!, nil, b4, :start, 45.0) == false &&
   PE.send(:turn_wall!, a4, nil, :start, 45.0) == false)

# ------------------------------------------- the corner partner comes along
Sketchup.reset_model!
m = Sketchup.active_model
p1 = wall!(m, 'p1', 0, 0, 120, 0)
p2 = wall!(m, 'p2', 120, 0, 122, 96)          # turns
p3 = wall!(m, 'p3', 122, 96, 240, 96)         # hangs off p2's far end
PE.send(:turn_wall!, p2, p1, :start, 90.0)
moved = pts(p2)[2, 2]
ok('the wall turned', (angle_at(p2, :start, p1, :end) - 90).abs < 1e-6)
ok('and the wall attached to its far end followed the corner',
   (pts(p3)[0] - moved[0]).abs < 1e-6 && (pts(p3)[1] - moved[1]).abs < 1e-6,
   [pts(p3)[0, 2], moved])

# with keep_corners off it lets go instead
Sketchup.reset_model!
m = Sketchup.active_model
q1 = wall!(m, 'q1', 0, 0, 120, 0)
q2 = wall!(m, 'q2', 120, 0, 122, 96)
q3 = wall!(m, 'q3', 122, 96, 240, 96)
PE.send(:turn_wall!, q2, q1, :start, 90.0, false)
ok('told not to keep corners, the neighbour stays where it was',
   pts(q3)[0, 2] == [122.0, 96.0], pts(q3)[0, 2])

# -------------------------------- changing a length is exactly what it was
# turn_wall! goes through stretch_wall!, so the old road must be untouched.
Sketchup.reset_model!
m = Sketchup.active_model
s1 = wall!(m, 's1', 0, 0, 120, 0)
ok('a plain length change still works',
   PE.send(:stretch_wall!, s1, 240.0, :end, true) != false)
ok('and it really is 240 long now', (length_of(s1) - 240).abs < 1e-6, length_of(s1))
ok('along the same direction as before', pts(s1) == [0.0, 0.0, 240.0, 0.0], pts(s1))
ok('the same length twice is still refused',
   PE.send(:stretch_wall!, s1, 240.0, :end, true) == false)
ok('and a silly length is still refused',
   PE.send(:stretch_wall!, s1, 2.0, :end, true) == false)

s2 = wall!(m, 's2', 0, 100, 120, 100)
PE.send(:stretch_wall!, s2, 60.0, :start, true)
ok('shortening from the start still moves the start',
   pts(s2) == [60.0, 100.0, 120.0, 100.0], pts(s2))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

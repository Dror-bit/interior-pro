# encoding: utf-8
# rt155 - THE TRIANGULAR HOLE BY THE HOUSE WALL IS CLOSED (2026-09-18).
# His picture, both sides of the house: open air between the top of the
# garage roof and the plane of the house roof, on the house wall line.
# A first round closed the wrong side - UNDER the garage roof, off a
# section drawing that he approved before either of us saw the mistake
# ("זה צריך להיות מחוץ לגג של הגראז'"). It was taken straight out; this
# pins the right one. He hatched it in red on that same section:
#   west  x -606.51 (wall face) .. -534.51 (leg): z 92 -> 110 at the
#         wall, closing to a point at the leg. 72" long, 18" tall.
#   east  x -313.44 .. -385.44, the mirror.
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

RF = InteriorPro::RoofManager
ORIG_VALLEY = RF::USE_ROOF_VALLEY
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, true)

Sketchup.reset_model!
mm = Sketchup.active_model
def roof(m, fp, gables, eave_z, ridge_z, pitch, oh, lvl = 1)
  g = m.entities.add_group
  { 'type' => 'roof', 'footprint_xy' => fp.flatten, 'gable_edges' => gables,
    'eave_z' => eave_z, 'ridge_z' => ridge_z, 'pitch' => pitch,
    'overhang_in' => oh, 'level' => lvl
  }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
HOUSE = [[12.0, 535.82], [-618.51, 535.82], [-618.51, -12.0], [12.0, -12.0]]
GAR   = [[-301.44, -379.2], [-301.44, 17.0], [-618.51, 17.0], [-618.51, -379.2]]
roof(mm, HOUSE, [1, 3], 110.0, 175.48, 3.0, 12.0)
lg = roof(mm, GAR, [3], 92.0, 128.63, 3.0, 12.0)
g = RF.roof_geom(lg)
rs = RF.valley_inside_regions(g[:pts], [false, false, false, true], g[:slope],
                              g[:deck_z], g[:ridge_z], 1, lg)
west = rs.find { |r| r[:poly].all? { |p| p[0] < -459.0 } }
east = rs.find { |r| r[:poly].all? { |p| p[0] > -460.0 } }
ok('the two regions are there', !west.nil? && !east.nil?)

# ---- which end is the leg, which is the roof's outline --------------
pr = west && RF.valley_wall_end_pair(west)
ok('west: the OUTLINE end is the roof edge, x = -618.51',
   pr && near(pr[0][0], -618.51) && near(pr[0][1], 0.0), pr && pr[0])
ok('west: the LEG end is where the two planes meet, x = -534.51',
   pr && near(pr[1][0], -534.51) && near(pr[1][1], 0.0), pr && pr[1])
ok('west: 84" from the roof edge to the leg', pr && near(pr[3], 84.0), pr && pr[3])

# ---- the closing triangle -------------------------------------------
q = west && RF.valley_wall_end_tri(west, 12.0)
ok('west: a three-corner face comes out', q && q.length == 3, q)
if q
  ok('it STARTS at the wall face, one overhang in: x = -606.51',
     near(q[0][0], -606.51) && near(q[2][0], -606.51), [q[0], q[2]])
  ok('...so no wall stands out in the 12" overhang', near(q[0][0] - -618.51, 12.0))
  ok('its point is the valley leg, x = -534.51', near(q[1][0], -534.51))
  ok('72" long', near((q[1][0] - q[0][0]).abs, 72.0), q[1][0] - q[0][0])
  ok('at the wall it runs from the GARAGE roof, z = 92...', near(q[0][2], 92.0), q[0][2])
  ok('...up to the HOUSE roof plane, z = 110 - 18" tall',
     near(q[2][2], 110.0) && near(q[2][2] - q[0][2], 18.0), q[2][2])
  ok('at the leg the two planes are the same height, so it closes to a point',
     near(q[1][2], 110.0), q[1][2])
  ok('the whole face sits ON the wall line, y = 0', q.all? { |p| near(p[1], 0.0) })
  ok('nothing of it hangs BELOW the garage roof - that was the wrong side',
     q.all? { |p| p[2] >= RF.plane_z(west[:plane], p[0], p[1]) - 0.01 }, q)
end

qe = east && RF.valley_wall_end_tri(east, 12.0)
ok('east: the mirror, x -313.44 .. -385.44, z 92 -> 110',
   qe && near(qe[0][0], -313.44) && near(qe[1][0], -385.44) &&
   near(qe[0][2], 92.0) && near(qe[2][2], 110.0), qe)

# ---- it does not build where there is nothing to build --------------
ok('an overhang as long as the whole run leaves nothing to close',
   RF.valley_wall_end_tri(west, 84.0).nil?)

RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, ORIG_VALLEY)
puts($fails.zero? ? 'rt155 OK' : "rt155 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

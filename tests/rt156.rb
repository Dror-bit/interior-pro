# encoding: utf-8
# rt156 - THE RIDGE CAP RUNS ON TO THE APEX (2026-09-18, his list:
# "רידג' קאפ לגראז' נעלם אחרי ההארכה - להחזיר, כולל עד הקודקוד").
#
# valley_extend! carries the garage's two planes past its abut line up to
# the apex, where they and the house plane all meet. The cap walk runs
# EARLIER in the build, so that stretch of ridge was never capped -
# measured on his model (ridge_report.txt): the cap stops at the polygon
# edge, y=17, and the apex is at y=74.54. This pins the stretch that has
# to be capped: 57.54" at x = -459.975, from z 128.63 at both ends
# (the ridge is level).
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
hgrp = roof(mm, HOUSE, [1, 3], 110.0, 175.48, 3.0, 12.0)
lg   = roof(mm, GAR, [3], 92.0, 128.63, 3.0, 12.0)

lo = RF.roof_geom(lg)
hi = RF.roof_geom(hgrp)
pair = RF.two_side_planes(lo)
ok('the garage has its two slope planes', !pair.nil?)
hp = RF.edge_plane(hi, 2) # the house's south eave, the one it runs into
ok('the house plane over the garage is there', !hp.nil?)

apex = RF.planes_apex(pair[0], pair[1], hp)
ok('the APEX is where all three planes meet: (-459.975, 74.54, 128.63)',
   apex && near(apex[0], -459.975) && near(apex[1], 74.54) && near(apex[2], 128.63, 0.02),
   apex)

ridge = RF.planes_meet(pair[0], pair[1])
ok('the garage ridge runs at x = -459.975', ridge && near(ridge[0][0], -459.975), ridge)

# edge 1 of the garage polygon is the abut line, y = 17
abut = RF.edge_line(lo[:pts], 1)
ok('edge 1 is the abut line, y = 17', abut && near(abut[0][1], 17.0), abut)
b = RF.lines_meet_xy(ridge[0], ridge[1], abut[0], abut[1])
ok('the ridge crosses it at (-459.975, 17) - where the cap stops today',
   b && near(b[0], -459.975) && near(b[1], 17.0), b)

run = b && apex ? Math.hypot(apex[0] - b[0], apex[1] - b[1]) : nil
ok('so 57.54" of ridge is uncapped', near(run, 57.54, 0.02), run)
ok('and the ridge is LEVEL over it - both ends at the garage ridge height',
   near(RF.plane_z(pair[0], b[0], b[1]), 128.63, 0.02) &&
   near(RF.plane_z(pair[0], apex[0], apex[1]), 128.63, 0.02),
   [RF.plane_z(pair[0], b[0], b[1]), RF.plane_z(pair[0], apex[0], apex[1])])

# the apex must lie PAST the abut line, or there is no extension at all
ok('the apex is on the house side of the abut line', apex[1] > 17.0)

RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, false)
ok('with the flag off nothing carries on - valley_extend! is not entered',
   RF.valley_extend!(lg, nil, nil, [1]).nil?)
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, ORIG_VALLEY)

puts($fails.zero? ? 'rt156 OK' : "rt156 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

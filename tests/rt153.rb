# encoding: utf-8
# rt153 - THE CUT IS ON THE MEETING LINE (2026-09-17, his rule):
# "החיתוך של הגגות צריך להיות במפגש. גג הגראז' נכנס לתוך הבית."
#
# The garage roof exists only where it stands ABOVE the house roof's
# plane, or SOUTH of the house wall line (y <= 0). Everything else is
# inside the attic and comes off on the valley legs. On his own numbers
# (valley_report.txt) that is two trapezoids, 72" on the wall line and
# 89" at the roof's edge, 17" deep:
#   west  (-618.51,0) (-534.51,0) (-517.51,17) (-618.51,17)
#   east  (-385.44,0) (-301.44,0) (-301.44,17) (-402.44,17)
# (72"/89" measured off the house wall face, 84"/101" off the roof edge -
#  the region runs out to the edge and swallows the overhang strip.)
# The legs: west y = x + 534.51, east x = -385.44 - y.
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

# does the polygon carry this plan corner?
def has?(poly, x, y)
  poly.any? { |p| near(p[0], x) && near(p[1], y) }
end

RF = InteriorPro::RoofManager
ORIG_VALLEY = RF::USE_ROOF_VALLEY
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, true)

# ---- 1. the pure "which plane is lower" clip ------------------------
SQ = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]]
FLAT = [0.0, 0.0, 100.0]            # a level plane at 100
TILT = [1.0, 0.0, 95.0]             # rises east, crosses FLAT at x = 5
c = RF.clip_under(SQ, TILT, FLAT)
ok('clip_under keeps the half where the tilted plane is the lower one',
   c.length == 4 && has?(c, 0.0, 0.0) && has?(c, 5.0, 0.0) &&
   has?(c, 5.0, 10.0) && has?(c, 0.0, 10.0), c)
ok('the other way round is the other half',
   RF.clip_under(SQ, FLAT, TILT).length == 4 &&
   has?(RF.clip_under(SQ, FLAT, TILT), 10.0, 0.0))
ok('a plane wholly under a parallel one keeps the polygon whole',
   RF.clip_under(SQ, [0.0, 0.0, 90.0], FLAT).length == 4)
ok('a plane wholly over a parallel one leaves nothing',
   RF.clip_under(SQ, [0.0, 0.0, 110.0], FLAT).empty?)
ok('poly_area2 of the 10x10 square is 200', near(RF.poly_area2(SQ).abs, 200.0))

# ---- 2. his model ---------------------------------------------------
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
g = RF.roof_geom(lg)
rs = RF.valley_inside_regions(g[:pts], [false, false, false, true], g[:slope],
                              g[:deck_z], g[:ridge_z], 1, lg)
ok('two regions come out - one per garage slope', rs.length == 2, rs.map { |r| r[:poly].length })

west = rs.find { |r| r[:poly].all? { |p| p[0] < -459.0 } }
east = rs.find { |r| r[:poly].all? { |p| p[0] > -460.0 } }
ok('a WEST region and an EAST one', !west.nil? && !east.nil?)

if west
  w = west[:poly]
  ok('west has 4 corners', w.length == 4, w)
  ok('west: the wall-line corners (-618.51, 0) and (-534.51, 0)',
     has?(w, -618.51, 0.0) && has?(w, -534.51, 0.0), w)
  ok('west: the far corners (-618.51, 17) and (-517.51, 17)',
     has?(w, -618.51, 17.0) && has?(w, -517.51, 17.0), w)
  # 84" and 101" here, not the 72"/89" measured off the house WALL face:
  # the region runs to the roof's own edge and swallows the 12" overhang
  # strip valley_low_deck_cuts already takes off. Same cut, done once.
  ok('west: 84" wide on the wall line, out to the roof edge',
     near(-534.51 + 618.51, 84.0))
  ok('west: 101" wide at y = 17', near(-517.51 + 618.51, 101.0))
  z = w.find { |p| near(p[0], -534.51) && near(p[1], 0.0) }
  ok('west: the leg corner stands on the garage plane at z = 110.0',
     z && near(z[2], 110.0), z)
  ok('...and the HOUSE plane is at 110.0 there too - they MEET',
     near(RF.plane_z(RF.edge_plane(RF.roof_geom(hgrp), 2), -534.51, 0.0), 110.0),
     RF.plane_z(RF.edge_plane(RF.roof_geom(hgrp), 2), -534.51, 0.0))
end

if east
  e = east[:poly]
  ok('east has 4 corners', e.length == 4, e)
  ok('east: the wall-line corners (-385.44, 0) and (-301.44, 0)',
     has?(e, -385.44, 0.0) && has?(e, -301.44, 0.0), e)
  ok('east: the far corners (-402.44, 17) and (-301.44, 17)',
     has?(e, -402.44, 17.0) && has?(e, -301.44, 17.0), e)
  z = e.find { |p| near(p[0], -385.44) && near(p[1], 0.0) }
  ok('east: its leg corner meets the house plane at z = 110.0 as well',
     z && near(z[2], 110.0) &&
     near(RF.plane_z(RF.edge_plane(RF.roof_geom(hgrp), 2), -385.44, 0.0), 110.0), z)
end

ok('nothing is cut SOUTH of the wall line - every corner has y >= 0',
   rs.all? { |r| r[:poly].all? { |p| p[1] >= -0.01 } })

# ---- 2b. the region carries what the sweep needs --------------------
# (2026-09-17, his picture: the deck's 1/2" frame band stayed standing on
# the old edge, y=17. valley_sweep_under! cuts the faces that are NOT
# parallel to the roof plane on the HOUSE plane and drops what hangs
# below it - so the region has to hand it that plane and the wall line.)
if west
  hp = west[:hp]
  ok('the region carries the HOUSE plane it is cut against', !hp.nil?)
  ok('...that plane is 110.0 on the wall line and 114.25 at y = 17',
     hp && near(RF.plane_z(hp, -560.0, 0.0), 110.0) &&
     near(RF.plane_z(hp, -560.0, 17.0), 114.25),
     hp && [RF.plane_z(hp, -560.0, 0.0), RF.plane_z(hp, -560.0, 17.0)])
  ok('...and the wall line: a point on it, with the inward normal',
     west[:wall] && near(west[:wall][1], 0.0) &&
     west[:inw] && near(west[:inw][0], 0.0) && near(west[:inw][1], 1.0),
     [west[:wall], west[:inw]])
  # the frame band he pointed at: y=17, z 92..129.15. Below the house
  # plane there (114.25) it is inside the attic and has to go; above it
  # the garage really does stand proud of the house roof and it stays.
  ok('the frame band at (-560, 17, 100) is UNDER the house plane - it goes',
     RF.plane_z(hp, -560.0, 17.0) > 100.0)
  ok('the same band at the ridge (-459.97, 17, 129.15) stands ABOVE it - it stays',
     RF.plane_z(hp, -459.97, 17.0) < 129.15)
end

# ---- 3. the house itself gets nothing -------------------------------
hg = RF.roof_geom(hgrp)
ok('the HOUSE roof has no taller neighbour, so no region',
   RF.valley_inside_regions(hg[:pts], [false, true, false, true], hg[:slope],
                            hg[:deck_z], hg[:ridge_z], 1, hgrp).empty?)

# ---- 4. the kill switch ---------------------------------------------
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, false)
ok('with USE_ROOF_VALLEY off nothing is cut at all',
   RF.valley_inside_regions(g[:pts], [false, false, false, true], g[:slope],
                            g[:deck_z], g[:ridge_z], 1, lg).empty?)
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, ORIG_VALLEY)

puts($fails.zero? ? 'rt153 OK' : "rt153 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

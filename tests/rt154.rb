# encoding: utf-8
# rt154 - THE HOUSE'S EAVE DRESSING MEETS THE GARAGE ROOF, IT DOES NOT
# RUN INTO IT (2026-09-18, his rule: "נפגשים, לא נכנסים").
#
# Between the two valley legs the dressing is skipped already. OUTSIDE
# them it stays built - and on his model the garage's west plane runs
# straight THROUGH the fascia for 32", from z 99 (the soffit) up to
# z 107 (the fascia top): west x -578.51..-546.51, east the mirror
# x -373.44..-341.44. valley_cuts now hands out the low roof's two
# planes and the dressing strip over it, and valley_sweep_under! cuts
# the boards on that plane and drops what hangs below.
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
roof(mm, GAR, [3], 92.0, 128.63, 3.0, 12.0)

hg = RF.roof_geom(hgrp)
cuts = RF.valley_cuts(hg[:pts], [false, true, false, true], hg[:slope],
                      hg[:deck_z], hg[:ridge_z], 1, hgrp, hg[:oh])
ok('the cut lands on edge 2 - the SOUTH eave, the one facing the garage',
   cuts.keys == [2], cuts.keys)
v = cuts[2] && cuts[2].first
ok('there is one cut on it', !v.nil?)
ok('the six-argument call still works, and asks for no strip (rt151)',
   RF.valley_cuts(hg[:pts], [false, true, false, true], hg[:slope],
                  hg[:deck_z], hg[:ridge_z], 1, hgrp)[2].first[:span] == v[:span])

if v
  # ---- the skipped stretch: between the two legs ---------------------
  # edge 2 runs (-618.51,-12) -> (12,-12), so t is x + 618.51
  ok('the dressing is skipped from the WEST leg (x=-546.51, t=72)...',
     near(v[:span][0], 72.0), v[:span])
  ok('...to the EAST leg (x=-373.44, t=245.07)',
     near(v[:span][1], 245.07), v[:span])

  # ---- the strip the sweep works on ----------------------------------
  ok('the strip covers the garage in plan, x -618.51..-301.44',
     v[:strip] && near(v[:strip].map { |p| p[0] }.min, -618.51) &&
     near(v[:strip].map { |p| p[0] }.max, -301.44), v[:strip])
  ok('...and reaches 8" out past the eave for the fascia and the gutter, ' \
     'and the 12" overhang in for the soffit',
     v[:strip] && near(v[:strip].map { |p| p[1] }.min, -20.0) &&
     near(v[:strip].map { |p| p[1] }.max, 0.0), v[:strip])

  # ---- the two garage planes, and the 32" band -----------------------
  west = v[:lo] && v[:lo].find { |pl| pl[0] > 0 }   # rises going east
  east = v[:lo] && v[:lo].find { |pl| pl[0] < 0 }
  ok('the cut carries the garage\'s two planes', !west.nil? && !east.nil?, v[:lo])
  if west
    ok('west plane: z = 99 (the soffit) at x = -578.51',
       near(RF.plane_z(west, -578.51, -12.0), 99.0),
       RF.plane_z(west, -578.51, -12.0))
    ok('west plane: z = 107 (the fascia top) at x = -546.51',
       near(RF.plane_z(west, -546.51, -12.0), 107.0),
       RF.plane_z(west, -546.51, -12.0))
    ok('...so the band that gets cut is 32" wide', near(-546.51 + 578.51, 32.0))
    ok('the band ENDS exactly where the skipped stretch begins (t=72)',
       near(v[:span][0], -546.51 + 618.51))
    ok('40" further west the plane is under the soffit - nothing is touched',
       RF.plane_z(west, -598.51, -12.0) < 99.0,
       RF.plane_z(west, -598.51, -12.0))
  end
  if east
    ok('east plane: z = 99 at x = -341.44 and z = 107 at x = -373.44',
       near(RF.plane_z(east, -341.44, -12.0), 99.0) &&
       near(RF.plane_z(east, -373.44, -12.0), 107.0),
       [RF.plane_z(east, -341.44, -12.0), RF.plane_z(east, -373.44, -12.0)])
  end

  # ---- each plane takes its own half of the strip ---------------------
  if west && east
    w = RF.clip_under(v[:strip], west, east)
    e = RF.clip_under(v[:strip], east, west)
    ok('the strip splits on the garage RIDGE, x = -459.975',
       near(w.map { |p| p[0] }.max, -459.975) &&
       near(e.map { |p| p[0] }.min, -459.975),
       [w.map { |p| p[0] }.max, e.map { |p| p[0] }.min])
    ok('the west half still holds the 32" band',
       w.map { |p| p[0] }.min <= -578.51)
  end
end

# ---- the kill switch -------------------------------------------------
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, false)
ok('with USE_ROOF_VALLEY off there is no cut at all',
   RF.valley_cuts(hg[:pts], [false, true, false, true], hg[:slope],
                  hg[:deck_z], hg[:ridge_z], 1, hgrp, hg[:oh]).empty?)
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, ORIG_VALLEY)

puts($fails.zero? ? 'rt154 OK' : "rt154 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

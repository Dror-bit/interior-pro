# encoding: utf-8
# rt151 - THE VALLEY between the low roof and the high one (2026-09-15).
#
# The user: "צריך שהגגות יתחברו, כרגע זה שני גגות נפרדים". The garage
# roof dies vertically into the house wall today; what he wants is the
# low roof's two planes running on into the house roof's plane, meeting
# it on two valleys, and the house's eave trim cut away between them.
#
# WHAT IS PINNED HERE: the pure maths, against the REAL numbers measured
# off his model (debug_valley.rb -> valley_report.txt, 2026-09-03):
#   house  eave_z 110 at the wall (y=0), 3:12, south eave line y=-12
#   garage eave_z  92 at the wall, 12" overhang, 3:12,
#          footprint x -618.51 .. -301.44, ridge at x=-459.975, z 128.63
# The apex the maths finds MUST come out at the garage's own ridge
# height - if it does not, the two roofs are not being fitted, they are
# being guessed.
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

SLOPE = 0.25          # 3:12
HOUSE_EAVE_Y = -12.0  # the house's south fascia line
HOUSE_DECK_AT_EAVE = 107.0 # eave_z 110 at the wall, less 12" of overhang
GAR_W = -618.51       # garage footprint, west edge
GAR_E = -301.44       # ...and east edge
GAR_DECK = 89.0       # eave_z 92 at the wall, less 12" of overhang

# ---- the three planes ------------------------------------------------
hi = RF.plane_abc([0.0, HOUSE_EAVE_Y], [0, 1], SLOPE, HOUSE_DECK_AT_EAVE)
ok('the house plane is z = 0.25y + 110',
   near(hi[0], 0.0) && near(hi[1], 0.25) && near(hi[2], 110.0), hi)
ok('...and it stands at 175.48 on the ridge, y=261.91',
   near(RF.plane_z(hi, 0.0, 261.91), 175.4775), RF.plane_z(hi, 0.0, 261.91))

lo_w = RF.plane_abc([GAR_W, 0.0], [1, 0], SLOPE, GAR_DECK)
lo_e = RF.plane_abc([GAR_E, 0.0], [-1, 0], SLOPE, GAR_DECK)
ok('the garage west plane rises eastwards from 89',
   near(RF.plane_z(lo_w, GAR_W, 0.0), 89.0) &&
   near(RF.plane_z(lo_w, -459.975, 0.0), 128.63375), RF.plane_z(lo_w, -459.975, 0.0))
ok('the garage east plane rises westwards from 89',
   near(RF.plane_z(lo_e, GAR_E, 0.0), 89.0) &&
   near(RF.plane_z(lo_e, -459.975, 0.0), 128.63375), RF.plane_z(lo_e, -459.975, 0.0))
ok('a zero direction is refused, not divided by', RF.plane_abc([0, 0], [0, 0], SLOPE, 0.0).nil?)

# ---- the apex --------------------------------------------------------
ap = RF.planes_apex(lo_w, lo_e, hi)
ok('THE APEX IS ON THE GARAGE RIDGE LINE, x = -459.975',
   near(ap && ap[0], -459.975), ap && ap[0])
ok('...74.54" north of the house wall', near(ap && ap[1], 74.535), ap && ap[1])
ok('...AND AT THE GARAGE ROOF\'S OWN RIDGE HEIGHT, 128.63',
   near(ap && ap[2], 128.63375), ap && ap[2])
ok('the apex sits on all three planes at once',
   near(RF.plane_z(lo_w, ap[0], ap[1]), ap[2]) &&
   near(RF.plane_z(lo_e, ap[0], ap[1]), ap[2]) &&
   near(RF.plane_z(hi, ap[0], ap[1]), ap[2]),
   [RF.plane_z(lo_w, ap[0], ap[1]), RF.plane_z(lo_e, ap[0], ap[1]), RF.plane_z(hi, ap[0], ap[1])])
ok('two parallel planes have no apex',
   RF.planes_apex(lo_w, lo_w, hi).nil? && RF.planes_meet(hi, [hi[0], hi[1], hi[2] + 9]).nil?)

# ---- the legs and the cut -------------------------------------------
v = RF.roof_valley(lo_w, lo_e, hi, [[0.0, HOUSE_EAVE_Y], [1, 0]])
ok('roof_valley answers', !v.nil?)
ok('the west leg lands on the house eave at x = -546.51',
   near(v[:cut][0][0], -546.51) && near(v[:cut][0][1], HOUSE_EAVE_Y), v[:cut][0])
ok('the east leg lands on the house eave at x = -373.44',
   near(v[:cut][1][0], -373.44) && near(v[:cut][1][1], HOUSE_EAVE_Y), v[:cut][1])
ok('SO 173.07" OF THE HOUSE EAVE IS CUT - and no more',
   near(v[:cut_len], 173.07), v[:cut_len])
ok('both legs run from the eave UP to the apex',
   v[:legs].all? { |l| near(l[0][2], HOUSE_DECK_AT_EAVE) && l[1] == v[:apex] },
   v[:legs].map { |l| l[0][2] })
ok('the cut stays inside the house eave, x -618.51 .. 12',
   v[:cut].all? { |p| p[0] > -618.51 && p[0] < 12.0 }, v[:cut])
ok('the cut stays inside the garage width, so the fascia lives on both sides',
   v[:cut].all? { |p| p[0] > GAR_W && p[0] < GAR_E }, v[:cut])
ok('a low roof that never reaches the high plane gives no valley',
   RF.roof_valley(lo_w, lo_w, hi, [[0.0, HOUSE_EAVE_Y], [1, 0]]).nil?)

# ---- the same planes, READ OFF A ROOF GROUP --------------------------
# The trap this pins: eave_z is measured at the WALL, not at the eave
# edge, so the overhang's drop has to come off it. Get that wrong and
# every plane here is 3" out and the valley lands somewhere else.
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
# his house and his garage, exactly as valley_report.txt found them
hg = roof(mm, [[12.0, 535.82], [-618.51, 535.82], [-618.51, -12.0], [12.0, -12.0]],
          [1, 3], 110.0, 175.48, 3.0, 12.0)
lg = roof(mm, [[-301.44, -379.2], [-301.44, 17.0], [-618.51, 17.0], [-618.51, -379.2]],
          [3], 92.0, 128.63, 3.0, 12.0)
hgm = InteriorPro::RoofManager.roof_geom(hg)
lgm = InteriorPro::RoofManager.roof_geom(lg)
ok('the deck height is taken at the EAVE, not at the wall: house 107',
   near(hgm[:deck_z], 107.0), hgm[:deck_z])
ok('...and garage 89', near(lgm[:deck_z], 89.0), lgm[:deck_z])
ok('the house south edge (2) reads back as the plane z = 0.25y + 110',
   (pl = RF.edge_plane(hgm, 2)) && near(pl[0], 0.0) && near(pl[1], 0.25) && near(pl[2], 110.0),
   RF.edge_plane(hgm, 2))
ok('the garage two sides read back as the same two planes',
   near(RF.edge_plane(lgm, 0)[2], 13.64) && near(RF.edge_plane(lgm, 2)[2], 243.6275),
   [RF.edge_plane(lgm, 0), RF.edge_plane(lgm, 2)])
ok('and the apex off THOSE is the one measured in the model',
   (ap2 = RF.planes_apex(RF.edge_plane(lgm, 0), RF.edge_plane(lgm, 2), RF.edge_plane(hgm, 2))) &&
   near(ap2[0], -459.975) && near(ap2[1], 74.535) && near(ap2[2], 128.63375), ap2)
# the partner search: from just past the garage abut line (edge 1, y=17)
part = RF.valley_partner(lg, lgm, [-459.975, 41.0])
ok('the garage finds the HOUSE roof above it...', part[0] == hg, part[0].class)
ok('...and picks the house SOUTH plane, the one actually overhead',
   part[2] == 2, part[2])
ok('a roof no lower than us is not a partner',
   RF.valley_partner(hg, hgm, [-459.975, 41.0])[0].nil?)

# ---- the kill switch is there, and it is OFF -------------------------
ok('USE_ROOF_VALLEY exists', RF.const_defined?(:USE_ROOF_VALLEY))
ok('...and starts OFF, so nothing he has built moves today',
   RF::USE_ROOF_VALLEY == false, RF::USE_ROOF_VALLEY)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

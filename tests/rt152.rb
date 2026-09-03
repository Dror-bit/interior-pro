# encoding: utf-8
# rt152 - THE GARAGE EAVE'S END PLATE STANDS AT THE WALL, NOT AT THE
# CORNER (2026-09-03, his green plate).
#
# valley_low_spans pulls the garage's west trim back 17" to the house
# wall line (y=0). Its end plate (build_end_caps!) went on standing at
# the polygon corner (y=17) - a 12x11 white plate in mid air with the
# deck's half-inch edge sliver running back to the fascia. He painted it
# green: "היא לא אמורה להיות שם, זה יתרה מהפשייה". Pinned here:
#   1. cap_corner_pull_back moves the corner to the span's inner end
#   2. valley_low_deck_cuts hands the strip its wall line and inner line
#      for valley_low_strip_sweep!
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

# his garage footprint, CCW as roof_geom hands it out
GAR = [[-301.44, -379.2], [-301.44, 17.0], [-618.51, 17.0], [-618.51, -379.2]]
# edge 0: east eave, heads north  (-301.44,-379.2)->(-301.44,17)   len 396.2
# edge 2: west eave, heads south  (-618.51,17)->(-618.51,-379.2)   len 396.2
SPANS = { 2 => [[0.0, 17.0]], 0 => [[379.2, 396.2]] }

# ---- 1. the pure corner pull-back -----------------------------------
c = RF.cap_corner_pull_back(GAR, 2, GAR[2], SPANS)
ok('WEST corner (-618.51, 17) is pulled back to the wall line, y = 0',
   near(c[0], -618.51) && near(c[1], 0.0), c)
c = RF.cap_corner_pull_back(GAR, 0, GAR[1], SPANS)
ok('EAST corner (-301.44, 17) - the tail end of edge 0 - the same',
   near(c[0], -301.44) && near(c[1], 0.0), c)
c = RF.cap_corner_pull_back(GAR, 2, GAR[3], SPANS)
ok('the far corner of the west eave (y=-379.2) is not touched',
   near(c[0], -618.51) && near(c[1], -379.2), c)
ok('no spans at all - the corner stays', RF.cap_corner_pull_back(GAR, 2, GAR[2], nil) == GAR[2])
ok('spans on another edge only - the corner stays',
   RF.cap_corner_pull_back(GAR, 2, GAR[2], { 0 => [[379.2, 396.2]] }) == GAR[2])
ok('a span that swallows the WHOLE edge (the abut tuck) is not a pull-back',
   RF.cap_corner_pull_back(GAR, 2, GAR[2], { 2 => [[0.0, 396.2]] }) == GAR[2])
ok('a span in the middle of the edge does not move an end',
   RF.cap_corner_pull_back(GAR, 2, GAR[2], { 2 => [[100.0, 120.0]] }) == GAR[2])

# ---- 2. the strip knows its two cut lines ---------------------------
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
roof(mm, [[12.0, 535.82], [-618.51, 535.82], [-618.51, -12.0], [12.0, -12.0]],
     [1, 3], 110.0, 175.48, 3.0, 12.0)
lg = roof(mm, GAR, [3], 92.0, 128.63, 3.0, 12.0)
lgm = RF.roof_geom(lg)
lc = RF.valley_low_deck_cuts(lgm[:pts], [false, false, false, true], lgm[:slope],
                             lgm[:deck_z], lgm[:ridge_z], 1, lg, 12.0)
w = lc.find { |v| v[:poly][0][0] < -400 }
ok('the west strip carries its WALL line: (-618.51,0) -> (-606.51,0)',
   w && w[:wall] && near(w[:wall][0][0], -618.51) && near(w[:wall][0][1], 0.0) &&
   near(w[:wall][1][0], -606.51) && near(w[:wall][1][1], 0.0), w && w[:wall])
ok('...its along-the-eave direction (0,-1)',
   w && w[:along] && near(w[:along][0], 0.0) && near(w[:along][1], -1.0), w && w[:along])
ok('...and its INNER line at the wall face, x = -606.51',
   w && w[:inner] && near(w[:inner][0][0], -606.51) && near(w[:inner][1][0], -606.51) &&
   w[:inw] && near(w[:inw][0], 1.0), w && [w[:inner], w[:inw]])
e = lc.find { |v| v[:poly][0][0] > -400 }
ok('the east strip: wall line at y = 0 too, (-301.44,0) -> (-313.44,0)',
   e && e[:wall] && near(e[:wall][0][1], 0.0) && near(e[:wall][1][0], -313.44), e && e[:wall])

# ---- the kill switch still ships OFF ---------------------------------
ok('USE_ROOF_VALLEY ships OFF', ORIG_VALLEY == false, ORIG_VALLEY)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt157 - THE DOWNSPOUT STANDS CLEAR OF THE HOUSE (2026-09-18).
# Measured on his model (spout_report.txt): the garage's west pipe stood
# at (-614.19, -1.00) - 18" back from the polygon corner (12" overhang +
# 6" inset), which is one inch past where the valley now ends the gutter,
# on the house wall line y=0. He asked for 4" more south: y = -5.
# A pipe next to a stretch the valley took the trim off backs off
# DS_VALLEY_BACK further. And the pipe he took off by hand keeps its
# identity across that move - its key was where it STOOD.
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
GAR = [[-301.44, -379.2], [-301.44, 17.0], [-618.51, 17.0], [-618.51, -379.2]]
# edge 2 is the west eave, heading south from the corner at y = 17;
# edge 0 is the east eave, heading north and ENDING at y = 17.
PULL = { 2 => [[0.0, 17.0]], 0 => [[379.2, 396.2]] }
# edge 1 is the abut line into the house - the builder hands it in as a
# skipped edge, which is why his east pipe sits on edge 0 at y = -1 and
# not on the abut line (spout_report.txt: its off-key is -301.4,-1.0).
GABLES = [false, true, false, true]

ok('DS_VALLEY_BACK is 4"', near(RF::DS_VALLEY_BACK, 4.0))

# ---- without the valley: 18" back, exactly as before ----------------
old = RF.downspout_spots(GAR, GABLES, 12.0)
w = old.find { |(p, _e)| near(p[0], -618.51) && p[1] > -100 }
ok('west pipe used to stand at y = -1 (17 - 18)', w && near(w[0][1], -1.0), w && w[0])
e = old.find { |(p, _e)| near(p[0], -301.44) && p[1] > -100 }
ok('east pipe used to stand at y = -1 too', e && near(e[0][1], -1.0), e && e[0])

# ---- with the valley's spans: 4" further south ----------------------
now = RF.downspout_spots(GAR, GABLES, 12.0, RF::DS_INSET, PULL)
w2 = now.find { |(p, _e)| near(p[0], -618.51) && p[1] > -100 }
ok('west pipe now stands at y = -5 - 4" south', w2 && near(w2[0][1], -5.0), w2 && w2[0])
ok('...and it carries where it USED to stand, for the off-list',
   w2 && w2[2] && near(w2[2][1], -1.0), w2 && w2[2])
ok('its old key is the one he clicked: -618.5,-1.0',
   w2 && RF.downspout_key(w2[2]) == '-618.5,-1.0', w2 && RF.downspout_key(w2[2]))
e2 = now.find { |(p, _e)| near(p[0], -301.44) && p[1] > -100 }
ok('east pipe moves the same way, off the far END of its edge',
   e2 && near(e2[0][1], -5.0), e2 && e2[0])
ok('...its old key is -301.4,-1.0, the one in his model\'s off-list',
   e2 && RF.downspout_key(e2[2]) == '-301.4,-1.0', e2 && RF.downspout_key(e2[2]))

# ---- the far corners, nowhere near the valley, do not move ----------
far = now.select { |(p, _e)| p[1] < -300 }
ok('the two south pipes stay at 18" back (y = -361.2)',
   far.length == 2 && far.all? { |(p, _e)| near(p[1], -361.2) },
   far.map { |(p, _e)| p })
ok('...and a roof with no pulled spans at all is untouched',
   RF.downspout_spots(GAR, GABLES, 12.0, RF::DS_INSET, nil)
     .map { |(p, _e)| [p[0].round(2), p[1].round(2)] } ==
   old.map { |(p, _e)| [p[0].round(2), p[1].round(2)] })

# ---- a span in the MIDDLE of an edge is not a corner --------------
mid = RF.downspout_spots(GAR, GABLES, 12.0, RF::DS_INSET, { 2 => [[100.0, 140.0]] })
mw = mid.find { |(p, _e)| near(p[0], -618.51) && p[1] > -100 }
ok('a stretch away from the corner does not move the pipe',
   mw && near(mw[0][1], -1.0), mw && mw[0])

puts($fails.zero? ? 'rt157 OK' : "rt157 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

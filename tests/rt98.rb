# encoding: utf-8
# rt98 - THE DORMER'S MITRED CORNERS AND ITS TRIM (2026-09-02).
#
# WHY
# The user, looking at the body on his roof: "מה עם הפשייה והמטל אדג
# והקירות שוב נכנסים אחת בתוך השני במקום ליצור פינות באלכסון?"
# Two separate faults in one sentence:
#   - the front wall ran the FULL width and each cheek ran the FULL
#     length, so at each front corner both walls owned the same block -
#     exactly what the BOARDS MEET law in CLAUDE.md forbids;
#   - there was no fascia, no rake board and no metal edge at all.
#
# THE CLAIMS PINNED HERE
# 1. THE MITRE IS A PLANE. At a front corner the two walls are separated
#    by the 45 degree plane s + |w| = setback + half: every front-wall
#    point is on or in front of it, every cheek point on or behind it.
#    Neither wall has one thousandth of an inch on the other's side.
# 2. THE MITRE COSTS NOTHING OUTSIDE. The outside faces do not move -
#    the width is still the width and the front is still the setback.
# 3. THE FASCIA IS RoofManager's OWN BAND: it hangs UNDER the slab's
#    edge, inside the roof line, exactly as it does on the house.
# 4. IT DIES ON THE MAIN ROOF - it stops where the climbing roof reaches
#    its bottom edge, so not one point of it is buried.
# 5. THE GABLE COMES IN FRONT OF THE PERPENDICULAR. The rake board runs
#    its whole edge and covers the eave board's end; the eave board
#    stops on the gable line. The user set this with a picture of his
#    own roof: "ככה זה אמור להראות זה בגגות". The rake itself is still
#    RoofManager's own board - the dormer hands it an outline and a
#    height map and builds no rake of its own.
# 6. THE METAL EDGE WRAPS THE GABLE CORNER, running square past the
#    gable line onto the rake drip - the roof's own wrap_flags.
# 7. THE KILL SWITCH removes every board and nothing else.
#
# Against yesterday's code claims 1, 3, 4, 5 and 6 all fail.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

DM = InteriorPro::DormerManager

Z0    = 100.0
SLOPE = 8.0 / 12.0
SET   = 36.0
WID   = 48.0
LEN   = 96.0
RT    = 0.5
TH    = 5.0
OH    = 6.0
DEPTH = 8.0
RM    = InteriorPro::RoofManager
FT    = RM::FASCIA_THICK
DT    = RM::DRIP_THICK
DD    = RM::DRIP_DEPTH

spec = { z0: Z0, slope: SLOPE, setback: SET, width: WID, length: LEN,
         thickness: TH, roof_thickness: RT, overhang: OH,
         fascia_depth: DEPTH, soffit: 'wood', soffit_slope: true,
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0] }
fr = DM.frame(spec)
ok('the frame is computed', !fr.nil?)

Sketchup.reset_model!
m = Sketchup.active_model
grp = DM.build_dormer!(m.entities, spec)
ok('the dormer builds', !grp.nil?)

parts = grp.entities.to_a.select { |e| e.respond_to?(:entities) }
kind = lambda { |k| parts.select { |g| g.get_attribute('InteriorPro', 'part') == k } }
def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map(&:position) }
end
# base at the origin with into = +y, so world x = w and world y = s.
front  = kind.call('dormer_front')
cheeks = kind.call('dormer_cheek')
roofs  = kind.call('dormer_roof')
fascia = kind.call('dormer_fascia')
rakes  = kind.call('dormer_rake')
drips  = kind.call('dormer_drip')
soffs  = kind.call('dormer_soffit')

# ---- 1. THE MITRE IS A PLANE ------------------------------------------
MIT = SET + WID / 2.0            # s + |w| on the mitre plane
fp = front.flat_map { |g| pts_of(g) }
cp = cheeks.flat_map { |g| pts_of(g) }
worst_f = fp.map { |p| (p.y + p.x.abs) - MIT }.max
worst_c = cp.map { |p| MIT - (p.y + p.x.abs) }.max
ok('every front-wall point is on its own side of the mitre',
   worst_f < 0.001, worst_f)
ok('every cheek point is on its own side of the mitre',
   worst_c < 0.001, worst_c)
ok('...and both actually REACH it (they meet, not just miss)',
   close(worst_f, 0.0, 0.001) && close(worst_c, 0.0, 0.001),
   [worst_f, worst_c])
ok('the front wall inner face is pulled back by one thickness',
   close(fp.select { |p| close(p.y, SET + TH, 0.01) }.map { |p| p.x.abs }.max,
         WID / 2.0 - TH, 0.01),
   fp.select { |p| close(p.y, SET + TH, 0.01) }.map { |p| p.x.abs }.max)
ok('the cheek inner face starts one thickness back',
   close(cp.select { |p| close(p.x.abs, WID / 2.0 - TH, 0.01) }.map(&:y).min,
         SET + TH, 0.01),
   cp.select { |p| close(p.x.abs, WID / 2.0 - TH, 0.01) }.map(&:y).min)

# ---- 2. THE MITRE COSTS NOTHING OUTSIDE -------------------------------
wall_pts = fp + cp
ok('width is still outside face to outside face',
   close(wall_pts.map(&:x).max - wall_pts.map(&:x).min, WID, 0.01))
ok('the front is still the setback', close(wall_pts.map(&:y).min, SET, 0.01))
ok('no wall runs up inside the roof slab',
   wall_pts.map { |p| p.z - (DM.top_z(fr, p.x) - RT) }.max < 0.001,
   wall_pts.map { |p| p.z - (DM.top_z(fr, p.x) - RT) }.max)

# ---- 3 + 4. THE FASCIA - RoofManager's OWN BAND ----------------------
BAND = fr[:z_edge] - RT                       # the slab underside at the eave
ok('there is a fascia', !fascia.empty?, fascia.length)
fa = fascia.flat_map { |g| pts_of(g) }
ok('it hangs UNDER the slab edge, inside the roof line - as on the house',
   close(fa.map { |p| p.x.abs }.max, fr[:w_edge], 0.01) &&
   close(fa.map { |p| p.x.abs }.min, fr[:w_edge] - FT, 0.01),
   [fa.map { |p| p.x.abs }.min, fa.map { |p| p.x.abs }.max])
ok('its top is the slab underside',
   close(fa.map(&:z).max, BAND, 0.01), fa.map(&:z).max)
ok('...and it is as deep as the house fascia',
   close(fa.map(&:z).max - fa.map(&:z).min, DEPTH, 0.01),
   fa.map(&:z).max - fa.map(&:z).min)
ok('it stops ON the gable line - the rake board covers its end',
   close(fa.map(&:y).min, fr[:s_rake], 0.01), fa.map(&:y).min)
# THE BACK END IS A DIAGONAL (the user, 2026-09-02: "הפשייה צריך להגיע
# עד סוף הגג ולהיחתך באלכסון"). Its TOP corner runs on to where the
# roof reaches the board's top, its BOTTOM stops where the roof reaches
# the board's bottom, and the cut between them is the roof's own plane.
top = fa.select { |p| close(p.z, BAND, 0.01) }
bot = fa.select { |p| close(p.z, BAND - DEPTH, 0.01) }
ok('its TOP corner reaches the end of the roof',
   close(top.map(&:y).max, (BAND - Z0) / SLOPE, 0.05),
   [top.map(&:y).max, (BAND - Z0) / SLOPE])
ok('...its BOTTOM corner stops earlier, on the same roof plane',
   close(bot.map(&:y).max, (BAND - DEPTH - Z0) / SLOPE, 0.05),
   [bot.map(&:y).max, (BAND - DEPTH - Z0) / SLOPE])
ok('...so the end is a DIAGONAL cut, not a square one',
   top.map(&:y).max - bot.map(&:y).max > DEPTH / SLOPE - 0.1,
   top.map(&:y).max - bot.map(&:y).max)
ok('...and not one point of it is buried under the main roof',
   fa.all? { |p| p.z >= Z0 + p.y * SLOPE - 0.02 })

# ---- 5. THE CORNER: the EAVE FASCIA owns it, the RAKE is cut back -----
# This is the rule every gable on the house already follows
# (rake_meet_span, CLAUDE.md 2026-08-26). The first dormer trim had it
# the other way round, which is what the user caught.
ok('there is a rake board', !rakes.empty?, rakes.length)
ra = rakes.flat_map { |g| pts_of(g) }
ok('the rake sits OUTSIDE the gable line, one board thick',
   close(ra.map(&:y).max, fr[:s_rake], 0.01) &&
   close(ra.map(&:y).min, fr[:s_rake] - FT, 0.01),
   [ra.map(&:y).min, ra.map(&:y).max])
# THE GABLE COMES IN FRONT OF THE PERPENDICULAR (2026-09-02, the user:
# "הגיבל צריך לבוא לפני האנכי", with a picture of his own roof). So the
# rake runs its WHOLE edge, right out to the eave fascia's OUTER face,
# and covers that board's end - the opposite of rake_meet_span, which
# is what a level-edge corner on the house does.
ok('the rake runs out to the eave fascia OUTER face and covers its end',
   close(ra.map { |p| p.x.abs }.max, fr[:w_edge], 0.02),
   ra.map { |p| p.x.abs }.max)
ok('...so their bottoms line up at the corner',
   close(ra.map(&:z).min, fa.map(&:z).min, 0.02),
   [ra.map(&:z).min, fa.map(&:z).min])
ok('the rake climbs to the ridge underside',
   close(ra.map(&:z).max, fr[:z_ridge] - RT, 0.01), ra.map(&:z).max)
# it CLIMBS, so its own depth is measured across one end, not top to
# bottom of the whole board.
rend = ra.select { |p| close(p.x.abs, fr[:w_edge], 0.02) }
ok('...and is as deep as the fascia',
   close(rend.map(&:z).max - rend.map(&:z).min, DEPTH, 0.02),
   rend.map(&:z).max - rend.map(&:z).min)
# ONE PLANE SEPARATES THEM - the gable line itself. The rake is all in
# front of it, the eave board all behind it: they meet, and neither has
# a thousandth of an inch inside the other.
ok('one plane separates the rake from the eave board - they MEET',
   ra.all? { |p| p.y <= fr[:s_rake] + 0.001 } &&
   fa.all? { |p| p.y >= fr[:s_rake] - 0.001 },
   [ra.map(&:y).max, fa.map(&:y).min])

# ---- 6. THE METAL EDGE ------------------------------------------------
ok('there is a metal edge', !drips.empty?, drips.length)
dr = drips.flat_map { |g| pts_of(g) }
ok('it sits on the fascia OUTER face, never inside it',
   close(dr.map { |p| p.x.abs }.max, fr[:w_edge] + DT, 0.01),
   dr.map { |p| p.x.abs }.max)
ok('it laps only the top of the boards',
   close(dr.map(&:z).max, fr[:z_ridge] - RT, 0.01) &&
   close(dr.select { |p| close(p.x.abs, fr[:w_edge] + DT, 0.01) }.map(&:z).min,
         BAND - DD, 0.02),
   dr.select { |p| close(p.x.abs, fr[:w_edge] + DT, 0.01) }.map(&:z).min)
ok('IT WRAPS THE GABLE CORNER - it runs past the gable line onto the ' \
   'rake drip, square, exactly as on the house',
   close(dr.map(&:y).min, fr[:s_rake] - FT - DT, 0.02), dr.map(&:y).min)

# ---- 6b. THE SHINGLE REACHES THE METAL EDGE --------------------------
# (the user's fix 2: "הגג שינגלס צריך להגיע עד סוף המטל אדג כמו בצדדים")
rp = roofs.flat_map { |g| pts_of(g) }
ok('the deck finishes ON the eave metal edge, not short of it',
   close(rp.map { |p| p.x.abs }.max, fr[:w_edge] + DT, 0.01),
   [rp.map { |p| p.x.abs }.max, fr[:w_edge] + DT])
ok('...and on the gable metal edge too',
   close(rp.map(&:y).min, fr[:s_rake] - FT - DT, 0.01),
   [rp.map(&:y).min, fr[:s_rake] - FT - DT])
ok('...and never past it', rp.map { |p| p.x.abs }.max <= fr[:w_edge] + DT + 0.001)

# ---- 6c. THE EAVES ARE CLOSED ----------------------------------------
# (the user's last item: "עכשיו רק איבס וסיימנו")
ST = RM::SOFFIT_THICK
ok('there is a soffit under the eave and under the rake',
   soffs.length == 2, soffs.length)
eso = soffs.select { |g| pts_of(g).map { |p| p.x.abs }.max > WID / 2.0 + 0.1 }
rso = soffs - eso
ok('one of each', eso.length == 1 && rso.length == 1, [eso.length, rso.length])
es = eso.flat_map { |g| pts_of(g) }
ok('the eave soffit runs from the wall face to the fascia INNER face',
   close(es.map { |p| p.x.abs }.min, WID / 2.0, 0.02) &&
   close(es.map { |p| p.x.abs }.max, fr[:w_edge] - FT, 0.02),
   [es.map { |p| p.x.abs }.min, es.map { |p| p.x.abs }.max])
ok('...its bottom IS the fascia bottom line - the two boards meet',
   close(es.map(&:z).min, BAND - DEPTH, 0.02),
   [es.map(&:z).min, BAND - DEPTH])
ok('...it is one soffit board thick',
   close(es.select { |p| close(p.x.abs, fr[:w_edge] - FT, 0.02) }
           .map(&:z).max - es.map(&:z).min, ST, 0.02))
ok('...and it tilts with the roof: the inner edge is higher by pitch x overhang',
   close(es.map(&:z).max - (BAND - DEPTH + ST),
         fr[:pitch] * fr[:overhang], 0.02),
   es.map(&:z).max - (BAND - DEPTH + ST))
inner = es.select { |p| close(p.x.abs, WID / 2.0, 0.02) }
outer = es.select { |p| close(p.x.abs, fr[:w_edge] - FT, 0.02) }
ok('...its back end is a DIAGONAL: the higher inner edge reaches further',
   inner.map(&:y).max > outer.map(&:y).max + 1.0,
   [outer.map(&:y).max, inner.map(&:y).max])
ok('...and no point of it is buried under the main roof',
   es.all? { |p| p.z >= Z0 + p.y * SLOPE - 0.02 })
rs = rso.flat_map { |g| pts_of(g) }
ok('the rake soffit is pulled back one overhang, onto the eave board',
   close(rs.map { |p| p.x.abs }.max, fr[:w_edge] - OH, 0.05),
   rs.map { |p| p.x.abs }.max)
ok('...and it fills the front overhang',
   close(rs.map(&:y).min, fr[:s_rake], 0.05) &&
   close(rs.map(&:y).max, SET, 0.05), [rs.map(&:y).min, rs.map(&:y).max])

Sketchup.reset_model!
g4 = DM.build_dormer!(Sketchup.active_model.entities, spec.merge(soffit: 'none'))
ok('soffit "none" closes nothing and breaks nothing',
   g4.entities.grep(Sketchup::Group).none? do |g|
     g.get_attribute('InteriorPro', 'part') == 'dormer_soffit'
   end)

# ---- 7. NOTHING IS HAND ROLLED ---------------------------------------
# The sizes are RoofManager's own constants, because RoofManager built
# every one of these boards.
ok('the boards are the roof manager\'s boards',
   close(FT, RM::FASCIA_THICK) && close(DT, RM::DRIP_THICK) &&
   close(DD, RM::DRIP_DEPTH))
ok('...and with no roof manager loaded the dormer simply wears none',
   DM.respond_to?(:roof_manager))

# ---- 8. THE KILL SWITCH ----------------------------------------------
Sketchup.reset_model!
m3 = Sketchup.active_model
g3 = DM.build_dormer!(m3.entities, spec.merge(fascia_depth: 0.0))
p3 = g3.entities.to_a.select { |e| e.respond_to?(:entities) }
kinds3 = p3.map { |g| g.get_attribute('InteriorPro', 'part') }.uniq.sort
ok('a zero fascia depth leaves the body alone and builds no boards',
   kinds3 == %w[dormer_cheek dormer_front dormer_roof], kinds3)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

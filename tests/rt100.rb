# encoding: utf-8
# rt100 - THE SHED GABLET (2026-09-02, style 2 of 4).
#
# WHY
# The user asked for every roof type on the dormer - "פיצ גייבל שטוח
# וSHED" - and agreed the order: gable first, then shed, then flat, then
# hip. This is shed.
#
# THE CLAIMS PINNED HERE
# 1. THE LAW DOES NOT CHANGE. The gablet still dies into the roof at the
#    end of its own length, so the front wall height is still a RESULT:
#       height = length * (roof slope - gablet pitch)
#    and that is why the pitch must be FLATTER than the roof. Equal or
#    steeper is refused, with a reason, not built into a sliver.
# 2. ONE PLANE, and its back edge is a straight line across the whole
#    width - both planes fall along s alone, so they cross at one s.
# 3. THE EDGES SWAP ROLES and every board follows: the FRONT is the level
#    eave (fascia across it, nothing to cut - it never meets the roof),
#    the two SIDES are rakes (they climb, and stop where the roof rises
#    into them), the BACK is buried and gets no boards at all.
# 4. THE RAKE COMES IN FRONT OF THE PERPENDICULAR - the rule he set on
#    the gable, kept here: the side boards cover the front fascia's ends.
# 5. BOARDS MEET. Front corners mitred on the 45 degree plane, every wall
#    stopping on the deck's underside, nothing buried in the roof.
# 6. THE GABLE IS UNTOUCHED - same spec with style gable still builds the
#    gable, corner for corner.
#
# Against yesterday's code every claim fails: style was ignored and a
# shed spec built a gable.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
# 2026-09-13B: this suite pins the RAW gablet formulas, so the 6" the roof
# now rides above the window is switched off here - exactly the way the
# raised heel is kept out of these same formulas. rt148 pins the headroom.
InteriorPro::DormerManager.send(:remove_const, :USE_DORMER_HEADROOM)
InteriorPro::DormerManager.const_set(:USE_DORMER_HEADROOM, false)


# THE GABLET HEEL IS OFF IN HERE (2026-09-06). Every number in this suite
# was measured when the gablet's roof sat straight on its walls and its
# eave tail hung overhang x pitch below them. He asked for the same raised
# heel the house roof got, and chose that it ADDS to the typed height -
# "העקב נוסף למספר" - so a typed 33 now comes out 35.5 and the overhang
# does move z_eave. That is the new rule, pinned by rt119; this suite is
# about something else, so here the heel stays off.
module InteriorPro
  module DormerManager
    def self.dormer_heel(_overhang, _style, _pitch, _slope, _spec)
      0.0
    end
  end
end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

DM = InteriorPro::DormerManager
RM = InteriorPro::RoofManager
FT = RM::FASCIA_THICK
DT = RM::DRIP_THICK

Z0    = 100.0
SLOPE = 8.0 / 12.0
SET   = 36.0
WID   = 48.0
LEN   = 96.0
RT    = 0.5
TH    = 5.0
OH    = 6.0
DEPTH = 8.0

spec = { z0: Z0, slope: SLOPE, setback: SET, width: WID, length: LEN,
         thickness: TH, roof_thickness: RT, overhang: OH, fascia_depth: DEPTH,
         soffit: 'wood', soffit_slope: true, style: 'shed',
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0] }
fr = DM.frame(spec)
ok('the frame is computed', !fr.nil?)
ok('it knows it is a shed', fr[:style] == 'shed', fr[:style])

# ---- 1. THE LAW DOES NOT CHANGE --------------------------------------
ok('with no pitch typed it takes half the roof, so it is always flatter',
   close(fr[:pitch], SLOPE / 2.0), fr[:pitch])
ok('the front wall height is length x (slope - pitch)',
   close(fr[:height], LEN * (SLOPE - fr[:pitch])), fr[:height])
ok('...and the deck really does reach the roof at the end of the length',
   close(DM.deck_z(fr, fr[:s_ridge], 0.0), Z0 + fr[:s_ridge] * SLOPE, 0.001),
   DM.deck_z(fr, fr[:s_ridge], 0.0))
ok('a pitch equal to the roof is refused',
   DM.frame(spec.merge(pitch: SLOPE)).nil?)
ok('a pitch steeper than the roof is refused',
   DM.frame(spec.merge(pitch: SLOPE * 1.5)).nil?)
ok('a flatter pitch is fine, and makes the wall taller',
   DM.frame(spec.merge(pitch: SLOPE / 4.0))[:height] > fr[:height])

Sketchup.reset_model!
m = Sketchup.active_model
grp = DM.build_dormer!(m.entities, spec)
ok('the shed builds', !grp.nil?)
parts = grp.entities.to_a.select { |e| e.respond_to?(:entities) }
kind = lambda { |k| parts.select { |g| g.get_attribute('InteriorPro', 'part') == k } }
def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map(&:position) }
end
front = kind.call('dormer_front')
cheeks = kind.call('dormer_cheek')
roofs = kind.call('dormer_roof')
fascia = kind.call('dormer_fascia')
rakes = kind.call('dormer_rake')
soffs = kind.call('dormer_soffit')

# ---- 2. ONE PLANE ----------------------------------------------------
ok('there is exactly ONE roof plane', roofs.length == 1, roofs.length)
rp = roofs.flat_map { |g| pts_of(g) }
back = rp.select { |p| close(p.y, fr[:s_ridge], 0.01) }
ok('its back edge is a straight line right across the width',
   back.map { |p| p.x.abs.round(2) }.uniq.length == 1 &&
   close(back.map { |p| p.x.abs }.max, fr[:w_deck], 0.02),
   back.map { |p| p.x.round(2) }.uniq)
ok('...and its TOP surface sits ON the main roof there',
   back.map(&:z).max > 0 &&
   close(back.map(&:z).max, Z0 + fr[:s_ridge] * SLOPE, 0.02),
   back.map(&:z).max)

# ---- 3. THE EDGES SWAP ROLES -----------------------------------------
fa = fascia.flat_map { |g| pts_of(g) }
ok('the fascia is ACROSS THE FRONT, one board thick', fascia.length == 1 &&
   close(fa.map(&:y).min, fr[:s_rake], 0.01) &&
   close(fa.map(&:y).max, fr[:s_rake] + FT, 0.01),
   [fa.map(&:y).min, fa.map(&:y).max])
ok('...level, because the front edge is level',
   close(fa.map(&:z).max, fr[:z_edge] - RT, 0.01) &&
   close(fa.map(&:z).max - fa.map(&:z).min, DEPTH, 0.01),
   [fa.map(&:z).max, fa.map(&:z).min])
ok('...and it needs no cut at all - it never meets the main roof',
   fa.all? { |p| p.z > Z0 + p.y * SLOPE + 0.01 })
# SQUARE AT BOTH CORNERS, not mitred: the soffit under it runs square
# out to the rake line, so a 45 degree fascia left a triangle of open
# sky between the two (2026-09-02: "פשיה אחד הוא אלכסון ואחד הוא
# מרובע - תסתום את הפינה").
ok('the front fascia ends SQUARE on the rake line, at BOTH its faces',
   close(fa.select { |p| close(p.y, fr[:s_rake], 0.01) }.map { |p| p.x.abs }.max,
         fr[:w_edge], 0.01) &&
   close(fa.select { |p| close(p.y, fr[:s_rake] + FT, 0.01) }.map { |p| p.x.abs }.max,
         fr[:w_edge], 0.01),
   [fa.select { |p| close(p.y, fr[:s_rake], 0.01) }.map { |p| p.x.abs }.max,
    fa.select { |p| close(p.y, fr[:s_rake] + FT, 0.01) }.map { |p| p.x.abs }.max])
ra = rakes.flat_map { |g| pts_of(g) }
ok('the rakes run down the two SIDES', !ra.empty? &&
   close(ra.map { |p| p.x.abs }.max, fr[:w_edge] + FT, 0.02),
   ra.map { |p| p.x.abs }.max)
ok('...climbing with the deck',
   ra.map(&:z).max > ra.map(&:z).min + DEPTH + 1.0,
   [ra.map(&:z).min, ra.map(&:z).max])
ok('...and stopping before the roof buries them',
   ra.map(&:y).max < fr[:s_ridge] - 0.5 &&
   ra.all? { |p| p.z >= Z0 + p.y * SLOPE - 0.05 },
   ra.map(&:y).max)
ok('the buried back edge gets no boards at all',
   (fa + ra).none? { |p| close(p.y, fr[:s_ridge], 0.01) })

# ---- 4. THE RAKE COMES IN FRONT --------------------------------------
ok('the rake is outboard of the fascia line, so it covers its end',
   ra.map { |p| p.x.abs }.max > fa.map { |p| p.x.abs }.max + 0.1,
   [ra.map { |p| p.x.abs }.max, fa.map { |p| p.x.abs }.max])
ok('...and reaches the front edge to do it',
   close(ra.map(&:y).min, fr[:s_rake], 0.02), ra.map(&:y).min)

# ---- 4b. THE METAL EDGE WRAPS THE CORNER -----------------------------
# The house's rule since 2026-08-26, and the user caught the shed
# without it: "לא חיברת את המטל בפינה כמו שצריך". The FRONT metal runs
# SQUARE past both corners, out onto the side metal's own outer face,
# instead of stopping short of it in a mitre.
drips = kind.call('dormer_drip')
dr = drips.flat_map { |g| pts_of(g) }
front_drip = dr.select { |p| p.y < fr[:s_rake] + 0.01 }
side_drip  = dr.select { |p| p.y > fr[:s_rake] + 1.0 }
ok('there is metal on the front and on both sides',
   !front_drip.empty? && !side_drip.empty?)
ok('the side metal sits on the rake board outer face',
   close(side_drip.map { |p| p.x.abs }.min, fr[:w_edge] + FT, 0.01) &&
   close(side_drip.map { |p| p.x.abs }.max, fr[:w_edge] + FT + DT, 0.01),
   [side_drip.map { |p| p.x.abs }.min, side_drip.map { |p| p.x.abs }.max])
ok('THE FRONT METAL WRAPS right out onto it - no notch at the corner',
   close(front_drip.map { |p| p.x.abs }.max, fr[:w_edge] + FT + DT, 0.01),
   [front_drip.map { |p| p.x.abs }.max, fr[:w_edge] + FT + DT])

# ---- 4c. THE SOFFIT CORNER -------------------------------------------
# The FRONT board owns the corner square and the side board is pulled
# back one overhang onto its inner edge, so they meet instead of both
# building into the same block (the bite he circled from underneath).
so = soffs.flat_map { |g| pts_of(g) }
side_sof = so.select { |p| p.y > SET + 1.0 }
ok('the side soffit reaches the rake line - no slot beside the board',
   close(side_sof.map { |p| p.x.abs }.max, fr[:w_edge], 0.02),
   [side_sof.map { |p| p.x.abs }.max, fr[:w_edge]])
ok('...and comes in to the cheek face',
   close(side_sof.map { |p| p.x.abs }.min, WID / 2.0, 0.02),
   side_sof.map { |p| p.x.abs }.min)
# the cheek face is the side board's own inner edge, and it starts on
# the wall line - which is exactly where the front board ends. They MEET.
cheek_edge = so.select { |p| close(p.x.abs, WID / 2.0, 0.02) }
ok('...and starts at the wall line, not out at the eave line',
   close(cheek_edge.map(&:y).min, SET, 0.05), cheek_edge.map(&:y).min)
ok('...which is exactly where the front board ends - they MEET',
   close(so.select { |p| p.y < SET + 0.01 }.map(&:y).max, SET, 0.05),
   so.select { |p| p.y < SET + 0.01 }.map(&:y).max)

# ---- 5. BOARDS MEET --------------------------------------------------
fp = front.flat_map { |g| pts_of(g) }
cp = cheeks.flat_map { |g| pts_of(g) }
MIT = SET + WID / 2.0
ok('every front-wall point is on its own side of the mitre',
   fp.map { |p| (p.y + p.x.abs) - MIT }.max < 0.001,
   fp.map { |p| (p.y + p.x.abs) - MIT }.max)
ok('every cheek point is on its own side of it',
   cp.map { |p| MIT - (p.y + p.x.abs) }.max < 0.001,
   cp.map { |p| MIT - (p.y + p.x.abs) }.max)
walls = fp + cp
ok('no wall runs up inside the deck',
   walls.map { |p| p.z - (DM.deck_z(fr, p.y, p.x) - RT) }.max < 0.001,
   walls.map { |p| p.z - (DM.deck_z(fr, p.y, p.x) - RT) }.max)
ok('...and the front wall top IS the deck underside, not level',
   close(fp.map(&:z).max, DM.deck_z(fr, SET + TH, 0.0) - RT, 0.01) &&
   fp.map(&:z).max > DM.deck_z(fr, SET, 0.0) - RT + 0.5,
   fp.map(&:z).max)
ok('the cheek ends where the deck underside meets the roof',
   close(cp.map(&:y).max, fr[:s_cheek], 0.05), cp.map(&:y).max)
# ...measured on the OUTSIDE faces. The inner faces deliberately reach
# down past the roof plane, into the hole the dormer cuts, so there is no
# slot of daylight where the wall meets the deck it stands on.
outside = fp.select { |p| close(p.y, SET, 0.01) } +
          cp.select { |p| close(p.x.abs, WID / 2.0, 0.01) }
ok('no OUTSIDE wall face is buried under the main roof',
   outside.all? { |p| p.z >= Z0 + p.y * SLOPE - 0.02 },
   outside.reject { |p| p.z >= Z0 + p.y * SLOPE - 0.02 }.first(2)
          .map { |p| [p.y.round(1), p.z.round(1)] })
ok('the eaves are closed', !soffs.empty?, soffs.length)

# ---- 6. THE GABLE IS UNTOUCHED ---------------------------------------
gfr = DM.frame(spec.merge(style: 'gable'))
ok('a gable spec still builds a gable', gfr[:style] == 'gable', gfr[:style])
ok('...with its own eave height, not the shed one',
   close(gfr[:z_eave], gfr[:z_ridge] - (WID / 2.0) * gfr[:pitch]), gfr[:z_eave])
ok('...and its hole is still the five-corner one',
   DM.opening_plan(gfr).length == 5, DM.opening_plan(gfr).length)
# the OUTER face of the walls now - see rt95
ok('the shed hole is a plain rectangle back to the die-in',
   DM.opening_plan(fr) == [[SET, -(WID / 2.0)], [SET, WID / 2.0],
                           [fr[:s_ridge], WID / 2.0], [fr[:s_ridge], -(WID / 2.0)]],
   DM.opening_plan(fr))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

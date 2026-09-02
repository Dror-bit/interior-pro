# encoding: utf-8
# rt102 - THE HIP GABLET (2026-09-02, style 4 of 4 - the last one).
#
# THE CLAIMS PINNED HERE
# 1. THREE PLANES AT ONE PITCH: a triangle over the front, a quad down
#    each side, and they meet on two 45 degree hips - which is what one
#    pitch on all three means.
# 2. THE RIDGE STARTS ONE HALF WIDTH BACK from the front eave and runs
#    to the same die-in point every other style uses. Too wide for its
#    length and there is no ridge left to start: refused, with the
#    number of inches it is short.
# 3. THE LAW DOES NOT CHANGE: the front wall height is still what the
#    width, the length and the pitch produce.
# 4. EVERY OPEN EDGE IS A LEVEL EAVE at one height - no rake anywhere.
# 5. THE CORNERS ARE MITRED and the seams CLOSE: the front band's corner
#    and the side board's 45 are the same line, at both faces. The side
#    boards are still cut on the roof at the back.
# 6. BOARDS MEET, and nothing is buried in the main roof.
#
# Against yesterday's code every claim fails - style 'hip' built a gable.
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
         soffit: 'wood', soffit_slope: true, style: 'hip',
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0] }
fr = DM.frame(spec)
ok('the frame is computed', !fr.nil?)
ok('it knows it is a hip', fr[:style] == 'hip', fr[:style])

# ---- 2 + 3. THE RIDGE, AND THE LAW -----------------------------------
ok('the ridge starts one half width back from the front eave',
   close(fr[:s_hip], fr[:s_rake] + fr[:w_edge]), fr[:s_hip])
ok('...and dies at the same point every style dies at',
   close(fr[:s_ridge], SET + LEN))
ok('the front wall height is the gable formula, unchanged',
   close(fr[:height], LEN * SLOPE - (WID / 2.0) * fr[:pitch]), fr[:height])
# wide AND flat: the wall is still tall enough, so the only thing that
# can stop it is the hip guard itself.
ok('too wide for its length is refused, not squeezed',
   DM.frame(spec.merge(width: 200.0, pitch: 2.0 / 12.0)).nil?)
ok('...with a reason that says how much more length it needs',
   DM.last_reason.to_s.include?('more length'), DM.last_reason)
fh = DM.frame(spec.merge(height: 30.0))
ok('a typed height still comes back as that height',
   close(fh[:height], 30.0, 0.01), fh && fh[:height])

# ---- 1. THREE PLANES, MEETING ON 45s ---------------------------------
planes = DM.hip_planes(fr)
ok('there are three plans: a front triangle and two side quads',
   planes.length == 3 && planes[0].length == 3 &&
   planes[1].length == 4 && planes[2].length == 4,
   planes.map(&:length))
apex = planes[0].last
ok('the front triangle points at the hip, on the centre line',
   close(apex[1], 0.0) && close(apex[0], fr[:s_deck] + fr[:w_deck], 0.05), apex)
# one pitch everywhere: the surface over the hip line agrees from both sides
mid_s = (fr[:s_deck] + apex[0]) / 2.0
mid_w = fr[:w_deck] - (mid_s - fr[:s_deck])
ok('the two planes agree along the hip line - one surface, not a step',
   close(DM.deck_z(fr, mid_s, mid_w), DM.deck_z(fr, mid_s, mid_w - 0.001), 0.01) &&
   close(DM.deck_z(fr, mid_s, mid_w),
         fr[:z_edge] + (fr[:w_edge] - mid_w) * fr[:pitch], 0.01),
   DM.deck_z(fr, mid_s, mid_w))
ok('the ridge height is the same one the gable reaches',
   close(DM.deck_z(fr, fr[:s_ridge], 0.0), fr[:z_ridge], 0.01),
   DM.deck_z(fr, fr[:s_ridge], 0.0))

Sketchup.reset_model!
m = Sketchup.active_model
grp = DM.build_dormer!(m.entities, spec)
ok('the hip builds', !grp.nil?)
parts = grp.entities.to_a.select { |e| e.respond_to?(:entities) }
kind = lambda { |k| parts.select { |g| g.get_attribute('InteriorPro', 'part') == k } }
def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map(&:position) }
end
roofs = kind.call('dormer_roof')
fascia = kind.call('dormer_fascia')
soffs = kind.call('dormer_soffit')
drips = kind.call('dormer_drip')
walls = (kind.call('dormer_front') + kind.call('dormer_cheek')).flat_map { |g| pts_of(g) }
ok('three roof planes are built', roofs.length == 3, roofs.length)
ok('there is no rake board anywhere on a hip',
   kind.call('dormer_rake').empty?, kind.call('dormer_rake').length)

# ---- 4. EVERY OPEN EDGE IS A LEVEL EAVE ------------------------------
fa = fascia.flat_map { |g| pts_of(g) }
BAND = fr[:z_edge] - RT
ok('all the fascia hangs from ONE level line', close(fa.map(&:z).max, BAND, 0.01),
   fa.map(&:z).max)
ok('...and is one depth deep all round',
   close(fa.map(&:z).max - fa.map(&:z).min, DEPTH, 0.01),
   fa.map(&:z).max - fa.map(&:z).min)
front_fa = fa.select { |p| p.y < fr[:s_rake] + FT + 0.01 }
side_fa = fa.select { |p| p.x.abs > WID / 2.0 }
ok('the front band sits inside the front line',
   close(front_fa.map(&:y).min, fr[:s_rake], 0.01), front_fa.map(&:y).min)
ok('the side boards sit inside the side line',
   close(side_fa.map { |p| p.x.abs }.max, fr[:w_edge], 0.01) &&
   close(side_fa.map { |p| p.x.abs }.min, fr[:w_edge] - FT, 0.01),
   [side_fa.map { |p| p.x.abs }.min, side_fa.map { |p| p.x.abs }.max])

# ---- 5. THE MITRE CLOSES ---------------------------------------------
# the outer face starts at the corner, the inner face one thickness in -
# the same 45 the band's own corner cuts.
outer_start = fa.select { |p| close(p.x.abs, fr[:w_edge], 0.01) }.map(&:y).min
inner_start = fa.select { |p| close(p.x.abs, fr[:w_edge] - FT, 0.01) }.map(&:y).min
ok('the side board is mitred 45 at the front corner',
   close(outer_start, fr[:s_rake], 0.01) &&
   close(inner_start, fr[:s_rake] + FT, 0.01),
   [outer_start, inner_start])
ok('...and cut on the roof at the back, top corner reaching further',
   close(fa.select { |p| close(p.z, BAND, 0.01) }.map(&:y).max,
         (BAND - Z0) / SLOPE, 0.05) &&
   close(fa.select { |p| close(p.z, BAND - DEPTH, 0.01) }.map(&:y).max,
         (BAND - DEPTH - Z0) / SLOPE, 0.05),
   [fa.select { |p| close(p.z, BAND, 0.01) }.map(&:y).max,
    fa.select { |p| close(p.z, BAND - DEPTH, 0.01) }.map(&:y).max])
dr = drips.flat_map { |g| pts_of(g) }
ok('the metal edge is outside the fascia face, all round',
   close(dr.map { |p| p.x.abs }.max, fr[:w_edge] + DT, 0.01),
   dr.map { |p| p.x.abs }.max)

# ---- 6. BOARDS MEET, NOTHING BURIED ----------------------------------
ok('every wall stops on the deck underside',
   walls.map { |p| p.z - (DM.deck_z(fr, p.y, p.x) - RT) }.max < 0.001,
   walls.map { |p| p.z - (DM.deck_z(fr, p.y, p.x) - RT) }.max)
MIT = SET + WID / 2.0
fp = kind.call('dormer_front').flat_map { |g| pts_of(g) }
cp = kind.call('dormer_cheek').flat_map { |g| pts_of(g) }
ok('the front corners are still mitred on the 45 degree plane',
   fp.map { |p| (p.y + p.x.abs) - MIT }.max < 0.001 &&
   cp.map { |p| MIT - (p.y + p.x.abs) }.max < 0.001,
   [fp.map { |p| (p.y + p.x.abs) - MIT }.max,
    cp.map { |p| MIT - (p.y + p.x.abs) }.max])
ok('no board is buried under the main roof',
   (fa + dr + soffs.flat_map { |g| pts_of(g) })
     .all? { |p| p.z >= Z0 + p.y * SLOPE - 0.02 })
ok('the eaves are closed all round', !soffs.empty?, soffs.length)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

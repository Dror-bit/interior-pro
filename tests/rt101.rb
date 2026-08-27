# encoding: utf-8
# rt101 - THE FLAT GABLET (2026-09-02, style 3 of 4).
#
# WHY
# Third of the four the user asked for. The point of this suite is that
# flat is NOT a fourth builder: a flat gablet is the shed with its pitch
# zeroed, and every line of the shed's maths holds at zero. If someone
# later gives flat its own code path, these claims are what should stop
# them.
#
# THE CLAIMS PINNED HERE
# 1. THE DECK IS LEVEL - one height, front to back, side to side.
# 2. THE LAW STILL HOLDS: it dies into the roof at the end of its own
#    length, so height = length x the ROOF's pitch, and a typed height
#    gives back that same height.
# 3. IT IS THE SHED, ZEROED. Same one plane, same straight back edge,
#    same hole, same walls - every number the shed produces at pitch 0.
# 4. THE BOARDS ARE STILL CUT ON THE ROOF at the back, and the corners
#    are still closed square.
# 5. NO PITCH IS A REAL ANSWER, not a refusal - the shed's "must be
#    flatter than the roof" rule must not fire on it.
#
# Against yesterday's code every claim fails - style 'flat' built a gable.
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
         soffit: 'wood', soffit_slope: true, style: 'flat',
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0] }
fr = DM.frame(spec)
ok('the frame is computed', !fr.nil?)
ok('it knows it is flat', fr[:style] == 'flat', fr[:style])

# ---- 5. NO PITCH IS AN ANSWER ----------------------------------------
ok('a flat gablet has no pitch, and that is not a refusal',
   close(fr[:pitch], 0.0), fr[:pitch])
ok('...even when a pitch is handed to it, flat means flat',
   close(DM.frame(spec.merge(pitch: SLOPE / 2.0))[:pitch], 0.0))

# ---- 1 + 2. LEVEL, AND THE LAW HOLDS ---------------------------------
ok('the deck is one height from front to back',
   close(DM.deck_z(fr, fr[:s_rake], 0.0), DM.deck_z(fr, fr[:s_ridge], 0.0)),
   [DM.deck_z(fr, fr[:s_rake], 0.0), DM.deck_z(fr, fr[:s_ridge], 0.0)])
ok('...and side to side',
   close(DM.deck_z(fr, fr[:s_ridge], 0.0), DM.deck_z(fr, fr[:s_ridge], fr[:w_edge])))
ok('the deck sits exactly where the roof has climbed to it',
   close(DM.deck_z(fr, fr[:s_ridge], 0.0), Z0 + fr[:s_ridge] * SLOPE, 0.001))
ok('height is length x the ROOF pitch', close(fr[:height], LEN * SLOPE), fr[:height])
fh = DM.frame(spec.merge(height: 40.0))
ok('a typed height comes back as that height', close(fh[:height], 40.0, 0.01),
   fh && fh[:height])
ok('...off the roof pitch alone', close(fh[:length], 40.0 / SLOPE, 0.01),
   fh[:length])

# ---- 3. IT IS THE SHED, ZEROED ---------------------------------------
shed0 = DM.frame(spec.merge(style: 'shed', pitch: 0.0001))
%i[s_rake s_ridge w_edge w_deck s_deck].each do |k|
  ok("flat matches a shed at zero pitch: #{k}", close(fr[k], shed0[k], 0.05),
     [fr[k], shed0[k]])
end
ok('the hole is the shed rectangle, on the walls OUTER face',
   DM.opening_plan(fr) == [[SET, -(WID / 2.0)], [SET, WID / 2.0],
                           [fr[:s_ridge], WID / 2.0],
                           [fr[:s_ridge], -(WID / 2.0)]],
   DM.opening_plan(fr))

Sketchup.reset_model!
m = Sketchup.active_model
grp = DM.build_dormer!(m.entities, spec)
ok('the flat gablet builds', !grp.nil?)
parts = grp.entities.to_a.select { |e| e.respond_to?(:entities) }
kind = lambda { |k| parts.select { |g| g.get_attribute('InteriorPro', 'part') == k } }
def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map(&:position) }
end
roofs = kind.call('dormer_roof')
fascia = kind.call('dormer_fascia')
rakes = kind.call('dormer_rake')
soffs = kind.call('dormer_soffit')
walls = (kind.call('dormer_front') + kind.call('dormer_cheek')).flat_map { |g| pts_of(g) }

ok('one roof plane', roofs.length == 1, roofs.length)
rp = roofs.flat_map { |g| pts_of(g) }
ok('...and it really is level - two heights only, top and underside',
   rp.map { |p| p.z.round(3) }.uniq.length == 2,
   rp.map { |p| p.z.round(3) }.uniq)
ok('every wall stops on the deck underside',
   walls.map { |p| p.z - (DM.deck_z(fr, p.y, p.x) - RT) }.max < 0.001,
   walls.map { |p| p.z - (DM.deck_z(fr, p.y, p.x) - RT) }.max)

# ---- 4. THE BOARDS ---------------------------------------------------
fa = fascia.flat_map { |g| pts_of(g) }
ok('the front fascia is level and never meets the roof',
   close(fa.map(&:z).max, fr[:z_edge] - RT, 0.01) &&
   fa.all? { |p| p.z > Z0 + p.y * SLOPE + 0.01 },
   fa.map(&:z).max)
ok('...and ends SQUARE on the side line at both its faces',
   close(fa.select { |p| close(p.y, fr[:s_rake], 0.01) }.map { |p| p.x.abs }.max,
         fr[:w_edge], 0.01) &&
   close(fa.select { |p| close(p.y, fr[:s_rake] + FT, 0.01) }.map { |p| p.x.abs }.max,
         fr[:w_edge], 0.01))
ra = rakes.flat_map { |g| pts_of(g) }
ok('the side boards are level too', ra.map { |p| p.z.round(3) }.uniq.length == 2,
   ra.map { |p| p.z.round(3) }.uniq)
ok('...and are CUT ON THE ROOF at the back, top corner reaching further',
   close(ra.select { |p| close(p.z, fr[:z_edge] - RT, 0.01) }.map(&:y).max,
         (fr[:z_edge] - RT - Z0) / SLOPE, 0.05) &&
   close(ra.select { |p| close(p.z, fr[:z_edge] - RT - DEPTH, 0.01) }.map(&:y).max,
         (fr[:z_edge] - RT - DEPTH - Z0) / SLOPE, 0.05),
   [ra.select { |p| close(p.z, fr[:z_edge] - RT, 0.01) }.map(&:y).max,
    ra.select { |p| close(p.z, fr[:z_edge] - RT - DEPTH, 0.01) }.map(&:y).max])
ok('nothing of any board is buried under the main roof',
   (fa + ra + soffs.flat_map { |g| pts_of(g) })
     .all? { |p| p.z >= Z0 + p.y * SLOPE - 0.02 })
so = soffs.flat_map { |g| pts_of(g) }
side_sof = so.select { |p| p.y > SET + 1.0 }
ok('the side soffit reaches the side line and comes in to the cheek',
   close(side_sof.map { |p| p.x.abs }.max, fr[:w_edge], 0.02) &&
   close(side_sof.map { |p| p.x.abs }.min, WID / 2.0, 0.02),
   [side_sof.map { |p| p.x.abs }.min, side_sof.map { |p| p.x.abs }.max])
dr = kind.call('dormer_drip').flat_map { |g| pts_of(g) }
ok('the metal edge wraps the front corners onto the side metal',
   close(dr.select { |p| p.y < fr[:s_rake] + 0.01 }.map { |p| p.x.abs }.max,
         fr[:w_edge] + FT + DT, 0.01),
   dr.select { |p| p.y < fr[:s_rake] + 0.01 }.map { |p| p.x.abs }.max)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

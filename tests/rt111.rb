# encoding: utf-8
# rt111 - NO RIB STUB IN THE DORMER'S BACK CORNER (2026-09-05).
#
# He circled a loose tab on the dormer: "הבעיה לא היתה בקאפ אלא באחד
# הפאנלים בסוף הגג". Measured in his own model, inside the dormer group:
# five ribs 26.87" long on each slope and ONE 4.00" long, alone in the
# corner where the dormer closes into the main roof.
#
# THE CAUSE, not the number: a dormer slope is a trapezoid that narrows to
# nothing at the back, so the last seam line before the valley crosses only
# a sliver. RoofTilePlace already refuses a sliver - min_run_len, "half a
# pipe poking out of a corner looks worse than a bare stretch of texture" -
# but its 3" was set for the clay tile's short courses on a house roof.
#
# THE CLAIMS PINNED HERE
# 1. The stub is real: laid with the default minimum, a dormer slope gets a
#    run far shorter than the rest.
# 2. stub_len asks the CAP how long a run has to be, and is never below the
#    placer's own floor.
# 3. With it, that run is gone and every run left is a full one.
# 4. Nothing else is thrown away: the full-length runs all survive.
# 5. The house roof is untouched - the number is handed to the dormer only.
#
# Against the old code claims 2-4 fail: stub_len does not exist and the
# dormer is laid with the 3" floor, stub and all.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
RM = InteriorPro::RoofManager
PLACE = InteriorPro::RoofTilePlace

Z0    = 100.0
SLOPE = 5.0 / 12.0
# 130" on purpose: where the last seam line falls relative to the back
# corner depends on the dormer's own length, and this one drops it right in
# the sliver - a 5" run beside 28.69" ones, the stub in miniature.
SPEC  = { z0: Z0, slope: SLOPE, setback: 50.0, width: 50.0, length: 130.0,
          thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
          style: 'gable', base: [0.0, 0.0], along: [1.0, 0.0],
          into: [0.0, 1.0] }.freeze

Sketchup.reset_model!
model = Sketchup.active_model
roof = model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
roof.set_attribute('InteriorPro', 'roof_material', 'seam')
at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
roof.entities.add_face([at.call(-400, 0), at.call(400, 0),
                        at.call(400, 400), at.call(-400, 400)])

d = DM.add_dormer!(roof.entities, SPEC.merge(no_tiles: true))
ok('a bare dormer was built', !d.nil?)

subs = d.entities.grep(Sketchup::Group).select do |s|
  s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
end
ok('two slopes', subs.length == 2, subs.length)

planes = subs.map { |s| PLACE.planes_from_faces([DM.top_skin(s)]).first }.compact
ok('two planes to lay on', planes.length == 2, planes.length)

# ---- 1. the stub is real with the placer's own floor ------------------
loose = PLACE.run_slots(planes, 'seam', min_len: PLACE.min_run_len)
lens  = loose.map { |s| s[:length].to_f }.sort
ok('with the 3" floor a dormer slope grows a stub',
   lens.first < 10.0 && lens.last > 20.0, [lens.first, lens.last])

# ---- 2. stub_len asks the cap, and never goes below the floor ---------
sl = DM.respond_to?(:stub_len) ? DM.stub_len('seam') : nil
ok('stub_len exists', !sl.nil?)
ok('stub_len is the ridge cap width', sl == RM.cap_width_for('seam').to_f, sl)
ok('and never below the placer\'s own floor',
   !sl.nil? && sl >= PLACE.min_run_len, sl)

# ---- 3 + 4. the stub goes, the real runs stay ------------------------
tight = PLACE.run_slots(planes, 'seam', min_len: sl.to_f)
tlens = tight.map { |s| s[:length].to_f }
ok('no run shorter than the cap is left',
   !sl.nil? && tlens.all? { |l| l >= sl - 1.0e-6 }, tlens.sort.first(3))
full = lens.select { |l| l >= sl.to_f }
ok('every full-length run survives', tlens.length == full.length,
   [tlens.length, full.length])
ok('and exactly the stubs were dropped',
   loose.length - tight.length == lens.count { |l| l < sl.to_f },
   [loose.length, tight.length])

# ---- 4b. END TO END: the dormer as it is actually built ---------------
# The claim that matters in his model - not what run_slots would say if it
# were asked nicely, but what add_dormer! leaves standing.
built = DM.add_dormer!(roof.entities, SPEC)
bsubs = built.entities.grep(Sketchup::Group).select do |s|
  s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
end
ribs = bsubs.map { |s| s.entities.grep(Sketchup::ComponentInstance).length }
ok('the built dormer carries only the full runs',
   ribs.inject(0, :+) == tight.length, [ribs, tight.length, loose.length])
ok('and that is fewer than the bare floor would have left',
   tight.length < loose.length, [tight.length, loose.length])

# ---- 4c. THE EAVE BAR NEVER PASSES THE METAL EDGE (2026-09-05).
# "הוא יוצא החוצה הוא מעבר למטל אדג". The deck runs a little past the
# boards under it, and at the valley corner the bar rode that little out
# over the main roof - 1.56" of it in his model, with nothing underneath.
# The bar is cut on the metal edge now, and the edge is MEASURED, not
# assumed: metal_edge_u projects the dormer's own drip into the plane.
mu = DM.respond_to?(:metal_edge_u) ? DM.metal_edge_u(built, bsubs.first, planes.first) : nil
ok('the metal edge is measured, not assumed', !mu.nil? && mu[1] > mu[0], mu)

free = PLACE.eave_bar_slots(planes, 'seam')
held = PLACE.eave_bar_slots(planes, 'seam', u_range: [mu[0] + 2.0, mu[1] - 2.0])
ok('a bar is laid at all', !free.empty?, free.length)
ok('and it is cut where the caller says the metal edge ends',
   !held.empty? && held.map { |x| x[:length] }.max <
     free.map { |x| x[:length] }.max - 1.0,
   [free.map { |x| x[:length].round(2) }, held.map { |x| x[:length].round(2) }])

untouched = PLACE.eave_bar_slots(planes, 'seam', u_range: nil)
ok('no range given, nothing changes - the house roof is untouched',
   untouched.map { |x| x[:length].round(4) } == free.map { |x| x[:length].round(4) })

# ---- 5. the house roof keeps its own floor ---------------------------
house = PLACE.planes_from_faces(roof.entities.grep(Sketchup::Face).select { |f| f.normal.z > 0.2 })
a = PLACE.run_slots(house, 'seam')
b = PLACE.run_slots(house, 'seam', min_len: PLACE.min_run_len)
ok('the house roof is laid with the placer\'s floor, unchanged',
   a.length == b.length, [a.length, b.length])

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"

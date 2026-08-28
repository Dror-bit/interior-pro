# encoding: utf-8
# rt112 - AN EDIT KEEPS THE DORMER'S MATERIALS (2026-09-05).
#
# "אני לוחץ על עריכת כל גמלון הגג שלו מאבד את הצבע" - press Edit on any
# dormer and its roof comes back bare.
#
# THE CAUSE: dormer_spec saves NUMBERS. The materials were never attributes
# on the group - place_on_roof! read them off the roof and off the house
# wall and handed them to the builder. replace_dormer! rebuilds straight
# through add_dormer!, so it never went past that line and the new dormer
# was built with roof_material nil.
#
# THE CLAIMS PINNED HERE
# 1. A dormer built with a roof material wears it.
# 2. dormer_spec does NOT carry it - that is the hole, and it is still
#    there on purpose: the fix asks the standing dormer, it does not add
#    an attribute that an older model would not have.
# 3. After an edit the new dormer's roof still wears the same material.
# 4. An edit that names a material explicitly still wins.
#
# Against the old code claim 3 fails: the rebuilt roof has no material.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
Z0 = 100.0
SLOPE = 5.0 / 12.0
SPEC = { z0: Z0, slope: SLOPE, setback: 50.0, width: 50.0, length: 130.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         style: 'gable', base: [0.0, 0.0], along: [1.0, 0.0],
         into: [0.0, 1.0] }.freeze

MAT = 'IP_TestRoofMaterial'

def roof_mats(d)
  d.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
  end.flat_map { |s| s.entities.grep(Sketchup::Face).map(&:material) }.compact.uniq
end

Sketchup.reset_model!
model = Sketchup.active_model
roof = model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
roof.entities.add_face([at.call(-400, 0), at.call(400, 0),
                        at.call(400, 400), at.call(-400, 400)])

d = DM.add_dormer!(roof.entities, SPEC.merge(roof_material: MAT, no_tiles: true))
ok('a dormer was built', !d.nil?)
ok('its roof wears the material it was given', roof_mats(d) == [MAT], roof_mats(d))

spec = DM.dormer_spec(d)
ok('dormer_spec carries no material - that is the hole',
   !spec.key?(:roof_material), spec && spec.keys)

# ---- 3. the edit keeps it -------------------------------------------
d2 = DM.replace_dormer!(d, width: 60.0)
ok('the edit rebuilt the dormer', !d2.nil?)
ok('and its roof still wears the same material', roof_mats(d2) == [MAT],
   roof_mats(d2))
ok('the edit actually took effect', d2 && d2.get_attribute('InteriorPro', 'width').to_f == 60.0,
   d2 && d2.get_attribute('InteriorPro', 'width'))

# ---- 4. an explicit material on the edit still wins ------------------
d3 = DM.replace_dormer!(d2, width: 55.0, roof_material: 'IP_Other')
ok('a material named on the edit wins', roof_mats(d3) == ['IP_Other'],
   roof_mats(d3))

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"

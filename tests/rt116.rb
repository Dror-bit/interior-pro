# encoding: utf-8
# rt116 - A FLAT GABLET SURVIVES A REBUILD (2026-09-06).
#
# He reported it as a material change: "גגון שטוח נעלם כששמים אותו על גג
# ברזל ואז מחליפים לשינגלס. כל שאר הגגות נשארים." Measured, it has
# nothing to do with the material - ANY rebuild threw it away.
#
# THE CAUSE: shed_frame zeroes the pitch for `flat` on purpose (that is
# what flat means), build_dormer! writes fr[:pitch] onto the group, and
# dormer_spec reads it back. So every rebuild handed frame() a spec with
# pitch 0.0 and hit `return warn_nil('the dormer roof has no pitch')`.
# Gable and shed store a real pitch, which is why only flat vanished.
#
# THE THREE DOORS IT CAME BACK THROUGH, all pinned here:
#   replant! (any roof rebuild), replace_dormer! (Edit), and the spec
#   Move hands to place_on_roof!.
#
# Against the old code claims 2, 3 and 4 fail.
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

def new_roof
  Sketchup.reset_model!
  r = Sketchup.active_model.entities.add_group
  r.set_attribute('InteriorPro', 'type', 'roof')
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  r.entities.add_face([at.call(-400, 0), at.call(400, 0),
                       at.call(400, 400), at.call(-400, 400)])
  r
end

BASE = { z0: Z0, slope: SLOPE, setback: 50.0, width: 50.0, length: 120.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0],
         no_tiles: true }.freeze

# ---- 1. a flat gablet stores a zero pitch - that IS flat -------------
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'flat'))
ok('a flat gablet was built', !d.nil?)
ok('1. and it stores a zero pitch, on purpose',
   d && d.get_attribute('InteriorPro', 'pitch').to_f == 0.0,
   d && d.get_attribute('InteriorPro', 'pitch'))
ok('1b. and dormer_spec hands that zero back',
   DM.dormer_spec(d)[:pitch].to_f == 0.0, DM.dormer_spec(d)[:pitch])

# ---- 2. frame() accepts it ------------------------------------------
ok('2. frame builds a flat gablet from a zero pitch',
   !DM.frame(BASE.merge(style: 'flat', pitch: 0.0)).nil?, DM.last_reason)
ok('2b. and still refuses a zero pitch on every other style',
   %w[gable hip shed].all? { |st| DM.frame(BASE.merge(style: st, pitch: 0.0)).nil? })

# ---- 3. it comes back after a roof rebuild --------------------------
%w[gable shed flat].each do |style|
  roof = new_roof
  sp = BASE.merge(style: style)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'
  d = DM.add_dormer!(roof.entities, sp)
  next ok("#{style} was built", false) if d.nil?
  saved = DM.harvest([roof])
  roof2 = new_roof
  back = DM.replant!(roof2, saved)
  ok("3. a #{style} gablet is put back after a roof rebuild", back == 1,
     [back, DM.last_reason])
end

# ---- 4. Edit and Move do not lose it either -------------------------
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'flat'))
d2 = DM.replace_dormer!(d, width: 60.0)
ok('4a. an Edit keeps a flat gablet', !d2.nil?, DM.last_reason)
ok('4b. and the edit took effect',
   d2 && d2.get_attribute('InteriorPro', 'width').to_f == 60.0,
   d2 && d2.get_attribute('InteriorPro', 'width'))
ok('4c. it is still flat', d2 && d2.get_attribute('InteriorPro', 'style') == 'flat',
   d2 && d2.get_attribute('InteriorPro', 'style'))
# Move goes through place_on_roof! with the dormer's own spec
mv = DM.dormer_spec(d2)
roof3 = new_roof
d4 = DM.place_on_roof!(roof3, 0.0, 120.0, mv.merge(no_tiles: true, no_relay: true))
ok('4d. Move can put a flat gablet down again', !d4.nil?, DM.last_reason)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

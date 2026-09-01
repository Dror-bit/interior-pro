# encoding: utf-8
# rt141 - THE GABLET CAN WEAR SOMETHING ELSE (2026-09-13).
#
# He asked for it in one line: "צריך שיהיה אפשרי לבחור לגגון את כל
# החומרים של הקירות וגם זה לא חייב להיות אותו החומר באוטומטית - אפשרי גם
# לבחור חומר שונה".
#
# Until today the finish was never asked for and never stored: place_on_roof!
# and replace_dormer! both went and looked up whatever most of the house
# walls wear. So there was nothing to pick with, and nothing to remember.
#
# WHAT IS PINNED HERE:
# 1. the pick is stored ON the dormer, so a rebuild keeps it;
# 2. '' still means "follow the house", exactly as before - a dormer built
#    before today must not change;
# 3. an EDIT does not quietly put the house material back over his pick.
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

BASE = { z0: Z0, slope: SLOPE, setback: 50.0, width: 60.0, length: 120.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0, style: 'gable',
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0],
         no_tiles: true }.freeze

def new_roof
  Sketchup.reset_model!
  r = Sketchup.active_model.entities.add_group
  r.set_attribute('InteriorPro', 'type', 'roof')
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  r.entities.add_face([at.call(-600, 0), at.call(600, 0),
                       at.call(600, 600), at.call(-600, 600)])
  r
end

# ---- 1. the panel has a place to keep it -----------------------------
ok('settings carry a wall_material', DM.settings.key?(:wall_material),
   DM.settings.keys)
ok("and it starts as '' - follow the house",
   DM.settings[:wall_material].to_s.empty?, DM.settings[:wall_material])

# ---- 2. a pick is stored on the dormer and comes back ----------------
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(wall_names: ['Brick', nil]))
ok('it was built', !d.nil?, DM.last_reason)
if d
  ok('the dormer remembers the finish it was given',
     d.get_attribute('InteriorPro', 'wall_material') == 'Brick',
     d.get_attribute('InteriorPro', 'wall_material'))
  ok('dormer_spec hands it back, so a rebuild keeps it',
     Array(DM.dormer_spec(d)[:wall_names]).first == 'Brick',
     DM.dormer_spec(d)[:wall_names])
end

# ---- 3. nothing chosen is still "follow the house" -------------------
roof2 = new_roof
d2 = DM.add_dormer!(roof2.entities, BASE)
ok('a dormer with no pick stores a blank, not a guess',
   !d2.nil? && d2.get_attribute('InteriorPro', 'wall_material').to_s.empty?,
   d2 && d2.get_attribute('InteriorPro', 'wall_material'))
ok('and dormer_spec then asks for nothing, so the house decides',
   !d2.nil? && DM.dormer_spec(d2)[:wall_names].nil?,
   d2 && DM.dormer_spec(d2)[:wall_names])

# ---- 4. an edit does not overwrite his pick --------------------------
roof3 = new_roof
d3 = DM.add_dormer!(roof3.entities, BASE.merge(wall_names: ['Stone', nil]))
if d3
  out = DM.replace_dormer!(d3, width: 66.0)
  ok('after an edit the gablet still wears what he picked',
     !out.nil? && out.get_attribute('InteriorPro', 'wall_material') == 'Stone',
     out && out.get_attribute('InteriorPro', 'wall_material'))
end

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

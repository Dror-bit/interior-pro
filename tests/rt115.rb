# encoding: utf-8
# rt115 - A DORMER REMEMBERS WHERE IT SITS (2026-09-06).
#
# He reported two halves of one hole:
#   "בעריכה עומק מהפשיה / מצב מיקום לא נתפס"
#   "אם קבעתי 60 אינץ' מהפשיה, הגגון יזוז רק על הקו הזה, וחופשי רק
#    אם המצב הוא קליק חופשי"
#
# THE CAUSE, measured in the live code:
#   1. build_dormer! never wrote `place_mode` on the group, and
#      dormer_spec never read it - so a built dormer had no mode at all.
#   2. dormer_dialog sent replace_dormer! only sizes - no setback, no
#      mode - so a typed depth on an Edit did nothing.
#   3. DormerMoveTool merged `follow_click: true` unconditionally, which
#      overrides every mode: Move was always free.
#
# Against the old code claims 1, 2, 6 and 7 fail.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
require './dormer_edit_tools'

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

Sketchup.reset_model!
model = Sketchup.active_model
roof = model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
roof.entities.add_face([at.call(-400, 0), at.call(400, 0),
                        at.call(400, 400), at.call(-400, 400)])

# ---- 1. the group keeps the mode ------------------------------------
d = DM.add_dormer!(roof.entities, SPEC.merge(place_mode: 'depth', no_tiles: true))
ok('a dormer was built', !d.nil?)
ok('1. the group remembers its placing mode',
   d && d.get_attribute('InteriorPro', 'place_mode') == 'depth',
   d && d.get_attribute('InteriorPro', 'place_mode'))

# ---- 2. dormer_spec hands it back -----------------------------------
sp = DM.dormer_spec(d)
ok('2. dormer_spec reads the mode back', sp && sp[:place_mode] == 'depth',
   sp && sp[:place_mode])

# a dormer placed with no mode at all is FREE, never accidentally locked
d0 = DM.add_dormer!(roof.entities, SPEC.merge(base: [200.0, 0.0], no_tiles: true))
ok('3. a dormer placed with no mode is free',
   DM.dormer_spec(d0)[:place_mode] == 'free',
   DM.dormer_spec(d0)[:place_mode])

# ---- 4/5. click_spec obeys the mode ---------------------------------
rf = { s_click: 200.0 }
ok('4. depth ignores the click and keeps the typed depth',
   DM.click_spec({ setback: 60.0, place_mode: 'depth' }, rf)[:setback] == 60.0,
   DM.click_spec({ setback: 60.0, place_mode: 'depth' }, rf)[:setback])
ok('5. free with a click on it takes the click',
   DM.click_spec({ setback: 60.0, place_mode: 'free',
                   follow_click: true }, rf)[:setback] == 200.0,
   DM.click_spec({ setback: 60.0, place_mode: 'free',
                   follow_click: true }, rf)[:setback])
ok('5b. free with no click behind it keeps what it was handed',
   DM.click_spec({ setback: 60.0, place_mode: 'free' }, rf)[:setback] == 60.0,
   DM.click_spec({ setback: 60.0, place_mode: 'free' }, rf)[:setback])

# ---- 6. flush on a slope with no wall does not fall to the eave -----
ok('6a. flush lands on the wall when there is one',
   DM.click_spec({ setback: 60.0, place_mode: 'flush' },
                 { s_click: 200.0, wall_s: 24.0 })[:setback] == 24.0,
   DM.click_spec({ setback: 60.0, place_mode: 'flush' },
                 { s_click: 200.0, wall_s: 24.0 })[:setback])
ok('6b. and keeps its setback when there is no wall',
   DM.click_spec({ setback: 60.0, place_mode: 'flush' },
                 { s_click: 200.0, wall_s: 0.0 })[:setback] == 60.0,
   DM.click_spec({ setback: 60.0, place_mode: 'flush' },
                 { s_click: 200.0, wall_s: 0.0 })[:setback])

# ---- 7. Move does not override the mode -----------------------------
mv = InteriorPro::DormerMoveTool.new
mode_of = lambda do |spec|
  mv.instance_variable_set(:@spec, spec)
  mv.send(:move_spec)
end
s_depth = mode_of.call(setback: 60.0, place_mode: 'depth')
ok('7a. Move does not follow the click on a depth dormer',
   !s_depth[:follow_click], s_depth[:follow_click])
ok('7b. and it keeps the mode', s_depth[:place_mode] == 'depth',
   s_depth[:place_mode])
s_free = mode_of.call(setback: 60.0, place_mode: 'free')
ok('7c. Move still follows the click on a free dormer',
   s_free[:follow_click] == true, s_free[:follow_click])
s_old = mode_of.call(setback: 60.0)
ok('7d. an older dormer with no saved mode still moves freely',
   s_old[:follow_click] == true && s_old[:place_mode] == 'free',
   [s_old[:place_mode], s_old[:follow_click]])

# ---- 8. an Edit that types a depth actually moves it -----------------
d2 = DM.replace_dormer!(d, place_mode: 'depth', setback: 62.0)
ok('8a. the edit rebuilt the dormer', !d2.nil?)
ok('8b. and it sits at the typed depth',
   d2 && d2.get_attribute('InteriorPro', 'setback').to_f == 62.0,
   d2 && d2.get_attribute('InteriorPro', 'setback'))
ok('8c. and it still remembers the mode',
   d2 && d2.get_attribute('InteriorPro', 'place_mode') == 'depth',
   d2 && d2.get_attribute('InteriorPro', 'place_mode'))

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt121 - EDITING THE GABLET WINDOW (2026-09-07).
#
# HIS WORDS: "אני צריך להיות אפשרי לערוך אותו מבחינת גודל סוג וכו - ואני
# רוצה שזה יהיה ע"י כלי העריכת חלונות. כמובן שיש לו יותר מגבלות מחלונות
# על קירות וזה בסדר. וגם צריך רק גודל ועוד שתי סוגים של חלונות."
#
# So: Edit Window, click the gablet window, a SHORT panel - size and the
# three types - and Apply rebuilds it. The limits are real and they are
# the wall's, not the panel's.
#
# WHAT IS PINNED HERE
# 1. A typed size only ever fits inside what the wall allows, and never
#    goes under the smallest window we build.
# 2. Typing nothing leaves the 48 x 24 rt117 pinned, digit for digit.
# 3. window_limits tells the panel exactly what it may ask for.
# 4. set_window! stores the numbers on the DORMER and rebuilds it, so the
#    hole and the body change together and Move/Edit keep them.
# 5. The window edit tool routes a gablet window to the dormer, and the
#    wall-window paths refuse it instead of half-doing it.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
require './window_tool'
require './window_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
WM = InteriorPro::WindowManager
Z0 = 100.0
SLOPE = 5.0 / 12.0

BASE = { z0: Z0, slope: SLOPE, setback: 50.0, width: 60.0, length: 120.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0],
         no_tiles: true }.freeze

def new_roof
  Sketchup.reset_model!
  r = Sketchup.active_model.entities.add_group
  r.set_attribute('InteriorPro', 'type', 'roof')
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  r.entities.add_face([at.call(-400, 0), at.call(400, 0),
                       at.call(400, 400), at.call(-400, 400)])
  r
end

def a_of(g, k)
  g.nil? ? nil : g.get_attribute('InteriorPro', k)
end

FR = DM.frame(BASE.merge(style: 'gable'))

# ---- 1/2. what a typed size may be -----------------------------------
free = DM.window_rect(FR)
ok('2. nothing typed is still the 48 x 24 rt117 pinned',
   free[:width] == 48.0 && free[:height] == 24.0,
   [free[:width], free[:height]])

small = DM.window_rect(FR, 30.0, 18.0)
ok('1. a smaller window is built exactly as typed',
   small[:width] == 30.0 && small[:height] == 18.0,
   [small[:width], small[:height]])

big = DM.window_rect(FR, 300.0, 300.0)
ok('1b. asking for more than the wall has is pulled back to the wall',
   big[:width] == free[:width] && big[:height] == free[:height],
   [big[:width], big[:height]])

tiny = DM.window_rect(FR, 2.0, 2.0)
ok('1c. and it never goes under the smallest window we build',
   tiny[:width] == DM.window_min_w && tiny[:height] == DM.window_min_h,
   [tiny[:width], tiny[:height]])

ok('1d. a typed window stays centred in the front wall, like the full one',
   small[:w] == free[:w] && (small[:z] - free[:z]).abs < 6.0,
   [small[:w], small[:z], free[:z]])

ok('1e. a NARROWER window may be taller - the gable head is measured '\
   'after the width is settled',
   DM.window_rect(FR, 24.0)[:height] >= free[:height],
   [DM.window_rect(FR, 24.0)[:height], free[:height]])

# ---- 3. what the panel is told ---------------------------------------
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'gable', window: true))
lim = DM.window_limits(d)
ok('3. window_limits hands the panel the wall\'s own numbers',
   lim && lim[:max_w] == 48.0 && lim[:max_h] == 24.0 &&
   lim[:min_w] == DM.window_min_w && lim[:min_h] == DM.window_min_h, lim)

# ---- 4. Apply ---------------------------------------------------------
d2 = DM.set_window!(d, 'window_type' => 'Slider XO',
                       'width' => 36.0, 'height' => 20.0)
w2 = DM.window_of(d2)
ok('4. Apply rebuilds the gablet with the new window',
   !d2.nil? && !w2.nil?, DM.last_reason)
ok('4b. the body carries the typed size and type',
   a_of(w2, 'width_in') == 36.0 && a_of(w2, 'height_in') == 20.0 &&
   a_of(w2, 'window_type') == 'Slider XO',
   [a_of(w2, 'width_in'), a_of(w2, 'height_in'), a_of(w2, 'window_type')])
ok('4c. and so does the HOLE - they can never drift apart',
   a_of(DM.window_of(d2), 'window_w') == 36.0,
   a_of(DM.window_of(d2), 'window_w'))
front = d2.entities.grep(Sketchup::Group).find do |s|
  s.get_attribute('InteriorPro', 'part').to_s == 'dormer_front'
end
ok('4d. the wall was punched to the same size',
   front && a_of(front, 'window_w') == 36.0 && a_of(front, 'window_h') == 20.0,
   front && [a_of(front, 'window_w'), a_of(front, 'window_h')])
ok('4e. the numbers are stored on the DORMER, which is what Edit and Move '\
   'rebuild from',
   DM.dormer_spec(d2)[:window_w] == 36.0 &&
   DM.dormer_spec(d2)[:window_type] == 'Slider XO',
   DM.dormer_spec(d2).select { |k, _| k.to_s.start_with?('window') })

d3 = DM.replace_dormer!(d2, width: 72.0)
ok('4f. a later Edit Dormer keeps the window exactly as it was set',
   d3 && a_of(DM.window_of(d3), 'width_in') == 36.0 &&
   a_of(DM.window_of(d3), 'window_type') == 'Slider XO',
   d3 && [a_of(DM.window_of(d3), 'width_in'),
          a_of(DM.window_of(d3), 'window_type')])

d4 = DM.set_window!(d3, 'window_type' => 'Nothing Like It', 'width' => 999.0)
ok('4g. rubbish from the panel cannot build a wrong window',
   d4 && a_of(DM.window_of(d4), 'window_type') == 'Picture' &&
   a_of(DM.window_of(d4), 'width_in') == 48.0,
   d4 && [a_of(DM.window_of(d4), 'window_type'),
          a_of(DM.window_of(d4), 'width_in')])

# ---- 5. the tools know which window this is ---------------------------
win = DM.window_of(d4)
ok('5. the window manager knows it is a dormer\'s', WM.dormer_window?(win))
ok('5b. and the front wall is not mistaken for one',
   !WM.dormer_window?(front))
ok('5c. it is found in a click path, deepest first',
   WM.find_window_in_path([d4, win]) == win)
ok('5d. and so is the dormer it belongs to - no id to keep in step',
   WM.find_dormer_in_path([d4, win]) == d4)
ok('5e. the wall-window editor refuses it instead of half-doing it',
   WM.update_window(win, {}) == false)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

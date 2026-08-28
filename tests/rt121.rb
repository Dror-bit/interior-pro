# encoding: utf-8
# rt121 - EDITING THE GABLET WINDOW (2026-09-07).
#
# HIS WORDS: "אני צריך להיות אפשרי לערוך אותו מבחינת גודל סוג וכו - ואני
# רוצה שזה יהיה ע"י כלי העריכת חלונות ... וגם צריך רק גודל ועוד שתי סוגים
# של חלונות."
#
# Then he used it, and two things came out of that (both measured in his
# own model, both pinned here):
#
# THE CEILING IS THE WALL. He typed a height of 30, got 24 without a word,
# and said the panel did nothing. 48 x 24 was the maximum he set back when
# it was only a default. Asked what it should be now that he can type, he
# chose: "כמה שהקיר מרשה". So 48 x 24 is still what an untouched gablet
# gets - rt117 is untouched - and a TYPED size is capped by the wall.
#
# IT REBUILDS THE WALL AND THE WINDOW, AND NOTHING ELSE. Apply used to go
# through replace_dormer!, which erases the whole gablet, heals the roof
# hole, relays the WHOLE tile field and cuts again. On his metal roof a
# panel came back under the window: "הוא עדיין משפיע על דברים אחרים במקום
# על החלון". One window change relaid 44 runs across his roof.
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

# the LIVE part - the stub leaves an erased group in the entity list
def part_of(d, name)
  d.entities.grep(Sketchup::Group).find do |s|
    s.valid? && s.get_attribute('InteriorPro', 'part').to_s == name
  end
end

def other_parts(d)
  d.entities.grep(Sketchup::Group).select do |s|
    s.valid? && !%w[dormer_front dormer_window]
                 .include?(s.get_attribute('InteriorPro', 'part').to_s)
  end
end

FR = DM.frame(BASE.merge(style: 'gable'))

# ---- 1. nothing typed: rt117's numbers, digit for digit ---------------
free = DM.window_rect(FR)
ok('1. nothing typed is still the 48 x 24 he picked',
   free[:width] == 48.0 && free[:height] == 24.0,
   [free[:width], free[:height]])

# ---- 2. a typed size is capped by the WALL, not by 48 x 24 ------------
cap_w = DM.window_cap_w(FR)
cap_h = DM.window_cap_h(FR, cap_w)
ok('2. the wall on this gablet allows 48 wide and more than 24 tall',
   cap_w == 48.0 && cap_h > 24.0, [cap_w, cap_h])

big = DM.window_rect(FR, 300.0, 300.0)
ok('2b. a typed size may go past 24 - the wall is the only ceiling',
   big[:width] == cap_w && big[:height] == cap_h && big[:height] > 24.0,
   [big[:width], big[:height]])
ok('2c. and it can never pass the wall itself',
   big[:width] <= cap_w + 0.001 && big[:height] <= cap_h + 0.001,
   [big[:width], big[:height], cap_w, cap_h])

small = DM.window_rect(FR, 30.0, 18.0)
ok('2d. a smaller window is built exactly as typed',
   small[:width] == 30.0 && small[:height] == 18.0,
   [small[:width], small[:height]])

tiny = DM.window_rect(FR, 2.0, 2.0)
ok('2e. and it never goes under the smallest window we build',
   tiny[:width] == DM.window_min_w && tiny[:height] == DM.window_min_h,
   [tiny[:width], tiny[:height]])

ok('2f. a NARROWER window may be taller - the gable head is measured '\
   'after the width is settled',
   DM.window_rect(FR, 24.0, 300.0)[:height] > big[:height],
   [DM.window_rect(FR, 24.0, 300.0)[:height], big[:height]])

ok('2g. it stays centred in the front wall whatever the size',
   small[:w] == free[:w] && small[:w] == 0.0, [small[:w], free[:w]])

# ---- 3. what the panel is told ---------------------------------------
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'gable', window: true))
lim = DM.window_limits(d)
ok('3. window_limits hands the panel the WALL\'s numbers, not 48 x 24',
   lim && lim[:max_w] == cap_w && lim[:max_h] > 24.0 &&
   lim[:min_w] == DM.window_min_w && lim[:min_h] == DM.window_min_h, lim)
ok('3b. a fresh gablet still starts at the 48 x 24 default',
   a_of(DM.window_of(d), 'width_in') == 48.0 &&
   a_of(DM.window_of(d), 'height_in') == 24.0,
   [a_of(DM.window_of(d), 'width_in'), a_of(DM.window_of(d), 'height_in')])

# ---- 4. Apply ---------------------------------------------------------
keep = other_parts(d).dup
old_front  = part_of(d, 'dormer_front')
old_window = part_of(d, 'dormer_window')

d2 = DM.set_window!(d, 'window_type' => 'Double Hung',
                       'width' => 36.0, 'height' => 30.0)
ok('4. Apply comes back with the SAME gablet - it is not rebuilt', d2 == d,
   DM.last_reason)

w2 = DM.window_of(d2)
ok('4b. the body carries the typed size and type',
   a_of(w2, 'width_in') == 36.0 && a_of(w2, 'height_in') == 30.0 &&
   a_of(w2, 'window_type') == 'Double Hung',
   [a_of(w2, 'width_in'), a_of(w2, 'height_in'), a_of(w2, 'window_type')])
ok('4c. 30 tall really is built - the old 24 ceiling is gone',
   a_of(w2, 'height_in') == 30.0, a_of(w2, 'height_in'))
front = part_of(d2, 'dormer_front')
ok('4d. the wall was punched to exactly the same size',
   front && a_of(front, 'window_w') == 36.0 && a_of(front, 'window_h') == 30.0,
   front && [a_of(front, 'window_w'), a_of(front, 'window_h')])
ok('4e. the numbers stored on the gablet are what was BUILT',
   a_of(d2, 'window_w') == 36.0 && a_of(d2, 'window_h') == 30.0 &&
   a_of(d2, 'window_type') == 'Double Hung',
   [a_of(d2, 'window_w'), a_of(d2, 'window_h')])

# ---- 5. THE ROOF IS NOT TOUCHED --------------------------------------
ok('5. the front wall was rebuilt', !front.nil? && front != old_front)
ok('5b. and so was the window', !w2.nil? && w2 != old_window)
now = other_parts(d2)
ok('5c. every OTHER part of the gablet is the very same object - the '\
   'roof, the cheeks, the trim and the tiles were never rebuilt',
   now.length == keep.length && now.all? { |g| keep.include?(g) },
   [keep.length, now.length])

# ---- 6. it still survives the dormer\'s own Edit and a roof rebuild ----
d3 = DM.replace_dormer!(d2, width: 72.0)
ok('6. a later Edit Dormer keeps the window exactly as it was set',
   d3 && a_of(DM.window_of(d3), 'width_in') == 36.0 &&
   a_of(DM.window_of(d3), 'window_type') == 'Double Hung',
   d3 && [a_of(DM.window_of(d3), 'width_in'),
          a_of(DM.window_of(d3), 'window_type')])

d4 = DM.set_window!(d3, 'window_type' => 'Nothing Like It', 'width' => 999.0)
w4 = DM.window_of(d4)
ok('6b. rubbish from the panel cannot build a wrong window',
   d4 && a_of(w4, 'window_type') == 'Picture' &&
   a_of(w4, 'width_in') == DM.window_cap_w(DM.frame(DM.dormer_spec(d4))),
   d4 && [a_of(w4, 'window_type'), a_of(w4, 'width_in')])

# ---- 7. the tools know which window this is ---------------------------
ok('7. the window manager knows it is a gablet\'s', WM.dormer_window?(w4))
ok('7b. and the front wall is not mistaken for one',
   !WM.dormer_window?(part_of(d4, 'dormer_front')))
ok('7c. it is found in a click path, deepest first',
   WM.find_window_in_path([d4, w4]) == w4)
ok('7d. and so is the gablet it belongs to - no id to keep in step',
   WM.find_dormer_in_path([d4, w4]) == d4)
ok('7e. the wall-window editor refuses it instead of half-doing it',
   WM.update_window(w4, {}) == false)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

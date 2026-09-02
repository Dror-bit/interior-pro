# encoding: utf-8
# rt122 - A REBUILD CHANGES NOTHING (2026-09-07).
#
# He clicked Apply in the new window panel and got "too long for this
# roof - it would reach the ridge. The tallest front wall that fits here
# is 99"", and said: "לא הבנתי מה הוא רוצה". The window had nothing to do
# with it.
#
# THE CAUSE, MEASURED. frame() adds the raised heel to `length`, and
# build_dormer! saved THAT number on the group. dormer_spec handed it
# back as the next rebuild's typed length, and the heel went on again -
# so every Edit, Move, replant and Apply grew the gablet. On a 5:12 roof
# with a 6" eave a typed 120 came back 139.2, 158.4, 177.6, 196.8, and
# the front wall climbed 45.5 -> 53.5 -> 61.5 -> 69.5 until the gablet
# reached the ridge and refused to build at all.
#
# THE FIX: the group remembers the length that was ASKED FOR. The
# geometry still uses the heeled length - rt118 and rt119 are untouched -
# and the heel is now added exactly once.
#
# WHAT IS PINNED HERE: rebuilding a gablet, over and over, leaves it
# exactly the size it was. That is the whole test.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
# 2026-09-13B: this suite pins the RAW gablet formulas, so the 6" the roof
# now rides above the window is switched off here - exactly the way the
# raised heel is kept out of these same formulas. rt148 pins the headroom.
InteriorPro::DormerManager.send(:remove_const, :USE_DORMER_HEADROOM)
InteriorPro::DormerManager.const_set(:USE_DORMER_HEADROOM, false)


$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
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
  r.entities.add_face([at.call(-600, 0), at.call(600, 0),
                       at.call(600, 600), at.call(-600, 600)])
  r
end

def num(g, k)
  g.get_attribute('InteriorPro', k).to_f.round(4)
end

# ---- 1. the heel is added ONCE, not once per rebuild ------------------
%w[gable shed flat hip].each do |style|
  sp = BASE.merge(style: style)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'
  roof = new_roof
  d = DM.add_dormer!(roof.entities, sp)
  ok("#{style}: it was built at all", !d.nil?, DM.last_reason)
  next if d.nil?

  ok("1. #{style}: the group remembers the length that was ASKED for, " \
     'not the heeled one', num(d, 'length') == 120.0, num(d, 'length'))

  lens = [num(d, 'length')]
  hts  = [num(d, 'height')]
  4.times do
    d2 = DM.replace_dormer!(d)
    break if d2.nil?
    d = d2
    lens << num(d, 'length')
    hts  << num(d, 'height')
  end
  ok("1b. #{style}: four rebuilds and the length never moves",
     lens.length == 5 && lens.uniq.length == 1, lens)
  ok("1c. #{style}: and the front wall never grows",
     hts.length == 5 && hts.uniq.length == 1, hts)
end

# ---- 2. the heel is still THERE - rt118/rt119 are not being undone ----
fr = DM.frame(BASE.merge(style: 'gable'))
ok('2. the heel still lengthens the geometry, it is only not saved twice',
   fr[:length] > fr[:length_asked] && fr[:length_asked] == 120.0,
   [fr[:length], fr[:length_asked]])
ok('2b. and the front wall still gets the room the heel bought it',
   (fr[:z_eave] - fr[:z_front] - 45.5).abs < 0.001,
   fr[:z_eave] - fr[:z_front])

# ---- 3. what he actually hit: a window Apply on a standing gablet -----
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'shed', pitch: SLOPE / 2.0,
                                             window: true))
ok('3. a gablet with a window was built', !d.nil?, DM.last_reason)
5.times do |i|
  d2 = DM.set_window!(d, 'window_type' => 'Double Hung',
                         'width' => 36.0, 'height' => 20.0)
  ok("3b. Apply number #{i + 1} still builds", !d2.nil?, DM.last_reason)
  break if d2.nil?
  d = d2
end
ok('3c. and five Applies later the gablet is the size it started',
   num(d, 'length') == 120.0 && num(d, 'height') == 33.0,
   [num(d, 'length'), num(d, 'height')])

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt144 - THE PANEL SHOWS THE NUMBER HE TYPED (2026-09-13).
#
# "משום מה שאני לוחץ על עריכה לדורמר הקיים הוא לא מראה לי את הנתונים של
# הדורמר הקיים... הוא מראה לי 30 ואז שאני לוחץ APPLY הוא אומר לי לשנות
# את זה ל-22. אז הוא לא מראה לי 22 מהתחלה?"
#
# MEASURED: exactly the trap the LENGTH fell into (rt122), one attribute
# over. frame() adds the raised heel - the gablet's own fascia depth - so
# a typed 22 is BUILT as 30, and build_dormer! wrote 30 on the group. The
# panel read 30 and sent it back as the next Apply's typed height, which
# heeled it again to 38 - taller than the roof allows, so the panel
# refused a dormer that was standing right there.
#
# WHAT IS PINNED HERE: the group remembers the height that was ASKED for,
# the geometry still uses the built one, and a rebuild does not grow.
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
ASKED = 30.0

BASE = { z0: Z0, slope: SLOPE, setback: 50.0, width: 60.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         fascia_depth: 8.0, height: ASKED,
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

ok('the heel is real here, so the two numbers differ',
   DM.dormer_heel(6.0, 'gable', SLOPE, SLOPE, BASE) > 0.0)

%w[gable shed flat].each do |style|
  sp = BASE.merge(style: style)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'

  fr = DM.frame(sp)
  ok("#{style}: it framed", !fr.nil?, DM.last_reason)
  next if fr.nil?
  ok("#{style}: frame keeps the asked height beside the built one",
     (fr[:height_asked].to_f - ASKED).abs < 1e-6, fr[:height_asked])
  ok("#{style}: and the BUILT height is taller - that is the heel",
     fr[:height].to_f > ASKED + 0.5, [fr[:height], ASKED])

  roof = new_roof
  d = DM.add_dormer!(roof.entities, sp)
  ok("#{style}: it was built", !d.nil?, DM.last_reason)
  next if d.nil?
  ok("#{style}: the group remembers what he TYPED, not what came out",
     (d.get_attribute('InteriorPro', 'height').to_f - ASKED).abs < 1e-6,
     d.get_attribute('InteriorPro', 'height'))

  # and a rebuild at that number does not grow it, over and over
  hs = [d.get_attribute('InteriorPro', 'height').to_f]
  cur = d
  3.times do
    cur = DM.replace_dormer!(cur, height: hs.last)
    break if cur.nil?
    hs << cur.get_attribute('InteriorPro', 'height').to_f
  end
  ok("#{style}: rebuilding it three times changes nothing",
     !cur.nil? && hs.uniq.length == 1, hs)
end

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

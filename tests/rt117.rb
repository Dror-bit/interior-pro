# encoding: utf-8
# rt117 - A WINDOW IN THE GABLET'S FRONT WALL (2026-09-06).
#
# His rule, in his words: start from the 48 x 24 he picked - "זה יהיה
# המקסימום" - and on a smaller gablet just keep 6" of wall clear on every
# side, "כמובן שלא יוכל להיכנס לתוך עובי הקירות". The panel gets an option
# with a window or without: "בסרגל של הגגונים תהיה אופציה עם חלון או בלי
# חלון". And it belongs to the gablet: "החלון נמחק וזז עם הגגון".
#
# WHAT IS PINNED HERE
# 1. No window unless it is asked for - every older path is untouched.
# 2. 48 x 24 is a ceiling, never exceeded.
# 3. 6" of wall on each side, and ALWAYS at least 1" clear of the inside
#    face of the cheeks, whatever the margin works out to.
# 4. A gablet too narrow or too short says so and builds no window.
# 5. The opening lives INSIDE the dormer group, so Move and Delete take
#    it with them, and it survives Edit and a roof rebuild.
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
TH = 5.0

BASE = { z0: Z0, slope: SLOPE, setback: 50.0, width: 60.0, length: 120.0,
         thickness: TH, roof_thickness: 0.5, overhang: 6.0,
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

def front_wall(d)
  d.entities.grep(Sketchup::Group).find do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'dormer_front'
  end
end

def win_of(d)
  w = front_wall(d)
  return nil if w.nil?
  ww = w.get_attribute('InteriorPro', 'window_w')
  ww.nil? ? nil : [ww.to_f, w.get_attribute('InteriorPro', 'window_h').to_f]
end

# ---- 1. nothing changes for a caller that never asked ---------------
roof = new_roof
plain = DM.add_dormer!(roof.entities, BASE.merge(style: 'gable'))
ok('a gablet was built', !plain.nil?)
ok('1. no window unless it is asked for', win_of(plain).nil?, win_of(plain))
ok('1b. and the group says so',
   plain && plain.get_attribute('InteriorPro', 'window') == false,
   plain && plain.get_attribute('InteriorPro', 'window'))

# ---- 2/3. the sizes ---------------------------------------------------
def rect_for(style, width, extra = {})
  sp = BASE.merge(style: style, width: width).merge(extra)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'
  fr = DM.frame(sp)
  fr.nil? ? nil : [DM.window_rect(fr), fr]
end

r60, fr60 = rect_for('gable', 60.0)
ok('2. a 60" gablet gets the 48 x 24 he picked',
   r60 && r60[:width] == 48.0 && r60[:height] == 24.0,
   r60 && [r60[:width], r60[:height]])
ok('2b. 48 x 24 is a ceiling, not a target - a 90" gablet gets no more',
   (rect_for('flat', 90.0)[0][:width] == 48.0),
   rect_for('flat', 90.0)[0][:width])

%w[gable flat hip shed].each do |style|
  [40.0, 50.0, 60.0, 80.0].each do |w|
    got = rect_for(style, w)
    next if got.nil? || got[0].nil?
    r, fr = got
    outside = (w - r[:width]) / 2.0
    inside  = (2.0 * (fr[:half] - fr[:thickness]) - r[:width]) / 2.0
    ok("3. #{style} #{w.to_i}\": 6\" of wall each side, and clear of the cheeks",
       outside >= 5.99 && inside >= 0.99 && r[:width] <= DM.window_max_w &&
       r[:height] <= DM.window_max_h,
       [r[:width], r[:height], outside.round(2), inside.round(2)])
  end
end

# ---- 4. it refuses when it cannot fit --------------------------------
tiny = rect_for('gable', 26.0)
ok('4. a gablet too narrow gets no window',
   tiny.nil? || tiny[0].nil?, tiny && tiny[0])

# ---- 5. it belongs to the gablet -------------------------------------
roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'flat', window: true))
ok('5. a window was punched', !win_of(d).nil?, win_of(d))
ok('5b. the group remembers it',
   d && d.get_attribute('InteriorPro', 'window') == true)
ok('5c. dormer_spec carries it', DM.dormer_spec(d)[:window] == true,
   DM.dormer_spec(d)[:window])
ok('5d. the opening is INSIDE the dormer group, so it moves and dies with it',
   !front_wall(d).nil? && d.entities.to_a.include?(front_wall(d)))

d2 = DM.replace_dormer!(d, width: 70.0)
ok('5e. an Edit keeps the window', d2 && !win_of(d2).nil?,
   d2 && win_of(d2))
# a fresh one for the rebuild: the stub's erase! leaves the edited copy
# behind, so harvesting the roof d2 stands on would count two.
roofr = new_roof
dr = DM.add_dormer!(roofr.entities, BASE.merge(style: 'flat', window: true))
saved = DM.harvest([roofr])
roof2 = new_roof
back = DM.replant!(roof2, saved)
ok('5f. a roof rebuild puts it back', back == 1, [back, DM.last_reason])
kept = roof2.entities.grep(Sketchup::Group).select do |g|
  g.get_attribute('InteriorPro', 'type') == 'dormer'
end
ok('5g. and it comes back WITH its window',
   kept.length == 1 && !win_of(kept.first).nil?,
   kept.map { |g| win_of(g) })

# and a gablet asked for no window keeps none through an Edit
roof3 = new_roof
d3 = DM.add_dormer!(roof3.entities, BASE.merge(style: 'flat', window: false))
d4 = DM.replace_dormer!(d3, width: 62.0)
ok('5h. "no window" survives an Edit too', d4 && win_of(d4).nil?,
   d4 && win_of(d4))

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt120 - THE WINDOW BODY IN THE GABLET'S FRONT WALL (2026-09-07).
#
# rt117 punched the HOLE. This is what fills it.
#
# HIS INSTRUCTION: "תעתיק את הקוד של החלון ... מהחלונות שכבר קיימים ברשימת
# החלונות." So there is no second window builder. The gablet window is an
# empty group put in the hole, pointed the right way, and handed to
# WindowTool#casement_body! - the same call every window in a wall makes.
#
# WHAT IS PINNED HERE
# 1. No body unless a window was asked for.
# 2. It answers type == 'window', so Edit Window finds it in the click
#    path exactly like a house window, and it says it is a dormer's.
# 3. It is placed where the window tool expects to build: the centre of
#    the hole ON THE OUTSIDE FACE, u along the wall, v into it.
# 4. Three types and only three; anything else falls back to the fixed
#    window he picked first.
# 5. The jamb never stands out into the room on a thin gablet wall.
# 6. It lives INSIDE the dormer group and survives Edit and a rebuild.
#
# THE STUB CANNOT SEE THE SOLID. Sketchup::Face has no erase! there, so
# the ring-with-a-hole the window tool builds stops at the first face -
# the same limit rt117 works under. Everything measured here is the
# PLACING, which is what this file owns.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
require './window_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
Z0 = 100.0
SLOPE = 5.0 / 12.0

# along = +x and into = +y, so at(s, w, z) lands at (w, s, z).
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

# ---- 1. nothing at all for a gablet that never asked -----------------
roof = new_roof
plain = DM.add_dormer!(roof.entities, BASE.merge(style: 'gable'))
ok('a gablet was built', !plain.nil?)
ok('1. no window body unless it is asked for', DM.window_of(plain).nil?)

roof = new_roof
d = DM.add_dormer!(roof.entities, BASE.merge(style: 'gable', window: true))
win = DM.window_of(d)
ok('a gablet with a window was built', !d.nil? && !win.nil?, DM.last_reason)

fr = DM.frame(BASE.merge(style: 'gable'))
r  = DM.window_rect(fr)
ok('the opening is still the 48 x 24 he picked',
   r && r[:width] == 48.0 && r[:height] == 24.0, r && [r[:width], r[:height]])

# ---- 2. Edit Window can find it --------------------------------------
ok('2. it answers type == "window" - Edit Window picks it up',
   a_of(win, 'type') == 'window', a_of(win, 'type'))
ok('2b. and it says it belongs to a dormer',
   a_of(win, 'dormer_window') == true, a_of(win, 'dormer_window'))
ok('2c. it carries the size of the hole it fills',
   a_of(win, 'width_in') == r[:width] && a_of(win, 'height_in') == r[:height],
   [a_of(win, 'width_in'), a_of(win, 'height_in')])

# ---- 3. where the body is put ----------------------------------------
pl = DM.window_place(fr, DM.at_lambda(BASE), r)
ok('3. u runs ALONG the wall and v runs INTO the roof',
   pl[:unit][0].round(6) == 1.0 && pl[:unit][1].round(6) == 0.0 &&
   pl[:n][0].round(6) == 0.0 && pl[:n][1].round(6) == 1.0,
   [pl[:unit], pl[:n]])
ok('3b. and outdoors is -v, which is what clicked_side = -1 means to the '\
   'window tool', pl[:clicked_side] == -1, pl[:clicked_side])
ok('3c. the origin sits on the OUTSIDE face, centred in the hole',
   (pl[:origin].y - fr[:s_front]).abs < 0.001 &&
   (pl[:origin].x - r[:w]).abs < 0.001 &&
   (pl[:origin].z - r[:z]).abs < 0.001,
   [pl[:origin].to_a, fr[:s_front], r[:w], r[:z]])
ok('3d. the group really stands there',
   win && (win.transformation.origin.distance(pl[:origin]) < 0.001),
   win && win.transformation.origin.to_a)

# ---- 4. the three types ----------------------------------------------
ok('4. three types, the three he was shown',
   DM.window_types == ['Picture', 'Slider XO', 'Double Hung'], DM.window_types)
ok('4b. nothing asked for is the fixed window he picked first',
   a_of(win, 'window_type') == 'Picture', a_of(win, 'window_type'))
roof = new_roof
ds = DM.add_dormer!(roof.entities,
                    BASE.merge(style: 'gable', window: true,
                               window_type: 'Slider XO'))
ok('4c. a type that is asked for is the type that is built',
   a_of(DM.window_of(ds), 'window_type') == 'Slider XO',
   a_of(DM.window_of(ds), 'window_type'))
roof = new_roof
dj = DM.add_dormer!(roof.entities,
                    BASE.merge(style: 'gable', window: true,
                               window_type: 'Bay Window Deluxe'))
ok('4d. a type we do not build falls back, it never builds a wrong window',
   a_of(DM.window_of(dj), 'window_type') == 'Picture',
   a_of(DM.window_of(dj), 'window_type'))

# ---- 5. a thin wall holds the jamb back -------------------------------
thin = BASE.merge(style: 'gable', window: true, thickness: 2.0)
frt  = DM.frame(thin)
plt  = DM.window_place(frt, DM.at_lambda(thin), DM.window_rect(frt))
ok('5. on a 2" wall the jamb is cut back so it cannot stand in the room',
   plt[:interior_depth] <= 2.0 - 2.0 + 0.251 && plt[:interior_depth] > 0.0,
   plt[:interior_depth])
ok('5b. on a normal 5" wall it is the full 1" a house window has',
   pl[:interior_depth] == 1.0, pl[:interior_depth])

# ---- 6. it belongs to the gablet -------------------------------------
roof = new_roof
d6 = DM.add_dormer!(roof.entities,
                    BASE.merge(style: 'gable', window: true,
                               window_type: 'Double Hung'))
ok('6. the body is INSIDE the dormer group',
   d6.entities.to_a.include?(DM.window_of(d6)))
d7 = DM.replace_dormer!(d6, width: 70.0)
ok('6b. an Edit keeps it, WITH its type',
   d7 && a_of(DM.window_of(d7), 'window_type') == 'Double Hung',
   d7 && a_of(DM.window_of(d7), 'window_type'))
roofr = new_roof
dr = DM.add_dormer!(roofr.entities,
                    BASE.merge(style: 'flat', window: true,
                               window_type: 'Slider XO'))
saved = DM.harvest([roofr])
roof2 = new_roof
back = DM.replant!(roof2, saved)
kept = roof2.entities.grep(Sketchup::Group).select do |g|
  g.get_attribute('InteriorPro', 'type') == 'dormer'
end
ok('6c. a roof rebuild puts it back with its type',
   back == 1 && kept.length == 1 &&
   a_of(DM.window_of(kept.first), 'window_type') == 'Slider XO',
   [back, kept.length, DM.last_reason])

# every style that can hold a window gets a body
%w[gable flat hip shed].each do |style|
  sp = BASE.merge(style: style, window: true)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'
  rr = new_roof
  dsx = DM.add_dormer!(rr.entities, sp)
  ok("6d. #{style}: the hole and the body both get built",
     !DM.window_of(dsx).nil?, DM.last_reason)
end

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

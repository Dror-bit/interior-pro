# encoding: utf-8
# rt134 - AN UPPER-STOREY DOWNSPOUT ENDS ON WHAT IS UNDER IT (2026-09-11).
#
# WHY
# The user: "בקומה שניה דאון ספוט שלא יושב מעל גג של קומה ראשונה צריך
# לרדת עד לרצפה". Every pipe used to stop at its OWN storey's floor, so
# on a second storey a pipe with nothing under it ended in mid-air.
#
# WHAT IS PINNED HERE
# downspout_ground_probe, with a fake ray: the lowest storey is untouched
# (its floor is the ground); higher up, a hit well above the true ground
# is where the pipe lands, anything else and it runs to the true ground.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

RF = InteriorPro::RoofManager

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}#{extra.nil? ? '' : "   << #{extra.inspect}"}"
    FAILS << name
  end
end

model = Sketchup.active_model
shots = []

# --- the lowest storey: the floor IS the ground, no ray fired ----------
g0 = RF.downspout_ground_probe(model, 0.0, true_ground: 0.0,
                               ray: ->(x, y, z) { shots << [x, y, z]; 120.0 })
ok('lowest storey: the pipe ends on its own floor', g0.call(10, 10) == 0.0, g0.call(10, 10))
ok('...and no ray was fired', shots.empty?, shots)

# --- an upper storey (floor 106) over a true ground of 0 ---------------
lower_roof = ->(_x, _y, _z) { 100.0 }          # a first-storey roof at z=100
g1 = RF.downspout_ground_probe(model, 106.0, true_ground: 0.0, ray: lower_roof)
ok('over a lower roof: the pipe lands on it', g1.call(10, 10) == 100.0, g1.call(10, 10))

nothing = ->(_x, _y, _z) { nil }
g2 = RF.downspout_ground_probe(model, 106.0, true_ground: 0.0, ray: nothing)
ok('over nothing: the pipe runs to the true ground', g2.call(10, 10) == 0.0, g2.call(10, 10))

slab = ->(_x, _y, _z) { 2.0 }                  # a ground slab, barely above 0
g3 = RF.downspout_ground_probe(model, 106.0, true_ground: 0.0, ray: slab)
ok('a hit barely above the ground is still the ground', g3.call(10, 10) == 0.0,
   g3.call(10, 10))

# --- the ray starts just UNDER this storey's floor ---------------------
seen = nil
g4 = RF.downspout_ground_probe(model, 106.0, true_ground: 0.0,
                               ray: ->(x, y, z) { seen = [x, y, z]; nil })
g4.call(30.0, 40.0)
ok('the ray is fired at the pipe\'s own plan point',
   seen && seen[0] == 30.0 && seen[1] == 40.0, seen)
ok('...from just under this storey\'s floor', seen && seen[2] < 106.0 && seen[2] > 100.0,
   seen)

# --- a ray that raises does not take the roof down with it -------------
boom = ->(_x, _y, _z) { raise 'no model' }
g5 = RF.downspout_ground_probe(model, 106.0, true_ground: 0.0, ray: boom)
ok('a failing ray falls back to the true ground', g5.call(1, 1) == 0.0)

# --- per-pipe answers really differ ------------------------------------
mixed = ->(x, _y, _z) { x < 100.0 ? 100.0 : nil }
g6 = RF.downspout_ground_probe(model, 106.0, true_ground: 0.0, ray: mixed)
ok('two pipes on one roof can end at two different heights',
   g6.call(50, 0) == 100.0 && g6.call(150, 0) == 0.0,
   [g6.call(50, 0), g6.call(150, 0)])

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

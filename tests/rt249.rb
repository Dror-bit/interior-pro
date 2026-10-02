# encoding: utf-8
# rt249 - BUILT FROM NOTHING, THE TWO ROOFS STILL MEET (2026-10-02).
#
# His question: "if I delete the roofs and make them again from the roof
# window, does the join come out by itself?" Measured on his Aetna model
# (roof_scratch_report.txt): NO. One Apply builds the house first - it has
# more walls - while the garage roof does not exist yet, so the house finds
# no lower roof to be cut for: its deck and top skin ran whole UNDER the
# garage roof (107.6" under 115.0" at one point) and its eave dressing ran
# straight through. The garage, built second, came out right. One more build
# of the house and the zone was line for line what it had been.
#
# Pinned: a roof built before a neighbour it has to meet is built once more
# at the end of the same Apply - the pure rule that picks it, then the real
# path on his walls, then the kill switch.
ENV['REAL_ROOMS'] = '1'
require 'stringio'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager
def set_const(name, val)
  RF.send(:remove_const, name) if RF.const_defined?(name, false)
  RF.const_set(name, val)
end
set_const(:USE_ROOF_VALLEY, true)
ok('the code is loaded', RF.respond_to?(:valley_redo_indices) && RF.respond_to?(:valley_second_pass!) &&
                         RF.const_defined?(:USE_VALLEY_SECOND_PASS, false))

# ---- 1. the pure rule: who is built once more ----------------------------------
HOUSE = { pts: [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]], ridge_z: 145.25, level: 1 }.freeze
GARAGE = { pts: [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]], ridge_z: 116.5, level: 1 }.freeze
ADU = { pts: [[900.0, 0.0], [1100.0, 0.0], [1100.0, 200.0], [900.0, 200.0]], ridge_z: 120.0, level: 1 }.freeze
if RF.respond_to?(:valley_redo_indices)
  ok('his two roofs, house built first: the house is built once more',
     RF.valley_redo_indices([HOUSE, GARAGE]) == [0], RF.valley_redo_indices([HOUSE, GARAGE]))
  ok('the other order: whichever came FIRST is the one that missed its neighbour',
     RF.valley_redo_indices([GARAGE, HOUSE]) == [0], RF.valley_redo_indices([GARAGE, HOUSE]))
  ok('the last one built saw everybody - never built again',
     !RF.valley_redo_indices([HOUSE, GARAGE]).include?(1))
  ok('two roofs of the SAME height do not run into each other: nothing',
     RF.valley_redo_indices([HOUSE, GARAGE.merge(ridge_z: 145.25)]) == [])
  ok('a roof on another storey: nothing',
     RF.valley_redo_indices([HOUSE, GARAGE.merge(level: 2)]) == [])
  ok('a detached building far away, another height: nothing',
     RF.valley_redo_indices([HOUSE, ADU]) == [], RF.valley_redo_indices([HOUSE, ADU]))
  ok('three roofs: only the one with a later neighbour',
     RF.valley_redo_indices([HOUSE, ADU, GARAGE]) == [0], RF.valley_redo_indices([HOUSE, ADU, GARAGE]))
  ok('a roof that failed to build (nil) is stepped over',
     RF.valley_redo_indices([HOUSE, nil, GARAGE]) == [0] && RF.valley_redo_indices([nil, GARAGE]) == [])
  ok('one roof, or none: nothing', RF.valley_redo_indices([HOUSE]) == [] && RF.valley_redo_indices([]) == [])
end

# ---- 2. the real path, on his walls ---------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def fresh_walls
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
end

def quiet
  old = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old
end

# everything a roof group holds, as one sortable picture
def picture(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] }.sort }.sort
end

# the way the roof window builds: one Apply over the storey, nothing standing
def scratch
  fresh_walls
  log = quiet { RF.build_roof!(level: 1, style: 'gable', pitch: 3.0, soffit: 'boxed') }
  [RF.roof_of_wall_id('h2'), RF.roof_of_wall_id('gS'), log]
end

house, garage, log = scratch
ok('one Apply: two roofs, no more', RF.roofs.length == 2 && house && garage && house != garage, RF.roofs.length)
ok('the house is built, then the garage, then the house ONCE more',
   log.lines.grep(/gable over level 1/).map { |l| l[/eave ([0-9.]+)/, 1] } == %w[104.0 86.0 104.0],
   log.lines.grep(/gable over level 1/))
ok('the builder says why', log =~ /built once more/, log.lines.grep(/once more/))
ok('on that second build the house IS cut for the garage roof (eave dressing + deck)',
   log =~ /valley: eave dressing \+ deck cut on 1 edge/, log.lines.grep(/valley: eave/))
ok('the garage is not built again', log.lines.grep(/gable over level 1: eave 86/).length == 1)
if house && garage
  first_house = picture(house)
  first_garage = picture(garage)
  ok('each roof kept its own walls', RF.roof_of_wall_id('h8') == house && RF.roof_of_wall_id('gE') == garage)
  # ...and it is the SAME pair his usual console line gives: each roof rebuilt, twice
  quiet { 2.times { RF.roofs.each { |r| RF.build_roof!(replace: r) } } }
  h2 = RF.roof_of_wall_id('h2')
  g2 = RF.roof_of_wall_id('gS')
  ok('the house from one Apply = the house after two more rebuilds', picture(h2) == first_house,
     [first_house.length, picture(h2).length])
  ok('the garage from one Apply = the garage after two more rebuilds', picture(g2) == first_garage,
     [first_garage.length, picture(g2).length])
end

# a second Apply over standing roofs: nothing is stacked
log2 = quiet { RF.build_roof!(level: 1, style: 'gable', pitch: 3.0, soffit: 'boxed') }
ok('Apply again over the standing roofs: still two roofs', RF.roofs.length == 2, RF.roofs.length)

# two buildings that never meet: nobody is built twice
Sketchup.reset_model!
[['a1', 0, 0, 200, 0], ['a2', 200, 0, 200, 150], ['a3', 200, 150, 0, 150], ['a4', 0, 150, 0, 0],
 ['b1', 900, 0, 1100, 0], ['b2', 1100, 0, 1100, 150], ['b3', 1100, 150, 900, 150], ['b4', 900, 150, 900, 0]].each do |id, sx, sy, ex, ey|
  g = Sketchup.active_model.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx.to_f, 'start_y' => sy.to_f, 'end_x' => ex.to_f, 'end_y' => ey.to_f,
    'thickness' => 5.0, 'base_z' => (id.start_with?('b') ? -18.0 : 0.0), 'height' => 96.0, 'level' => 1,
    'wall_category' => 'exterior', 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
end
log3 = quiet { RF.build_roof!(level: 1, style: 'gable', pitch: 3.0) }
ok('two detached buildings of different heights: two roofs, each built once',
   RF.roofs.length == 2 && log3.lines.grep(/gable over level 1/).length == 2 && log3 !~ /once more/,
   [RF.roofs.length, log3.lines.grep(/over level 1|once more/)])

# ---- 3. the kill switch ---------------------------------------------------------
set_const(:USE_VALLEY_SECOND_PASS, false)
_h, _g, lk = scratch
ok('kill switch: each roof is built once, as before',
   lk.lines.grep(/gable over level 1/).map { |l| l[/eave ([0-9.]+)/, 1] } == %w[104.0 86.0], lk.lines.grep(/gable over level 1/))
ok('kill switch: the house is left uncut', lk !~ /valley: eave dressing \+ deck cut/ && lk !~ /once more/)
set_const(:USE_VALLEY_SECOND_PASS, true)
set_const(:USE_ROOF_VALLEY, false)
_h, _g, lv = scratch
ok('the valley switched off: no second build either', lv.lines.grep(/gable over level 1/).length == 2 && lv !~ /once more/,
   lv.lines.grep(/gable over level 1|once more/))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

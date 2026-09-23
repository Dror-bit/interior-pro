# encoding: utf-8
# rt208 - TWO FLOORS IN THE COUNT (2026-09-22, his choice "2"): the room's
# floor is the room minus its showers, and each shower is a floor of its
# own, with its own material - in the tile count and in the surface takeoff.
require './sketchup_stub'
require './floor_manager'
require './shower_floor'
require './tile_takeoff'
require './surface_takeoff'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor
model = Sketchup.active_model
room = model.entities.add_group
room.set_attribute('InteriorPro', 'type', 'room')
room.set_attribute('InteriorPro', 'id', 'room-1')
room.set_attribute('InteriorPro', 'name', 'Bath')
room.set_attribute('InteriorPro', 'area_sqft', 240.0)
room.set_attribute('InteriorPro', 'boundary_xy', [0.0, 0.0, 240.0, 0.0, 240.0, 144.0, 0.0, 144.0])
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_type', 'Poetry Stone')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.set_attribute('InteriorPro', 'area_sqft', 240.0)
floor.set_attribute('InteriorPro', 'unit_w', 24.0)
floor.set_attribute('InteriorPro', 'unit_l', 24.0)
floor.set_attribute('InteriorPro', 'pattern', 'Tile')
floor.entities.add_face([[0, 0], [240, 0], [240, 144], [0, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })

# a 5 ft x 3 ft shower = 15 sq ft
sq = [[12.0, 12.0], [72.0, 12.0], [72.0, 48.0], [12.0, 48.0]]
pad = SF.build!(sq, 0.0, kind: 'flat', tile: SF::SAME_AS_ROOM, model: model)
ok('the shower is built', pad.respond_to?(:entities))
ok('the shower knows its area', (pad.get_attribute('InteriorPro', 'area_sqft') - 15.0).abs < 0.01, pad.get_attribute('InteriorPro', 'area_sqft'))
ok('the room floor is NET of the shower', (floor.get_attribute('InteriorPro', 'area_sqft') - 225.0).abs < 0.01, floor.get_attribute('InteriorPro', 'area_sqft'))
ok('and remembers its gross', floor.get_attribute('InteriorPro', 'gross_area_sqft') == 240.0)
ok('same-as-room shower is named after the room floor', pad.get_attribute('InteriorPro', 'floor_type') == 'Poetry Stone', pad.get_attribute('InteriorPro', 'floor_type'))

# building the shower again does not take the area off twice
SF.build!(sq, 0.0, kind: 'flat', tile: SF::SAME_AS_ROOM, model: model)
ok('drawn again: still net once', (floor.get_attribute('InteriorPro', 'area_sqft') - 225.0).abs < 0.01, floor.get_attribute('InteriorPro', 'area_sqft'))

# the tile count sees two floors
fl = InteriorPro::TileTakeoff.floors(model)
ok('the tile count lists two floors', fl.length == 2, fl.map { |f| f[:name] })
sh = fl.find { |f| f[:shower] }
ok('the shower row is named after the room', sh && sh[:name] == 'Bath - Shower', sh && sh[:name])
ok('it counts with the room\'s tile when it runs the room\'s tile on', sh && sh[:tw] == 24.0 && sh[:tl] == 24.0, sh)
ok('its outline is its own loop', sh && sh[:poly].length == 4)
rm = fl.find { |f| !f[:shower] }
ok('the room row is net', rm && (rm[:area] - 225.0).abs < 0.01)
ok('and carries the hole for the count', rm && rm[:holes].length == 1)

# the surface takeoff too
rows = InteriorPro::SurfaceTakeoff.take(model).select { |r| r[:kind] == 'floor' }
ok('the takeoff has two floor rows', rows.length == 2, rows.map { |r| r[:name] })
ok('one is the shower, with its material', rows.any? { |r| r[:name] == 'Bath - Shower' && r[:material] == 'Poetry Stone' && r[:sqft] == 15.0 }, rows)
ok('the floors add up to the room', (rows.sum { |r| r[:sqft] } - 240.0).abs < 0.01)

exit($fails.zero? ? 0 : 1)

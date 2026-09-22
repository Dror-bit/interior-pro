# encoding: utf-8
# rt205 - THE SHOWER FLOOR GETS THE ROOM'S REAL TILES (2026-09-22).
#
# His words: "בדיוק כמו הטיל של הריצפות". "Same as the room floor" lays
# the room's own layout inside the shower loop - the grid computed over
# the ROOM, so it runs on without a jump - in its own group tied to the
# shower, and the room's layout is left alone.
require './sketchup_stub'
require './tile_grid'
require './floor_manager'
require './floor_pattern'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

model = Sketchup.active_model
room = model.entities.add_group
room.set_attribute('InteriorPro', 'type', 'room')
room.set_attribute('InteriorPro', 'id', 'room-2')
room.set_attribute('InteriorPro', 'boundary_xy', [0.0, 0.0, 240.0, 0.0, 240.0, 144.0, 0.0, 144.0])
module InteriorPro
  module RoomManager
    def self.rooms_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('InteriorPro', 'type') == 'room' }
    end
  end
end

floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-2')
floor.set_attribute('InteriorPro', 'room_id', 'room-2')
floor.set_attribute('InteriorPro', 'pattern', 'Tile')
floor.set_attribute('InteriorPro', 'unit_w', 24.0)
floor.set_attribute('InteriorPro', 'unit_l', 24.0)
floor.set_attribute('InteriorPro', 'floor_level', 0.0)

FP = InteriorPro::FloorPattern
room_pat = FP.build_for_floor!(floor)
ok('the room layout is built as before', room_pat == true)
n_room = FP.patterns_in_model.length

sq = [[12.0, 12.0], [72.0, 12.0], [72.0, 48.0], [12.0, 48.0]]
sp = FP.build_for_floor!(floor, clip: sq, base_z: -0.05, shower_id: 'sh-1')
ok('the shower gets a layout group of its own', sp.respond_to?(:entities), sp)
ok('marked as the shower\'s', sp && sp.get_attribute('InteriorPro', 'type') == 'shower_pattern' &&
   sp.get_attribute('InteriorPro', 'shower_id') == 'sh-1')
ok('the room layout was NOT thrown away', FP.patterns_in_model.length == n_room)
pts = sp ? sp.entities.grep(Sketchup::Edge).flat_map { |e| [e.a, e.b] } : []
ok('every tile line lies inside the shower loop',
   pts.any? && pts.all? { |p| p.x >= 11.99 && p.x <= 72.01 && p.y >= 11.99 && p.y <= 48.01 }, pts.first(4))
ok('and at the pad top + LINE_Z (level with the room tiles)',
   pts.any? && pts.all? { |p| (p.z - 0.0).abs < 1.0e-6 })
xs = pts.map { |p| p.x.round(3) }.uniq.sort
ok('the room grid runs on: a joint at x = 24 and 48, same as the room', xs.include?(24.0) && xs.include?(48.0), xs)

ok('the shower finds its tiles', InteriorPro::ShowerFloor.tiles_of('sh-1', model) == [sp])
ok('there is a kill switch', InteriorPro::ShowerFloor::USE_SHOWER_TILES == true)

exit($fails.zero? ? 0 : 1)

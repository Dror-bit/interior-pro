# encoding: utf-8
# rt220 - A FLOOR BUILT AGAIN KNOWS THE SHOWER STANDING IN IT (2026-09-23).
# Measured on his model: Room 2's floor was rebuilt, `shower_holes stored: 0`,
# and the room tile ran under the flat shower. cut_floor! (called at the end
# of every slab build) now writes the loop of every flat shower of the room.
require './sketchup_stub'
require './floor_manager'
require './floor_pattern'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor
model = Sketchup.active_model
ents = model.entities
# his numbers
loop_xy = [[-486.61, 401.88], [-486.61, 333.04], [-443.63, 333.04], [-443.63, 401.88]]
pad = ents.add_group
pad.set_attribute('InteriorPro', 'type', 'shower_floor')
pad.set_attribute('InteriorPro', 'kind', 'flat')
pad.set_attribute('InteriorPro', 'room_id', 'room-2')
pad.set_attribute('InteriorPro', 'poly_xy', loop_xy.flatten)
raised = ents.add_group
raised.set_attribute('InteriorPro', 'type', 'shower_floor')
raised.set_attribute('InteriorPro', 'kind', 'curb')
raised.set_attribute('InteriorPro', 'room_id', 'room-2')
raised.set_attribute('InteriorPro', 'poly_xy', [[-520, 340], [-500, 340], [-500, 360], [-520, 360]].flatten)
other = ents.add_group
other.set_attribute('InteriorPro', 'type', 'shower_floor')
other.set_attribute('InteriorPro', 'kind', 'flat')
other.set_attribute('InteriorPro', 'room_id', 'room-1')
other.set_attribute('InteriorPro', 'poly_xy', [[-600, 200], [-580, 200], [-580, 220], [-600, 220]].flatten)

floor = ents.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'room_id', 'room-2')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.set_attribute('InteriorPro', 'area_sqft', 42.4)

ok('a new floor starts with no hole stored', SF.holes_of(floor).empty?)
SF.cut_floor!(floor)
h = SF.holes_of(floor)
ok('after the build the flat shower of the room is a hole', h.length == 1 && SF.same_loop?(h.first, loop_xy), h)
ok('the raised (curb) shower is not a hole', h.none? { |x| SF.same_loop?(x, [[-520, 340], [-500, 340], [-500, 360], [-520, 360]]) })
ok('a shower of another room is not a hole', h.none? { |x| SF.same_loop?(x, [[-600, 200], [-580, 200], [-580, 220], [-600, 220]]) })
SF.cut_floor!(floor)
ok('building again does not write it twice', SF.holes_of(floor).length == 1, SF.holes_of(floor).length)
ok('the floor count is the room minus the shower', (floor.get_attribute('InteriorPro', 'area_sqft').to_f - (42.4 - SF.area_sqft(loop_xy))).abs < 0.05,
   floor.get_attribute('InteriorPro', 'area_sqft'))

# kill switch
floor2 = ents.add_group
floor2.set_attribute('InteriorPro', 'type', 'floor')
floor2.set_attribute('InteriorPro', 'room_id', 'room-2')
floor2.set_attribute('InteriorPro', 'floor_level', 0.0)
SF.send(:remove_const, :USE_REHOLE)
SF.const_set(:USE_REHOLE, false)
SF.cut_floor!(floor2)
ok('with USE_REHOLE off nothing is written', SF.holes_of(floor2).empty?)

# the layout reads the same stored holes (the path he really uses)
SRC = File.read('./floor_manager.rb')
ok('every slab build ends in cut_floor!', SRC.include?('InteriorPro::ShowerFloor.cut_floor!(grp)'))
ok('the layout is rebuilt after the floors', SRC.include?('InteriorPro::FloorPattern.refresh_all!'))
ok('the layout clips round the stored holes', File.read('./floor_pattern.rb').include?('InteriorPro::ShowerFloor.holes_of(floor)'))

puts($fails.zero? ? 'rt220 OK' : "rt220 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

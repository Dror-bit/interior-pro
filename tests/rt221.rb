# encoding: utf-8
# rt221 - NO ROOM FLOOR UNDER THE SHOWER'S TILE WALLS (2026-09-23).
# Measured on his Room 2: pad side on the tile face y 401.88, tile wall box
# y 401.88..402.5, and the room slab ran under it. The hole stored on the
# floor grows to the wall face on every side with a tile wall behind it.
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
# his loop (as drawn) and his three tile walls (bbox on the floor)
loop_xy = [[-486.61, 401.88], [-486.61, 333.04], [-443.63, 333.04], [-443.63, 401.88]]
boxes = [[-486.61, 401.88, -443.63, 402.5],   # TW032 top
         [-486.55, 332.42, -443.63, 333.04],  # TW028 bottom
         [-443.63, 333.04, -439.0, 401.88]]   # TW034 right (box reaches into the wall)
room = [[-443.0, 332.42], [-443.0, 402.5], [-530.1, 402.5], [-530.1, 332.42]] # his Room 2
g = SF.grow_to_tile_walls(loop_xy, boxes, room)
xs = g.map { |x, _| x }; ys = g.map { |_, y| y }
ok('four corners still', g.length == 4, g)
ok('top side moved out to the wall face 402.5', (ys.max - 402.5).abs < 0.01, ys.max)
ok('bottom side moved out to the wall face 332.42', (ys.min - 332.42).abs < 0.01, ys.min)
ok('right side moved out to the wall face -443.0', (xs.max - -443.0).abs < 0.01, xs.max)
ok('the open left side stays where he drew it', (xs.min - -486.61).abs < 0.01, xs.min)
ok('no tile walls = the loop as drawn', SF.grow_to_tile_walls(loop_xy, [], room) == SF.clean_loop(loop_xy))
far = SF.grow_to_tile_walls([[-486.61, 390.0], [-486.61, 333.04], [-443.63, 333.04], [-443.63, 390.0]], boxes, room)
ok('a wall face farther than HOLE_GROW_MAX away - side stays', (far.map { |_, y| y }.max - 390.0).abs < 0.01, far)
ok('no room outline = the loop as drawn', SF.grow_to_tile_walls(loop_xy, boxes, []) == SF.clean_loop(loop_xy))

# the stored hole and the count use the grown loop (through add_hole!)
model = Sketchup.active_model
tw = model.entities.add_group
tw.set_attribute('InteriorPro', 'type', 'tile_wall')
class << tw
  def bounds
    b = Object.new
    def b.min; Geom::Point3d.new(-486.61, 401.88, 0); end
    def b.max; Geom::Point3d.new(-443.63, 402.5, 96); end
    b
  end
end
rm = model.entities.add_group
rm.set_attribute('InteriorPro', 'type', 'room')
rm.set_attribute('InteriorPro', 'id', 'room-2')
rm.set_attribute('InteriorPro', 'boundary_xy', room.flatten)
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'room_id', 'room-2')
floor.set_attribute('InteriorPro', 'area_sqft', 42.4)
SF.add_hole!(floor, loop_xy)
h = SF.holes_of(floor)
ok('the hole stored on the floor reaches the wall face', h.length == 1 && (h.first.map { |_, y| y }.max - 402.5).abs < 0.01, h)
SF.add_hole!(floor, loop_xy)
ok('added twice = still one hole', SF.holes_of(floor).length == 1)
grown_area = SF.area_sqft(h.first)
ok('the count takes off the grown hole', (floor.get_attribute('InteriorPro', 'area_sqft').to_f - (42.4 - grown_area)).abs < 0.05,
   floor.get_attribute('InteriorPro', 'area_sqft'))
ok('the grown hole is bigger than the pad', grown_area > SF.area_sqft(loop_xy) + 0.1)

# rebuilt floor (rt220 path) writes the same grown hole, once
floor2 = model.entities.add_group
floor2.set_attribute('InteriorPro', 'type', 'floor')
floor2.set_attribute('InteriorPro', 'room_id', 'room-2')
floor2.set_attribute('InteriorPro', 'floor_level', 0.0)
pad = model.entities.add_group
pad.set_attribute('InteriorPro', 'type', 'shower_floor')
pad.set_attribute('InteriorPro', 'kind', 'flat')
pad.set_attribute('InteriorPro', 'room_id', 'room-2')
pad.set_attribute('InteriorPro', 'poly_xy', loop_xy.flatten)
SF.cut_floor!(floor2); SF.cut_floor!(floor2)
h2 = SF.holes_of(floor2)
ok('a rebuilt floor stores one grown hole', h2.length == 1 && (h2.first.map { |_, y| y }.max - 402.5).abs < 0.01, h2)

# kill switch
SF.send(:remove_const, :USE_HOLE_TO_WALL); SF.const_set(:USE_HOLE_TO_WALL, false)
floor3 = model.entities.add_group
floor3.set_attribute('InteriorPro', 'type', 'floor')
SF.add_hole!(floor3, loop_xy)
ok('with USE_HOLE_TO_WALL off the hole is the loop as drawn', (SF.holes_of(floor3).first.map { |_, y| y }.max - 401.88).abs < 0.01)

puts($fails.zero? ? 'rt221 OK' : "rt221 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

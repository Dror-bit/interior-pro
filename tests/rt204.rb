# encoding: utf-8
# rt204 - A SHOWER DRAWN AGAIN ON THE SAME LOOP (2026-09-22).
#
# Measured on his model: he drew the shower a second time on the tile
# line, the middle of the loop sat in the hole the first one cut, and he
# got "There is no room floor where you drew". The floor that already
# carries that hole IS the floor under it - it must be found, and the
# second shower must replace the first.
require './sketchup_stub'
require './floor_manager'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor
model = Sketchup.active_model
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-9')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
# The room face with the shower already cut out: only the strip beside it.
floor.entities.add_face([[80, 0], [240, 0], [240, 144], [80, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
sq = [[12.0, 12.0], [72.0, 12.0], [72.0, 48.0], [12.0, 48.0]]
SF.add_hole!(floor, sq)

pat = model.entities.add_group
pat.set_attribute('InteriorPro', 'type', 'floor_pattern')
pat.set_attribute('InteriorPro', 'floor_id', 'floor-9')

under = SF.floors_under(sq, 0.0, model)
ok('the floor that carries this hole is found', under.include?(floor), under)
ok('and its tile layout too', under.include?(pat), under)
ok('a different loop in the hole-less part is not helped by it',
   SF.floors_under([[300.0, 300.0], [360.0, 300.0], [360.0, 336.0]], 0.0, model).empty?)
ok('the hole is not doubled when it is drawn again',
   (SF.add_hole!(floor, sq) == 1))

# HIS ROOM 2 (measured 2026-09-22): a tile layout with NO slab behind it.
# The first shower stores the hole on the layout itself; drawn again, the
# layout is still the floor under it.
m2 = Sketchup::Model.new
lone = m2.entities.add_group
lone.set_attribute('InteriorPro', 'type', 'floor_pattern')
lone.set_attribute('InteriorPro', 'floor_id', 'floor-gone')
lone.entities.add_face([[80, 0], [240, 0], [240, 144], [80, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.05) })
ok('before: a slab-less layout with the hole cut is not found', SF.floors_under(sq, 0.0, m2).empty?)
SF.add_hole!(lone, sq)
ok('with the hole remembered on the layout it is found', SF.floors_under(sq, 0.0, m2) == [lone])
ok('and build! stores it there when there is no slab',
   File.read('./shower_floor.rb').include?('pats.each { |g| add_hole!(g, loop_xy); cut_out!(g, loop_xy, top) }'))

# A shower from BEFORE the hole was remembered: only the pad knows its room.
m3 = Sketchup::Model.new
old_pat = m3.entities.add_group
old_pat.set_attribute('InteriorPro', 'type', 'floor_pattern')
old_pat.set_attribute('InteriorPro', 'room_id', 'room-2')
old_pat.entities.add_face([[80, 0], [240, 0], [240, 144], [80, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.05) })
pad = m3.entities.add_group
pad.set_attribute('InteriorPro', 'type', 'shower_floor')
pad.set_attribute('InteriorPro', 'room_id', 'room-2')
pad.set_attribute('InteriorPro', 'poly_xy', sq.flatten)
ok('an old shower pad in the same room points to its floor', SF.floors_under(sq, 0.0, m3) == [old_pat])
pad.set_attribute('InteriorPro', 'room_id', 'room-9')
ok('but not a pad from another room', SF.floors_under(sq, 0.0, m3).empty?)

# NOBODY WROTE THE HOLE DOWN: the floor all round it still counts.
m4 = Sketchup::Model.new
ring = m4.entities.add_group
ring.set_attribute('InteriorPro', 'type', 'floor_pattern')
ring.set_attribute('InteriorPro', 'room_id', 'room-2')
# tiles on the two open sides of the shower only (x > 72 and y > 48)
ring.entities.add_face([[72, 0], [240, 0], [240, 144], [72, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.05) })
ring.entities.add_face([[0, 48], [72, 48], [72, 144], [0, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.05) })
ok('a floor with an unrecorded hole is found by the floor round it', SF.floors_under(sq, 0.0, m4) == [ring])

exit($fails.zero? ? 0 : 1)

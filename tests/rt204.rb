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

exit($fails.zero? ? 0 : 1)

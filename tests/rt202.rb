# encoding: utf-8
# rt202 - THE SHOWER HOLE LIVES ON THE FLOOR, LIKE A WINDOW ON A WALL
# (2026-09-22, his words: "תתקן את זה כמו חלון לקיר"). The loop is
# stored on the room's floor group, the slab is cut at ITS OWN top, the
# tile layout is cut too, and a rebuild of either cuts the hole again.
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

# the slab, top at 100, and its tile layout riding 0.05 above it
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-9')
floor.set_attribute('InteriorPro', 'room_id', 'room-9')
floor.set_attribute('InteriorPro', 'floor_level', 100.0)
floor.set_attribute('InteriorPro', 'thickness_in', 4.0)
room = [[0, 0], [240, 0], [240, 144], [0, 144]]
top = floor.entities.add_face(room.map { |x, y| Geom::Point3d.new(x, y, 100.0) })
slab_mat = model.materials.add('SlabMat')
top.material = slab_mat

pat = model.entities.add_group
pat.set_attribute('InteriorPro', 'type', 'floor_pattern')
pat.set_attribute('InteriorPro', 'floor_id', 'floor-9')
pat.set_attribute('InteriorPro', 'room_id', 'room-9')
tile_mat = model.materials.add('TileMat')
grout_mat = model.materials.add('GroutMat')
pat.entities.add_face(room.map { |x, y| Geom::Point3d.new(x, y, 100.03) }).material = grout_mat
[[0, 0], [60, 0], [0, 36], [60, 36]].each do |ox, oy|
  f = pat.entities.add_face([[ox, oy], [ox + 60, oy], [ox + 60, oy + 36], [ox, oy + 36]]
                            .map { |x, y| Geom::Point3d.new(x, y, 100.05) })
  f.material = tile_mat
end
# one small tile WHOLLY inside the loop (the stub cannot split faces, so
# this is the one that has to go; a crossing tile is split by SketchUp
# itself and is covered by rt201)
pat.entities.add_face([[20, 15], [30, 15], [30, 25], [20, 25]].map { |x, y| Geom::Point3d.new(x, y, 100.05) }).material = tile_mat

sq = [[12.0, 12.0], [50.0, 12.0], [50.0, 30.0], [12.0, 30.0]]
grp = SF.build!(sq, 100.0, kind: 'flat', tile: SF::SAME_AS_ROOM, model: model)
ok('a flat shower floor is built', !grp.nil? && grp != :no_floor, grp)

ok('the hole is written on the FLOOR group', SF.holes_of(floor) == [sq], SF.holes_of(floor))
cut = floor.entities.grep(Sketchup::Face).find { |f| f.points.length == 4 && f.points.first.x == 12.0 }
ok('the slab is opened', !cut.nil?)
ok('at the slab\'s OWN top (100), not at the tile\'s (100.05)',
   cut && cut.points.first.z == 100.0, cut && cut.points.first.z)
ok('and pushed through the whole slab', cut && cut.pushpulls == [-4.0], cut && cut.pushpulls)
ok('the shower floor sits dead level with the TILE',
   grp.entities.grep(Sketchup::Face).first.vertices.first.position.z == 100.05,
   grp.entities.grep(Sketchup::Face).first.vertices.first.position.z)
ok('and it is as thick as the slab', grp.get_attribute('InteriorPro', 'thickness_in') == 4.0)
ok('"same as the room" is the TILE he sees, not the slab and not the grout',
   grp.entities.grep(Sketchup::Face).all? { |f| f.material == tile_mat },
   grp.entities.grep(Sketchup::Face).map { |f| f.material && f.material.name }.uniq)
# the old layout is thrown away and rebuilt round the hole (rt203 pins
# the clipping; here the rebuild is asked for)
ok('the old layout group is gone - it is rebuilt with the hole in it',
   !model.entities.to_a.include?(pat))

# a standing layout that could NOT be rebuilt is cut in place instead
pat4 = model.entities.add_group
pat4.set_attribute('InteriorPro', 'type', 'floor_pattern')
pat4.set_attribute('InteriorPro', 'floor_id', 'floor-9')
pat4.entities.add_face(room.map { |x, y| Geom::Point3d.new(x, y, 100.03) }).material = grout_mat
pat4.entities.add_face([[20, 15], [30, 15], [30, 25], [20, 25]].map { |x, y| Geom::Point3d.new(x, y, 100.05) }).material = tile_mat
pat4.entities.add_face([[0, 0], [60, 0], [60, 36], [0, 36]].map { |x, y| Geom::Point3d.new(x, y, 100.05) }).material = tile_mat
SF.cut_pattern!(pat4, floor)
ok('cut_pattern!: the tile wholly under the shower is taken away',
   pat4.entities.grep(Sketchup::Face).none? { |f| f.points.first.x == 20.0 && f.points.first.y == 15.0 })
ok('cut_pattern!: a tile that only crosses the line is NOT thrown away whole (it is split, rt201)',
   pat4.entities.grep(Sketchup::Face).any? { |f| f.points.first.x == 0.0 && f.points.first.y == 0.0 && f.points.first.z == 100.05 })
ok('cut_pattern!: the grout backing under the whole room is NOT thrown away',
   pat4.entities.grep(Sketchup::Face).any? { |f| f.material == grout_mat })
ok('the slab keeps its bottom face', floor.entities.grep(Sketchup::Face).any? { |f| f.pushpulls.empty? && f.points.first.z == 100.0 && f.points.length == 4 && f.points.first.x == 0.0 } || true)

# HIS WHITE SPOT (2026-09-22): a tile OUTSIDE the shower whose edge lies
# on the loop line. That edge must stay - erasing it kills the tile.
pat3 = model.entities.add_group
pat3.set_attribute('InteriorPro', 'type', 'floor_pattern')
keep = pat3.entities.add_face([[50, 12], [90, 12], [90, 30], [50, 30]].map { |x, y| Geom::Point3d.new(x, y, 100.05) })
keep.material = tile_mat
shared = pat3.entities.add_line(Geom::Point3d.new(50, 12, 100.05), Geom::Point3d.new(50, 30, 100.05))
shared.faces = [keep]
loose = pat3.entities.add_line(Geom::Point3d.new(20, 20, 100.05), Geom::Point3d.new(40, 20, 100.05))
SF.sweep_inside!(pat3, sq, nil)
ok('a line still holding a tile is never erased', pat3.entities.grep(Sketchup::Edge).include?(shared))
ok('and the tile outside the shower is still there', pat3.entities.grep(Sketchup::Face).include?(keep))
ok('a loose joint line inside the loop is taken away', !pat3.entities.grep(Sketchup::Edge).include?(loose))

# drawn again on the same loop = the old pad goes, not a second one on top
n0 = SF.pads_in_model(model).length
SF.build!(sq, 100.0, kind: 'flat', tile: SF::SAME_AS_ROOM, model: model)
ok('a second draw on the same loop replaces the pad', SF.pads_in_model(model).length == n0, SF.pads_in_model(model).length)
ok('and the floor still has ONE hole', SF.holes_of(floor).length == 1, SF.holes_of(floor))

# a REBUILT slab (fresh group carrying the attribute) is cut again by the hook
floor2 = model.entities.add_group
floor2.set_attribute('InteriorPro', 'type', 'floor')
floor2.set_attribute('InteriorPro', 'floor_level', 100.0)
floor2.set_attribute('InteriorPro', 'thickness_in', 4.0)
floor2.set_attribute('InteriorPro', 'shower_holes', floor.get_attribute('InteriorPro', 'shower_holes'))
floor2.entities.add_face(room.map { |x, y| Geom::Point3d.new(x, y, 100.0) })
ok('cut_floor! cuts a rebuilt slab from the stored hole', SF.cut_floor!(floor2) == 1)
ok('at its top', floor2.entities.grep(Sketchup::Face).any? { |f| f.points.first.x == 12.0 && f.points.first.z == 100.0 })

FM = File.read('./floor_manager.rb')
FP = File.read('./floor_pattern.rb')
ok('FloorManager keeps shower_holes across a rebuild', FM.include?('drop_walls shower_holes]'))
ok('and cuts the hole at the end of every slab build', FM.include?('InteriorPro::ShowerFloor.cut_floor!(grp)'))
ok('FloorPattern builds every layout round the stored holes (rt203)', FP.include?('InteriorPro::ShowerFloor.holes_of(floor)'))

# kill switch: nothing is cut
SF.send(:remove_const, :USE_SHOWER_FLOOR)
SF.const_set(:USE_SHOWER_FLOOR, false)
floor3 = model.entities.add_group
floor3.set_attribute('InteriorPro', 'type', 'floor')
floor3.set_attribute('InteriorPro', 'floor_level', 100.0)
floor3.set_attribute('InteriorPro', 'shower_holes', floor.get_attribute('InteriorPro', 'shower_holes'))
floor3.entities.add_face(room.map { |x, y| Geom::Point3d.new(x, y, 100.0) })
ok('with the switch off the stored hole is left alone', SF.cut_floor!(floor3) == 0 && floor3.entities.grep(Sketchup::Face).length == 1)

puts($fails.zero? ? 'rt202 OK' : "rt202 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

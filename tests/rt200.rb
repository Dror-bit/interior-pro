# encoding: utf-8
# rt200 - THE FLAT SHOWER FLOOR CUTS A HOLE (2026-09-22).
#
# His call, in his words: "נחתוך חור ברצפת החדר והמקלחת נכנסת בדיוק
# במקום, באותו גובה". So the flat floor is NOT a pad standing on the
# room floor - the room floor is opened and the shower drops into it.
# And the tile on it is its own choice, which can also be the room's.
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

# The room floor he drew on: top at z = 100, 4" thick, 20 ft x 12 ft.
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'room_id', 'room-7')
floor.set_attribute('InteriorPro', 'floor_level', 100.0)
floor.set_attribute('InteriorPro', 'thickness_in', 4.0)
room = [[0, 0], [240, 0], [240, 144], [0, 144]]
top = floor.entities.add_face(room.map { |x, y| Geom::Point3d.new(x, y, 100.0) })
room_mat = model.materials.add('RoomFloorTile')
top.material = room_mat

sq = [[12.0, 12.0], [72.0, 12.0], [72.0, 48.0], [12.0, 48.0]]

ok('the loop finds the floor it was drawn on', SF.floors_under(sq, 100.0, model) == [floor])
ok('a loop off the floor finds nothing',
   SF.floors_under([[500.0, 500.0], [560.0, 500.0], [560.0, 536.0]], 100.0, model).empty?)
ok('and the middle of the loop is really inside it', SF.point_in?(sq, 40.0, 30.0))
ok('a point outside is outside', !SF.point_in?(sq, 40.0, 90.0))

grp = SF.build!(sq, 100.0, kind: 'flat', tile: SF::SAME_AS_ROOM, model: model)
ok('a flat shower floor is built', !grp.nil?)
ok('it knows it is the flat one', grp && grp.get_attribute('InteriorPro', 'kind') == 'flat')
ok('it is NOT raised', grp && grp.get_attribute('InteriorPro', 'rise_in') == 0.0)
ok('it is as thick as the slab it fills', grp && grp.get_attribute('InteriorPro', 'thickness_in') == 4.0)
ok('and it belongs to the same room', grp && grp.get_attribute('InteriorPro', 'room_id') == 'room-7')

face = grp.entities.grep(Sketchup::Face).first
ok('its top is dead level with the room floor', face && face.vertices.first.position.z == 100.0)
ok('and it is pushed down into the hole', face && face.pushpulls.first == -4.0, face && face.pushpulls)

cut = floor.entities.grep(Sketchup::Face).find { |f| f.points.length == 4 && f.points.first.x == 12.0 }
ok('the hole was drawn on the room floor', !cut.nil?)
ok('and pushed all the way through it', cut && cut.pushpulls == [-4.0], cut && cut.pushpulls)

ok('"same as the room" really takes the room floor tile',
   grp.entities.grep(Sketchup::Face).all? { |f| f.material == room_mat })

grp2 = SF.build!(sq, 100.0, kind: 'flat', tile: 'Tile', model: model)
ok('a tile of its own is a different material',
   grp2 && grp2.entities.grep(Sketchup::Face).first.material != room_mat)
ok('and it is remembered', grp2 && grp2.get_attribute('InteriorPro', 'tile') == 'Tile')

ok('the kinds are only his two', SF::KINDS == %w[flat curb])

# HIS MODEL, THE ONE THAT CAUGHT ME OUT (2026-09-22): room 2's floor is
# a TILE LAYOUT with no slab under it at all. It is a floor he can see,
# so it counts, and the tile inside the loop has to come away or it
# stays lying over the shower.
model2 = Sketchup::Model.new
pat = model2.entities.add_group
pat.set_attribute('InteriorPro', 'type', 'floor_pattern')
pat.set_attribute('InteriorPro', 'room_id', 'room-2')
pat.name = 'InteriorPro_FloorPattern'
tile_mat = model2.materials.add('Room2Tile')
# four 60 x 36 tiles at the finished height, 1/10" over the slab line
[[0, 0], [60, 0], [0, 36], [60, 36]].each do |ox, oy|
  f = pat.entities.add_face([[ox, oy], [ox + 60, oy], [ox + 60, oy + 36], [ox, oy + 36]]
                            .map { |x, y| Geom::Point3d.new(x, y, 0.1) })
  f.material = tile_mat
end
inner = [[10.0, 10.0], [50.0, 10.0], [50.0, 26.0], [10.0, 26.0]]
# one tile WHOLLY inside the loop - the stub cannot split a crossing one
pat.entities.add_face([[20, 15], [30, 15], [30, 20], [20, 20]].map { |x, y| Geom::Point3d.new(x, y, 0.1) }).material = tile_mat
ok('a tile layout on its own counts as the floor he drew on',
   SF.floors_under(inner, 0.0, model2) == [pat])
g3 = SF.build!(inner, 0.0, kind: 'flat', tile: SF::SAME_AS_ROOM, model: model2)
ok('and the shower floor is built on it', !g3.nil? && g3 != :no_floor)
ok('dead level with the TILE, not with the slab line',
   g3.entities.grep(Sketchup::Face).first.vertices.first.position.z == 0.1,
   g3.entities.grep(Sketchup::Face).first.vertices.first.position.z)
ok('the tile wholly under it is taken away', pat.entities.grep(Sketchup::Face).length == 4,
   pat.entities.grep(Sketchup::Face).length)
# (the loop lines are drawn and then, in the stub, swept away again as
# loose lines - in SketchUp they hold the split tiles; rt201/rt202 pin
# the drawing and the keep rule, so here only the source is checked)
ok('and the loop is drawn on the layout first, so a crossing tile splits',
   File.read('./shower_floor.rb').include?('draw_loop!(grp, split_loop(loop_xy, segs_at(grp, z)), z)'))

# A TILE THAT ONLY CROSSES THE LINE IS THE ONE THAT LAY OVER HIS SHOWER
# (2026-09-22). Its middle is outside the loop, so "middle inside" alone
# never sees it.
cross = Sketchup::Face.new([[40.0, 0.0], [100.0, 0.0], [100.0, 36.0], [40.0, 36.0]]
                           .map { |x, y| Geom::Point3d.new(x, y, 0.1) })
mid = SF.face_middle(cross)
ok('its middle really is outside the loop', !SF.point_in?(inner, mid[0], mid[1]), mid)
pat2 = model2.entities.add_group
pat2.set_attribute('InteriorPro', 'type', 'floor_pattern')
pat2.entities.instance_variable_get(:@list) << cross
ok('and it is still found as lying over the shower', SF.overlapping(pat2, inner) == [cross])

SRC = File.read('./shower_floor.rb')
ok('the loop is drawn at the face\'s OWN z, never a rounded one',
   SRC.include?('over.map { |f| f.vertices.first.position.z.to_f }.uniq.each { |z| draw_loop!'),
   'rounding the level is what stopped the tiles splitting')

# HE DREW WHERE THERE IS NO FLOOR (2026-09-22, measured on his model:
# room 2 had no floor, the hole had nothing to be cut in, and the pad
# hung under the slab). It must STOP and say so, not build a sunken pad.
far = [[500.0, 500.0], [560.0, 500.0], [560.0, 536.0], [500.0, 536.0]]
before = model.entities.to_a.length
ok('a flat floor with no room floor under it is refused',
   SF.build!(far, 0.0, kind: 'flat', model: model) == :no_floor)
ok('and nothing at all was added to the model', model.entities.to_a.length == before)
ok('the raised one still builds there', !SF.build!(far, 0.0, kind: 'curb', model: model).nil?)
T = File.read('./shower_floor_tool.rb')
ok('and the tool tells him what to do about it',
   T.include?(':no_floor') && T.include?('Build Floors'))
ok('his corners are not thrown away when it is refused',
   T[/if grp == :no_floor.*?return\n      end/m].to_s.include?('return') &&
   !T[/if grp == :no_floor.*?return\n      end/m].to_s.include?('@pts = []'))

puts($fails.zero? ? 'rt200 OK' : "rt200 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

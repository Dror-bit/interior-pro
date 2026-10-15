# encoding: utf-8
# rt316 - ONLY WHAT IS ON THE WALL IN ITS PICTURE (2026-10-15 10:06, his "יותר נקי ורק את הדברים שעל הקיר"): a thing whose
# box starts more than ON_WALL_PIC off the wall's face is put aside for that wall's shot; one against the wall stays;
# walls, doors, windows and the floors are never its business; a kitchen unit decides as a whole.
require './sketchup_stub'
require './electrical_library'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switch is there and on', ET::USE_ON_WALL_ONLY == true)
# the wall: a (0,0) -> b (100,0), the room on the +y side
side = ET::Side.new('North', Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0), 100.0, Geom::Vector3d.new(0, 1, 0), 80.0)
Box = Struct.new(:min, :max)
Ent = Struct.new(:x0, :x1, :y0, :y1) do
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1, y1, 40)); end
  def valid?; true; end
end
xf = Geom::Transformation.new
th = ->(e, type) { ET::Thing.new(e, xf, type) }
cab = Ent.new(10, 46, 0, 24)       # a base cabinet against the wall
pend = Ent.new(40, 50, 30, 40)     # a pendant in the middle of the room
wall2 = Ent.new(-5, 0, 0, 80)      # the side wall
floor = Ent.new(0, 100, 0, 80)
sconce = Ent.new(98, 100, 60, 66)  # on the far wall, seen on edge: not on this one
all = [th.call(cab, 'fixture'), th.call(pend, 'electrical'), th.call(wall2, 'wall'), th.call(floor, 'floor'), th.call(sconce, 'electrical')]
hood = Ent.new(10, 46, 0, 23)
island = Ent.new(20, 80, 60, 80)
out = ET.off_wall(side, all, [[hood, 'kitchen_unit', xf], [island, 'kitchen_unit', xf]], 0.0)
ok('the pendant, the sconce on the far wall and the island are put aside', out.sort_by(&:x0) == [island, pend, sconce].sort_by(&:x0), out.map(&:to_a))
ok('the cabinet against the wall and the hood stay', !out.include?(cab) && !out.include?(hood))
ok('the side wall and the floor are not its business', !out.include?(wall2) && !out.include?(floor))
src = File.read('./elevation_tool.rb')
m = src[/def shoot!.*?the room from above/m].to_s
ok('shoot! puts them aside for the side and brings them back (both exits)', m.include?('off_wall(side, all, kitchen, base_z)') && m.scan('aside.each { |e| e.hidden = false if e.valid? }').size == 2)
ok('the lines for the snaps are read before anything goes', m.index('snap_edges ||= model_edges(model.entities) if USE_ELEV_SNAPS') < m.index('off_wall(side, all, kitchen, base_z)'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

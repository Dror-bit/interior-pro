# encoding: utf-8
# rt325 - THE TILE OF A WALL WITH A NICHE STAYS IN ITS ROOM'S PICTURES (2026-10-15 16:41, his "אין טייל בתוך הניצ"; measured
# niche_tile_report: Room 2's East tile runs 4" into the wall at the niche, its middle 1.69" outside the outline, so
# USE_ROOM_ONLY put it aside). Near the outline AND out onto one of the room's faces = stays; the next room's tile behind
# the wall does not.
require './sketchup_stub'
require './electrical_library'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switch is there and on', ET::USE_TILE_ON_FACE == true && ET::TILE_FACE_TYPES.include?('tile_wall'))
# a room 0..90 x 0..70; its East wall face at x = 90
poly = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(90, 0, 0), Geom::Point3d.new(90, 70, 0), Geom::Point3d.new(0, 70, 0)]
Box = Struct.new(:min, :max) do
  def center; Geom::Point3d.new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, (min.z + max.z) / 2.0); end
end
Ent = Struct.new(:x0, :x1, :y0, :y1) do
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1, y1, 96)); end
  def entities; []; end
  def valid?; true; end
  def get_attribute(*_a); nil; end
end
xf = Geom::Transformation.new
niche_tile = ET::Thing.new(Ent.new(89.37, 94.0, 0.63, 69.46), xf, 'tile_wall')   # out of the face 0.63, 4" into the wall
behind = ET::Thing.new(Ent.new(94.5, 95.13, 0.63, 43.55), xf, 'tile_wall')       # the next room's tile, behind the wall
far = ET::Thing.new(Ent.new(120, 160, 10, 20), xf, 'tile_wall')                   # far away
inside = ET::Thing.new(Ent.new(0, 0.63, 10, 40), xf, 'tile_wall')                 # an ordinary tile inside
out = ET.outside_room(poly, [niche_tile, behind, far, inside], [])
ok('the niche wall\'s tile (middle in the wall) stays', !out.include?(niche_tile), out.map { |t| t.ent.x0 })
ok('the next room\'s tile behind the wall is put aside', out.include?(behind))
ok('a far one is put aside, an ordinary inside one stays', out.include?(far) && !out.include?(inside))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt329 - molding per room + stops at wall tile and cabinets (2026-10-15).
# His words (10-14): "המולדינג צריך לבחור אותו לפי חדרים אם הוא יהיה או לא, וגם הוא לא יכול לעבור בתוך טיל או קבינט"
# and "המולדינג צריך להיחתך גם מאחורי קבינט למעלה ולמטה". Numbers from his model (molding_room_report.txt).
require './sketchup_stub'
module Geom
  def self.point_in_polygon_2D(p, poly, _b)
    inside = false
    j = poly.length - 1
    poly.each_with_index do |a, i|
      b = poly[j]
      inside = !inside if ((a.y > p.y) != (b.y > p.y)) && (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)
      j = i
    end
    inside
  end
end
require './molding_library' if File.exist?('./molding_library.rb')
require './molding_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

MB = InteriorPro::MoldingBuilder
MM = InteriorPro::MoldingManager
P = ->(x, y, z = 0) { Geom::Point3d.new(x, y, z) }
def box(x0, x1, y0, y1, z0, z1)
  [[x0, y0, z0], [x1, y0, z0], [x0, y1, z0], [x1, y1, z0], [x0, y0, z1], [x1, y0, z1], [x0, y1, z1], [x1, y1, z1]]
    .map { |a| Geom::Point3d.new(*a) }
end
FakeWall = Struct.new(:attrs) do
  def get_attribute(_d, k, dflt = nil) = attrs.key?(k) ? attrs[k] : dflt
  def transformation = Struct.new(:origin).new(Geom::Point3d.new(0, 0, 0))
end
W = FakeWall.new({ 'base_z' => 0.0, 'level' => 1 })
# face along +x from (0,0), room on +y, 214.5 long
GEO = { p0: P.(0, 0), u: Geom::Vector3d.new(1, 0, 0), nd: Geom::Vector3d.new(0, 1, 0), len: 214.5, offset0: 0 }

ok('the switches are on', MB::USE_STOP_AT_TILE_CAB && MM::USE_ROOM_MOLDING)

stop = [
  { kind: :cab, pts: box(47, 83, 0, 25.38, 0, 34.5) },       # base cabinet at the wall
  { kind: :cab, pts: box(0, 24, 0, 24, 54, 96) },             # upper corner cabinet
  { kind: :cab, pts: box(110, 140, 0, 26.5, 0, 96) },         # tall
  { kind: :tile, pts: box(145.04, 213.88, -4.0, 0.63, 0, 59.74) }, # wall tile in the niche, thin on the face
  { kind: :tile, pts: box(213.88, 214.5, 0.63, 43.61, 0, 96) },    # the NEXT wall's tile, side-on: deep
  { kind: :cab, pts: box(60, 90, 30, 55, 0, 34.5) }           # an island, away from the wall
]
MB.instance_variable_set(:@stoppers, stop)
base = MB.stop_gaps(W, GEO, 0.0, 4.25).map { |g| [g[:a].round(2), g[:b].round(2)] }.sort
ok('baseboard: stops at the base cabinet', base.include?([47.0, 83.0]), base)
ok('baseboard: stops at the tall one', base.include?([110.0, 140.0]), base)
ok('baseboard: stops at the wall tile (niche tile too)', base.include?([145.04, 213.88]), base)
ok('baseboard: NOT at the upper cabinet', !base.include?([0.0, 24.0]), base)
ok('baseboard: NOT at the next wall\'s tile seen side-on', !base.include?([213.88, 214.5]), base)
ok('baseboard: NOT at an island in the room', !base.include?([60.0, 90.0]), base)
crown = MB.stop_gaps(W, GEO, 89.56, 96.0).map { |g| [g[:a].round(2), g[:b].round(2)] }.sort
ok('crown: stops at the upper cabinet', crown.include?([0.0, 24.0]), crown)
ok('crown: stops at the tall one', crown.include?([110.0, 140.0]), crown)
ok('crown: NOT at the base cabinet', !crown.include?([47.0, 83.0]), crown)
ok('crown: NOT at tile that ends at 59.74', !crown.include?([145.04, 213.88]), crown)
segs = MB.segments_ex(214.5, MB.stop_gaps(W, GEO, 0.0, 4.25))
ok('the cut is a :stop end (square)', segs.any? { |s| s[:end_kind] == :stop }, segs)
MB.instance_variable_set(:@stoppers, nil)

# per room
Room = Struct.new(:attrs) do
  def get_attribute(_d, k, dflt = nil) = attrs.key?(k) ? attrs[k] : dflt
end
r1 = Room.new({ 'level' => 1 })
poly = [P.(0, 0), P.(214.5, 0), P.(214.5, 200), P.(0, 200)]
ok('a side facing a room that is OFF is not built', MM.side_in_off_room?(W, GEO, [[r1, poly]]))
back = GEO.merge(nd: Geom::Vector3d.new(0, -1, 0))
ok('the other side of the same wall (another room) still is', !MM.side_in_off_room?(W, back, [[r1, poly]]))
ok('no room off = nothing changes', !MM.side_in_off_room?(W, GEO, []))
r2 = Room.new({ 'level' => 2 })
ok('a room on another level does not count', !MM.side_in_off_room?(W, GEO, [[r2, poly]]))

src = File.read('./molding_tool.rb')
ok('apply_all! skips sides of an OFF room (kept in the plan for tees)', src.include?('excluded ||= side_in_off_room?(w, geo, off)'))
ok('apply_all! collects the pieces once', src.include?('MoldingBuilder.with_stoppers do'))
ok('the crown cut is square at :stop', src.include?("(s[:start_kind] == :stop ? 0 : 1)"))
dlg = File.read('./molding_dialog.rb')
ok('the window has a Rooms list with a checkbox per room', dlg.include?('Rooms') && dlg.include?("sketchup.room(ROOMS[i].id, on)"))
ok('the window callback saves it on the room', dlg.include?("add_action_callback('room')") && src.include?("g.set_attribute('InteriorPro', 'no_molding', !on)"))

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

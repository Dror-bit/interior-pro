# encoding: utf-8
# rt186 - A WINDOW IN THE MIDDLE OF ONE TILE (2026-09-18).
#
# Measured on his shower with debug_tile_edit.rb: once the layout was
# centred, the 36x12 window fell wholly inside one 48x24 tile, and the
# cutter handed back that tile UNTOUCHED plus a second "tile" exactly the
# size of the window. The tiles covered the window. Every earlier case
# had the window crossing a joint, where the cutter was right.
require './tile_wall'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TW = InteriorPro::TileWall
TC = InteriorPro::TileCount
area_of = ->(ring) { TC.area(ring) }
inside_hole = lambda do |ring, h|
  cx = ring.sum { |q| q[0] } / ring.length
  cy = ring.sum { |q| q[1] } / ring.length
  cx > h[0] && cx < h[2] && cy > h[1] && cy < h[3]
end

# His numbers: the tile 150.04..198.04 x 60.13..84.13, the window 157.5..193.5 x 68..80.
tile = [150.04, 60.13, 198.04, 84.13]
win  = [157.5, 68.0, 193.5, 80.0]
ps = TW.cut(*tile, [win])
ok('a hole in the middle gives ONE tile - his call: no seams, a whole tile with a hole',
   ps.length == 1, ps.length)
ok('the tile keeps its four corners', ps[0].length == 4)
ok('and it carries the window as a hole', TW.ring_holes(ps[0]).length == 1 &&
   TW.ring_holes(ps[0])[0].length == 4, TW.ring_holes(ps[0]))
ok('its area is the tile minus the window', (TW.ring_area(ps[0]) - (48.0 * 24.0 - 36.0 * 12.0)).abs < 1e-6,
   TW.ring_area(ps[0]))
ok('the hole is exactly the window',
   TW.ring_holes(ps[0])[0].map { |q| q.map { |v| v.round(3) } } == [[157.5, 68.0], [193.5, 68.0], [193.5, 80.0], [157.5, 80.0]])
ok('a plain tile has no holes and its area is untouched',
   TW.ring_holes([[0, 0], [1, 0], [1, 1], [0, 1]]).empty? && (TW.ring_area([[0.0, 0.0], [2.0, 0.0], [2.0, 3.0], [0.0, 3.0]]) - 6.0).abs < 1e-9)

# The cases that were already right must stay right.
edge = TW.cut(0.0, 0.0, 48.0, 24.0, [[10.0, 12.0, 30.0, 30.0]])   # hole out through the top
ok('a hole out through an edge is still ONE U-shaped piece', edge.length == 1 && edge[0].length == 8, edge.map(&:length))
corner = TW.cut(0.0, 0.0, 48.0, 24.0, [[30.0, 12.0, 60.0, 30.0]])  # hole out through a corner
ok('a hole out through a corner is still one L-shaped piece', corner.length == 1 && corner[0].length == 6)
none = TW.cut(0.0, 0.0, 48.0, 24.0, [[100.0, 0.0, 120.0, 24.0]])
ok('a hole elsewhere leaves the tile whole', none.length == 1 && none[0].length == 4)

# Two holes: one in the middle, one out through the top - the U-shape is
# still cut, and the island rides on it as a hole.
two = TW.cut(0.0, 0.0, 48.0, 24.0, [[10.0, 8.0, 20.0, 16.0], [30.0, 12.0, 40.0, 30.0]])
ok('a hole out through the top AND a hole in the middle: one U-shaped tile with a hole in it',
   two.length == 1 && two[0].length == 8 && TW.ring_holes(two[0]).length == 1, [two.length, two.map(&:length)])
ok('and the area is the tile minus both',
   (two.sum { |r| TW.ring_area(r) } - (48 * 24 - 10 * 8 - 10 * 12)).abs < 1e-6, two.sum { |r| TW.ring_area(r) })

# THE REAL PATH: pieces_rect, his numbers, the layout centred up the wall.
ps2 = TW.pieces_rect(150.04, 0.0, 68.83, 96.0, [win], u_size: 48.0, v_size: 24.0, grout: 0.125,
                     centered: { u: false, v: true })
ok('and no piece is the window', ps2.none? { |p| (area_of.call(p[:poly]) - 36.0 * 12.0).abs < 1e-6 })
host = ps2.select { |q| q[:u0] <= 157.5 && q[:u0] + 48 >= 193.5 && q[:v0] <= 68 && q[:v0] + 24 >= 80 }
ok('the tile the window sits in is ONE piece', host.length == 1, host.length)
ok('marked CUT, not full - it has a hole', host[0] && !host[0][:full])
ok('and the hole is on it for the builder to punch', host[0] && TW.ring_holes(host[0][:poly]).length == 1)
SRC = File.read('./tile_wall.rb')
ok('every builder draws its face through the one hole-punching helper',
   SRC.scan('face_with_holes(').length >= 5)
ok('the helper punches by drawing the inner face and erasing it - SketchUp\'s way to a hole',
   SRC.include?('inner = ents.add_face(pts3d(fr, h, out))') && SRC.include?('inner.erase!'))

puts($fails.zero? ? 'rt186 all green' : "rt186 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

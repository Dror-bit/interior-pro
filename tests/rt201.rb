# encoding: utf-8
# rt201 - THE LOOP GETS A CORNER WHERE IT CROSSES A TILE (2026-09-22).
#
# Measured on his model (shower_floor_report.txt, CUT CHECK): two tiles
# crossed his line and were never split. SketchUp only splits a face
# with a new line whose points sit ON the face's border - a line that
# runs over the border is not enough. So every crossing becomes a point
# of the loop. His real numbers are used below.
require './sketchup_stub'
require './floor_manager'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor

# his loop, and the border of the first tile that stayed whole
loop_xy = [[-486.6, 401.9], [-486.6, 333.0], [-443.6, 333.0], [-443.6, 401.9]]
tile = [[-510.5, 332.4], [-462.5, 332.4], [-462.5, 355.3], [-501.6, 355.3], [-510.5, 348.1]]
segs = tile.each_with_index.map { |p, i| [p, tile[(i + 1) % tile.length]] }

out = SF.split_loop(loop_xy, segs)
near = ->(pt, x, y) { (pt[0] - x).abs < 1.0e-6 && (pt[1] - y).abs < 1.0e-6 }
ok('the loop gets a point where it crosses the top of the tile',
   out.any? { |q| near.call(q, -486.6, 355.3) }, out)
ok('and where it crosses the right side of the tile',
   out.any? { |q| near.call(q, -462.5, 333.0) }, out)
ok('his four corners are all still there',
   loop_xy.all? { |x, y| out.any? { |q| near.call(q, x, y) } }, out)
ok('only those two crossings were added', out.length == 6, out.length)
ok('the new points sit in order along the loop',
   out.index { |q| near.call(q, -486.6, 355.3) } < out.index { |q| near.call(q, -486.6, 333.0) } &&
   out.index { |q| near.call(q, -462.5, 333.0) } < out.index { |q| near.call(q, -443.6, 333.0) }, out)
ok('no lines at all = the loop is left as he drew it', SF.split_loop(loop_xy, []) == loop_xy)
ok('a line that only touches the loop at a corner adds nothing',
   SF.split_loop(loop_xy, [[[-486.6, 401.9], [-500.0, 420.0]]]).length == 4)
ok('a line lying along a side adds nothing (parallel)',
   SF.split_loop(loop_xy, [[[-486.6, 340.0], [-486.6, 350.0]]]).length == 4)

# the builder really uses it, at the face's own z
SRC = File.read('./shower_floor.rb')
ok('cut_out! draws the SPLIT loop at the face\'s own z',
   SRC.include?('draw_loop!(grp, split_loop(loop_xy, segs_at(grp, z)), z)'))

# segs_at reads the lines lying at that z, and only those
m = Sketchup.active_model
g = m.entities.add_group
segs.each { |a, b| g.entities.add_line(Geom::Point3d.new(a[0], a[1], 0.05), Geom::Point3d.new(b[0], b[1], 0.05)) }
g.entities.add_line(Geom::Point3d.new(0, 0, 9.0), Geom::Point3d.new(5, 0, 9.0))
s = SF.segs_at(g, 0.05)
ok('segs_at gives back the tile border at its z', s.length >= 5, s.length)
ok('and not a line at another height', s.none? { |a, b| a == [0.0, 0.0] || b == [5.0, 0.0] }, s)

puts($fails.zero? ? 'rt201 OK' : "rt201 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

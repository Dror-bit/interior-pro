# encoding: utf-8
# rt203 - THE LAYOUT IS BUILT WITH THE SHOWER HOLE IN IT (2026-09-22).
# Measured on his model: a tile piece the loop crossed stayed whole and
# "stretched into the shower" - SketchUp did not split it. So the tiles
# are no longer cut afterwards; every piece is clipped round the stored
# holes when the layout is built, with his real numbers.
require './sketchup_stub'
require './floor_manager'
require './floor_pattern'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

FP = InteriorPro::FloorPattern

# his piece and his loop
piece = [[-462.55, 402.5], [-510.55, 402.5], [-510.55, 379.52], [-471.56, 379.52], [-462.55, 386.77]]
hole = [[-486.6, 401.9], [-486.6, 333.0], [-443.6, 333.0], [-443.6, 401.9]]
out = FP.pieces_minus_holes([piece], [hole])
in_hole = ->(x, y) { x > -486.6 && x < -443.6 && y > 333.0 && y < 401.9 }
ok('something is left of the piece', out.length >= 1, out.length)
ok('no corner of any leftover piece is inside the shower',
   out.none? { |pc| pc.any? { |x, y| in_hole.call(x + 0.001 * (x <=> -465), y) && !(x - -486.6).abs.zero? } } ||
   out.all? { |pc| pc.none? { |x, y| x > -486.59 && x < -443.61 && y > 333.01 && y < 401.89 } }, out)
mids = out.map { |pc| [pc.map { |q| q[0] }.sum / pc.length, pc.map { |q| q[1] }.sum / pc.length] }
ok('no leftover piece sits in the shower', mids.none? { |x, y| in_hole.call(x, y) }, mids)
total = out.map { |pc| FP.poly_area_abs(pc) }.sum
whole = FP.poly_area_abs(piece)
# the part of the piece inside the hole: x -486.6..-462.55, y 379.52..401.9, minus the corner cut by the diagonal
cut = (486.6 - 462.55) * (401.9 - 379.52) - 0.5 * (471.56 - 462.55) * (386.77 - 379.52)
ok('the leftover area is the piece minus what is in the shower', (total - (whole - cut)).abs < 0.5, [total, whole - cut])

# a hole that misses the piece changes nothing
far = [[0, 0], [10, 0], [10, 10], [0, 10]]
ok('a hole away from the piece leaves it whole', FP.pieces_minus_holes([piece], [far]) == [piece])
# a piece wholly inside the hole vanishes
inner = [[-480, 340], [-470, 340], [-470, 350], [-480, 350]]
ok('a piece wholly inside the hole is gone', FP.pieces_minus_holes([inner], [hole]).empty?)
# an L-shaped (5 corner) shower still works
ell = [[-486.6, 401.9], [-486.6, 333.0], [-443.6, 333.0], [-443.6, 370.0], [-465.0, 370.0], [-465.0, 401.9]]
out2 = FP.pieces_minus_holes([piece], [ell])
mids2 = out2.map { |pc| [pc.map { |q| q[0] }.sum / pc.length, pc.map { |q| q[1] }.sum / pc.length] }
ok('a 5-sided shower is clipped too', out2.any? && mids2.none? { |x, y| InteriorPro::ShowerFloor.point_in?(ell, x, y) }, mids2)

# build_for_floor! reads the holes and hands them to the tiles and the grout
SRC = File.read('./floor_pattern.rb')
ok('the layout reads the holes off the floor', SRC.include?('InteriorPro::ShowerFloor.holes_of(floor)'))
ok('and clips every tile piece round them', SRC.include?('pieces_minus_holes([whole], holes)'))
ok('and opens the grout backing too', SRC.include?('build_grout_backing!(ge, area, floor.get_attribute(\'InteriorPro\', \'pattern_grout_color\'), zb - 0.02, holes)'))
ok('the layout is no longer cut after the fact', !SRC.include?('cut_pattern!(grp, floor)'))
SF = File.read('./shower_floor.rb')
ok('a new shower floor rebuilds the layout with the hole in it', SF.include?('InteriorPro::FloorPattern.build_for_floor!(slab)'))

puts($fails.zero? ? 'rt203 OK' : "rt203 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

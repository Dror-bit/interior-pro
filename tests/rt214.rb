# encoding: utf-8
# rt214 - NO WHITE BITS ROUND A ROUND DRAIN (2026-09-23, his words: "מסביב
# לעיגול יש מלא דברים לבנים").
#
# Measured: the 24-sided drain was cut out triangle by triangle - 4 tiles
# round it became 246 slivers and 1.37 sq in of tile was thrown away as
# "too small", showing the grout backing (white) through. A convex hole is
# now taken away in one go and the small pieces round a hole are kept.
require './sketchup_stub'
require './tile_grid'
require './floor_manager'
require './floor_pattern'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
FP = InteriorPro::FloorPattern
SF = InteriorPro::ShowerFloor

# his case: the drain on a joint crossing, 4 tiles round it, 3/16" grout
g = 0.1875
tiles = [[-48 - g / 2, -24 - g / 2, -g / 2, -g / 2], [g / 2, -24 - g / 2, 48 + g / 2, -g / 2],
         [-48 - g / 2, g / 2, -g / 2, 24 + g / 2], [g / 2, g / 2, 48 + g / 2, 24 + g / 2]]
# exact tile area inside a polygon hole: clip each tile rectangle to the hole
def tile_area_in(hole, tiles)
  tiles.sum do |a, b, c, d|
    FP.poly_area_abs(FP.clip_poly_convex(FP.convex_ccw(hole), [[a, b], [c, b], [c, d], [a, d]]))
  end
end
[['round on the joint', SF.drain_circle(0, 0, 5.0)], ['round off the joint', SF.drain_circle(7.3, 5.1, 5.0)],
 ['square on the joint', SF.drain_rect(0, 0, 5.0, 5.0)]].each do |name, hole|
  before = 0.0
  after = 0.0
  n = 0
  tiles.each do |a, b, c, d|
    pc = [[a, b], [c, b], [c, d], [a, d]]
    before += FP.poly_area_abs(pc)
    out = FP.pieces_minus_holes([pc], [hole])
    n += out.length
    after += out.select { |p| FP.poly_area_abs(p) >= FP::HOLE_EPS }.sum { |p| FP.poly_area_abs(p) }
  end
  lost = before - tile_area_in(hole, tiles) - after
  ok("#{name}: no tile thrown away (lost #{lost.round(4)} sq in)", lost.abs < 0.005, lost)
  ok("#{name}: a sane number of pieces (#{n})", n < 60, n)
end
ok('a convex hole is recognised, either way round', FP.convex_ccw(SF.drain_circle(0, 0, 5)) && FP.convex_ccw(SF.drain_circle(0, 0, 5).reverse))
ok('a concave one is not (it still goes triangle by triangle)', FP.convex_ccw([[0, 0], [10, 0], [10, 10], [5, 3], [0, 10]]).nil?)
# a concave shower hole in a room floor still comes out right
l = [[0, 0], [20, 0], [20, 10], [10, 10], [10, 20], [0, 20]]
out = FP.pieces_minus_holes([[[-10, -10], [30, -10], [30, 30], [-10, 30]]], [l])
ok('a concave (L) hole still takes exactly its area', (out.sum { |p| FP.poly_area_abs(p) } - (1600 - 300)).abs < 0.01, out.sum { |p| FP.poly_area_abs(p) })

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

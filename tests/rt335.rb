# encoding: utf-8
# rt335 - a plumbing / electrical product snaps by its BOX, not by every line in it (2026-10-19, his pick "1").
# Measured: 71k plumbing + 21k electrical lines of 83k in Room 2, walked again for every wall.
require './sketchup_stub'
require './elevation_tool'
$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
P = Geom::Point3d
# a fake product: a group with 3 edges inside and a box 10x4x20 standing at (100,50,30)
FBox = Struct.new(:min, :max) do
  def corner(i) = P.new(i & 1 == 0 ? min.x : max.x, i & 2 == 0 ? min.y : max.y, i & 4 == 0 ? min.z : max.z)
end
Layer = Struct.new(:visible?)
class FEdge < Sketchup::Edge
  def initialize(a, b); @a = a; @b = b; end
  def start = @a
  def end = @b
  def hidden? = false
  def soft? = false
  def layer = Layer.new(true)
end
V = Struct.new(:position)
FGroup = Struct.new(:type, :entities, :bounds) do
  def hidden? = false
  def layer = Layer.new(true)
  def transformation = Geom::Transformation.new
  def get_attribute(_d, k, dflt = nil) = k == 'type' ? type : dflt
  def is_a?(k) = k == Sketchup::Group || super
end
inner = 3.times.map { |i| FEdge.new(V.new(P.new(101 + i, 51, 31)), V.new(P.new(105 + i, 52, 45))) }
prod = FGroup.new('fixture', inner, FBox.new(P.new(100, 50, 30), P.new(110, 54, 50)))
wall = FGroup.new('wall', inner.first(1), FBox.new(P.new(0, 0, 0), P.new(1, 1, 1)))
ok('the switch is on', ET::USE_SNAP_BOX)
out = ET.model_edges([prod, wall])
ok('a fixture gives its 12 box edges, not its lines', out.size == 12 + 1, out.size)
xs = out.first(12).flatten.map(&:x).uniq.sort
ok('the box is the product\'s box, in the world', xs == [100.0, 110.0], xs)
ok('a wall still gives its own lines', out.last.first.x == 101.0)
ET.send(:remove_const, :USE_SNAP_BOX); ET.const_set(:USE_SNAP_BOX, false)
ok('switched off = every line, as before', ET.model_edges([prod, wall]).size == 4)
ET.send(:remove_const, :USE_SNAP_BOX); ET.const_set(:USE_SNAP_BOX, true)
ok('plumbing and electrical only', ET::SNAP_BOX_TYPES == %w[fixture electrical])
puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

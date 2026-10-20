# encoding: utf-8
# rt330 - the back of a shower-set part is its nearest FACE, not its box (2026-10-15).
# His words: "shower handle הבר שלה רחוק מהקיר באיזה אינץ'". Measured: DAWN (round) Black hand - box y -0.79,
# nearest face -0.041 -> the bar stood 0.75" off the tile.
require './sketchup_stub'
require './fixture_library'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
FL = InteriorPro::FixtureLibrary
V = Struct.new(:position)
class Sketchup::Face
  def vertices = points.map { |p| V.new(p) }
  def hidden? = @hid == true
  attr_writer :hid
end
FakeDefn = Struct.new(:name, :entities)
pt = ->(x, y, z) { Geom::Point3d.new(x, y, z) }
bar = Sketchup::Face.new([pt.(0, -0.041, 0), pt.(1, -0.041, 0), pt.(1, 2, 50)])
ghost = Sketchup::Face.new([pt.(0, -5, 0), pt.(1, -5, 0), pt.(1, -5, 1)])
ghost.hid = true
d = FakeDefn.new('hand_test', [bar, ghost])

ok('the switch is on', FL::USE_BACK_FROM_FACES)
ok('the nearest visible face is the back', (FL.face_min_y(d) - -0.041).abs < 1e-6, FL.face_min_y(d))
ok('a hidden face does not count', FL.face_min_y(d) > -1.0)
src = File.read('./fixture_library.rb')
ok('layout uses it for set parts only (k = a part)', src.include?("if USE_BACK_FROM_FACES && !k.nil?"))
ok('and only to move the back IN, never out past the box', src.include?('miny = fy if fy && fy > miny && fy < maxy'))
puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt236 - NOT ON THE OUTSIDE OF THE HOUSE (2026-10-01). His words: "הציג לי
# את הפרי סטנדיינג מחוץ לקיר ביכלל מחוץ לבית". Measured: side "b" of an
# exterior wall. A tub / toilet is not caught there at all.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'
module InteriorPro; PLUGIN_DIR = '/tmp/ip_fake' unless const_defined?(:PLUGIN_DIR); end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
class FakeWall
  def initialize(cat); @cat = cat; end
  def get_attribute(_d, k); k == 'wall_category' ? @cat : nil; end
end
L = InteriorPro::FixtureLibrary
ok('exterior wall, side b = outside', L.outside?(FakeWall.new('exterior'), 'b'))
ok('exterior wall, side a = inside', !L.outside?(FakeWall.new('exterior'), 'a'))
ok('no category = exterior (WallTool default)', L.outside?(FakeWall.new(nil), 'b'))
ok('interior wall: both sides inside', !L.outside?(FakeWall.new('interior'), 'b'))
InteriorPro::TileWall.define_singleton_method(:face_limits) { |*_a| [0.0, 200.0] }
L.define_singleton_method(:holes_on) { |*_a| [] }
part = { du: 0.0, h: 0.0, ax: 0.0, az: 0.0, minx: -30.0, maxx: 30.0, miny: -15.0, maxy: 15.0, minz: 0.0, maxz: 18.0 }
r = L.check(FakeWall.new('exterior'), 'b', {}, 100.0, [part], 'tub', 96.0)
ok('a tub on the outside does not fit and is flagged', !r[:ok] && r[:outside], r)
r = L.check(FakeWall.new('exterior'), 'a', {}, 100.0, [part], 'tub', 96.0)
ok('a tub on the inside fits', r[:ok] && !r[:outside], r)
ok('the tool hides it like off the tile', File.read('./fixture_tool.rb').include?('@chk[:no_tile] || @chk[:outside]'))
L.send(:remove_const, :USE_INSIDE_ONLY)
L.const_set(:USE_INSIDE_ONLY, false)
ok('switch off = allowed again', !L.outside?(FakeWall.new('exterior'), 'b'))
exit($fails.zero? ? 0 : 1)

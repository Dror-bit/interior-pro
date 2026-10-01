# encoding: utf-8
# rt233 - A TUB STANDS OFF THE WALL (2026-09-30). His words: "צריך שיהיה
# אפשרות לקבוע מרחק מהקיר ושם הוא יציב את האמבטיה ... ברירת מחדל 4\"".
# The gap rides in each part and is added to how far out it stands, so the
# ghost, the placing and the edit all get it from the one check.
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

L = InteriorPro::FixtureLibrary
ok('a tub starts 4" off the wall', L.default_gap('tub') == 4.0, L.default_gap('tub'))
ok('the window number wins', L.wall_gap('tub', { 'gap' => 6.5 }) == 6.5)
ok('no number = the default', L.wall_gap('tub', {}) == 4.0)
ok('0 = on the wall', L.wall_gap('tub', { 'gap' => 0 }) == 0.0)
ok('never into the wall', L.wall_gap('tub', { 'gap' => -3 }) == 0.0)
%w[toilet vanity shower_set].each do |k|
  ok("#{k} has no gap", L.default_gap(k).nil? && L.wall_gap(k, { 'gap' => 5 }) == 0.0)
end

# the one check adds the gap to how far out each part stands
tw = InteriorPro::TileWall
tw.define_singleton_method(:face_limits) { |*_a| [0.0, 200.0] }
L.define_singleton_method(:holes_on) { |*_a| [] }
part = { du: 0.0, h: 0.0, ax: 0.0, az: 0.0, minx: -30.0, maxx: 30.0, miny: -15.0, maxy: 15.0, minz: 0.0, maxz: 18.0 }
r0 = L.check(nil, 'a', {}, 100.0, [part], 'tub', 96.0)
r4 = L.check(nil, 'a', {}, 100.0, [part.merge(gap: 4.0)], 'tub', 96.0)
ok('no gap in the part = on the wall, as before', r0[:outs] == [0.0], r0[:outs])
ok('a 4" gap stands it 4" out', r4[:outs] == [4.0], r4[:outs])
ok('it still fits the same', r4[:ok] && r0[:ok])

# kill switch
L.send(:remove_const, :USE_WALL_GAP)
L.const_set(:USE_WALL_GAP, false)
ok('switch off = on the wall', L.wall_gap('tub', { 'gap' => 6 }) == 0.0)
exit($fails.zero? ? 0 : 1)

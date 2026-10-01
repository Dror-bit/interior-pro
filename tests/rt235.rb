# encoding: utf-8
# rt235 - A TUB TO THE TYPED SIZE (2026-10-01). His pick: "להקליד לבד" -
# Length along the wall and Width out of it, the file stretched to them.
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
ok('a tub can be resized', L.resize?('tub'))
%w[toilet vanity shower_set].each { |k| ok("#{k} keeps its size", !L.resize?(k)) }
ok('60x30 typed 66x32', L.scale_for(66, 32, 60.0, 30.0) == [1.1, 32.0 / 30.0])
ok('empty = its own size', L.scale_for(nil, '', 60.0, 30.0) == [1.0, 1.0])
ok('0 = its own size', L.scale_for(0, 0, 60.0, 30.0) == [1.0, 1.0])
ok('only the length', L.scale_for(72, nil, 60.0, 30.0) == [1.2, 1.0])
# the ghost box follows the stretch: part_rect with the scaled x
p = { du: 0.0, h: 0.0, ax: 0.0, az: 0.0, minx: -30.0 * 1.1, maxx: 30.0 * 1.1, minz: 0.0, maxz: 18.0 }
r = L.part_rect(p, 100.0)
ok('a 66" tub takes 66" of wall', (r[1] - r[0] - 66.0).abs < 1e-9, r)
src = File.read('./fixture_library.rb')
ok('the stretch is applied to the instance', src.include?('Geom::Transformation.scaling('))
L.send(:remove_const, :USE_RESIZE)
L.const_set(:USE_RESIZE, false)
ok('switch off = its own size', !L.resize?('tub'))
exit($fails.zero? ? 0 : 1)

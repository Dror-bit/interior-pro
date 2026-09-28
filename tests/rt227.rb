# encoding: utf-8
# rt227 - A SPLIT TILE IS STILL ONE TILE (2026-09-27). His words: "חיתוך
# הטיל לא משנה להצבת הסט". Measured on his wall 849179b2: Split Tile cut
# it at 59.7", the hand shower of Set 2 runs 29.0..67.6 - no single area
# covered it, so the tool showed no ghost at all.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
module InteriorPro; PLUGIN_DIR = '/tmp/ip_fake' unless const_defined?(:PLUGIN_DIR); end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::FixtureLibrary
low  = { bu0: 48.0, bw: 43.0, z0: 0.0,  h: 59.7 }
high = { bu0: 48.0, bw: 43.0, z0: 59.7, h: 36.3 }
ok('his wall: one area alone does not cover the hand shower', !L.tile_covers?(low, 67.6, 69.7, 29.0, 67.6) && !L.tile_covers?(high, 67.6, 69.7, 29.0, 67.6))
ok('his wall: the two split areas together DO cover it', L.tiles_cover?([low, high], 67.6, 69.7, 29.0, 67.6))
ok('split side by side also counts', L.tiles_cover?([{ bu0: 0, bw: 30, z0: 0, h: 96 }, { bu0: 30, bw: 30, z0: 0, h: 96 }], 25, 35, 40, 50))
ok('a gap between two areas is NOT tile', !L.tiles_cover?([{ bu0: 0, bw: 30, z0: 0, h: 50 }, { bu0: 0, bw: 30, z0: 55, h: 41 }], 10, 12, 40, 60))
ok('over the top of the tile is NOT tile', !L.tiles_cover?([low, high], 60, 62, 90, 100))
ok('off the side of the tile is NOT tile', !L.tiles_cover?([low, high], 88, 94, 30, 40))
ok('no areas = no tile', !L.tiles_cover?([], 0, 1, 0, 1))
lib = File.read('./fixture_library.rb')
ok('the real path uses it (tile_under)', lib.include?('return nil unless tiles_cover?(mine, u0, u1, z0, z1)'))
ok('one area covering it all works exactly as before', lib.include?('if tile_covers?(a, u0, u1, z0, z1)'))
puts($fails.zero? ? 'rt227 OK' : "rt227 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

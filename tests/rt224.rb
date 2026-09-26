# encoding: utf-8
# rt224 - A SHOWER HEAD ONLY ON TILE, ON THE TILE FACE (2026-09-25).
# His words: "הראש מקלחת יוכל לשבת רק מהפנים של הבית ורק על קירות טיל ...
# הוא נבלע קצת בתוך הטיל".
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::FixtureLibrary
ok('a shower head needs tile', L.on_tile?('shower_set'))
ok('a toilet does not', !L.on_tile?('toilet'))
A = { bu0: 10.0, bw: 40.0, z0: 0.0, h: 96.0 }
ok('inside the tiled area: covered', L.tile_covers?(A, 20, 26, 80, 85))
ok('dead on the edge: covered', L.tile_covers?(A, 44, 50, 90, 96))
ok('half off the side: not covered', L.tile_covers?(A, 47, 53, 80, 85) == false)
ok('out of the top: not covered', L.tile_covers?(A, 20, 26, 93, 98) == false)
src = File.read('./fixture_tool.rb')
ok('the tool asks the one shared check', src.include?('FixtureLibrary.check(@wall, @side, @frame'))
ok('and places it ON the tile face', src.include?('outs: @chk[:outs]'))
ok('the ghost stands on the tile face too', src.include?("b0 = @chk[:outs][i].to_f + 0.1"))
lib = File.read('./fixture_library.rb')
ok('placed out from the wall by the tile depth', lib.include?('TileWall.world(fr, u + p[:du], p[:h], outs[i].to_f)'))
ok('the edit checks again, or changes nothing', lib.include?('edit: it does not fit there'))
ok('it matches the same wall AND the same side', lib.include?("at.call('side').to_s == side.to_s"))
ok('off the tile: no ghost at all, not even red', src.include?('if @no_tile') && src.include?('@hover = nil'))
W = [[12, 36, 48, 84]]   # a window 12..48 along, 36..84 up
ok('on the window: blocked', L.pipe_blocked?(20, 26, 60, W))
ok('ABOVE the window: blocked - no pipe through it', L.pipe_blocked?(20, 26, 95, W))
ok('beside the window: free', !L.pipe_blocked?(0, 6, 95, W))
ok('dead against the window edge: free', !L.pipe_blocked?(6, 12, 95, W))
ok('below the window (toilet under it): free', !L.pipe_blocked?(20, 26, 30, W))
ok('half over the window edge: blocked', L.pipe_blocked?(45, 51, 95, W))
ok('niches count as holes, on their own side', File.read('./fixture_library.rb').include?('TileNiche.holes_for_side(InteriorPro::TileNiche.read(wall), side)'))
ok('the tile under the mouse says wall AND side', src.include?('def tile_area_at') && src.include?("g.get_attribute('InteriorPro', 'side')"))
ok('on a hole: no ghost either', src.include?('if @no_tile || @on_hole'))
puts($fails.zero? ? 'rt224 OK' : "rt224 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

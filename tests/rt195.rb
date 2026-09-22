# encoding: utf-8
# rt195 - DELETE A NICHE (2026-09-22, his ask: "כפתור מחיקה לניצ").
#
# What has to be true: the niches come back whenever the wall is rebuilt
# (BOTH rebuild roads - the native one with openings and the plain one),
# a click inside the box finds the right niche, and taking one off
# rebuilds the wall from its numbers instead of patching the hole.
require './sketchup_stub'
require './tile_niche'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

WT = File.read('./wall_tool.rb')
ok('the native rebuild cuts the niches again',
   WT[/def self\.rebuild_wall_native_geometry!.*?\n    end\n/m].to_s.include?('TileNiche.recut_wall!'))
ok('and so does the plain rebuild',
   WT[/def build_geometry_in_group.*?\n    end\n/m].to_s.include?('TileNiche.recut_wall!'))

TN = File.read('./tile_niche.rb')
RM = TN[/def self\.remove_at!.*?\n    end\n/m].to_s
ok('remove_at! rebuilds the wall the way a window does', RM.include?('rebuild_wall_native!'))
ok('and lays the tile on that wall again', RM.include?('TileWall.refresh_wall!'))
ok('and never cuts on its own after the rebuild (the rebuild does it)', !RM.include?('recut_wall!'))
ok('a missing index is said out loud', RM.include?('there is no niche'))

AT = TN[/def self\.niche_at.*?\n    end\n/m].to_s
ok('niche_at tests all three axes of the box',
   AT.include?('n[:u0] + n[:w]') && AT.include?('n[:z0] + n[:h]') && AT.include?('-n[:depth]'))
ok('and when two overlap, the nearer face wins', AT.include?('d < best[3]'))

DT = File.read('./tile_niche_delete_tool.rb')
ok('the delete tool owns no geometry',
   DT.include?('TileNiche.niche_at') && DT.include?('TileNiche.remove_at!') && !DT.include?('add_face'))
ok('it shows what it will delete before the click', DT.include?('def draw') && DT.include?('GL_LINE_LOOP'))
TB = File.read('./toolbar.rb')
ok('Delete Niche sits in the niche group, after Niche',
   TB.include?("niche_buttons = [niche_cmd, niche_del_cmd"))
ok('the plugin loads the tool', File.read('./main.rb').include?('tile_niche_delete_tool.rb'))

puts($fails.zero? ? 'rt195 OK' : "rt195 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

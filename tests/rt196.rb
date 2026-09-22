# encoding: utf-8
# rt196 - EDIT A NICHE (2026-09-22, his ask: "כפתור עריכה").
#
# The niche keeps its MIDDLE along the wall, its bottom is the new height
# off the floor, its depth never goes through the wall - and the tool
# opens the same four-line window the niche was placed with.
require './sketchup_stub'
require './tile_niche'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TN = InteriorPro::TileNiche
n = TN.normalize(['a', 24.0, 48.0, 12.0, 24.0, 4.0])   # middle at 30
nn = TN.new_numbers(n, w: 20.0, h: 30.0, depth: 4.0, sill: 40.0, thickness: 6.0)
ok('a wider niche grows both ways round its middle', nn[:u0] == 20.0 && nn[:w] == 20.0, nn)
ok('the bottom is the new height off the floor', nn[:z0] == 40.0)
ok('the height is taken as typed', nn[:h] == 30.0)
ok('the side does not change', nn[:side] == 'a')
ok('the depth is held back from the far face',
   TN.new_numbers(n, w: 12.0, h: 24.0, depth: 5.0, sill: 48.0, thickness: 4.5)[:depth] == 4.0)

SRC = File.read('./tile_niche.rb')
UP = SRC[/def self\.update_at!.*?\n    end\n/m].to_s
ok('update_at! rebuilds the wall the way a window does', UP.include?('rebuild_wall_native!'))
ok('and lays the tile again', UP.include?('TileWall.refresh_wall!'))
ok('sizes that leave no niche are refused out loud', UP.include?('leave no niche'))
ET = File.read('./tile_niche_edit_tool.rb')
ok('the edit tool is the delete tool with a window', ET.include?('< TileNicheDeleteTool'))
ok('the same four lines as placing', ET.include?("['Width', 'Height', 'Depth into the wall', 'Height from the floor']"))
ok('filled with the niche\'s own numbers', ET.include?('f.call(n[:w]), f.call(n[:h]), f.call(n[:depth]), f.call(n[:z0])'))
ok('no geometry of its own', ET.include?('TileNiche.update_at!') && !ET.include?('add_face'))
ok('Edit Niche sits at the END of the niche group',
   File.read('./toolbar.rb').include?('niche_buttons = [niche_cmd, niche_del_cmd, niche_edit_cmd]'))
ok('the plugin loads it', File.read('./main.rb').include?('tile_niche_edit_tool.rb'))

puts($fails.zero? ? 'rt196 OK' : "rt196 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

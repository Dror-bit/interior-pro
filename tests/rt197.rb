# encoding: utf-8
# rt197 - MOVE A NICHE (2026-09-22, his ask: "הזזה").
#
# Pick a niche up, carry it as the placing tool's ghost, put it down on
# the same face or another wall. Same sizes, new place; both walls come
# back from their numbers.
require './sketchup_stub'
require './tile_niche'
require './tile_wall_tool'
require './tile_niche_tool'
require './tile_niche_move_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SRC = File.read('./tile_niche.rb')
MV = SRC[/def self\.move_at!.*?\n    end\n/m].to_s
ok('on the same wall it is one row that changes', MV.include?('ns[idx.to_i] = moved'))
ok('onto another wall it leaves the old list and joins the new one',
   MV.include?('ns.delete_at(idx.to_i)') && MV.include?('persist!(to_wall, read(to_wall) + [moved])'))
ok('both walls are rebuilt from their numbers', MV.scan('rebuild_wall_native!').length >= 3)
ok('the tile on both walls is laid again', MV.scan('TileWall.refresh_wall!').length == 2)
ok('the depth is held to the NEW wall', MV.include?('clamp_depth(n[:depth], thickness_of(to_wall))'))
ok('a missing index is said out loud', MV.include?('there is no niche'))

T = InteriorPro::TileNicheMoveTool
ok('the move tool is the placing tool with a first click', T.ancestors.include?(InteriorPro::TileNicheTool))
t = T.allocate
t.instance_variable_set(:@cfg, { h: 24.0 })
ok('carried by its middle up the wall too', t.sill_for(60.0) == 48.0)
MT = File.read('./tile_niche_move_tool.rb')
ok('the drop goes through the same fits? as placing', MT.include?('TileNicheTool.fits?'))
ok('and the same point law (face_point) for the drop', MT.include?('face_point(view, x, y)'))
ok('Esc puts it back instead of leaving the tool', MT.include?("Esc = put it back"))
ok('no geometry of its own', MT.include?('TileNiche.move_at!') && !MT.include?('add_face'))
ok('Move Niche sits at the END of the niche group',
   File.read('./toolbar.rb').include?('niche_buttons = [niche_cmd, niche_del_cmd, niche_edit_cmd, niche_move_cmd]'))
ok('the plugin loads it', File.read('./main.rb').include?('tile_niche_move_tool.rb'))

puts($fails.zero? ? 'rt197 OK' : "rt197 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

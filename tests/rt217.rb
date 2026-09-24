# encoding: utf-8
# rt217 - THE NICHE'S OWN TILE (2026-09-23, his ask: "לשנות רק את הטיל
# שבתוך הניצ", choice 2 - its own material AND tile size, and why: "לפעמים
# עושים רק את החלק שצמוד לקיר בצבע שונה אבל לא את הצדדים"). Stored on the
# niche row, it survives edit and move, it goes on the back only or on the
# whole niche, and Edit Tile on a tile inside the niche opens its window.
require './sketchup_stub'
require './tile_grid'
require './tile_wall'
require './tile_niche'
require './tile_wall_tool'
require './tile_wall_edit_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
TN = InteriorPro::TileNiche
TW = InteriorPro::TileWall

# ---- stored on the row -------------------------------------------------
t = { 'card' => 'IP_MAT_0007', 'tile_w' => 2.0, 'tile_l' => 2.0, 'grout' => 0.0625, 'where' => 'back' }
n = { side: 'a', u0: 10.0, z0: 40.0, w: 12.0, h: 24.0, depth: 4.0, tile: t }
row = TN.to_row(n)
ok('the tile rides on the row as a 7th item', row.length == 7 && row[6].is_a?(String), row)
back = TN.normalize(row)
ok('and comes back the same', back[:tile] == t && back[:w] == 12.0, back)
ok('an old row (6 items) has no tile', !TN.normalize(['a', 1, 2, 3, 4, 5]).key?(:tile))
ok('a row without a tile stays 6 items', TN.to_row(n.reject { |k, _| k == :tile }).length == 6)
ok('no card = no tile', TN.tile_of_row({ 'card' => '' }.to_json).nil?)
ok('where is back unless it says all', TN.tile_of_row(t.merge('where' => 'x').to_json)['where'] == 'back')
nn = TN.new_numbers(n, w: 14.0, h: 24.0, depth: 4.0, sill: 40.0)
ok('Edit Niche keeps the niche\'s own tile', nn[:tile] == t)

# ---- which linings ------------------------------------------------------
ok('back only = the back lining', TW.own_tile_keys('back') == [:back])
ok('the whole niche = all five', TW.own_tile_keys('all').sort == %i[back bottom left right top].sort)
cells = TW.niche_own_cells([10.0, 40.0, 22.0, 64.0], 2.0, 2.0, 0.0625)
us = cells.map { |c| c[:u0] }
ok('the niche\'s own grid is centred on the niche', cells.any? { |c| (c[:u0] - 15.0).abs < 1e-6 && (c[:v0] - 51.0).abs < 1e-6 }, us.uniq.sort.first(6))
sets = TW.niche_lining(cells, 2.0, 2.0, 0.0625, [10.0, 40.0, 22.0, 64.0], 0.625, 4.0)
ok('the lining is cut from the niche\'s own tile', sets && sets[:back][:pieces].length > 20, sets && sets[:back][:pieces].length)
src = File.read('./tile_wall.rb')
body = src[/def self\.emit_niche_lining!.*?\n    end\n/m].to_s
ok('the lining swaps in the niche\'s own sets and material', body.include?('niche_own(x, dp)') && body.include?('own[:mat]'))
ok('build! hands the stored tile to the lining', src.include?('niches << { r: nr, depth: n[:depth].to_f, tile: n[:tile] }'))
ok('kill switch', TW.const_defined?(:USE_NICHE_OWN_TILE))

# ---- the real path: set_tile! stores it and lays the wall again ---------
$wall = Sketchup::Group.new
$wall.set_attribute('InteriorPro', 'type', 'wall')
$wall.set_attribute('InteriorPro', 'id', 'W1')
TN.persist!($wall, [n.reject { |k, _| k == :tile }])
$laid = []
class << TW
  def refresh_wall!(id); $laid << id; 1; end
end
ok('set_tile! stores it', TN.set_tile!($wall, 0, t) && TN.read($wall)[0][:tile] == t)
ok('and the tile on that wall is laid again', $laid == ['W1'], $laid)
ok('Same as the wall takes it off', TN.set_tile!($wall, 0, nil) && !TN.read($wall)[0].key?(:tile))
ok('no card chosen - nothing changes', !TN.set_tile!($wall, 0, { 'card' => '' }))

# ---- Edit Tile routes a click inside a niche to the niche window -----------
es = File.read('./tile_wall_edit_tool.rb')
ok('Edit Tile opens the niche window for a click inside a niche', es.include?('InteriorPro::TileNicheTileDialog.show(hit[0], hit[1])'))
html = InteriorPro::TileNicheTileDialog.build_html({ 'card' => '', 'tile_w' => 0, 'tile_l' => 0, 'grout' => 0.125, 'where' => 'back' }, [])
ok('the niche window: card, tile size, grout, back only / whole niche, same as the wall',
   %w[id="card" id="tile" id="grout" id="w_back" id="w_all" same_as_wall fit_height].all? { |k| html.include?(k) })

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

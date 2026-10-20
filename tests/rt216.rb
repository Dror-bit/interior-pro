# encoding: utf-8
# rt216 - SPLIT A TILED AREA IN TWO (2026-09-23, his words: "חיתוך הקיר של
# הטיל... כל קיר טיל בנפרד ואני יכול לערוך אותו", and "גם וגם" - a lying
# cut and a standing one). Pinned on the maths - EVERY grout line stays
# where it was - and then on the real path: split_area! hands both halves
# to TileWall.build!, the old id kept, a new free id for the second.
require './sketchup_stub'
require './tile_grid'
require './tile_wall'
require './tile_wall_tool'
require './tile_wall_stretch_tool'
require './tile_wall_split_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

G  = InteriorPro::TileGrid
TW = InteriorPro::TileWall
ST = InteriorPro::TileWallSplitTool

# Every tile corner [u, v] the grid puts inside a rectangle.
def tiles(a, u0, z0, w, h)
  cells = G.cells(TW.rect(u0, z0, w, h), u_size: a[:tile_w], v_size: a[:tile_l], grout: a[:grout],
                  angle: 0.0, ox: a[:ox], oy: a[:oy],
                  centered: TW.center_for_grid(a[:centered], a[:axis] || a[:center_axis]),
                  stagger: a[:stagger])
  over(cells.map { |c| [c[:u0].round(6), c[:v0].round(6)] }, u0, z0, w, h, a[:tile_w], a[:tile_l])
end

# The tiles of a list that show inside a rectangle (cut ones too).
def over(list, u0, z0, w, h, tw = 12.0, tl = 24.0)
  list.select { |u, v| u < u0 + w - 1e-6 && u + tw > u0 + 1e-6 && v < z0 + h - 1e-6 && v + tl > z0 + 1e-6 }.uniq.sort
end

# An area 69 wide, 96 tall, 12x24 tile, centred on a tile both ways.
base = { u0: 0.0, z0: 0.0, w: 69.0, h: 96.0, bu0: 0.0, bw: 69.0, tile_w: 12.0, tile_l: 24.0,
         grout: 0.125, stagger: 0.0, angle: 0.0, ox: 0.0, oy: 0.0, centered: true, axis: 'uv' }

p = ST.split_parts(base, :h, 36.0)
ok('a lying cut: bottom 36 tall, top 60 tall', p && p[0][:h] == 36.0 && p[1][:z0] == 36.0 && p[1][:h] == 60.0, p)
all = tiles(base, 0, 0, 69, 96)
b = tiles(p[0].merge(tile_w: 12.0, tile_l: 24.0, grout: 0.125, stagger: 0.0), 0, 0, 69, 36)
t = tiles(p[1].merge(tile_w: 12.0, tile_l: 24.0, grout: 0.125, stagger: 0.0), 0, 36, 69, 60)
ok('the bottom keeps every grout line it had', b == over(all, 0, 0, 69, 36), [b.first(3), all.first(3)])
ok('the top keeps every grout line it had', t == over(all, 0, 36, 69, 60), [t.first(3)])
ok('nothing is centred any more - the grid is carried as a shift', !p[0][:centered] && !p[1][:centered])

p = ST.split_parts(base, :v, 30.0)
ok('a standing cut: left 30 wide, right 39 wide', p && p[0][:w] == 30.0 && p[1][:u0] == 30.0 && p[1][:w] == 39.0, p)
l = tiles(p[0].merge(tile_w: 12.0, tile_l: 24.0, grout: 0.125, stagger: 0.0), 0, 0, 30, 96)
r = tiles(p[1].merge(tile_w: 12.0, tile_l: 24.0, grout: 0.125, stagger: 0.0), 30, 0, 39, 96)
ok('the left keeps its grout lines', l == over(all, 0, 0, 30, 96))
ok('the right keeps its grout lines', r == over(all, 30, 0, 39, 96))

# A running bond (1/2): the top's first row is pushed like the row it was.
sb = base.merge(stagger: 0.5, centered: false, oy: 0.0)
allb = tiles(sb, 0, 0, 69, 96)
p = ST.split_parts(sb, :h, 30.0) # 30 lands in the SECOND row (24.125 .. 48.125) - an odd row
tb = tiles(p[1].merge(tile_w: 12.0, tile_l: 24.0, grout: 0.125, stagger: 0.5), 0, 30, 69, 66)
ok('running bond: the top half keeps the staggered joints (its first row was an odd row)', tb == over(allb, 0, 30, 69, 66), [tb.first(4), over(allb, 0, 30, 69, 66).first(4)])

ok('a cut outside the area - nothing', ST.split_parts(base, :h, 0.5).nil? && ST.split_parts(base, :v, 70.0).nil?)
ok('a cut on the edge - nothing', ST.split_parts(base, :h, 96.0).nil?)

# ---- the real path -------------------------------------------------------
$wall = Sketchup::Group.new
$wall.set_attribute('InteriorPro', 'type', 'wall')
$wall.set_attribute('InteriorPro', 'id', 'W1')
$area = Sketchup::Group.new
{ 'type' => 'tile_wall', 'id' => 'TW001', 'wall_id' => 'W1', 'side' => 'a', 'u0' => 0.0, 'z0' => 0.0,
  'area_w' => 69.0, 'area_h' => 96.0, 'built_u0' => 0.0, 'built_w' => 69.0, 'tile_w' => 12.0, 'tile_l' => 24.0,
  'pattern_grout' => 0.125, 'pattern_ox' => 0.0, 'pattern_oy' => 0.0, 'pattern_center' => true,
  'pattern_center_axis' => 'uv', 'material_card_id' => 'C1', 'tile_depth' => 0.625, 'tile_mode' => 'tiles',
  'pattern_grout_color' => 'gray', 'pattern_stagger' => 0.0, 'pattern_angle' => 0.0 }.each { |k, v| $area.set_attribute('InteriorPro', k, v) }
$other = Sketchup::Group.new
$other.set_attribute('InteriorPro', 'type', 'tile_wall')
$other.set_attribute('InteriorPro', 'id', 'TW003')
$builds = []
$niches = []
class << TW
  def areas_in_model(_m = nil); [$area, $other]; end
  def wall_by_id(_id, _m = nil); $wall; end
  def build!(**kw); $builds << kw; Sketchup::Group.new; end
end
module InteriorPro
  module TileNiche
    def self.read(_w); $niches; end
  end
end
TW.instance_variable_set(:@seq, 0) # next_id would give TW003 first - that one is taken

res = ST.split_area!($area, :h, 36.0)
ok('split: two areas come back', res.is_a?(Array) && res.length == 2)
ok('both go through TileWall.build! - the one real path', $builds.length == 2)
ok('the bottom keeps the old id', $builds[0][:id] == 'TW001' && $builds[0][:h] == 36.0, $builds[0] && $builds[0].slice(:id, :z0, :h))
ok('the top gets a new id nobody has', !%w[TW001 TW003].include?($builds[1][:id].to_s) && $builds[1][:z0] == 36.0, $builds[1] && $builds[1][:id])
ok('both keep the card, tile, grout, colour, depth', $builds.all? { |k| k[:card_id] == 'C1' && k[:tile_w] == 12.0 && k[:grout] == 0.125 && k[:grout_color] == 'gray' && k[:depth] == 0.625 })
ok('inside ONE undo step', $builds.all? { |k| k[:wrap_operation] == false })

$builds = []
$niches = [{ side: 'a', u0: 20.0, z0: 40.0, w: 12.0, h: 24.0 }]
ok('a cut through a niche is refused', ST.split_area!($area, :h, 50.0).nil? && $builds.empty?)
ok('a cut past the niche is fine', !ST.split_area!($area, :h, 30.0).nil?)

src = File.read('./toolbar.rb')
ok('a Split Tile button on the bar, next to Stretch Tile', src.include?("UI::Command.new('Split Tile')") && src.include?('tile_stretch_cmd, tile_split_cmd, tile_edit_cmd]'))
ok('main.rb loads the tool', File.read('./main.rb').include?('tile_wall_split_tool.rb'))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

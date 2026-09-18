# encoding: utf-8
# rt180 - ONE EDIT WINDOW FOR A TILED AREA (2026-09-18).
#
# His words: "אני חושב שזה יהיה בכללי חלון עריכה גם לגודל וצבע וכו והוא
# כולל את הפריסה וכן כפתור." One window: the material, the tile, the
# grout, the size AND the layout - centre the tile, shift it, turn it.
#
# CLAUDE.md, the law this suite exists to keep: a test on the maths alone
# proves nothing. What has to be pinned is that every number he types in
# the window reaches the REAL path - TileWall.build! - under the SAME id,
# and that the corner square is laid again afterwards.
require './sketchup_stub'
require './tile_wall'
require './tile_wall_tool'
require './tile_wall_edit_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

D = InteriorPro::TileWallEditDialog
TW = InteriorPro::TileWall

ok('the feature has a kill switch, like every feature that builds geometry',
   D.const_defined?(:USE_TILE_EDIT))

# ---- the window is reached from a button and from a tool ----------------
BAR = File.read('./toolbar.rb')
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
ok('the button is on the surfaces bar', SURF.include?("UI::Command.new('Edit Tile')"))
ok('and it is in the button list, which is what the bar is built from',
   SURF.include?('tile_edit_cmd]'))
ok('the older buttons are still on that list, untouched',
   SURF.include?('buttons = [floors_cmd, tile_wall_cmd, tile_stretch_cmd,'))
ok('the plugin loads the new file',
   File.read('./main.rb').include?('tile_wall_edit_tool.rb'))

SRC = File.read('./tile_wall_edit_tool.rb')
ok('the window has every field he asked for - material, tile, grout, size and layout',
   %w[id="card" id="tile" id="grout" id="gcolor" id="stagger" id="depth"
      id="mode" id="center" id="ox" id="oy" id="angle"
      id="w" id="h" id="u0" id="z0"].all? { |q| SRC.include?(q) })
ok('the JS in the heredoc has no single backslash escape - CLAUDE.md, Ruby eats it',
   SRC[/<script>.*?<\/script>/m].to_s !~ /\\[dsw.]/)

# ---- THE REAL PATH ------------------------------------------------------
# A stand-in area group with the numbers a drawn area really carries.
area = Sketchup::Group.new
{ 'type' => 'tile_wall', 'id' => 'TW007', 'wall_id' => 'W3', 'side' => 'b',
  'u0' => 10.0, 'z0' => 0.0, 'area_w' => 60.0, 'area_h' => 96.0,
  'material_card_id' => 'CARD1', 'tile_w' => 12.0, 'tile_l' => 12.0,
  'tile_depth' => 0.625, 'tile_mode' => 'tiles', 'pattern_grout' => 0.125,
  'pattern_grout_color' => 'light', 'pattern_stagger' => 0.0,
  'pattern_angle' => 0.0, 'pattern_ox' => 0.0, 'pattern_oy' => 0.0,
  'pattern_center' => false }.each { |k, v| area.set_attribute('InteriorPro', k, v) }
wall = Sketchup::Group.new
wall.set_attribute('InteriorPro', 'type', 'wall')
wall.set_attribute('InteriorPro', 'id', 'W3')

$built = nil
$refreshed = 0
class << TW
  def areas_in_model(_m = nil); [$stub_area]; end
  def wall_by_id(_id, _m = nil); $stub_wall; end
  def build!(**kw); $built = kw; $stub_area; end
  def refresh_corner_neighbours!(_g, _m = nil); $refreshed += 1; 1; end
end
$stub_area = area
$stub_wall = wall

D.apply!('TW007', {
  'card' => 'CARD2', 'tile' => '48x24', 'mode' => 'image',
  'grout' => 0.25, 'gcolor' => 'dark', 'stagger' => 0.5, 'depth' => 0.5,
  'center' => true, 'ox' => 3.0, 'oy' => -1.5, 'angle' => 45.0,
  'w' => 72.0, 'h' => 84.0, 'u0' => 12.0, 'z0' => 6.0
})

ok('the window rebuilt the area through TileWall.build! - the one real path',
   !$built.nil?)
ok('under the SAME id, so the edit replaces the area instead of adding one',
   $built && $built[:id] == 'TW007', $built && $built[:id])
ok('on the same wall and the same face it was drawn on',
   $built && $built[:side] == 'b', $built && $built[:side])
ok('the new material card went through', $built && $built[:card_id] == 'CARD2')
ok('the typed tile size went through, first number along the wall',
   $built && $built[:tile_w] == 48.0 && $built[:tile_l] == 24.0,
   $built && [$built[:tile_w], $built[:tile_l]])
ok('the grout width and its colour went through',
   $built && $built[:grout] == 0.25 && $built[:grout_color] == 'dark')
ok('the offset between courses went through', $built && $built[:stagger] == 0.5)
ok('the stand-off depth went through', $built && $built[:depth] == 0.5)
ok('tile by tile or the whole image went through', $built && $built[:mode] == 'image')
ok('CENTRE THE TILE went through - the thing he asked for',
   $built && $built[:centered] == true)
ok('the shift and the angle went through',
   $built && $built[:ox] == 3.0 && $built[:oy] == -1.5 && $built[:angle] == 45.0)
ok('the SIZE went through too - he asked for one window for size as well',
   $built && $built[:w] == 72.0 && $built[:h] == 84.0)
ok('and where the area sits on the wall',
   $built && $built[:u0] == 12.0 && $built[:z0] == 6.0)
ok('the corner square is laid again afterwards, or the neighbour breaks',
   $refreshed == 1, $refreshed)

# 'From material' means the card decides - a 0 tells build! to read the card.
$built = nil
D.apply!('TW007', { 'card' => '', 'tile' => 'From material', 'mode' => 'tiles',
                    'grout' => 0.0, 'gcolor' => 'light', 'stagger' => 0.0,
                    'depth' => 0.625, 'center' => false, 'ox' => 0, 'oy' => 0,
                    'angle' => 0, 'w' => 60.0, 'h' => 96.0, 'u0' => 10.0, 'z0' => 0.0 })
ok("'From material' hands 0 over, and build! then reads the card's own size",
   $built && $built[:tile_w] == 0.0 && $built[:tile_l] == 0.0,
   $built && [$built[:tile_w], $built[:tile_l]])
ok('an empty card means joint lines only, not a broken id',
   $built && $built[:card_id].nil?, $built && $built[:card_id])

puts($fails.zero? ? 'rt180 all green' : "rt180 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

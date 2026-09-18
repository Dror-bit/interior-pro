# encoding: utf-8
# rt183 - A GROUT LINE AT THE CENTRE (2026-09-18).
#
# His words: "אני רוצה גם להכניס את האופציה של סנטר לגראוט ליד סנטר לטיל."
# So the wall's layout has three choices: from the edge, a whole TILE on
# the middle, or a GROUT line on the middle - a whole tile either side.
#
# Pinned on the one grid (tile_grid.rb), then on the REAL path: the wall
# stores it under one spelling, reads it back the same, and the window
# hands it over. Floors never pass it and must not move.
require './sketchup_stub'
require './tile_grid'
require './tile_wall'
require './tile_wall_tool'
require './tile_wall_edit_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

G  = InteriorPro::TileGrid
TW = InteriorPro::TileWall
D  = InteriorPro::TileWallEditDialog

# A 100" run, centre at 50, 12" tile, 1/8" grout -> pitch 12.125.
size = 12.0; g = 0.125; pitch = size + g
s_edge  = G.start(0.0, 50.0, size, pitch, 0.0, false)
s_tile  = G.start(0.0, 50.0, size, pitch, 0.0, true)
s_grout = G.start(0.0, 50.0, size, pitch, 0.0, 'grout')

# Where a joint's own middle lands: tile starts at s + k*pitch, the joint
# after it runs size..size+g, so its middle is at s + k*pitch + size + g/2.
joint_mid = ->(s) { (0..20).map { |k| s + k * pitch + size + g / 2.0 } }
tile_mid  = ->(s) { (0..20).map { |k| s + k * pitch + size / 2.0 } }

ok('from the edge, the first tile starts at the edge (unchanged)', (s_edge - 0.0).abs < 1e-9, s_edge)
ok('a TILE at the centre: the middle of a tile sits on 50 (unchanged)',
   tile_mid.call(s_tile).any? { |m| (m - 50.0).abs < 1e-9 })
ok('a GROUT line at the centre: the middle of a joint sits on 50',
   joint_mid.call(s_grout).any? { |m| (m - 50.0).abs < 1e-9 }, joint_mid.call(s_grout).min_by { |m| (m - 50).abs })
ok('and it is half a pitch away from the tile-centred layout, no more, no less',
   (((s_grout - s_tile).abs % pitch) - pitch / 2.0).abs < 1e-9, (s_grout - s_tile).abs % pitch)
ok('the start is still pulled back to cover the run from its very edge', s_grout <= 0.0 && s_grout > -pitch)
ok('with no grout at all a joint at the centre is the seam between two tiles',
   (0..20).map { |k| G.start(0.0, 50.0, size, size, 0.0, 'grout') + k * size }.any? { |e| (e - 50.0).abs < 1e-9 })
ok('a symbol spelling works the same as the string',
   (G.start(0.0, 50.0, size, pitch, 0.0, :grout) - s_grout).abs < 1e-9)
ok('the shift he types still moves it, by exactly what he typed (modulo a pitch)',
   (((G.start(0.0, 50.0, size, pitch, 2.0, 'grout') - s_grout - 2.0).abs % pitch)).abs < 1e-9)

# ---- one spelling for the attribute ------------------------------------
ok("the wall stores 'grout' as 'grout'", TW.center_value('grout') == 'grout')
ok('true stays true, false stays false, nil is false',
   TW.center_value(true) == true && TW.center_value(false) == false && TW.center_value(nil) == false)
SRC = File.read('./tile_wall.rb')
ok('the build stores it through that one spelling',
   SRC.include?("grp.set_attribute('InteriorPro', 'pattern_center', center_value(centered))"))
ok('and the rebuild reads it back through the same one',
   SRC.include?("centered: center_value(a.call('pattern_center')),"))
ok('floors still coerce to true/false - nothing there moves',
   File.read('./floor_pattern.rb').include?("centered = floor.get_attribute('InteriorPro', 'pattern_center') ? true : false"))

# ---- the window hands it over ------------------------------------------
ok("the window's two menus map to what build! takes",
   D.center_from('tile') == true && D.center_from('grout') == 'grout')
ok('neither Horizontal nor Vertical ticked = no centring, whatever the menu says',
   D.center_from('tile', 'off') == false && D.center_from('grout', D.axis_from(false, false)) == false)
ok('an old true from the checkbox days still means a tile', D.center_from('true') == true)

area = Sketchup::Group.new
{ 'type' => 'tile_wall', 'id' => 'T1', 'wall_id' => 'W1', 'side' => 'a', 'u0' => 0.0,
  'z0' => 0.0, 'area_w' => 60.0, 'area_h' => 96.0 }.each { |k, v| area.set_attribute('InteriorPro', k, v) }
wall = Sketchup::Group.new
wall.set_attribute('InteriorPro', 'type', 'wall')
$built = nil
class << TW
  def areas_in_model(_m = nil); [$ga]; end
  def wall_by_id(_i, _m = nil); $gw; end
  def build!(**kw); $built = kw; $ga; end
  def refresh_corner_neighbours!(_g, _m = nil); 0; end
  def connected_areas(g, _m = nil); [g]; end
end
$ga = area; $gw = wall
D.apply!('T1', { 'card' => '', 'tile' => '', 'mode' => 'tiles', 'grout' => 0.125, 'gcolor' => 'light',
                 'stagger' => 0, 'depth' => 0.625, 'center' => 'grout', 'cen_h' => true, 'cen_v' => true, 'ox' => 0, 'oy' => 0, 'angle' => 0,
                 'w' => 60.0, 'h' => 96.0, 'u0' => 0.0, 'z0' => 0.0, 'whole' => false })
ok("choosing the grout line in the window reaches build! as 'grout'", $built && $built[:centered] == 'grout', $built && $built[:centered])
ESRC = File.read('./tile_wall_edit_tool.rb')
ok('the window has ONE menu, Tile or Grout - his call',
   ESRC.include?('value="tile">Tile') && ESRC.include?('value="grout">Grout') && !ESRC.include?('From the edge'))

puts($fails.zero? ? 'rt183 all green' : "rt183 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

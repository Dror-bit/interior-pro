# encoding: utf-8
# rt184 - CENTRE ONE WAY OR BOTH, AND FROM THE FIRST DRAWING (2026-09-18).
#
# His words: "אולי גם יהיה מירכוז רק הקווים האנכיים ולא האופקיים כי לפעמים
# רוצים רק יתרה למעלה או למטה ... מירכוז כללי, מירכוז אופקי ומירכוז אנכי.
# לפני התפריט אני בוחר אם זה מתייחס לטיל עצמו או לגראוט." And: "אם זה
# צריך להיכנס גם בסרטוט ההתחלתי."
#
# So: WHAT is centred (tile / grout) and WHICH WAY (both / along / up),
# in the drawing dialog and in the edit window alike, stored on the area
# and read back on every rebuild. Pinned on the grid, then the REAL path.
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
T  = InteriorPro::TileWallTool
D  = InteriorPro::TileWallEditDialog

# ---- 1. the grid takes a direction each ---------------------------------
# A 100 x 100 square, 12" tile, no grout. Centred both ways a tile's middle
# sits on (50, 50); from the edge the first tile starts at 0.
sq = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]]
mids = lambda do |cells|
  cells.map { |c| [(c[:u0] + 6.0).round(6), (c[:v0] + 6.0).round(6)] }
end
both = G.cells(sq, u_size: 12.0, v_size: 12.0, centered: true)
ok('both ways (plain true, as before): a tile middle on 50 along AND 50 up',
   mids.call(both).include?([50.0, 50.0]))
u_only = G.cells(sq, u_size: 12.0, v_size: 12.0, centered: { u: true, v: false })
ok('ALONG only: a tile middle on 50 along, and up it starts from the edge',
   mids.call(u_only).any? { |m| m[0] == 50.0 } && u_only.any? { |c| c[:v0].round(6) == 0.0 } &&
     mids.call(u_only).none? { |m| m[1] == 50.0 })
v_only = G.cells(sq, u_size: 12.0, v_size: 12.0, centered: { u: false, v: true })
ok('UP only: a tile middle on 50 up, and along it starts from the edge',
   mids.call(v_only).any? { |m| m[1] == 50.0 } && v_only.any? { |c| c[:u0].round(6) == 0.0 } &&
     mids.call(v_only).none? { |m| m[0] == 50.0 })
none = G.cells(sq, u_size: 12.0, v_size: 12.0, centered: { u: false, v: false })
edge = G.cells(sq, u_size: 12.0, v_size: 12.0, centered: false)
ok('a Hash of two falses is the same as plain false',
   none.map { |c| [c[:u0], c[:v0]] } == edge.map { |c| [c[:u0], c[:v0]] })
gv = G.cells(sq, u_size: 12.0, v_size: 12.0, grout: 1.0, centered: { u: false, v: 'grout' })
ok('a grout line up only: a joint middle on 50 up (tile 12 + joint 1 -> joint middle at tile top + 0.5)',
   gv.any? { |c| (c[:v0] + 12.0 + 0.5 - 50.0).abs < 1e-6 } && gv.any? { |c| c[:u0].round(6) == 0.0 })

# ---- 2. one spelling for the axis --------------------------------------
ok("'uv' 'u' 'v' pass, anything else is both", TW.axis_value('u') == 'u' && TW.axis_value('v') == 'v' &&
   TW.axis_value('uv') == 'uv' && TW.axis_value(nil) == 'uv' && TW.axis_value('x') == 'uv')
ok('the grid gets the choice on the axes he named and from-the-edge on the other',
   TW.center_for_grid(true, 'u') == { u: true, v: false } &&
   TW.center_for_grid('grout', 'v') == { u: false, v: 'grout' } &&
   TW.center_for_grid(true, 'uv') == { u: true, v: true } &&
   TW.center_for_grid(false, 'v') == { u: false, v: false })
SRC = File.read('./tile_wall.rb')
ok('the build hands the grid that pair', SRC.include?('cen = center_for_grid(centered, center_axis)') &&
   SRC.include?('centered: cen,'))
ok('the axis is stored on the area', SRC.include?("'pattern_center_axis', axis_value(center_axis)"))
ok('and read back on every rebuild', SRC.include?("center_axis: axis_value(a.call('pattern_center_axis')),"))
ok('an area drawn before today, with no axis stored, is centred both ways as it always was',
   TW.axis_value(nil) == 'uv')

# ---- 3. the drawing dialog ----------------------------------------------
ok('the drawing dialog: Tile or Grout, then Horizontal yes/no, Vertical yes/no - his call',
   T::CENTRES == %w[Tile Grout] && T::CENTRE_V == [true, 'grout'] && T::YESNO == %w[No Yes])
ok('two yes/no become the one stored axis - Horizontal is the horizontal LINES (rows, v), Vertical the columns (u)',
   T.axis_of(true, true) == 'uv' && T.axis_of(true, false) == 'v' && T.axis_of(false, true) == 'u')
ok('the window says the same', D.axis_from(true, false) == 'v' && D.axis_from(false, true) == 'u' &&
   D.axis_from(true, true) == 'uv' && D.axis_from(false, false) == 'off')
TSRC = File.read('./tile_wall_tool.rb')
ok('the three rows are in the one dialog, before the tile size',
   TSRC.include?("'Corner', 'Centre', 'Horizontal', 'Vertical', 'Tile size'"))
ok('what he picks is remembered for the next area, and a new wall starts on a GROUT line both ways (his call, 2026-09-18 evening)',
   TSRC.include?("center: 'grout', cen_h: true, cen_v: true }"))
ok('and handed to the build from the first drawing - off when neither is ticked',
   TSRC.include?('centered: (@cfg[:cen_h] || @cfg[:cen_v]) ? @cfg[:center] : false') &&
   TSRC.include?('center_axis: InteriorPro::TileWallTool.axis_of(@cfg[:cen_h], @cfg[:cen_v])'))

# ---- 4. the edit window, the real path ----------------------------------
area = Sketchup::Group.new
{ 'type' => 'tile_wall', 'id' => 'T1', 'wall_id' => 'W1', 'side' => 'a', 'u0' => 0.0,
  'z0' => 0.0, 'area_w' => 60.0, 'area_h' => 96.0, 'pattern_center' => 'grout',
  'pattern_center_axis' => 'v' }.each { |k, v| area.set_attribute('InteriorPro', k, v) }
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
                 'stagger' => 0, 'depth' => 0.625, 'center' => 'tile', 'cen_h' => true, 'cen_v' => false, 'ox' => 0, 'oy' => 0,
                 'angle' => 0, 'w' => 60.0, 'h' => 96.0, 'u0' => 0.0, 'z0' => 0.0, 'whole' => false })
ok('the window hands WHAT and WHICH WAY to build! - Horizontal ticked alone centres the rows',
   $built && $built[:centered] == true && $built[:center_axis] == 'v', $built && [$built[:centered], $built[:center_axis]])
ESRC = File.read('./tile_wall_edit_tool.rb')
ok('the window shows Horizontal and Vertical as two ticks next to the Tile/Grout menu',
   ESRC.include?('id="cen_h"> Horizontal') && ESRC.include?('id="cen_v"> Vertical'))
ok('and opens on what the area already has', ESRC.include?("'axis'    => tw.axis_value(at.call('pattern_center_axis'))"))
# The whole shower keeps each area's own centring.
$builds = []
class << TW
  def build!(**kw); $builds << kw; $ga; end
  def connected_areas(_g, _m = nil); [$ga, $ga2]; end
end
$ga2 = Sketchup::Group.new
{ 'type' => 'tile_wall', 'id' => 'T2', 'wall_id' => 'W2', 'side' => 'b', 'u0' => 0.0,
  'z0' => 0.0, 'area_w' => 40.0, 'area_h' => 96.0, 'pattern_center' => 'grout',
  'pattern_center_axis' => 'v' }.each { |k, v| $ga2.set_attribute('InteriorPro', k, v) }
D.apply!('T1', { 'card' => '', 'tile' => '', 'mode' => 'tiles', 'grout' => 0.125, 'gcolor' => 'light',
                 'stagger' => 0, 'depth' => 0.625, 'center' => 'tile', 'cen_h' => true, 'cen_v' => false, 'ox' => 0, 'oy' => 0,
                 'angle' => 0, 'w' => 60.0, 'h' => 96.0, 'u0' => 0.0, 'z0' => 0.0, 'whole' => true })
b2 = $builds.find { |b| b[:id] == 'T2' }
ok('the whole shower leaves each wall its OWN centring - that is layout, not material',
   b2 && b2[:centered] == 'grout' && b2[:center_axis] == 'v', b2 && [b2[:centered], b2[:center_axis]])

puts($fails.zero? ? 'rt184 all green' : "rt184 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

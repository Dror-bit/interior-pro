# encoding: utf-8
# rt185 - THE SIDES FOLLOW THE WALL HE CENTRED (2026-09-18).
#
# His picture: the back wall centred, the two side walls on their old
# layout, the grout lines breaking at both corners. His words: "שהצדדים
# ילכו עם הפריסה המתאימה לשינוי הקיר שאני משנה אותו."
#
# The lattice of the edited wall is walked round the corners: the tile
# cut at the corner carries on as the first piece of the next wall - in
# BOTH directions, from ANY layout, and on from that wall to the next.
# The rows go with it. Pinned on the maths, then on the real path.
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

SIZE = 24.0; GR = 0.125; PITCH = SIZE + GR

# A shower: left wall L (face b, 0..60, its END at the corner), the back
# wall B (face a, 0..100), the right wall R (face a, 0..60, its START at
# the corner). No corner square in the numbers here (bu0/bw = u0/w) so
# the maths is bare.
AREAS = [
  { id: 'L', wall_id: 'WL', side: 'b', u0: 0.0, w: 60.0,  bu0: 0.0, bw: 60.0 },
  { id: 'B', wall_id: 'WB', side: 'a', u0: 0.0, w: 100.0, bu0: 0.0, bw: 100.0, ox: 0.0, cen_u: true },
  { id: 'R', wall_id: 'WR', side: 'a', u0: 0.0, w: 60.0,  bu0: 0.0, bw: 60.0 }
]
NB = lambda do |wall_id, side, u|
  case [wall_id, side, u.round(1)]
  when ['WB', 'a', 0.0]   then { wall_id: 'WL', side: 'b', u_from: 60.0, dir: -1.0 }
  when ['WB', 'a', 100.0] then { wall_id: 'WR', side: 'a', u_from: 0.0,  dir: 1.0 }
  when ['WL', 'b', 60.0]  then { wall_id: 'WB', side: 'a', u_from: 0.0,  dir: 1.0 }
  when ['WR', 'a', 0.0]   then { wall_id: 'WB', side: 'a', u_from: 100.0, dir: -1.0 }
  end
end

# Every joint of a lattice inside a span, from a start and a pitch.
joints = lambda do |s, lo, hi|
  (-20..20).map { |k| s + k * PITCH }.select { |j| j >= lo - 1e-9 && j <= hi + 1e-9 }.map { |j| j.round(6) }
end

res = TW.follow_layout(AREAS, 'B', NB, SIZE, GR)
ok('both side walls get a shift, the back wall itself does not', res.keys.sort == %w[L R], res)

# The back wall, centred: a whole tile on 50, so joints at 50 +- 12 +- pitch...
sB = G.start(0.0, 50.0, SIZE, PITCH, 0.0, true)
jB = joints.call(sB, 0.0, 100.0)
ok('the back wall really is centred - a tile from 38 to 62, then the joint, then the next tile',
   jB.include?(38.0) && jB.include?(62.125), jB)
# Its tile at the RIGHT corner: last tile start before 100 is 38 + 2 x 24.125 = 86.25,
# so 13.75 of tile is on the back wall and the rest must be on the right wall.
last_before_100 = jB.select { |j| j <= 100.0 }.max
cut_r = 100.0 - last_before_100
ok('the cut at the right corner is what is left after the last tile start', (cut_r - 13.75).abs < 1e-6, cut_r)

# The RIGHT wall runs away from the corner (dir +1, u_from 0): its first
# joint must sit at pitch - cut from the corner, so that tile is whole
# again when you add the two pieces.
sR = G.start(0.0, 30.0, SIZE, PITCH, res['R'], false)
jR = joints.call(sR, 0.0, 60.0)
ok('the right wall: first joint at pitch minus the cut - the corner tile carries on',
   (jR.min - (PITCH - cut_r)).abs < 1e-6, [jR.min, PITCH - cut_r])
ok('and after it the joints march on a whole pitch apart', (jR[1] - jR[0] - PITCH).abs < 1e-6)

# The LEFT wall runs INTO the corner (dir -1, u_from 60): its last joint
# before the corner must be pitch - cut short of it.
# At the LEFT corner the tile that starts at -10.25 has 13.75 on the back
# wall (up to its joint at 13.75); the other 10.25 of it belongs on the
# left wall, right against the corner.
first_after_0 = jB.select { |j| j >= 0.0 }.min
on_back = first_after_0 - GR
sL = G.start(0.0, 30.0, SIZE, PITCH, res['L'], false)
jL = joints.call(sL, 0.0, 60.0)
ok('the left wall: the rest of that tile sits against the corner - the two pieces make one tile',
   (60.0 - jL.max + on_back - SIZE).abs < 1e-6, [60.0 - jL.max, on_back])

# A joint exactly ON the corner: the next wall starts with a whole tile.
res2 = TW.follow_layout(AREAS.map { |a| a[:id] == 'B' ? a.merge(cen_u: false, ox: 0.0) : a }, 'B', NB, 25.0, 0.0)
sR2 = G.start(0.0, 30.0, 25.0, 25.0, res2['R'], false)
j25 = (-20..20).map { |k| sR2 + k * 25.0 }.select { |j| j >= -1e-9 && j <= 60.0 }.sort
ok('a joint dead on the corner (100 = 4 x 25): the next wall starts with a whole tile',
   j25.first.abs < 1e-6 && (j25[1] - 25.0).abs < 1e-6, j25)

# Three in a row: the shift walks on from the side wall to the one after it.
AREAS3 = AREAS + [{ id: 'X', wall_id: 'WX', side: 'a', u0: 0.0, w: 40.0, bu0: 0.0, bw: 40.0 }]
NB3 = lambda do |wall_id, side, u|
  case [wall_id, side, u.round(1)]
  when ['WR', 'a', 60.0] then { wall_id: 'WX', side: 'a', u_from: 0.0, dir: 1.0 }
  when ['WX', 'a', 0.0]  then { wall_id: 'WR', side: 'a', u_from: 60.0, dir: -1.0 }
  else NB.call(wall_id, side, u)
  end
end
res3 = TW.follow_layout(AREAS3, 'B', NB3, SIZE, GR)
ok('a wall after the side wall follows the side wall, not the back wall', res3.key?('X'))
sX = G.start(0.0, 20.0, SIZE, PITCH, res3['X'], false)
jR3 = joints.call(G.start(0.0, 30.0, SIZE, PITCH, res3['R'], false), 0.0, 60.0)
cut_x = 60.0 - jR3.max
ok('and its first joint carries the tile cut at THAT corner',
   (joints.call(sX, 0.0, 40.0).min - (PITCH - cut_x)).abs < 1e-6)

ok('a size of nothing gives nothing, not a crash', TW.follow_layout(AREAS, 'B', NB, 0.0) == {})
ok('an unknown start gives nothing', TW.follow_layout(AREAS, 'Q', NB, SIZE) == {})

# ---- the real path ------------------------------------------------------
def mk(id, wall_id, side, w, extra = {})
  g = Sketchup::Group.new
  { 'type' => 'tile_wall', 'id' => id, 'wall_id' => wall_id, 'side' => side, 'u0' => 0.0, 'z0' => 0.0,
    'area_w' => w, 'area_h' => 96.0, 'built_u0' => 0.0, 'built_w' => w, 'tile_w' => SIZE, 'tile_l' => 12.0,
    'pattern_grout' => GR, 'pattern_ox' => 0.0, 'pattern_oy' => 0.0, 'pattern_center' => false,
    'pattern_center_axis' => 'uv', 'material_card_id' => 'C', 'tile_depth' => 0.625, 'tile_mode' => 'tiles',
    'pattern_grout_color' => 'light', 'pattern_stagger' => 0.0, 'pattern_angle' => 0.0
  }.merge(extra).each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
$gL = mk('L', 'WL', 'b', 60.0, 'pattern_ox' => 5.0, 'z0' => 4.0)
$gB = mk('B', 'WB', 'a', 100.0)
$gR = mk('R', 'WR', 'a', 60.0)
$gw = Sketchup::Group.new
$builds = []
class << TW
  def areas_in_model(_m = nil); [$gL, $gB, $gR]; end
  def wall_by_id(_i, _m = nil); $gw; end
  def neighbour_at(*_a); nil; end
  def frame_for(*_a); {}; end
  # the build WRITES what it was given, the way the real one does, so the
  # follow reads the just-built back wall
  def build!(**kw)
    $builds << kw
    g = [$gL, $gB, $gR].find { |x| x.get_attribute('InteriorPro', 'id') == kw[:id] }
    g.set_attribute('InteriorPro', 'pattern_center', center_value(kw[:centered]))
    g.set_attribute('InteriorPro', 'pattern_center_axis', axis_value(kw[:center_axis]))
    g.set_attribute('InteriorPro', 'pattern_ox', kw[:ox].to_f)
    g.set_attribute('InteriorPro', 'pattern_oy', kw[:oy].to_f)
    g.set_attribute('InteriorPro', 'z0', kw[:z0].to_f)
    g.set_attribute('InteriorPro', 'area_h', kw[:h].to_f)
    g
  end
  def refresh_corner_neighbours!(*_a); 0; end
  def connected_areas(_g, _m = nil); [$gB, $gL, $gR]; end
  def chain_input(_m = nil)
    areas = [$gL, $gB, $gR].map do |g|
      a = lambda { |k| g.get_attribute('InteriorPro', k) }
      { id: a.call('id'), wall_id: a.call('wall_id'), side: a.call('side'), u0: 0.0, w: a.call('area_w').to_f,
        bu0: 0.0, bw: a.call('area_w').to_f, ox: a.call('pattern_ox').to_f,
        cen_u: axis_value(a.call('pattern_center_axis')).include?('u') ? center_value(a.call('pattern_center')) : false }
    end
    [[$gL, $gB, $gR], areas, NB]
  end
end
CFG = { 'card' => 'C', 'tile' => '24x12', 'mode' => 'tiles', 'grout' => GR, 'gcolor' => 'light', 'stagger' => 0,
        'depth' => 0.625, 'center' => 'tile', 'cen_h' => true, 'cen_v' => true, 'ox' => 0, 'oy' => 1.5, 'angle' => 0,
        'w' => 100.0, 'h' => 84.0, 'u0' => 0.0, 'z0' => 2.0, 'whole' => false, 'follow' => true }
D.apply!('B', CFG)
ok('with the tick, the two joined walls are rebuilt after the back wall',
   $builds.map { |b| b[:id] } == %w[B L R] || $builds.map { |b| b[:id] } == %w[B R L], $builds.map { |b| b[:id] })
bR = $builds.find { |b| b[:id] == 'R' }
bL = $builds.find { |b| b[:id] == 'L' }
ok('the right wall gets the shift the maths gave, and its along-the-wall centring is OFF',
   bR && (bR[:ox] - res['R']).abs < 1e-6 && bR[:center_axis] == 'v', bR && [bR[:ox], bR[:center_axis]])
ok('the rows follow: the same up-shift, the same bottom, the same height, the same centring up the wall',
   bR && bR[:oy] == 1.5 && bR[:z0] == 2.0 && bR[:h] == 84.0 && bR[:centered] == true,
   bR && [bR[:oy], bR[:z0], bR[:h], bR[:centered]])
ok('the left wall the same, its old shift of 5 and old bottom of 4 gone',
   bL && (bL[:ox] - res['L']).abs < 1e-6 && bL[:z0] == 2.0)
ok('but each keeps its OWN width and material - this is layout, not a whole-shower change',
   bL && bL[:w] == 60.0 && bL[:card_id] == 'C' && bR[:w] == 60.0)

# Centred UP only on the back wall: the sides get rows centred, and along
# the wall only the shift.
$builds = []
D.apply!('B', CFG.merge('center' => 'grout', 'cen_h' => false, 'cen_v' => true))
bR = $builds.find { |b| b[:id] == 'R' }
ok('when the back wall is centred along only, the sides get plain rows (from the edge)',
   bR && bR[:centered] == false && bR[:center_axis] == 'v', bR && [bR[:centered], bR[:center_axis]])

# Without the tick nothing else moves.
$builds = []
D.apply!('B', CFG.merge('follow' => false))
ok('without the tick only the back wall is rebuilt', $builds.map { |b| b[:id] } == ['B'])

ESRC = File.read('./tile_wall_edit_tool.rb')
ok('the tick is in the window, next to the centring', ESRC.include?('id="follow"'))
ok('and off for an area joined to nothing', ESRC.include?("getElementById('follow').disabled = true"))

puts($fails.zero? ? 'rt185 all green' : "rt185 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

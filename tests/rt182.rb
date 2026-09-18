# encoding: utf-8
# rt182 - THE WHOLE SHOWER (2026-09-18).
#
# His words: "אני כן רוצה שהוא יערוך רק קיר אחד ספציפי בכל פעם ושתהיה
# אופציה לשנות גם את כל הקירות ביחד ... אבל את כל הקירות של אותה המקלחת."
# And "the same shower" is, by his choice (1), the CHAIN: every tiled area
# joined to this one round the corners, wall after wall - not the room.
#
# Two things are pinned. The chain walk on its own (pure), and then the
# REAL path: the window told to do the whole shower rebuilds every area
# in the chain through TileWall.build!, the shared numbers on all of them
# and each one's own width and place left alone.
require './sketchup_stub'
require './tile_wall'
require './tile_wall_tool'
require './tile_wall_edit_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TW = InteriorPro::TileWall
D  = InteriorPro::TileWallEditDialog

# ---- 1. the chain, pure --------------------------------------------------
# A three-wall shower: W1 face a runs 0..100, round the corner W2 face b
# 0..60, round the next corner W3 face a 0..100. W9 is the tiled wall of
# another bathroom that touches nothing here.
AREAS = [
  { id: 'A1', wall_id: 'W1', side: 'a', u0: 0.0,  w: 100.0 },
  { id: 'A2', wall_id: 'W2', side: 'b', u0: 0.0,  w: 60.0 },
  { id: 'A3', wall_id: 'W3', side: 'a', u0: 0.0,  w: 100.0 },
  { id: 'A9', wall_id: 'W9', side: 'a', u0: 0.0,  w: 80.0 },
  # a second area on W1, the same face, but not touching the corner
  { id: 'A5', wall_id: 'W1', side: 'a', u0: 20.0, w: 30.0 }
]
# The corner map, both ways round.
NB = lambda do |wall_id, side, u|
  case [wall_id, side, u.round(1)]
  when ['W1', 'a', 100.0] then { wall_id: 'W2', side: 'b', u_from: 0.0,  dir: 1.0 }
  when ['W2', 'b', 0.0]   then { wall_id: 'W1', side: 'a', u_from: 100.0, dir: -1.0 }
  when ['W2', 'b', 60.0]  then { wall_id: 'W3', side: 'a', u_from: 0.0,  dir: 1.0 }
  when ['W3', 'a', 0.0]   then { wall_id: 'W2', side: 'b', u_from: 60.0, dir: -1.0 }
  end
end

ok('from the first wall the chain reaches all three, itself first',
   TW.chain_ids(AREAS, 'A1', NB) == %w[A1 A2 A3], TW.chain_ids(AREAS, 'A1', NB))
ok('from the middle wall it reaches both ways',
   TW.chain_ids(AREAS, 'A2', NB).sort == %w[A1 A2 A3], TW.chain_ids(AREAS, 'A2', NB))
ok('from the last wall it walks back to the first',
   TW.chain_ids(AREAS, 'A3', NB).sort == %w[A1 A2 A3])
ok('the other bathroom is NOT in the shower',
   !TW.chain_ids(AREAS, 'A1', NB).include?('A9'))
ok('an area on the same face that does not reach the corner is not joined either',
   !TW.chain_ids(AREAS, 'A1', NB).include?('A5'))
ok('an area joined to nothing is a shower of one', TW.chain_ids(AREAS, 'A9', NB) == ['A9'])
ok('an area that starts a hair off the corner still counts - the corner square, a slip of the mouse',
   TW.chain_ids(AREAS.map { |a| a[:id] == 'A2' ? a.merge(u0: 1.5, w: 58.5) : a }, 'A1', NB) == %w[A1 A2 A3])
ok('but one that starts a foot away is another area, not this shower',
   TW.chain_ids(AREAS.map { |a| a[:id] == 'A2' ? a.merge(u0: 12.0, w: 48.0) : a }, 'A1', NB) == ['A1'])
ok('the tolerance is a number with a name', TW.const_defined?(:CHAIN_TOL))

# ---- 2. THE REAL PATH ---------------------------------------------------
def mk_area(id, wall_id, side, u0, w, h, ox)
  g = Sketchup::Group.new
  { 'type' => 'tile_wall', 'id' => id, 'wall_id' => wall_id, 'side' => side,
    'u0' => u0, 'z0' => 0.0, 'area_w' => w, 'area_h' => h,
    'material_card_id' => 'OLD', 'tile_w' => 12.0, 'tile_l' => 12.0,
    'tile_depth' => 0.625, 'tile_mode' => 'tiles', 'pattern_grout' => 0.125,
    'pattern_grout_color' => 'light', 'pattern_stagger' => 0.0,
    'pattern_angle' => 0.0, 'pattern_ox' => ox, 'pattern_oy' => 0.0,
    'pattern_center' => false }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
A1 = mk_area('A1', 'W1', 'a', 0.0, 100.0, 96.0, 0.0)
A2 = mk_area('A2', 'W2', 'b', 0.0, 60.0, 96.0, 7.5)
A3 = mk_area('A3', 'W3', 'a', 0.0, 100.0, 96.0, 3.0)
A9 = mk_area('A9', 'W9', 'a', 0.0, 80.0, 96.0, 0.0)
WALL = Sketchup::Group.new
WALL.set_attribute('InteriorPro', 'type', 'wall')

$builds = []
class << TW
  def areas_in_model(_m = nil); [$a1, $a2, $a3, $a9]; end
  def wall_by_id(_id, _m = nil); $wall; end
  def build!(**kw); $builds << kw; [$a1, $a2, $a3, $a9].find { |g| g.get_attribute('InteriorPro', 'id') == kw[:id] }; end
  def refresh_corner_neighbours!(_g, _m = nil); 0; end
  def connected_areas(g, _m = nil); g.get_attribute('InteriorPro', 'id') == 'A9' ? [g] : [$a1, $a2, $a3]; end
end
$a1 = A1; $a2 = A2; $a3 = A3; $a9 = A9; $wall = WALL

CFG = { 'card' => 'NEW', 'tile' => '24x12', 'mode' => 'tiles',
        'grout' => 0.0625, 'gcolor' => 'gray', 'stagger' => 0.5, 'depth' => 0.5,
        'center' => true, 'ox' => 4.0, 'oy' => 0.0, 'angle' => 0.0,
        'w' => 100.0, 'h' => 84.0, 'u0' => 0.0, 'z0' => 0.0 }

# This wall only.
$builds = []
D.apply!('A1', CFG.merge('whole' => false))
ok('THIS WALL ONLY rebuilds one area', $builds.length == 1, $builds.length)
ok('and it is the one he clicked', $builds[0][:id] == 'A1')

# The whole shower.
$builds = []
D.apply!('A1', CFG.merge('whole' => true))
ok('THE WHOLE SHOWER rebuilds every area in the chain, and no other',
   $builds.map { |b| b[:id] }.sort == %w[A1 A2 A3], $builds.map { |b| b[:id] })
ok('the other bathroom was left alone', $builds.none? { |b| b[:id] == 'A9' })
b2 = $builds.find { |b| b[:id] == 'A2' }
b3 = $builds.find { |b| b[:id] == 'A3' }
ok('the material went to all of them', $builds.all? { |b| b[:card_id] == 'NEW' })
ok('the tile size went to all of them', $builds.all? { |b| b[:tile_w] == 24.0 && b[:tile_l] == 12.0 })
ok('the grout, its colour, the offset and the depth went to all of them',
   $builds.all? { |b| b[:grout] == 0.0625 && b[:grout_color] == 'gray' && b[:stagger] == 0.5 && b[:depth] == 0.5 })
ok('the HEIGHT went to all of them - that is what he named first',
   $builds.all? { |b| b[:h] == 84.0 }, $builds.map { |b| b[:h] })
ok('each wall keeps its OWN width', b2[:w] == 60.0 && b3[:w] == 100.0, [b2[:w], b3[:w]])
ok('each wall keeps its OWN place on the wall', b2[:u0] == 0.0 && b2[:side] == 'b')
ok('each wall keeps its OWN pattern shift - the phase that carried round the corner',
   b2[:ox] == 7.5 && b3[:ox] == 3.0, [b2[:ox], b3[:ox]])
ok('and each keeps its own id, so nothing is added, only rebuilt',
   $builds.map { |b| b[:id] }.uniq.length == 3)

SRC = File.read('./tile_wall_edit_tool.rb')
ok('the window has the choice, and THIS WALL ONLY is the one that is ticked',
   SRC.include?('id="scope_one" checked') && SRC.include?('id="scope_all"'))
ok('the window says how many walls the shower has', SRC.include?("'chain'   => tw.connected_areas(g).length"))
ok('an area joined to nothing cannot be told to do the whole shower',
   SRC.include?("if (D.chain < 2)") && SRC.include?("scope_all').disabled = true"))

puts($fails.zero? ? 'rt182 all green' : "rt182 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

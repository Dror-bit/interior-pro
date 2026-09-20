# encoding: utf-8
# rt189 - THE LAST TILE MEETS ONLY THE PREVIOUS TILE, AND THE CORNER STILL
# GETS ITS EMPTY SQUARE (2026-09-20).
#
# His picture: four tiled walls round a square, one corner filled solid and
# three with the empty square. Measured in tile_corner_report.txt: at that
# one corner the last area's end sits one tile depth (5/8") in front of the
# previous area's wall corner, so refresh_corner_neighbours! - which used
# neighbour_at, matching only within 0.51" - never re-laid the previous
# area, and its end stayed run full into the corner.
#
# corner_neighbour_wall_ids finds a corner by world-space proximity of the
# two areas' ends (within a tile depth), so the 5/8" gap no longer hides it.
# HIS walls, read out of tile_corner_report.txt.
require './sketchup_stub'
require './tile_wall'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

Sketchup.reset_model!
M = Sketchup.active_model
def wall(a)
  g = M.entities.add_group
  a.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  z0 = Struct.new(:z).new(0.0)
  g.define_singleton_method(:bounds) { Struct.new(:min).new(z0) }
  g
end
def area(a)
  g = M.entities.add_group
  { 'type' => 'tile_wall', 'z0' => 0.0, 'tile_depth' => 0.625 }.merge(
    a.transform_keys(&:to_s)
  ).each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end

TW = InteriorPro::TileWall
E  = wall(type: 'wall', id: '6269165a', start_x: -438.0, start_y: 183.0, end_x: -438.0, end_y: 407.5, thickness: 5.0, height: 96.0, anchor: 'left')
IH = wall(type: 'wall', id: '849179b2', start_x: -534.6, start_y: 327.918, end_x: -443.0, end_y: 327.918, thickness: 4.5, height: 96.0, anchor: 'left')

# The two areas that make the filled corner in his model.
A_IH = area(id: 'TW019', wall_id: '849179b2', side: 'a', u0: 4.5,     area_w: 87.099)
A_E  = area(id: 'TW025', wall_id: '6269165a', side: 'a', u0: 150.043, area_w: 68.832)

# The east area was drawn last. When it is laid, the horizontal wall's area
# must be found as a corner neighbour so it can pull its end back.
ids = TW.corner_neighbour_wall_ids(A_E, M)
ok('drawing the east area finds the horizontal wall as a corner neighbour',
   ids.include?('849179b2'), ids)

# And it is symmetric - laying the horizontal one finds the east wall.
ids2 = TW.corner_neighbour_wall_ids(A_IH, M)
ok('and the other way round', ids2.include?('6269165a'), ids2)

# The exact gap that used to hide it: the two ends are 0.625 apart, more
# than neighbour_at's 0.51" window - so the OLD path (neighbour_at) missed.
fr_e = TW.frame_for(E, 'a')
nb = TW.neighbour_at(E, fr_e, 150.043, M)
ok('the old neighbour_at path could NOT see this corner (0.625 > 0.51)', nb.nil?, nb)

# A parallel wall is never a corner - the two long outside walls of a room.
W_FAR = wall(type: 'wall', id: 'wfar', start_x: -438.0, start_y: 183.0, end_x: -534.6, end_y: 183.0, thickness: 5.0, height: 96.0, anchor: 'left')
A_FAR = area(id: 'TWfar', wall_id: 'wfar', side: 'a', u0: 0.0, area_w: 40.0)
ids3 = TW.corner_neighbour_wall_ids(A_FAR, M)
ok('a wall square across the room, sharing no corner, is not pulled in',
   !ids3.include?('849179b2'), ids3)

# And refresh_corner_neighbours! is wired to the helper.
SRC = File.read('./tile_wall.rb')
ok('refresh_corner_neighbours! uses the corner helper, not neighbour_at',
   SRC.include?('corner_neighbour_wall_ids(grp, model).each { |wid| n += refresh_wall!(wid) }') &&
   SRC[/def self\.refresh_corner_neighbours!.*?\n    end\n/m] !~ /neighbour_at/)

puts($fails.zero? ? 'rt189 all green' : "rt189 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

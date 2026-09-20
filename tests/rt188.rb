# encoding: utf-8
# rt188 - ROUND THE CORNER, INTO THE SAME ROOM (2026-09-20).
#
# His picture: the run hopped round the corner of Room 2 and landed on the
# FAR side of the interior wall - in the next room. From there face_limits
# collapsed the area to nothing and the tool would not draw anything at
# all ("הוא לא נותן לי לצייר על הקיר הזה את האריחים").
#
# neighbour_at used to take the first direction that had room (+1), and
# only fell back to -1 when the +1 side was at the end of the wall. The
# room a run is in is not a matter of order: THIS wall blocks a2..b2 of
# the next face, and the face being tiled crosses that face at exactly
# one of those two ends. That end is the room we are standing in.
#
# The walls below are HIS model, read out of tile_stretch_report.txt.
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

TW = InteriorPro::TileWall
# The four outside walls of his plan, 5" thick, anchored left.
W_W = wall(type: 'wall', id: 'west',  start_x: -702.0, start_y: 407.5, end_x: -702.0, end_y: 183.0, thickness: 5.0, height: 96.0, anchor: 'left')
W_S = wall(type: 'wall', id: 'south', start_x: -702.0, start_y: 183.0, end_x: -438.0, end_y: 183.0, thickness: 5.0, height: 96.0, anchor: 'left')
W_E = wall(type: 'wall', id: 'east',  start_x: -438.0, start_y: 183.0, end_x: -438.0, end_y: 407.5, thickness: 5.0, height: 96.0, anchor: 'left')
W_N = wall(type: 'wall', id: 'north', start_x: -438.0, start_y: 407.5, end_x: -702.0, end_y: 407.5, thickness: 5.0, height: 96.0, anchor: 'left')
# Room 2's two interior walls, 4.5" thick.
I_V = wall(type: 'wall', id: 'ivert', start_x: -534.6, start_y: 402.5,  end_x: -534.6, end_y: 327.92, thickness: 4.5, height: 96.0, anchor: 'left')
I_H = wall(type: 'wall', id: 'ihorz', start_x: -534.6, start_y: 327.92, end_x: -443.0, end_y: 327.92, thickness: 4.5, height: 96.0, anchor: 'left')

fr_iv = TW.frame_for(I_V, 'a')   # the vertical interior wall, Room 2 side
ok('the tiled face is 74.58 long', (fr_iv[:len] - 74.582).abs < 0.01, fr_iv[:len])

# THE BUG: at u = 0 that face runs into the north wall.
nb = TW.neighbour_at(I_V, fr_iv, 0.0, M)
ok('the run carries on onto the north wall', nb && nb[:wall].equal?(W_N), nb && nb[:wall].get_attribute('InteriorPro', 'id'))
ok('...on its room face', nb && nb[:side] == 'a', nb && nb[:side])
ok('...starting at the interior wall\'s ROOM face, u 92.1 - not 96.6 on the far side',
   nb && (nb[:u_from] - 92.1).abs < 0.05, nb && nb[:u_from])
ok('...and heading back along the room, not away from it', nb && nb[:dir] == -1.0, nb && nb[:dir])
ok('...with room left to draw', nb && nb[:u_from] > 1.0)

# AND THE TWO THAT WERE ALREADY RIGHT - they must not flip.
nb2 = TW.neighbour_at(I_V, fr_iv, 70.082, M)   # where the tiles stop, at the horizontal wall
ok('at the other end the run carries on onto the horizontal interior wall',
   nb2 && nb2[:wall].equal?(I_H) && nb2[:side] == 'a', nb2)
ok('...from u 4.5 going up', nb2 && (nb2[:u_from] - 4.5).abs < 0.05 && nb2[:dir] == 1.0, nb2)

fr_ih = TW.frame_for(I_H, 'a')
nb3 = TW.neighbour_at(I_H, fr_ih, 4.5, M)
ok('back the other way: onto the vertical interior wall from u 70.08 going down',
   nb3 && nb3[:wall].equal?(I_V) && (nb3[:u_from] - 70.082).abs < 0.05 && nb3[:dir] == -1.0, nb3)

# THE REAL PATH: with the right start the area can actually be built.
fr_n = TW.frame_for(W_N, 'a')
lo, hi = TW.face_limits(W_N, fr_n, nb[:u_from] - 0.25, M)
ok('from the room face there is a clear run to draw into', (hi - lo) > 80.0, [lo, hi])
lo2, hi2 = TW.face_limits(W_N, fr_n, 96.6 - 0.25, M)
ok('from the far face (the old answer) the room he clicked in was out of bounds',
   lo2 > 90.0, [lo2, hi2])

puts($fails.zero? ? 'rt188 all green' : "rt188 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

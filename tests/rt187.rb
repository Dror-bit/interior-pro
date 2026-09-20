# encoding: utf-8
# rt187 - THE CORNER BELONGS TO THE WALL HE CAME FROM (2026-09-18).
#
# Measured with debug_tile_pick.rb on his model: at the T corner between
# the interior wall and the exterior wall, the pick under the cursor
# returns ONE path - the interior wall's long face. The exterior face is
# not under that pixel at all, so no rule about "which face" can choose
# it. What can: the wall and side the mouse was last sliding on freely
# stay in force while the inference point sits on an edge or a corner.
require './tile_wall'
require './tile_wall_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

T = InteriorPro::TileWallTool

# ---- on_edge_or_point? : the gate ---------------------------------------
IP = Struct.new(:vertex, :degrees_of_freedom)
t = T.allocate
ok('a vertex is a point', t.on_edge_or_point?(IP.new(:v, 0)))
ok('no freedom is a point', t.on_edge_or_point?(IP.new(nil, 0)))
ok('one freedom (an edge) counts too', t.on_edge_or_point?(IP.new(nil, 1)))
ok('two freedoms (sliding on a face) does NOT', !t.on_edge_or_point?(IP.new(nil, 2)))
ok('three (free in space) does not', !t.on_edge_or_point?(IP.new(nil, 3)))
ok('nil is not', !t.on_edge_or_point?(nil))
ok('locked_point? is unchanged: an edge is still not a locked POINT',
   !t.locked_point?(IP.new(nil, 1)) && t.locked_point?(IP.new(nil, 0)))

# ---- a point in the MIDDLE of a face belongs to that wall ---------------
require './sketchup_stub'
Sketchup.reset_model!
M = Sketchup.active_model
def wall(a)
  g = M.entities.add_group
  a.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  z0 = Struct.new(:z).new(0.0)
  g.define_singleton_method(:bounds) { Struct.new(:min).new(z0) }
  g
end
# Exterior wall runs north along x=0, 5 thick, centred: faces at x=+-2.5.
EXT = wall(type: 'wall', id: 'ext', start_x: 0.0, start_y: 0.0, end_x: 0.0, end_y: 200.0,
           thickness: 5.0, height: 96.0)
# Interior wall runs east from that face, its start ON the exterior face.
INT = wall(type: 'wall', id: 'int', start_x: 2.5, start_y: 100.0, end_x: 120.0, end_y: 100.0,
           thickness: 4.5, height: 96.0)
P = Geom::Point3d
corner = P.new(2.5, 100.0, 0.0)              # the purple dot
r = t.wall_mid_face_at(corner, M)
ok('the corner is the END of the interior wall and the MIDDLE of the exterior face -> exterior',
   r && r[:wall].equal?(EXT), r && r[:wall].get_attribute('InteriorPro', 'id'))
ok('...on the face that looks into the room (+x side)', r && r[:side] == 'b', r)
ok('...and u is where the interior wall stands', r && (r[:u] - 100.0).abs < 1e-6, r)
r2 = t.wall_mid_face_at(P.new(60.0, 102.25, 48.0), M)
ok('a point half way along the interior wall face is the interior wall',
   r2 && r2[:wall].equal?(INT) && r2[:side] == 'a', r2)
ok('the far end of the exterior wall is nobody\'s middle',
   t.wall_mid_face_at(P.new(2.5, 200.0, 0.0), M).nil?)
ok('a point above the wall is not on it',
   t.wall_mid_face_at(P.new(2.5, 50.0, 120.0), M).nil?)
# THE PURPLE DOT (his second picture): the interior wall's corner vertex
# standing INSIDE the exterior wall, on its centre line, 2.5" behind the
# room face. Seen from the room (eye at +x) it is the exterior wall's
# room face; seen from outside it is the outside face.
deep = P.new(0.0, 100.0, 0.0)
r3 = t.wall_mid_face_at(deep, M, P.new(60.0, 100.0, 60.0))
ok('a corner vertex inside the exterior wall body still belongs to the exterior wall',
   r3 && r3[:wall].equal?(EXT) && r3[:inside], r3)
ok('...on the face that looks at the camera - the room side',
   r3 && r3[:side] == 'b', r3)
r4 = t.wall_mid_face_at(deep, M, P.new(-60.0, 100.0, 60.0))
ok('...and from outside, the outside face', r4 && r4[:side] == 'a', r4)
ok('a point ON a face is still found first, before the inside pass',
   !t.wall_mid_face_at(corner, M)[:inside])
ok('face_point hands the camera eye along',
   File.read('./tile_wall_tool.rb').include?('wall_mid_face_at(pos, Sketchup.active_model, eye)'))
ok('a point out in the room is not on any face',
   t.wall_mid_face_at(P.new(40.0, 50.0, 10.0), M).nil?)

# ---- BOTH walls at that corner: the drag decides ------------------------
# First click on the purple dot lands on the exterior wall (room face 'b'),
# with the interior wall remembered as the other choice.
TW = InteriorPro::TileWall
t2 = T.allocate
fr_ext = TW.frame_for(EXT, 'b')
t2.instance_variable_set(:@wall, EXT)
t2.instance_variable_set(:@side, 'b')
t2.instance_variable_set(:@frame, fr_ext)
t2.instance_variable_set(:@len, fr_ext[:len])
t2.instance_variable_set(:@hgt, 96.0)
t2.instance_variable_set(:@holes, [])
t2.instance_variable_set(:@first, { u: 100.0, z: 0.0, kind: :corner, wall: EXT, side: 'b', pos: corner })
t2.instance_variable_set(:@alt, { wall: INT, side: nil })
# mouse slides along the exterior face - nothing changes
t2.swap_to_alt!(P.new(2.5, 60.0, 40.0))
ok('dragging along the exterior face keeps the exterior wall', t2.instance_variable_get(:@wall).equal?(EXT))
# mouse goes onto the interior wall's room face (y = 100 - 2.25 = 97.75, side 'b')
t2.swap_to_alt!(P.new(60.0, 97.75, 40.0))
ok('dragging onto the interior face moves the area to the interior wall', t2.instance_variable_get(:@wall).equal?(INT))
f1 = t2.instance_variable_get(:@first)
ok('the first corner is re-measured on that face: u at its start', (f1[:u] - 0.0).abs < 1e-6, f1)
ok('...and the side is the one the mouse is on', t2.instance_variable_get(:@side) == 'b', t2.instance_variable_get(:@side))
ok('the exterior wall is now the other choice', t2.instance_variable_get(:@alt)[:wall].equal?(EXT))
# and back again
t2.swap_to_alt!(P.new(2.5, 60.0, 40.0))
ok('he can change his mind and drag back to the exterior wall', t2.instance_variable_get(:@wall).equal?(EXT))
ok('...where the first corner is u = 100 again', (t2.instance_variable_get(:@first)[:u] - 100.0).abs < 1e-6)

# ---- the other wall is the one that ENDS here, found from geometry ------
ok('the interior wall ends at the corner', t.wall_ending_at(corner, EXT, M).equal?(INT))
ok('nothing else ends half way along the exterior wall', t.wall_ending_at(P.new(2.5, 50.0, 0.0), EXT, M).nil?)
ok('the exterior wall itself is never its own other', t.wall_ending_at(P.new(0.0, 0.0, 0.0), EXT, M).nil?)

# ---- the tile cannot walk through the interior wall --------------------
fr_b = TW.frame_for(EXT, 'b')
# the interior wall blocks u = 97.75 .. 102.25 on the exterior room face
lo, hi = TW.face_limits(EXT, fr_b, 100.0 - 0.25, M)
ok('drawing from the corner AWAY from the interior wall: the wall is the far limit', (hi - 97.75).abs < 1e-6 && lo == 0.0, [lo, hi])
lo, hi = TW.face_limits(EXT, fr_b, 100.0 + 0.25, M)
ok('drawing from the corner the other way: the wall is the near limit', (lo - 102.25).abs < 1e-6, [lo, hi])
lo, hi = TW.face_limits(EXT, fr_b, 99.0, M)
ok('a ref INSIDE the wall is no longer skipped in silence - the nearer face limits', (hi - 97.75).abs < 1e-6, [lo, hi])
bsrc = SRC_ALL = File.read('./tile_wall_tool.rb')
ok('build! clamps both corners to face_limits before building',
   bsrc.include?('lo, hi = InteriorPro::TileWall.face_limits(@wall, @frame, ref)') &&
   bsrc.include?('au = a[:u].clamp(lo, hi)') && bsrc.include?('bu = b[:u].clamp(lo, hi)'))
ok('...measured a hair from the first corner towards the second',
   bsrc.include?("ref = a[:u] + (b[:u] >= a[:u] ? 0.25 : -0.25)"))

# ---- the real path ------------------------------------------------------
SRC = File.read('./tile_wall_tool.rb')
fp = SRC[/def face_point.*?\n    end\n/m]
ok('face_point asks the gate', fp.include?('on_point = on_edge_or_point?(ip)'))
ok('on a point, the wall whose face runs THROUGH it is asked first',
   fp.include?('mid = on_point && !@first ? wall_mid_face_at(pos, Sketchup.active_model, eye) : nil') &&
   fp.include?("elsif mid\n") && fp.include?('wall = mid[:wall]') && fp.include?('hint = mid[:side]'))
ok('on an edge or corner the remembered wall wins over the pick',
   fp.include?('elsif on_point && @hover_wall&.valid?') &&
   fp.include?('wall = @hover_wall') && fp.include?('hint = @hover_side'))
ok('and the remembered SIDE wins too - side_from_face is not re-asked',
   fp.include?('side = hint || side_from_face(view, x, y, wall) || side_of(wall, pos)'))
ok('the memory is written only while sliding freely, and never once the first corner is down',
   fp.include?('unless @first || on_point') &&
   fp.include?('@hover_wall = wall') && fp.include?('@hover_side = @side'))
# THE SWAP HAS TO STICK (2026-09-20). `wall` was read BEFORE swap_to_alt!,
# and the frame block below then rebuilt everything for that stale wall and
# put @wall back - undoing the swap on the same move, while @first had
# already been re-measured onto the other wall. The area then ran from the
# interior wall's u to the exterior wall's u: straight past the corner into
# the next room. His picture, 2026-09-20.
ok('with the first corner down the wall is read AFTER the swap, so the swap sticks',
   fp.include?("swap_to_alt!(pos) if @alt\n        wall = @wall"))
ok('...and it is not read before the swap any more',
   !fp.include?("if @first\n        wall = @wall"))
ok('the first click keeps the other wall, the second forgets it',
   SRC.include?("@alt = p[:alt]") && SRC.include?("@alt = nil\n        build!(@first, p, view)"))
ok('while the second corner is open the mouse face decides',
   fp.include?('swap_to_alt!(pos) if @alt'))
ok('the memory is cleared with the area',
   SRC[/def reset_area.*?\n    end\n/m].include?('@hover_wall = nil'))

puts($fails.zero? ? 'rt187 all green' : "rt187 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

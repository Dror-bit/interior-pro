# encoding: utf-8
# rt181 - THE SIDE OF THE WALL HE CLICKED ON (2026-09-18).
#
# His picture: "סימנתי אותו מצד אחד של הקיר והוא צייר לי אותו מהצד השני."
# He marked the face inside the room and the tile came out on the face
# of the next room.
#
# WHY. The side was worked out from the INFERENCE point - and that point
# is very often a VERTEX, which is exactly what the point law asks for
# everywhere else in this tool. But a wall corner carries vertices on
# BOTH of its faces: aim at the corner of the near face and SketchUp can
# hand back the vertex standing on the far one, a wall thickness away.
# side_of then measures that far point and answers with the far side.
#
# THE FIX: ask the FACE the mouse ray really hit first. A face's own
# normal points out of the wall, so it cannot be ambiguous. The point is
# still what gives u and z - only the SIDE stopped coming from it.
require './tile_wall'
require './tile_wall_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

T = InteriorPro::TileWallTool
TW = InteriorPro::TileWall

# ---- 1. the left perpendicular is the SAME one TileWall.frame uses ------
# A wall running east: start (0,0) -> end (100,0). Left of that is +Y.
n = T.left_normal(0.0, 0.0, 100.0, 0.0)
ok('left of a wall running east is +Y', n[0].abs < 1e-9 && (n[1] - 1.0).abs < 1e-9, n)

fa = TW.frame(0.0, 0.0, 100.0, 0.0, 5.0, 'center', 'a')
fb = TW.frame(0.0, 0.0, 100.0, 0.0, 5.0, 'center', 'b')
ok("face 'a' really is the one on that side - the same 'a' the builder uses",
   fa[:oy] > 0 && fb[:oy] < 0, [fa[:oy], fb[:oy]])
ok('and its own outward normal points the same way', (fa[:ny] - 1.0).abs < 1e-9, fa[:ny])

ok('a wall with no length has no side', T.left_normal(5.0, 5.0, 5.0, 5.0).nil?)

# ---- 2. the face normal decides, and nothing else ----------------------
S = ->(fx, fy) { T.side_from_normal(n[0], n[1], fx, fy) }
ok("a face looking +Y is side 'a'", S.call(0.0, 1.0) == 'a')
ok("a face looking -Y is side 'b'", S.call(0.0, -1.0) == 'b')
ok('the TOP of the wall is neither - its normal lies flat here',
   S.call(0.0, 0.0).nil?)
ok('and an end cap, looking along the wall, is neither',
   S.call(1.0, 0.0).nil? && S.call(-1.0, 0.0).nil?)
ok('a face tilted a little still answers, it does not go silent',
   S.call(0.2, 0.98) == 'a')

# A wall running NORTH: start (0,0) -> end (0,100). Left is -X.
n2 = T.left_normal(0.0, 0.0, 0.0, 100.0)
ok('left of a wall running north is -X', (n2[0] + 1.0).abs < 1e-9 && n2[1].abs < 1e-9, n2)
ok("so a face looking -X is 'a' on that wall",
   T.side_from_normal(n2[0], n2[1], -1.0, 0.0) == 'a')
ok("and one looking +X is 'b'",
   T.side_from_normal(n2[0], n2[1], 1.0, 0.0) == 'b')

# ---- 3. THE REAL PATH ---------------------------------------------------
SRC = File.read('./tile_wall_tool.rb')
ok('the face the ray hit is asked FIRST, and the point only as a fallback',
   SRC.include?('side = side_from_face(view, x, y, wall) || side_of(wall, pos)'))
ok('and only a face of THIS wall counts - another object says nothing',
   SRC.include?('next unless path.any? { |e| e.equal?(wall) }'))
ok('the face is taken from the pick, with its own transformation',
   SRC.include?('ph.leaf_at(i)') && SRC.include?('ph.transformation_at(i)'))
ok('the side that was measured is printed - no silent skip (CLAUDE.md)',
   SRC.include?("[TileWall] the mouse is on face"))
ok('side_of, the fallback, now uses the same one perpendicular',
   SRC.include?('n = self.class.left_normal(sx, sy, ex, ey)'))

puts($fails.zero? ? 'rt181 all green' : "rt181 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt177 - THE CORNER SQUARE (2026-09-18).
#
# His design, in his words: "אני רוצה ששתי הפינות שלהם יפגשו ובאמצע יהיה
# ריבוע שווה צלעות", and then "הפינות החיצוניות שלהם". Two tiled faces
# that meet in an inside corner stop so that their OUTER corners land on
# ONE point, and what is left between them and the wall corner is a
# square whose side is the tile's own stand-off depth. Nothing overlaps.
#
# The maths on its own proves nothing (CLAUDE.md): the pulled-back number
# has to reach the REAL path - area_polys and pieces_rect - and the
# number he drew has to be STORED untouched, or every rebuild would pull
# the area back again.
require './tile_wall'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TW = InteriorPro::TileWall
DEPTH = 0.625

ok('the feature has a kill switch', TW.const_defined?(:USE_CORNER_GAP))
ok('there is no fixed gap number any more - the tile depth is the gap',
   !TW.const_defined?(:CORNER_GAP, false))

# ---- 1. the trim itself -------------------------------------------------
ok('no corner, nothing moves', TW.trim_for_corners(10.0, 40.0) == [10.0, 40.0])

u, w = TW.trim_for_corners(10.0, 40.0, DEPTH, 0.0)
ok('a corner at the start moves the start in and leaves the far end put',
   (u - 10.625).abs < 1e-9 && (u + w - 50.0).abs < 1e-9, [u, w])

u, w = TW.trim_for_corners(10.0, 40.0, 0.0, DEPTH)
ok('a corner at the far end pulls back only that end',
   (u - 10.0).abs < 1e-9 && (u + w - 49.375).abs < 1e-9, [u, w])

u, w = TW.trim_for_corners(10.0, 40.0, DEPTH, DEPTH)
ok('a corner at both ends comes off both', (w - 38.75).abs < 1e-9, w)
ok('a negative pull is refused', TW.trim_for_corners(10.0, 40.0, -5.0) == [10.0, 40.0])

# ---- 2. THE PROMISE: the two outer corners land on one point ------------
# His own model, measured off it (tile_corner_report.txt): two 5" walls,
# left anchored, meeting at (-438, 407.5) at a right angle, both tiled on
# side a, 5/8" stand-off.
fb = TW.frame(-438.0, 183.0, -438.0, 407.5, 5.0, 'left', 'a')   # runs north
fa = TW.frame(-438.0, 407.5, -702.0, 407.5, 5.0, 'left', 'a')   # runs west
ok('side a of the north wall is the face he tiled', (fb[:ox] + 443.0).abs < 1e-9, fb[:ox])
ok('side a of the west wall is the face he tiled', (fa[:oy] - 402.5).abs < 1e-9, fa[:oy])

# How far an end already stands off the OTHER face - the same number
# corner_ends works out in the model.
stand_off = lambda do |fr, u, ofr|
  x, y, = TW.world(fr, u, 0.0, 0.0)
  (x - ofr[:ox]) * ofr[:nx] + (y - ofr[:oy]) * ofr[:ny]
end

b_end = 219.5     # he drew it right into the corner
a_start = 5.625   # and this one onto the neighbour's tile face
ok('the end drawn into the corner is flush with the other wall face',
   stand_off.call(fb, b_end, fa).abs < 1e-9, stand_off.call(fb, b_end, fa))
ok('the end drawn onto the tile already stands a tile depth off',
   (stand_off.call(fa, a_start, fb) - DEPTH).abs < 1e-9)

pull_b = DEPTH - stand_off.call(fb, b_end, fa)
pull_a = DEPTH - stand_off.call(fa, a_start, fb)
ok('so the flush end comes back a whole tile depth', (pull_b - DEPTH).abs < 1e-9, pull_b)
ok('and the end that is already right does not move at all', pull_a.abs < 1e-9, pull_a)

cb = TW.world(fb, b_end - pull_b, 0.0, DEPTH)
ca = TW.world(fa, a_start + pull_a, 0.0, DEPTH)
ok('THE TWO OUTER CORNERS LAND ON THE SAME POINT',
   (cb[0] - ca[0]).abs < 1e-9 && (cb[1] - ca[1]).abs < 1e-9, [cb, ca])

# and what is left at the corner is a square of the tile depth
side_b = stand_off.call(fb, b_end, fa) + pull_b
side_a = stand_off.call(fa, a_start, fb) + pull_a
ok('what is left empty at the corner is a SQUARE, equal on both sides',
   (side_a - side_b).abs < 1e-9 && (side_a - DEPTH).abs < 1e-9, [side_a, side_b])

# ---- 3. it really moves the tiles ---------------------------------------
tight = TW.pieces_rect(0.0, 0.0, 40.0, 40.0, [], u_size: 12.0, v_size: 12.0)
u2, w2 = TW.trim_for_corners(0.0, 40.0, 0.0, DEPTH)
short = TW.pieces_rect(u2, 0.0, w2, 40.0, [], u_size: 12.0, v_size: 12.0)
far = lambda { |ps| ps.flat_map { |p| p[:poly].map { |q| q[0] } }.max }
near = lambda { |ps| ps.flat_map { |p| p[:poly].map { |q| q[0] } }.min }
ok('the last tile stops a tile depth short of where it used to',
   (far.call(tight) - far.call(short) - DEPTH).abs < 1e-6,
   [far.call(tight), far.call(short)])
ok('and the end with no corner did not move',
   near.call(tight).round(6) == near.call(short).round(6))

# ---- 4. the real path, and what gets stored ------------------------------
SRC = File.read('./tile_wall.rb')
ok('build! works out how far each end has to come back',
   SRC.include?('lo, hi = corner_ends(wall, fr, u0, w, z0, model)'))
ok('the pulled-back numbers are what the area is cut from',
   SRC.include?('area = area_polys(bu0, z0, bw, h, holes)'))
ok('and what the tiles are laid from',
   SRC.include?('ps = pieces_rect(bu0, z0, bw, h, holes'))
ok('the whole-image way is pulled back too',
   SRC.include?('cut(bu0, z0, bu0 + bw, z0 + h, holes)'))
ok('what is STORED is what he drew, so a rebuild cannot pull it back twice',
   SRC.include?("set_attribute('InteriorPro', 'u0', u0)") &&
   SRC.include?("set_attribute('InteriorPro', 'area_w', w)"))
ok('the pull is the neighbour tile depth minus what the end already stands off',
   SRC.include?('need = o[:dp] - d'))
ok('a corner that eats the whole area is refused out loud',
   SRC.include?('the corner square left nothing to tile'))
ok('only a wall at an angle to this one can make a corner with it',
   SRC.include?('fr[:ux] * ofr[:ux] + fr[:uy] * ofr[:uy]).abs > 0.99'))
ok('the corner test can never take the build down with it',
   SRC.include?('the corner test failed'))

puts($fails.zero? ? 'rt177 all green' : "rt177 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

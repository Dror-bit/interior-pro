# encoding: utf-8
# rt192 - THE NICHE (2026-09-20).
#
# His ask: "נישה בקיר אריחים - אותו מנגנון של שטח, עם עומק פנימה",
# depth typed, 4" by default. Three things have to be true:
#   1. the niche NEVER cuts through the wall - a thin wall shortens it,
#   2. the cutting box stands on the SAME plane the tiled area uses and
#      goes IN, not out (the sign that would have built a lump on the
#      face instead of a hole),
#   3. a niche on one face is a hole for the tile on THAT face only.
require './tile_niche'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TN = InteriorPro::TileNiche
TW = InteriorPro::TileWall

# ---- 1. it never goes through the wall --------------------------------
ok('4" fits in a 6" wall', TN.clamp_depth(4.0, 6.0) == 4.0, TN.clamp_depth(4.0, 6.0))
ok('a 4.5" wall keeps half an inch behind it',
   (TN.clamp_depth(4.0, 4.5) - 4.0).abs < 1e-9, TN.clamp_depth(4.0, 4.5))
ok('a 4" wall shortens the niche to 3.5"',
   (TN.clamp_depth(4.0, 4.0) - 3.5).abs < 1e-9, TN.clamp_depth(4.0, 4.0))
ok('a 1/2" wall has no room at all', TN.clamp_depth(4.0, 0.5) == 0.0, TN.clamp_depth(4.0, 0.5))
ok('no depth given falls back to his 4"', TN.clamp_depth(0.0, 12.0) == 4.0)

# ---- 2. the box is on the face and goes IN ----------------------------
# The same wall rt175 uses: along +x, 6" thick, centred, floor at z = 100.
fa = TW.frame(0.0, 0.0, 96.0, 0.0, 6.0, 'center', 'a', 100.0)
front, back = TN.box_corners(fa, 24.0, 36.0, 24.0, 30.0, 4.0)
ok('the front of the box stands proud of the face',
   (front[0][1] - (3.0 + TN::OVER)).abs < 1e-9, front[0])
ok('the back of the box is 4" INSIDE the wall',
   (back[0][1] - (3.0 - 4.0)).abs < 1e-9, back[0])
ok('and it is still inside the wall body', back.all? { |p| p[1] > -3.0 })
ok('the box starts where he clicked, along the wall',
   front[0][0].round(6) == 24.0 && front[1][0].round(6) == 48.0, front)
ok('and at the height he clicked, off the wall floor',
   front[0][2].round(6) == 136.0 && front[3][2].round(6) == 166.0, front)

fb = TW.frame(0.0, 0.0, 96.0, 0.0, 6.0, 'center', 'b', 100.0)
_fr2, back2 = TN.box_corners(fb, 24.0, 36.0, 24.0, 30.0, 4.0)
ok('on side b it goes in the other way', (back2[0][1] - (-3.0 + 4.0)).abs < 1e-9, back2[0])

# ---- 3. a niche is a hole for the tile on ITS OWN face ----------------
ns = [TN.normalize(['a', 24.0, 36.0, 24.0, 30.0, 4.0]),
      TN.normalize(['b', 10.0, 12.0, 20.0, 20.0, 3.0])]
ok('a stored row reads back', ns.compact.length == 2, ns)
ha = TN.holes_for_side(ns, 'a')
hb = TN.holes_for_side(ns, 'b')
ok('side a sees only its own niche', ha == [[24.0, 36.0, 48.0, 66.0]], ha)
ok('side b sees only its own', hb == [[10.0, 12.0, 30.0, 32.0]], hb)
ok('a row survives a round trip', TN.normalize(TN.to_row(ns[0])) == ns[0])

# and the tile really goes round it: the area minus that hole is four
# pieces, never one that runs over the niche.
area = TW.area_polys(0.0, 0.0, 96.0, 96.0, ha)
ok('the tiled area is broken around the niche', area.length == 4, area.length)
ok('and no piece covers the middle of the niche',
   area.none? { |p| p.all? { |u, z| u >= 24.0 - 1e-9 && u <= 48.0 + 1e-9 && z >= 36.0 - 1e-9 && z <= 66.0 + 1e-9 } })

puts($fails.zero? ? 'rt192 OK' : "rt192 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

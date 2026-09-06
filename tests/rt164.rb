# encoding: utf-8
# rt164 - TILES ARE COUNTED AS TILES (2026-09-06).
# "יש לי שתי חתיכות אז היא תמזג אותן ותספור לי אותן כחתיכה אחת" - a
# 24x48 cut in half, both halves used, is ONE tile bought. And his rule
# for the leftovers: under 20% of a tile is waste, never paired, and
# counted on its own line so he can price it with the contractor.
require './tile_count'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

TC = InteriorPro::TileCount
def rect(w, h, x = 0.0, y = 0.0)
  [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
end

# ---- 1. the geometry underneath --------------------------------------
ok('area of a 24x48 rectangle', near(TC.area(rect(24, 48)), 1152.0))
ok('a cell fully inside the room clips to itself',
   near(TC.area(TC.clip_rect(rect(100, 100), 0, 0, 24, 48)), 1152.0))
ok('a cell half off the room clips to half',
   near(TC.area(TC.clip_rect(rect(12, 100), 0, 0, 24, 48)), 576.0))
ok('a cell outside the room clips to nothing',
   TC.clip_rect(rect(10, 10), 50, 50, 74, 98).empty?)

# ---- 2. a room that needs no cutting ---------------------------------
full, cuts = TC.layout(rect(48, 96), 24, 48)
ok('a 48x96 room takes exactly 4 whole 24x48 tiles', full == 4, [full, cuts])
ok('...and nothing is cut', cuts.empty?, cuts)

# ---- 3. THE case he described ----------------------------------------
# 72" wide = three 24" columns; 48" tall = one row. Nothing cut.
full, cuts = TC.layout(rect(72, 48), 24, 48)
ok('72x48 is three whole tiles', full == 3 && cuts.empty?, [full, cuts])
# 60" wide = two whole columns and one 12" strip -> one cut per row
full, cuts = TC.layout(rect(60, 96), 24, 48)
ok('60x96: four whole tiles', full == 4, [full, cuts])
ok('...and two 12x48 cuts', cuts.length == 2 && cuts.all? { |c| c == [12.0, 48.0] }, cuts)
res = TC.count(full, cuts, 24, 48)
ok('the two 12" strips come out of ONE tile - the second is its offcut',
   res[:cut_tiles] == 1 && res[:paired] == 1, res)
ok('so five tiles are bought, not six', res[:tiles] == 5, res)
ok('and none of them is a small piece', res[:small_pieces].zero?, res)

# ---- 4. the 20% rule -------------------------------------------------
# a 4" strip off a 24x48 tile is 4*48 / 1152 = 16.7% -> waste
ok('a 4x48 strip is under 20%', TC.small?([4.0, 48.0], 24, 48))
ok('a 5x48 strip is over 20%', !TC.small?([5.0, 48.0], 24, 48))
full, cuts = TC.layout(rect(52, 96), 24, 48)
ok('52x96 leaves two 4" strips', cuts.length == 2 && cuts.all? { |c| c == [4.0, 48.0] }, cuts)
res = TC.count(full, cuts, 24, 48)
ok('they are NOT paired - each takes its own tile',
   res[:small_pieces] == 2 && res[:paired].zero?, res)
ok('...and they show on their own line, as he asked', res[:small_pieces] == 2)
ok('four whole plus two small = six tiles', res[:tiles] == 6, res)
res25 = TC.count(full, cuts, 24, 48, 10.0)
ok('with the threshold at 10% the same strips ARE paired',
   res25[:small_pieces].zero? && res25[:paired] == 1, res25)

# ---- 5. the offcut maths ---------------------------------------------
ok('cutting 12x48 off a 24x48 leaves 12x48', TC.offcut([12.0, 48.0], 24, 48) == [12.0, 48.0])
ok('cutting 24x20 off it leaves 24x28', TC.offcut([24.0, 20.0], 24, 48) == [24.0, 28.0])
ok('an offcut covers a piece that fits inside it', TC.fits?([12.0, 48.0], [12.0, 48.0]))
ok('...and one turned sideways', TC.fits?([48.0, 12.0], [12.0, 48.0]))
ok('but not one that is bigger', !TC.fits?([12.0, 48.0], [13.0, 48.0]))

# ---- 6. an L-shaped room still counts ---------------------------------
L = [[0, 0], [96, 0], [96, 48], [48, 48], [48, 96], [0, 96]]
full, cuts = TC.layout(L, 24, 48)
ok('the L is covered without a tile hanging outside it',
   full.positive? && cuts.all? { |c| c[0] <= 24.01 && c[1] <= 48.01 },
   [full, cuts])
res = TC.plan(L, 24, 48)
ok('plan() gives the same answer as layout+count', res[:full] == full, res)
ok('every tile bought is accounted for',
   res[:tiles] == res[:full] + res[:cut_tiles] + res[:small_pieces], res)

# ---- 7. grout moves the grid, it does not vanish ----------------------
f0, = TC.layout(rect(48, 96), 24, 48, grout: 0.0)
f1, c1 = TC.layout(rect(48, 96), 24, 48, grout: 0.25)
ok('with a joint the same room no longer holds four WHOLE tiles',
   f1 < f0 && !c1.empty?, [f0, f1, c1.length])

# ---- 8. the report lines ---------------------------------------------
ln = TC.lines(TC.count(4, [[12.0, 48.0], [12.0, 48.0]], 24, 48), 24, 48)
ok('the report names the tile', ln[0] == 'tile 24x48', ln[0])
ok('...the whole ones', ln[1] =~ /whole tiles\s+4/, ln[1])
ok('...where the cuts came from', ln[2] =~ /from 1 tiles, 1 taken from offcuts/, ln[2])
ok('...the small pieces on their own line', ln[3] =~ /under 20%\s+0/, ln[3])
ok('...and the number he orders', ln[4] =~ /TILES TO BUY\s+5/, ln[4])

puts($fails.zero? ? 'rt164 OK' : "rt164 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

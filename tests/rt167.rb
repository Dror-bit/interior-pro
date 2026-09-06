# encoding: utf-8
# rt167 - THE COUNT NOW READS THE SAME LAYOUT THE DRAWER WILL (2026-09-06).
#
# tile_count.rb used to lay its own grid, anchored on the model's ZERO
# POINT, and it knew nothing about the pattern angle or the centring.
# That is why the same room gave a different number depending on where
# it happened to sit in the model - measured on his own Bathroom 2,
# 2026-09-06, and the numbers below are that room, to the inch.
#
# Now it reads tile_grid.rb. USE_SHARED_GRID = false brings the old one
# back, and layout_legacy is still here, so this test pins both.
require './tile_count'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TC = InteriorPro::TileCount
def rect(w, h, x = 0.0, y = 0.0)
  [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
end

# His Bathroom 2: 283.071 x 362.696 inches, 713 sq ft, 48x24 tile, no joint.
ROOM = 283.071
WALL = 362.696

# ---- 1. the room stops depending on where it sits in the model -------
here = TC.plan(rect(ROOM, WALL), 48, 24)
there = TC.plan(rect(ROOM, WALL, 7.3, 4.1), 48, 24)
ok('the same room laid the same way needs the same tiles',
   here[:tiles] == there[:tiles], [here[:tiles], there[:tiles]])
ok('...every line of it, not just the total', here == there, [here, there])

f0, c0 = TC.layout_legacy(rect(ROOM, WALL), 48, 24, 0, 0, 0, 0)
f1, c1 = TC.layout_legacy(rect(ROOM, WALL, 7.3, 4.1), 48, 24, 0, 0, 0, 0)
old_here = TC.count(f0, c0, 48, 24)
old_there = TC.count(f1, c1, 48, 24)
ok('the OLD grid moved the answer when the room moved - this was the bug',
   old_here[:tiles] != old_there[:tiles], [old_here[:tiles], old_there[:tiles]])

# ---- 2. centring costs tiles, and now the count knows it -------------
# Starting on the wall leaves ONE wide strip; centring splits it into
# two, one at each wall - better looking, more tiles.
edge = TC.plan(rect(ROOM, WALL), 48, 24, centered: false)
mid = TC.plan(rect(ROOM, WALL), 48, 24, centered: true)
ok('starting on the wall: 96 tiles', edge[:tiles] == 96, edge)
ok('centred: 104 tiles - the number he checked by hand', mid[:tiles] == 104, mid)
ok('centring makes twice as many cuts', mid[:cut_pieces] == 2 * edge[:cut_pieces],
   [edge[:cut_pieces], mid[:cut_pieces]])
ok('...but they pair up, so only half of them come out of a new tile',
   mid[:cut_tiles] == 15 && mid[:paired] == 15, mid)
ok('the whole tiles are the same either way', mid[:full] == edge[:full], [edge[:full], mid[:full]])
ok('the old count could not tell the two apart',
   TC.layout_legacy(rect(ROOM, WALL), 48, 24, 0, 0, 0, 0) ==
   TC.layout_legacy(rect(ROOM, WALL), 48, 24, 0, 0, 0, 0))

# ---- 3. the angle reaches the count at last --------------------------
straight = TC.plan(rect(ROOM, WALL), 48, 24)
turned = TC.plan(rect(ROOM, WALL), 48, 24, angle: 30)
ok('a layout on the diagonal is not the same count as a straight one',
   turned[:tiles] != straight[:tiles], [straight[:tiles], turned[:tiles]])
ok('...and it costs more, which is what a tiler would tell him',
   turned[:tiles] > straight[:tiles], [straight[:tiles], turned[:tiles]])
ok('turning by a whole 90 degrees on a square room changes nothing',
   TC.plan(rect(96, 96), 24, 24)[:tiles] == TC.plan(rect(96, 96), 24, 24, angle: 90)[:tiles])

# ---- 4. a turned tile is measured across ITSELF, not across the model -
# Every cut piece must still fit inside one tile. Measured in the
# model's own x/y a turned cut looks bigger than the tile it came from.
_, cuts = TC.layout(rect(120, 120), 24, 48, angle: 37.0)
ok('no cut piece is bigger than the tile it was cut from',
   cuts.all? { |c| c[0] <= 24.0 + 0.07 && c[1] <= 48.0 + 0.07 },
   cuts.reject { |c| c[0] <= 24.07 && c[1] <= 48.07 }.first(4))

# ---- 5. the old answers are untouched --------------------------------
# rt164 pins these too; they are here so a change to the shared grid
# cannot quietly move them.
full, cuts = TC.layout(rect(60, 96), 24, 48)
res = TC.count(full, cuts, 24, 48)
ok('60x96 is still four whole tiles and two 12" strips',
   full == 4 && cuts.length == 2 && cuts.all? { |c| c == [12.0, 48.0] }, [full, cuts])
ok('...still five tiles bought, not six', res[:tiles] == 5, res)
ok('48x96 is still exactly four tiles, nothing cut',
   TC.layout(rect(48, 96), 24, 48) == [4, []], TC.layout(rect(48, 96), 24, 48))

# ---- 6. the kill switch is real --------------------------------------
ok('USE_SHARED_GRID is on', TC::USE_SHARED_GRID == true)
ok('layout_legacy is still here to fall back to', TC.respond_to?(:layout_legacy))
ok('the legacy grid still answers the old way',
   TC.layout_legacy(rect(48, 96), 24, 48, 0, 0, 0, 0) == [4, []])

puts($fails.zero? ? 'rt167 OK' : "rt167 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

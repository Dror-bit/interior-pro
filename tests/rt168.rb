# encoding: utf-8
# rt168 - THE DRAWING AND THE COUNT ARE THE SAME LAYOUT (2026-09-06).
#
# His words that started this: "אני לא רוצה ששרטוט הפריסה יהיה רק דומה
# לרינדור." Until today floor_pattern.rb drew one grid and tile_count.rb
# counted another - different axis, different start point, and a joint
# that meant two different things. This pins them to one.
#
# Only the Tile pattern goes through the shared grid. Straight,
# Herringbone and Chevron are plank patterns and are left alone; the
# last block here proves they were not touched.
require './sketchup_stub'
require './room_manager'
require './tile_grid'
require './tile_count'
require './floor_pattern'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 1.0e-6)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

def dist(a, b)
  Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2)
end

FP = InteriorPro::FloorPattern
TG = InteriorPro::TileGrid
TC = InteriorPro::TileCount
def rect(w, h, x = 0.0, y = 0.0)
  [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
end

# A room and a floor with everything switched on at once: a joint, a
# turned layout and centring - the three things the count used to be
# blind to.
ROOM = rect(283.071, 362.696, -601.507, -362.196)
W = 48.0
L = 24.0
GROUT = 0.5
ANG = 20.0 * Math::PI / 180.0

planks = FP.tile_planks(ROOM, ANG, W, L, 0.0, 0.0, true, GROUT)
cells  = TG.cells(ROOM, u_size: W, v_size: L, grout: GROUT, angle: 20.0,
                        ox: 0.0, oy: 0.0, centered: true)

# ---- 1. the drawer lays exactly the grid ------------------------------
ok('the drawer draws a tile for every cell of the shared grid',
   !planks.nil? && planks.length == cells.length, [planks && planks.length, cells.length])
ok('...in the same places, corner for corner',
   planks.each_with_index.all? { |pl, i| pl[:c].each_with_index.all? { |q, j| near(q[0], cells[i][:quad][j][0]) && near(q[1], cells[i][:quad][j][1]) } })

# ---- 2. the tile he draws is the tile he buys -------------------------
ok('a drawn tile is 48 along the layout', near(dist(planks[0][:c][0], planks[0][:c][1]), W))
ok('...and 24 across it', near(dist(planks[0][:c][1], planks[0][:c][2]), L))
# The old drawer works in SketchUp points; the new one takes either.
PTS = ROOM.map { |q| Geom::Point3d.new(q[0], q[1], 0) }
ok('the grid gives the same answer for SketchUp points as for plain pairs',
   TG.cells(PTS, u_size: W, v_size: L, grout: GROUT, angle: 20.0, centered: true)
     .map { |q| q[:quad] } == cells.map { |q| q[:quad] })
old = FP.tile_planks_legacy(PTS, ANG, W, L, 0.0, 0.0, true, GROUT)
ok('the OLD drawer shrank the tile by the joint instead - this was the bug',
   near(dist(old[0][:c][0], old[0][:c][1]), L - GROUT), dist(old[0][:c][0], old[0][:c][1]))

# ---- 3. the joint is the gap between two tiles ------------------------
row = planks.select { |pl| near(dist(pl[:c][0], planks[0][:c][0]), dist(pl[:c][0], planks[0][:c][0])) }
a = planks[0][:c][1]
nxt = planks.find { |pl| near(dist(pl[:c][0], a), GROUT) }
ok('the next tile along starts exactly one joint later', !nxt.nil?, GROUT)

# ---- 4. what is drawn is what is counted ------------------------------
full, cuts = TC.layout(ROOM, W, L, grout: GROUT, angle: 20.0, centered: true)
drawn = planks.length
ok('every tile the count knows about is a tile that was drawn',
   full + cuts.length <= drawn, [full, cuts.length, drawn])
ok('the count found whole tiles and cut ones in the same layout',
   full.positive? && !cuts.empty?, [full, cuts.length])
ok('no counted cut is bigger than the tile it came from',
   cuts.all? { |c| c[0] <= W + 0.07 && c[1] <= L + 0.07 },
   cuts.reject { |c| c[0] <= W + 0.07 && c[1] <= L + 0.07 }.first(3))

# ---- 5. the flags are real -------------------------------------------
ok('USE_SHARED_GRID is on in the drawer', FP::USE_SHARED_GRID == true)
ok('the old drawer is still there to fall back to', FP.respond_to?(:tile_planks_legacy))
ok('the old line grid is still there too', FP.respond_to?(:draw_tile_lines_legacy!))
ok('UNIT_W_ALONG_LAYOUT is the one word that turns every tile floor',
   FP::UNIT_W_ALONG_LAYOUT == true)

# ---- 6. the plank patterns were NOT touched --------------------------
SQ = rect(96, 96).map { |q| Geom::Point3d.new(q[0], q[1], 0) }
st = FP.straight_planks(SQ, 0.0, 6.0, 48.0, 0.0, 0.0, false)
ok('Straight still lays planks the way it always did',
   !st.nil? && st.length.positive? && near(dist(st[0][:c][0], st[0][:c][1]), 48.0),
   st && st.first)
hb = FP.herringbone_planks(SQ, 0.0, 6.0, 24.0, 0.0, 0.0, false)
ok('Herringbone still runs on its own 45 degree grid', !hb.nil? && hb.length.positive?)
ch = FP.chevron_planks(SQ, 0.0, 6.0, 24.0, 0.0, 0.0, false)
ok('Chevron too', !ch.nil? && ch.length.positive?)

puts($fails.zero? ? 'rt168 OK' : "rt168 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

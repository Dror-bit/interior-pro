# encoding: utf-8
# rt166 - ONE TILE LAYOUT, READ BY EVERYONE (2026-09-06).
#
# The drawer and the counter each had their own idea of where a tile
# sits. This pins the single calculation they will both read: the joint
# is ADDED to the tile ("רק אריח" - his answer, 2026-09-06), the angle
# and the centring are part of the layout, and the square feet a tile
# covers include the joint while the unit itself does not.
#
# Nothing is wired to it yet - floor_pattern.rb and tile_count.rb are
# untouched by this step.
require './tile_grid'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 1.0e-6)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

TG = InteriorPro::TileGrid
def rect(w, h, x = 0.0, y = 0.0)
  [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
end

# ---- 1. the frame ----------------------------------------------------
fr0 = TG.degrees(0)
ok('at angle 0, u is plain x', near(TG.to_uv(3, 7, fr0)[0], 3.0))
ok('...and v is plain y', near(TG.to_uv(3, 7, fr0)[1], 7.0))
fr30 = TG.degrees(30)
u, v = TG.to_uv(11.0, -4.0, fr30)
x, y = TG.to_xy(u, v, fr30)
ok('a turned frame comes back to the same point', near(x, 11.0) && near(y, -4.0), [x, y])
fr90 = TG.degrees(90)
ok('at angle 90, u runs up the green axis', near(TG.to_uv(0, 5, fr90)[0], 5.0))

# ---- 2. where the room reaches --------------------------------------
ext = TG.extent(rect(48, 96), fr0)
ok('the room reaches 0..48 along u', near(ext[:u_min], 0.0) && near(ext[:u_max], 48.0), ext)
ok('...and 0..96 along v', near(ext[:v_min], 0.0) && near(ext[:v_max], 96.0), ext)
ok('the centre of a plain rectangle is its middle',
   near(ext[:cu], 24.0) && near(ext[:cv], 48.0), ext)

# ---- 3. a room that fits whole tiles ---------------------------------
c = TG.cells(rect(48, 96), u_size: 24, v_size: 48)
ok('48x96 holds exactly four 24x48 tiles', c.length == 4, c.length)
ok('the first tile sits in the corner',
   near(c[0][:quad][0][0], 0.0) && near(c[0][:quad][0][1], 0.0), c[0][:quad])
ok('a tile quad is the tile itself, 24 by 48',
   near(c[0][:quad][1][0] - c[0][:quad][0][0], 24.0) &&
   near(c[0][:quad][3][1] - c[0][:quad][0][1], 48.0), c[0][:quad])
ok('no tile is laid past the far edge of the room',
   c.all? { |t| t[:u0] < 48.0 && t[:v0] < 96.0 }, c.map { |t| [t[:u0], t[:v0]] })

# ---- 4. THE JOINT IS ADDED, NOT TAKEN OFF ----------------------------
# His rule, 2026-09-06: the size he types is the tile he buys.
g = TG.cells(rect(48, 96), u_size: 24, v_size: 48, grout: 0.5)
ok('the tile stays 24 wide when a joint is added',
   near(g[0][:quad][1][0] - g[0][:quad][0][0], 24.0), g[0][:quad])
row = g.select { |t| near(t[:v0], g[0][:v0]) }.sort_by { |t| t[:u0] }
ok('the gap between two tiles IS the joint',
   near(row[1][:u0] - (row[0][:u0] + 24.0), 0.5), [row[0][:u0], row[1][:u0]])
# cells() lays the grid; it never says whole-or-cut - that is the
# counter's job. What the joint does here is push the last column out
# past the wall, so it BECOMES a cut.
ok('with no joint the second column ends exactly on the far wall',
   near(c.map { |t| t[:u0] }.max + 24.0, 48.0), c.map { |t| t[:u0] }.uniq)
ok('with a joint it is pushed past the wall - so it is now a cut',
   row[1][:u0] + 24.0 > 48.0, row[1][:u0] + 24.0)
ok('a joint moves the layout - this is what the old drawer never did',
   !near(g[1][:u0], c[1][:u0]) || g.length != c.length, [g.length, c.length])

# ---- 5. square feet include the joint, the unit does not -------------
# "סקווארפוט זה כולל האריח והגראוט - היחידה היא בלי הגראוט"
ok('a 24x48 tile with a 1/8" joint covers 24.125 x 48.125',
   TG.coverage(24, 48, 0.125) == [24.125, 48.125], TG.coverage(24, 48, 0.125))
ok('...which is that many square feet',
   near(TG.coverage_sqft(24, 48, 0.125), 24.125 * 48.125 / 144.0))
ok('with no joint the coverage is the tile itself',
   TG.coverage(24, 48) == [24.0, 48.0])

# ---- 6. the start point ----------------------------------------------
off = TG.cells(rect(48, 96), u_size: 24, v_size: 48, ox: 6.0)
ok('pushing the layout 6" moves the joints 6"',
   off.map { |t| t[:u0] }.uniq.sort.include?(-18.0), off.map { |t| t[:u0] }.uniq.sort)
ok('...and the grid still covers the room from its very edge',
   off.map { |t| t[:u0] }.min <= 0.0, off.map { |t| t[:u0] }.min)
cen = TG.cells(rect(50, 96), u_size: 24, v_size: 48, centered: true)
mid = cen.map { |t| t[:u0] }.uniq.select { |uu| uu <= 25.0 && uu + 24.0 >= 25.0 }
ok('centred: a WHOLE tile sits on the middle of the room',
   mid.length == 1 && near(mid[0], 13.0), [mid, cen.map { |t| t[:u0] }.uniq.sort])

# ---- 7. the angle is part of the layout ------------------------------
# Turning the room 90 degrees is the same as turning the layout 90.
flat = TG.cells(rect(48, 96), u_size: 24, v_size: 48)
turn = TG.cells(rect(96, 48), u_size: 24, v_size: 48, angle: 90)
ok('a layout at 90 degrees lays the same number of tiles',
   turn.length == flat.length, [flat.length, turn.length])
ok('...and its tiles really are turned',
   near(turn[0][:quad][1][0] - turn[0][:quad][0][0], 0.0, 1.0e-6) == false ||
   near(turn[0][:quad][1][1] - turn[0][:quad][0][1], 24.0), turn[0][:quad])
ok('the angle changes the answer - the counter ignored it until today',
   TG.cells(rect(48, 96), u_size: 24, v_size: 48, angle: 45).length != flat.length)

# ---- 8. stagger (a running bond, when one is asked for) --------------
st = TG.cells(rect(96, 96), u_size: 24, v_size: 24, stagger: 0.5)
r0 = st.select { |t| near(t[:v0], st.map { |q| q[:v0] }.min) }.map { |t| t[:u0] }.sort
r1 = st.select { |t| near(t[:v0], st.map { |q| q[:v0] }.min + 24.0) }.map { |t| t[:u0] }.sort
ok('every second row is pushed along half a tile',
   near((r1[0] - r0[0]) % 24.0, 12.0), [r0.first(3), r1.first(3)])
ok('no stagger means the rows line up',
   near(TG.cells(rect(96, 96), u_size: 24, v_size: 24)[0][:u0], 0.0))

# ---- 9. an L-shaped room --------------------------------------------
L = [[0, 0], [96, 0], [96, 48], [48, 48], [48, 96], [0, 96]]
lc = TG.cells(L, u_size: 24, v_size: 48)
ok('the L gets a grid over the whole of its reach', lc.length == 8, lc.length)
ok('the outline is never cut by this file - that is the counter\'s job',
   lc.all? { |t| t[:quad].length == 4 })

# ---- 10. safety ------------------------------------------------------
ok('a tile too small for the room gives nil, not a hung SketchUp',
   TG.cells(rect(1000, 1000), u_size: 1, v_size: 1).nil?)
ok('a room with no outline gives nothing', TG.cells([[0, 0]], u_size: 24, v_size: 48) == [])
ok('a tile with no size gives nothing', TG.cells(rect(48, 96), u_size: 0, v_size: 48) == [])
ok('a negative joint is treated as none',
   TG.cells(rect(48, 96), u_size: 24, v_size: 48, grout: -3).length == 4)

puts($fails.zero? ? 'rt166 OK' : "rt166 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

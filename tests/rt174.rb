# encoding: utf-8
# rt174 - STAGGER (running bond) reaches the floor (2026-09-17).
#
# tile_grid.rb has had a `stagger` argument since the day it was written,
# and nobody ever passed it: "Nothing in the dialog" says so in its own
# comment. He asked for staggered tiles, so this pins the whole path -
# the calculation, and the two files that carry the number to it.
require './tile_grid'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TG = InteriorPro::TileGrid
ROOM = [[0.0, 0.0], [96.0, 0.0], [96.0, 96.0], [0.0, 96.0]].map { |x, y| [x, y] }

def row_starts(cells, v)
  cells.select { |c| (c[:v0] - v).abs < 0.001 }.map { |c| c[:u0].round(4) }.sort
end

# ---- 1. the calculation ------------------------------------------------
plain = TG.cells(ROOM, u_size: 24.0, v_size: 24.0, grout: 0.0)
bond  = TG.cells(ROOM, u_size: 24.0, v_size: 24.0, grout: 0.0, stagger: 0.5)
ok('a plain grid comes back', plain && !plain.empty?)
ok('a staggered grid comes back', bond && !bond.empty?)

r0 = row_starts(plain, 0.0)
r1 = row_starts(plain, 24.0)
ok('with no stagger both rows start alike', r0 == r1, [r0, r1])

b0 = row_starts(bond, 0.0)
b1 = row_starts(bond, 24.0)
ok('row 0 is untouched by the stagger', b0 == r0, [b0, r0])
ok('row 1 is pushed half a tile', b1.include?(-12.0) && b1.include?(12.0), b1)
ok('row 2 lines up with row 0 again', row_starts(bond, 48.0) == b0,
   [row_starts(bond, 48.0), b0])

third = TG.cells(ROOM, u_size: 24.0, v_size: 24.0, grout: 0.0, stagger: 1.0 / 3.0)
ok('a third of a tile is a third, not a half',
   row_starts(third, 24.0).include?(8.0), row_starts(third, 24.0))

# the joint counts as part of the pitch, or a staggered row drifts off the grid
g = TG.cells(ROOM, u_size: 24.0, v_size: 24.0, grout: 0.5, stagger: 0.5)
ok('the joint is inside the shift', row_starts(g, 24.5).include?(12.25),
   row_starts(g, 24.5))

# a whole tile of stagger is no stagger at all
full = TG.cells(ROOM, u_size: 24.0, v_size: 24.0, grout: 0.0, stagger: 1.0)
ok('a whole tile of shift is the plain grid', row_starts(full, 24.0) == r1,
   [row_starts(full, 24.0), r1])

# ---- 2. the number actually travels ------------------------------------
# A test on the calculation alone does not prove the tool works - that
# rule is in CLAUDE.md, and stagger is exactly how it was broken before:
# the argument existed and nothing filled it in.
FP = File.read('./floor_pattern.rb')
ok('the floor reads the attribute',
   FP.include?("get_attribute('InteriorPro', 'pattern_stagger')"))
ok('and hands it to the grid', FP =~ /cells\(.*stagger: stagger/m)
ok('the faces get it', FP =~ /tile_planks\(poly, ang, w, l, ox, oy, centered, grout, img_w, img_l, stagger\)/)
ok('the LINES layer gets it too - the drawing must match the render',
   FP =~ /draw_tile_lines!\(ge, poly, ang, w, l, ox, oy, centered, zb, grout, stagger\)/)

FD = File.read('./floor_dialog.rb')
ok('the dialog stores it',
   FD.include?("set_attribute('InteriorPro', 'pattern_stagger', cfg['stagger'].to_f)"))
ok('the dialog reads it back out for the window',
   FD.include?("get_attribute('InteriorPro', 'pattern_stagger')"))
ok('there is a picker', FD.include?('staggerOptions') && FD.include?("id=\"st_' + i + '\""))
ok('and the picker is sent on Apply', FD.include?("stagger: parseFloat(document.getElementById('st_' + i).value)"))

FM = File.read('./floor_manager.rb')
ok('it survives a rebuild', FM.include?('pattern_stagger'))

puts($fails.zero? ? 'rt174 all green' : "rt174 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

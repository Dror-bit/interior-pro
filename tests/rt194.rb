# encoding: utf-8
# rt194 - TILE INSIDE THE NICHE, MITRED 45 AT THE OPENING (2026-09-22).
#
# His words: "בתוך הניצ צריך להיות אריחים", and the joint: "החיתוך בין
# הניש לטיל של הקירות החיבור יהיה 45 מעלות". What has to be true:
#   1. the wall tile's hole is the niche brought in by the tile depth,
#   2. its back loop moves OUT onto the niche edge - and only that loop,
#   3. the lining's front edge moves FORWARD, and the two moved edges lie
#      on ONE 45 degree plane (that plane is the mitre),
#   4. the linings cover the niche and line up with the wall's joints,
#   5. build! really goes down this road - not just the maths.
require './tile_wall'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def near(a, b, t = 1e-6) = (a - b).abs < t

TW = InteriorPro::TileWall
DP = 0.625
NR = [24.0, 48.0, 36.0, 72.0]      # 12 x 24 niche, 48" up
ND = 4.0

# ---- 1. the hole in the wall tile ----------------------------------------
ins = TW.niche_inset(NR, DP)
ok('the tile hole is the niche brought in by the tile depth',
   ins == [24.625, 48.625, 35.375, 71.375], ins)

# ---- 2. which back vertices move, and where ------------------------------
ok('a vertex on the left edge moves left by dp', TW.bevel_shift(24.625, 60.0, ins, DP) == [-DP, 0.0])
ok('on the right edge, right', TW.bevel_shift(35.375, 60.0, ins, DP) == [DP, 0.0])
ok('on the bottom, down', TW.bevel_shift(30.0, 48.625, ins, DP) == [0.0, -DP])
ok('on the top, up', TW.bevel_shift(30.0, 71.375, ins, DP) == [0.0, DP])
ok('the corner goes both ways - onto the niche corner itself',
   TW.bevel_shift(24.625, 48.625, ins, DP) == [-DP, -DP])
ok('a vertex off the niche does not move', TW.bevel_shift(10.0, 60.0, ins, DP).nil?)
ok('nor one on the line of the edge but past the niche', TW.bevel_shift(24.625, 90.0, ins, DP).nil?)

# ---- 3. the two halves meet on ONE 45 plane ------------------------------
fr = TW.frame(0.0, 0.0, 96.0, 0.0, 6.0, 'center', 'a', 100.0)   # second storey
lf = TW.lining_frames(fr, NR, ND)
# the lining's tile face front vertex, after it came forward by dp:
x, y, z = TW.lining_world(lf[:left], -DP, 60.0, DP)
wx, wy, wz = TW.world(fr, NR[0] + DP, 60.0, DP)   # the wall tile's arris
ok('the left lining comes forward onto the wall tile arris exactly',
   near(x, wx) && near(y, wy) && near(z, wz), [[x, y, z], [wx, wy, wz]])
# the wall tile's moved back vertex is the niche edge on the wall face:
bx, by, = TW.world(fr, ins[0] - DP, 60.0, 0.0)
lx, ly, = TW.lining_world(lf[:left], 0.0, 60.0, 0.0)
ok('and the wall tile back edge lands where the lining starts', near(bx, lx) && near(by, ly))
# both bevel lines run through (u0, out 0) and (u0+dp, out dp): 45 degrees.
ok('the mitre is 45 degrees (rise = run = tile depth)', near((wx - bx).abs, DP) && near(wy - by, DP))
# every lining normal points INTO the niche
mid = TW.world(fr, 30.0, 60.0, -2.0)
%i[left right bottom top back].each do |k|
  f = lf[k]
  o = TW.lining_world(f, 0.0, 0.0, 0.0)
  d = [mid[0] - o[0], mid[1] - o[1], mid[2] - o[2]]
  ok("the #{k} lining faces into the niche", d[0] * f[:n][0] + d[1] * f[:n][1] + d[2] * f[:n][2] > 0)
end
_a, bb, out = TW.lining_local(lf[:bottom], *TW.lining_world(lf[:bottom], 1.0, 30.0, 0.3))
ok('lining_local undoes lining_world', near(bb, 30.0) && near(out, 0.3))

# ---- 4. the linings -------------------------------------------------------
# 12 x 12 tile, 1/8 grout, laid from 0 - joints at 0, 12.125, 24.25 ...
cells = InteriorPro::TileGrid.cells(TW.rect(0.0, 0.0, 96.0, 96.0), u_size: 12.0, v_size: 12.0, grout: 0.125)
L = TW.niche_lining(cells, 12.0, 12.0, 0.125, NR, DP, ND)
ok('five linings', L && L.keys.sort == %i[back bottom left right top], L && L.keys)
area = L[:back][:pieces].sum { |p| InteriorPro::TileCount.area(p[:poly]) }
ok('the back is the whole niche less the joints that cross it',
   area < 12.0 * 24.0 && area > 12.0 * 24.0 * 0.95, area)
ok('the back is anchored on the WALL grid, so its joints are the wall joints',
   L[:back][:pieces].all? { |p| near(((p[:a0] / 12.125).round * 12.125), p[:a0], 1e-6) })
len = ND - DP
side = L[:left][:pieces]
ok('the sides run from the opening to the back lining',
   side.map { |p| p[:poly].map(&:first) }.flatten.minmax.then { |lo, hi| near(lo, 0.0) && near(hi, len) })
ok('and stop dp short of top and bottom (the mitre closes that corner)',
   side.map { |p| p[:poly].map(&:last) }.flatten.minmax.then { |lo, hi| near(lo, NR[1] + DP) && near(hi, NR[3] - DP) })
ok('the side rows break on the wall rows (a joint at 60.625)',
   side.any? { |p| p[:poly].any? { |_a, b| near(b, 60.625) } })
bot = L[:bottom][:pieces]
ok('the bottom spans between the two sides',
   bot.map { |p| p[:poly].map(&:last) }.flatten.minmax.then { |lo, hi| near(lo, NR[0] + DP) && near(hi, NR[2] - DP) })
ok('too shallow a niche is not lined', TW.niche_lining(cells, 12.0, 12.0, 0.125, NR, DP, 0.5).nil?)

# ---- 5. build! really takes this road -------------------------------------
SRC = File.read('./tile_wall.rb')
BUILD = SRC[/def self\.build!.*?\n    end\n/m].to_s
ok('there is a kill switch', SRC.include?('USE_NICHE_TILES = true'))
ok('build! puts the inset hole in place of the niche', BUILD.include?('holes[idx] = niche_inset(nr, dp)'))
ok('build! bevels the wall tiles', BUILD.include?('bevel_niche_tiles!(ge, fr'))
ok('build! lines the niche', BUILD.include?('emit_niche_lining!(ge, fr, x, cells'))
ok('the bevel runs AFTER the wall tiles are built',
   BUILD.index('emit_tile_solids!(ge, fr, ps').to_i < BUILD.index('bevel_niche_tiles!').to_i)
ok('every lining tile is its own group',
   SRC[/def self\.lining_solid!.*?\n    end\n/m].to_s.include?('sub = ge.add_group'))

puts($fails.zero? ? 'rt194 OK' : "rt194 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

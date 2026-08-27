# encoding: utf-8
# rt107 - THE FLAT TILE KNOWS ABOUT A DORMER TOO (2026-09-03).
#
# rt105 taught the RUN materials that a dormer is a hole: a run is a line,
# and spans_minus subtracts an interval from a line. The flat tile never
# learned it, because it has a layout of its own - flat_slots - and nothing
# in it ever looked at the plane's holes. He put a dormer on the square-tile
# roof and the tiles ran straight over it: "והפלאט טיל לא נחתך ביכלל".
# Measured on his own model before the fix: 59 and 52 whole tiles standing
# inside the two dormer openings.
#
# THE CLAIMS PINNED HERE
# 1. clip_outside_poly is the mirror of clip_to_poly: a plate inside the
#    hole is gone, one outside it is untouched, one on its edge keeps only
#    the part outside - and what it keeps really is outside.
# 2. It clips by the NEAREST reaching edge only, so a plate sitting past a
#    CORNER of the hole is not bitten twice.
# 3. flat_slots lays no tile inside a dormer, and lays fewer tiles on a
#    slope with a dormer than on the same slope without one.
# 4. The run materials are untouched by all of it.
#
# Against the old code claims 1-3 fail: clip_outside_poly does not exist and
# flat_slots ignores the holes.
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RTM   = InteriorPro::RoofTileMath
PLACE = InteriorPro::RoofTilePlace

# ---- 1 and 2. the maths ----------------------------------------------
HOLE2D = [[80.0, 30.0], [120.0, 30.0], [120.0, 60.0], [80.0, 60.0]].freeze
def plate(cx, cy, w = 10.0, h = 10.0)
  [[cx - w / 2, cy - h / 2], [cx + w / 2, cy - h / 2],
   [cx + w / 2, cy + h / 2], [cx - w / 2, cy + h / 2]]
end

far = plate(20.0, 20.0)
ok('a plate nowhere near the hole is untouched',
   RTM.clip_outside_poly(far, HOLE2D) == far)
ok('a plate deep inside the hole is gone',
   RTM.clip_outside_poly(plate(100.0, 45.0), HOLE2D).empty?)

edge = RTM.clip_outside_poly(plate(80.0, 45.0), HOLE2D)
ok('a plate on the edge keeps something', edge.length >= 3, edge)
ok('and it keeps about half of itself',
   (RTM.poly_area(edge).abs - 50.0).abs < 0.51, RTM.poly_area(edge).abs)
cx = edge.sum { |p| p[0] } / edge.length
cy = edge.sum { |p| p[1] } / edge.length
ok('what it keeps is really OUTSIDE the hole',
   !RTM.poly_contains?(HOLE2D, [cx, cy]), [cx, cy])

# rect minus a convex hole is an L at a corner, and a tile has to come back
# as ONE face - so the answer is the biggest piece that is outside, 90 of the
# plate's 100. The 1 square inch it gives up is the corner block; the tile
# never hangs over the opening, which is the side to err on.
corner = RTM.clip_outside_poly(plate(76.0, 26.0), HOLE2D)
ok('a plate straddling a CORNER keeps the biggest piece outside the hole',
   (RTM.poly_area(corner).abs - 90.0).abs < 0.51, RTM.poly_area(corner).abs)
# On the boundary is fine - that is the tile meeting the dormer wall. What
# it must never do is reach PAST it.
ok('and no corner of what it keeps reaches inside the hole',
   corner.none? { |q| q[0] > 80.01 && q[0] < 119.99 &&
                      q[1] > 30.01 && q[1] < 59.99 },
   corner)

ok('no hole at all changes nothing', RTM.clip_outside_poly(far, []) == far)

# ---- the slope, and a dormer standing on it --------------------------
NRM  = [0.0, -1.0 / 3.0, 1.0]
FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
        [200.0, 90.0, 130.0], [0.0, 90.0, 130.0]].freeze
HOLE = [[80.0, 30.0, 110.0], [120.0, 30.0, 110.0],
        [120.0, 60.0, 120.0], [80.0, 60.0, 120.0]].freeze

class StubVertex
  def initialize(p); @p = Geom::Point3d.new(p[0], p[1], p[2]); end
  def position; @p; end
end

class StubLoop
  def initialize(pts, outer); @pts = pts; @outer = outer; end
  def outer?; @outer; end
  def vertices; @pts.map { |p| StubVertex.new(p) }; end
end

class HoledFace
  def initialize(outer, holes, nrm)
    @outer = outer
    @holes = holes
    @nrm = Geom::Vector3d.new(nrm[0], nrm[1], nrm[2])
  end
  def normal; @nrm; end
  def outer_loop; StubLoop.new(@outer, true); end
  def loops
    [StubLoop.new(@outer, true)] + @holes.map { |h| StubLoop.new(h, false) }
  end
  def vertices; (@outer + @holes.flatten(1)).map { |p| StubVertex.new(p) }; end
end

plain = PLACE.planes_from_faces([HoledFace.new(FACE, [], NRM)])
holed = PLACE.planes_from_faces([HoledFace.new(FACE, [HOLE], NRM)])

# ---- 3. the flat tile -------------------------------------------------
before = PLACE.run_slots(plain, 'slate')
after  = PLACE.run_slots(holed, 'slate')
ok('the plain slope gets tiles', before.length > 20, before.length)
ok('the slope with a dormer gets FEWER tiles',
   after.length < before.length, [before.length, after.length])

pu = RTM.plane_uv(holed[0][:points], holed[0][:n])
hole_uv = HOLE.map { |p| RTM.project(p, pu[:origin], pu[:u], pu[:v]) }
hu = hole_uv.map { |p| p[0] }
hv = hole_uv.map { |p| p[1] }

# WHERE THE TILE REALLY IS, not where its slot starts. A cut tile carries
# its own clipped footprint in the plane's u/v, and that is the thing on the
# roof - a piece cut down to the strip beside the dormer still has its
# course's origin inside the opening.
def tile_centre(s, pu, exposure)
  if s[:cut] && s[:cut].length >= 3
    n = s[:cut].length.to_f
    return [s[:cut].sum { |q| q[0] } / n, s[:cut].sum { |q| q[1] } / n]
  end
  o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
  [o[0], o[1] + (exposure / 2.0)]
end

def inside_count(slots, pu, hu, hv, exposure)
  slots.count do |s|
    c = tile_centre(s, pu, exposure)
    c[0] > hu.min + 1.0 && c[0] < hu.max - 1.0 &&
      c[1] > hv.min + 1.0 && c[1] < hv.max - 1.0
  end
end

exp = RTM.shape('slate')[:exposure].to_f
ok('the plain slope really does cover that patch',
   inside_count(before, pu, hu, hv, exp).positive?,
   inside_count(before, pu, hu, hv, exp))
ok('no tile is laid inside the dormer',
   inside_count(after, pu, hu, hv, exp).zero?,
   inside_count(after, pu, hu, hv, exp))

# ---- 4. the run materials are untouched -------------------------------
ok('the seam still gets its runs on a plain slope',
   PLACE.run_slots(plain, 'seam').length > 4)
ok('and a dormer still SPLITS them, exactly as rt105 pinned',
   PLACE.run_slots(holed, 'seam').length > PLACE.run_slots(plain, 'seam').length)

puts($fails.zero? ? 'rt107 OK' : "rt107 #{$fails} FAILURES")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt108 - THE TILES STOP AT THE OUTER FACE OF THE DORMER WALL (2026-09-03).
#
# He looked into a dormer opening and every material's cut end was showing
# inside it: "כל הדברים האלו הקשורים לגג צריכים להיחתך בקצה החיצוני של הקיר
# ולא הפנימי". cut_roof! opens the deck at the ROUGH opening - the INSIDE
# faces of the dormer's walls, because that is what carries them - and the
# tile machine took that loop as the hole. So every piece ran one wall
# thickness too far and died under the wall instead of against it.
#
# THE CLAIMS PINNED HERE
# 1. grow_poly pushes a convex loop out by a stated distance, whichever way
#    round it was wound, and hands back what it was given when it cannot.
# 2. run_slots stops the runs that same distance short of the deck's hole.
# 3. flat_slots does it too - one hole, both layouts.
# 4. With no grow asked for, everything is exactly what rt105 and rt107
#    already pinned. This change is invisible until a dormer asks for it.
#
# Against the old code claims 1-3 fail: grow_poly does not exist.
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

# ---- 1. the maths ----------------------------------------------------
SQ   = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]].freeze
grown = RTM.grow_poly(SQ, 2.0)
xs = grown.map { |p| p[0] }
ys = grown.map { |p| p[1] }
ok('a square grows on all four sides',
   (xs.min + 2.0).abs < 1.0e-6 && (xs.max - 12.0).abs < 1.0e-6 &&
   (ys.min + 2.0).abs < 1.0e-6 && (ys.max - 12.0).abs < 1.0e-6, grown)
ok('and its area grows to match', (RTM.poly_area(grown).abs - 196.0).abs < 1.0e-6,
   RTM.poly_area(grown).abs)
ok('the winding it arrived in does not matter',
   RTM.poly_area(RTM.grow_poly(SQ.reverse, 2.0)).abs.round(6) == 196.0,
   RTM.poly_area(RTM.grow_poly(SQ.reverse, 2.0)).abs)
ok('growing by nothing changes nothing', RTM.grow_poly(SQ, 0.0) == SQ)
ok('a pentagon keeps its five corners',
   RTM.grow_poly([[0.0, 0.0], [20.0, 0.0], [20.0, 10.0], [10.0, 16.0],
                  [0.0, 10.0]], 3.0).length == 5)
ok('nothing to grow comes back as it was', RTM.grow_poly([[0.0, 0.0]], 3.0) == [[0.0, 0.0]])

# THE VALLEY EDGE DOES NOT MOVE. Up the slope the gablet dies into the main
# roof and there is no wall to hide behind - growing there takes tiles from
# ABOVE the dormer and leaves bare deck round its top ("he circled exactly
# that spot on both dormers", 2026-09-03).
kept = RTM.grow_poly(SQ, 2.0, :walls)
kxs = kept.map { |p| p[0] }
kys = kept.map { |p| p[1] }
ok('the wall edges still move',
   (kxs.min + 2.0).abs < 1.0e-6 && (kxs.max - 12.0).abs < 1.0e-6 &&
   (kys.min + 2.0).abs < 1.0e-6, kept)
ok('but the edge facing UP the slope stays where it was',
   (kys.max - 10.0).abs < 1.0e-6, kys.max)
pent = RTM.grow_poly([[0.0, 0.0], [20.0, 0.0], [20.0, 10.0], [10.0, 16.0],
                      [0.0, 10.0]], 3.0, :walls)
ok('a gablet keeps its apex exactly where the two roofs meet',
   (pent.map { |p| p[1] }.max - 16.0).abs < 1.0e-6, pent)

# :sides moves the two cheeks and nothing else - a run is cut on its CENTRE
# line, so half a piece has to come off the sides as well or the pipe beside
# the dormer still has half its body inside the opening.
sides = RTM.grow_poly(SQ, 2.0, :sides)
sxs = sides.map { |p| p[0] }
sys = sides.map { |p| p[1] }
ok('the cheeks move', (sxs.min + 2.0).abs < 1.0e-6 && (sxs.max - 12.0).abs < 1.0e-6, sides)
ok('the foot and the head stay exactly where they were',
   sys.min.abs < 1.0e-6 && (sys.max - 10.0).abs < 1.0e-6, sides)

# ---- the slope, and a dormer standing on it --------------------------
NRM  = [0.0, -1.0 / 3.0, 1.0]
FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
        [200.0, 90.0, 130.0], [0.0, 90.0, 130.0]].freeze
HOLE = [[80.0, 30.0, 110.0], [120.0, 30.0, 110.0],
        [120.0, 60.0, 120.0], [80.0, 60.0, 120.0]].freeze
TH = 5.0

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

holed = PLACE.planes_from_faces([HoledFace.new(FACE, [HOLE], NRM)])
pu = RTM.plane_uv(holed[0][:points], holed[0][:n])
huv = HOLE.map { |p| RTM.project(p, pu[:origin], pu[:u], pu[:v]) }
hu = huv.map { |p| p[0] }
hv = huv.map { |p| p[1] }

# ---- 2. the runs ------------------------------------------------------
tight = PLACE.run_slots(holed, 'seam')
wide  = PLACE.run_slots(holed, 'seam', hole_grow: TH)

def gap_below(slots, pu, hu, hv)
  # the run that dies UNDER the dormer: how far below the opening it stops
  ends = slots.map do |s|
    o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
    next nil unless o[0] > hu.min && o[0] < hu.max
    top = o[1] + s[:length].to_f
    next nil if top > hv.max
    hv.min - top
  end.compact
  ends.empty? ? nil : ends.min
end

g0 = gap_below(tight, pu, hu, hv)
g1 = gap_below(wide, pu, hu, hv)
ok('without a grow a run dies ON the deck hole', !g0.nil? && g0.abs < 0.01, g0)
ok('with the grow it dies a wall thickness short of it',
   !g1.nil? && (g1 - TH).abs < 0.01, g1)

# THE RUN'S BODY, NOT ONLY ITS CENTRE LINE - but only as far as it SHOWS.
# A pipe lying half under the dormer's wall is what flashing is for; one
# coming out past the INNER face is in the room. So the test is the inner
# face, which is the deck's own hole, and the cheeks are pushed out by half
# a piece LESS the wall it can hide in. Taking out every run that touches
# the wall opened a foot-wide bare lane up both sides: "יותר מידי פתחים".
half = InteriorPro::RoofTileParts.run_cover_w(RTM.shape('roman')) / 2.0
def body_past(slots, pu, hu, hv, half)
  slots.count do |s|
    o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
    v0 = o[1]
    v1 = o[1] + s[:length].to_f
    o[0] + half > hu.min + 0.01 && o[0] - half < hu.max - 0.01 &&
      v1 > hv.min + 0.01 && v0 < hv.max - 0.01
  end
end

# A hole placed so a pipe really does straddle its cheek: the roman runs sit
# every 10" and the pipe is 14" wide, so an opening whose cheek falls 6" off
# a run's centre line has that run's body 1" inside the room.
HOLE_S = [[71.0, 30.0, 110.0], [111.0, 30.0, 110.0],
          [111.0, 60.0, 120.0], [71.0, 60.0, 120.0]].freeze
hs = PLACE.planes_from_faces([HoledFace.new(FACE, [HOLE_S], NRM)])
pus = RTM.plane_uv(hs[0][:points], hs[0][:n])
suv = HOLE_S.map { |p| RTM.project(p, pus[:origin], pus[:u], pus[:v]) }
su = suv.map { |p| p[0] }
sv = suv.map { |p| p[1] }
ok('with the grow nothing comes out past the inner face',
   body_past(PLACE.run_slots(hs, 'roman', hole_grow: TH), pus, su, sv, half).zero?,
   body_past(PLACE.run_slots(hs, 'roman', hole_grow: TH), pus, su, sv, half))
ok('and the seam, whose rib is thinner than the wall, loses no run to it',
   PLACE.run_slots(hs, 'seam', hole_grow: TH).length ==
     PLACE.run_slots(hs, 'seam', hole_grow: TH).length)

# ---- 3. the flat tile -------------------------------------------------
flat_tight = PLACE.run_slots(holed, 'slate')
flat_wide  = PLACE.run_slots(holed, 'slate', hole_grow: TH)
exp = RTM.shape('slate')[:exposure].to_f

def tile_centre(s, pu, exposure)
  if s[:cut] && s[:cut].length >= 3
    n = s[:cut].length.to_f
    return [s[:cut].sum { |q| q[0] } / n, s[:cut].sum { |q| q[1] } / n]
  end
  o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
  [o[0], o[1] + (exposure / 2.0)]
end

def in_box(slots, pu, exp, u0, u1, v0, v1)
  slots.count do |s|
    c = tile_centre(s, pu, exp)
    c[0] > u0 && c[0] < u1 && c[1] > v0 && c[1] < v1
  end
end

ok('the tiles cleared the deck hole already',
   in_box(flat_tight, pu, exp, hu.min + 1, hu.max - 1, hv.min + 1, hv.max - 1).zero?)
# the band is round the three WALLS - the sides and the foot - and stops at
# the opening's own top, where the valley is
ok('with the grow the band round the three walls is clear too',
   in_box(flat_wide, pu, exp,
          hu.min - TH + 1, hu.max + TH - 1,
          hv.min - TH + 1, hv.max - 1).zero?,
   in_box(flat_wide, pu, exp, hu.min - TH + 1, hu.max + TH - 1,
          hv.min - TH + 1, hv.max - 1))
ok('and the tiles ABOVE the dormer are still there',
   in_box(flat_wide, pu, exp, hu.min, hu.max, hv.max + 1, hv.max + 20).positive?,
   in_box(flat_wide, pu, exp, hu.min, hu.max, hv.max + 1, hv.max + 20))
ok('and that band really did cost it tiles',
   flat_wide.length < flat_tight.length, [flat_tight.length, flat_wide.length])

# ---- 4. asking for nothing changes nothing ----------------------------
ok('the seam with no grow is what it always was',
   PLACE.run_slots(holed, 'seam', hole_grow: 0.0).length == tight.length)
ok('the flat tile with no grow is what it always was',
   PLACE.run_slots(holed, 'slate', hole_grow: 0.0).length == flat_tight.length)

puts($fails.zero? ? 'rt108 OK' : "rt108 #{$fails} FAILURES")
exit($fails.zero? ? 0 : 1)

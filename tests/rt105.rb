# encoding: utf-8
# rt105 - A RUN STOPS AT A DORMER (2026-09-02B).
#
# He looked up at a dormer from inside the attic and the standing seam
# panels were running straight through it: "תיראה שמבתוכו הוא לא חתך את
# הפאנלים". cut_roof! opens the deck, but nothing told the tile machine
# that the slope now has a hole in it.
#
# THE CLAIMS PINNED HERE
# 1. spans_minus does plain interval subtraction: one cut in the middle
#    of a span makes two, a cut off the end makes none, a cut that
#    swallows a span kills it, and pieces under min_len are dropped.
# 2. planes_from_faces reads the OUTLINE off the outer loop and carries
#    every inner loop as a hole. face.vertices mixes the two together -
#    the landmine this project has hit before - so a slope with a dormer
#    on it used to come out as a polygon that is not the roof at all.
# 3. run_slots splits a run that crosses a hole into one below it and
#    one above, and NO slot's span lies inside the hole. Exactly what a
#    valley already did to a run, now for a dormer.
#
# Against the old code claim 3 fails: the runs cross the hole unbroken.
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

# ---- 1. the interval maths ------------------------------------------
ok('a cut in the middle makes two spans',
   RTM.spans_minus([[0.0, 100.0]], [[40.0, 60.0]]) == [[0.0, 40.0], [60.0, 100.0]],
   RTM.spans_minus([[0.0, 100.0]], [[40.0, 60.0]]))
ok('a cut that misses changes nothing',
   RTM.spans_minus([[0.0, 100.0]], [[120.0, 140.0]]) == [[0.0, 100.0]])
ok('a cut off the bottom shortens it',
   RTM.spans_minus([[0.0, 100.0]], [[-10.0, 30.0]]) == [[30.0, 100.0]],
   RTM.spans_minus([[0.0, 100.0]], [[-10.0, 30.0]]))
ok('a cut that swallows the span leaves nothing',
   RTM.spans_minus([[0.0, 100.0]], [[-5.0, 105.0]]).empty?)
ok('two cuts make three pieces',
   RTM.spans_minus([[0.0, 100.0]], [[20.0, 30.0], [60.0, 70.0]]).length == 3)
ok('a piece under min_len is dropped, the long one survives',
   RTM.spans_minus([[0.0, 100.0]], [[5.0, 60.0]], 20.0) == [[60.0, 100.0]],
   RTM.spans_minus([[0.0, 100.0]], [[5.0, 60.0]], 20.0))
ok('no cuts, nothing changes',
   RTM.spans_minus([[0.0, 10.0]], []) == [[0.0, 10.0]])

# ---- the slope, and a dormer standing on it -------------------------
NRM  = [0.0, -1.0 / 3.0, 1.0]
FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
        [200.0, 90.0, 130.0], [0.0, 90.0, 130.0]].freeze
# a 40 x 30 opening in the middle of it, on the same plane
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
  # what face.vertices does in SketchUp: outline AND holes, mixed
  def vertices; (@outer + @holes.flatten(1)).map { |p| StubVertex.new(p) }; end
end

plain  = PLACE.planes_from_faces([HoledFace.new(FACE, [], NRM)])
holed  = PLACE.planes_from_faces([HoledFace.new(FACE, [HOLE], NRM)])

# ---- 2. the outline, and the holes ----------------------------------
ok('the outline is the outer loop, not every vertex',
   plain[0][:points].length == 4 && holed[0][:points].length == 4,
   [plain[0][:points].length, holed[0][:points].length])
ok('a face with no holes carries none', plain[0][:holes] == [])
ok('the inner loop travels with the plane as a hole',
   holed[0][:holes].length == 1 && holed[0][:holes][0].length == 4,
   holed[0][:holes])

# ---- 3. the runs ----------------------------------------------------
before = PLACE.run_slots(plain, 'seam')
after  = PLACE.run_slots(holed, 'seam')
ok('the plain slope gets runs', before.length > 4, before.length)
ok('a hole SPLITS the runs that cross it, so there are more of them',
   after.length > before.length, [before.length, after.length])

pu = RTM.plane_uv(holed[0][:points], holed[0][:n])
hole_uv = HOLE.map { |p| RTM.project(p, pu[:origin], pu[:u], pu[:v]) }
hu = hole_uv.map { |p| p[0] }
hv = hole_uv.map { |p| p[1] }

inside = after.count do |s|
  o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
  v0 = o[1]
  v1 = o[1] + s[:length].to_f
  # the middle of the run, so a run that merely touches the edge is fine
  vm = (v0 + v1) / 2.0
  o[0] > hu.min + 1.0 && o[0] < hu.max - 1.0 &&
    vm > hv.min + 1.0 && vm < hv.max - 1.0
end
ok('no run has its middle inside the dormer', inside.zero?, inside)

deep = after.count do |s|
  o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
  o[0] > hu.min + 1.0 && o[0] < hu.max - 1.0 &&
    o[1] < hv.min - 1.0 && o[1] + s[:length].to_f > hv.max + 1.0
end
ok('no run runs straight through it from below to above', deep.zero?, deep)

# ---- 4. IT MEETS THE DORMER, it does not stop short ------------------
# The setback exists to hide a cut under a ridge cap or a valley channel.
# A dormer has neither, so the run comes right up to it - the user's law:
# boards MEET. Pulling back there left bare deck all round the dormer,
# "הוא נחתך יותר מדי".
touch_below = 0
touch_above = 0
after.each do |s|
  o = RTM.project(s[:origin], pu[:origin], pu[:u], pu[:v])
  next unless o[0] > hu.min + 1.0 && o[0] < hu.max - 1.0
  hspans = RTM.v_spans_at(hole_uv, o[0], 0.0)
  next if hspans.empty?
  lo, hi = hspans.first
  top = o[1] + s[:length].to_f
  touch_below += 1 if (top - lo).abs < 1.0
  touch_above += 1 if (o[1] - hi).abs < 1.0
end
ok('a run below the dormer ends ON it, not short of it', touch_below > 0,
   touch_below)
ok('a run above the dormer starts ON it', touch_above > 0, touch_above)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

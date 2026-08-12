# encoding: utf-8
# rt32 — the eave of a CURVED wall (2026-08-12).
#
# Until now RoofManager.eave_polygon flattened a bowed wall to its chord, so a
# roof over a round wall came out with a straight edge. The eave of a curved
# wall is now the CONCENTRIC arc: the wall's centreline circle pushed outward
# by half the thickness plus the overhang, cut at both ends against its
# straight neighbours' own eave lines, then chopped into short facets that all
# carry the SAME wall id.
#
# The geometry is the user's real room 1 from rt31 (a 192 x 191 room whose
# right-hand wall bows 60" outward), so the numbers below are the numbers the
# model actually has to hit. Everything here is closed-form - no tolerance
# fiddling, no rendering needed to know whether it is right.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'
require './room_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager
D = 'InteriorPro'.freeze
OVERHANG = 12.0

def mkwall(model, id, sx, sy, ex, ey, sag = nil, th = 5.0)
  g = model.entities.add_group
  g.set_attribute(D, 'type', 'wall');      g.set_attribute(D, 'id', id)
  g.set_attribute(D, 'start_x', sx);       g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);         g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', th);     g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', 'bottom-left')
  g.set_attribute(D, 'wall_category', 'exterior')
  g.set_attribute(D, 'level', 1)
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

# The user's room 1. Right-hand wall bows 60" to the OUTSIDE (+x).
ROOM = [
  ['top',    2907.5, 1034.0, 3099.5, 1034.0, nil],
  ['left',   2907.5, 1034.0, 2907.5,  843.0, nil],
  ['bottom', 2907.5,  843.0, 3099.5,  843.0, nil],
  ['arc',    3099.5,  843.0, 3099.5, 1034.0, -60.0]
].freeze

def build(sag_on_right)
  Sketchup.reset_model!
  m = Sketchup.active_model
  ROOM.each { |w| mkwall(m, w[0], w[1], w[2], w[3], w[4], sag_on_right ? w[5] : nil) }
  m.entities.grep(Sketchup::Group)
end

# ---------------------------------------------------------------- straight
# The same room with a FLAT right-hand wall must come out exactly as it always
# did: four corners, one per wall. This is the regression guard - a straight
# room may not notice that the curve code exists at all.
flat = RF.eave_polygon(build(false), OVERHANG)
ok('straight room still gives one point per wall', flat && flat[:pts].length == 4,
   flat && flat[:pts].length)
if flat
  xs = flat[:pts].map { |p| p[0] }.sort
  ys = flat[:pts].map { |p| p[1] }.sort
  ok('straight room eave spans x 2895.5 .. 3111.5',
     (xs.first - 2895.5).abs < 0.01 && (xs.last - 3111.5).abs < 0.01, [xs.first, xs.last])
  ok('straight room eave spans y 831.0 .. 1051.0',
     (ys.first - 831.0).abs < 0.01 && (ys.last - 1051.0).abs < 0.01, [ys.first, ys.last])
  ok('straight room still names all four walls',
     flat[:wall_ids].compact.sort == %w[arc bottom left top], flat[:wall_ids])
end
flat_area = flat ? RF.polygon_area(flat[:pts]).abs : 0.0

# ---------------------------------------------------------------- curved
ep = RF.eave_polygon(build(true), OVERHANG)
ok('a curved wall still produces an eave polygon', !ep.nil?)

if ep
  pts = ep[:pts]
  ids = ep[:wall_ids]

  # The circle the eave has to sit on, worked out by hand:
  #   drawn chord 191" with sag 60"  -> r = 106.002083, centre x = 3053.497917
  #   centreline (anchor 'left')     -> r - 2.5  = 103.502083
  #   eave (half thickness + 12")    -> + 14.5   = 118.002083
  CX = 3053.4979167
  CY = 938.5
  RR = 118.0020833

  arc_i = (0...pts.length).select { |i| ids[i] == 'arc' }
  ok('the bowed wall is now many facets, not one straight edge',
     arc_i.length >= 4, arc_i.length)
  ok('and not an absurd number of them (ROOF_CURVE_TOL keeps it sane)',
     arc_i.length <= 40, arc_i.length)
  ok('the facets are consecutive - the curve is not scattered round the loop',
     arc_i.each_cons(2).all? { |a, b| b == a + 1 }, arc_i)

  worst = arc_i.map { |i| (Math.hypot(pts[i][0] - CX, pts[i][1] - CY) - RR).abs }.max
  ok('every facet point sits on the concentric eave circle (r = 118.00)',
     worst && worst < 0.001, worst)

  # The two corners. Each point in the ring is the START of its own edge, so
  # the arc's FIRST point is the bottom corner, and the corner at its far end
  # is the first point of the next edge - the top wall.
  bot_c = pts[arc_i.first]
  top_c = pts[ids.index('top')]
  ok('the bottom corner lands on the bottom wall eave line (3102.162, 831.0)',
     (bot_c[0] - 3102.1618).abs < 0.01 && (bot_c[1] - 831.0).abs < 0.01, bot_c)
  ok('the top corner lands on the top wall eave line (3089.110, 1051.0)',
     (top_c[0] - 3089.1099).abs < 0.01 && (top_c[1] - 1051.0).abs < 0.01, top_c)
  ok('both corners really are on the eave circle too',
     [bot_c, top_c].all? { |p| (Math.hypot(p[0] - CX, p[1] - CY) - RR).abs < 0.001 },
     [bot_c, top_c])

  # The three flat walls keep exactly one point each, and their eave lines did
  # not move because a neighbour started bending.
  %w[top left bottom].each do |name|
    ok("the straight wall '#{name}' still owns exactly one point",
       ids.count(name) == 1, ids.count(name))
  end
  li = ids.index('left')
  ok('the left wall eave is still at x = 2895.5', li && (pts[li][0] - 2895.5).abs < 0.01,
     li && pts[li])

  # Shape sanity: still one simple CCW ring, and bulging outward can only ADD
  # area - a sign slip would eat area instead.
  area = RF.polygon_area(pts)
  ok('the eave ring is still counter-clockwise', area > 0, area)
  ok('bowing the wall OUTWARD grows the roof area', area > flat_area + 1000.0,
     [area, flat_area])
  ok('no two neighbouring points sit on top of each other',
     pts.each_cons(2).all? { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) > 0.01 }, nil)
end

# ------------------------------------------ a bulge that outruns its neighbour
# With a 120" bow the eave CIRCLE (r = 110.0, centre y = 938.5, so its top is
# at y = 1048.5) never reaches the top wall's eave line at y = 1051 - the two
# simply miss. The straight run must NOT be tilted down to chase the curve;
# that would slope a whole fascia board. The straight eave stays put and the
# curve is brought to it.
Sketchup.reset_model!
m = Sketchup.active_model
ROOM.each { |w| mkwall(m, w[0], w[1], w[2], w[3], w[4], w[0] == 'arc' ? -120.0 : nil) }
big = RF.eave_polygon(m.entities.grep(Sketchup::Group), OVERHANG)
ok('a bow bigger than the corner still gives an eave polygon', !big.nil?)
if big
  bt = big[:pts][big[:wall_ids].index('top')]
  bl = big[:pts][big[:wall_ids].index('left')]
  ok('the top wall eave stays dead level at y = 1051 on BOTH its ends',
     (bt[1] - 1051.0).abs < 0.001 && (bl[1] - 1051.0).abs < 0.001, [bt, bl])
  ok('and its corner sits straight above the circle centre (x = 3121.503)',
     (bt[0] - 3121.5026).abs < 0.01, bt)
  ok('the gap the curve has to jump is small (under 3")',
     (Math.hypot(bt[0] - 3121.5026, bt[1] - 938.5) - 109.9974).abs < 3.0,
     Math.hypot(bt[0] - 3121.5026, bt[1] - 938.5))
end

# ------------------------------------------------- the bow the other way
# Bowing INWARD shrinks the eave circle instead of growing it. Same maths,
# opposite sign - and it must not fall back to the chord silently.
Sketchup.reset_model!
m = Sketchup.active_model
ROOM.each { |w| mkwall(m, w[0], w[1], w[2], w[3], w[4], w[0] == 'arc' ? 40.0 : nil) }
inn = RF.eave_polygon(m.entities.grep(Sketchup::Group), OVERHANG)
ok('an inward bow still gives an eave polygon', !inn.nil?)
if inn
  n_arc = inn[:wall_ids].count('arc')
  ok('an inward bow is faceted too', n_arc >= 4, n_arc)
  ok('an inward bow SHRINKS the roof area', RF.polygon_area(inn[:pts]).abs < flat_area,
     [RF.polygon_area(inn[:pts]).abs, flat_area])
end

# ------------------------------------------- no ridge caps on the facet fan
# The straight skeleton raises a hip between every pair of facets, so a curved
# wall grows a fan of rays across one smooth surface. Those rays must get NO
# ridge cap; every hip between two DIFFERENT walls keeps its cap.
ep2 = RF.eave_polygon(build(true), OVERHANG)
if ep2
  poly = ep2[:pts]
  ids  = ep2[:wall_ids]
  fan = RF.facet_hip_points(poly, ids)
  n_arc = ids.count('arc')
  ok('every facet seam is spotted (one per facet, minus the last)',
     fan.length == n_arc - 1, [fan.length, n_arc])
  ok('no real corner is mistaken for a facet seam',
     fan.none? { |p| p == poly[ids.index('top')] || p == poly[ids.index('left')] }, fan)

  # A line hanging off a facet seam is dropped; a line between two different
  # walls, and a ridge in open air, are both kept.
  seam = fan.first
  corner = poly[ids.index('left')]                       # top <-> left, a real corner
  lines = [[seam,        0.0, [seam[0] - 30.0, seam[1] - 30.0], 9.0, []],
           [corner,      0.0, [corner[0] + 40.0, corner[1] - 40.0], 9.0, []],
           [[0.0, 0.0],  9.0, [50.0, 0.0], 9.0, []]]
  kept = RF.drop_facet_hips(lines, poly, ids)
  ok('the fan ray loses its cap', kept.none? { |l| l[0] == seam }, kept.length)
  ok('the hip between two different walls keeps its cap',
     kept.any? { |l| l[0] == corner }, kept.length)
  ok('a plain ridge keeps its cap', kept.any? { |l| l[0] == [0.0, 0.0] }, kept.length)
  ok('nothing else was thrown away', kept.length == 2, kept.length)
end

# A straight-only roof must not lose a single cap.
flat2 = RF.eave_polygon(build(false), OVERHANG)
if flat2
  lines = [[flat2[:pts][0], 0.0, [0.0, 0.0], 9.0, []]]
  ok('a straight-only roof keeps every cap it had',
     RF.drop_facet_hips(lines, flat2[:pts], flat2[:wall_ids]).length == 1)
  ok('and has no facet seams at all', RF.facet_hip_points(flat2[:pts], flat2[:wall_ids]).empty?)
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

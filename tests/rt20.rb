# encoding: utf-8
# rt20 — curved wall FOOTPRINT (wall_tool.rb, 2026-08-10).
# The floor outline a curved wall is extruded from. Pure numbers, no model.
# The whole point of this suite: a curved wall must land its two faces in the
# SAME places a straight wall would, relative to the drawn line - otherwise
# curving a wall would quietly move it.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

# Signed distance of p from the line a->b. Positive = LEFT of a->b.
def left_of(ax, ay, bx, by, p)
  ((bx - ax) * (p[1] - ay) - (by - ay) * (p[0] - ax)) / Math.sqrt((bx - ax)**2 + (by - ay)**2)
end

# ------------------------------------------------------- the straight cases

ok('no bow at all -> nil (build it straight)',
   WT.curved_footprint_xy(0, 0, 120, 0, 5, 'center', 0.0).nil?)
ok('a hair of bow -> nil (noise is not a curve)',
   WT.curved_footprint_xy(0, 0, 120, 0, 5, 'center', 0.01).nil?)
ok('nil bow -> nil', WT.curved_footprint_xy(0, 0, 120, 0, 5, 'center', nil).nil?)
ok('MIN_ARC_SAG is a sane hair', WT::MIN_ARC_SAG > 0 && WT::MIN_ARC_SAG < 0.5, WT::MIN_ARC_SAG)

# ------------------------------------------------- the anchors must not move

# For every anchor, the two sides sit a known distance either side of the
# drawn line. On a curve that distance is measured along the ARC's own
# normal (the end cap is radial, like every CAD tool cuts a curved wall), so
# the test is: how far each side's end corner is FROM THE DRAWN END POINT,
# and which side of the line it fell on.
[['center', 2.5, -2.5], ['left', 5.0, 0.0], ['right', 0.0, -5.0]].each do |h_anchor, want_pos, want_neg|
  fp = WT.curved_footprint_xy(0, 0, 120, 0, 5.0, h_anchor, 8.0)
  ok("anchor #{h_anchor}: footprint built", !fp.nil?)
  next unless fp

  n = fp.length / 2
  pos = fp[0, n]                 # outer side, start -> end
  neg = fp[n, n].reverse         # inner side, put back in start -> end order

  ok("anchor #{h_anchor}: both sides have the same number of points",
     pos.length == neg.length, [pos.length, neg.length])

  [['start', pos.first, neg.first, 0.0, 0.0],
   ['end',   pos.last,  neg.last, 120.0, 0.0]].each do |where, p, q, dx, dy|
    ok("anchor #{h_anchor}: #{where} of the + side is #{want_pos.abs} from the drawn point",
       close(AM.dist(dx, dy, p[0], p[1]), want_pos.abs, 1e-6), AM.dist(dx, dy, p[0], p[1]))
    ok("anchor #{h_anchor}: #{where} of the - side is #{want_neg.abs} from the drawn point",
       close(AM.dist(dx, dy, q[0], q[1]), want_neg.abs, 1e-6), AM.dist(dx, dy, q[0], q[1]))
    ok("anchor #{h_anchor}: #{where} + side fell on the correct side",
       want_pos.zero? ? true : left_of(0, 0, 120, 0, p) > 0)
    ok("anchor #{h_anchor}: #{where} - side fell on the correct side",
       want_neg.zero? ? true : left_of(0, 0, 120, 0, q) < 0)
    # The middle of the end cap must sit exactly where the straight wall's
    # does relative to the drawn point - this is what stops curving a wall
    # from sliding it sideways. (Measured as a real distance: the cap is cut
    # radially, so projecting it onto the straight line would read short.)
    cap = [(p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0]
    ok("anchor #{h_anchor}: #{where} cap sits the right distance off the drawn point",
       close(AM.dist(dx, dy, cap[0], cap[1]), ((want_pos + want_neg) / 2.0).abs, 1e-9),
       AM.dist(dx, dy, cap[0], cap[1]))
  end

  ok("anchor #{h_anchor}: the wall is 5\" thick everywhere",
     pos.zip(neg).all? { |a, b| close(AM.dist(a[0], a[1], b[0], b[1]), 5.0, 1e-6) })
end

# A centre-anchored wall must keep BOTH its ends exactly on the drawn points.
cfp = WT.curved_footprint_xy(0, 0, 120, 0, 5.0, 'center', 8.0)
cn = cfp.length / 2
cmid_s = [(cfp[0][0] + cfp[-1][0]) / 2.0, (cfp[0][1] + cfp[-1][1]) / 2.0]
cmid_e = [(cfp[cn - 1][0] + cfp[cn][0]) / 2.0, (cfp[cn - 1][1] + cfp[cn][1]) / 2.0]
ok('centre anchor: the start cap is centred exactly on the drawn start',
   close(cmid_s[0], 0.0, 1e-9) && close(cmid_s[1], 0.0, 1e-9), cmid_s)
ok('centre anchor: the end cap is centred exactly on the drawn end',
   close(cmid_e[0], 120.0, 1e-9) && close(cmid_e[1], 0.0, 1e-9), cmid_e)

# The offsets themselves must match the straight builder's, exactly.
inst = WT.new
[['center', 0], ['left', 0], ['right', 0]].each do |h_anchor, _|
  s = Struct.new(:x, :y)
  corners = inst.perpendicular_corners_xy(s.new(0.0, 0.0), s.new(120.0, 0.0), 5.0, h_anchor)
  o_pos, o_neg = WT.anchor_side_offsets(5.0, h_anchor)
  ok("anchor #{h_anchor}: curved offsets equal the straight builder's",
     close(left_of(0, 0, 120, 0, corners[0]), o_pos) &&
     close(left_of(0, 0, 120, 0, corners[3]), o_neg),
     [left_of(0, 0, 120, 0, corners[0]), o_pos, left_of(0, 0, 120, 0, corners[3]), o_neg])
end

# --------------------------------------------------- which way does it bow

pos_bow = WT.curved_footprint_xy(0, 0, 120, 0, 9.0, 'center', 9.0)
neg_bow = WT.curved_footprint_xy(0, 0, 120, 0, 9.0, 'center', -9.0)
# The belly of the wall's CENTRE line, halfway along - the number the user
# actually dragged. Measured between the two sides so the thickness cancels.
def belly(fp)
  n = fp.length / 2
  k = n / 2
  p = fp[k]
  q = fp[n + (n - 1 - k)]
  left_of(0, 0, 120, 0, [(p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0])
end
ok('a positive bow leans LEFT of the drawn line', belly(pos_bow) > 0, belly(pos_bow))
ok('a negative bow leans RIGHT of the drawn line', belly(neg_bow) < 0, belly(neg_bow))
ok('the two bows are exact mirror images', close(belly(pos_bow), -belly(neg_bow), 1e-9),
   [belly(pos_bow), belly(neg_bow)])
ok('the belly really is about the 9" that was asked for',
   (belly(pos_bow) - 9.0).abs <= WT::CURVE_TOL, belly(pos_bow))
# And the outer side of a positive bow leans further out than the centre.
ok('the outer side leans further out than the centre line',
   left_of(0, 0, 120, 0, pos_bow[pos_bow.length / 4]) > belly(pos_bow))

# ------------------------------------------------- the ring is a real ring

fp = WT.curved_footprint_xy(0, 0, 120, 0, 6.0, 'center', 18.0)
ok('the footprint has an even number of points', fp.length.even?, fp.length)
ok('the footprint has more points than a rectangle', fp.length > 4, fp.length)
ok('no two points land on top of each other',
   fp.each_cons(2).all? { |a, b| AM.dist(a[0], a[1], b[0], b[1]) > 1e-9 })
ok('the ring closes: last point is next to the first, across the thickness',
   close(AM.dist(fp.first[0], fp.first[1], fp.last[0], fp.last[1]), 6.0, 1e-6),
   AM.dist(fp.first[0], fp.first[1], fp.last[0], fp.last[1]))

# Shoelace area > 0 means a simple, non-crossed ring (a bow-tie comes out ~0).
def area(fp)
  a = 0.0
  fp.each_with_index { |p, i| q = fp[(i + 1) % fp.length]; a += p[0] * q[1] - q[0] * p[1] }
  a / 2.0
end
ok('the footprint encloses a real area (not a bow tie)', area(fp).abs > 100.0, area(fp))
# A 10ft wall, 6in thick, bowed 18in: area must stay near length * thickness.
ok('the enclosed area is about arc length x thickness',
   (area(fp).abs / 6.0).between?(120.0, 135.0), area(fp).abs / 6.0)

# ----------------------------------------------------- too tight to build

# 20" long, bowed 10" = a half circle of radius 10. A 30" thick wall cannot
# have an inner face there - it would turn itself inside out. Must refuse.
ok('an impossible curve refuses to build',
   WT.curved_footprint_xy(0, 0, 20, 0, 30.0, 'center', 10.0).nil?,
   WT.curved_footprint_xy(0, 0, 20, 0, 30.0, 'center', 10.0))
ok('the same curve on a thin wall is fine',
   !WT.curved_footprint_xy(0, 0, 20, 0, 4.0, 'center', 10.0).nil?)
ok('a zero-length wall refuses to build',
   WT.curved_footprint_xy(50, 50, 50, 50, 5.0, 'center', 8.0).nil?)

# -------------------------------------------------------- smoothness / cost

gentle = WT.curved_footprint_xy(0, 0, 240, 0, 5.0, 'center', 6.0)
strong = WT.curved_footprint_xy(0, 0, 240, 0, 5.0, 'center', 60.0)
ok('a stronger curve uses more facets', strong.length > gentle.length,
   [gentle.length, strong.length])
ok('even a wild curve stays under the facet ceiling',
   WT.curved_footprint_xy(0, 0, 240, 0, 5.0, 'center', 119.0).length <= (AM::MAX_SEGMENTS + 1) * 2)

# Every facet on the centre line must stay within tolerance of the true curve.
arc = AM.from_chord_and_sag(0, 0, 240, 0, 60.0)
mid = AM.chord_points(arc)
worst = mid.each_cons(2).map do |p, q|
  arc[:r] - AM.dist((p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0, arc[:cx], arc[:cy])
end.max
ok('facets stay inside the 1/8" smoothness budget', worst <= WT::CURVE_TOL + 1e-9, worst)

# ---------------------------------------------------------- a real diagonal

# Nothing above may depend on the wall running along X.
ax, ay, bx, by = 37.0, -12.0, -95.0, 143.0
d = WT.curved_footprint_xy(ax, ay, bx, by, 5.0, 'center', 11.0)
ok('a diagonal wall curves too', !d.nil?)
n = d.length / 2
dpos = d[0, n]
dneg = d[n, n].reverse
ok('diagonal: + side starts 2.5 from the drawn start, on the left',
   close(AM.dist(ax, ay, dpos.first[0], dpos.first[1]), 2.5, 1e-6) &&
   left_of(ax, ay, bx, by, dpos.first) > 0, AM.dist(ax, ay, dpos.first[0], dpos.first[1]))
ok('diagonal: - side starts 2.5 from the drawn start, on the right',
   close(AM.dist(ax, ay, dneg.first[0], dneg.first[1]), 2.5, 1e-6) &&
   left_of(ax, ay, bx, by, dneg.first) < 0, AM.dist(ax, ay, dneg.first[0], dneg.first[1]))
ok('diagonal: the start cap is centred exactly on the drawn start',
   close((dpos.first[0] + dneg.first[0]) / 2.0, ax, 1e-9) &&
   close((dpos.first[1] + dneg.first[1]) / 2.0, ay, 1e-9),
   [(dpos.first[0] + dneg.first[0]) / 2.0, (dpos.first[1] + dneg.first[1]) / 2.0])
ok('diagonal: the end cap is centred exactly on the drawn end',
   close((dpos.last[0] + dneg.last[0]) / 2.0, bx, 1e-9) &&
   close((dpos.last[1] + dneg.last[1]) / 2.0, by, 1e-9),
   [(dpos.last[0] + dneg.last[0]) / 2.0, (dpos.last[1] + dneg.last[1]) / 2.0])
ok('diagonal: still 5" thick everywhere',
   dpos.zip(dneg).all? { |p, q| close(AM.dist(p[0], p[1], q[0], q[1]), 5.0, 1e-6) })
ok('diagonal: bows to the left', left_of(ax, ay, bx, by, dpos[n / 2]) > 2.5,
   left_of(ax, ay, bx, by, dpos[n / 2]))

# ------------------------------------------------------------ kill switch

ok('USE_CURVED_WALLS exists and is on', WT::USE_CURVED_WALLS == true)
ok('curved_wall? is false for a wall with no arc_sag at all',
   WT.wall_sag(nil) == 0.0)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

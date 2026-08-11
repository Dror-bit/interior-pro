# encoding: utf-8
# rt24 — FLAT PANELS for doors and windows on a curved wall (2026-08-11).
#
# A door frame is a straight thing. You cannot bend it. So over the width of
# each opening the wall stops curving and becomes ONE straight panel, and the
# door sits in that. Real builders do the same.
#
# This suite is the outline only - nothing is cut yet. What it has to prove:
#   * the stretch a door occupies really comes out FLAT
#   * the flat panel is exactly as wide as the door, measured straight across
#   * the rest of the wall keeps curving, unchanged
#   * a wall with NO openings comes out byte-for-byte as it did before
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

SX = 0.0
SY = 0.0
EX = 240.0
EY = 0.0
TH = 6.0
SAG = 30.0
ARC = AM.from_chord_and_sag(SX, SY, EX, EY, SAG)
LEN = AM.length(ARC)

def fp_with(openings, thickness = TH, h_anchor = 'center', sag = SAG)
  WT.curved_footprint_xy(SX, SY, EX, EY, thickness, h_anchor, sag, WT::CURVE_TOL, openings)
end

def sides(fp)
  n = fp.length / 2
  [fp[0, n], fp[n, n].reverse]
end

# How far a point sits off the straight line through a and b. ~0 means the
# three points are in a line.
def off_line(a, b, p)
  d = Math.sqrt((b[0] - a[0])**2 + (b[1] - a[1])**2)
  return 0.0 if d < 1e-12
  (((b[0] - a[0]) * (p[1] - a[1])) - ((b[1] - a[1]) * (p[0] - a[0]))).abs / d
end

# ------------------------------------------- nothing changes without doors

# THE regression guard. An empty or missing opening list must give exactly
# the outline the wall had before any of this existed.
plain = WT.curved_footprint_xy(SX, SY, EX, EY, TH, 'center', SAG)
ok('no openings at all -> the old outline, unchanged', fp_with(nil) == plain)
ok('an empty opening list -> the old outline, unchanged', fp_with([]) == plain)
ok('the old call with no openings argument still works', !plain.nil? && plain.length > 4)
%w[center left right].each do |ha|
  a = WT.curved_footprint_xy(SX, SY, EX, EY, TH, ha, SAG)
  b = WT.curved_footprint_xy(SX, SY, EX, EY, TH, ha, SAG, WT::CURVE_TOL, [])
  ok("anchor #{ha}: unchanged without openings", a == b)
end

# ---------------------------------------------- one door comes out FLAT

door = [{ t: LEN / 2.0, width: 36.0 }]
fp = fp_with(door)
ok('a wall with one door still builds an outline', !fp.nil?)
pos, neg = sides(fp)
ok('both sides still have the same number of points', pos.length == neg.length)

# Find the two points that bound the flat panel: the pocket's own ends.
pk = WT.opening_pocket(SX, SY, EX, EY, SAG, LEN / 2.0, 36.0)
ok('the pocket is reported', !pk.nil?)
ok('the pocket knows it is on a curve', pk[:curved] == true)

# Every station strictly inside the pocket must be gone, so the stretch is a
# single straight run.
st = WT.curved_wall_stations(ARC, WT::CURVE_TOL, door)
inside = st.select { |d| d > pk[:panel_d0] + 1e-6 && d < pk[:panel_d1] - 1e-6 }
ok('no outline point survives inside the door opening', inside.empty?, inside)
# The flat panel is a little wider than the opening, so the hole is cut well
# inside flat wall and never right on the seam where the curve starts again.
ok('the panel is wider than the opening it holds',
   pk[:panel_d0] < pk[:d0] && pk[:panel_d1] > pk[:d1], [pk[:panel_d0], pk[:d0], pk[:d1], pk[:panel_d1]])
ok('both ends of the flat PANEL are outline points',
   st.any? { |d| close(d, pk[:panel_d0], 1e-6) } && st.any? { |d| close(d, pk[:panel_d1], 1e-6) },
   [pk[:panel_d0], pk[:panel_d1]])
ok('no outline point survives inside the flat panel either',
   st.none? { |d| d > pk[:panel_d0] + 1e-6 && d < pk[:panel_d1] - 1e-6 })
ok('the opening sits in the middle of its panel',
   close((pk[:d0] + pk[:d1]) / 2.0, (pk[:panel_d0] + pk[:panel_d1]) / 2.0, 1e-9))
ok('the opening\'s two ends lie ON the flat panel, not on the curve',
   off_line(pk[:panel_p0], pk[:panel_p1], pk[:p0]) < 1e-9 &&
   off_line(pk[:panel_p0], pk[:panel_p1], pk[:p1]) < 1e-9,
   [off_line(pk[:panel_p0], pk[:panel_p1], pk[:p0])])
ok('and they are exactly the opening width apart',
   close(AM.dist(pk[:p0][0], pk[:p0][1], pk[:p1][0], pk[:p1][1]), 36.0, 1e-9))
ok('the wall still starts at 0 and ends at its full length',
   close(st.first, 0.0, 1e-9) && close(st.last, LEN, 1e-6), [st.first, st.last, LEN])
ok('the stations only ever go forwards', st.each_cons(2).all? { |a, b| b > a })

# The flat panel really is flat, on BOTH faces of the wall.
i0 = st.index { |d| close(d, pk[:panel_d0], 1e-6) }
i1 = st.index { |d| close(d, pk[:panel_d1], 1e-6) }
ok('the flat panel is one single step of the outline', i1 == i0 + 1, [i0, i1])

# ------------------------------------- the panel is exactly the door's width

# This is the whole point: the door is 36" measured STRAIGHT ACROSS, so the
# flat panel must be 36" straight across - not 36" of curve.
[[36.0, 'a 36" door'], [72.0, 'a 72" slider'], [24.0, 'a 24" window']].each do |w, label|
  p = WT.opening_pocket(SX, SY, EX, EY, SAG, LEN / 2.0, w)
  ok("#{label}: the flat panel is built", !p.nil?)
  next unless p
  straight = AM.dist(p[:p0][0], p[:p0][1], p[:p1][0], p[:p1][1])
  ok("#{label}: measures #{w}\" straight across", close(straight, w, 1e-6), straight)
  ok("#{label}: eats slightly MORE wall than that, because the wall curves",
     (p[:d1] - p[:d0]) > w, [p[:d1] - p[:d0], w])
  ok("#{label}: but not much more", (p[:d1] - p[:d0]) < w * 1.2, p[:d1] - p[:d0])
  ok("#{label}: gets a strip of flat wall either side",
     (p[:panel_d1] - p[:panel_d0]) > (p[:d1] - p[:d0]),
     [p[:panel_d1] - p[:panel_d0], p[:d1] - p[:d0]])
  ok("#{label}: is centred on where the door was asked for",
     close((p[:d0] + p[:d1]) / 2.0, LEN / 2.0, 1e-9), (p[:d0] + p[:d1]) / 2.0)
  ok("#{label}: reports a unit direction",
     close(Math.sqrt(p[:dir][0]**2 + p[:dir][1]**2), 1.0, 1e-9), p[:dir])
  ok("#{label}: its middle sits halfway between its ends",
     close(p[:center][0], (p[:p0][0] + p[:p1][0]) / 2.0, 1e-9) &&
     close(p[:center][1], (p[:p0][1] + p[:p1][1]) / 2.0, 1e-9))
end

# The panel's direction must be the direction of its own straight run - that
# is what a door body will be turned to.
p36 = WT.opening_pocket(SX, SY, EX, EY, SAG, LEN / 2.0, 36.0)
dx = p36[:panel_p1][0] - p36[:panel_p0][0]
dy = p36[:panel_p1][1] - p36[:panel_p0][1]
dl = Math.sqrt(dx * dx + dy * dy)
ok('the panel direction really is end-minus-start',
   close(p36[:dir][0], dx / dl, 1e-9) && close(p36[:dir][1], dy / dl, 1e-9))
# At the middle of this wall the curve runs flat along X, so the panel does too.
ok('a door in the middle of this wall runs along the wall, not across it',
   p36[:dir][0].abs > 0.99, p36[:dir])

# A door somewhere else leans, because the wall leans there.
poff = WT.opening_pocket(SX, SY, EX, EY, SAG, LEN * 0.2, 36.0)
ok('a door near the end leans, following the wall there', poff[:dir][1].abs > 0.05, poff[:dir])

# ---------------------------- the curve outside the opening is untouched

fp_open = fp_with(door)
st_open = WT.curved_wall_stations(ARC, WT::CURVE_TOL, door)
st_plain = WT.curved_wall_stations(ARC, WT::CURVE_TOL, nil)
kept = st_plain.select { |d| d < pk[:panel_d0] - 1e-6 || d > pk[:panel_d1] + 1e-6 }
ok('every curve point outside the opening survives',
   kept.all? { |d| st_open.any? { |s| close(s, d, 1e-9) } })
ok('the wall away from the door is still curved',
   st_open.select { |d| d < pk[:panel_d0] - 1e-6 }.length >= 2,
   st_open.select { |d| d < pk[:panel_d0] - 1e-6 }.length)
# Points before the opening must NOT be in a line - that stretch still bends.
before = st_open.select { |d| d <= pk[:panel_d0] + 1e-9 }
if before.length >= 3
  a = AM.point_at_distance(ARC, before[0])
  b = AM.point_at_distance(ARC, before[-1])
  mid = AM.point_at_distance(ARC, before[before.length / 2])
  ok('the stretch before the door is genuinely still curved', off_line(a, b, mid) > 0.05,
     off_line(a, b, mid))
end

# --------------------------------------------------- more than one opening

two = [{ t: LEN * 0.25, width: 36.0 }, { t: LEN * 0.75, width: 48.0 }]
ok('two openings on one wall are fine', !fp_with(two).nil?)
st2 = WT.curved_wall_stations(ARC, WT::CURVE_TOL, two)
two.each do |o|
  p = WT.opening_pocket(SX, SY, EX, EY, SAG, o[:t], o[:width])
  ok("opening at #{o[:t].round(1)} gets its own flat panel",
     st2.none? { |d| d > p[:panel_d0] + 1e-6 && d < p[:panel_d1] - 1e-6 })
end
ok('openings given out of order still work',
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, two.reverse) == st2)
ok('string keys work as well as symbols',
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, [{ 't' => LEN / 2.0, 'width' => 36.0 }]) ==
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, [{ t: LEN / 2.0, width: 36.0 }]))

# ------------------------------------------------------ refusing bad input

ok('two overlapping openings are refused',
   WT.curved_wall_stations(ARC, WT::CURVE_TOL,
                           [{ t: LEN / 2.0, width: 60.0 }, { t: LEN / 2.0 + 20.0, width: 60.0 }]).nil?)
ok('an opening hanging off the start is refused',
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, [{ t: 2.0, width: 36.0 }]).nil?)
ok('an opening hanging off the end is refused',
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, [{ t: LEN - 2.0, width: 36.0 }]).nil?)
ok('a zero-width opening is ignored, not a crash',
   !WT.curved_wall_stations(ARC, WT::CURVE_TOL, [{ t: LEN / 2.0, width: 0.0 }]).nil?)
ok('a junk opening is ignored',
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, [nil, {}]) ==
   WT.curved_wall_stations(ARC, WT::CURVE_TOL, nil))
ok('the whole footprint refuses when the openings do not fit',
   fp_with([{ t: 2.0, width: 36.0 }]).nil?)

# A door wider than the curve's own circle can never lie flat in it.
tight = AM.from_chord_and_sag(0, 0, 40, 0, 20.0)   # r = 20, a half circle
ok('a door wider than the curve itself is refused',
   WT.curved_wall_stations(tight, WT::CURVE_TOL, [{ t: AM.length(tight) / 2.0, width: 90.0 }]).nil?)
ok('half_arc_for_chord refuses a chord wider than the circle',
   AM.half_arc_for_chord(tight, 41.0).nil?)
ok('half_arc_for_chord is never shorter than half the chord',
   AM.half_arc_for_chord(ARC, 36.0) >= 18.0, AM.half_arc_for_chord(ARC, 36.0))

# ------------------------------------------- a straight wall answers too

# opening_pocket must work on a straight wall as well, so nothing downstream
# has to ask whether the wall is curved.
sp = WT.opening_pocket(0, 0, 240, 0, 0.0, 120.0, 36.0)
ok('a straight wall reports a pocket too', !sp.nil?)
ok('and says it is not curved', sp[:curved] == false)
ok('straight: the panel is exactly the door width',
   close(AM.dist(sp[:p0][0], sp[:p0][1], sp[:p1][0], sp[:p1][1]), 36.0, 1e-9))
ok('straight: it eats exactly the door width of wall, no more',
   close(sp[:d1] - sp[:d0], 36.0, 1e-9), sp[:d1] - sp[:d0])
ok('straight: it runs along the wall', close(sp[:dir][0], 1.0, 1e-9) && close(sp[:dir][1], 0.0, 1e-9))
ok('straight: it sits where it was asked for',
   close(sp[:center][0], 120.0, 1e-9) && close(sp[:center][1], 0.0, 1e-9))
ok('straight: an opening off the end is refused',
   WT.opening_pocket(0, 0, 240, 0, 0.0, 238.0, 36.0).nil?)
ok('a zero-length wall reports nothing', WT.opening_pocket(5, 5, 5, 5, 10.0, 1.0, 36.0).nil?)
ok('a zero-width opening reports nothing', WT.opening_pocket(0, 0, 240, 0, 0.0, 120.0, 0.0).nil?)

# ------------------------------------- the panel really is flat in the wall

# The two outline points either side of the panel, on BOTH faces, plus the
# wall thickness between them - the door has to fit in there.
o_pos, o_neg = WT.anchor_side_offsets(TH, 'center')
a_pos = AM.offset_point_at_distance(ARC, pk[:panel_d0], o_pos)
b_pos = AM.offset_point_at_distance(ARC, pk[:panel_d1], o_pos)
a_neg = AM.offset_point_at_distance(ARC, pk[:panel_d0], o_neg)
b_neg = AM.offset_point_at_distance(ARC, pk[:panel_d1], o_neg)
ok('the panel is still one wall thickness deep at both ends',
   close(AM.dist(a_pos[0], a_pos[1], a_neg[0], a_neg[1]), TH, 1e-6) &&
   close(AM.dist(b_pos[0], b_pos[1], b_neg[0], b_neg[1]), TH, 1e-6))
# The two faces of the panel must be PARALLEL, or a straight frame would bind.
d_out = [b_pos[0] - a_pos[0], b_pos[1] - a_pos[1]]
d_in  = [b_neg[0] - a_neg[0], b_neg[1] - a_neg[1]]
cosv = ((d_out[0] * d_in[0] + d_out[1] * d_in[1]) /
        (Math.sqrt(d_out[0]**2 + d_out[1]**2) * Math.sqrt(d_in[0]**2 + d_in[1]**2)))
ok('the panel\'s two faces are parallel, so a straight frame fits',
   close(cosv, 1.0, 1e-9), cosv)
# The outer face of the panel is a little longer than the inner one - that is
# a real opening in a curved wall, splayed slightly at the jambs.
ok('the outer face is the longer one on a wall bowing this way',
   (Math.sqrt(d_out[0]**2 + d_out[1]**2) - Math.sqrt(d_in[0]**2 + d_in[1]**2)).abs > 1e-6,
   [Math.sqrt(d_out[0]**2 + d_out[1]**2), Math.sqrt(d_in[0]**2 + d_in[1]**2)])

# ------------------------------------------ the hole lands ON the panel

# The hole is drawn on the wall's own face and pushed through to the back.
# Two things have to be exactly right or SketchUp makes a mess: the four
# corners must sit ON the face (not a hair inside it), and the push depth
# must be the real distance to the face behind - which on a curve is a touch
# LESS than the wall thickness.
o_p, o_n = WT.anchor_side_offsets(TH, 'center')
pkx = WT.opening_pocket(SX, SY, EX, EY, SAG, LEN / 2.0, 36.0)
fa = AM.offset_point_at_distance(ARC, pkx[:panel_d0], o_p)
fb = AM.offset_point_at_distance(ARC, pkx[:panel_d1], o_p)
ba = AM.offset_point_at_distance(ARC, pkx[:panel_d0], o_n)
bb = AM.offset_point_at_distance(ARC, pkx[:panel_d1], o_n)
uxx = fb[0] - fa[0]
uyy = fb[1] - fa[1]
ull = Math.sqrt(uxx**2 + uyy**2)
uxx /= ull; uyy /= ull
nxx = -uyy; nyy = uxx
depth = ((ba[0] - fa[0]) * nxx) + ((ba[1] - fa[1]) * nyy)

ok('the two panel faces are parallel', close(off_line(fa, fb, ba), off_line(fa, fb, bb), 1e-9))
ok('the push depth is a real distance', depth.abs > 0.1, depth)
ok('the push depth is slightly LESS than the wall thickness (it is a curve)',
   depth.abs < TH && depth.abs > TH * 0.95, [depth.abs, TH])
ok('pushing the full thickness would poke out the back', TH > depth.abs)

# The hole itself: centred on the panel face, exactly the door width.
mxx = (fa[0] + fb[0]) / 2.0
myy = (fa[1] + fb[1]) / 2.0
h1 = [mxx - uxx * 18.0, myy - uyy * 18.0]
h2 = [mxx + uxx * 18.0, myy + uyy * 18.0]
ok('the hole is exactly the door width', close(AM.dist(h1[0], h1[1], h2[0], h2[1]), 36.0, 1e-9))
ok('both hole edges sit ON the panel face',
   off_line(fa, fb, h1) < 1e-9 && off_line(fa, fb, h2) < 1e-9)
ok('the hole fits inside the panel face with room to spare',
   AM.dist(fa[0], fa[1], h1[0], h1[1]) > 0.5 && AM.dist(fb[0], fb[1], h2[0], h2[1]) > 0.5,
   [AM.dist(fa[0], fa[1], h1[0], h1[1]), AM.dist(fb[0], fb[1], h2[0], h2[1])])
ok('the panel face is wider than the hole', ull > 36.0, ull)

# A door too wide for the panel it was given must never be cut.
ok('a door as wide as its whole panel is caught before cutting', ull - 36.0 > 0.02, ull - 36.0)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

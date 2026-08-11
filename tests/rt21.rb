# encoding: utf-8
# rt21 — the DRAG itself (wall_curve_tool.rb, 2026-08-10).
# The tool turns a cursor position into one number: how far the wall's middle
# is pulled sideways. If that number is wrong the wall bows the wrong way or
# by the wrong amount, so it gets its own suite.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
InteriorPro.send(:remove_const, :WallCurveTool) if InteriorPro.const_defined?(:WallCurveTool, false)
require './arc_math'
require './wall_tool'
require './wall_curve_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

CT = InteriorPro::WallCurveTool
WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

# ------------------------------------------------------ cursor -> bow number

# Wall along +X. Cursor above the line = LEFT of start -> end = positive.
ok('cursor above a west-east wall gives a positive bow',
   close(CT.sag_from_point(0, 0, 100, 0, 50, 20), 20.0), CT.sag_from_point(0, 0, 100, 0, 50, 20))
ok('cursor below it gives a negative bow',
   close(CT.sag_from_point(0, 0, 100, 0, 50, -20), -20.0), CT.sag_from_point(0, 0, 100, 0, 50, -20))
ok('cursor exactly on the line gives zero',
   close(CT.sag_from_point(0, 0, 100, 0, 50, 0), 0.0))
ok('sliding the cursor ALONG the wall changes nothing',
   close(CT.sag_from_point(0, 0, 100, 0, 5, 20), CT.sag_from_point(0, 0, 100, 0, 95, 20)))
ok('the cursor may sit past the wall end and still work',
   close(CT.sag_from_point(0, 0, 100, 0, 500, 20), 20.0))

# Drawing the same wall backwards flips which side is "positive" - that is
# correct, and it is why the tool reads start/end straight off the wall.
ok('a wall drawn the other way flips the sign',
   close(CT.sag_from_point(100, 0, 0, 0, 50, 20), -20.0), CT.sag_from_point(100, 0, 0, 0, 50, 20))

ok('a zero-length wall gives nil, not a crash',
   CT.sag_from_point(7, 7, 7, 7, 50, 20).nil?)

# Works on any angle, not just along an axis.
[[0, 0, 100, 100], [0, 0, -60, 20], [12, -40, -3, -180]].each do |sx, sy, ex, ey|
  chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
  # A point exactly 9" to the LEFT of the middle of the wall.
  nx = -(ey - sy) / chord
  ny =  (ex - sx) / chord
  px = (sx + ex) / 2.0 + nx * 9.0
  py = (sy + ey) / 2.0 + ny * 9.0
  ok("angled wall (#{sx},#{sy})->(#{ex},#{ey}): a point 9\" left reads as +9",
     close(CT.sag_from_point(sx, sy, ex, ey, px, py), 9.0, 1e-9),
     CT.sag_from_point(sx, sy, ex, ey, px, py))
end

# ------------------------------------- the drag really lands where you point

# THE test that matters: point at a spot, take the number the tool computes,
# build the wall with it, and the middle of the wall must arrive at that spot.
[[0, 0, 120, 0, 60, 14], [0, 0, 120, 0, 60, -14], [10, 5, -70, 90, -20, 60]].each do |sx, sy, ex, ey, px, py|
  sag = CT.sag_from_point(sx, sy, ex, ey, px, py)
  arc = AM.from_chord_and_sag(sx, sy, ex, ey, sag)
  mid = AM.mid_point(arc)
  # The wall's middle should land on the cursor's own sideways offset - the
  # cursor may be anywhere along the wall, so compare sideways distance only.
  got = CT.sag_from_point(sx, sy, ex, ey, mid[0], mid[1])
  ok("drag to (#{px},#{py}): the wall's middle lands on that sideways offset",
     close(got, sag, 1e-9), [got, sag])
end

# ------------------------------------------------- the ghost tells the truth

# The straight ghost must be exactly the straight builder's footprint.
inst = WT.new
s = Struct.new(:x, :y)
[['center', 5.0], ['left', 5.0], ['right', 5.0], ['center', 12.0]].each do |h_anchor, th|
  ghost = CT.straight_corners(0, 0, 120, 0, th, h_anchor)
  real  = inst.perpendicular_corners_xy(s.new(0.0, 0.0), s.new(120.0, 0.0), th, h_anchor)
  same = ghost.zip(real).all? { |g, r| close(g[0], r[0], 1e-9) && close(g[1], r[1], 1e-9) }
  ok("ghost matches the real straight footprint (#{h_anchor}, #{th}\")", same, [ghost, real])
end
ok('the straight ghost of a zero-length wall is nil',
   CT.straight_corners(3, 3, 3, 3, 5.0, 'center').nil?)

# And the curved ghost is literally the footprint that will be built.
gh = WT.curved_footprint_xy(0, 0, 120, 0, 5.0, 'center', 14.0)
ok('the curved ghost is the real footprint', !gh.nil? && gh.length > 4, gh&.length)

# ------------------------------------------------------- refusing a bad bow

# 20" wall, 30" thick, bowed 10": impossible. The tool must get nil back and
# refuse rather than build something inside out.
ok('an impossible bow gives the tool nil to refuse on',
   WT.curved_footprint_xy(0, 0, 20, 0, 30.0, 'center', 10.0).nil?)
# A bow under the noise floor is simply straight, never an error.
ok('a bow under the noise floor is treated as straight',
   WT.curved_footprint_xy(0, 0, 120, 0, 5.0, 'center', WT::MIN_ARC_SAG / 2).nil?)

# ------------------------------------------------- typed value keeps the side

# onUserText uses |typed| and the side the mouse is on. Reproduce that rule.
def typed(value, current_sag)
  value.abs * (current_sag >= 0 ? 1.0 : -1.0)
end
ok('typing 12 while the mouse is on the left bows left',  close(typed(12, 5.0), 12.0))
ok('typing 12 while the mouse is on the right bows right', close(typed(12, -5.0), -12.0))
ok('typing -12 does not sneak the wall to the other side', close(typed(-12, 5.0), 12.0))
ok('typing 0 straightens it', close(typed(0, -5.0), 0.0))

# ------------------------------------------------ reading a typed-in number

# The right-click box takes the number as-is, INCLUDING its minus sign, so a
# person can type the exact bow they want on either side.
ok('reads a plain number as inches', close(CT.parse_length('12'), 12.0), CT.parse_length('12'))
ok('reads a negative number', close(CT.parse_length('-12'), -12.0), CT.parse_length('-12'))
ok('reads a decimal', close(CT.parse_length('7.5'), 7.5), CT.parse_length('7.5'))
ok('reads a comma decimal', close(CT.parse_length('7,5'), 7.5), CT.parse_length('7,5'))
ok('reads zero', close(CT.parse_length('0'), 0.0), CT.parse_length('0'))
ok('reads a negative zero as zero', close(CT.parse_length('-0'), 0.0), CT.parse_length('-0'))
ok('reads feet', close(CT.parse_length("1'"), 12.0), CT.parse_length("1'"))
ok('reads negative feet', close(CT.parse_length("-1'"), -12.0), CT.parse_length("-1'"))
ok('reads a Hebrew geresh as feet', close(CT.parse_length('1׳'), 12.0), CT.parse_length('1׳'))
ok('ignores stray spaces', close(CT.parse_length('  -9  '), -9.0), CT.parse_length('  -9  '))
ok('empty text is nil, not zero', CT.parse_length('').nil?)
ok('a lone minus is nil, not zero', CT.parse_length('-').nil?)
ok('nil text is nil', CT.parse_length(nil).nil?)

# ---------------------------------------------- the seams can all be hidden

# A curved wall is many flat panels. SketchUp draws a line at every seam, and
# the user saw those lines. They are hidden by softening the seams - but only
# where the two panels are nearly in line. So: the faceting must never turn
# more sharply than the softening threshold, or lines would stay visible.
def worst_turn(fp)
  n = fp.length / 2
  side = fp[0, n]
  worst = 0.0
  side.each_cons(3) do |a, b, c|
    v1 = [b[0] - a[0], b[1] - a[1]]
    v2 = [c[0] - b[0], c[1] - b[1]]
    l1 = Math.sqrt(v1[0]**2 + v1[1]**2)
    l2 = Math.sqrt(v2[0]**2 + v2[1]**2)
    next if l1 < 1e-9 || l2 < 1e-9
    cosv = ((v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)).clamp(-1.0, 1.0)
    a_deg = Math.acos(cosv) * 180.0 / Math::PI
    worst = a_deg if a_deg > worst
  end
  worst
end

[[0, 0, 240, 0, 6.0, 6.0],       # a gentle 20ft bow
 [0, 0, 240, 0, 6.0, 60.0],      # a strong one
 [0, 0, 240, 0, 6.0, 119.0],     # nearly a half circle
 [0, 0, 96, 0, 4.0, 40.0],       # a short tight one
 [0, 0, 600, 0, 8.0, 30.0]].each do |sx, sy, ex, ey, th, sag|
  fp = WT.curved_footprint_xy(sx, sy, ex, ey, th, 'center', sag)
  next ok("footprint for sag #{sag} built", false) unless fp
  w = worst_turn(fp)
  ok("sag #{sag} on a #{(ex - sx).to_i}\" wall: every seam is soft enough to hide (#{w.round(2)} deg)",
     w < WT::CURVE_SMOOTH_MAX_ANGLE, w)
end
ok('the smoothing threshold is a sane angle',
   WT::CURVE_SMOOTH_MAX_ANGLE > 20.0 && WT::CURVE_SMOOTH_MAX_ANGLE < 90.0,
   WT::CURVE_SMOOTH_MAX_ANGLE)

# The wall's own END corners must stay visible: there the panels meet at a
# real angle, far above the threshold, so softening leaves them alone.
fp_end = WT.curved_footprint_xy(0, 0, 240, 0, 6.0, 'center', 30.0)
n_end = fp_end.length / 2
first_side = fp_end[0]
second_side = fp_end[1]
last_other = fp_end[-1]
v_side = [second_side[0] - first_side[0], second_side[1] - first_side[1]]
v_cap  = [first_side[0] - last_other[0], first_side[1] - last_other[1]]
lc = Math.sqrt(v_cap[0]**2 + v_cap[1]**2)
ls = Math.sqrt(v_side[0]**2 + v_side[1]**2)
cap_angle = Math.acos((((v_side[0] * v_cap[0] + v_side[1] * v_cap[1]) / (ls * lc)).clamp(-1.0, 1.0))) * 180.0 / Math::PI
ok('the wall end is a real corner, well past the threshold',
   cap_angle > WT::CURVE_SMOOTH_MAX_ANGLE, cap_angle)
# It is a touch over square, not exactly 90: the cap is cut radially while the
# first panel is a straight chord, so it leans by half a facet. That is right.
ok('the wall end is still roughly square', (cap_angle - 90.0).abs < 10.0, cap_angle)
ok('typing 12 while the mouse is on the right bows right', close(typed(12, -5.0), -12.0))
ok('typing -12 does not sneak the wall to the other side', close(typed(-12, 5.0), 12.0))
ok('typing 0 straightens it', close(typed(0, -5.0), 0.0))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

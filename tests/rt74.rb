# encoding: utf-8
# rt74 — a window is never cut into a wall you did not click on (2026-08-18).
#
# WHAT HAPPENED
# The user placed a window and a hole appeared somewhere else entirely, on the
# other side of the house. His console gave the number away:
#
#     [WindowTool] n_offset=87.8809
#
# n_offset is how far the clicked point sits off the chosen wall's centreline
# plane. On a real click it is half a wall thickness - about 2.5". Here it was
# 87.88", i.e. the wall the tool picked was seven feet BEHIND the point he
# clicked.
#
# THE CAUSE
# SketchUp's PickHelper returns everything along the pick ray, near and far.
# find_wall_under_cursor took the first path that merely CONTAINED a wall, so
# whenever the nearest thing was not a wall - a pillar, an existing window,
# the roof overhang - it walked deeper down the ray and grabbed a wall on the
# far side of the building.
#
# THE FIX, and what this suite pins
# click_on_wall? asks whether the point is really on that wall, using the
# SAME arithmetic cut_window_opening uses, so the filter predicts the cut
# instead of guessing at it. A candidate that fails is skipped, not cut.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'
require './window_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); !a.nil? && !b.nil? && (a - b).abs < tol; end

D = 'InteriorPro'
MODEL = Sketchup.active_model
TOOL = InteriorPro::WindowTool.new

def mkwall(sx, sy, ex, ey, anchor = 'bottom-center', th = 5.0, sag = nil)
  g = MODEL.entities.add_group
  g.set_attribute(D, 'type', 'wall')
  g.set_attribute(D, 'id', "w#{rand(1_000_000)}")
  g.set_attribute(D, 'start_x', sx); g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);   g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', th); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', anchor)
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

def pt(x, y, z = 0)
  Geom::Point3d.new(x, y, z)
end

def on?(w, p)
  TOOL.send(:click_on_wall?, w, p)
end

def offs(w, p)
  TOOL.send(:wall_click_offsets, w, p)
end

# A plain 200" wall along +X, 5" thick, centre anchored.
W = mkwall(0.0, 0.0, 200.0, 0.0)

# ---------------------------------------------------- the numbers themselves

o = offs(W, pt(50.0, 2.5))
ok('a click on the face is half a thickness off the centreline',
   close(o[:n_offset], 2.5), o)
ok('...and it reports how far along the wall it lands', close(o[:t], 50.0), o)
ok('the other face is the same distance, other sign',
   close(offs(W, pt(50.0, -2.5))[:n_offset], -2.5))
ok('dead on the centreline is zero', close(offs(W, pt(50.0, 0.0))[:n_offset], 0.0))
ok('it reports the wall length', close(o[:length], 200.0), o[:length])
ok('a wall with no attributes gives nil, not a crash',
   offs(MODEL.entities.add_group, pt(0, 0)).nil?)
ok('a zero length wall gives nil', offs(mkwall(0.0, 0.0, 0.0, 0.0), pt(0, 0)).nil?)

# --------------------------------------------------------- accept and refuse

ok('a click ON the near face is accepted',  on?(W, pt(50.0, 2.5)))
ok('a click ON the far face is accepted',   on?(W, pt(50.0, -2.5)))
ok('a click on the centreline is accepted', on?(W, pt(50.0, 0.0)))
ok('siding thickness is still accepted',    on?(W, pt(50.0, 3.4)))
ok('a casing at 5" is accepted',            on?(W, pt(50.0, 5.0)))
ok('>>> THE BUG: a wall 87.88" away is REFUSED', !on?(W, pt(50.0, 87.8809)))
ok('    and refused on the other side too',     !on?(W, pt(50.0, -87.8809)))
ok('a wall 12" away is refused', !on?(W, pt(50.0, 12.0)))
ok('a wall 6" away is refused',  !on?(W, pt(50.0, 6.0)))
ok('nil point is refused, not a crash', !on?(W, nil))

# The tolerance must not creep. 3" of slack past the face, no more.
ok('the slack past the face is exactly 3 inches', close(TOOL.send(:off_wall_tol), 3.0),
   TOOL.send(:off_wall_tol))
ok('so a 5" wall accepts up to 5.5" and refuses 5.6"',
   on?(W, pt(50.0, 5.5)) && !on?(W, pt(50.0, 5.6)))

# ------------------------------------------------- a thick wall gets its due

T12 = mkwall(0.0, 500.0, 200.0, 500.0, 'bottom-center', 12.0)
ok('a 12" wall accepts a click on ITS face (6")', on?(T12, pt(50.0, 506.0)))
ok('...and still refuses 87.88"', !on?(T12, pt(50.0, 587.88)))

# ------------------------------------------------------- anchors move the wall
# A left-anchored wall's centreline sits half a thickness off the drawn line,
# and the check has to follow it there - the same offset cut_window_opening
# bakes in. If these two ever disagree the filter is worthless.

L = mkwall(0.0, 1000.0, 200.0, 1000.0, 'bottom-left')
ok('left anchor: the drawn line is half a thickness off the centreline',
   close(offs(L, pt(50.0, 1000.0))[:n_offset], -2.5), offs(L, pt(50.0, 1000.0)))
ok('left anchor: a click on the real face is accepted', on?(L, pt(50.0, 1005.0)))
ok('left anchor: 87.88" away is still refused', !on?(L, pt(50.0, 1087.88)))

R = mkwall(0.0, 2000.0, 200.0, 2000.0, 'bottom-right')
ok('right anchor: the offset flips sign',
   close(offs(R, pt(50.0, 2000.0))[:n_offset], 2.5), offs(R, pt(50.0, 2000.0)))

# ---------------------------------------------------------- a curved wall
# A curve bows away from the straight line between its ends, so a click on its
# middle is legitimately far from the chord. It gets its sag as extra slack -
# otherwise every window on a round room would be refused.

C = mkwall(0.0, 3000.0, 200.0, 3000.0, 'bottom-center', 5.0, 30.0)
ok('a curved wall is recognised as curved',
   InteriorPro::WallTool.curved_wall?(C), InteriorPro::WallTool.wall_sag(C))
ok('a click out on the bow is accepted', on?(C, pt(100.0, 3030.0)))
ok('but 87.88" past the bow is still refused', !on?(C, pt(100.0, 3120.0)))
ok('a straight wall gets NO sag allowance', !on?(W, pt(100.0, 30.0)))

# ------------------------------- a wall that is NOT at the model origin
# (2026-08-18C §8 - the bug that blocked the user: "it works better on the
# lower floor but it does not work on the upper floor".)
#
# start_x/start_y and friends are LOCAL to the wall group. The click is in
# WORLD space. As long as a wall sits at the origin the two are the same
# numbers and nobody notices. Measured on the user's real house
# (win_level_report.txt): 10 of his 12 level-2 walls carry
# y = -161.687 in their group transformation, and 18 of his 22 level-1 walls
# carry a shift too. Only the 4 identity walls ever computed correctly.
#
# A pure lift (z only) is harmless, which is why level 1 SEEMED to work.

LV2 = mkwall(0.0, 0.0, 200.0, 0.0)
LV2.transformation = Geom::Transformation.new(Geom::Point3d.new(0.0, -161.687, 106.0))
LV2_HIT = pt(50.0, -159.187, 106.0)   # 2.5" off ITS centreline, in world space

ok('a lifted+shifted wall: a click on its REAL face is accepted', on?(LV2, LV2_HIT))
ok('a lifted+shifted wall: the offset is half a thickness, not 161"',
   close(offs(LV2, LV2_HIT)[:n_offset], 2.5), offs(LV2, LV2_HIT))
ok('a lifted+shifted wall: the click still lands 50" along the wall',
   close(offs(LV2, LV2_HIT)[:t], 50.0), offs(LV2, LV2_HIT))
ok('a lifted+shifted wall: the spot where it was DRAWN is refused',
   !on?(LV2, pt(50.0, 2.5, 106.0)))
ok('a lifted+shifted wall: 87.88" off its real face is still refused',
   !on?(LV2, pt(50.0, -73.807, 106.0)))

# A shift along X as well - the user has walls at x = 76.603 too.
SHX = mkwall(0.0, 0.0, 200.0, 0.0)
SHX.transformation = Geom::Transformation.new(Geom::Point3d.new(76.603, -48.256, 0.0))
ok('a wall shifted in X and Y: a click on its real face is accepted',
   on?(SHX, pt(126.603, -45.756)))
ok('a wall shifted in X and Y: 12" off its real face is refused',
   !on?(SHX, pt(126.603, -36.256)))

# A pure lift must behave EXACTLY as it did before - this is the promise that
# level 1 cannot break.
LIFT = mkwall(0.0, 0.0, 200.0, 0.0)
LIFT.transformation = Geom::Transformation.new(Geom::Point3d.new(0.0, 0.0, 106.0))
ok('a purely lifted wall reads exactly like an unlifted one',
   close(offs(LIFT, pt(50.0, 2.5, 106.0))[:n_offset], 2.5) &&
   close(offs(LIFT, pt(50.0, 2.5, 106.0))[:t], 50.0))
ok('an identity wall is unchanged by the conversion',
   close(offs(W, pt(50.0, 2.5))[:n_offset], 2.5) && on?(W, pt(50.0, 2.5)))

# ------------------------------------------- the guard is really in the code
src = File.read('window_tool.rb', encoding: 'UTF-8')

# The filter and the cut MUST convert the click the same way. If only one of
# them does it, the filter stops predicting the cut and is worthless again.
ok('the filter converts the click into the wall\'s own space',
   src[/def wall_click_offsets.*?\n    end/m].to_s.include?('wall_local_point'))
ok('the cut converts the click the same way',
   src[/def cut_window_opening.*?Validate fit along wall length/m].to_s
      .include?('wall_local_point'))
ok('there is ONE conversion helper, not two copies of the maths',
   src.include?('def wall_local_point'))
ok('find_wall_under_cursor actually calls the filter',
   src[/def find_wall_under_cursor.*?\n    end/m].to_s.include?('click_on_wall?'))
ok('a rejected candidate is skipped, not returned',
   src.include?('unless click_on_wall?(wall, point)'))
ok('cut_window_opening refuses an off-wall point too',
   src[/def cut_window_opening.*?Validate fit along wall length/m].to_s.include?('allow_off'))
ok('the user is told WHY nothing happened',
   src.include?('Not on a wall face'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

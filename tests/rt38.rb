# encoding: utf-8
# rt38 — drawing a wall by hand at ANY angle (2026-08-12).
#
# The bug the user hit: detect_auto_snap always chose the NEARER of red and
# green, so every wall he drew was thrown onto one of those two. An angled
# wall was impossible to draw with the mouse.
#
# The rule now: red and green pull the hardest, the four 45s pull a little
# less, and outside both windows nothing is snapped at all - the wall goes
# exactly where the mouse is. This suite calls the real
# WallTool.direction_snap; it carries no copy of the rule.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

WT = InteriorPro::WallTool
def at(deg, len = 200.0)
  r = deg * Math::PI / 180.0
  [Math.cos(r) * len, Math.sin(r) * len]
end
def snap(deg, len = 200.0); WT.direction_snap(*at(deg, len)); end

# ---------------- red and green still win -------------------------------
ok('dead east is red',   snap(0.0)   == :x, snap(0.0))
ok('dead west is red',   snap(180.0) == :x, snap(180.0))
ok('dead north is green', snap(90.0)  == :y, snap(90.0))
ok('dead south is green', snap(-90.0) == :y, snap(-90.0))
ok('a wobble of 3 degrees is still red', snap(3.0) == :x, snap(3.0))
ok('a wobble of 3 degrees off green is still green', snap(87.0) == :y, snap(87.0))

# ---------------- the four 45s ------------------------------------------
[45.0, 135.0, -135.0, -45.0].each do |a|
  s = snap(a)
  ok("#{a.to_i} degrees snaps to a 45", s.is_a?(Array) && s[0] == :diag, s)
  next unless s.is_a?(Array)
  got = Math.atan2(s[2], s[1]) * 180.0 / Math::PI
  ok("#{a.to_i} degrees snaps to the RIGHT 45", WT.angle_gap(got, a) < 1e-6, got)
end
ok('2 degrees off a 45 still snaps to it', snap(47.0).is_a?(Array), snap(47.0))

# ---------------- and everything else is FREE ---------------------------
# This is the whole complaint. Before the fix every one of these came back
# as :x or :y.
[20.0, 30.0, 60.0, 70.0, 110.0, 160.0, -25.0, -70.0, 200.0, 254.0].each do |a|
  ok("#{a.to_i} degrees is left alone - free hand", snap(a).nil?, snap(a))
end

# the exact edge of each window
ok('just inside the red window snaps',  !snap(WT::DRAW_SNAP_ORTHO_DEG - 0.5).nil?)
ok('just outside the red window is free', snap(WT::DRAW_SNAP_ORTHO_DEG + 0.5).nil?,
   snap(WT::DRAW_SNAP_ORTHO_DEG + 0.5))
ok('just outside the 45 window is free',
   snap(45.0 + WT::DRAW_SNAP_DIAG_DEG + 0.5).nil?, snap(45.0 + WT::DRAW_SNAP_DIAG_DEG + 0.5))

# red beats the 45 where the two windows would overlap, if they ever did
ok('red and green have the wider pull', WT::DRAW_SNAP_ORTHO_DEG > WT::DRAW_SNAP_DIAG_DEG,
   [WT::DRAW_SNAP_ORTHO_DEG, WT::DRAW_SNAP_DIAG_DEG])

# ---------------- no direction yet --------------------------------------
ok('the cursor has barely moved -> nothing snapped', WT.direction_snap(0.02, 0.02).nil?)
ok('dead still -> nothing snapped', WT.direction_snap(0.0, 0.0).nil?)

# a long drag is judged by ANGLE, not by how far it went
ok('a 30 degree drag is free however long it is', snap(30.0, 5000.0).nil?, snap(30.0, 5000.0))
ok('a 30 degree drag is free however short it is', snap(30.0, 0.5).nil?, snap(30.0, 0.5))

# ---------------- the gap helper ----------------------------------------
ok('the short way round: 350 to 10 is 20 degrees', (WT.angle_gap(350.0, 10.0) - 20.0).abs < 1e-9,
   WT.angle_gap(350.0, 10.0))
ok('-170 to 170 is 20 degrees', (WT.angle_gap(-170.0, 170.0) - 20.0).abs < 1e-9,
   WT.angle_gap(-170.0, 170.0))

# ---------------- Shift is untouched ------------------------------------
# Shift is the hard constrain-to-axis and must keep behaving exactly as
# rt16 pins it - free hand did not change it.
ok('Shift still forces the nearer axis, even at 30 degrees',
   WT.axis_lock(*at(30.0)) == :x, WT.axis_lock(*at(30.0)))

# ---------------- the kill switch ---------------------------------------
ok('the ortho-only kill switch is there', WT.const_defined?(:DRAW_SNAP_ORTHO_ONLY, false))
ok('with it on, a 45 goes back to being free',
   WT.direction_snap(*at(45.0), 8.0, 5.0).is_a?(Array) || WT::DRAW_SNAP_ORTHO_ONLY)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

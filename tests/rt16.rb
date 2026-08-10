# encoding: utf-8
# rt16 — exterior wall orientation (2026-08-06). The 2D editor passes each
# wall's DRAWN direction through as-is and exterior = right side of
# start->end, so one wall drawn backwards came out inside-out on the
# user's Mac plan. reversed_loop_segments finds exactly those walls.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
WT = InteriorPro::WallTool

# ---- the user's real Mac plan (6 walls, wall index 2 drawn backwards) ----
mac = [
  [396.5, 238.5, -288.5, 238.5],  # 0 north, west-bound
  [396.5, 34.5, 396.5, 238.5],    # 1 east, north-bound
  [396.5, 34.5, 187.5, 34.5],     # 2 THE FLIPPED ONE (a4a2ed66)
  [187.5, -649.5, 187.5, 34.5],   # 3
  [-288.5, -649.5, 187.5, -649.5],# 4
  [-288.5, 238.5, -288.5, -649.5] # 5
]
ok('the user Mac plan: exactly wall 2 runs against the loop',
   WT.reversed_loop_segments(mac) == [2], WT.reversed_loop_segments(mac))

# fixing it makes the plan clean - and re-running is a no-op (idempotent)
fixed = mac.map.with_index { |g, i| i == 2 ? [g[2], g[3], g[0], g[1]] : g }
ok('after the flip nothing is reversed', WT.reversed_loop_segments(fixed).empty?,
   WT.reversed_loop_segments(fixed))

# ---- a clean CCW square is untouched ------------------------------------
ccw = [[0, 0, 100, 0], [100, 0, 100, 100], [100, 100, 0, 100], [0, 100, 0, 0]]
ok('a clean counter-clockwise loop needs no flips',
   WT.reversed_loop_segments(ccw).empty?, WT.reversed_loop_segments(ccw))

# a whole loop drawn clockwise = every wall inside-out -> all flagged
cw = ccw.map { |g| [g[2], g[3], g[0], g[1]] }
ok('a loop drawn entirely clockwise flags all 4 walls',
   WT.reversed_loop_segments(cw) == [0, 1, 2, 3], WT.reversed_loop_segments(cw))
ok('and flipping them all leaves nothing reversed',
   WT.reversed_loop_segments(cw.map { |g| [g[2], g[3], g[0], g[1]] }).empty?)

# order of the walls in the list must not matter
ok('wall order in the list does not matter',
   WT.reversed_loop_segments([mac[3], mac[2], mac[5], mac[0], mac[4], mac[1]]).length == 1)

# ---- safety: never touch anything that is not one closed loop -----------
ok('an open chain is left alone', WT.reversed_loop_segments(ccw[0..2]).empty?)
ok('a detached wall is left alone',
   WT.reversed_loop_segments(ccw + [[900, 900, 950, 900]]).empty?)
ok('fewer than 3 walls is a quiet no-op', WT.reversed_loop_segments(ccw[0..1]).empty?)
ok('nil / empty is a quiet no-op',
   WT.reversed_loop_segments(nil).empty? && WT.reversed_loop_segments([]).empty?)

# endpoints that meet within the 0.75" tolerance still chain
loose = [[0, 0, 100, 0], [100.3, 0, 100, 100], [100, 100, 0, 100], [0, 100, 0, 0]]
ok('endpoints within tolerance still form the loop',
   WT.reversed_loop_segments(loose).empty?, WT.reversed_loop_segments(loose))

# ---- an L-shaped plan (a wing), one wall backwards ----------------------
lsh = [[0, 0, 300, 0], [300, 0, 300, 120], [300, 120, 120, 120],
       [120, 120, 120, 300], [120, 300, 0, 300], [0, 300, 0, 0]]
ok('a clean L-shape is untouched', WT.reversed_loop_segments(lsh).empty?)
lbad = lsh.map.with_index { |g, i| i == 3 ? [g[2], g[3], g[0], g[1]] : g }
ok('L-shape with wall 3 backwards flags only wall 3',
   WT.reversed_loop_segments(lbad) == [3], WT.reversed_loop_segments(lbad))


# ---- Shift direction lock (2026-08-10) --------------------------------
# The user drew a wall DOWNWARD on the Mac, pressed Shift to hold that
# direction, and the wall snapped sideways. onKeyDown measured the lock
# off @end_point - which snap_to_axis had already flattened onto the
# auto-guessed axis - so once the guess was horizontal, dy was 0 and
# Shift could only ever re-confirm horizontal. The decision now comes
# from the RAW cursor direction.
ok('a mostly-downward run locks the vertical axis', WT.axis_lock(0.4, -300.0) == :y,
   WT.axis_lock(0.4, -300.0))
ok('a mostly-sideways run locks the horizontal axis', WT.axis_lock(-300.0, 2.0) == :x,
   WT.axis_lock(-300.0, 2.0))
ok('an upward run locks vertical too', WT.axis_lock(0.0, 120.0) == :y, WT.axis_lock(0.0, 120.0))
ok('no movement yet -> no lock at all', WT.axis_lock(0.0, 0.0).nil?, WT.axis_lock(0.0, 0.0))
# the exact shape of the bug: the preview was already flattened to y=start
ok('a flattened preview would have said horizontal', WT.axis_lock(-300.0, 0.0) == :x)
ok('...while the real cursor says vertical', WT.axis_lock(-300.0, 900.0) == :y)

# Shift's key code differs per platform: onKeyDown gets 16 on Windows but
# CONSTRAIN_MODIFIER_KEY on the Mac - measured as 131072 on the user's
# SketchUp 2026. The lock worked on the PC and was dead on the Mac.
MAC_SHIFT = 131_072
ok('Windows Shift (16) is recognised', WT.shift_key?(16))
ok('a random key is not Shift', !WT.shift_key?(65))
ok('without the SketchUp constant the Mac code is unknown',
   !WT.shift_key?(MAC_SHIFT))
Object.const_set(:CONSTRAIN_MODIFIER_KEY, MAC_SHIFT) unless Object.const_defined?(:CONSTRAIN_MODIFIER_KEY)
ok('Mac Shift (CONSTRAIN_MODIFIER_KEY = 131072) is recognised too',
   WT.shift_key?(MAC_SHIFT))
ok('and 16 still works alongside it', WT.shift_key?(16))
ok('other keys are still ignored', !WT.shift_key?(27) && !WT.shift_key?(9))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

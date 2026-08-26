# encoding: utf-8
# rt90 - HOW HIGH A ROOF CLIMBS, and the cap on it (2026-08-30).
#
# WHAT THIS IS
# The user's two-storey model: the roof over the LOWER storey dies
# against the upper storey's wall (abut edges, speed 0), so it has no
# ridge of its own there - it just keeps rising until it hits that wall.
# Over his 43 ft wing at 4:12 that was 14 ft above the upper floor, and
# the second storey disappeared behind it. He asked for a limit: "מקסימום
# 4 פוט מעל הרצפה של הקומה העליונה", and for his own Pitch picker to keep
# meaning what it says - the roof is only ever made FLATTER, never
# steeper, and only when it would break the limit.
#
# This is the maths half only. Nothing calls either method yet, so no
# roof anybody has already built can move.
#
# THE CLAIMS PINNED HERE
# 1. REACH IS THE PITCH-FREE HALF of the height. build_hip_geometry!
#    lifts a cell point by slope * (distance from that cell's eave), so
#    the top of the roof is z0 - slope*overhang + slope*reach. Reach is
#    that distance at its worst, and it does not depend on the pitch.
# 2. A PLAIN HIP REACHES HALF ITS SHORT SPAN. 600 square -> 300.
# 3. ABUT EDGES DOUBLE IT. Close two adjacent sides off (speed 0) and the
#    far corner is a full 600 from the two eaves that are left. This is
#    the user's corner, and it is why the roof climbed.
# 4. THE CAP INVERTS THE SAME FORMULA. slope_for_limit gives back exactly
#    the slope whose top lands ON the limit - checked by putting it back
#    through the build formula.
# 5. NOTHING TO CAP -> nil, and the caller leaves the pitch alone.
# 6. THE CAP ONLY EVER FLATTENS. A roof that already fits gets a cap
#    ABOVE its own pitch, so min() keeps the user's choice.
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 1e-6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RM = InteriorPro::RoofManager

SQ = [[0.0, 0.0], [600.0, 0.0], [600.0, 600.0], [0.0, 600.0]]

# ------------------------------------------------ 2. the plain hip
arcs  = RM.straight_skeleton(SQ)
cells = arcs && RM.roof_cells(SQ, arcs)
ok('the plain square gives a skeleton', !arcs.nil?)
ok('...and roof cells', !cells.nil?, cells && cells.length)
reach = RM.cell_reach(SQ, cells)
ok('a plain hip reaches half its span', close(reach, 300.0, 0.5), reach)

# --------------------------------- 3. two adjacent sides walled off
# edges: 0 bottom, 1 right, 2 top, 3 left. Top and left are the upper
# storey's walls, so the roof rises away from BOTH and peaks in that
# corner - exactly the user's plan, where the deep wing is boxed in on
# two sides by the two-storey block.
sp = [1.0, 1.0, 0.0, 0.0]
a2 = RM.straight_skeleton(SQ, sp)
c2 = a2 && RM.roof_cells(SQ, a2, sp)
ok('the abut square gives roof cells', !c2.nil?, c2 && c2.length)
reach2 = RM.cell_reach(SQ, c2)
ok('two abut sides double the reach', close(reach2, 600.0, 0.5), reach2)
ok('...which is strictly worse than the plain hip', reach2 > reach + 1.0,
   [reach2, reach])

# ---------------------------------------------- 1/4. the cap inverts it
Z0    = 106.0     # the lower storey's wall top
OH    = 12.0      # overhang
LIMIT = 154.0     # upper floor 106 + the 4 ft he asked for
cap = RM.slope_for_limit(reach2, OH, Z0, LIMIT)
ok('a reach that climbs gets a cap', !cap.nil?, cap)
top = Z0 - cap * OH + cap * reach2
ok('the capped roof tops out exactly ON the limit', close(top, LIMIT, 1e-9), top)
ok('...and that is flatter than his 4:12', cap < 4.0 / 12.0, cap)
ok('...and it is the same number the formula gives', close(cap, 48.0 / 588.0), cap)

# a shallower roof needs a gentler cut
cap_small = RM.slope_for_limit(200.0, OH, Z0, LIMIT)
ok('a shallow wing may keep a steeper pitch', cap_small > cap, [cap_small, cap])

# ------------------------------------------------ 5. nothing to cap
ok('a reach inside the overhang caps to nil',
   RM.slope_for_limit(12.0, OH, Z0, LIMIT).nil?)
ok('a zero reach caps to nil', RM.slope_for_limit(0.0, OH, Z0, LIMIT).nil?)
ok('no cells, no reach', close(RM.cell_reach(SQ, nil), 0.0))

# ------------------------------------------------ 6. it only flattens
# 240 deep, plain hip -> reach 120. At 4:12 the top is 106 - 4 + 40 = 142,
# well under 154, so the cap must come out ABOVE 4:12 and min() keeps 4:12.
small = [[0.0, 0.0], [600.0, 0.0], [600.0, 240.0], [0.0, 240.0]]
as = RM.straight_skeleton(small)
cs = as && RM.roof_cells(small, as)
rs = RM.cell_reach(small, cs)
ok('the shallow plan reaches half its 240', close(rs, 120.0, 0.5), rs)
cap_s = RM.slope_for_limit(rs, OH, Z0, LIMIT)
ok('a roof that already fits is capped ABOVE its own pitch',
   cap_s > 4.0 / 12.0, cap_s)
ok('...so taking the smaller of the two keeps his pitch',
   close([4.0 / 12.0, cap_s].min, 4.0 / 12.0))

# a limit at the eave itself is honest, not negative
ok('a limit at the eave gives a flat roof, never a negative slope',
   close(RM.slope_for_limit(600.0, OH, Z0, Z0), 0.0))
ok('a limit BELOW the eave gives 0.0 too',
   close(RM.slope_for_limit(600.0, OH, Z0, Z0 - 50.0), 0.0))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

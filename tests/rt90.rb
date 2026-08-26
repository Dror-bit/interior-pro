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
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

# a face that remembers its points, so the finished roof can be measured
module Sketchup
  class Face
    attr_accessor :pts, :pulled, :material, :back_material
    def normal
      a, b, c = @pts[0], @pts[1], @pts[2]
      u = Geom::Vector3d.new(b.x - a.x, b.y - a.y, b.z - a.z)
      v = Geom::Vector3d.new(c.x - a.x, c.y - a.y, c.z - a.z)
      (u * v).normalize
    end
    def pushpull(d); @pulled = d; end
    def reverse!; @pts = @pts.reverse; self; end
  end
  class Entities
    def add_face(pts)
      f = Face.new
      f.pts = pts
      @list << f
      f
    end
  end
end

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

# ================================================================
# 7. THE CAP ON A REAL BUILD (2026-08-30)
# The maths above is only worth anything if build_roof! actually uses
# it. This is the user's own shape in miniature: a lower storey with the
# upper storey sitting on the back of it, so the lower roof dies against
# a crossing wall and has nowhere to stop climbing.
def make_wall(m, id, s, e, level = 1, base = 0.0, height = 96.0)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0])
  w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0])
  w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', height)
  w.set_attribute('InteriorPro', 'base_z', base)
  w.set_attribute('InteriorPro', 'level', level)
  w.set_attribute('InteriorPro', 'wall_category', 'exterior')
  w
end

def two_storey(deep)
  Sketchup.reset_model!
  m = Sketchup.active_model
  make_wall(m, 'cS', [0, 0], [400, 0], 1)
  make_wall(m, 'cE', [400, 0], [400, deep + 100], 1)
  make_wall(m, 'cN', [400, deep + 100], [0, deep + 100], 1)
  make_wall(m, 'cW', [0, deep + 100], [0, 0], 1)
  make_wall(m, 'uS', [0, deep], [400, deep], 2, 96.0)
  make_wall(m, 'uE', [400, deep], [400, deep + 100], 2, 96.0)
  make_wall(m, 'uN', [400, deep + 100], [0, deep + 100], 2, 96.0)
  make_wall(m, 'uW', [0, deep + 100], [0, deep], 2, 96.0)
  m
end

def roof_top(r)
  r.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z).max
end

UPPER_FLOOR = 96.0

# --- a DEEP wing: 4:12 would climb far over the upper floor
two_storey(600)
RM.build_roof!(style: 'hip', pitch: 4, overhang: 12, thickness: 0.0,
               ridge_cap: false)
deep = RM.build_roof!(level: 1, pitch: 4, overhang: 12, thickness: 0.0,
                      ridge_cap: false, abut_headroom: 48)
ok('the deep lower roof builds', !deep.nil?)
top_capped = deep && roof_top(deep)
ok('...and it stops at the 4 ft limit, not wherever 4:12 took it',
   top_capped && top_capped <= UPPER_FLOOR + RM.abut_headroom + 0.5, top_capped)
ok('...but it still rises above its own eave', top_capped && top_capped > 96.5,
   top_capped)
ok('...and the roof carries the limit it was built with',
   deep && (RM.roof_settings(deep)[:abut_headroom].to_f - 48.0).abs < 0.01,
   deep && RM.roof_settings(deep)[:abut_headroom])

# the same build with the cap OFF must go higher - otherwise the two
# assertions above would pass for a roof that was never capped at all
two_storey(600)
RM.build_roof!(style: 'hip', pitch: 4, overhang: 12, thickness: 0.0,
               ridge_cap: false, abut_headroom: 0)
loose = RM.build_roof!(level: 1, pitch: 4, overhang: 12, thickness: 0.0,
                       ridge_cap: false, abut_headroom: 0)
top_loose = loose && roof_top(loose)
ok('with the cap off the very same roof climbs higher',
   top_loose && top_capped && top_loose > top_capped + 10.0,
   [top_loose, top_capped])
ok('...far over the upper floor, which is the bug he photographed',
   top_loose && top_loose > UPPER_FLOOR + 60.0, top_loose)
ok('...and 0 is what turned it off, through the setting',
   loose && RM.roof_settings(loose)[:abut_headroom].to_f.zero?,
   loose && RM.roof_settings(loose)[:abut_headroom])

# --- a SHALLOW wing: 4:12 already fits, so nothing may move
two_storey(120)
RM.build_roof!(style: 'hip', pitch: 4, overhang: 12, thickness: 0.0,
               ridge_cap: false, abut_headroom: 48)
shal = RM.build_roof!(level: 1, pitch: 4, overhang: 12, thickness: 0.0,
                      ridge_cap: false, abut_headroom: 48)
top_shal = shal && roof_top(shal)
ok('a shallow wing builds', !shal.nil?)
ok('...and keeps the pitch he picked, untouched',
   top_shal && top_shal < UPPER_FLOOR + RM.abut_headroom - 1.0, top_shal)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

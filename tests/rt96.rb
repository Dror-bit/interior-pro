# encoding: utf-8
# rt96 - A HALF-STACKED UPPER WALL STILL CUTS THE LOWER ROOF (2026-09-01).
#
# WHAT THIS IS
# The user's own two-storey model, wall for wall (roof_levels_report,
# 2026-09-01). The lower storey is an L: a big body plus a front wing.
# The upper storey stands on the big body only, so the roof over the
# lower storey must cover THE WING ONLY.
#
# WHAT WENT WRONG
# exposed_polygon decided which upper walls cross the storey by looking
# at each wall's MIDDLE POINT. The upper south wall is half and half: it
# stands on the lower wall for its eastern 377", and flies over the open
# wing for its western 249". Its middle lands on the stacked half, so
# the wall was written off as "just stacked", no divider was found, the
# whole thing bailed to nil - and the roof was built over the ENTIRE
# lower storey, upper house and all (his photo, 2026-09-01).
#
# THE CLAIM PINNED HERE
# A wall counts as a divider when ANY REAL RUN of it crosses the storey
# clear of the boundary, not when its midpoint happens to. The exposed
# loop is then the wing, and the upper wall is the abut edge.
#
# Against the old code this suite fails on the first exposed_polygon
# call: it returns nil (verified at birth, 2026-09-01).
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

# The same Face the roof suites use (rt93): the stub's plain one has no
# normal worth reading and no pushpull, and build_roof! walks both.
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
def close(a, b, tol = 0.6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RM = InteriorPro::RoofManager

def wall(m, id, lvl, s, e, bz)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => 'bottom-center', 'height' => lvl == 1 ? 106.0 : 96.0,
    'base_z' => bz, 'level' => lvl, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

Sketchup.reset_model!
m = Sketchup.active_model
# level 1 - the L: big body y 920.5..1523, wing x -60..184.5, y 713.5..920.5
wall(m, '497e882d', 1, [566.5, 1523.0], [-60.0, 1522.9], 0.0)
wall(m, 'ba88582f', 1, [566.5, 920.5], [566.5, 1523.0], 0.0)
wall(m, '843776c1', 1, [184.5, 920.5], [566.5, 920.5], 0.0)   # the stacked half
wall(m, 'a3ddc2b0', 1, [184.5, 713.5], [184.5, 920.5], 0.0)
wall(m, '006d5644', 1, [-60.0, 713.5], [184.5, 713.5], 0.0)
wall(m, 'c37ede43', 1, [-60.0, 1522.9], [-60.0, 713.5], 0.0)
# level 2 - the big rectangle, sitting on the body
wall(m, 'd2d2f7d6', 2, [566.5, 920.5], [566.5, 1523.0], 106.0)
wall(m, '2795ffef', 2, [566.5, 1523.0], [-60.0, 1522.9], 106.0)
wall(m, '83462982', 2, [-60.0, 1522.9], [-60.0, 920.5], 106.0)
wall(m, '534649af', 2, [-60.0, 920.5], [566.5, 920.5], 106.0) # HALF AND HALF

low = RM.walls_of(1)
up  = InteriorPro::LevelManager.all_walls.select do |w|
  w.get_attribute('InteriorPro', 'level').to_i > 1
end
ok('six walls downstairs, four up', low.length == 6 && up.length == 4,
   [low.length, up.length])

# ---- the wall itself ---------------------------------------------------
base = RM.eave_polygon(low, 0.0)
ok('the lower storey is an L', !base.nil? && base[:pts].length == 6,
   base && base[:pts].length)
half = up.find { |w| w.get_attribute('InteriorPro', 'id') == '534649af' }
stacked = up.find { |w| w.get_attribute('InteriorPro', 'id') == 'd2d2f7d6' }
ok('the half-and-half wall counts as a divider',
   RM.crosses_storey?(base[:pts], half))
ok('a wall that only stands on the one below does NOT',
   !RM.crosses_storey?(base[:pts], stacked))

# ---- the exposed loop --------------------------------------------------
ep = RM.exposed_polygon(low, up, 12.0)
ok('the exposed part is found at all', !ep.nil?)
if ep
  xs = ep[:pts].map { |p| p[0] }
  ys = ep[:pts].map { |p| p[1] }
  ok('it is the WING, not the whole storey', ep[:pts].length == 4,
     ep[:pts].length)
  ok('...its west side is the wing wall plus the overhang',
     close(xs.min, -60.0 - 12.0 - 2.5), xs.min)
  ok('...its east side is the wing wall plus the overhang',
     close(xs.max, 184.5 + 12.0 + 2.5), xs.max)
  ok('...its front is the south wall plus the overhang',
     close(ys.min, 713.5 - 12.0 - 2.5), ys.min)
  # THE ABUT EDGE LANDS ON THE UPPER WALL'S FACE (2026-09-01). It used
  # to stop an inch inside it, and the user could see the shingles
  # disappear into the stucco. The wall's centre is 920.5 and it is 5"
  # thick, so the face the roof meets is 918.0 - not 919.0, and not past.
  ok('...and it stops ON the upper wall face, not inside it',
     close(ys.max, 918.0, 0.2), ys.max)
  ok('the upper wall is the abut edge', ep[:abut_ids] == ['534649af'],
     ep[:abut_ids])
  ok('the roof over the wing is far smaller than the whole storey',
     (xs.max - xs.min) < 300.0 && (ys.max - ys.min) < 260.0,
     [xs.max - xs.min, ys.max - ys.min])
end

# ---- NOTHING POKES OUT OF THE UPPER WALL ------------------------------
# The user measured 7/8" of board standing proud of the stucco: the metal
# edge was wrapping the abut corner as if a rake drip waited out there.
# Build the real roof and check every point of it.
roof = RM.build_roof!(style: 'hip', pitch: 4, overhang: 12, level: 1)
ok('the roof over the wing builds', !roof.nil?)
if roof
  pts = []
  walk = lambda do |ents|
    ents.to_a.each do |e|
      if e.is_a?(Sketchup::Face)
        pts += Array(e.pts)
      elsif e.respond_to?(:entities)
        walk.call(e.entities)
      end
    end
  end
  walk.call(roof.entities)
  ymax = pts.map(&:y).max
  # 918.0 is the wall face. All that may stand proud of it now is the
  # metal edge's own tenth of an inch; it was 7/8" before the wrap was
  # taken off the abut corners.
  ok('no board stands proud of the upper wall face',
     ymax <= 918.0 + InteriorPro::RoofManager::DRIP_THICK + 0.01, ymax)
end

# ---- nothing changed for a storey with nothing above it ---------------
ok('with no upper walls at all there is nothing to cut',
   RM.exposed_polygon(low, [], 12.0).nil?)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

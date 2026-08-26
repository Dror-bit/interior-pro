# encoding: utf-8
# rt91 - THE SHED ROOF: one plane, one eave (2026-08-26).
#
# WHAT THIS IS
# The user asked for a single-slope roof. It is NOT a new geometry
# engine: a shed is the gable machinery with the marks INVERTED. Every
# edge but the low one runs at speed 0 and is cut vertical, so the
# straight skeleton collapses to ONE cell and the roof is one plane -
# and the rakes, the gable wall tops and fascia-on-the-eave-only all
# come out of the code that was already there.
#
# THE CLAIMS PINNED HERE
# 1. ONE CELL, FULL REACH. A hip on a rectangle reaches half its short
#    span; a shed reaches the WHOLE run, because there is no second eave
#    coming the other way to meet it. This is the number the user saw in
#    the section drawing: 914" of run, not 457".
# 2. THE SHED CLIMBS HIGHER THAN THE HIP at the same pitch - which is
#    exactly why he must pick a low pitch on a long plan.
# 3. THE LOW EDGE DEFAULTS TO THE LONGEST EDGE, so the roof runs across
#    the short way and stays as low as it can with nothing marked.
# 4. A MARKED WALL WINS over that default - this is what his button does.
# 5. HIP AND GABLE ARE UNTOUCHED. Same footprint, same pitch, same tops
#    as before the shed branch existed.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

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
def close(a, b, tol = 1.0)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RM = InteriorPro::RoofManager

RUN  = 914.0    # his level-1 block, the short way
DEEP = 1069.0   # ...and the long way
POLY = [[0.0, 0.0], [RUN, 0.0], [RUN, DEEP], [0.0, DEEP]]

# ---------------------------------------- 1. one cell, the whole run
sp_shed = [0.0, 0.0, 0.0, 1.0]   # only edge 3 (the left, 1069 long) slopes
a_shed  = RM.straight_skeleton(POLY, sp_shed)
c_shed  = a_shed && RM.roof_cells(POLY, a_shed, sp_shed)
ok('a shed footprint gives a skeleton', !a_shed.nil?)
ok('...and exactly ONE roof cell', c_shed && c_shed.length == 1,
   c_shed && c_shed.length)
reach_shed = RM.cell_reach(POLY, c_shed)
ok('...that reaches the WHOLE run, not half of it',
   close(reach_shed, RUN, 0.5), reach_shed)

a_hip  = RM.straight_skeleton(POLY)
c_hip  = a_hip && RM.roof_cells(POLY, a_hip)
reach_hip = RM.cell_reach(POLY, c_hip)
ok('a hip on the same plan reaches half its short span',
   close(reach_hip, RUN / 2.0, 0.5), reach_hip)
ok('...so the shed reaches twice as far', reach_shed > reach_hip * 1.9,
   [reach_shed, reach_hip])

# ---------------------------------------- 3/4. which edge is the low one
ok('with nothing marked the low edge is the LONGEST edge',
   RM.shed_low_edge(POLY, %w[S E N W], []) == 1,
   RM.shed_low_edge(POLY, %w[S E N W], []))
ok('...and a marked wall wins over that default',
   RM.shed_low_edge(POLY, %w[S E N W], ['S']) == 0,
   RM.shed_low_edge(POLY, %w[S E N W], ['S']))
ok('a mark on a wall that is not in this loop falls back to longest',
   RM.shed_low_edge(POLY, %w[S E N W], ['ZZ']) == 1,
   RM.shed_low_edge(POLY, %w[S E N W], ['ZZ']))

# 6. AN ABUT EDGE CAN NEVER BE THE EAVE. A line buried in the wall of
#    the storey above is not a place a roof can drain to, and if it were
#    picked every edge would run at speed 0 and the skeleton would have
#    nothing left to build from.
ok('the longest edge is skipped when it abuts the storey above',
   RM.shed_low_edge(POLY, %w[S E N W], [], ['E']) == 3,
   RM.shed_low_edge(POLY, %w[S E N W], [], ['E']))
ok('...and a MARK on an abut wall is skipped too',
   RM.shed_low_edge(POLY, %w[S E N W], ['E'], ['E']) == 3,
   RM.shed_low_edge(POLY, %w[S E N W], ['E'], ['E']))
ok('...but if every wall abuts, we still name one rather than crash',
   !RM.shed_low_edge(POLY, %w[S E N W], [], %w[S E N W]).nil?)

# ================================================================
# 2/5. A REAL BUILD
def make_wall(m, id, s, e, level = 1, base = 0.0, height = 106.0)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 6.0,
    'anchor' => 'bottom-center', 'height' => height, 'base_z' => base,
    'level' => level, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

def block
  Sketchup.reset_model!
  m = Sketchup.active_model
  make_wall(m, 'S', [0, 0], [RUN, 0])
  make_wall(m, 'E', [RUN, 0], [RUN, DEEP])
  make_wall(m, 'N', [RUN, DEEP], [0, DEEP])
  make_wall(m, 'W', [0, DEEP], [0, 0])
  m
end

def top_of(r)
  r && r.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z).max
end

block
shed4 = RM.build_roof!(style: 'shed', pitch: 4, overhang: 12, ridge_cap: false)
top_shed4 = top_of(shed4)
ok('a shed roof builds', !shed4.nil?)

block
hip4 = RM.build_roof!(style: 'hip', pitch: 4, overhang: 12, ridge_cap: false)
top_hip4 = top_of(hip4)
ok('a hip roof still builds', !hip4.nil?)
ok('THE SHED CLIMBS HIGHER THAN THE HIP at the same pitch',
   top_shed4 && top_hip4 && top_shed4 > top_hip4 + 100.0,
   [top_shed4, top_hip4])

# the number he was shown in the section: 914 of run at 4:12 over a
# 106 wall, less the overhang drop = 406.7 before the fascia board.
ok('...and lands where the drawing said it would',
   close(top_shed4, 106.0 - (4.0 / 12) * 12 + (4.0 / 12) * RUN, 12.0),
   top_shed4)

block
shed1 = RM.build_roof!(style: 'shed', pitch: 1, overhang: 12, ridge_cap: false)
top_shed1 = top_of(shed1)
ok('a gentle shed is far lower than a steep one',
   top_shed1 && top_shed4 && top_shed1 < top_shed4 - 200.0,
   [top_shed1, top_shed4])
ok('...and 1:12 over this run stays about 15 ft',
   close(top_shed1, 106.0 - (1.0 / 12) * 12 + (1.0 / 12) * RUN, 12.0),
   top_shed1)

# ---------------------------------------- 5. nothing else moved
block
gab4 = RM.build_roof!(style: 'gable', pitch: 4, overhang: 12, ridge_cap: false)
top_gab4 = top_of(gab4)
ok('a gable roof still builds', !gab4.nil?)
ok('...and a hip and a gable on a rectangle still top out together',
   close(top_gab4, top_hip4, 0.5), [top_gab4, top_hip4])
ok('...both well under the shed', top_gab4 && top_shed4 && top_gab4 < top_shed4,
   [top_gab4, top_shed4])

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

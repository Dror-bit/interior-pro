# encoding: utf-8
# rt92 - A RAISED WALL STOPS WHERE ITS WALL STOPS (2026-08-26).
#
# WHAT THIS IS
# The poly edge a gable wall is built along comes from the EAVE polygon -
# the wall centrelines pushed out by the overhang - so at every corner it
# runs past the wall it belongs to, by the overhang. On a gable nobody
# ever saw it: the triangle has no height down at the corners, so the
# stub is a sliver at the eave. On a SHED the far end of a side wall is
# at FULL height, and the stub hangs in the air past the corner. The user
# photographed exactly that: a white board floating past the high corner
# with nothing underneath it (2026-08-26).
#
# THE CLAIMS PINNED HERE
# 1. EVERY RAISED WALL STAYS INSIDE ITS OWN WALL, in plan. This is the
#    photograph, turned into a number.
# 2. ...AND STILL REACHES BOTH ENDS of it - the fix must not eat the
#    corner it was meant to close.
# 3. THE HIGH WALL IS FULL HEIGHT and the two side walls rake, which is
#    what makes the stub visible on a shed in the first place.
# 4. wall_span_on_edge is PURE and clamps to the edge.
# 5. clip_profile keeps the middle, interpolates the two new ends, and
#    gives back nothing when the window is empty.
# 6. AN OVER-FRAMED ROOF IS NOT CLIPPED. There a gable wall is MEANT to
#    run past its own wall, out to where the wing roof meets the main one
#    (rt17, rt86). Guarded here so the shed fix can never creep into it.
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

# THE RAISED HEEL IS OFF IN HERE (2026-09-06). Every z in this suite was
# measured when the roof's underside met the wall top exactly, and the
# eave tail fell slope x overhang BELOW it. He asked for that tail to be
# lifted level with the wall corner instead, which moves every roof up by
# that same amount - so the whole roof, not this suite's subject, would be
# under test. rt118 pins the heel itself; here it stays off, exactly the
# way rt85 already switches off the abut cap.
module InteriorPro
  module RoofManager
    def self.heel_lift(_overhang, _slope, _drop = 0.0)
      0.0
    end
  end
end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.05)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RM = InteriorPro::RoofManager

# ---------------------------------------------- 4. wall_span_on_edge
# a 200-long wall on an edge that runs 24 longer (12 of overhang each end)
FAKE = Struct.new(:atts) do
  def valid?; true; end
  def transformation; Geom::Transformation.new; end
  def get_attribute(_d, k, dflt = nil); atts.fetch(k, dflt); end
end
w = FAKE.new({ 'start_x' => 0.0, 'start_y' => 0.0, 'end_x' => 200.0,
               'end_y' => 0.0, 'thickness' => 6.0, 'anchor' => 'bottom-center' })
lo, hi = RM.wall_span_on_edge(w, [-12.0, -12.0], [1.0, 0.0], 224.0, 6.0)
ok('the span starts at the wall, not at the eave corner', close(lo, 9.0), lo)
ok('...and ends at the far end of the wall, not 12 past it', close(hi, 215.0), hi)
ok('...leaving the overhang stub OUT at both ends',
   lo > 0.5 && hi < 223.5, [lo, hi])
ok('a wall that cannot be measured gives back the whole edge',
   RM.wall_span_on_edge(nil, [0.0, 0.0], [1.0, 0.0], 224.0, 6.0) == [0.0, 224.0])

# ------------------------------- 4b. the BOX wins over the centreline
# His walls are drawn along their OUTER face, not down the middle, so the
# centreline already reaches the corner and padding it by half a
# thickness pushed 2.5 in. past the building - the stub he photographed
# coming out through the soffit (2026-08-26). The wall's own bounding box
# carries no assumption about how it was drawn.
BB = Struct.new(:min, :max)
BOXED = Struct.new(:atts, :bb) do
  def valid?; true; end
  def bounds; bb; end
  def transformation; Geom::Transformation.new; end
  def get_attribute(_d, k, dflt = nil); atts.fetch(k, dflt); end
end
# straight from his report: the high wall, drawn corner to OUTER corner
outer = BOXED.new({ 'start_x' => 1185.32, 'start_y' => 154.32,
                    'end_x' => 1347.36, 'end_y' => 154.32,
                    'thickness' => 5.0, 'anchor' => 'bottom-center' },
                  BB.new(Geom::Point3d.new(1185.32, 151.82, 106.0),
                         Geom::Point3d.new(1347.36, 156.82, 208.0)))
A = [1173.32, 154.32] # the eave corner, 12 of overhang before the wall
lo2, hi2 = RM.wall_span_on_edge(outer, A, [1.0, 0.0], 186.04, 5.0)
ok('the box stops exactly at the wall, with no pad',
   close(lo2, 12.0, 0.01) && close(hi2, 174.04, 0.01), [lo2, hi2])
ok('...and the padded centreline would have overshot by 2.5 each way',
   close(RM.wall_centre_span(outer, A, [1.0, 0.0], 5.0)[0], 9.5, 0.01) &&
   close(RM.wall_centre_span(outer, A, [1.0, 0.0], 5.0)[1], 176.54, 0.01),
   RM.wall_centre_span(outer, A, [1.0, 0.0], 5.0))
ok('a wall with nothing to measure has no box span',
   RM.wall_bounds_span(w, [0.0, 0.0], [1.0, 0.0]).nil?)
ok('...so the padded centreline still answers for it',
   !RM.wall_centre_span(w, [0.0, 0.0], [1.0, 0.0], 6.0).nil?)

# ---------------------------------------------------- 5. clip_profile
prof = [[0.0, 100.0], [100.0, 200.0]]
c = RM.clip_profile(prof, 25.0, 75.0)
ok('clip_profile cuts to the window', c.length == 2, c)
ok('...and interpolates the new low end', close(c.first[1], 125.0), c.first)
ok('...and the new high end', close(c.last[1], 175.0), c.last)
ok('a window wider than the profile changes nothing',
   RM.clip_profile(prof, -50.0, 500.0) == prof)
ok('an empty window gives nothing back', RM.clip_profile(prof, 60.0, 60.2).empty?)
ok('a window past the end gives nothing back', RM.clip_profile(prof, 300.0, 400.0).empty?)
mid = [[0.0, 100.0], [50.0, 150.0], [100.0, 100.0]]
ok('...and a middle point inside the window survives',
   RM.clip_profile(mid, 10.0, 90.0).length == 3,
   RM.clip_profile(mid, 10.0, 90.0))

# ---------------- 7. THE PROFILE IS READ WHERE THE WALL STANDS
# The wall is drawn one overhang INBOARD of the roof edge. The old code
# copied the profile off the EDGE and drew it at the WALL - the same
# height only when stepping inboard runs square to the fall. That is true
# of a gable end, which is why it held for two years, and false of a
# SHED's high wall, where stepping inboard runs straight DOWNHILL: the
# roof there is slope*overhang lower, and the wall stood that far proud
# of the shingles (the user's photo, 2026-08-26). Nothing is copied now -
# the profile is sampled off the roof's own underside along the wall's
# own line.
SQ = [[0.0, 0.0], [400.0, 0.0], [400.0, 300.0], [0.0, 300.0]]
ONE = [{ pts: SQ, eave: 0 }]        # one plane, draining to edge 0
SLOPE = 1.0 / 3.0                   # 4:12
Z0 = 102.0
OH = 12.0

ok('the roof underside starts one overhang-drop below the wall top',
   close(RM.roof_under_z(SQ, ONE, Z0, SLOPE, OH, 200.0, 0.0), 98.0, 0.001),
   RM.roof_under_z(SQ, ONE, Z0, SLOPE, OH, 200.0, 0.0))
ok('...and climbs at the pitch away from the eave',
   close(RM.roof_under_z(SQ, ONE, Z0, SLOPE, OH, 200.0, 300.0), 198.0, 0.001),
   RM.roof_under_z(SQ, ONE, Z0, SLOPE, OH, 200.0, 300.0))
ok('...so 12 in. back from the far edge it is 4 in. LOWER',
   close(RM.roof_under_z(SQ, ONE, Z0, SLOPE, OH, 200.0, 288.0), 194.0, 0.001),
   RM.roof_under_z(SQ, ONE, Z0, SLOPE, OH, 200.0, 288.0))
ok('no cells, no surface', RM.roof_under_z(SQ, nil, Z0, SLOPE, OH, 0.0, 0.0).nil?)

# the HIGH wall (edge 2): its line is the flat one at y = 288
hp = RM.wall_line_profile(SQ, 2, ONE, Z0, SLOPE, OH, 0.0, 400.0)
ok('the high wall gets a profile', !hp.nil? && hp.length >= 2, hp && hp.length)
ok('...flat along its whole length', hp && hp.map { |_t, z| z }.minmax
   .then { |lo3, hi3| close(lo3, hi3, 0.001) }, hp && hp.map { |_t, z| z }.minmax)
ok('...at the height of the roof over the WALL, not over the edge',
   hp && close(hp.first[1], 194.0, 0.001), hp && hp.first[1])
ok('...which is exactly slope * overhang below the old copied value',
   hp && close(198.0 - hp.first[1], SLOPE * OH, 0.001), hp && hp.first[1])

# a RAKE (edge 1): stepping inboard is square to the fall, so it is
# unchanged - this is the gable case, and it must not have moved.
rp = RM.wall_line_profile(SQ, 1, ONE, Z0, SLOPE, OH, 0.0, 300.0)
ok('a rake gets a profile', !rp.nil? && rp.length >= 2, rp && rp.length)
ok('...that starts down at the eave', rp && close(rp.first[1], 98.0, 0.001),
   rp && rp.first[1])
ok('...and climbs to the far end, exactly as the roof edge does',
   rp && close(rp.last[1], 198.0, 0.001), rp && rp.last[1])
ok('...so stepping in off a rake moved it not at all',
   rp && close(rp.last[1] - rp.first[1], 100.0, 0.001))

ok('a window shorter than half an inch has no profile',
   RM.wall_line_profile(SQ, 2, ONE, Z0, SLOPE, OH, 10.0, 10.2).nil?)

# a plane samples into a run of collinear points, and a prism does not
# need them
ok('simplify_profile drops the collinear middle',
   RM.simplify_profile([[0.0, 0.0], [5.0, 5.0], [10.0, 10.0]]).length == 2,
   RM.simplify_profile([[0.0, 0.0], [5.0, 5.0], [10.0, 10.0]]))
ok('...and keeps a real bend',
   RM.simplify_profile([[0.0, 0.0], [5.0, 9.0], [10.0, 10.0]]).length == 3)
ok('...and leaves two points alone',
   RM.simplify_profile([[0.0, 0.0], [10.0, 10.0]]).length == 2)

# ================================================================
# 1/2/3. THE REAL BUILD - the user's own rectangle
def make_wall(m, id, s, e)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => 'bottom-center', 'height' => 102.0, 'base_z' => 0.0,
    'level' => 1, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

# centrelines straight off his model (shed_edge_report, 2026-08-26)
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'D', [-218.5, 2.5], [-2.5, 2.5])       # south - the low eave
make_wall(m, 'A', [-2.5, 2.5], [-2.5, 208.7])       # east  - rakes
make_wall(m, 'B', [-2.5, 208.7], [-218.5, 208.7])   # north - the high wall
make_wall(m, 'C', [-218.5, 208.7], [-218.5, 2.5])   # west  - rakes
m.set_attribute('InteriorPro', 'roof_shed_wall_ids', ['D'])

roof = RM.build_roof!(style: 'shed', pitch: 4, overhang: 12, thickness: 0.5,
                      ridge_cap: true)
ok('the shed builds on his footprint', !roof.nil?)

tops = roof.entities.to_a.reject { |e| e.is_a?(Sketchup::Face) }
ok('three walls are raised to meet it - the two rakes and the high end',
   tops.length == 3, tops.length)

def box(g)
  p = g.entities.grep(Sketchup::Face).flat_map(&:pts)
  return nil if p.empty?
  { x: [p.map(&:x).min, p.map(&:x).max], y: [p.map(&:y).min, p.map(&:y).max],
    z: [p.map(&:z).min, p.map(&:z).max] }
end
boxes = tops.map { |g| box(g) }.compact
ok('...and every one of them has geometry', boxes.length == 3, boxes.length)

# the building itself, outer faces: x -221..0, y 0..211.2
XLO, XHI, YLO, YHI = -221.0, 0.0, 0.0, 211.2
TOL = 0.05
boxes.each_with_index do |bx, i|
  ok("raised wall #{i} stays inside the building in x",
     bx[:x][0] >= XLO - TOL && bx[:x][1] <= XHI + TOL, bx[:x])
  ok("raised wall #{i} stays inside the building in y",
     bx[:y][0] >= YLO - TOL && bx[:y][1] <= YHI + TOL, bx[:y])
  ok("raised wall #{i} starts at the wall top, not in the air",
     close(bx[:z][0], 102.0, 0.6), bx[:z])
end

# 2. it still REACHES both ends - a fix that ate the corner would pass
#    every test above and leave a hole.
# MITRED since later the same day (2026-08-26): the butt rule this block
# first pinned ("give up the START corner to the neighbour") left a
# vertical seam on the FLAT of the wall, one thickness from the corner -
# the user's second round of red arrows. Now every wall's OUTER face
# runs all the way to BOTH corners, the INNER face stops a
# neighbour-thickness short, and the end is cut on the diagonal - so the
# seam lies on the corner arris. The mitred solid carries real thickness
# even in the stub (it is built face by face, not push-pulled), so the
# rakes are 5 in. wide boxes here, not planes.
TH = 5.0
side = boxes.select { |bx| (bx[:x][1] - bx[:x][0]).abs < 40.0 } # the two rakes
high = boxes.reject { |bx| (bx[:x][1] - bx[:x][0]).abs < 40.0 }
ok('two of them are the rakes', side.length == 2, side.length)
ok('...and one is the high wall', high.length == 1, high.length)
ok('...and a rake now has real thickness, even in the stub',
   side.all? { |bx| close(bx[:x][1] - bx[:x][0], TH, 0.1) },
   side.map { |bx| bx[:x][1] - bx[:x][0] })
side.each_with_index do |bx, i|
  ok("rake #{i} reaches the high corner - no butt gap",
     (bx[:y][1] - YHI).abs < 0.6, bx[:y])
end
hb = high.first
ok('the high wall reaches BOTH corners on its outer face',
   hb && (hb[:x][0] - XLO).abs < 0.6 && (hb[:x][1] - XHI).abs < 0.6,
   hb && hb[:x])

# ...and the mitre must not put two walls on the same piece of plan.
# Each footprint is a convex trapezoid (outer face long, inner face
# short); hull + separating-axis says how deeply any two interpenetrate.
# Touching on the shared diagonal is 0 - that IS the mitre.
def hull(pts)
  ps = pts.map { |p| [p.x.round(4), p.y.round(4)] }.uniq.sort
  return ps if ps.length < 3
  cr = ->(o, a2, b2) { (a2[0] - o[0]) * (b2[1] - o[1]) - (a2[1] - o[1]) * (b2[0] - o[0]) }
  lower = []
  ps.each do |p|
    lower.pop while lower.length >= 2 && cr.call(lower[-2], lower[-1], p) <= 0
    lower << p
  end
  upper = []
  ps.reverse.each do |p|
    upper.pop while upper.length >= 2 && cr.call(upper[-2], upper[-1], p) <= 0
    upper << p
  end
  lower[0...-1] + upper[0...-1]
end

def overlap_depth(h1, h2)
  axes = (h1.zip(h1.rotate) + h2.zip(h2.rotate))
         .map { |a2, b2| [-(b2[1] - a2[1]), b2[0] - a2[0]] }
  best = 1.0e9
  axes.each do |ax|
    l = Math.sqrt(ax[0]**2 + ax[1]**2)
    next if l < 1.0e-9
    nx = ax[0] / l
    ny = ax[1] / l
    p1 = h1.map { |p| nx * p[0] + ny * p[1] }.minmax
    p2 = h2.map { |p| nx * p[0] + ny * p[1] }.minmax
    ov = [p1[1], p2[1]].min - [p1[0], p2[0]].max
    return 0.0 if ov <= 1.0e-6
    best = [best, ov].min
  end
  best
end

hulls = tops.map { |g| hull(g.entities.grep(Sketchup::Face).flat_map(&:pts)) }
clashes = hulls.combination(2).map { |h1, h2| overlap_depth(h1, h2) }
               .select { |v| v > 0.05 }
ok('no two raised walls overlap in plan', clashes.empty?, clashes)

# 3. the shape that made the stub visible: the high wall is a full-height
#    band, the rakes climb to just under it.
# on the real build: all three now top out on the SAME roof underside,
# because all three stand on the wall line. Before the drop the high one
# was a full slope*overhang above the other two - the bar.
ok('every raised wall tops out on the same roof underside',
   (hb[:z][1] - side.map { |bx| bx[:z][1] }.max).abs < 0.05,
   [hb[:z][1], side.map { |bx| bx[:z][1] }])
ok('...and none of them stands above where the roof deck starts',
   hb[:z][1] < 176.0, hb[:z][1])

ok('the high wall is at least as tall as the rakes',
   hb[:z][1] > side.map { |bx| bx[:z][1] }.max - 0.01,
   [hb[:z][1], side.map { |bx| bx[:z][1] }])
ok('...and it is a proper band, not a sliver',
   hb[:z][1] - hb[:z][0] > 60.0, hb[:z])

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

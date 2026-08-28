# encoding: utf-8
# rt93 - SHED CORNERS ARE MITRED, THE HIGH WALL IS BEVELLED (2026-08-26).
#
# WHAT THIS IS
# Round two of the shed corner. rt92's first fix gave every raised wall's
# START corner to its neighbour - a BUTT joint. The geometry was correct
# (no overlap, no gap) but the seam stood as a vertical line on the FLAT
# of the wall, one thickness from the corner: the user's red arrows,
# second photo set. He asked for corners like the walls below have.
#
# THE CLAIMS PINNED HERE
# 1. THE MITRE. Each raised wall's OUTER face runs to the corner; its
#    INNER face stops one neighbour-thickness short; the end is cut on
#    the diagonal between the two. Both walls of a corner cut onto the
#    SAME diagonal - they share the outer and the inner corner point -
#    so the only visible edges sit on the corner arris itself.
# 2. THE BEVEL. The top is sampled off the roof underside on the outer
#    AND the inner line. The high wall stands square to the fall, so its
#    top drops by slope*thickness across itself and tucks UNDER the
#    deck - it used to be flat-topped and proud of the shingles.
# 3. A RAKE IS NOT TILTED. A rake runs parallel to the fall - outer and
#    inner top lines are level with each other. The bevel must show up
#    only where the roof really drops across the wall.
#
# Every claim here FAILS against the butt-joint code (verified once at
# birth): the old prism had no inner face in the stub at all, started
# one thickness late at a shared corner, and had a flat top.
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

def make_wall(m, id, s, e)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => 'bottom-center', 'height' => 102.0, 'base_z' => 0.0,
    'level' => 1, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

# the user's own rectangle (shed_edge_report, 2026-08-26)
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'D', [-218.5, 2.5], [-2.5, 2.5])       # south - the low eave
make_wall(m, 'A', [-2.5, 2.5], [-2.5, 208.7])       # east  - rakes
make_wall(m, 'B', [-2.5, 208.7], [-218.5, 208.7])   # north - the high wall
make_wall(m, 'C', [-218.5, 208.7], [-218.5, 2.5])   # west  - rakes
m.set_attribute('InteriorPro', 'roof_shed_wall_ids', ['D'])

SLOPE = 4.0 / 12.0
TH = 5.0
roof = RM.build_roof!(style: 'shed', pitch: 4, overhang: 12, thickness: 0.5,
                      ridge_cap: true)
ok('the shed builds', !roof.nil?)

tops = roof.entities.to_a.reject { |e| e.is_a?(Sketchup::Face) }
ok('three raised walls', tops.length == 3, tops.length)

def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map(&:pts)
end
def bx(g)
  p = pts_of(g)
  { x: [p.map(&:x).min, p.map(&:x).max], y: [p.map(&:y).min, p.map(&:y).max],
    z: [p.map(&:z).min, p.map(&:z).max] }
end

# outer faces of the building: x -221..0, y 0..211.2
XLO, XHI, YHI = -221.0, 0.0, 211.2
boxes = tops.map { |g| [g, bx(g)] }
high = boxes.find { |_g, b| (b[:x][1] - b[:x][0]).abs > 40.0 }
rakes = boxes.select { |_g, b| (b[:x][1] - b[:x][0]).abs <= 40.0 }
ok('one high wall, two rakes', !high.nil? && rakes.length == 2)

hg, hb = high

# ---- 1. THE MITRE ------------------------------------------------------
ok('the high wall OUTER face reaches the west corner',
   close(hb[:x][0], XLO, 0.6), hb[:x])
ok('...and the east corner', close(hb[:x][1], XHI, 0.6), hb[:x])
# its inner face (y = YHI - TH) stops one rake-thickness short each side
hin = pts_of(hg).select { |p| close(p.y, YHI - TH, 0.1) }
ok('the high wall HAS an inner face', hin.length >= 3, hin.length)
ok('...pulled back one neighbour-thickness at the west end',
   close(hin.map(&:x).min, XLO + TH, 0.6), hin.map(&:x).min)
ok('...and at the east end',
   close(hin.map(&:x).max, XHI - TH, 0.6), hin.map(&:x).max)
# both walls of a corner cut onto the SAME diagonal: they share the
# outer corner point and the inner corner point (in plan)
def has_pt(g, x, y)
  pts_of(g).any? { |p| (p.x - x).abs < 0.6 && (p.y - y).abs < 0.6 }
end
rakes.each do |rg, rb2|
  cx = rb2[:x][0] > -100.0 ? XHI : XLO       # which corner this rake owns
  ix = cx > -100.0 ? XHI - TH : XLO + TH
  ok("rake at x~#{cx.round} shares the OUTER corner point with the high wall",
     has_pt(rg, cx, YHI) && has_pt(hg, cx, YHI), cx)
  ok('...and the INNER corner point - one shared diagonal, one seam',
     has_pt(rg, ix, YHI - TH) && has_pt(hg, ix, YHI - TH), ix)
end

# ---- 2. THE BEVEL ------------------------------------------------------
htop = pts_of(hg).select { |p| p.z > hb[:z][0] + 1.0 }
out_z = htop.select { |p| close(p.y, YHI, 0.1) }.map(&:z).max
in_z  = htop.select { |p| close(p.y, YHI - TH, 0.1) }.map(&:z).max
ok('the high wall top has points on BOTH faces', !out_z.nil? && !in_z.nil?,
   [out_z, in_z])
ok('...and drops slope*thickness across itself - the bevel',
   close(out_z.to_f - in_z.to_f, SLOPE * TH, 0.05), out_z.to_f - in_z.to_f)

# ---- 3. A RAKE IS NOT TILTED ------------------------------------------
# The rake's sloped top collapses to its two endpoints (collinear points
# are simplified away), so the outer top line is read as a LINE and the
# inner top points are checked against it at their own y.
rg, rb2 = rakes.first
router = rb2[:x][0] > -100.0 ? XHI : XLO
rinner = router - (router > -100.0 ? TH : -TH)
rp = pts_of(rg)
zlo = rb2[:z][0]
# the outer top line runs from the apex (the high corner) down to the
# zbase point at the FAR y - the low end, where top and bottom meet
oface = rp.select { |p| close(p.x, router, 0.1) }
apex = oface.max_by(&:z)
base = oface.select { |p| close(p.z, zlo, 0.1) }
            .max_by { |p| (p.y - apex.y).abs }
itop = rp.select { |p| close(p.x, rinner, 0.1) && p.z > zlo + 1.0 }
ok('the rake has a top line and an inner face',
   !apex.nil? && !base.nil? && (apex.y - base.y).abs > 1.0 && !itop.empty?,
   [apex, base, itop.length])
worst = itop.map do |p|
  zline = base.z + (apex.z - base.z) * ((p.y - base.y) / (apex.y - base.y))
  (p.z - zline).abs
end.max
ok('a rake top is LEVEL across its thickness - no false bevel',
   !worst.nil? && worst < 0.1, worst)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

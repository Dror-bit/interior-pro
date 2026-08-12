# encoding: utf-8
# rt36 — no ridge cap where a curved wall runs TANGENTIALLY into its neighbour
# (2026-08-12B).
#
# rt32 already killed the caps on the fan of rays inside one curved wall. Then
# the user looked at his own house and asked for one more: the two hips at the
# ENDS of the round part, where the arc meets the straight wall. There the eave
# turns by about half a facet angle - roughly 7 degrees - so the two roof planes
# are all but the same plane and the cap reads as a scar.
#
# The rule: a corner between two DIFFERENT walls loses its cap only when it
# barely turns AND a curved wall is one of the two sides. A corner that really
# turns keeps its cap, and a corner between two straight walls is never touched
# however shallow it is.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager
D = 'InteriorPro'.freeze
OVERHANG = 12.0

def mkwall(m, id, sx, sy, ex, ey, sag = nil)
  g = m.entities.add_group
  g.set_attribute(D, 'type', 'wall');   g.set_attribute(D, 'id', id)
  g.set_attribute(D, 'start_x', sx);    g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);      g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', 6.0); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', 'bottom-center')
  g.set_attribute(D, 'level', 1)
  g.set_attribute(D, 'wall_category', 'exterior')
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

def eave(walls_spec)
  Sketchup.reset_model!
  m = Sketchup.active_model
  walls_spec.each { |w| mkwall(m, *w) }
  RF.eave_polygon(m.entities.grep(Sketchup::Group), OVERHANG)
end

def turn_at(poly, j)
  n = poly.length
  i = (j - 1) % n
  k = (j + 1) % n
  a = [poly[j][0] - poly[i][0], poly[j][1] - poly[i][1]]
  b = [poly[k][0] - poly[j][0], poly[k][1] - poly[j][1]]
  Math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1]).abs * 180.0 / Math::PI
end

# ---------------------------------------------------------------- the user's
# A wing with a HALF-ROUND end: a 900 x 300 box whose right-hand wall bows out
# by half its own length, so the arc leaves each straight wall tangentially.
ROUND_END = [
  ['s1',   0.0,   0.0, 900.0,   0.0, nil],
  ['arc', 900.0,   0.0, 900.0, 300.0, -150.0],
  ['s2',  900.0, 300.0,   0.0, 300.0, nil],
  ['s3',    0.0, 300.0,   0.0,   0.0, nil]
].freeze

ep = eave(ROUND_END)
ok('a half-round end still gives an eave polygon', !ep.nil?)
if ep
  poly = ep[:pts]
  ids  = ep[:wall_ids]

  # The two joins: last straight point before the arc, and the arc's last point.
  j_in  = ids.index('arc')                       # s1  -> arc
  j_out = ids.index('s2')                        # arc -> s2
  ok('the join into the curve barely turns (under 15 deg)',
     turn_at(poly, j_in) < 15.0, turn_at(poly, j_in))
  ok('and so does the join out of it',
     turn_at(poly, j_out) < 15.0, turn_at(poly, j_out))

  soft = RF.soft_hip_points(poly, ids)
  ok('both tangential joins are spotted as soft corners', soft.length == 2, soft.length)
  ok('the soft corners are exactly those two points',
     soft.include?(poly[j_in]) && soft.include?(poly[j_out]), soft)
  ok('the square corners are NOT soft',
     soft.none? { |p| p == poly[ids.index('s3')] || p == poly[0] }, soft)
  ok('a facet seam is not counted twice here (that is facet_hip_points job)',
     soft.none? { |p| RF.facet_hip_points(poly, ids).include?(p) }, soft)

  # A hip hanging off each of those joins loses its cap; the 90 degree corner
  # keeps it, and so does a plain ridge in open air.
  soft_pt = poly[j_in]
  hard_pt = poly[ids.index('s3')]                # a true 90 deg corner
  lines = [[soft_pt, 0.0, [soft_pt[0] + 40.0, soft_pt[1] + 40.0], 9.0, []],
           [hard_pt, 0.0, [hard_pt[0] + 40.0, hard_pt[1] + 40.0], 9.0, []],
           [[-500.0, -500.0], 9.0, [-450.0, -500.0], 9.0, []]]
  kept = RF.drop_facet_hips(lines, poly, ids)
  ok('the tangential join loses its cap', kept.none? { |l| l[0] == soft_pt }, kept.length)
  ok('the 90 degree corner keeps its cap', kept.any? { |l| l[0] == hard_pt }, kept.length)
  ok('a plain ridge keeps its cap', kept.any? { |l| l[0] == [-500.0, -500.0] }, kept.length)
  ok('nothing else was thrown away', kept.length == 2, kept.length)
end

# ------------------------------------------------- a curve that REALLY turns
# The same wing, but the arc is a shallow bow on the END wall only: it meets
# its neighbours at a proper corner, so those caps must stay.
sharp = eave([['s1',   0.0,   0.0, 900.0,   0.0, nil],
              ['arc', 900.0,   0.0, 900.0, 300.0, -20.0],
              ['s2',  900.0, 300.0,   0.0, 300.0, nil],
              ['s3',    0.0, 300.0,   0.0,   0.0, nil]])
if sharp
  poly = sharp[:pts]
  ids  = sharp[:wall_ids]
  j_in = ids.index('arc')
  ok('a shallow bow still meets its neighbour at a real corner',
     turn_at(poly, j_in) > 45.0, turn_at(poly, j_in))
  ok('so that corner is NOT soft and keeps its cap',
     RF.soft_hip_points(poly, ids).empty?, RF.soft_hip_points(poly, ids))
end

# ------------------------------------------------------- straight walls only
# THE regression guard. A shallow bend between two STRAIGHT walls (a bay front)
# must be left exactly as it was - caps and all.
bay = eave([['b1',   0.0,   0.0, 400.0,   0.0, nil],
            ['b2', 400.0,   0.0, 700.0, 100.0, nil],   # a ~18 deg bend
            ['b3', 700.0, 100.0, 700.0, 500.0, nil],
            ['b4', 700.0, 500.0,   0.0, 500.0, nil],
            ['b5',   0.0, 500.0,   0.0,   0.0, nil]])
if bay
  poly = bay[:pts]
  ids  = bay[:wall_ids]
  j = ids.index('b2')
  ok('the bay bend really is shallow', turn_at(poly, j) < 30.0, turn_at(poly, j))
  ok('but with no curve anywhere it is NOT soft',
     RF.soft_hip_points(poly, ids).empty?, RF.soft_hip_points(poly, ids))
  lines = [[poly[j], 0.0, [poly[j][0] + 30.0, poly[j][1] + 30.0], 9.0, []]]
  ok('a straight-only roof keeps every cap it had',
     RF.drop_facet_hips(lines, poly, ids).length == 1)
end

# ------------------------------------------------------------ end to end
# The whole roof still builds, and the caps that survive are fewer than before.
ep3 = eave(ROUND_END)
if ep3
  poly = ep3[:pts]
  ids = ep3[:wall_ids]
  fan = RF.facet_hip_points(poly, ids)
  soft = RF.soft_hip_points(poly, ids)
  ok('fan seams and soft joins do not overlap',
     (fan & soft).empty?, (fan & soft))
  ok('together they cover every corner the curve touches',
     fan.length + soft.length == ids.count('arc') + 1,
     [fan.length, soft.length, ids.count('arc')])
end


# ---------------------------- a LOW wing dying into a TALLER block (the L)
# The user's own roof, 2026-08-12B. His wing ridge sits at 158" and the main
# block's at 235". Both lines came out with NO ridge cap, twice, and he drew
# them in red twice.
#
# The cause was not the valley rule. ridge_lines decides which side of a shared
# edge each face lies on by comparing the face's CENTRE OF GRAVITY with the
# middle of the edge - and on the long L-shaped cell a hip roof grows over a
# wing, that centre sits past the edge's own line. Both faces were filed on the
# same side, so "one plane each side" failed and the ridge was dropped.
# face_side_of_edge now steps a whisker off the edge and asks the face's own
# outline instead. A valley must still get nothing.
module Sketchup
  class Face
    attr_accessor :pts, :material, :back_material, :pulled
    def pushpull(d); @pulled = d; end
    def reverse!; @pts = @pts.reverse; self; end
    def normal
      a, b, c = @pts[0], @pts[1], @pts[2]
      u = Geom::Vector3d.new(b.x - a.x, b.y - a.y, b.z - a.z)
      v = Geom::Vector3d.new(c.x - a.x, c.y - a.y, c.z - a.z)
      (u * v).normalize
    end
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

# his eave polygon, straight off the debug print in the live model
L_POLY = [[-52.3, -2409.3], [806.8, -2409.3], [806.8, -955.2],
          [411.1, -955.2], [411.1, -1495.8], [-52.3, -1495.8]].freeze

Sketchup.reset_model!
l_arcs  = RF.straight_skeleton(L_POLY)
l_cells = l_arcs && RF.roof_cells(L_POLY, l_arcs)
ok('the L plan still skeletonises', !l_cells.nil? && l_cells.length == 6,
   l_cells && l_cells.length)

if l_cells
  grp = Sketchup.active_model.entities.add_group
  ridge, = RF.build_hip_geometry!(grp, L_POLY, l_cells, 96.0, 4.0 / 12.0, 12.0, nil, nil)
  ok('the hip shell builds', !ridge.nil? && (ridge - 235.18).abs < 0.1, ridge)
  l_lines = RF.ridge_lines(grp.entities.grep(Sketchup::Face))

  near = lambda do |a, b|
    l_lines.any? do |l|
      (Math.hypot(l[0][0] - a[0], l[0][1] - a[1]) < 1.5 &&
       Math.hypot(l[2][0] - b[0], l[2][1] - b[1]) < 1.5) ||
        (Math.hypot(l[0][0] - b[0], l[0][1] - b[1]) < 1.5 &&
         Math.hypot(l[2][0] - a[0], l[2][1] - a[1]) < 1.5)
    end
  end

  ok("the wing's own ridge gets a cap",
     near.call([608.9, -1153.1], [608.9, -1693.6]), l_lines.length)
  ok('the hip that carries it up to the main ridge gets a cap',
     near.call([608.9, -1693.6], [377.3, -1925.3]), l_lines.length)
  ok('the valley off the inside corner still gets NOTHING',
     !near.call([411.1, -1495.8], [608.9, -1693.6]), l_lines.length)
  ok('and every line the roof really has is found (8)', l_lines.length == 8,
     l_lines.length)
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

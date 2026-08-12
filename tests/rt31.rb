# encoding: utf-8
# rt31 — weld_corner!: one shared seam between a curve and its neighbour
# (2026-08-12, after rendering the user's exact rooms).
#
# Two geometries:
# * SAME-SIDE bands (near-parallel spring, user's room 1): both cuts nearly
#   coincide -> the guest snaps EXACTLY onto the owner's cut.
# * OPPOSITE-SIDE bands (user's room 2): only the touching lip is pulled to
#   the owner's FAR lip (a shoulder); the other cut point stays natural.
# In both: the owner (straight wall) keeps its FULL length - the old miter
# pulled it back 22"-64" and the wall looked torn in 2D and 3D.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

# Rebuild touches real faces; the corner attributes are what this pins.
InteriorPro::WallTool.class_eval do
  def rebuild_wall_geometry(_g, _c, _d); true; end
end

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close_pt(p, x, y, tol = 0.05); (p[0] - x).abs < tol && (p[1] - y).abs < tol; end

D = 'InteriorPro'
def mkwall(model, id, sx, sy, ex, ey, sag)
  g = model.entities.add_group
  g.set_attribute(D, 'type', 'wall'); g.set_attribute(D, 'id', id)
  g.set_attribute(D, 'start_x', sx); g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);   g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', 5.0); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', 'bottom-left'); g.set_attribute(D, 'wall_category', 'exterior')
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

def slots(g, side)
  c = g.get_attribute('InteriorPro', 'corners_xy')
  return nil unless c.is_a?(Array) && c.length == 8
  side == :start ? [[c[0], c[1]], [c[6], c[7]]] : [[c[2], c[3]], [c[4], c[5]]]
end

tool = InteriorPro::WallTool.new

# ---------------- OPPOSITE-SIDE bands: user's room 2 top corner ----------
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
top = mkwall(model, 'top', 2907.5, 1034.0, 3099.5, 1034.0, nil)   # band ABOVE
arc = mkwall(model, 'arc', 3099.5, 843.0, 3099.5, 1034.0, -60.0)  # band toward the room
tool.apply_miter(top, :end, arc, :end, model)

t_cut = slots(top, :end)
ok('opposite: the straight wall keeps its FULL length, plain square cut',
   t_cut && ((close_pt(t_cut[0], 3099.5, 1039.0) && close_pt(t_cut[1], 3099.5, 1034.0)) ||
             (close_pt(t_cut[0], 3099.5, 1034.0) && close_pt(t_cut[1], 3099.5, 1039.0))), t_cut)

a_cut = slots(arc, :end)
lips = a_cut ? [a_cut[0], a_cut[1]] : []
ok('opposite: the touching lip is pulled onto the owner FAR lip (3099.5, 1039)',
   lips.any? { |p| close_pt(p, 3099.5, 1039.0) }, a_cut)
ok('opposite: the other cut point stays on the natural radial cut',
   lips.any? { |p| close_pt(p, 3097.33, 1029.5, 0.05) }, a_cut)

# ---------------- SAME-SIDE bands: a near-tangent arch spring ------------
# A wall runs straight up and an almost-half-circle arch springs off it: the
# two cuts nearly coincide (under half an inch apart), so the guest snaps
# EXACTLY onto the owner's cut - one shared seam.
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
leg  = mkwall(model, 'leg', 0.0, 0.0, 0.0, 100.0, nil)
arch = mkwall(model, 'arch', 0.0, 100.0, 120.0, 100.0, 55.0)
# (through apply_miter this pair takes a legitimate short miter; the weld
# itself is what this section pins, so it is called directly)
tool.weld_corner!(leg, :end, arch, :start)

o_cut = slots(leg, :end)
g_cut = slots(arch, :start)
ok('same-side: owner keeps its full-length square cut',
   o_cut && ((close_pt(o_cut[0], -5.0, 100.0) && close_pt(o_cut[1], 0.0, 100.0)) ||
             (close_pt(o_cut[0], 0.0, 100.0) && close_pt(o_cut[1], -5.0, 100.0))), o_cut)
same = g_cut && o_cut &&
       ((close_pt(g_cut[0], *o_cut[0]) && close_pt(g_cut[1], *o_cut[1])) ||
        (close_pt(g_cut[0], *o_cut[1]) && close_pt(g_cut[1], *o_cut[0])))
ok('same-side: the guest cut IS the owner cut - one exact shared seam', same, [o_cut, g_cut])

# ---------------- both rooms end-to-end: no wall ever torn ----------------
[[
  ['top',    2907.5, 1034.0, 3099.5, 1034.0, nil],
  ['left',   2907.5, 1034.0, 2907.5, 843.0, nil],
  ['bottom', 2907.5, 843.0, 3099.5, 843.0, nil],
  ['arc',    3099.5, 843.0, 3099.5, 1034.0, -60.0]
], [
  ['top',    3273.5, 1521.0, 2977.5, 1521.0, nil],
  ['left',   2977.5, 1521.0, 2977.5, 1228.5, nil],
  ['bottom', 3273.5, 1228.5, 2977.5, 1228.5, nil],
  ['arc',    3273.5, 1228.5, 3273.5, 1521.0, -125.12]
]].each_with_index do |walls, ri|
  Sketchup.reset_model!
  model = Sketchup.active_model
  def model.active_entities; entities; end
  groups = walls.map { |w| mkwall(model, w[0], w[1], w[2], w[3], w[4], w[5]) }
  2.times { groups.each { |g| tool.join_corners(g, model) } }
  worst = 0.0
  groups.each do |g|
    sx = g.get_attribute(D, 'start_x'); sy = g.get_attribute(D, 'start_y')
    ex = g.get_attribute(D, 'end_x');   ey = g.get_attribute(D, 'end_y')
    c = g.get_attribute(D, 'corners_xy')
    next unless c
    [[c[0], c[1], sx, sy], [c[6], c[7], sx, sy],
     [c[2], c[3], ex, ey], [c[4], c[5], ex, ey]].each do |px, py, qx, qy|
      d = Math.hypot(px - qx, py - qy)
      worst = d if d > worst
    end
  end
  ok("room #{ri + 1}: no corner ever reaches further than 2 thicknesses (was 64\")",
     worst <= 10.0, worst)
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt33 — swap_wall_side!: move a wall's BODY to the other side of its drawn
# line (2026-08-12). Born from the user's left arc corner: wall C's body sat
# EAST of its line while the arc's band sat WEST, so weld_corner! could only
# give a shoulder - the arc poked 5" past C's face. Moving C's body west puts
# both bands on the same side and the seam becomes exact, like his right
# corner already was. The numbers below are the user's real model.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

# Rebuild touches real faces; the attributes are what this pins.
InteriorPro::WallTool.class_eval do
  def rebuild_wall_geometry(_g, _c, _d); true; end
end

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close_pt(p, x, y, tol = 0.05); (p[0] - x).abs < tol && (p[1] - y).abs < tol; end

D = 'InteriorPro'
def mkwall(model, id, sx, sy, ex, ey, anchor, sag = nil)
  g = model.entities.add_group
  g.set_attribute(D, 'type', 'wall'); g.set_attribute(D, 'id', id)
  g.set_attribute(D, 'start_x', sx); g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);   g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', 5.0); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', anchor); g.set_attribute(D, 'wall_category', 'exterior')
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

def pts_of(g)
  c = g.get_attribute(D, 'corners_xy')
  c.is_a?(Array) && c.length == 8 ? c.each_slice(2).to_a : nil
end

wt = InteriorPro::WallTool

# ---------------- the swap itself, on a lone straight wall ----------------
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
w = mkwall(model, 'w', 0.0, 0.0, 100.0, 0.0, 'bottom-left')
ok('swap succeeds on a plain wall', wt.swap_wall_side!(w))
ok('the anchor is mirrored', w.get_attribute(D, 'anchor') == 'bottom-right',
   w.get_attribute(D, 'anchor'))
ok('the drawn line did not move',
   w.get_attribute(D, 'start_x') == 0.0 && w.get_attribute(D, 'end_x') == 100.0)
p1 = pts_of(w)
ok('the body now lies on the OTHER side of the line (y in 0..-5)',
   p1 && p1.all? { |p| p[1] <= 0.001 && p[1] >= -5.001 }, p1)
ok('swapping back returns the original side', wt.swap_wall_side!(w) &&
   pts_of(w).all? { |p| p[1] >= -0.001 && p[1] <= 5.001 }, pts_of(w))

# center anchor: there is no other side - refused, nothing changed
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
c = mkwall(model, 'c', 0.0, 0.0, 100.0, 0.0, 'bottom-center')
ok('a center-anchored wall is refused', !wt.swap_wall_side!(c))
ok('and its anchor is untouched', c.get_attribute(D, 'anchor') == 'bottom-center')

# a wall hosting a window is refused (the rebuild would bury the hole)
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
hw = mkwall(model, 'hw', 0.0, 0.0, 100.0, 0.0, 'bottom-left')
win = model.entities.add_group
win.set_attribute(D, 'type', 'window')
win.set_attribute(D, 'host_wall_id', 'hw')
ok('a wall hosting a window is refused', !wt.swap_wall_side!(hw))
ok('and keeps its anchor', hw.get_attribute(D, 'anchor') == 'bottom-left')

# ---------------- the user's left corner, before and after ----------------
# Wall C runs down the west side, body EAST; the arc springs east with its
# band SOUTH-WEST. Natural cuts sit on opposite sides -> shoulder.
def build_user_corner(model, c_anchor)
  cw = mkwall(model, 'C', -1016.74, 573.05, -1016.74, -125.4, "bottom-#{c_anchor}")
  ar = mkwall(model, 'ARC', -1016.74, -125.4, -542.31, -125.4, 'bottom-right', -197.14)
  [cw, ar]
end

Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
cw, ar = build_user_corner(model, 'left')
tool = wt.new
2.times { [cw, ar].each { |g| tool.join_corners(g, model) } }
before = pts_of(ar)
west_before = before.map { |p| p[0] }.min
ok('BEFORE: opposite sides - the arc pokes past C west face (shoulder)',
   west_before < -1016.74 - 0.5, west_before)

# Move C's body to the west - the multi entry point, exactly what the menu
# runs - and the corner is re-joined for us.
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
cw, ar = build_user_corner(model, 'left')
tool = wt.new
2.times { [cw, ar].each { |g| tool.join_corners(g, model) } }
ok('the multi swap reports one wall moved', wt.swap_wall_side_multi!([cw]) == 1)
ok('C anchor is now bottom-right', cw.get_attribute(D, 'anchor') == 'bottom-right')

cp = pts_of(cw)
ap = pts_of(ar)
ok('C body now lies WEST of its line', cp && cp.all? { |p| p[0] <= -1016.74 + 0.001 }, cp)
shared = ap && cp && ap.count { |a| cp.any? { |b| Math.hypot(a[0] - b[0], a[1] - b[1]) < 0.1 } }
ok('AFTER: the arc and C share BOTH lips of the cut - one exact seam, no shoulder',
   shared && shared >= 2, [shared, ap, cp])
west_after = ap.map { |p| p[0] }.min
ok('nothing pokes past C new west face (-1021.74)', west_after >= -1021.74 - 0.05, west_after)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

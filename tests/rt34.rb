# encoding: utf-8
# rt34 — a door (or window) on a curved wall must sit IN its own opening for
# EVERY anchor (2026-08-12).
#
# rt25 pinned the curved-door ruler, but only on a bottom-center wall - and
# center is exactly the anchor where the bug cannot show. geo_at rebuilt
# cline_start from the pocket centre, which sits on the DRAWN arc, and forgot
# the anchor's center_offset that the straight path bakes in. On any
# left/right-anchored curved wall every door slid HALF A THICKNESS off its
# hole, into the house (user 2026-08-12, the round room: "the doors are
# inside the house - they must move toward the opening").
#
# THE invariant that catches it: adding a hair of curvature to a wall must
# move the door a hair. Before the fix it jumped 2.5" the moment sag crossed
# MIN_ARC_SAG; after it, the placement is continuous in sag for all anchors.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'
require './door_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

D = 'InteriorPro'
DM = InteriorPro::DoorManager

def mkwall(model, sx, sy, ex, ey, anchor, sag)
  g = model.entities.add_group
  g.set_attribute(D, 'type', 'wall'); g.set_attribute(D, 'id', 'w')
  g.set_attribute(D, 'start_x', sx); g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);   g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', 5.0); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', anchor)
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

# The door-centre line every door caller uses.
def door_cx_cy(geo, t, width)
  g2 = DM.geo_at(geo, t, width)
  [g2[:cline_start].x + g2[:unit].x * t + g2[:n].x * geo[:n_side],
   g2[:cline_start].y + g2[:unit].y * t + g2[:n].y * geo[:n_side]]
end

model = Sketchup.active_model
T = 100.0
W = 36.0

# ---- continuity in sag, for every anchor -------------------------------
%w[bottom-left bottom-right bottom-center].each do |anc|
  straight = mkwall(model, 0.0, 0.0, 200.0, 0.0, anc, nil)
  barely   = mkwall(model, 0.0, 0.0, 200.0, 0.0, anc, 0.08) # a hair over MIN_ARC_SAG
  ca = door_cx_cy(DM.wall_geometry(straight), T, W)
  cb = door_cx_cy(DM.wall_geometry(barely),   T, W)
  jump = Math.hypot(cb[0] - ca[0], cb[1] - ca[1])
  ok("#{anc}: a hair of curvature moves the door a hair (was a 2.5\" jump)",
     jump < 0.2, jump)
end

# ---- geo_at carries the anchor offset through --------------------------
ok('wall_geometry now ships center_offset',
   DM.wall_geometry(mkwall(model, 0.0, 0.0, 200.0, 0.0, 'bottom-left', nil))
     .key?(:center_offset))

# ---- a REAL bow: the door centre sits on the panel centreline ----------
# For each anchor, the door centre (cline + n*n_side) must land at the same
# distance from the pocket chord that it has from the drawn line on a
# straight wall - i.e. the door stays glued to its own flat panel.
%w[bottom-left bottom-right bottom-center].each do |anc|
  g = mkwall(model, 0.0, 0.0, 200.0, 0.0, anc, 60.0)
  geo = DM.wall_geometry(g)
  cx, cy = door_cx_cy(geo, geo[:wall_length] / 2.0, W)
  pk = InteriorPro::WallTool.opening_pocket(0.0, 0.0, 200.0, 0.0, 60.0,
                                            geo[:wall_length] / 2.0, W)
  d_pocket = Math.hypot(cx - pk[:center][0], cy - pk[:center][1])
  want = (geo[:center_offset] + geo[:n_side]).abs
  ok("#{anc}: on a 60\" bow the door hugs its panel (#{want.round(1)}\" off the pocket chord)",
     (d_pocket - want).abs < 0.01, [d_pocket, want])
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

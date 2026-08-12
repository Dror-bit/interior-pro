# encoding: utf-8
# rt35 — bending a wall ALIGNS THE BODY SIDES BY ITSELF (2026-08-12).
#
# The user's bug, in his words: why do I need another button to fix this?
# He drew a room and an arch with the plugin's own tools and the spring
# corner came out with a 5" tooth, because the arch's body and its
# neighbour's body sat on opposite sides of their drawn lines - and welding
# opposite lanes can only ever produce a shoulder or a tooth.
#
# Now set_wall_sag! (the ONE entry point for both the drag and the 3-click
# arc tool) calls align_curve_lanes!: it re-seats the curve, and any straight
# neighbour that still clashes, so every curve corner welds to ONE exact
# seam - no button, no manual step, one undo. The numbers here are the
# user's exact 6-wall model from the 2026-08-12 session.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

InteriorPro::WallTool.class_eval do
  def rebuild_wall_geometry(_g, _c, _d); true; end
end

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

D = 'InteriorPro'
def mkwall(model, id, sx, sy, ex, ey, anc, sag = nil)
  g = model.entities.add_group
  g.set_attribute(D, 'type', 'wall'); g.set_attribute(D, 'id', id)
  g.set_attribute(D, 'start_x', sx); g.set_attribute(D, 'start_y', sy)
  g.set_attribute(D, 'end_x', ex);   g.set_attribute(D, 'end_y', ey)
  g.set_attribute(D, 'thickness', 5.0); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', anc); g.set_attribute(D, 'wall_category', 'exterior')
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

def cuts(g, side)
  c = g.get_attribute(D, 'corners_xy')
  return nil unless c.is_a?(Array) && c.length == 8
  p = c.each_slice(2).to_a
  side == :start ? [p[0], p[3]] : [p[1], p[2]]
end

def shared(a, b)
  return 0 unless a && b
  a.count { |p| b.any? { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) < 0.1 } }
end

wt = InteriorPro::WallTool

# ---------------- the user's model: bend the wall, everything aligns ------
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
top = mkwall(model, 'top', 268.56, 336.67, -615.11, 336.67, 'bottom-left')
mkwall(model, 'left', -615.11, 336.67, -615.11, -564.66, 'bottom-left')
mkwall(model, 'bot', -615.11, -564.66, -136.22, -564.66, 'bottom-left')
mid = mkwall(model, 'mid', -136.22, -564.66, -136.22, 0.0, 'bottom-left')
arc = mkwall(model, 'arc', 268.56, 0.0, 268.56, 336.67, 'bottom-right')   # straight, wrong lane
low = mkwall(model, 'low', -136.22, 0.0, 268.56, 0.0, 'bottom-right')      # wrong lane too
tool = wt.new
2.times { model.entities.grep(Sketchup::Group).each { |g| tool.join_corners(g, model) } }

# THE user action: bend the wall. Nothing else.
ok('bending the wall succeeds', wt.set_wall_sag!(arc, -146.35, wrap_operation: false))

ae = cuts(arc, :end)
as = cuts(arc, :start)
ok('top corner: one exact seam, both lips shared', shared(ae, cuts(top, :start)) == 2,
   [ae, cuts(top, :start)])
ok('bottom corner: one exact seam, both lips shared', shared(as, cuts(low, :end)) == 2,
   [as, cuts(low, :end)])
ok('NO tooth above the top wall face (was 4.95")',
   ae.map { |p| p[1] }.max <= 336.67 + 0.01, ae)
ok('NO tooth below the low wall face',
   as.map { |p| p[1] }.min >= 0.0 - 5.01, as)
ok('the top wall itself was NOT moved (long house wall stays put)',
   wt.wall_h_anchor(top) == 'left', wt.wall_h_anchor(top))
ok('the curve was re-seated to the matching lane',
   wt.wall_h_anchor(arc) == 'left', wt.wall_h_anchor(arc))
ok('and so was its little spring wall',
   wt.wall_h_anchor(low) == 'left', wt.wall_h_anchor(low))
ok('the drawn lines did not move an inch',
   arc.get_attribute(D, 'start_x') == 268.56 && low.get_attribute(D, 'end_x') == 268.56)
ok('low-mid corner still welds shut after the re-seat',
   shared(cuts(low, :start), cuts(mid, :end)) >= 1,
   [cuts(low, :start), cuts(mid, :end)])

# ---------------- lanes already match: bending must touch NOTHING else ----
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
leg  = mkwall(model, 'leg', 0.0, 0.0, 0.0, 100.0, 'bottom-left')
arch = mkwall(model, 'arch', 0.0, 100.0, 120.0, 100.0, 'bottom-left')
tool = wt.new
2.times { [leg, arch].each { |g| tool.join_corners(g, model) } }
ok('bending a matched-lane wall succeeds', wt.set_wall_sag!(arch, 55.0, wrap_operation: false))
ok('nobody was re-seated - the neighbour keeps its anchor',
   wt.wall_h_anchor(leg) == 'left', wt.wall_h_anchor(leg))
ok('the arch keeps its anchor too', wt.wall_h_anchor(arch) == 'left',
   wt.wall_h_anchor(arch))
ok('and the seam is exact', shared(cuts(arch, :start), cuts(leg, :end)) == 2,
   [cuts(arch, :start), cuts(leg, :end)])

# ---------------- a lone wall: no neighbours, no drama --------------------
Sketchup.reset_model!
model = Sketchup.active_model
def model.active_entities; entities; end
solo = mkwall(model, 'solo', 0.0, 0.0, 200.0, 0.0, 'bottom-right')
ok('bending a lone wall still works', wt.set_wall_sag!(solo, 40.0, wrap_operation: false))
ok('and it is not re-seated', wt.wall_h_anchor(solo) == 'right', wt.wall_h_anchor(solo))

# ---------------- straightening back never triggers the aligner -----------
ok('straightening back works', wt.set_wall_sag!(solo, 0.0, wrap_operation: false))
ok('anchor untouched by straightening', wt.wall_h_anchor(solo) == 'right')

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

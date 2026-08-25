# encoding: utf-8
# rt86 - A GABLE END CLOSES A BODY, NOT A WALL (2026-08-27).
#
# The user's house: a main body gabled south, and a wing hanging south off
# its western half. Only the EASTERN half of the main's south side has a
# wall. Until today the gable end plane was built over that wall and
# nowhere else, so above the wing roof it stayed WIDE OPEN - his photos of
# 26.08 look straight through the house.
#
# `framed_edge_span` is the answer: the profile now reaches across the
# whole framed piece that owns the end line, and the covering-roof clip
# that was already there (wall_visible_profile / framed_cover_z) decides
# where it actually needs a face.
#
# THE OTHER HALF OF THE JOB is the 2026-08-09 rule, and it still holds:
# NEVER IN MID AIR. `full: true` was tried first and broke rt17 exactly
# that way - the end-plane LINE is infinite and drags in zmap nodes from
# elsewhere on it. The rect is what keeps the wall wider than the wall and
# never wider than the body.
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
def close(a, b, t = 0.01)
  (a.to_f - b.to_f).abs < t
end
RF = InteriorPro::RoofManager

# ===================================================== 1. the pure helper
# One square body, gabled south. The end line is its own south edge, so
# the span IS the edge - nothing changes for a plain gable.
PLAIN = { main: [0.0, 0.0, 100.0, 200.0], g: { s: true, n: false, e: false, w: false },
          wings: [], edges: [0] }
SQ = [[0.0, 0.0], [100.0, 0.0], [100.0, 200.0], [0.0, 200.0]].freeze

sp = RF.framed_edge_span(PLAIN, SQ, 0)
ok('a plain gable spans exactly its own edge', sp && close(sp[0], 0.0) && close(sp[1], 100.0), sp)

# ...and the user's shape: the marked wall is only the eastern part of the
# body's south side, so the span reaches WEST of the edge, into negative t.
L_MAIN = [-600.0, 0.0, 0.0, 700.0].freeze
L_PLAN = { main: L_MAIN, g: { s: true, n: false, e: false, w: false },
           wings: [{ rect: [-600.0, -300.0, -250.0, 0.0], mouth: :n, gabled: true }],
           edges: [0] }
# poly edge 0 runs west->east along y = 0, from the wing's east side out to
# the body's east corner - the marked wall, and nothing more.
L_POLY = [[-250.0, 0.0], [0.0, 0.0], [0.0, 700.0], [-600.0, 700.0], [-600.0, -300.0],
          [-250.0, -300.0]].freeze
sp2 = RF.framed_edge_span(L_PLAN, L_POLY, 0)
ok('the span reaches back across the whole body, not just the wall',
   sp2 && close(sp2[0], -350.0) && close(sp2[1], 250.0), sp2)
ok('...which is wider than the poly edge on the wing side',
   sp2[0] < 0.0, sp2)
ok('...and never past the body on the far side',
   close(sp2[1], 250.0), sp2)

# no plan, no span - every caller falls back to the poly edge, unchanged
ok('no framed plan -> nil, so nothing changes', RF.framed_edge_span(nil, L_POLY, 0).nil?)
# an edge no framed piece owns (a plain eave) -> nil too
ok('an unowned edge -> nil', RF.framed_edge_span(L_PLAN, L_POLY, 2).nil?,
   RF.framed_edge_span(L_PLAN, L_POLY, 2))

# a WING's own gable end: its span is its own rect, so it does not grow
w_poly = [[-600.0, -300.0], [-250.0, -300.0], [-250.0, 0.0], [-600.0, 0.0]].freeze
w_plan = { main: L_MAIN, g: { s: false, n: false, e: false, w: false },
           wings: [{ rect: [-600.0, -300.0, -250.0, 0.0], mouth: :n, gabled: true }],
           edges: [0] }
spw = RF.framed_edge_span(w_plan, w_poly, 0)
ok('a wing gable spans its own rect', spw && close(spw[0], 0.0) && close(spw[1], 350.0), spw)

# ================================================ 2. the user's real house
# Straight from his model (gable_pair_report.txt, 2026-08-27): 6 walls,
# two gable marks, 4:12, 12" eaves.
def mk(m, id, s, e)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id,
    'start_x' => s[0], 'start_y' => s[1], 'end_x' => e[0], 'end_y' => e[1],
    'thickness' => 5.0, 'anchor' => 'bottom-center', 'height' => 106.0,
    'base_z' => 0.0, 'level' => 1, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

Sketchup.reset_model!
m = Sketchup.active_model
mk(m, 'A', [0.0, 0.0],         [0.0, 765.84])
mk(m, 'B', [0.0, 765.84],      [-599.61, 765.84])
mk(m, 'C', [-599.61, 765.84],  [-599.61, -330.32])
mk(m, 'D', [-279.46, -330.32], [-279.46, 0.0])
mk(m, 'E', [-279.46, 0.0],     [0.0, 0.0])
mk(m, 'F', [-599.61, -330.32], [-279.46, -330.32])
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', %w[E F])
m.set_attribute('InteriorPro', 'roof_gable_click_xy', [-184.24, 0.0, -465.27, -330.32])

r = RF.build_roof!(style: 'hip', pitch: 4.0, overhang: 12.0, fascia: true,
                   fascia_depth: 8.0, drip: true, soffit: 'wood',
                   soffit_slope: true, thickness: 0.5, ridge_cap: true,
                   gable_walls: true)
ok('his house builds', !r.nil?)

def walk(ents, out)
  ents.each do |e|
    case e
    when Sketchup::Face then out << e
    when Sketchup::Group then walk(e.entities, out)
    end
  end
  out
end

south = nil
r.entities.grep(Sketchup::Group).each do |g|
  next unless g.get_attribute('InteriorPro', 'part') == 'gable_wall_top'
  fs = walk(g.entities, [])
  next if fs.empty?
  next if fs.flat_map(&:pts).map(&:y).min < -300.0 # that one is the wing's
  south = fs
end
ok('the main body still gets its gable wall', !south.nil? && !south.empty?)

sx = south.flat_map(&:pts).map(&:x)
sz = south.flat_map(&:pts).map(&:z)
# The wing's ridge sits at the middle of its rect: (-614.11 + -264.96)/2.
ok('the wall reaches the wing ridge, closing the hole (was -265)',
   close(sx.min, -439.5, 1.5), sx.min)
ok('...and still ends at the marked wall\'s far corner', close(sx.max, 2.5, 1.0), sx.max)
ok('...and never past the building - no mid-air wall', sx.min > -614.11, sx.min)
ok('it still peaks at the main ridge', close(sz.max, 206.77, 0.5), sz.max)
ok('and still starts at the wall top, not the eave', close(sz.min, 106.0, 0.1), sz.min)

# THE HOLE ITSELF: at the gable line, between the wing ridge and the marked
# wall, there must now be wall at every height the main roof reaches.
plan = RF.framed_plan(RF.eave_polygon(RF.walls_of(1), 12.0)[:pts],
                      RF.eave_polygon(RF.walls_of(1), 12.0)[:wall_ids], %w[E F], 'hip')
ok('the plan is still main + one gabled wing',
   plan && plan[:wings].length == 1 && plan[:wings][0][:gabled], plan && plan[:wings])

covered = [-430.0, -400.0, -350.0, -300.0, -280.0].all? do |x|
  south.any? { |f| f.pts.map(&:x).min <= x + 0.01 && f.pts.map(&:x).max >= x - 0.01 }
end
ok('every x across the old hole is inside a wall face now', covered)

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

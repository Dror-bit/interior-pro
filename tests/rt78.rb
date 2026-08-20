# encoding: utf-8
# rt78 - RoofManager.roof_edges: the ONE place that names the four kinds of
# roof edge (2026-08-19, ROOF_TILES_PROPOSAL.md §3, hybrid tile roof step 3).
#
# WHAT THIS SUITE IS REALLY GUARDING
# The proposal says, in bold: do NOT write a second edge classifier.
# ridge_lines, drop_facet_hips, eave_polygon and the gable_spans machinery all
# already work and are all already in production. roof_edges is a WRAPPER.
# Two classifiers that disagree is precisely the bug that ate 2026-08-19 in
# window_tool.rb, so the central test here is not "are the numbers pretty" -
# it is "does the wrapper return EXACTLY what the production classifier
# returned, only sorted into named buckets".
#
# So:
#   1. ridge + hip together == drop_facet_hips(ridge_lines(faces)) exactly,
#      on the user's own L-shaped plan. Not a similar number. The same number.
#   2. level -> :ridge, sloped -> :hip. That is the single new decision.
#   3. a plain edge is one eave; a GABLED edge is split at band_top into the
#      rake stretch and the eave stretch, the same split build_band! makes.
#   4. every segment carries real 3D endpoints, so the placer never has to
#      guess a height.
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

def close(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RF = InteriorPro::RoofManager

# The stub's Face has to answer `normal` and keep its points, exactly the way
# rt36 needs it for ridge_lines. Same block, same reason.
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

# ------------------------------------------------------- chain_z_at is honest

CH = [[0.0, [0.0, 0.0], 100.0], [50.0, [50.0, 0.0], 150.0],
      [100.0, [100.0, 0.0], 100.0]].freeze

ok('chain_z_at with no chain falls back',   close(RF.chain_z_at(nil, 10.0, 96.0), 96.0))
ok('chain_z_at clamps before the start',    close(RF.chain_z_at(CH, -5.0, nil), 100.0))
ok('chain_z_at clamps past the end',        close(RF.chain_z_at(CH, 500.0, nil), 100.0))
ok('chain_z_at hits a node exactly',        close(RF.chain_z_at(CH, 50.0, nil), 150.0))
ok('chain_z_at interpolates on the way up', close(RF.chain_z_at(CH, 25.0, nil), 125.0))
ok('chain_z_at interpolates on the way down', close(RF.chain_z_at(CH, 75.0, nil), 125.0))

# -------------------------------------------- a plain hip roof on the L plan
#
# Straight out of the live model, the same polygon rt36 uses.
L_POLY = [[-52.3, -2409.3], [806.8, -2409.3], [806.8, -955.2],
          [411.1, -955.2], [411.1, -1495.8], [-52.3, -1495.8]].freeze

Sketchup.reset_model!
arcs  = RF.straight_skeleton(L_POLY)
cells = arcs && RF.roof_cells(L_POLY, arcs)
ok('the L plan skeletonises', !cells.nil? && cells.length == 6, cells && cells.length)

if cells
  grp = Sketchup.active_model.entities.add_group
  _ridge, zmap = RF.build_hip_geometry!(grp, L_POLY, cells, 96.0, 4.0 / 12.0,
                                        12.0, nil, nil)
  faces = grp.entities.grep(Sketchup::Face)
  ids   = Array.new(L_POLY.length) { |i| "w#{i}" } # 6 straight walls, all different

  raw  = RF.drop_facet_hips(RF.ridge_lines(faces), L_POLY, ids)
  ed   = RF.roof_edges(faces, L_POLY, ids, zmap, band_top: 92.0)

  # 1. THE point of the file: nothing is invented and nothing is lost.
  ok('ridge + hip together are EXACTLY what the production classifier found',
     ed[:ridge].length + ed[:hip].length == raw.length,
     [ed[:ridge].length, ed[:hip].length, raw.length])
  ok('and that is the 8 lines rt36 pinned',
     raw.length == 8, raw.length)

  # 2. the one new decision
  ok('every :ridge really is level',
     ed[:ridge].all? { |l| (l[:a][2] - l[:b][2]).abs < 1.0 },
     ed[:ridge].map { |l| (l[:a][2] - l[:b][2]).round(2) })
  ok('every :hip really does slope',
     ed[:hip].all? { |l| (l[:a][2] - l[:b][2]).abs >= 1.0 },
     ed[:hip].map { |l| (l[:a][2] - l[:b][2]).round(2) })
  ok('a hip roof has both kinds', !ed[:ridge].empty? && !ed[:hip].empty?,
     [ed[:ridge].length, ed[:hip].length])

  # 3. no gables were asked for, so every poly edge is one plain eave
  ok('no gable asked for -> no rake at all', ed[:rake].empty?, ed[:rake].length)
  ok('one eave per poly edge', ed[:eave].length == L_POLY.length, ed[:eave].length)
  ok('each eave names the wall it stands on',
     ed[:eave].map { |e| e[:wall_id] }.sort == ids.sort,
     ed[:eave].map { |e| e[:wall_id] })

  # 4. the eaves add up to the perimeter - nothing dropped, nothing doubled
  peri = (0...L_POLY.length).sum do |i|
    a = L_POLY[i]
    b = L_POLY[(i + 1) % L_POLY.length]
    Math.hypot(b[0] - a[0], b[1] - a[1])
  end
  got = ed[:eave].sum { |e| Math.hypot(e[:b][0] - e[:a][0], e[:b][1] - e[:a][1]) }
  ok('the eaves add up to the whole perimeter', close(got, peri, 0.5), [got, peri])

  # 5. real 3D endpoints, not a flat 2D line the placer would have to guess at
  ok('every segment carries a z on both ends',
     (ed[:eave] + ed[:ridge] + ed[:hip]).all? { |e| e[:a][2] && e[:b][2] })
  ok('the eaves sit at the eave height, not at the ridge',
     ed[:eave].all? { |e| close(e[:a][2], 92.0, 0.5) && close(e[:b][2], 92.0, 0.5) },
     ed[:eave].map { |e| e[:a][2].round(2) })
  ok('a ridge sits above its eaves',
     ed[:ridge].all? { |l| l[:a][2] > 92.0 },
     ed[:ridge].map { |l| l[:a][2].round(2) })
end

# ------------------------------------------- a GABLED edge splits, it is not
#                                             swallowed whole
#
# The rule build_band! has followed since 2026-08-09: only the stretch of a
# gabled edge that RISES above the eave line belongs to the rake; the rest of
# the very same edge is still a plain eave and still gets its fascia.
#
# A 200 x 100 rectangle. Edge 0 runs (0,0) -> (200,0) and is marked as a
# gable. Its profile is flat at 96 for the first 60", then climbs to 140 at
# 140" and drops back to 96 at the far corner.
G_POLY = [[0.0, 0.0], [200.0, 0.0], [200.0, 100.0], [0.0, 100.0]].freeze
G_ZMAP = { [0.0, 0.0] => 96.0, [60.0, 0.0] => 96.0, [140.0, 0.0] => 140.0,
           [200.0, 0.0] => 96.0, [200.0, 100.0] => 96.0,
           [0.0, 100.0] => 96.0 }.freeze
G_IDS = %w[g0 g1 g2 g3].freeze
FLAT = ->(_x, _y) { nil } # nothing over-frames anything here

g = RF.roof_edges([], G_POLY, G_IDS, G_ZMAP,
                  gables: [0], band_top: 96.0, surface: FLAT)

rake0 = g[:rake].select { |e| e[:edge] == 0 }
eave0 = g[:eave].select { |e| e[:edge] == 0 }

ok('the gabled edge produces exactly one rake stretch', rake0.length == 1,
   g[:rake].map { |e| [e[:edge], e[:a][0].round(1), e[:b][0].round(1)] })
ok('the rake starts where the profile leaves the eave line (60")',
   rake0[0] && close(rake0[0][:a][0], 60.0, 0.5), rake0[0] && rake0[0][:a][0])
ok('and runs to the end of the edge (200")',
   rake0[0] && close(rake0[0][:b][0], 200.0, 0.5), rake0[0] && rake0[0][:b][0])
ok('the rake carries the CLIMBING z, not a flat one',
   rake0[0] && close(rake0[0][:a][2], 96.0, 0.5) && close(rake0[0][:b][2], 96.0, 0.5),
   rake0[0] && [rake0[0][:a][2], rake0[0][:b][2]])

ok('the REST of the same edge is still a plain eave', eave0.length == 1,
   eave0.length)
ok('and it is the first 60"',
   eave0[0] && close(eave0[0][:a][0], 0.0, 0.5) && close(eave0[0][:b][0], 60.0, 0.5),
   eave0[0] && [eave0[0][:a][0], eave0[0][:b][0]])
ok('the three un-gabled edges are untouched, one eave each',
   g[:eave].reject { |e| e[:edge] == 0 }.length == 3,
   g[:eave].reject { |e| e[:edge] == 0 }.length)
ok('a rake knows which wall it climbs', rake0[0] && rake0[0][:wall_id] == 'g0',
   rake0[0] && rake0[0][:wall_id])

# The same rectangle with NO gable mark: edge 0 must come back whole, so the
# split above is caused by the mark and by nothing else.
p0 = RF.roof_edges([], G_POLY, G_IDS, G_ZMAP, band_top: 96.0, surface: FLAT)
ok('drop the gable mark and edge 0 is one eave again',
   p0[:rake].empty? && p0[:eave].select { |e| e[:edge] == 0 }.length == 1,
   [p0[:rake].length, p0[:eave].length])
ok('and it spans the whole 200"',
   close(p0[:eave].find { |e| e[:edge] == 0 }[:b][0], 200.0, 0.5))

# ----------------------------------------------------------- it never throws

ok('nil poly -> empty buckets, no exception',
   RF.roof_edges([], nil, nil, nil) == { eave: [], rake: [], ridge: [], hip: [] })
ok('a 2-point poly is not a roof',
   RF.roof_edges([], [[0.0, 0.0], [10.0, 0.0]], nil, nil)[:eave].empty?)
ok('no zmap (a flat roof) still returns its eaves',
   RF.roof_edges([], G_POLY, G_IDS, nil, band_top: 96.0)[:eave].length == 4,
   RF.roof_edges([], G_POLY, G_IDS, nil, band_top: 96.0)[:eave].length)

puts($fails.zero? ? 'rt78 ALL PASS' : "rt78 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

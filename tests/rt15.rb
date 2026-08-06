# encoding: utf-8
# rt15 — RoofManager v2: hip roof from the TRUE footprint (straight skeleton).
# Covers: eave polygon (outer faces + overhang), the skeleton itself on a
# square (pyramid), rectangle (ridge) and L-shape (valley + 6 faces), face
# lifting at the right pitch, level-2 takeover, rebuild and remove.
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
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
RF = InteriorPro::RoofManager

def make_wall(m, id, s, e, level = 1, base = 0.0, height = 96.0)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0]); w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0]);   w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', height)
  w.set_attribute('InteriorPro', 'base_z', base)
  w.set_attribute('InteriorPro', 'level', level)
  w.set_attribute('InteriorPro', 'wall_category', 'exterior')
  w
end

def top_faces(r)
  # sloped tops = roof-colored (undersides are white, edge strips vertical)
  r.entities.grep(Sketchup::Face).select do |f|
    f.material && !f.material.name.include?('ffffff') && f.normal.z.abs > 0.3
  end
end

# ---- the skeleton engine on bare polygons --------------------------------
sq = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]]
arcs = RF.straight_skeleton(sq)
ok('square skeleton: 4 arcs to the center', arcs && arcs.length == 4, arcs && arcs.length)
ok('square arcs all end at (50,50)',
   arcs.all? { |a| (a[1][0] - 50.0).abs < 0.01 && (a[1][1] - 50.0).abs < 0.01 },
   arcs)

rect = [[0.0, 0.0], [300.0, 0.0], [300.0, 100.0], [0.0, 100.0]]
arcs = RF.straight_skeleton(rect)
ok('rectangle skeleton: 4 corner arcs + 1 ridge', arcs && arcs.length == 5, arcs && arcs.length)
ridge = arcs.find { |a| (a[0][1] - 50.0).abs < 0.01 && (a[1][1] - 50.0).abs < 0.01 }
ok('the ridge runs (50,50)-(250,50)',
   ridge && [ridge[0][0], ridge[1][0]].sort.zip([50.0, 250.0]).all? { |a, b| (a - b).abs < 0.01 },
   ridge)

lsh = [[0.0, 0.0], [300.0, 0.0], [300.0, 100.0], [100.0, 100.0], [100.0, 300.0], [0.0, 300.0]]
arcs = RF.straight_skeleton(lsh)
ok('L-shape skeleton returns arcs', !arcs.nil? && arcs.length >= 6, arcs && arcs.length)
cells = RF.roof_cells(lsh, arcs)
ok('L-shape forms 6 roof faces, one per eave edge',
   cells && cells.length == 6 && cells.map { |c| c[:eave] }.sort == [0, 1, 2, 3, 4, 5],
   cells && cells.map { |c| c[:eave] }.sort)

# regression 2026-08-05: the user's real 10-corner plan (three wings) left
# HOLES — facing parallel fronts (a wing corridor) were not annihilated.
zshape = [[12.0, -12.0], [12.0, 759.3019647820727],
          [-272.8018440144747, 759.3019647820727],
          [-272.8018440144747, 1008.5105865585169],
          [-632.4541895758142, 1008.5105865585169],
          [-632.4541895758142, 759.3019647820727],
          [-925.77487003997, 759.3019647820727],
          [-925.77487003997, -647.3379291147412],
          [-478.14504156867997, -647.3379291147412],
          [-478.14504156867997, -12.0]]
za = RF.straight_skeleton(zshape)
zc = za && RF.roof_cells(zshape, za)
ok('10-corner plan: a face for every wall (the holes bug)',
   zc && zc.length == 10 && zc.map { |c| c[:eave] }.sort == (0..9).to_a,
   zc && zc.map { |c| c[:eave] }.sort)

# regression 2026-08-05 (round 2): 4 marked gables with CLICK POINTS on the
# same plan — the gable goes to the strip under each click, all cells
# survive, and no plane climbs past the plausible ridge.
marks4 = [3, 6, 7, 9]
clicks4 = { 3 => [-450.0, 1008.5], 6 => [-925.8, 50.0],
            7 => [-700.0, -647.3], 9 => [-250.0, -12.0] }
p4, _ids4, g4 = RF.split_gable_edges(zshape, Array.new(10) { |i| "w#{i}" }, marks4, clicks4)
sp4 = Array.new(p4.length, 1.0)
g4.each { |i| sp4[i] = 0.0 }
a4 = RF.straight_skeleton(p4, sp4)
c4 = a4 && RF.roof_cells(p4, a4, sp4)
sloped4 = (0...p4.length).select { |i| sp4[i] > 0.5 }
ok('click-placed gables: every sloped wall keeps its face',
   c4 && (sloped4 - c4.map { |c| c[:eave] }).empty? && g4.length == 4,
   c4 && (sloped4 - c4.map { |c| c[:eave] }))
lines4 = p4.each_index.map do |i|
  d = RF.vnorm(RF.vsub(p4[(i + 1) % p4.length], p4[i]))
  { p: p4[i], n: [-d[1], d[0]] }
end
zmax4 = c4.flat_map { |c| c[:pts].map { |p| RF.vdot(lines4[c[:eave]][:n], RF.vsub(p, lines4[c[:eave]][:p])) } }.max
ok('and no plane climbs past half the plan depth', zmax4 < 470.0, zmax4)

# regression 2026-08-05 (round 3, OVER-FRAMING — the user's mock): a
# marked wall gables its WHOLE wing, every wing carries its own full
# gable volume, ridges dive into the parent on 45-degree valleys. The
# user's live plan: main body + top wing + bottom-left wing, 4 marks
# (right wall, top wing top, left wall, bottom wing bottom).
ids5 = Array.new(10) { |i| "w#{i}" }
marks5 = %w[w0 w3 w6 w7]
plan5 = RF.framed_plan(zshape, ids5, marks5, 'hip')
ok('live 4-gable plan decomposes to main + 2 wings',
   plan5 && plan5[:nrects] == 3 && plan5[:wings].length == 2,
   plan5 && plan5[:nrects])
mn = plan5[:main]
ok('the main body rect is found',
   (mn[0] + 925.77487).abs < 0.1 && (mn[1] + 12.0).abs < 0.1 &&
   (mn[2] - 12.0).abs < 0.1 && (mn[3] - 759.30196).abs < 0.1, mn)
ok('main gables east+west (his marks), wings gable their outer ends',
   plan5[:g][:e] && plan5[:g][:w] && !plan5[:g][:n] && !plan5[:g][:s] &&
   plan5[:wings].all? { |w| w[:gabled] }, plan5[:g])
g_grp = Sketchup.active_model.entities.add_group
r5, zmap5 = RF.build_framed_geometry!(g_grp, plan5, 96.0, 1.0 / 3.0, 12.0, nil, nil)
# main ridge: half depth 385.65 at 4:12 + heel -4 => 96 - 4 + 128.55
ok('main ridge at the real house height (~220.6"), nothing higher',
   (r5 - 220.55).abs < 0.1, r5)
faces5 = g_grp.entities.grep(Sketchup::Face)
tris5 = faces5.select { |f| f.pts.length == 3 && f.normal.z.abs < 0.01 }
ok('no white gable triangles (2026-08-05B: open ends)', tris5.length == 0, tris5.length)
ok('6 sloped roof planes', faces5.count { |f| f.normal.z.abs > 0.3 } == 6,
   faces5.count { |f| f.normal.z.abs > 0.3 })
zs5 = faces5.flat_map(&:pts).map(&:z)
ok('no face climbs past the main ridge', zs5.max <= r5 + 0.01, zs5.max)
# wing ridges: top wing half 179.8 -> 151.94; bottom wing half 223.8 -> 166.6
wr5 = plan5[:wings].map { |w| 92.0 + ((w[:rect][2] - w[:rect][0]) / 2.0) / 3.0 }
ok('wing ridges stay below the main ridge', wr5.all? { |z| z < r5 }, wr5)
# the wing ridge dives into the main roof and its penetration node sits
# EXACTLY on the main south plane (a true valley, not a floating edge)
wb = plan5[:wings].find { |w| w[:mouth] == :n } # the bottom-left wing
xr5 = (wb[:rect][0] + wb[:rect][2]) / 2.0
half5 = (wb[:rect][2] - wb[:rect][0]) / 2.0
pen5 = wb[:rect][3] + half5
vp = zmap5[[xr5.round(4), pen5.round(4)]]
main_plane_z = 92.0 + (pen5 - plan5[:main][1]) / 3.0
ok('the wing ridge dives into the main roof on a true valley',
   !vp.nil? && (vp - main_plane_z).abs < 0.05, [vp, main_plane_z])
# rakes get a clean 3-point chain on every gabled end (via max-z zmap)
chain_ok = plan5[:edges].length >= 4
ok('gabled poly edges resolved for bands/rakes', chain_ok, plan5[:edges])

# Gable STYLE with zero clicks (2026-08-05, "make the whole roof gable"):
# every wing end + both main short ends gable automatically.
plan6 = RF.framed_plan(zshape, ids5, [], 'gable')
ok('Gable style, no clicks: main short ends + every wing end gable',
   plan6 && plan6[:g][:e] && plan6[:g][:w] && plan6[:wings].all? { |w| w[:gabled] },
   plan6 && [plan6[:g], plan6[:wings].map { |w| w[:gabled] }])
g_grp6 = Sketchup.active_model.entities.add_group
RF.build_framed_geometry!(g_grp6, plan6, 96.0, 1.0 / 3.0, 12.0, nil, nil)
tris6 = g_grp6.entities.grep(Sketchup::Face).select { |f| f.pts.length == 3 && f.normal.z.abs < 0.01 }
ok('Gable style, no clicks: no white triangles', tris6.length == 0, tris6.length)

# regression 2026-08-05 (the user's THIRD house): wings hang on BOTH axes
# (a leg going south + a bump going east), so single-axis slab cuts left
# a chained wing with no parent and the plan fell back to strip gables.
# grid_rects (maximal rectangles on the vertex grid) finds the intuitive
# main + 2 wings directly on it.
h3 = [[72.0, 950.38], [-979.78, 950.38], [-979.78, -709.84],
      [-475.13, -709.84], [-475.13, -12.0], [72.0, -12.0],
      [72.0, 209.93], [260.05, 209.93], [260.05, 758.77], [72.0, 758.77]]
r3 = RF.grid_rects(h3)
ok('third house: 3 rects on the vertex grid', r3 && r3.length == 3, r3 && r3.length)
plan7 = RF.framed_plan(h3, Array.new(10) { |i| "v#{i}" }, [], 'gable')
ok('third house: main is the big block, 2 wings attach to it',
   plan7 && plan7[:wings].length == 2 &&
   (plan7[:main][0] + 979.78).abs < 0.1 && (plan7[:main][1] + 12.0).abs < 0.1 &&
   (plan7[:main][2] - 72.0).abs < 0.1 && (plan7[:main][3] - 950.38).abs < 0.1,
   plan7 && plan7[:main])
ok('third house: leg mouths north, bump mouths west',
   plan7 && plan7[:wings].map { |w| w[:mouth] }.sort == [:n, :w],
   plan7 && plan7[:wings].map { |w| w[:mouth] })
g_grp7 = Sketchup.active_model.entities.add_group
r7, = RF.build_framed_geometry!(g_grp7, plan7, 96.0, 1.0 / 3.0, 12.0, nil, nil)
tris7 = g_grp7.entities.grep(Sketchup::Face).select { |f| f.pts.length == 3 && f.normal.z.abs < 0.01 }
ok('third house: gable style = no triangles, sane ridge',
   tris7.length == 0 && (r7 - 252.4).abs < 0.1, [tris7.length, r7])

# regression 2026-08-05B (the user's FOURTH house): the main west gable
# plane is half-covered by a wing, so its poly edge holds only part of
# the gable profile - the apex sits OUTSIDE the edge. The rake must
# climb the clipped slope, not collapse to a flat board at the eave.
h4 = [[1168.71, -12.0], [1168.71, 1027.89], [-784.68, 1027.89],
      [-784.68, 457.99], [-12.0, 457.99], [-12.0, -12.0],
      [336.68, -12.0], [336.68, -302.63], [878.36, -302.63], [878.36, -12.0]]
plan8 = RF.framed_plan(h4, Array.new(10) { |i| "u#{i}" }, [], 'gable')
ok('fourth house: main + 2 wings, e+w gabled',
   plan8 && plan8[:wings].length == 2 && plan8[:g][:e] && plan8[:g][:w],
   plan8 && plan8[:g])
ok('fourth house: 4 gable poly edges', plan8[:edges].sort == [0, 2, 4, 7], plan8[:edges])
g_grp8 = Sketchup.active_model.entities.add_group
r8, zmap8 = RF.build_framed_geometry!(g_grp8, plan8, 96.0, 1.0 / 3.0, 12.0, nil, nil)
rk8 = Sketchup.active_model.entities.add_group
RF.build_rake_board!(rk8, h4, 4, zmap8, 8.0)
rkz8 = rk8.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
# eave-tip z is 92; the clipped profile tops out at 92 + 469.99/3 = 248.66
ok('partial gable end: rake climbs the slope (not flat at the eave)',
   !rkz8.empty? && (rkz8.max - 248.66).abs < 0.1, rkz8.max)
# a FULL gable end on the same house keeps its plain 2-segment rake
rk8b = Sketchup.active_model.entities.add_group
RF.build_rake_board!(rk8b, h4, 0, zmap8, 8.0)
zb8 = rk8b.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
ok('full gable end: rake still reaches its apex',
   !zb8.empty? && (zb8.max - (92.0 + 519.945 / 3.0)).abs < 0.1, zb8.max)
# full-profile mode (the live framed path): one rake per end PLANE,
# eave -> apex -> eave, spanning over the covering wing too
rk8f = Sketchup.active_model.entities.add_group
RF.build_rake_board!(rk8f, h4, 4, zmap8, 8.0, full: true)
zf8 = rk8f.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
ok('full-profile rake reaches the apex over the wing',
   !zf8.empty? && (zf8.max - (92.0 + 519.945 / 3.0)).abs < 0.1, zf8.max)
yf8 = rk8f.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:y)
ok('and spans the whole end plane (-12..1027.89)',
   (yf8.min + 12.0).abs < 0.1 && (yf8.max - 1027.89).abs < 0.1,
   [yf8.min, yf8.max])
# with cover clipping (the live path): the rake must END where the wing
# roof starts - at the wing ridge on the end plane (y=742.94) - and
# still reach its own apex (z=265.31)
rk8c = Sketchup.active_model.entities.add_group
cov8 = lambda { |x, y| RF.framed_cover_z(plan8, 92.0, 1.0 / 3.0, x, y, :main) }
RF.build_rake_board!(rk8c, h4, 4, zmap8, 8.0, full: true, cover: cov8)
yc8 = rk8c.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:y)
zc8 = rk8c.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
ok('clipped rake stops at the covering wing (y=742.94, not 1027.89)',
   !yc8.empty? && (yc8.max - 742.94).abs < 1.0, yc8.max)
ok('clipped rake still reaches the apex',
   (zc8.max - 265.31).abs < 0.1, zc8.max)
# a fully exposed end is untouched by the cover clip
rk8d = Sketchup.active_model.entities.add_group
cov8d = lambda { |x, y| RF.framed_cover_z(plan8, 92.0, 1.0 / 3.0, x, y, :main) }
RF.build_rake_board!(rk8d, h4, 0, zmap8, 8.0, full: true, cover: cov8d)
zd8 = rk8d.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
ok('exposed east end keeps its full rake under cover clipping',
   !zd8.empty? && (zd8.max - 265.31).abs < 0.1, zd8.max)
# straddling wing (its mouth spans the main ridge): the dive is fully
# UNDER the main roof - both planes must be clipped at the mouth, so no
# roof edge midpoint sits below the main surface (junk inside), while
# the normal wing (bottom bump) keeps its visible valley wedge.
g_grp9 = Sketchup.active_model.entities.add_group
RF.build_framed_geometry!(g_grp9, plan8, 96.0, 1.0 / 3.0, 12.0, nil, nil)
below9 = g_grp9.entities.grep(Sketchup::Face).flat_map do |f|
  f.pts.each_cons(2).map { |p, q| [(p.x + q.x) / 2.0, (p.y + q.y) / 2.0, (p.z + q.z) / 2.0] }
end.select do |(x, y, z)|
  x > -11.9 && x < 1168.6 && y > -11.9 && y < 1027.8 &&
    z < 92.0 + [y + 12.0, 1027.89 - y].min / 3.0 - 0.1
end
ok('straddling wing clipped: nothing dives under the main surface',
   below9.empty?, below9.length)
wedge9 = g_grp9.entities.grep(Sketchup::Face).flat_map(&:pts)
               .select { |p| (p.x - 607.52).abs < 0.1 && (p.y - 258.84).abs < 0.1 }
ok('normal wing keeps its valley tip diving onto the main slope',
   !wedge9.empty?, wedge9.length)

# ---- no walls: quiet skip -------------------------------------------------
Sketchup.reset_model!
ok('no walls -> no roof, no crash', RF.build_roof!.nil?)
ok('and no roof group left behind', RF.roofs.empty?)

# ---- square building 240x240, walls 96 high, th 6, overhang 12 -----------
# centerline loop 240x240 -> eave polygon 270x270 (th/2 + 12 = 15 out).
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'e1', [0, 0], [240, 0])
make_wall(m, 'e2', [240, 0], [240, 240])
make_wall(m, 'e3', [240, 240], [0, 240])
make_wall(m, 'e4', [0, 240], [0, 0])

ep = RF.eave_polygon(RF.top_walls, 12.0)
poly = ep[:pts]
ok('every eave edge knows its wall', ep[:wall_ids].compact.length == 4, ep[:wall_ids])
xs = poly.map { |p| p[0] }
ys = poly.map { |p| p[1] }
ok('eave polygon = walls outer face + overhang (-15..255)',
   (xs.min + 15.0).abs < 0.1 && (xs.max - 255.0).abs < 0.1 &&
   (ys.min + 15.0).abs < 0.1 && (ys.max - 255.0).abs < 0.1,
   [xs.min, xs.max, ys.min, ys.max])

r = RF.build_roof!
ok('a roof group is created', !r.nil? && r.get_attribute('InteriorPro', 'type') == 'roof')
ok('one roof in the model', RF.roofs.length == 1, RF.roofs.length)
ok('style is hip on level 1', r.get_attribute('InteriorPro', 'roof_style') == 'hip' &&
   r.get_attribute('InteriorPro', 'level') == 1)
ok('eave sits at the wall top 96', (r.get_attribute('InteriorPro', 'eave_z') - 96.0).abs < 0.01,
   r.get_attribute('InteriorPro', 'eave_z'))
# half-span 135 at 4:12 + heel shift (-slope*overhang), zero thickness
apex = 96.0 + 45.0 - 4.0
ok('pyramid apex includes the heel lift',
   (r.get_attribute('InteriorPro', 'ridge_z') - apex).abs < 0.05,
   [r.get_attribute('InteriorPro', 'ridge_z'), apex])
# the no-cut rule: no underside vertex INSIDE the walls goes below the
# wall top; the only dip below 96 is out in the overhang (min = 96 - 4).
unders = r.entities.grep(Sketchup::Face).flat_map(&:pts).select { |p| p.z < 96.0 - 0.01 }
ok('below-ceiling vertices exist only outside the walls (overhang)',
   unders.all? { |p| p.x < 3.01 || p.x > 236.99 || p.y < 3.01 || p.y > 236.99 },
   unders.map { |p| [p.x, p.y, p.z.round(2)] }.first(4))
tops = top_faces(r)
ok('4 sloped faces on a square hip', tops.length == 4, tops.length)
# 4 surface faces + fascia boxes 4x6 + drip boxes 4x6 (both on) = 52
ok('surface + fascia + drip edge = 52 faces',
   r.entities.grep(Sketchup::Face).length == 52, r.entities.grep(Sketchup::Face).length)
ok('faces are painted both sides', r.entities.grep(Sketchup::Face).all? { |f| f.material && f.back_material })
mats = r.entities.grep(Sketchup::Face).map { |f| f.material && f.material.name }.compact.uniq
ok('two colors: roof + fascia/drip', mats.length == 2, mats)
# the roof sits ON the trim: every fascia/drip face tops out at the slab
# underside line (96 - slope*overhang = 92) — nothing pokes past the edge.
trim = r.entities.grep(Sketchup::Face).select do |f|
  f.material.name == 'InteriorPro_Roof_ffffff' && f.pts.all? { |p| p.z <= 92.01 }
end
ok('all 48 trim faces hang below the slab underside (92)', trim.length == 48, trim.length)

# rebuild replaces
RF.build_roof!
ok('rebuild keeps a single roof', RF.roofs.length == 1, RF.roofs.length)

# console overrides reach the surface: pitch 6:12
r6 = RF.build_roof!(pitch: 6)
apex6 = 96.0 + 67.5 - 6.0
ok('pitch override changes the apex',
   (r6.get_attribute('InteriorPro', 'ridge_z') - apex6).abs < 0.05,
   [r6.get_attribute('InteriorPro', 'ridge_z'), apex6])
ok('and is remembered in the model settings', RF.settings[:pitch] == 6.0, RF.settings[:pitch])

# ---- trim off, flat style, no eaves, colors ------------------------------
r_no = RF.build_roof!(fascia: false, drip: false)
ok('fascia+drip off -> bare surface, 4 faces',
   r_no.entities.grep(Sketchup::Face).length == 4, r_no.entities.grep(Sketchup::Face).length)
ok('the choice is remembered', RF.settings[:fascia] == false && RF.settings[:drip] == false)
ok('every surface is white on its underside',
   r_no.entities.grep(Sketchup::Face).all? do |f|
     f.back_material && f.back_material.name == 'InteriorPro_Roof_ffffff' &&
       f.material.name != f.back_material.name
   end)
ok('fascia depth defaults to 8"', RF.settings[:fascia_depth] == 8.0, RF.settings[:fascia_depth])
# heel: at pitch 6 the surface dips to 96 - 0.5*12 = 90 at the eave tip
bmin = r_no.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z).min
ok('surface dips only to 96 - slope*overhang (90)', (bmin - 90.0).abs < 0.05, bmin)

r_fl = RF.build_roof!(style: 'flat')
ok('flat roof: a single surface face (trim still off)',
   r_fl.entities.grep(Sketchup::Face).length == 1, r_fl.entities.grep(Sketchup::Face).length)
flat_top = r_fl.entities.grep(Sketchup::Face).find { |f| f.pts.all? { |p| (p.z - 96.0).abs < 0.01 } }
ok('flat surface sits on the wall tops (96)', !flat_top.nil?)

r_ne = RF.build_roof!(style: 'hip', overhang: 0)
fp0 = r_ne.get_attribute('InteriorPro', 'footprint_xy').each_slice(2).map(&:first)
ok('no eaves: roof ends at the wall outer face (-3..243)',
   (fp0.min + 3.0).abs < 0.1 && (fp0.max - 243.0).abs < 0.1, [fp0.min, fp0.max])

r_col = RF.build_roof!(overhang: 12, fascia: true, drip: true,
                       roof_color: '#aa0000', fascia_color: '#222222')
names = r_col.entities.grep(Sketchup::Face).map { |f| f.material && f.material.name }.compact.uniq.sort
ok('color pickers create the two materials',
   names == ['InteriorPro_Roof_222222', 'InteriorPro_Roof_aa0000'], names)

# ---- gable style: two short ends become vertical rakes -------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'e1', [0, 0], [240, 0])
make_wall(m, 'e2', [240, 0], [240, 120])
make_wall(m, 'e3', [240, 120], [0, 120])
make_wall(m, 'e4', [0, 120], [0, 0])
rg = RF.build_roof!(style: 'gable')
ok('gable roof builds', !rg.nil? && rg.get_attribute('InteriorPro', 'roof_style') == 'gable')
gt = top_faces(rg)
ok('gable = exactly 2 sloped planes', gt.length == 2, gt.length)
# eave poly 270x150; ridge over the middle: z = 96 + heel + 75/3
gz = 96.0 - 4.0 + 25.0
ok('ridge reaches the gable ends at the right height',
   (rg.get_attribute('InteriorPro', 'ridge_z') - gz).abs < 0.05,
   [rg.get_attribute('InteriorPro', 'ridge_z'), gz])
# 2 surfaces + fascia/drip on the 2 sloped eaves (24) + rake boards on the
# 2 gable ends (2 ends x 2 segments x 6 faces = 24)
band_faces = rg.entities.grep(Sketchup::Face).length
ok('gable roof: surfaces + bands + rakes = 50 faces (no triangles)',
   band_faces == 50, band_faces)
tris = rg.entities.grep(Sketchup::Face).select do |f|
  xs3 = f.pts.map(&:x)
  f.pts.length == 3 && (xs3.max - xs3.min).abs < 0.01
end
ok('no white triangles at the gable ends (2026-08-05B)',
   tris.length == 0, tris.length)
rake_top = rg.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z).max
ok('rake boards climb to the ridge', (rake_top - gz).abs < 0.05, rake_top)

# ---- per-wall gable marking (the Gable Ends tool path) -------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'e1', [0, 0], [240, 0])
make_wall(m, 'e2', [240, 0], [240, 240])
make_wall(m, 'e3', [240, 240], [0, 240])
make_wall(m, 'e4', [0, 240], [0, 0])
RF.build_roof!
w1 = m.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == 'e1' }
RF.toggle_gable_wall!(w1)
ok('the wall is marked on the model', RF.gable_wall_ids == ['e1'], RF.gable_wall_ids)
rm1 = RF.roofs.first
ok('roof rebuilt with ONE gable end (3 sloped faces)', top_faces(rm1).length == 3,
   top_faces(rm1).length)
ok('marking works even in Hip style', RF.settings[:style] == 'hip')
# 3 surfaces + fascia 3x6 + drip 3x6 + rake 2x6
ok('one gable end = 51 faces (no triangle)',
   rm1.entities.grep(Sketchup::Face).length == 51,
   rm1.entities.grep(Sketchup::Face).length)
RF.toggle_gable_wall!(w1)
ok('second click un-marks', RF.gable_wall_ids.empty?, RF.gable_wall_ids)
ok('and the roof is a full hip again', top_faces(RF.roofs.first).length == 4,
   top_faces(RF.roofs.first).length)

# stale marks (2026-08-05, the user's split/join walls): an id from before
# a wall split/join points at a wall that no longer exists. It must not
# block the Gable style, and a toggle must prune it from the stored list.
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', ['dead-id'])
m.set_attribute('InteriorPro', 'roof_gable_click_xy', [1e9, 1e9])
r_st = RF.build_roof!(style: 'gable')
ok('a stale mark does not block the Gable style (2 sloped planes)',
   !r_st.nil? && top_faces(r_st).length == 2,
   r_st && top_faces(r_st).length)
w2s = m.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == 'e2' }
RF.toggle_gable_wall!(w2s)
ok('a toggle prunes dead ids from the stored marks', RF.gable_wall_ids == ['e2'], RF.gable_wall_ids)
RF.toggle_gable_wall!(w2s)
RF.build_roof!(style: 'hip')

# ---- gable stops at the mother roof (2026-08-05) -------------------------
# ONE long front wall spans a deep mother (x 0..300) and a shallow attached
# wing (x 300..500). Marking that wall gables ONLY the mother span; the
# wing keeps its slope, with a vertical tear at the junction.
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'front', [0, 0], [500, 0])
make_wall(m, 'wr',    [500, 0], [500, 150])
make_wall(m, 'wt',    [500, 150], [300, 150])
make_wall(m, 'mr',    [300, 150], [300, 300])
make_wall(m, 'mb',    [300, 300], [0, 300])
make_wall(m, 'ml',    [0, 300], [0, 0])
RF.build_roof!
wf = m.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == 'front' }
RF.toggle_gable_wall!(wf)
rz = RF.roofs.first
ok('mother-span gable builds', !rz.nil?)
# over-framing: the footprint is NOT split any more (6 corners as drawn)
fp = rz.get_attribute('InteriorPro', 'footprint_xy')
ok('over-framing keeps the footprint intact (6 corners)', fp.length == 12, fp.length)
ok('6 sloped faces: wing keeps its slope', top_faces(rz).length == 6, top_faces(rz).length)
# mother ridge (deep span) must be HIGHER than the wing ridge
zs2 = top_faces(rz).flat_map(&:pts)
mother_top = zs2.select { |p| p.x < 285 }.map(&:z).max
wing_top   = zs2.select { |p| p.x > 315 }.map(&:z).max
ok('mother roof rises above the attached wing', mother_top > wing_top + 12.0,
   [mother_top, wing_top])

# ---- the dialog drives the same settings ---------------------------------
require './roof_dialog'
InteriorPro::RoofDialog.show
dlg = InteriorPro::RoofDialog.instance_variable_get(:@dialog)
ok('roof dialog registers its callbacks',
   dlg && dlg.callbacks.key?('apply_roof') && dlg.callbacks.key?('remove_roof'))
dlg.callbacks['apply_roof'].call(nil, 'hip', '8', 'true', '18', 'true', '7.25', 'false', '#336699', '#eeeeee')
s = RF.settings
ok('dialog apply saves pitch/overhang/fascia depth/drip/colors',
   s[:pitch] == 8.0 && s[:overhang] == 18.0 && s[:fascia] == true &&
   s[:fascia_depth] == 7.25 && s[:drip] == false &&
   s[:roof_color] == '#336699' && s[:fascia_color] == '#eeeeee', s)
ok('dialog apply rebuilt a single roof', RF.roofs.length == 1, RF.roofs.length)
dlg.callbacks['apply_roof'].call(nil, 'hip', '8', 'false', '18', 'true', '7.25', 'false', '#336699', '#eeeeee')
ok('unchecking eaves in the dialog = overhang 0', RF.settings[:overhang] == 0.0, RF.settings[:overhang])
dlg.callbacks['remove_roof'].call(nil)
ok('dialog remove works', RF.roofs.empty?)
html = InteriorPro::RoofDialog.build_html(RF.settings)
ok('dialog html carries the saved values', html.include?('id="overhang"') && html.include?('#336699'))

# ---- L-shaped building: valleys, one face per wall -----------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'e1', [0, 0], [300, 0])
make_wall(m, 'e2', [300, 0], [300, 120])
make_wall(m, 'e3', [300, 120], [120, 120])
make_wall(m, 'e4', [120, 120], [120, 300])
make_wall(m, 'e5', [120, 300], [0, 300])
make_wall(m, 'e6', [0, 300], [0, 0])
rl = RF.build_roof!
ok('L-shape builds a roof', !rl.nil?)
ok('with 6 sloped faces', rl && top_faces(rl).length == 6, rl && top_faces(rl).length)

# ---- level-2 walls take over ---------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'e1', [0, 0], [240, 0])
make_wall(m, 'e2', [240, 0], [240, 240])
make_wall(m, 'e3', [240, 240], [0, 240])
make_wall(m, 'e4', [0, 240], [0, 0])
make_wall(m, 'u1', [60, 60], [180, 60], 2, 106.0)
make_wall(m, 'u2', [180, 60], [180, 180], 2, 106.0)
make_wall(m, 'u3', [180, 180], [60, 180], 2, 106.0)
make_wall(m, 'u4', [60, 180], [60, 60], 2, 106.0)
ok('top level is 2', RF.top_level == 2, RF.top_level)
r2 = RF.build_roof!
ok('roof belongs to level 2', r2 && r2.get_attribute('InteriorPro', 'level') == 2)
ok('eave rises to the level-2 wall top 202',
   r2 && (r2.get_attribute('InteriorPro', 'eave_z') - 202.0).abs < 0.01,
   r2 && r2.get_attribute('InteriorPro', 'eave_z'))
fp = r2.get_attribute('InteriorPro', 'footprint_xy')
fx = fp.each_slice(2).map(&:first)
ok('footprint shrinks to the level-2 walls +15 (45..195)',
   (fx.min - 45.0).abs < 0.1 && (fx.max - 195.0).abs < 0.1, [fx.min, fx.max])
ok('still a single roof', RF.roofs.length == 1, RF.roofs.length)

# ---- remove --------------------------------------------------------------
nrem = RF.remove_all!
ok('remove erases the roof', nrem == 1 && RF.roofs.empty?, [nrem, RF.roofs.length])
ok('remove again is a quiet 0', RF.remove_all! == 0)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

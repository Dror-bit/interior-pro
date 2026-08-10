# encoding: utf-8
# rt17 — real gable walls (2026-08-08): the wall itself rises into the
# gable triangle. Wall-thick prisms live in the roof group as subgroups
# (part='gable_wall_top'), sit on the WALL line (overhang back from the
# roof edge), start at the wall top and peak at the ridge.
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

def gable_tops(r)
  r.entities.grep(Sketchup::Group).select do |g|
    g.get_attribute('InteriorPro', 'part') == 'gable_wall_top'
  end
end

# ---- chain_regions_above: pure geometry --------------------------------
ch = [[0.0, [0, 0], 92.0], [60.0, [0, 0], 112.0], [120.0, [0, 0], 92.0]]
rg = RF.chain_regions_above(ch, 96.0)
ok('one region over the base line', rg.length == 1, rg)
ok('entry/exit interpolated AT the base',
   rg[0].first[1] == 96.0 && rg[0].last[1] == 96.0 &&
   (rg[0].first[0] - 12.0).abs < 0.01 && (rg[0].last[0] - 108.0).abs < 0.01, rg[0])
ok('the apex survives in the middle', rg[0].any? { |t, z| (z - 112.0).abs < 0.01 }, rg[0])
rg2 = RF.chain_regions_above(ch, 120.0)
ok('a profile entirely below gives nothing', rg2.empty?, rg2)
# a strip profile that STARTS high (junction end) keeps its start point
ch3 = [[0.0, [0, 0], 110.0], [50.0, [0, 0], 112.0], [100.0, [0, 0], 92.0]]
rg3 = RF.chain_regions_above(ch3, 96.0)
ok('a high junction end starts the region at its own height',
   rg3.length == 1 && rg3[0].first == [0.0, 110.0], rg3)

# ---- a gable-style rectangle: both end walls rise ----------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'wS', [0, 0], [300, 0])
make_wall(m, 'wE', [300, 0], [300, 100])
make_wall(m, 'wN', [300, 100], [0, 100])
make_wall(m, 'wW', [0, 100], [0, 0])
r = RF.build_roof!(style: 'gable', pitch: 4, overhang: 12,
                   fascia: false, drip: false)
ok('gable roof builds', !r.nil?)
tops = gable_tops(r)
ok('one gable wall top per end', tops.length == 2, tops.length)
ridge = r.get_attribute('InteriorPro', 'ridge_z').to_f
pts = tops.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
ok('the triangles peak exactly at the ridge',
   (pts.map(&:z).max - ridge).abs < 0.05, [pts.map(&:z).max, ridge])
ok('and sit on the wall top, never below', pts.map(&:z).min >= 96.0 - 0.01,
   pts.map(&:z).min)
xs = pts.map(&:x)
ok('prisms stand on the WALL line, not at the roof edge',
   xs.all? { |x| (x - -3.0).abs < 0.05 || (x - 303.0).abs < 0.05 }, xs.minmax)
ys = pts.map(&:y)
ok('the triangle base spans outer face to outer face of the side walls',
   (ys.min - -3.0).abs < 0.05 && (ys.max - 103.0).abs < 0.05, ys.minmax)
pulls = tops.flat_map { |g| g.entities.grep(Sketchup::Face).map(&:pulled) }.compact
ok('each triangle is push-pulled one wall thickness',
   pulls.length == 2 && pulls.all? { |p| p.abs == 6.0 }, pulls)
faces_per = tops.map { |g| g.entities.grep(Sketchup::Face).length }
ok('one clean face per end - no seam at the apex', faces_per == [1, 1], faces_per)

# ---- roof face counts in the group itself are untouched ----------------
ok('no loose faces added to the roof group by the gable walls',
   r.entities.grep(Sketchup::Face).all? { |f| f.material },
   r.entities.grep(Sketchup::Face).count { |f| f.material.nil? })

# ---- kill switch -------------------------------------------------------
r2 = RF.build_roof!(gable_walls: false)
ok('gable_walls: false builds no wall tops', gable_tops(r2).empty?,
   gable_tops(r2).length)
r3 = RF.build_roof!(gable_walls: true)
ok('and true brings them back', gable_tops(r3).length == 2, gable_tops(r3).length)

# ---- hip style + one marked wall: only that end rises ------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'wS', [0, 0], [300, 0])
we = make_wall(m, 'wE', [300, 0], [300, 100])
make_wall(m, 'wN', [300, 100], [0, 100])
make_wall(m, 'wW', [0, 100], [0, 0])
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', ['wE'])
r4 = RF.build_roof!(style: 'hip', pitch: 4, overhang: 12,
                    fascia: false, drip: false, gable_walls: true)
ok('hip + one mark: exactly one wall rises', gable_tops(r4).length == 1,
   gable_tops(r4).length)
p4 = gable_tops(r4).flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
ok('and it is the marked east wall', p4.map(&:x).all? { |x| (x - 303.0).abs < 0.05 },
   p4.map(&:x).minmax)

# ---- the user's real 10-corner plan (2026-08-09): a low wing covers ----
# part of the south gable end. The wall prism must stop at the wing's
# ridge tip instead of knifing through the wing roof (the "green line").
# Give the roof code a WallTool that can actually paint, like the live one.
InteriorPro.send(:remove_const, :WallTool)
module InteriorPro
  class WallTool
    def self.wall_side_material_names(_w); ['StuccoX', 'GypsumX']; end
    def load_or_create_material(n)
      m = Sketchup.active_model.materials[n]
      m || Sketchup.active_model.materials.add(n)
    end
  end
end

Sketchup.reset_model!
m = Sketchup.active_model
POLY10 = [[12.0, -12.0], [12.0, 707.26], [203.82, 707.26], [203.82, 1352.67],
          [12.0, 1352.67], [12.0, 2263.06], [-1301.25, 2263.06],
          [-1301.25, -1714.33], [-652.11, -1714.33], [-652.11, -12.0]]
def inset10(poly, k)
  n = poly.length
  area = 0.0
  n.times { |i| a = poly[i]; b = poly[(i + 1) % n]; area += a[0] * b[1] - b[0] * a[1] }
  s = area > 0 ? 1.0 : -1.0
  lines = poly.each_index.map do |i|
    a = poly[i]; b = poly[(i + 1) % n]
    d = [b[0] - a[0], b[1] - a[1]]
    len = Math.hypot(*d)
    d = [d[0] / len, d[1] / len]
    [[a[0] - d[1] * s * k, a[1] + d[0] * s * k], d]
  end
  poly.each_index.map do |i|
    (p1, d1) = lines[(i - 1) % n]
    (p2, d2) = lines[i]
    den = d1[0] * d2[1] - d1[1] * d2[0]
    t = ((p2[0] - p1[0]) * d2[1] - (p2[1] - p1[1]) * d2[0]) / den
    [p1[0] + d1[0] * t, p1[1] + d1[1] * t]
  end
end
cl10 = inset10(POLY10, 15.0)
cl10.each_index do |i|
  make_wall(m, "w#{i}", cl10[i], cl10[(i + 1) % cl10.length])
end
ep10 = RF.eave_polygon(m.entities.grep(Sketchup::Group), 12.0)
marks10 = []
ep10[:pts].each_with_index do |p, i|
  q = ep10[:pts][(i + 1) % ep10[:pts].length]
  next unless (p[1] - q[1]).abs < 0.01
  ymid = (p[1] + q[1]) / 2.0
  marks10 << ep10[:wall_ids][i] if (ymid + 12.0).abs < 0.5 || (ymid - 2263.06).abs < 0.5
end
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks10.compact.uniq)
r10 = RF.build_roof!(style: 'hip', pitch: 4, overhang: 12, fascia: true, drip: true)
ok('the 10-corner plan builds', !r10.nil?)
t10 = gable_tops(r10)
ok('both marked ends rise', t10.length == 2, t10.length)
south = t10.find { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:y).max < 100 }
north = (t10 - [south]).first
sx = south.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:x)
sz = south.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
ok('the south wall STOPS at the building outline (x=-652.11), it does not ' \
   'hang over the wing roof', (sx.min - -652.11).abs < 1.0, sx.min)
ok('and still reaches the east corner', (sx.max - 0.0).abs < 0.5, sx.max)
ok('its west edge is the tall wall face against the wing (z up to ~308)',
   (sz.max - 310.94).abs < 1.0, sz.max)
nx = north.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:x)
ok('the clean north end keeps its full triangle',
   (nx.min - -1289.25).abs < 1.5 && (nx.max - 0.0).abs < 0.5, nx.minmax)

# the rake must live on the same span as the wall - never in mid-air
rk = r10.entities.grep(Sketchup::Face).select do |f|
  ys = f.pts.map(&:y)
  ys.min > -25 && ys.max < 5 && f.pts.map(&:z).max - f.pts.map(&:z).min > 2.0
end
rkx = rk.flat_map(&:pts).map(&:x)
ok('the south rake stays inside the outline too (no floating fascia)',
   (rkx.min - -652.9).abs < 1.5, rkx.min)
allf = t10.flat_map { |g| g.entities.grep(Sketchup::Face) }
ok('every gable-wall face is painted on BOTH sides (white-triangle bug)',
   allf.all? { |f| f.material && f.back_material }, allf.count { |f| !f.material || !f.back_material })
ok('painted with the WALL sides, not roof trim',
   allf.all? { |f| %w[StuccoX GypsumX].include?(f.material.name) },
   allf.map { |f| f.material && f.material.name }.uniq)

# ---- the LONG west wall marked (2026-08-09, the user's live case) ------
# Wall w6 runs 3977" down the whole west side: past the main body AND
# past the wing. The main gables to the west (ridge 565"), the wing does
# not. The fascia + wall must follow the real silhouette - up to the
# ridge and back DOWN to the main's own SW corner - and stop there. The
# old upper-envelope rule deleted that corner and bridged the profile
# straight from the ridge out over the wing roof, in mid-air.
Sketchup.reset_model!
m = Sketchup.active_model
cl10b = inset10(POLY10, 15.0)
cl10b.each_index { |i| make_wall(m, "w#{i}", cl10b[i], cl10b[(i + 1) % cl10b.length]) }
ep11 = RF.eave_polygon(m.entities.grep(Sketchup::Group), 12.0)
west = nil
ep11[:pts].each_with_index do |p, i|
  q = ep11[:pts][(i + 1) % ep11[:pts].length]
  west = ep11[:wall_ids][i] if (p[0] + 1301.25).abs < 1.0 && (q[0] + 1301.25).abs < 1.0
end
ok('found the long west wall', !west.nil?, west)
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', [west])
r11 = RF.build_roof!(style: 'hip', pitch: 5, overhang: 12, fascia: true, drip: true)
ok('the long-wall gable builds', !r11.nil?)
t11 = gable_tops(r11)
ok('one wall rises', t11.length == 1, t11.length)
wy = t11.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }.map(&:y)
ok('the wall covers the MAIN body only (y 0..2251), not the wing (y<0)',
   wy.min > -1.0 && (wy.max - 2251.06).abs < 1.5, wy.minmax)
# the RAKE = fascia above the eave band (the band itself lives at 83..91)
rake11 = r11.entities.grep(Sketchup::Face).select do |f|
  f.pts.map(&:x).max < -1295.0 && f.pts.map(&:z).max > 120.0
end
ok('there is a rake on the gabled west line at all', !rake11.empty?)
ry = rake11.flat_map(&:pts).map(&:y)
ok('the fascia stops at the body corner too - nothing hanging over the wing',
   ry.min > -13.0, ry.min)
rz = rake11.flat_map(&:pts).map(&:z)
ok('and it still climbs all the way to the ridge', (rz.max - 564.97).abs < 1.0, rz.max)

puts $fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

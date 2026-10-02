# encoding: utf-8
# rt247 - THE SHINGLES RUN ON TO THE VALLEY (2026-10-02).
#
# His picture, with arrows: where the garage roof carries on past its back
# line up to the valley, "it stops the layer of material (shingles) before
# it reaches the edge of the roof". Measured on his model
# (valley_skin_report.txt): the roof is a slab - a deck, and a top skin
# 0.52" above it that the shingles and the ridge cap sit on - and
# valley_extend! carried only the DECK on. Past y=481.5 there was no face
# at +0.52 at all, and the slab's edge ribbon stood across the roof there.
#
# Pinned: the two triangles are built on the top skin too, where the two
# SKINS meet; the ribbon under them goes; the cap and the tiles are handed
# the TOP faces; no thickness / the kill switch = the deck only, as before.
ENV['REAL_ROOMS'] = '1'
require 'stringio'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

def quiet
  old = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old
end

RF = InteriorPro::RoofManager
def set_const(name, val)
  RF.send(:remove_const, name) if RF.const_defined?(name, false)
  RF.const_set(name, val)
end
set_const(:USE_ROOF_VALLEY, true)
ok('the code is loaded', RF.respond_to?(:valley_carry_tris) && RF.respond_to?(:valley_extend_skin!) && RF.respond_to?(:soften_same_plane_joints!))

# ---- 1. the pure rule, on HIS numbers (valley_skin_report.txt) -----------------
LO_A = [0.25, 0.0, 164.625].freeze     # garage west side
LO_B = [-0.25, 0.0, 68.375].freeze     # garage east side
HI = [0.0, 0.25, -14.125].freeze       # the house's south side
ABUT = [[-146.0, 481.5], [-1.0, 0.0]].freeze   # the back line, from the house wall westward
LEN = 188.5
if RF.respond_to?(:valley_carry_tris)
  tris = RF.valley_carry_tris(LO_A, LO_B, HI, ABUT, LEN)
  ok('two triangles, one per side of the garage roof', tris.length == 2, tris)
  feet = tris.map { |_pl, t| t[0] }.sort
  ok('the legs land on the back line at x = -233.5 and x = -151.5',
     feet.length == 2 && near(feet[0][0], -233.5) && near(feet[1][0], -151.5) && feet.all? { |f| near(f[1], 481.5) }, feet)
  ok('both run to the ridge\'s point on that line and on to the apex (-192.5, 522.5)',
     tris.all? { |_pl, t| near(t[1][0], -192.5) && near(t[1][1], 481.5) && near(t[2][0], -192.5) && near(t[2][1], 522.5) }, tris.map { |_p, t| t })
  dz = RF.slab_lift(0.5, 0.25)
  up = lambda { |pl, d| [pl[0], pl[1], pl[2] + d] }
  skin = RF.valley_carry_tris(up.call(LO_A, dz), up.call(LO_B, dz), up.call(HI, dz), ABUT, LEN)
  ok('two skins of the SAME thickness meet over the very same lines',
     skin.map { |_p, t| t.flatten.map { |v| v.round(3) } } == tris.map { |_p, t| t.flatten.map { |v| v.round(3) } })
  thick = RF.valley_carry_tris(up.call(LO_A, dz), up.call(LO_B, dz), up.call(HI, dz + 1.0), ABUT, LEN)
  ok('a house skin 1" thicker pulls the apex 4" back (1" at 3:12), and the feet in with it',
     thick.length == 2 && near(thick[0][1][2][1], 518.5) && near(thick.map { |_p, t| t[0][0] }.min, -229.5), thick.map { |_p, t| t })
  ok('a leg that lands past the END of the back line gives no triangle',
     RF.valley_carry_tris(LO_A, LO_B, HI, ABUT, 20.0).length == 1)
end

# ---- 2. the builder of the carried faces, on a bare pair of roofs ---------------
def roof(m, fp, gables, eave_z, ridge_z, pitch, oh)
  g = m.entities.add_group
  { 'type' => 'roof', 'footprint_xy' => fp.flatten, 'gable_edges' => gables, 'eave_z' => eave_z,
    'ridge_z' => ridge_z, 'pitch' => pitch, 'overhang_in' => oh, 'level' => 1 }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
HOUSE = [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]].freeze
GAR = [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]].freeze
P = Geom::Point3d
DZ = RF.slab_lift(0.5, 0.25)

def pair_of_roofs
  Sketchup.reset_model!
  m = Sketchup.active_model
  roof(m, HOUSE, [0, 2], 102.0, 145.25, 3.0, 12.0)
  lg = roof(m, GAR, [0, 3], 84.0, 116.5, 3.0, 12.0)
  # the slab's edge ribbon on the back line, deck to skin:
  #   under the east triangle, under the west one, and a piece past the leg
  # (the east one as it stands in HIS model: five corners, its tail cut on the
  # house's deck plane 2.06" past the leg's foot - valley_skin_report.txt)
  e = lg.entities.add_face([P.new(-151.5, 481.5, 106.25), P.new(-192.5, 481.5, 116.5), P.new(-192.5, 481.5, 116.5 + DZ),
                            P.new(-151.5, 481.5, 106.25 + DZ), P.new(-149.44, 481.5, 106.25)])
  w = lg.entities.add_face([P.new(-192.5, 481.5, 116.5), P.new(-233.5, 481.5, 106.25), P.new(-233.5, 481.5, 106.25 + DZ), P.new(-192.5, 481.5, 116.5 + DZ)])
  past = lg.entities.add_face([P.new(-146.0, 481.5, 104.875), P.new(-151.5, 481.5, 106.25), P.new(-151.5, 481.5, 106.25 + DZ), P.new(-146.0, 481.5, 104.875 + DZ)])
  # ...and a board on the same line that is NOT the ribbon (it hangs under the deck)
  board = lg.entities.add_face([P.new(-160.0, 481.5, 100.0), P.new(-190.0, 481.5, 100.0), P.new(-190.0, 481.5, 104.0), P.new(-160.0, 481.5, 104.0)])
  [lg, e, w, past, board]
end

def zs_of(f); f.points.map { |p| p.z.to_f.round(3) }.sort; end

lg, rib_e, rib_w, rib_past, board = pair_of_roofs
log = quiet { @ext = RF.valley_extend!(lg, 'ROOF', 'TRIM', [1], DZ) }
ext = @ext
ok('the planes are carried on', ext && ext[:deck] && ext[:deck].length == 2, ext && ext.keys)
if ext && ext[:deck]
  ok('the DECK triangles are where they always were: 106.25 at the feet, 116.5 on the ridge',
     ext[:deck].all? { |f| zs_of(f) == [106.25, 116.5, 116.5] }, ext[:deck].map { |f| zs_of(f) })
  ok('...facing up, roof colour on top, trim underneath', ext[:deck].all? { |f| f.normal.z > 0 && f.material == 'ROOF' && f.back_material == 'TRIM' })
  ok('the SKIN is carried on too: the same two triangles, 0.52" higher',
     ext[:skin].length == 2 && ext[:skin].all? { |f| zs_of(f) == [(106.25 + DZ).round(3), (116.5 + DZ).round(3), (116.5 + DZ).round(3)] },
     ext[:skin].map { |f| zs_of(f) })
  ok('...over the same plan triangles as the deck',
     ext[:skin].map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2)] }.sort }.sort ==
     ext[:deck].map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2)] }.sort }.sort)
  ok('...facing up, roof colour on BOTH sides (it is the top skin)',
     ext[:skin].all? { |f| f.normal.z > 0 && f.material == 'ROOF' && f.back_material == 'ROOF' })
  ok('the ridge cap and the tiles are handed the TOP faces', ext[:faces] == ext[:skin])
  left = lg.entities.grep(Sketchup::Face)
  ok('the edge ribbon under the two triangles is taken out', !left.include?(rib_e) && !left.include?(rib_w))
  ok('a ribbon that stands wholly past the leg (5.5" of it) is not touched', left.include?(rib_past))
  ok('a board on the same line that hangs UNDER the deck is not touched', left.include?(board))
  ok('the builder says so', log =~ /the top skin carried on too \(2 face\(s\), 2 edge strip\(s\) taken out\)/, log)
end

lg, rib_e, = pair_of_roofs
quiet { @ext = RF.valley_extend!(lg, 'ROOF', 'TRIM', [1], 0.0) }
ok('a roof with no thickness: the deck only, and the ribbon stays',
   @ext && @ext[:skin].empty? && @ext[:faces] == @ext[:deck] && lg.entities.grep(Sketchup::Face).include?(rib_e))
lg, = pair_of_roofs
quiet { @ext = RF.valley_extend!(lg, 'ROOF', 'TRIM', [1]) }
ok('the old four-argument call still means the deck only', @ext && @ext[:skin].empty? && @ext[:faces].length == 2)

# ---- 3. one sheet carrying on is not a line ------------------------------------
FF = Struct.new(:normal, :edges) do
  def valid?; true; end
end
V = Geom::Vector3d
if RF.respond_to?(:soften_same_plane_joints!)
  slope_a = V.new(-0.25, 0.0, 1.0).normalize
  slope_b = V.new(0.25, 0.0, 1.0).normalize
  joint = Sketchup::Edge.new(P.new(0, 0, 0), P.new(1, 0, 0))
  ridge = Sketchup::Edge.new(P.new(0, 0, 0), P.new(0, 1, 0))
  free = Sketchup::Edge.new(P.new(0, 0, 0), P.new(0, 0, 1))
  three = Sketchup::Edge.new(P.new(1, 0, 0), P.new(1, 1, 0))
  tri = FF.new(slope_a, [joint, ridge, free, three])
  main = FF.new(slope_a, [])
  other = FF.new(slope_b, [])
  joint.faces = [tri, main]
  ridge.faces = [tri, other]
  free.faces = [tri]
  three.faces = [tri, main, other]
  n = RF.soften_same_plane_joints!([tri])
  ok('the joint with a face on the same plane is softened', joint.soft? && joint.smooth? && n == 1, n)
  ok('the ridge - two different planes - stays a hard line', !ridge.soft? && !ridge.smooth?)
  ok('a free edge and an edge three faces share are left alone', !free.soft? && !three.soft?)
  ok('a second pass has nothing left to do', RF.soften_same_plane_joints!([tri]).zero?)
end

# ---- 4. the real path, on his walls --------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def build
  Sketchup.reset_model!
  m = Sketchup.active_model
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = m.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  log = quiet do
    RF.build_roof!(level: 1, style: 'gable', pitch: 3.0)
    2.times { RF.roofs.each { |r| RF.build_roof!(replace: r, pitch: 3) } }
  end
  [RF.roof_of_wall_id('gS'), log]
end

# faces of the garage roof standing wholly past its back line, by height over the apex
def past_back(r)
  r.entities.grep(Sketchup::Face).select { |f| f.normal.z.abs > 0.3 && f.points.all? { |p| p.y.to_f > 481.4 } && f.points.any? { |p| p.y.to_f > 500.0 } }
end

gar, log = build
ok('the garage roof was built', !gar.nil?)
if gar
  ridge = gar.get_attribute('InteriorPro', 'ridge_z').to_f
  tops = past_back(gar).map { |f| f.points.map { |p| p.z.to_f }.max.round(2) }.sort
  ok('past the back line the roof now has BOTH sheets: two faces on the deck, two on the skin',
     tops == [ridge.round(2), ridge.round(2), (ridge + DZ).round(2), (ridge + DZ).round(2)], [tops, ridge])
  ok('the builder says so on the real path', log =~ /valley: the top skin carried on too/, log.lines.grep(/skin|carried/))
  ok('the ridge cap is still carried on to the apex', log =~ /of ridge cap carried on to the apex/)
end

# ---- 5. the kill switch ---------------------------------------------------------
set_const(:USE_VALLEY_SKIN, false)
gk, lk = build
if gk
  ridge = gk.get_attribute('InteriorPro', 'ridge_z').to_f
  tops = past_back(gk).map { |f| f.points.map { |p| p.z.to_f }.max.round(2) }
  ok('kill switch: the deck only, as before', tops == [ridge.round(2), ridge.round(2)], tops)
  ok('kill switch: and nothing is said about a skin', lk !~ /top skin carried on/)
end

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

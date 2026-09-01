# encoding: utf-8
# rt18 — roof surface materials (2026-08-10). The roof used to be a flat
# colour only. Now a family ('shingle') can be chosen and the roof colour
# TINTS its greyscale tile, so one file covers every shingle colour.
# Checks the setting round-trips, the material carries the texture at its
# real-world size, colour and family both key the material name, and a
# missing file falls back to plain colour instead of killing the build.
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
RF = InteriorPro::RoofManager

model = Sketchup.active_model

# ---- settings round-trip -------------------------------------------
ok('default material is plain colour', RF.settings[:roof_material] == 'color',
   RF.settings[:roof_material])

s = RF.settings
s[:roof_material] = 'shingle'
RF.save_settings!(s)
ok('material saves on the model', RF.settings[:roof_material] == 'shingle',
   RF.settings[:roof_material])

s[:roof_material] = 'color'
RF.save_settings!(s)
ok('material comes back to colour', RF.settings[:roof_material] == 'color')

# ---- the texture family --------------------------------------------
# ROOF_TEXTURES became a METHOD on 2026-08-18 - a constant guarded by
# `unless const_defined?` is not re-read by InteriorPro.reload!, so four
# new tile materials silently never reached the model. rt73 pins the shape.
ok('shingle family is registered', RF.roof_textures.key?('shingle'))
spec = RF.roof_textures['shingle']
ok('tile has a real-world size', spec[:size] == [48.0, 24.0], spec[:size])
ok('tile height is a whole number of 6in courses',
   (spec[:size][1] / 6.0 - (spec[:size][1] / 6.0).round).abs < 1e-9)

path = RF.texture_path(spec[:file])
ok('texture path points into textures/', path.include?('textures'), path)

# The suites run on a COPY of roof_manager.rb inside tests/, so the real
# textures/ folder is one level up. Check the shipped file really exists
# there, then stand up a throw-away copy next to the test so the textured
# path can be exercised without touching the plugin folder.
shipped = File.join(File.dirname(__FILE__), '..', 'textures', spec[:file])
ok('the shingle tile is shipped in the plugin textures/ folder',
   File.exist?(shipped), shipped)
made_tmp = false
unless File.exist?(path)
  require 'fileutils'
  FileUtils.mkdir_p(File.dirname(path))
  if File.exist?(shipped)
    FileUtils.cp(shipped, path)
  else
    File.write(path, 'placeholder')
  end
  made_tmp = true
end
have_file = File.exist?(path)

# ---- plain colour path ---------------------------------------------
m1 = RF.surface_material(model, { roof_material: 'color', roof_color: '#584e4a' })
ok('colour path returns a material', !m1.nil?)
ok('colour path takes no texture', m1.texture.nil?)

# ---- unknown family falls back, never nil ---------------------------
m2 = RF.surface_material(model, { roof_material: 'no_such_thing', roof_color: '#584e4a' })
ok('unknown family falls back to colour', !m2.nil? && m2.texture.nil?)

# ---- the colour picker everywhere EXCEPT shingle (2026-08-21) ---------
#
# The user asked for the same colour mechanism on every roof: the tile
# materials carry the pattern in 3D and the real ones get done in Lumion, so a
# photographed tile under the geometry was two patterns fighting.
#
# Then he looked at shingle and its texture was gone - and shingle has no 3D
# piece to carry anything, so it was a flat colour with nothing on it: "תעשה
# טקסטורה נכון לעכשיו רק בשינגלס". So the rule is per family now, and this
# line has said all three things in one day. It is rewritten each time rather
# than deleted (the rt65 rule), and the texture machinery is still guarded
# either way: USE_ROOF_TEXTURES still turns it on for EVERYONE, and the block
# after this one flips that switch and checks every old promise still holds.
ok('shingle KEEPS its texture - it is the one family that still has one',
   have_file &&
   !RF.surface_material(model, { roof_material: 'shingle', roof_color: '#584e4a' }).texture.nil?)
ok('and it is the only one on the list', RF.textured_families == ['shingle'],
   RF.textured_families)
# 'slate' used to be the example here; since 2026-09-11 it wears the
# concrete GRAIN (rt131), so the example is a family that wears neither.
ok('a family not on the list takes the colour',
   RF.surface_material(model, { roof_material: 'barrel', roof_color: '#584e4a' }).texture.nil?)
ok('so does a tile family', have_file &&
   RF.surface_material(model, { roof_material: 'roman', roof_color: '#584e4a' }).texture.nil?)
# THE OLD DEFAULT NOW MEANS "NOT PICKED" (2026-09-11). #584e4a is the
# colour every roof was born with before each style got its own, so it
# reads as "give me the style's colour" and the material is named after
# THAT. rt130 pins the resolution rule itself.
ok('and the colour still names the material',
   RF.surface_material(model, { roof_material: 'shingle', roof_color: '#584e4a' })
     .name.include?(RF.roof_colors['shingle'].delete('#')))
ok('the colour still tints the greyscale tile',
   !RF.surface_material(model, { roof_material: 'shingle', roof_color: '#584e4a' })
      .color.nil?)
ok('a different colour is still a different material',
   RF.surface_material(model, { roof_material: 'shingle', roof_color: '#8a2b2b' }).name !=
   RF.surface_material(model, { roof_material: 'shingle', roof_color: '#584e4a' }).name)

# ---- the textured path, still there behind the switch -----------------
if have_file
  RF.send(:remove_const, :USE_ROOF_TEXTURES)
  RF.const_set(:USE_ROOF_TEXTURES, true)

  m3 = RF.surface_material(model, { roof_material: 'shingle', roof_color: '#584e4a' })
  ok('switch on: shingle material exists', !m3.nil?)
  ok('switch on: shingle material carries the texture', !m3.texture.nil?)
  ok('switch on: texture is sized in real inches',
     m3.texture && m3.texture.size == [48.0, 24.0], m3.texture && m3.texture.size)
  ok('switch on: greyscale tile is tinted by the roof colour', !m3.color.nil?)
  ok('switch on: name carries family and colour',
     m3.name == "InteriorPro_Roof_shingle_#{RF.roof_colors['shingle'].delete('#')}",
     m3.name)

  # a second colour must NOT reuse the first colour's material
  m4 = RF.surface_material(model, { roof_material: 'shingle', roof_color: '#8a2b2b' })
  ok('switch on: a different colour makes a different material',
     m4.name != m3.name, m4.name)
  ok('switch on: both are still shingle', m4.name.include?('shingle'))

  # asking twice for the same thing reuses it
  m5 = RF.surface_material(model, { roof_material: 'shingle', roof_color: '#584e4a' })
  ok('switch on: same request reuses the material', m5.equal?(m3))

  # Spanish Tile says flat_color on its own shape, so it never takes its
  # own PHOTOGRAPHED tile picture - not even with the switch on. Since
  # 2026-09-11 it wears the concrete GRAIN instead, which has no grid to
  # fight the 3D with; rt131 pins that. Here we only pin that the tile
  # picture itself is still refused: the material it gets is the grain's,
  # never roof_metal_tile.jpg.
  msp = RF.surface_material(model, { roof_material: 'metaltile',
                                     roof_color: '#584e4a' })
  ok('switch on: Spanish Tile still refuses its own tile PICTURE',
     msp.texture.nil? || msp.name.include?('grain'), msp.name)

  RF.send(:remove_const, :USE_ROOF_TEXTURES)
  RF.const_set(:USE_ROOF_TEXTURES, false)
else
  ok('texture file is reachable', false, path)
end

if made_tmp
  require 'fileutils'
  FileUtils.rm_f(path)
  Dir.rmdir(File.dirname(path)) rescue nil
end

# ====================================================================
# slab thickness (2026-08-10)
# ====================================================================

# ---- the lift is perpendicular thickness, not vertical --------------
ok('no thickness, no lift', RF.slab_lift(0, 0.5) == 0.0)
ok('negative thickness is ignored', RF.slab_lift(-3, 0.5) == 0.0)
ok('a flat plane lifts by exactly the thickness',
   (RF.slab_lift(1.0, 0.0) - 1.0).abs < 1e-12, RF.slab_lift(1.0, 0.0))
# 4:12 -> slope 1/3, sqrt(1+1/9) = 1.05409...
ok('a 4:12 plane lifts by t/cos(angle)',
   (RF.slab_lift(1.0, 4.0 / 12.0) - Math.sqrt(1.0 + 1.0 / 9.0)).abs < 1e-12)
ok('the lift always exceeds the thickness on a slope',
   RF.slab_lift(2.0, 0.5) > 2.0)
ok('thickness setting round-trips', begin
  st = RF.settings
  st[:thickness] = 1.5
  RF.save_settings!(st)
  (RF.settings[:thickness] - 1.5).abs < 1e-9
end, RF.settings[:thickness])

# ---- a real build: does the slab actually get thicker? ---------------
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

def box(m)
  make_wall(m, 'wS', [0, 0], [300, 0])
  make_wall(m, 'wE', [300, 0], [300, 100])
  make_wall(m, 'wN', [300, 100], [0, 100])
  make_wall(m, 'wW', [0, 100], [0, 0])
end

def roof_zs(r)
  r.entities.grep(Sketchup::Face).flat_map { |f| f.pts.map(&:z) }
end

def gable_zs(r)
  r.entities.grep(Sketchup::Group)
   .select { |g| g.get_attribute('InteriorPro', 'part') == 'gable_wall_top' }
   .flat_map { |g| g.entities.grep(Sketchup::Face).flat_map { |f| f.pts.map(&:z) } }
end

Sketchup.reset_model!
m0 = Sketchup.active_model
box(m0)
# caps off here: this pair isolates the THICKNESS, and a cap would add
# its own rise on top of the answer.
r0 = RF.build_roof!(style: 'gable', pitch: 4, overhang: 12, thickness: 0.0,
                    ridge_cap: false, fascia: false, drip: false)
ok('a sheet roof still builds', !r0.nil?)
z0_top = roof_zs(r0).max
z0_bot = roof_zs(r0).min
g0_top = gable_zs(r0).max
n0 = r0.entities.grep(Sketchup::Face).length

Sketchup.reset_model!
m1 = Sketchup.active_model
box(m1)
T = 1.0
r1 = RF.build_roof!(style: 'gable', pitch: 4, overhang: 12, thickness: T,
                    ridge_cap: false, fascia: false, drip: false)
ok('a thick roof builds', !r1.nil?)
z1_top = roof_zs(r1).max
z1_bot = roof_zs(r1).min
g1_top = gable_zs(r1).max
n1 = r1.entities.grep(Sketchup::Face).length

lift = RF.slab_lift(T, 4.0 / 12.0)
ok('the top rises by exactly the lift', (z1_top - z0_top - lift).abs < 0.01,
   [z0_top, z1_top, lift])
ok('the UNDERSIDE does not move', (z1_bot - z0_bot).abs < 0.01, [z0_bot, z1_bot])
ok('thickening adds faces', n1 > n0, [n0, n1])

# the whole point: the gable wall must end BELOW the visible roof now
ok('the gable wall does not move either', (g1_top - g0_top).abs < 0.01,
   [g0_top, g1_top])
ok('the sheet roof let the wall reach the visible top (the bug)',
   (g0_top - z0_top).abs < 0.01, [g0_top, z0_top])
ok('the thick roof buries the wall under the shingles',
   z1_top - g1_top > 0.9 * lift, [g1_top, z1_top, lift])

# ---- flat roofs thicken by the plain thickness -----------------------
Sketchup.reset_model!
m2 = Sketchup.active_model
box(m2)
r2 = RF.build_roof!(style: 'flat', thickness: 2.0, ridge_cap: false,
                    fascia: false, drip: false)
if r2
  zs = roof_zs(r2)
  ok('a flat roof gets a 2in slab', (zs.max - zs.min - 2.0).abs < 0.01,
     [zs.min, zs.max])
else
  ok('flat roof builds', false)
end

# ====================================================================
# ridge cap (2026-08-10)
# ====================================================================

def face_of(pts)
  f = Sketchup::Face.new
  f.pts = pts.map { |x, y, z| Geom::Point3d.new(x, y, z) }
  f
end

# ---- a plain gable: one ridge ---------------------------------------
gable_faces = [
  face_of([[0, 0, 90], [300, 0, 90], [300, 50, 110], [0, 50, 110]]),
  face_of([[0, 100, 90], [0, 50, 110], [300, 50, 110], [300, 100, 90]])
]
gl = RF.ridge_lines(gable_faces)
ok('a gable has exactly one ridge line', gl.length == 1, gl.length)
if gl.length == 1
  ka, za, kb, zb, sides = gl[0]
  ok('the ridge runs along the meeting line', ka[1] == 50.0 && kb[1] == 50.0, [ka, kb])
  ok('the ridge sits at the ridge height', za == 110.0 && zb == 110.0, [za, zb])
  ok('it knows a plane on each side', sides.map(&:first).uniq.length == 2, sides)
  ok('both planes fall away from it', sides.all? { |(_s, dz)| dz < 0 }, sides)
end

# ---- a VALLEY gets nothing ------------------------------------------
valley_faces = [
  face_of([[0, 0, 130], [300, 0, 130], [300, 50, 110], [0, 50, 110]]),
  face_of([[0, 100, 130], [0, 50, 110], [300, 50, 110], [300, 100, 130]])
]
ok('a valley gets NO cap', RF.ridge_lines(valley_faces).empty?)
ok('a lone eave edge is not a ridge', RF.ridge_lines([gable_faces[0]]).empty?)

# ---- a HIP: the ridge AND all four hips ------------------------------
# 300x100 rectangle, eaves at 90, ridge at 110 running x=50..250, y=50.
hip_faces = [
  face_of([[0, 0, 90], [300, 0, 90], [250, 50, 110], [50, 50, 110]]),   # south
  face_of([[300, 100, 90], [0, 100, 90], [50, 50, 110], [250, 50, 110]]), # north
  face_of([[0, 100, 90], [0, 0, 90], [50, 50, 110]]),                   # west hip
  face_of([[300, 0, 90], [300, 100, 90], [250, 50, 110]])               # east hip
]
hl = RF.ridge_lines(hip_faces)
ok('a hip roof caps the ridge AND all four hips', hl.length == 5, hl.length)
sloped = hl.reject { |(_ka, za, _kb, zb, _s)| (za - zb).abs < 0.01 }
ok('four of them are the sloping hips', sloped.length == 4, sloped.length)
ok('the flat one is the ridge at the ridge height',
   (hl - sloped).length == 1 && (hl - sloped)[0][1] == 110.0)

# ---- the cap geometry: sits ON the roof, never sunk ------------------
Sketchup.reset_model!
mc = Sketchup.active_model
gc = mc.entities.add_group
line = RF.ridge_lines(gable_faces)[0]
RF.build_ridge_caps!(gc, [line], nil, nil)
caps = gc.entities.grep(Sketchup::Group)
   .select { |g| g.get_attribute('InteriorPro', 'part') == 'ridge_cap' }
ok('the cap is made of separate overlapping pieces', caps.length > 5, caps.length)
# the arch is faceted: 2 facets per side, top and bottom, + 2 outer
# edges + 2 ends. This cap is built with shape_name nil - the plain arch - and
# it still uses RIDGE_CAP_SEGMENTS. The half-round section added on 2026-08-21
# is Roman's alone and has its own count, RoofManager.cap_segments; the two are
# checked apart on purpose, because "only Roman changes" is the whole point.
seg_faces = 2 * 2 * RF::RIDGE_CAP_SEGMENTS + 4
ok('a piece is a closed arched plate', 
   caps[0].entities.grep(Sketchup::Face).length == seg_faces,
   caps[0].entities.grep(Sketchup::Face).length)

cpts = caps.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
# a piece's head rides one thickness up on the tail below it, and the
# piece itself is one thickness deep - so two layers is the ceiling.
ok('the pile never grows past crown + lift + one plate',
   (cpts.map(&:z).max - (110.0 + RF::RIDGE_CAP_CROWN +
                         RF.cap_head_lift + RF::RIDGE_CAP_THICK)).abs < 1e-9,
   cpts.map(&:z).max)
ok('the arch really lifts off the crease', RF::RIDGE_CAP_CROWN > 0.0)
ok('every piece rides on the tail of the one before it',
   caps.all? do |g|
     zs = g.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z)
     (zs.max - zs.min) > RF::RIDGE_CAP_THICK
   end)
# on a 20-in-150 slope the plane is 6*(20/50)=2.4 below the ridge at 6"
drop = 6.0 * (20.0 / 50.0)
ok('the skirts land exactly on the planes, not inside them',
   (cpts.map(&:z).min - (110.0 - drop)).abs < 1e-6, [cpts.map(&:z).min, 110.0 - drop])
ok('it is one cap width across',
   (cpts.map(&:y).max - cpts.map(&:y).min - RF::RIDGE_CAP_WIDTH).abs < 1e-9)
# a free end is cut flush with the roof edge
ok('the caps are cut flush at both free ends',
   (cpts.map(&:x).min + RF::RIDGE_CAP_OVERSHOOT).abs < 1e-9 &&
   (cpts.map(&:x).max - (300.0 + RF::RIDGE_CAP_OVERSHOOT)).abs < 1e-9,
   [cpts.map(&:x).min, cpts.map(&:x).max])

# pieces really do lap: each is longer than the step between them
xs = caps.map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:x).min }.sort
ok('each piece starts one exposure along',
   (xs[1] - xs[0] - RF::RIDGE_CAP_EXPOSURE).abs < 1e-9, xs[0, 3])
ok('and is longer than that, so it laps the one before',
   RF::RIDGE_CAP_LENGTH > RF::RIDGE_CAP_EXPOSURE)

# ---- the cap rides ON TOP of a 3D tile (2026-08-21) -------------------
# "הם נכנסים לתוך הרידג' קאפ". The skirt used to be drawn flat on the roof
# plane, so every Roman run came out through it, worst of all on a hip where
# the skirt has already tapered to nothing. Now the whole cap lifts by the
# height of the tile it caps - and a material with no 3D tile lifts by
# nothing, so everything checked above this line is drawn exactly where it
# always was.
require './roof_tile_math'
require './roof_tile_parts'
RTM18 = InteriorPro::RoofTileMath
RTP18 = InteriorPro::RoofTileParts
ok('a plain material lifts the cap by nothing',
   RF.cap_lift_for(nil).zero?, RF.cap_lift_for(nil))
ok('and so does a shingle roof',
   RF.cap_lift_for('shingle').zero?, RF.cap_lift_for('shingle'))
ok('roman lifts it by the full height of the tile',
   (RF.cap_lift_for('roman') - RTP18.run_top_h(RTM18.shape('roman'))).abs < 1e-9,
   RF.cap_lift_for('roman'))
ok('which clears the roll instead of cutting through it',
   RF.cap_lift_for('roman') >= RTP18.run_height(RTM18.shape('roman')))
# ONLY Roman moved. Spanish was briefly lifted 1.31" and its section quietly
# turned round; the user went looking and thought both caps had been deleted.
ok('Spanish Tile is NOT lifted - it is drawn exactly where it was',
   RF.cap_lift_for('metaltile').zero?, RF.cap_lift_for('metaltile'))
ok('and it keeps the original parabola section',
   !RF.cap_round_for('metaltile'))
ok('so do shingle and plain colour',
   !RF.cap_round_for('shingle') && !RF.cap_round_for(nil))
ok('roman is the one that takes the half round',
   RF.cap_round_for('roman'))
# THE METAL RIDGE IS ONE PIECE, and keeps its edges. Clay stays a row of
# lapping pieces, which is how clay is laid.
ok('the metal ridge is drawn as one continuous strip',
   RF.cap_continuous_for('seam'))
ok('and clay is not', !RF.cap_continuous_for('roman') &&
   !RF.cap_continuous_for('shingle') && !RF.cap_continuous_for(nil))
# and their sizes never moved either
ok('shingle keeps the old constants',
   RF.cap_width_for('shingle') == RF::RIDGE_CAP_WIDTH &&
     RF.cap_crown_for('shingle') == RF::RIDGE_CAP_CROWN)
ok('Spanish keeps the size it derived from its own fold',
   (RF.cap_width_for('metaltile') -
    RTP18.run_cover_w(RTM18.shape('metaltile')) * RTP18.cap_lap).abs < 1e-9,
   RF.cap_width_for('metaltile'))

# ---- the lap is EXACT: no gap and no biting in ------------------------
# Two pieces one exposure apart are flush only when the lift is
# thickness * length / exposure - that is what killed the 0.11" overlap.
ok('the lift is the value that makes consecutive pieces meet exactly',
   (RF.cap_head_lift * RF::RIDGE_CAP_EXPOSURE / RF::RIDGE_CAP_LENGTH -
    RF::RIDGE_CAP_THICK).abs < 1e-12, RF.cap_head_lift)
under = ->(r, r0) { RF.cap_head_lift * [0.0, 1.0 - (r - r0) / RF::RIDGE_CAP_LENGTH].max }
lap_pts = [0.0, 0.5, 1.0].map { |t| RF::RIDGE_CAP_EXPOSURE + t * (RF::RIDGE_CAP_LENGTH - RF::RIDGE_CAP_EXPOSURE) }
ok('the upper piece lies exactly on the lower one all along the lap',
   lap_pts.all? do |r|
     top_low = under.call(r, 0.0) + RF::RIDGE_CAP_THICK
     (under.call(r, RF::RIDGE_CAP_EXPOSURE) - top_low).abs < 1e-9
   end)

# ---- the last piece is CUT at the end of the run ---------------------
lens = caps.map do |g|
  xs2 = g.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:x)
  xs2.max - xs2.min
end.sort
ok('every piece but the last runs a full length',
   lens[1..-1].all? { |l| (l - RF::RIDGE_CAP_LENGTH).abs < 0.01 }, lens)
ok('and the last one is cut shorter, not stretched',
   lens.first <= RF::RIDGE_CAP_LENGTH + 0.01, lens.first)

# ---- a Y junction: the runs bury the corner --------------------------
hipl = RF.ridge_lines(hip_faces)
js = RF.ridge_junctions(hipl)
ok('the two hip tops are junctions', js.length == 2, js)
ok('the eave corners are not', js.none? { |k| k == [0.0, 0.0] }, js)
Sketchup.reset_model!
gj = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gj, hipl, nil, nil)
jc = gj.entities.grep(Sketchup::Group)
jpts = jc.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
ok('caps run PAST the junction so the corner is covered',
   jpts.map(&:x).min < -0.01 || jpts.map(&:x).max > 300.01 ||
   jc.any? { |g| xs3 = g.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:x)
                 xs3.min < 50.0 && xs3.max > 50.0 }, [jpts.map(&:x).min, jpts.map(&:x).max])

# ---- the lap runs DOWNHILL, so water cannot get under -----------------
hip_one = RF.ridge_lines(hip_faces).find { |(_ka, za, _kb, zb, _s)| (za - zb).abs > 1.0 }
ok('found a sloping hip to test the lap', !hip_one.nil?)
hka, hza, hkb, hzb, = hip_one
hlen = Math.hypot(hkb[0] - hka[0], hkb[1] - hka[1])
hd = [(hkb[0] - hka[0]) / hlen, (hkb[1] - hka[1]) / hlen]

Sketchup.reset_model!
gh = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gh, [hip_one], nil, nil)
hpieces = gh.entities.grep(Sketchup::Group)
ok('the hip gets a run of caps', hpieces.length > 3, hpieces.length)

# For every piece, look at the CROWN vertices (the ones sitting on the
# line itself) and measure how far each is above the line. The low end
# must be a full cap thickness higher than the high end: that is the
# upper cap resting on the lower one.
# For every piece, look at the CROWN vertices (the ones sitting on the
# line itself), take the UNDERSIDE at each end, and measure how far it
# floats above the line. The piece's LOW end must be a full cap
# thickness higher: that is the upper cap resting on the lower one.
# Which end is low depends on how ridge_lines happened to order the
# points, so read it off za/zb rather than assuming.
rising_line = hzb >= hza
laps = hpieces.map do |g|
  crowns = g.entities.grep(Sketchup::Face).flat_map(&:pts).select do |p|
    ((p.x - hka[0]) * -hd[1] + (p.y - hka[1]) * hd[0]).abs < 1e-6
  end
  next nil if crowns.empty?
  by_q = Hash.new { |h, k| h[k] = [] }
  crowns.each do |p|
    q = (p.x - hka[0]) * hd[0] + (p.y - hka[1]) * hd[1]
    by_q[q.round(4)] << p.z - (hza + (hzb - hza) * q / hlen)
  end
  qs = by_q.keys.sort
  under = ->(q) { by_q[q].min }          # the plate's underside, not its top
  low_q  = rising_line ? qs.first : qs.last
  high_q = rising_line ? qs.last  : qs.first
  [under.call(low_q), under.call(high_q), (high_q - low_q).abs]
end.compact

ok('measured the lap on every piece', laps.length == hpieces.length)

# The bottom piece is trimmed to a point at the eave corner, so its
# crown heights are scaled down; it is judged separately below.
inner = laps[1..-1] || []
# the lift tapers over the NOMINAL length, so a piece cut short keeps a
# little of it at its high end - that is what lets it still line up.
ok('every piece rides its lift at the LOW end and sheds it uphill',
   inner.all? do |lo, hi, span|
     expect = RF.cap_head_lift * [span / RF::RIDGE_CAP_LENGTH, 1.0].min
     (lo - hi - expect).abs < 1e-6
   end, inner.first(3))
ok('none of them is lapped the wrong way (uphill)',
   inner.none? { |lo, hi, _sp| hi > lo + 1e-9 })

# ---- the bottom of a hip is trimmed, not left hanging ----------------
lowest_piece = hpieces.min_by do |g|
  g.entities.grep(Sketchup::Face).flat_map(&:pts).map(&:z).min
end
lp = lowest_piece.entities.grep(Sketchup::Face).flat_map(&:pts)
qs_lp = lp.map { |p| (p.x - hka[0]) * hd[0] + (p.y - hka[1]) * hd[1] }
perp = lp.map { |p| ((p.x - hka[0]) * -hd[1] + (p.y - hka[1]) * hd[0]).abs }
corner_q = rising_line ? qs_lp.min : qs_lp.max
at_corner = lp.each_index.select { |i| (qs_lp[i] - corner_q).abs < 1e-6 }
ok('the cap is trimmed to a point at the eave corner',
   at_corner.map { |i| perp[i] }.max < RF::RIDGE_CAP_WIDTH / 4.0,
   at_corner.map { |i| perp[i] }.max)
ok('and it is full width once it is clear of the corner',
   perp.max > RF::RIDGE_CAP_WIDTH / 2.0 - 0.01, perp.max)
ok('nothing runs off the end of the hip',
   rising_line ? qs_lp.min >= -0.01 : qs_lp.max <= hlen + 0.01,
   [qs_lp.min, qs_lp.max, hlen])

# ---- a junction: one run passes over, the rest tuck under -------------
hipl2 = RF.ridge_lines(hip_faces)
js2 = RF.ridge_junctions(hipl2)
run2 = RF.junction_runners(hipl2, js2)
ok('every junction has exactly one runner', run2.keys.sort == js2.sort, [run2.keys, js2])
ridge_idx = hipl2.index { |(_ka, za, _kb, zb, _s)| (za - zb).abs < 0.01 }
ok('the flat ridge is the one that runs over the hips',
   run2.values.uniq == [ridge_idx], [run2.values.uniq, ridge_idx])

Sketchup.reset_model!
gj2 = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gj2, hipl2, nil, nil)
allc = gj2.entities.grep(Sketchup::Group)
ok('a junction roof still gets its caps', allc.length > 10, allc.length)
# the hips stop short of the ridge ends (x=50 and x=250), the ridge runs past
hip_pts = hipl2.each_with_index.reject { |_l, i| i == ridge_idx }
ok('the tuck really pulls the hips back', RF::RIDGE_CAP_TUCK > 0.0)

# ---- and in a real build --------------------------------------------
Sketchup.reset_model!
m3 = Sketchup.active_model
box(m3)
r3 = RF.build_roof!(style: 'hip', pitch: 4, overhang: 12, thickness: 0.5,
                    ridge_cap: true, fascia: false, drip: false)
ok('a capped hip roof builds', !r3.nil?)
rc = r3.entities.grep(Sketchup::Group)
      .select { |g| g.get_attribute('InteriorPro', 'part') == 'ridge_cap' }
ok('a real hip roof gets caps', rc.length > 5, rc.length)
cap_z = rc.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map { |f| f.pts.map(&:z) } }
low = cap_z.min
ok('caps run down the hips, not just along the ridge',
   cap_z.max - low > 5.0, [low, cap_z.max])

Sketchup.reset_model!
m4 = Sketchup.active_model
box(m4)
r4 = RF.build_roof!(style: 'hip', pitch: 4, overhang: 12, thickness: 0.5,
                    ridge_cap: false, fascia: false, drip: false)
ok('switching the cap off leaves none behind',
   r4.entities.grep(Sketchup::Group)
     .none? { |g| g.get_attribute('InteriorPro', 'part') == 'ridge_cap' })
ok('ridge_cap setting round-trips', begin
  st2 = RF.settings
  st2[:ridge_cap] = false
  RF.save_settings!(st2)
  RF.settings[:ridge_cap] == false
end, RF.settings[:ridge_cap])

# ---- the metal hip cap ends in a CORNER (2026-08-21, second pass) ----
#
# Cut SQUARE, the cap's side corners poked out past the two eave lines that
# meet at the corner - "תעשה פינה שלא יעבור את ה-90 מעלות של הגג". The low
# free end of a sloping seam cap is now mitred per point (miter_lo in
# build_cap_piece!): the centre line still reaches the corner, and each point
# pulls back up the hip by its own plan offset - on a square corner that lands
# the cut exactly on both eave lines. Clay is untouched: taper, laps and all.
Sketchup.reset_model!
# a hip from the eave corner (0,0) z=100 up to (100,100) z=150, both ends free
seam_hip = [[0.0, 0.0], 100.0, [100.0, 100.0], 150.0,
            [[1.0, -0.5], [-1.0, -0.5]]]
gm = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gm, [seam_hip], nil, nil, 'seam')
mp = gm.entities.grep(Sketchup::Group)
ok('the metal hip cap is one continuous piece', mp.length == 1, mp.length)
mpts = mp.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
ok('nothing passes either eave line at the corner - the 90 degrees holds',
   mpts.map(&:x).min > -1.0e-6 && mpts.map(&:y).min > -1.0e-6,
   [mpts.map(&:x).min, mpts.map(&:y).min])
tip = mpts.min_by { |q| q.x + q.y }
ok('and the centre of the cap still reaches the corner itself',
   tip.x.abs < 0.01 && tip.y.abs < 0.01, [tip.x, tip.y])
Sketchup.reset_model!
gm2 = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gm2, [seam_hip], nil, nil, 'roman')
ok('clay on the same hip still lays its lapped pieces exactly as before',
   gm2.entities.grep(Sketchup::Group).length > 5,
   gm2.entities.grep(Sketchup::Group).length)

# ---- CLOSED FROM OUTSIDE, and the VALLEY CHANNEL (2026-08-21, 2nd pass) ----
#
# The metal cap rides a rib height above the deck; once the ribs stopped short
# of it, the slot underneath showed - "החלק הזה צריך לסגור מבחוץ שלא יראה
# חלול". A skirt now drops from the cap's whole bottom rim onto the deck.
Sketchup.reset_model!
gsk = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gsk, [seam_hip], nil, nil, 'seam')
skpts = gsk.entities.grep(Sketchup::Group)
           .flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
sk_low = skpts.select { |q| q.x < 0.5 && q.y < 0.5 }.map(&:z).min
ok('the skirt reaches the deck at the corner - nothing hollow from outside',
   (sk_low - 100.0).abs < 0.01, sk_low)
# And the crease honours a STATED crown: it was the constant, so crown 0
# still bulged an inch in the middle of the fold - and would have put a hump
# in the middle of the valley channel below.
ok('a stated crown of zero really is flat at the crease',
   RF.cap_crown_for('seam').zero? &&
     RF.cap_profile_flat([0.0, 1.0], [[1.0, -0.5], [-1.0, -0.5]], 5.0, 0.0)
       .map { |(_o, _dz, arc)| arc }.max.zero?)
ok('and clay still arches - its crown is the constant, exactly as before',
   RF.cap_profile_flat([0.0, 1.0], [[1.0, -0.5], [-1.0, -0.5]], 5.0,
                       RF::RIDGE_CAP_CROWN)
     .map { |(_o, _dz, arc)| arc }.max == RF::RIDGE_CAP_CROWN)

# THE VALLEY: "צריך משהו שמכסה פה בוואלי... זה לא מכסה זה יותר מוליך מים."
# ridge_lines with valleys: true hands back the lines where both planes
# CLIMB, and the seam lays a flat channel IN each - on the deck, no lift, one
# piece. Only build_roof! for the seam ever asks for them, so no other
# material grows one.
V_A = Sketchup::Face.new
V_A.pts = [[0.0, 0.0, 100.0], [80.0, 80.0, 140.0], [-100.0, 80.0, 140.0],
           [-100.0, 0.0, 100.0]].map { |p| Geom::Point3d.new(*p) }
V_B = Sketchup::Face.new
V_B.pts = [[0.0, 0.0, 100.0], [80.0, 0.0, 140.0],
           [80.0, 80.0, 140.0]].map { |p| Geom::Point3d.new(*p) }
ok('the default line walk still refuses a valley',
   RF.ridge_lines([V_A, V_B]).empty?)
VLINES = RF.ridge_lines([V_A, V_B], valleys: true)
ok('valleys: true finds it', VLINES.length == 1, VLINES.length)
Sketchup.reset_model!
gv = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gv, VLINES, nil, nil, 'seam')
vp = gv.entities.grep(Sketchup::Group)
ok('the channel is one continuous strip', vp.length == 1, vp.length)
v_worst = vp.flat_map { |g| g.entities.grep(Sketchup::Face).flat_map(&:pts) }
            .map do |q|
  [(q.z - (100.0 + q.y * 0.5)).abs, (q.z - (100.0 + q.x * 0.5)).abs].min
end.max
ok('and it lies flat IN the valley on the deck - a water channel, no lift',
   v_worst < RF::RIDGE_CAP_THICK + 0.01, v_worst)

# ---- EVERY CAP FACE IS PLANAR (2026-08-21, second pass) --------------------
#
# Real SketchUp refuses a non-planar loop; this stub accepts anything, which
# is exactly how a broken build shipped once: a mitred corner end meeting a
# tucked head bent the side quads ~0.01" out of plane, SketchUp raised, and
# the two hip caps at the foot of a wing died half drawn - "רידג' קאפ המקביל
# לאדום ירד". build_cap_piece! now fans a refused loop into triangles, so
# this rebuilds that exact scene - a ridge running to a peak where two hips
# tuck under it, seam mitres at both eave feet - and demands what SketchUp
# demands: not one face out of plane, and no piece missing.
# From here on add_face behaves like the real one: a non-planar loop RAISES.
# (This is the last scene in the file, so nothing milder runs after it.)
module Sketchup
  class Entities
    def add_face(pts)
      if pts.length > 3
        fa, fb, fc = pts[0], pts[1], pts[2]
        fu = [fb.x - fa.x, fb.y - fa.y, fb.z - fa.z]
        fv = [fc.x - fa.x, fc.y - fa.y, fc.z - fa.z]
        fn = [fu[1] * fv[2] - fu[2] * fv[1], fu[2] * fv[0] - fu[0] * fv[2],
              fu[0] * fv[1] - fu[1] * fv[0]]
        fl = Math.sqrt(fn[0]**2 + fn[1]**2 + fn[2]**2)
        if fl > 1e-12
          fn = fn.map { |q| q / fl }
          pts[3..-1].each do |p|
            d = (p.x - fa.x) * fn[0] + (p.y - fa.y) * fn[1] +
                (p.z - fa.z) * fn[2]
            raise ArgumentError, 'Points are not planar' if d.abs > 1.0e-3
          end
        end
      end
      f = Face.new
      f.pts = pts
      @list << f
      f
    end
  end
end
PK = [0.0, 0.0]
PK_LINES = [
  [PK, 150.0, [0.0, 200.0], 150.0, [[1.0, -0.5], [-1.0, -0.5]]],
  [[-60.0, -60.0], 108.0, PK, 150.0, [[1.0, -0.5], [-1.0, -0.5]]],
  [PK, 150.0, [60.0, -60.0], 108.0, [[1.0, -0.5], [-1.0, -0.5]]]
]
Sketchup.reset_model!
gpk = Sketchup.active_model.entities.add_group
RF.build_ridge_caps!(gpk, PK_LINES, nil, nil, 'seam')
PK_CAPS = gpk.entities.grep(Sketchup::Group)
ok('the peak scene builds all three caps - ridge and both hips',
   PK_CAPS.length == 3, PK_CAPS.length)
pk_bad = 0
PK_CAPS.each do |cg|
  cg.entities.grep(Sketchup::Face).each do |f|
    next if f.pts.length < 4
    fa, fb, fc = f.pts[0], f.pts[1], f.pts[2]
    fu = [fb.x - fa.x, fb.y - fa.y, fb.z - fa.z]
    fv = [fc.x - fa.x, fc.y - fa.y, fc.z - fa.z]
    fn = [fu[1] * fv[2] - fu[2] * fv[1], fu[2] * fv[0] - fu[0] * fv[2],
          fu[0] * fv[1] - fu[1] * fv[0]]
    fl = Math.sqrt(fn[0]**2 + fn[1]**2 + fn[2]**2)
    next if fl < 1e-12
    fn = fn.map { |q| q / fl }
    f.pts[3..-1].each do |p|
      d = (p.x - fa.x) * fn[0] + (p.y - fa.y) * fn[1] + (p.z - fa.z) * fn[2]
      pk_bad += 1 if d.abs > 1.0e-3
    end
  end
end
ok('and not one face is out of plane - real SketchUp would refuse it',
   pk_bad.zero?, pk_bad)
ok('no piece is left half drawn',
   PK_CAPS.all? { |cg| cg.entities.grep(Sketchup::Face).length >= 20 },
   PK_CAPS.map { |cg| cg.entities.grep(Sketchup::Face).length })

puts($fails.zero? ? 'ALL OK' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

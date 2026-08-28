# encoding: utf-8
# rt110 - THE DORMER GETS THE HOUSE'S RIDGE CAP TOO (2026-09-05).
#
# rt109 gave the dormer the house's tiles. Its ridge was still bare: two
# panels running up to a raw line where they meet. He asked for the cap
# with them, twice, in the same sentence.
#
# THE CLAIMS PINNED HERE
# 1. The two dormer slopes are in two SEPARATE sub-groups, so the cap walk
#    has to be handed faces lifted into ONE space. Given that, it finds
#    exactly ONE ridge - the w = 0 line - and not the eaves.
# 2. Placing a gable dormer on a roof stamped 'seam' leaves a ridge_cap
#    group INSIDE the dormer, so it moves and dies with it.
# 3. The cap ends where the ridge line ends: RIDGE_CAP_OVERSHOOT is 0, so
#    it runs neither into the main roof at the back nor past the rake at
#    the front. Boards meet, they never run inside each other.
# 4. A SHED dormer has one slope and no ridge, and gets no cap - the same
#    answer build_roof! gives a shed roof.
# 5. A roof with no tile material lays no cap and does not raise.
#
# Against the old code claims 1-3 fail: place_ridge_cap! does not exist and
# the dormer holds no ridge_cap group at all.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
RM = InteriorPro::RoofManager

Z0    = 100.0
SLOPE = 5.0 / 12.0

SPEC = { z0: Z0, slope: SLOPE, setback: 50.0, width: 50.0, length: 145.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         style: 'gable', base: [0.0, 0.0], along: [1.0, 0.0],
         into: [0.0, 1.0] }.freeze

def build_roof(material)
  Sketchup.reset_model!
  model = Sketchup.active_model
  roof = model.entities.add_group
  roof.set_attribute('InteriorPro', 'type', 'roof')
  roof.set_attribute('InteriorPro', 'roof_material', material) if material
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  roof.entities.add_face([at.call(-400, 0), at.call(400, 0),
                          at.call(400, 400), at.call(-400, 400)])
  roof
end

def roof_subs(dormer)
  dormer.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
  end
end

def caps(dormer)
  dormer.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'ridge_cap'
  end
end

# ---- 1. one ridge, found across two sub-groups ------------------------
roof = build_roof('seam')
d = DM.add_dormer!(roof.entities, SPEC)
ok('a dormer was built', !d.nil?)

subs = roof_subs(d)
faces = subs.map do |s|
  f = DM.top_skin(s)
  tr = s.transformation
  n = f.normal.transform(tr)
  n = n.z < 0 ? n.reverse : n
  (DM.const_defined?(:CapFace) ? DM::CapFace : Struct.new(:pts, :normal)).new(f.vertices.map { |v| v.position.transform(tr) }, n)
end
ok('two slopes to walk', faces.length == 2, faces.length)

lines = RM.ridge_lines(faces)
ok('exactly one ridge line, not the eaves too', lines.length == 1, lines.length)

if lines.length == 1
  ka, _za, kb, = lines[0]
  # the ridge is the w = 0 line: both ends sit on the dormer's centre line
  # this dormer's `along` is +x and its `into` is +y, so it faces down the
  # slope and its ridge climbs in y: one x, 152" of travel.
  ok('the ridge runs along the dormer, not across it',
     (ka[0] - kb[0]).abs < 0.01 && (ka[1] - kb[1]).abs > 100.0,
     [ka, kb])
end

# ---- 2. the cap lands inside the dormer -------------------------------
ok('the dormer carries a ridge cap', caps(d).length.positive?, caps(d).length)

# ---- 3. it ends where the ridge ends, no overshoot --------------------
ok('the cap does not overshoot its ridge line',
   RM::RIDGE_CAP_OVERSHOOT.zero?, RM::RIDGE_CAP_OVERSHOOT)

if lines.length == 1
  ka, _za, kb, = lines[0]
  len = Math.hypot(kb[0] - ka[0], kb[1] - ka[1])
  dx = (kb[0] - ka[0]) / len
  dy = (kb[1] - ka[1]) / len
  ts = caps(d).flat_map { |c| c.entities.grep(Sketchup::Face) }
              .flat_map { |f| f.vertices.map { |v| v.position } }
              .map { |q| ((q.x.to_f - ka[0]) * dx) + ((q.y.to_f - ka[1]) * dy) }
  ok('the cap spans the ridge and no more',
     !ts.empty? && (ts.max - ts.min) <= len + 0.01,
     ts.empty? ? 'no cap faces' : [(ts.max - ts.min).round(2), len.round(2)])
  ok('and it starts at the ridge line, not before it',
     !ts.empty? && ts.min >= -0.01 && ts.max <= len + 0.01,
     ts.empty? ? 'no cap faces' : [ts.min.round(2), ts.max.round(2)])
end

# ---- 3b. AND EVERY CORNER OF IT IS CARRIED (2026-09-05, he circled the
# back end: "תראה שאחת הקצוות יוצאות החוצה"). The two slopes are trapezoids
# that close to nothing at the back, so a cap laid along the whole ridge
# hangs its last few inches over thin air - 3.54" out in his own model.
polys = roof_subs(d).map do |sb|
  f = DM.top_skin(sb)
  tr = sb.transformation
  f.vertices.map { |v| p = v.position.transform(tr); [p.x.to_f, p.y.to_f] }
end
out = caps(d).flat_map { |c| c.entities.grep(Sketchup::Face) }
             .flat_map { |f| f.vertices.map { |v| v.position } }
             .reject do |p|
  polys.any? { |pl| InteriorPro::RoofTileMath.poly_contains?(pl, [p.x.to_f, p.y.to_f]) }
end
ok('no corner of the cap hangs off the dormer roof',
   out.empty?, out.first(3).map { |p| [p.x.round(2), p.y.round(2)] })

# and it was not simply thrown away to achieve that
if lines.length == 1
  ka, _za, kb, = lines[0]
  full = Math.hypot(kb[0] - ka[0], kb[1] - ka[1])
  ts = caps(d).flat_map { |c| c.entities.grep(Sketchup::Face) }
              .flat_map { |f| f.vertices.map { |v| v.position } }
              .map { |q| ((q.x.to_f - ka[0]) * ((kb[0] - ka[0]) / full)) +
                         ((q.y.to_f - ka[1]) * ((kb[1] - ka[1]) / full)) }
  ok('the cap still covers most of the ridge',
     !ts.empty? && (ts.max - ts.min) > full * 0.9,
     ts.empty? ? 'none' : [(ts.max - ts.min).round(2), full.round(2)])
end

# ---- 4. a shed has no ridge -------------------------------------------
roof2 = build_roof('seam')
d2 = DM.add_dormer!(roof2.entities, SPEC.merge(style: 'shed'))
ok('a shed dormer was built', !d2.nil?)
ok('and gets no ridge cap', caps(d2).empty?, caps(d2).length)

# ---- 4a. ONLY A DIE-IN END IS PULLED BACK (2026-09-05).
# The first cut of the trim walked BOTH ends in and ate the caps on a hip
# dormer's two diagonals: "שהיפ הוא לא יושב עד הסופ באלכסונים". A hip's
# lower end is the dormer's own outer corner, where a cap belongs; only the
# end that lands ON the house roof gets pulled back.
if lines.length == 1
  ka, za, kb, zb, = lines[0]
  a_in = DM.die_in?(d, ka, za)
  b_in = DM.die_in?(d, kb, zb)
  ok('exactly one end of the gable ridge dies into the house roof',
     [a_in, b_in].count(true) == 1, [a_in, b_in])
end

hp = build_roof('seam')
dh = DM.add_dormer!(hp.entities, SPEC.merge(style: 'hip'))
ok('a hip dormer was built', !dh.nil?)
if dh
  hsubs = dh.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
  end
  hf = hsubs.map do |s|
    f = DM.top_skin(s)
    tr = s.transformation
    n = f.normal.transform(tr)
    n = n.z < 0 ? n.reverse : n
    DM::CapFace.new(f.vertices.map { |v| v.position.transform(tr) }, n)
  end
  raw = RM.ridge_lines(hf)
  cut = DM.trim_cap_lines(dh, raw, hf, DM.cap_half(RM, 'seam'))
  ok('a hip has more than one cap line', raw.length > 1, raw.length)
  moved = raw.each_index.count do |i|
    raw[i][0] != cut[i][0] || raw[i][2] != cut[i][2]
  end
  kept = raw.each_index.count do |i|
    !DM.die_in?(dh, raw[i][0], raw[i][1]) && raw[i][0] == cut[i][0]
  end
  ok('every end that is NOT a die-in is left exactly where it was',
     kept == raw.each_index.count { |i| !DM.die_in?(dh, raw[i][0], raw[i][1]) },
     [kept, moved])
end

# ---- 4a2. AND NO PART OF A CAP SINKS INTO THE ROOF (2026-09-05).
# Where two caps meet, the covered one ducks so it passes beneath the other.
# A LIFTED metal cap carries a skirt the full height of its lift, so its rim
# already touches the roof and there is no room to duck: the same 0.45" a
# clay cap has 4" of air for pushed the seam's skirt into the deck. Measured
# on his hip dormer, both diagonals 0.45" below the surface.
if dh
  def plane_z_of(cf, x, y)
    n = cf.normal
    return nil if n.z.abs < 1.0e-9
    p0 = cf.pts[0]
    p0.z.to_f - (((n.x * (x - p0.x)) + (n.y * (y - p0.y))) / n.z)
  end

  def over?(cf, x, y)
    InteriorPro::RoofTileMath.poly_contains?(
      cf.pts.map { |p| [p.x.to_f, p.y.to_f] }, [x, y]
    )
  end

  worst = nil
  caps(dh).each do |c|
    c.entities.grep(Sketchup::Face).each do |f|
      f.vertices.each do |v|
        p = v.position.transform(c.transformation)
        zr = nil
        hf.each do |cf|
          next unless over?(cf, p.x.to_f, p.y.to_f)
          z = plane_z_of(cf, p.x.to_f, p.y.to_f)
          zr = z if z && (zr.nil? || z > zr)
        end
        next if zr.nil?
        d = p.z.to_f - zr
        worst = d if worst.nil? || d < worst
      end
    end
  end
  ok('a hip dormer has caps with geometry to measure', !worst.nil?, worst)
  ok('no part of a cap sinks below the roof it lies on',
     !worst.nil? && worst >= -0.01, worst)
end

# ---- 4b. A SHINGLE DORMER GETS THE CAP TOO (2026-09-05).
# "בגגון בשינגלס תוסיף רידג׳ קאפ". Shingles are drawn by the texture - there
# is no field to lay - and the cap sat behind the same guard as the field,
# so a shingle dormer came back with a bare ridge while the house's own
# shingle roof wears one.
sh = build_roof('shingle')
ok('shingles have no field to lay',
   !InteriorPro::RoofTileMath.runs?('shingle'))
ds = DM.add_dormer!(sh.entities, SPEC)
ok('a dormer was built on the shingle roof', !ds.nil?)
ok('and it still gets its ridge cap', caps(ds).length.positive?, caps(ds).length)
nofield = roof_subs(ds).map { |s| s.entities.grep(Sketchup::ComponentInstance).length }
ok('and no field pieces were invented for it', nofield.all?(&:zero?), nofield)

# ---- 5. a bare roof lays nothing --------------------------------------
roof3 = build_roof(nil)
d3 = DM.add_dormer!(roof3.entities, SPEC)
ok('a dormer on a bare roof still builds', !d3.nil?)
ok('and gets no ridge cap', caps(d3).empty?, caps(d3).length)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"

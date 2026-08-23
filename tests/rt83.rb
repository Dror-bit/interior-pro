# encoding: utf-8
# rt83 - THE FLAT TILE (2026-08-21c).
#
# WHAT WAS WRONG
# 'slate' was in the menu, had a texture, had a label - and built no geometry
# at all. `runs?` reads `scallop`, which means "the profile is curved", and a
# flat tile is not curved, so place_runs! returned an empty list and the roof
# came out as a smooth coloured deck with a photograph painted on it. That is
# the identical hole standing seam sat in until 2026-08-21, and this suite is
# here so a third material cannot fall into it unnoticed: the way in is
# `run_flat`, and it is tested as a THIRD way in beside scallop and run_seam.
#
# THE CLAIM THIS SUITE EXISTS TO PIN, and it is the user's own question:
# "האם הם יושבים אחד על השני?"
#
# They do. Every tile's NOSE is raised by one thickness and its HEAD lies flat
# on the deck, so a tile rests on the one below it AND nothing stacks - course
# twenty is no higher off the deck than course one. Get that wrong in either
# direction and the roof is either a tiled floor (no shadow line) or a wedge
# that climbs to the ridge. Both are checked below, by measurement.
#
# AND THE CAP DID NOT MOVE. Adding run_* to a material re-derives cap_w and
# cap_crown from it - that is the trap cap_crown_stated? was written for, and
# it would have swollen this cap from 6.9" to 14.95" behind the user's back.
# He asked for tiles, not for a new cap. The numbers are pinned here.
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def close(a, b, tol = 1e-6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RTM   = InteriorPro::RoofTileMath
RTP   = InteriorPro::RoofTileParts
PLACE = InteriorPro::RoofTilePlace
S     = RTM.shape('slate')

# ------------------------------------------------------------- the material

ok('the flat tile is described', !S.nil?)
ok('it is 13 x 13 - the size the user approved off his photograph',
   close(S[:tile_w].to_f, 13.0) && close(S[:exposure].to_f, 13.0),
   [S[:tile_w], S[:exposure]])
# STAGGERED. Built straight first, off the photograph; the user looked at it
# and asked for the broken bond by name - "אני רוצה שזה יהיה סטאגרן". The flag
# was already here and had never had a builder behind it, which is exactly why
# the first build ignored it. Measured on the real layout further down.
ok('every other course is shifted half a tile', S[:stagger] == true, S[:stagger])
ok('it is still dead flat - nothing about it is curved',
   S[:scallop].to_f.zero?)
ok('and it gets its 3D through run_flat, not through scallop',
   RTM.runs?('slate') && RTM.run_flat?('slate'))
ok('it is pressed into courses, because each tile laps the one below',
   RTM.run_courses?('slate'))

# nothing else became flat
ok('no other material is flat',
   RTM.shapes.keys.select { |k| RTM.run_flat?(k) } == ['slate'],
   RTM.shapes.keys.select { |k| RTM.run_flat?(k) })
ok('roman is still a pipe and seam is still a rib',
   RTM.runs?('roman') && !RTM.run_flat?('roman') &&
   RTM.seam?('seam') && !RTM.run_flat?('seam'))

# ---------------------------------------------------------------- the piece

M = Sketchup.active_model
D = RTP.flat_tile(M, 'slate')
ok('the piece builds', !D.nil?)
# the stub's Face keeps its corners in `points` (rt18's strict harness
# names them `pts` - they are two different classes, do not mix them up)
FACES = D.entities.grep(Sketchup::Face)
def fpts(f); f.points; end
ok('six faces: three bands of top, the nose, and two sides',
   FACES.length == 6, FACES.length)

# CACHED. One definition for the whole roof is the entire cost argument.
before = D.entities.length
again = RTP.flat_tile(M, 'slate')
ok('asking twice returns the SAME definition', again.equal?(D))
ok('...and builds nothing the second time', D.entities.length == before,
   [before, D.entities.length])

ok('only the flat material gets one', RTP.flat_tile(M, 'roman').nil? &&
   RTP.flat_tile(M, 'seam').nil?)

# EVERY FACE PLANAR. The stub accepts a bent face and real SketchUp throws
# ArgumentError - the lesson of 2026-08-21b, §0 of that handoff. Measured the
# same way the strict harness at the end of rt18 measures it.
bad = 0
FACES.each do |f|
  pts = fpts(f)
  next if pts.length < 4
  a, b, c = pts[0], pts[1], pts[2]
  u = [b.x - a.x, b.y - a.y, b.z - a.z]
  v = [c.x - a.x, c.y - a.y, c.z - a.z]
  n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2],
       u[0] * v[1] - u[1] * v[0]]
  l = Math.sqrt(n[0]**2 + n[1]**2 + n[2]**2)
  next if l < 1e-12
  n = n.map { |q| q / l }
  pts[3..-1].each do |p|
    d = (p.x - a.x) * n[0] + (p.y - a.y) * n[1] + (p.z - a.z) * n[2]
    bad += 1 if d.abs > 1.0e-3
  end
end
ok('not one face is out of plane - real SketchUp would refuse it', bad.zero?, bad)

# ------------------------------------------- DO THEY SIT ON EACH OTHER?

H = RTP.run_height(S)
ok('the tile is 0.7" thick', close(H, 0.7, 1e-9), H)

zs = FACES.flat_map { |f| fpts(f).map { |p| p.z.to_f } }
ok('nothing is thicker than one tile', zs.max <= H + 1e-9, zs.max)
ok('and nothing hangs below the deck', zs.min >= -1e-9, zs.min)

# The nose end (y = 0) is UP one thickness: that is what rests on the tile
# below, and what casts the shadow line at every course.
nose_z = FACES.flat_map { |f| fpts(f).select { |p| close(p.y.to_f, 0.0) } }
              .map { |p| p.z.to_f }
ok('the NOSE is raised a full thickness - it rests on the tile below',
   close(nose_z.max, H, 1e-9), nose_z.max)

# The head end (y = 1, the far end of the unit-long piece) is DOWN on the deck.
# This is the half that stops the roof stacking: every head is at zero, so
# course twenty sits exactly as high as course one.
head_z = FACES.flat_map { |f| fpts(f).select { |p| close(p.y.to_f, 1.0) } }
              .map { |p| p.z.to_f }
ok('the HEAD lies flat on the deck, so nothing stacks up the slope',
   !head_z.empty? && close(head_z.max, 0.0, 1e-9), head_z)

# There IS a nose face - a vertical one at y = 0 spanning the full thickness.
nose_face = FACES.find do |f|
  fpts(f).all? { |p| close(p.y.to_f, 0.0) }
end
ok('the nose is a real face, not just a step in the top surface',
   !nose_face.nil?)
ok('...and it is the full thickness tall',
   !nose_face.nil? &&
   close(fpts(nose_face).map { |p| p.z.to_f }.max -
         fpts(nose_face).map { |p| p.z.to_f }.min, H, 1e-9))

# NOT SOFTENED. Softening the nose/top edge blends the shading across it and
# the shadow line - the only reason this piece exists - disappears.
ok('a flat tile is NOT softened', !RTP.soften_run?(S))
ok('...but clay still is', RTP.soften_run?(RTM.shape('roman')))

# There is a joint down each side, or the roof reads as one poured slab.
xs = FACES.flat_map { |f| fpts(f).map { |p| p.x.to_f } }
ok('the tile is narrower than its pitch - there is a joint each side',
   (xs.max - xs.min) < RTP.run_pitch(S) - 1e-9,
   [xs.max - xs.min, RTP.run_pitch(S)])

# ------------------------------------------------- THE CAP DID NOT MOVE

ok('cap_w is still 6.9 - exactly what the old derivation gave',
   close(RTP.cap_w(S), 6.9, 1e-9), RTP.cap_w(S))
ok('cap_crown is still 2.622, ditto',
   close(RTP.cap_crown(S), 2.622, 1e-9), RTP.cap_crown(S))
ok('both are STATED, so changing the tile can never move them again',
   S.key?(:cap_w) && RTP.cap_crown_stated?(S))
ok('the cap is not round - that was not asked for and did not change',
   !RTP.cap_round?(S))
# The LIFT does follow the tile, and must: a cap floating at the old 2.28"
# over a 0.7" tile would show daylight underneath it.
ok('the cap now rides at tile height, not at the old 2.28"',
   close(RTP.run_top_h(S), H, 1e-9), RTP.run_top_h(S))
ok('the runs stop under the cap', close(RTP.ridge_setback(S), 3.45, 1e-9),
   RTP.ridge_setback(S))
ok('...which is half the cap, so the cut end hides beneath it',
   close(RTP.ridge_setback(S), RTP.cap_w(S) / 2.0, 0.01))

# nobody else's cap moved
ok("roman's stated cap is untouched",
   close(RTP.cap_w(RTM.shape('roman')), 13.0) &&
   close(RTP.cap_crown(RTM.shape('roman')), 1.42))
ok("the seam's folded plate is untouched",
   close(RTP.cap_w(RTM.shape('seam')), 10.0) &&
   RTP.cap_crown(RTM.shape('seam')).zero?)

# --------------------------------------------------------- on a real plane

NRM  = [0.0, -1.0 / 3.0, 1.0]
FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
        [200.0, 90.0, 130.0], [0.0, 90.0, 130.0]].freeze

class StubFace
  attr_reader :pts
  def initialize(pts, nrm)
    @pts = pts.map { |p| Geom::Point3d.new(p[0], p[1], p[2]) }
    @nrm = Geom::Vector3d.new(nrm[0], nrm[1], nrm[2])
  end

  def normal
    @nrm
  end
end

$tagged = []
module InteriorPro
  def self.assign_tag(entity, name)
    $tagged << [entity, name]
    true
  end
end

PLANES = PLACE.planes_from_faces([StubFace.new(FACE, NRM)])
SLOTS  = PLACE.run_slots(PLANES, 'slate')

ok('a 200" x 95" plane gets a GRID of tiles, not one run per column',
   SLOTS.length > 100, SLOTS.length)

# ------------------------------------------------ THE STAGGER, MEASURED
#
# Back-project every slot into the plane's own u/v so the layout can be read
# directly: which course it is in, and where across the slope it sits.
PU = RTM.plane_uv(PLANES[0][:points], PLANES[0][:n])
E  = S[:exposure].to_f
P  = RTP.run_pitch(S)
rows = Hash.new { |h, k| h[k] = [] }
SLOTS.each do |s|
  d = [s[:origin][0] - PU[:origin][0], s[:origin][1] - PU[:origin][1],
       s[:origin][2] - PU[:origin][2]]
  u = d[0] * PU[:u][0] + d[1] * PU[:u][1] + d[2] * PU[:u][2]
  v = d[0] * PU[:v][0] + d[1] * PU[:v][1] + d[2] * PU[:v][2]
  # the eave course starts at -overhang; round it back onto its own course
  k = ((v + RTP.eave_overhang) / E).round
  rows[k] << u
end
ok('the courses land on the plane grid, one per exposure',
   rows.keys.sort == (0...rows.keys.length).to_a, rows.keys.sort)

# Every column in one course is a whole pitch from the next - no drift.
gaps = rows[0].sort.each_cons(2).map { |a, b| (b - a).round(4) }.uniq
ok('inside one course the columns are exactly one pitch apart',
   gaps.length == 1 && close(gaps[0], P, 1e-6), gaps)

# ...and course 1 is offset from course 0 by HALF a pitch. This is the whole
# ask. Compare the two courses' offsets modulo the pitch.
off0 = rows[0].min % P
off1 = rows[1].min % P
ok('course 1 is shifted half a tile against course 0',
   close(((off1 - off0) % P), P / 2.0, 1e-6), [off0, off1, P])
ok('course 2 is back in line with course 0',
   close(((rows[2].min % P) - off0) % P, 0.0, 1e-6),
   [rows[2].min % P, off0])

ok('every piece is about one course long',
   SLOTS.all? { |s| s[:length] > 3.0 && s[:length] < 20.0 },
   [SLOTS.map { |s| s[:length] }.min.round(2),
    SLOTS.map { |s| s[:length] }.max.round(2)])
# The bottom course hangs over the eave like a real tile; the ones above it
# start where the course below ended and must NOT grow a nose out of nothing.
low = SLOTS.select { |s| close(s[:origin][2].to_f, 100.0, 1.5) }
ok('the bottom course hangs past the eave',
   low.any? { |s| s[:length] > RTM.shape('slate')[:exposure].to_f },
   low.map { |s| s[:length].round(2) }.uniq)

Sketchup.reset_model!
model = Sketchup.active_model
grp = model.entities.add_group
made = PLACE.place_runs!(grp, PLACE.planes_from_faces([StubFace.new(FACE, NRM)]),
                         'slate', model: model)
ok('they are actually placed', made > 100, made)
inst = grp.entities.grep(Sketchup::ComponentInstance)
ok('one instance each, all of ONE definition',
   inst.length == made && inst.map { |i| i.definition.name }.uniq.length == 1,
   inst.map { |i| i.definition.name }.uniq)
ok('and that definition is the FLAT tile, not the folded metal sheet',
   inst.first.definition.name.include?('IP_TileFlat'),
   inst.first.definition.name)

# -------------------------------------------- the old eave bar is skipped
#
# The flat tile's own bottom course IS the eave, so the separate 1.2"-tall
# eave piece would show as a doubled edge among 0.7" tiles.
mgr = ['../roof_manager.rb', './roof_manager.rb'].find { |f| File.file?(f) }
src = File.read(mgr, encoding: 'UTF-8')
ok('roof_manager skips the separate eave piece for a flat tile',
   src.include?('run_flat?(s[:roof_material])'), mgr)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

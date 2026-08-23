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
# A WEDGE since the third pass - "אני מעדיף שצורת הרעף תהיה יותר משולשית":
# one sloping top from the nose down to nothing at the head, the nose, and
# two side triangles. The stepped plate (nose + ramp + flat field, six faces)
# is what this replaced.
ok('four faces: the sloping top, the nose, and two side triangles',
   FACES.length == 4, FACES.length)
side = FACES.select { |f| fpts(f).map { |p| p.x.to_f }.uniq.length == 1 }
ok('the two sides really are triangles',
   side.length == 2 && side.all? { |f| fpts(f).length == 3 },
   side.map { |f| fpts(f).length })
top = FACES.find { |f| fpts(f).length == 4 && fpts(f).any? { |p| p.z.to_f > 1e-6 } && fpts(f).map { |p| p.x.to_f }.uniq.length == 2 && !fpts(f).all? { |p| p.y.to_f.abs < 1e-6 } }
ok('the top is ONE straight slope - nose height at the front, zero at the head',
   !top.nil? &&
   fpts(top).select { |p| p.y.to_f < 1e-6 }.all? { |p| (p.z.to_f - 0.7).abs < 1e-9 } &&
   fpts(top).select { |p| p.y.to_f > 0.5 }.all? { |p| p.z.to_f.abs < 1e-9 })

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
# 1.0 is the user's own number, in two steps: "מקסימום 2" (from the derived
# 2.622), then "תוריד את הגובה שלו ב-1 אחד נוסף".
ok('cap_crown is 1.0 - his number, twice corrected',
   close(RTP.cap_crown(S), 1.0, 1e-9), RTP.cap_crown(S))
ok('both are STATED, so changing the tile can never move them again',
   S.key?(:cap_w) && RTP.cap_crown_stated?(S))
ok('the cap is not round - that was not asked for and did not change',
   !RTP.cap_round?(S))
# The LIFT does follow the tile, and must: a cap floating at the old 2.28"
# over a 0.7" tile would show daylight underneath it.
ok('the cap now rides at tile height, not at the old 2.28"',
   close(RTP.run_top_h(S), H, 1e-9), RTP.run_top_h(S))
# WAS: the runs stop half a cap short of the ridge, like the clay pipes do.
# That is right for a piece that cannot be cut. These can: the boundary tiles
# are clipped on the line and built where they lie, so pulling them back as
# well would only re-open the gap the cutting closed. Measured on the user's
# own roof before the cut existed, the bare wedge at a hip reached 9.2" - an
# 18" ridge cap to hide it, which is why widening the cap was the wrong answer.
ok('the tiles are cut on the line, not set back from it',
   close(RTP.ridge_setback(S), 0.0, 1e-9), RTP.ridge_setback(S))
ok('...and it is STATED, so no derivation can put one back',
   S.key?(:ridge_setback))
ok("the clay pipes keep theirs - they cannot be cut",
   RTP.ridge_setback(RTM.shape('roman')) > 1.0,
   RTP.ridge_setback(RTM.shape('roman')))

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
# CUT AT THE EAVE. WAS: the bottom course hangs past it, the 1.25" every other
# material uses. The user saw it built and it read as a row of loose teeth with
# daylight between them - "תראה שהטייל לא נגמר באיב, הוא צריך להיחתך שמה" -
# because a flat tile, unlike a clay pipe, is a separate plate with a joint
# down each side and nothing under its nose.
low = SLOTS.select { |s| close(s[:origin][2].to_f, 100.0, 1.5) }
ok('the bottom course is CUT at the eave, not hung over it',
   !low.empty? &&
   low.all? { |s| s[:length] <= RTM.shape('slate')[:exposure].to_f + 1e-6 },
   low.map { |s| s[:length].round(2) }.uniq)
ok('...and it still reaches the eave line exactly',
   low.all? { |s| close(s[:origin][2].to_f, 100.0, 1e-6) },
   low.map { |s| s[:origin][2].round(3) }.uniq)

# ------------------------------------- NO TILE CROSSES A HIP OR A VALLEY
#
# v_spans_at cuts the tile's CENTRE LINE, and a tile is 12.6" wide, so against
# a diagonal one whole side used to hang past the line into the neighbouring
# plane and run through its tiles. flat_slots now measures the span at BOTH
# edges of the tile as it is drawn and takes the tightest. On a TRIANGLE -
# every edge above the eave is a hip - not one corner of one tile may sit
# outside the outline.
HIP_FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0], [100.0, 90.0, 130.0]].freeze
HIP_PL = PLACE.planes_from_faces([StubFace.new(HIP_FACE, NRM)])
HIP_PU = RTM.plane_uv(HIP_PL[0][:points], HIP_PL[0][:n])
HIP_SLOTS = PLACE.run_slots(HIP_PL, 'slate')
ok('a hip face still gets tiles', HIP_SLOTS.length > 20, HIP_SLOTS.length)

def inside?(poly, pt)
  x, y = pt
  hit = false
  n = poly.length
  n.times do |i|
    ax, ay = poly[i]
    bx, by = poly[(i + 1) % n]
    next if (ay > y) == (by > y)
    xx = ax + (y - ay) * (bx - ax) / (by - ay)
    hit = !hit if x < xx
  end
  hit
end

HALF = (RTP.run_pitch(RTM.shape('slate')) / 2.0) - RTP.flat_joint

# A tile is either WHOLE - and then its plain rectangle has to be inside - or
# CUT, and then it carries the clipped footprint it was actually built from.
# Both are checked against the same outline: nothing may cross the hip.
def corners(s, pu, half)
  return s[:cut] if s[:cut]
  d = [s[:origin][0] - pu[:origin][0], s[:origin][1] - pu[:origin][1],
       s[:origin][2] - pu[:origin][2]]
  u = d[0] * pu[:u][0] + d[1] * pu[:u][1] + d[2] * pu[:u][2]
  v = d[0] * pu[:v][0] + d[1] * pu[:v][1] + d[2] * pu[:v][2]
  [[u - half, v], [u + half, v],
   [u + half, v + s[:length]], [u - half, v + s[:length]]]
end

# nudge each corner a hair toward the polygon's centroid before asking - a
# vertex sitting EXACTLY on the outline (or exactly on its corner, which a
# tile at the eave-rake corner legitimately does) is inside, not outside.
HCX = HIP_PU[:poly].sum { |p| p[0] } / HIP_PU[:poly].length
HCY = HIP_PU[:poly].sum { |p| p[1] } / HIP_PU[:poly].length
out = 0
HIP_SLOTS.each do |s|
  corners(s, HIP_PU, HALF).each do |(x, y)|
    dx = HCX - x
    dy = HCY - y
    l = Math.hypot(dx, dy)
    l = 1.0 if l < 1.0e-9
    next if inside?(HIP_PU[:poly], [x + (dx / l * 5.0e-3), y + (dy / l * 5.0e-3)])
    out += 1
  end
end
ok('not one tile corner crosses the hip line', out.zero?, out)
ok('the hip really did cut some of them',
   HIP_SLOTS.count { |s| s[:cut] } > 5,
   HIP_SLOTS.count { |s| s[:cut] })
ok('a cut tile keeps its nose on the course line, it only loses material',
   HIP_SLOTS.select { |s| s[:cut] }
            .all? { |s| RTM.poly_area(s[:cut]).abs <= (2 * HALF * s[:length]) + 0.01 })
# The middle of a big plane is never cut - the field stays instances, which is
# the whole cost argument.
ok('the field is NOT cut - only the boundary pays',
   SLOTS.count { |s| s[:cut] }.to_f / SLOTS.length < 0.35,
   [SLOTS.count { |s| s[:cut] }, SLOTS.length])

# ----------------------- A PLANE UNDER ANOTHER ROOF GETS NO TILES
#
# Where one wing's roof runs in under another, the buried continuation is its
# own face in the shell. It was always built; the flat texture kept it
# invisible, and real tiles poked out through the covering roof - seen
# through the open gable end on the user's house. A face whose middle sits in
# plan under a higher plane is dropped whole.
UNDER = StubFace.new([[40.0, 10.0, 95.0], [160.0, 10.0, 95.0],
                      [160.0, 60.0, 111.7], [40.0, 60.0, 111.7]], NRM)
both = PLACE.planes_from_faces([StubFace.new(FACE, NRM), UNDER])
ok('the buried plane is seen by the frame machinery', both.length == 2,
   both.length)
covered = PLACE.run_slots(both, 'slate')
ok('...but gets NO tiles - only the covering plane is tiled',
   covered.length == SLOTS.length, [covered.length, SLOTS.length])
# side by side, nobody covers anybody - both tile as before
BESIDE = StubFace.new([[300.0, 0.0, 100.0], [500.0, 0.0, 100.0],
                       [500.0, 90.0, 130.0], [300.0, 90.0, 130.0]], NRM)
pair = PLACE.planes_from_faces([StubFace.new(FACE, NRM), BESIDE])
ok('two planes side by side both keep their tiles',
   PLACE.run_slots(pair, 'slate').length == 2 * SLOTS.length,
   [PLACE.run_slots(pair, 'slate').length, SLOTS.length])

# ------------------- THE GABLE CASE: A PLANE PARTLY UNDER ANOTHER
#
# A hip junction splits the shell on the valley, so a buried tongue is its
# own face and drop_covered_planes erases it whole. A GABLE junction splits
# nothing: the main slope stays ONE face whose far end runs in under the
# wing's roof - "אם אני משנה את הגג לגיבל היא חוזרת". The face stays (its
# middle is in daylight) and the TILES are cut instead, on the line where the
# two planes intersect in 3D - cover_clips. Q here crosses above P exactly
# like a wing roof: above it below y=50.77, under it above.
QF = StubFace.new([[60.0, 20.0, 140.0], [140.0, 20.0, 140.0],
                   [140.0, 90.0, 87.5], [60.0, 90.0, 87.5]], [0.0, 0.75, 1.0])
GP = PLACE.planes_from_faces([StubFace.new(FACE, NRM), QF])
ok('crossing planes BOTH survive the buried-plane filter', GP.length == 2 &&
   PLACE.drop_covered_planes(GP).length == 2, PLACE.drop_covered_planes(GP).length)
G_SLOTS = PLACE.run_slots(GP, 'slate')
gpu = RTM.plane_uv(GP[0][:points], GP[0][:n])
g_bad = 0
g_daylight = 0
G_SLOTS.each do |s|
  next unless s[:n][1] < 0 # P's tiles only
  pts_uv = if s[:cut]
             s[:cut]
           else
             d = [s[:origin][0] - gpu[:origin][0], s[:origin][1] - gpu[:origin][1],
                  s[:origin][2] - gpu[:origin][2]]
             u = (d[0] * gpu[:u][0]) + (d[1] * gpu[:u][1]) + (d[2] * gpu[:u][2])
             v = (d[0] * gpu[:v][0]) + (d[1] * gpu[:v][1]) + (d[2] * gpu[:v][2])
             [[u - HALF, v], [u + HALF, v],
              [u + HALF, v + s[:length]], [u - HALF, v + s[:length]]]
           end
  pts_uv.each do |q2|
    w = RTM.unproject(q2, gpu[:origin], gpu[:u], gpu[:v])
    inq = w[0] > 60.05 && w[0] < 139.95 && w[1] > 20.05 && w[1] < 89.95
    zq = 140.0 - ((w[1] - 20.0) * 0.75)
    if inq && zq > w[2] + 0.6
      g_bad += 1
    elsif inq
      g_daylight += 1
    end
  end
end
ok('not one tile point is buried under the crossing plane', g_bad.zero?, g_bad)
ok('...and the daylight part under its footprint is still tiled',
   g_daylight.positive?, g_daylight)

# THE KNIFE (2026-08-21c, "זה עדיין קיים בגייבל"): tiles were cut but the
# DECK tongue itself stayed - a face cannot be half-erased. So roof_manager
# draws the planes' 3D intersection line onto the shell first; SketchUp
# splits the face along it and the buried half then erases like any buried
# face. The stub cannot split, so the SEGMENT is what gets pinned: exactly
# one, landing exactly on the junction, on BOTH planes, bounded by the
# covering plane's footprint.
require './roof_manager'
RM2 = InteriorPro::RoofManager
seg_ci = { plan: [[0.0, 0.0], [200.0, 0.0], [200.0, 90.0], [0.0, 90.0]],
           cx: 100.0, cy: 45.0, cz: 115.0,
           p0: [0.0, 0.0, 100.0], n: [0.0, -1.0 / 3.0, 1.0] }
seg_qi = { plan: [[60.0, 20.0], [140.0, 20.0], [140.0, 90.0], [60.0, 90.0]],
           cx: 100.0, cy: 55.0, cz: 113.75,
           p0: [60.0, 20.0, 140.0], n: [0.0, 0.75, 1.0] }
SEGS = RM2.buried_split_segments(seg_ci, seg_qi)
ok('the knife finds exactly one junction segment', SEGS.length == 1,
   SEGS.length)
if SEGS.length == 1
  sa, sb = SEGS[0]
  ok('...landing exactly on the meeting line, y = 50.77',
     close(sa[1], 660.0 / 13.0, 0.01) && close(sb[1], 660.0 / 13.0, 0.01),
     [sa[1].round(3), sb[1].round(3)])
  ok('...bounded by the covering footprint, x = 60 to 140',
     close([sa[0], sb[0]].min, 60.0, 0.01) &&
     close([sa[0], sb[0]].max, 140.0, 0.01), [sa[0], sb[0]])
  ok('...with both endpoints ON both planes - SketchUp can cut with it',
     [sa, sb].all? do |w|
       close(w[2], 100.0 + (w[1] / 3.0), 1e-6) &&
       close(w[2], 140.0 - ((w[1] - 20.0) * 0.75), 1e-6)
     end)
end
ok('parallel planes get no knife - nothing to cut along',
   RM2.buried_split_segments(seg_ci, seg_ci.merge(p0: [0.0, 0.0, 110.0])).empty?)

# --------------------------------- THE UNDERSIDE TWIN (2026-08-23)
#
# The knife was never what was left. Measured in the user's own gable model:
# the buried TOP face was already erased, and the only face in the roof group
# with no twin was the one 0.5" below it - the underside of the slab, which
# drop_buried_faces! never sees because it is handed the top shell alone.
# That underside is the deck he kept seeing through the open gable.
#
# It cannot simply be fed to the same test: every underside face is covered
# by its own top skin, and the test flagged ALL SEVEN of his as buried. So an
# underside face is erased for exactly one reason - the face above it went.
class TwinFace
  attr_reader :points, :normal
  def initialize(pts, n)
    @points = pts.map { |p| Geom::Point3d.new(p[0], p[1], p[2]) }
    @normal = Geom::Vector3d.new(n[0], n[1], n[2])
    @gone = false
  end
  def valid?; !@gone; end
  def erase!; @gone = true; end
  def gone?; @gone; end
end

# a square deck tongue, and the underside half an inch below it
def twin_square(cx, cy, z, nz = 1.0)
  TwinFace.new([[cx - 10, cy - 10, z], [cx + 10, cy - 10, z],
                [cx + 10, cy + 10, z], [cx - 10, cy + 10, z]], [0.0, 0.0, nz])
end

gone_top   = RM2.face_cover_info(twin_square(100.0, 50.0, 120.0))
under_hit  = twin_square(100.0, 50.0, 119.5)       # the tongue's own underside
under_far  = twin_square(400.0, 50.0, 119.5)       # a different part of the roof
under_edge = twin_square(100.0, 50.0, 119.5, -1.0) # slab edge - faces the other way
under_over = twin_square(100.0, 50.0, 120.5)       # above the erased face, not below
twins_hit = RM2.drop_buried_twins!(
  [gone_top], [under_hit, under_far, under_edge, under_over]
)
ok('the underside twin of an erased top face is erased too',
   twins_hit == 1, twins_hit)
ok('...and it is the one directly below it', under_hit.gone?)
ok('a face elsewhere on the roof is left alone', !under_far.gone?)
ok('the slab edge sharing its centre is left alone - opposite normal',
   !under_edge.gone?)
ok('a face ABOVE the erased one is left alone', !under_over.gone?)

# THE REGRESSION THIS PASS EXISTS NOT TO BECOME: running the cover test over
# the underside would erase the whole ceiling. Nothing goes without a top
# face having gone first.
ok('no erased top face means no underside is touched',
   RM2.drop_buried_twins!([], [twin_square(100.0, 50.0, 119.5)]).zero?)
ok('and with no underside handed in, the pass does nothing',
   RM2.drop_buried_twins!([gone_top], nil).zero?)
# The old two-argument call still means "top shell only" - every other caller
# and every earlier suite is untouched.
ok('drop_buried_faces! still accepts the old two arguments',
   RM2.method(:drop_buried_faces!).arity == -2,
   RM2.method(:drop_buried_faces!).arity)

# --------------------------------- THE ORPHAN EDGES (2026-08-23)
#
# "שני קווים דקים על השיפוע" - erasing the tongue's faces left their rim
# edges behind with NO faces at all, and SketchUp draws a faceless edge as
# a bare line, always. Measured in the user's model: the two visible lines
# were two free 344" edges (deck top + underside, 0.5" apart, faces=0).
# The rule: only an edge left holding NOTHING is erased; an edge with a
# surviving face is a real boundary and is kept.
class OrphanEdge
  attr_reader :faces
  def initialize(faces)
    @faces = faces
    @gone = false
  end
  def valid?; !@gone; end
  def erase!; @gone = true; end
  def gone?; @gone; end
end
live_face = Object.new
e_bare = OrphanEdge.new([])          # the pencil line - nothing holds it
e_held = OrphanEdge.new([live_face]) # still a boundary of a real face
orphans_hit = RM2.drop_orphan_edges!([e_bare, e_held, e_bare])
ok('a faceless edge is erased - the visible pencil line', e_bare.gone?)
ok('an edge still holding a face is kept', !e_held.gone?)
ok('an already-erased edge is not counted twice', orphans_hit == 1,
   orphans_hit)
ok('and no edges at all is fine', RM2.drop_orphan_edges!(nil).zero?)

# drop_buried_twins! hands the twin's edges to the sweep: an erased twin
# with #edges lands them in the doomed list BEFORE the face goes.
class TwinFaceE < TwinFace
  def initialize(pts, n, edges)
    super(pts, n)
    @edges = edges
  end
  attr_reader :edges
end
twin_rim = OrphanEdge.new([])
twin_e = TwinFaceE.new(
  [[90, 40, 119.5], [110, 40, 119.5], [110, 60, 119.5], [90, 60, 119.5]],
  [0.0, 0.0, 1.0], [twin_rim]
)
doomed = []
RM2.drop_buried_twins!([gone_top], [twin_e], doomed)
ok('the erased twin\'s edges are collected for the orphan sweep',
   doomed.include?(twin_rim))
ok('...and the twin itself was erased', twin_e.gone?)
ok('the two-argument twin call still works - no doomed list, no sweep',
   RM2.drop_buried_twins!([gone_top],
                          [twin_square(100.0, 50.0, 119.5)]) == 1)

# --------------------------------- THE VALLEY PULL-BACK (fourth pass)
#
# Tiles used to be cut exactly ON the valley line from both sides and the
# bare meeting read as a ragged seam. Now roof_manager hands the valley lines
# in (opts[:valleys]) and every tile near one stops HALF A CHANNEL short of
# it - so the flat strip lands on cleared deck and the tiles butt its edge.
# The valley here runs up the plane's left edge: from [0,0,100] to [0,90,130],
# both endpoints ON the plane, which is how flat_slots knows it is hers.
VSB = RTP.cap_w(S) / 2.0
V_SLOTS = PLACE.run_slots(PLANES, 'slate',
                          valleys: [[[0.0, 0.0], 100.0, [0.0, 90.0], 130.0, []]])
ok('with a valley the plane still fills with tiles', V_SLOTS.length > 100,
   V_SLOTS.length)
min_u = V_SLOTS.map do |s|
  if s[:cut]
    s[:cut].map { |p| p[0] }.min
  else
    d = [s[:origin][0] - PU[:origin][0], s[:origin][1] - PU[:origin][1],
         s[:origin][2] - PU[:origin][2]]
    (d[0] * PU[:u][0] + d[1] * PU[:u][1] + d[2] * PU[:u][2]) - HALF
  end
end.min
ok('every tile stops half a channel short of the valley line',
   min_u >= VSB - 1.0e-3, [min_u.round(3), VSB])
ok('...and the first tile BUTTS the channel edge, no extra gap',
   min_u <= VSB + 0.6, [min_u.round(3), VSB])
# a valley belonging to some OTHER plane changes nothing here
FAR = PLACE.run_slots(PLANES, 'slate',
                      valleys: [[[500.0, 500.0], 0.0, [500.0, 590.0], 30.0, []]])
ok("a valley on another plane is ignored - not this plane's business",
   FAR.length == SLOTS.length, [FAR.length, SLOTS.length])

Sketchup.reset_model!
model = Sketchup.active_model
grp = model.entities.add_group
made = PLACE.place_runs!(grp, PLACE.planes_from_faces([StubFace.new(FACE, NRM)]),
                         'slate', model: model)
ok('they are actually placed', made > 100, made)
inst = grp.entities.grep(Sketchup::ComponentInstance)
# NOT grep(Group): in the stub ComponentInstance IS a Group, so that would
# count the whole field as well. The cut tiles are the ones that say so.
cutg = grp.entities.grep(Sketchup::Group).reject { |g| g.is_a?(Sketchup::ComponentInstance) }
ok('the field is instances of ONE definition',
   !inst.empty? && inst.map { |i| i.definition.name }.uniq.length == 1,
   inst.map { |i| i.definition.name }.uniq)
# The boundary tiles are groups, not instances - they are each a different
# shape, so they cannot share a definition. Everything is one or the other.
ok('the boundary tiles are their own groups',
   !cutg.empty? && inst.length + cutg.length == made,
   [inst.length, cutg.length, made])
# A CUT TILE IS THE SAME WEDGE, CLIPPED (fifth pass, his words): "הצורה של
# הרעף צריכה להמשיך לתוך הפינה ולעשות אינטרסקט עם הרעף שהיא נפגשת איתו - זה
# כבר לא צריך להיות שטוח, כי שינינו את צורת הרעף." The top keeps the wedge's
# own slope over its COURSE window, the boundary cuts through the thickness,
# and each perimeter edge that stands off the deck gets its vertical cut
# face. The flat single-face patch (fourth pass) is what this replaced - it
# also needed a float to dodge z-fighting; a wedge touches the deck only
# along a LINE, so it needs none.
ok('a cut tile is a clipped wedge - a top plus its cut faces',
   cutg.all? { |g| g.entities.grep(Sketchup::Face).length.between?(2, 8) },
   cutg.map { |g| g.entities.grep(Sketchup::Face).length }.uniq)
# Every vertex sits BETWEEN the deck and one tile height above it - the
# residual of the plane equation (z = 100 + y/3) is 0 on the deck and about
# h*sqrt(10)/3 at full thickness.
H_R = RTP.run_height(S) * Math.sqrt(10.0) / 3.0
cut_bad = 0
risen = 0
cutg.each do |g|
  g.entities.grep(Sketchup::Face).each do |f|
    f.points.each do |p|
      r = p.z.to_f - (100.0 + (p.y.to_f / 3.0))
      cut_bad += 1 if r < -1.0e-3 || r > H_R + 1.0e-3
      risen += 1 if r > 0.01
    end
  end
end
ok('a cut wedge stays between the deck and one tile height', cut_bad.zero?,
   cut_bad)
ok('...and it really rises off the deck - it is not the old flat plate',
   risen.positive?, risen)

# ------------------------- EVERY CUT FACE PASSES REAL SKETCHUP'S RULES
#
# The lesson of this whole feature, learned the hard way TWICE now (§0 of the
# 2026-08-21b handoff, and again today): the test stub's add_face accepts what
# real SketchUp refuses. The first cut-tile build passed every test here and
# died on the user's machine - a tile corner ON the eave line makes clip_left
# emit the corner twice, SketchUp raises on the duplicate, the rescue ate the
# error, and every hip and valley grew a bare stripe where its cut tiles
# should have been. So every face of every cut tile is now held to the real
# rules: no two adjacent points closer than 1e-4, at least 3 points, planar.
dup_bad = 0
plan_bad = 0
thin_bad = 0
cutg.each do |g|
  g.entities.grep(Sketchup::Face).each do |f|
    pts = f.points
    thin_bad += 1 if pts.length < 3
    pts.each_with_index do |p, i|
      q = pts[(i + 1) % pts.length]
      d = Math.sqrt(((p.x - q.x)**2) + ((p.y - q.y)**2) + ((p.z - q.z)**2))
      dup_bad += 1 if d < 1.0e-4
    end
    next if pts.length < 4
    a, b, c2 = pts[0], pts[1], pts[2]
    u = [b.x - a.x, b.y - a.y, b.z - a.z]
    v = [c2.x - a.x, c2.y - a.y, c2.z - a.z]
    n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2],
         u[0] * v[1] - u[1] * v[0]]
    l = Math.sqrt(n[0]**2 + n[1]**2 + n[2]**2)
    next if l < 1e-12
    n = n.map { |q| q / l }
    pts[3..-1].each do |p|
      dd = (p.x - a.x) * n[0] + (p.y - a.y) * n[1] + (p.z - a.z) * n[2]
      plan_bad += 1 if dd.abs > 1.0e-3
    end
  end
end
ok('no cut face carries a duplicated point - real SketchUp raises on one',
   dup_bad.zero?, dup_bad)
ok('no cut face is out of plane', plan_bad.zero?, plan_bad)
ok('no cut face is degenerate', thin_bad.zero?, thin_bad)

# The synthetic worst case, pinned by name: a tile whose corner lies EXACTLY
# on the clip line. This is the shape that killed the first build.
sq = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]]
tri = RTM.clip_to_poly([[0.0, 0.0], [20.0, 0.0], [0.0, 20.0]], sq)
dups = tri.each_index.count do |i|
  j = (i + 1) % tri.length
  Math.hypot(tri[i][0] - tri[j][0], tri[i][1] - tri[j][1]) < 1.0e-4
end
ok('a corner exactly on the clip line does not come back doubled',
   tri.length >= 3 && dups.zero?, tri)
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

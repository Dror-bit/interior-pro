# encoding: utf-8
# rt95 - THE DORMER BODY (2026-09-01, step 1 of the dormer).
#
# WHAT THIS IS
# The first piece of the dormer the user asked for: a gable dormer body -
# front wall, two cheeks, two roof slopes - built from the two sizes he
# said he wants to type (WIDTH across the roof, LENGTH into it) plus a
# setback whose default is 3 feet.
#
# THE CLAIMS PINNED HERE
# 1. THE DIE-IN RULE. The ridge ends exactly where the main roof surface
#    has climbed to the ridge's own height: ridge z = z0 + (setback +
#    length) * slope. That is what makes the front wall height a RESULT
#    and not a fourth number that can argue with the other three.
# 2. THE SIZES ARE THE SIZES. Outside face to outside face across the
#    roof = width. Front wall to ridge die-in = length.
# 3. BOARDS MEET (CLAUDE.md). Every wall - front and cheeks - stops on
#    the UNDERSIDE of the dormer's own roof slab. Not one wall point
#    lives inside the slab.
# 4. THE VALLEY IS ON THE ROOF. Both back corners of each roof slope sit
#    exactly on the main roof surface, so step 2 has a straight line to
#    cut along.
# 5. THE CHEEK RIDES THE ROOF. Its bottom starts on the roof at the
#    front wall and meets its own level top where the roof catches up.
# 6. IT REFUSES SIZES THAT CANNOT MAKE A DORMER instead of building a
#    sliver.
#
# Against the old code every claim fails: there was no dormer at all.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './dormer_manager'

# THE GABLET HEEL IS OFF IN HERE (2026-09-06). Every number in this suite
# was measured when the gablet's roof sat straight on its walls and its
# eave hung below them. He asked for the same raised heel the house roof
# got, and chose that it ADDS to the typed height - "העקב נוסף למספר" -
# so a typed height now comes back taller and the overhang moves z_eave.
# That is the new rule, pinned by rt119; this suite is about something
# else, so here the heel stays off.
module InteriorPro
  module DormerManager
    def self.dormer_heel(_overhang, _style, _pitch, _slope, _spec)
      0.0
    end
  end
end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

DM = InteriorPro::DormerManager

Z0    = 100.0        # the eave of the main roof
SLOPE = 8.0 / 12.0
SET   = 36.0
WID   = 48.0
LEN   = 96.0
RT    = 0.5
TH    = 5.0

fr = DM.frame(z0: Z0, slope: SLOPE, setback: SET, width: WID, length: LEN,
              thickness: TH, roof_thickness: RT)
ok('the frame is computed', !fr.nil?)

# ---- 1. THE DIE-IN RULE ------------------------------------------------
ok('the ridge dies where the roof reaches it',
   close(fr[:z_ridge], Z0 + (SET + LEN) * SLOPE), fr[:z_ridge])
ok('the dormer eave hangs half a width below the ridge',
   close(fr[:z_eave], fr[:z_ridge] - (WID / 2.0) * SLOPE), fr[:z_eave])
ok('the front wall height is what falls out',
   close(fr[:height], LEN * SLOPE - (WID / 2.0) * SLOPE), fr[:height])
ok('the front wall stands on the roof surface',
   close(fr[:z_front], Z0 + SET * SLOPE), fr[:z_front])

# ---- build it: base at the origin, so world x = w and world y = s ------
Sketchup.reset_model!
m = Sketchup.active_model
grp = DM.build_dormer!(m.entities, z0: Z0, slope: SLOPE, setback: SET,
                       width: WID, length: LEN, thickness: TH,
                       roof_thickness: RT,
                       base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0])
ok('the dormer builds', !grp.nil?)

parts = grp.entities.to_a.select { |e| e.respond_to?(:entities) }
kind = lambda { |k| parts.select { |g| g.get_attribute('InteriorPro', 'part') == k } }
ok('one front wall', kind.call('dormer_front').length == 1)
ok('two cheeks', kind.call('dormer_cheek').length == 2)
ok('two roof slopes', kind.call('dormer_roof').length == 2)

def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map(&:position) }
end
walls = kind.call('dormer_front') + kind.call('dormer_cheek')
roofs = kind.call('dormer_roof')
wall_pts = walls.flat_map { |g| pts_of(g) }
roof_pts = roofs.flat_map { |g| pts_of(g) }

# ---- 2. THE SIZES ARE THE SIZES ---------------------------------------
ok('outside to outside across the roof is the width',
   close(wall_pts.map(&:x).max - wall_pts.map(&:x).min, WID, 0.05),
   wall_pts.map(&:x).max - wall_pts.map(&:x).min)
# The LENGTH is still measured on the WALL - front wall to ridge die-in.
# The slab itself is longer by its rake overhang (2026-09-02, rt97).
ok('front wall to ridge die-in is the length',
   close(roof_pts.map(&:y).max - wall_pts.map(&:y).min, LEN, 0.05),
   roof_pts.map(&:y).max - wall_pts.map(&:y).min)
# ...plus the bit of deck that finishes ON the metal edge instead of
# short of it (2026-09-02, deck_front - rt98).
ok('...and the slab reaches past it by the rake overhang',
   close(wall_pts.map(&:y).min - roof_pts.map(&:y).min,
         fr[:overhang] + fr[:deck_front], 0.05),
   wall_pts.map(&:y).min - roof_pts.map(&:y).min)
ok('the front wall sits at the setback',
   close(wall_pts.map(&:y).min, SET, 0.01), wall_pts.map(&:y).min)

# ---- 3. BOARDS MEET ----------------------------------------------------
# the slab's underside over the centre line is z_ridge - RT, and over an
# offset w it is z_ridge - |w| * pitch - RT. No wall point may be above
# the underside AT ITS OWN x.
worst = wall_pts.map { |p| p.z - (DM.top_z(fr, p.x) - RT) }.max
ok('no wall runs up inside the roof slab', worst < 0.001, worst)
ok('...and the front wall apex reaches it exactly',
   close(wall_pts.map(&:z).max, fr[:z_ridge] - RT), wall_pts.map(&:z).max)

# ---- 4. THE VALLEY IS ON THE ROOF -------------------------------------
roofs.each_with_index do |g, i|
  top = pts_of(g).select { |p| close(p.z, DM.top_z(fr, p.x), 0.01) }
  back = top.select { |p| p.y > SET + 0.5 }
  ok("slope #{i}: its back corners sit on the main roof",
     !back.empty? && back.all? { |p| close(p.z, Z0 + p.y * SLOPE, 0.02) },
     back.map { |p| [p.y.round(2), p.z.round(2), (Z0 + p.y * SLOPE).round(2)] })
end
ok('the two slopes meet at the ridge die-in point',
   roofs.all? { |g| pts_of(g).any? { |p| close(p.y, SET + LEN, 0.01) &&
                                         close(p.x, 0.0, 0.01) } })

# ---- 5. THE CHEEK RIDES THE ROOF --------------------------------------
ch = kind.call('dormer_cheek').first
cp = pts_of(ch)
ok('the cheek starts on the roof at the front wall',
   close(cp.map(&:z).min, fr[:z_front]), cp.map(&:z).min)
ok('...its top is level under the slab',
   close(cp.map(&:z).max, fr[:z_eave] - RT), cp.map(&:z).max)
ok('...and it ends where the roof has climbed to that top',
   close(cp.map(&:y).max, (fr[:z_eave] - RT - Z0) / SLOPE, 0.02),
   cp.map(&:y).max)
ok('the cheek is one wall thickness thick',
   close(cp.map(&:x).max - cp.map(&:x).min, TH, 0.01),
   cp.map(&:x).max - cp.map(&:x).min)

# ---- 6. IT REFUSES THE IMPOSSIBLE -------------------------------------
ok('a dormer too short for a window is refused',
   DM.frame(z0: Z0, slope: SLOPE, setback: SET, width: WID, length: 30.0).nil?)
ok('a dormer wider than it is long is refused',
   DM.frame(z0: Z0, slope: SLOPE, setback: SET, width: 200.0, length: 96.0).nil?)
ok('a flat roof has no dormer to build',
   DM.frame(z0: Z0, slope: 0.0, width: WID, length: LEN).nil?)
ok('a sane dormer is NOT refused',
   !DM.frame(z0: Z0, slope: SLOPE, setback: 0.0, width: WID, length: LEN).nil?)

# ---- 7. STEP 2: THE HOLE IN THE ROOF ----------------------------------
# THE OUTER FACE OF THE WALLS (2026-09-03). It was the dormer's INSIDE -
# the walls' inner faces - so the deck ran on under every wall and its cut
# edge showed as a lip round the opening. Now it stops on the OUTSIDE, the
# same line the tiles above it stop on, and the wall closes the edge. At the
# back it is still the VALLEY: past that line there is no dormer over the
# hole any more, and no wall either.
op = DM.opening_plan(fr)
ok('there is an opening', !op.nil? && op.length == 5, op && op.length)
if op
  hw = WID / 2.0
  ok('...it reaches the OUTER face of both cheeks',
     close(op.map { |_s, w| w.abs }.max, hw), op.map { |_s, w| w.abs }.max)
  ok('...and the OUTER face of the front wall, not behind it',
     close(op.map { |s2, _w| s2 }.min, SET), op.map { |s2, _w| s2 }.min)
  ok('...and its back point is the ridge die-in',
     close(op.map { |s2, _w| s2 }.max, fr[:s_ridge]), op.map { |s2, _w| s2 }.max)
  side = op.select { |_s, w| close(w.abs, hw) }.map { |s2, _w| s2 }.max
  ok('...its back edge follows the valley, between eave and ridge die-in',
     side > fr[:s_eave] - 0.01 && side < fr[:s_ridge] + 0.01, side)
end

# cut a two-skin slab: both skins get the ring, and the rim between them
# is closed. (The stub does not split faces - what is pinned here is that
# the cut finds BOTH skins of the roof it is standing on, and no other.)
Sketchup.reset_model!
m2 = Sketchup.active_model
slab = m2.entities.add_group
tp = lambda do |x, y|
  Geom::Point3d.new(x, y, Z0 + y * SLOPE)
end
top = [tp.call(-200, 0), tp.call(200, 0), tp.call(200, 400), tp.call(-200, 400)]
slab.entities.add_face(top)
slab.entities.add_face(top.map { |p| Geom::Point3d.new(p.x, p.y, p.z - RT) })
before = slab.entities.grep(Sketchup::Face).length
at = DM.at_lambda(base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0])
cut = DM.cut_roof!(slab.entities, fr, at)
ok('both skins of the roof are cut', cut == 2, cut)
ok('...and the cut edge between them is closed',
   slab.entities.grep(Sketchup::Face).length > before + 2,
   slab.entities.grep(Sketchup::Face).length - before)

# a roof the dormer is nowhere near is left alone
far = m2.entities.add_group
far.entities.add_face([Geom::Point3d.new(5000, 5000, 0), Geom::Point3d.new(5100, 5000, 0),
                       Geom::Point3d.new(5100, 5100, 0)])
ok('a roof the dormer is not on is untouched',
   DM.cut_roof!(far.entities, fr, at).zero?)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

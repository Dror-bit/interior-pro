# encoding: utf-8
# rt84 - THE BOXED SOFFIT (2026-08-24), step 1 of the soffit options.
#
# WHAT THIS IS
# Until today the eave had no soffit at all: the thing you saw looking up
# under the overhang was simply the underside of the sloped roof slab,
# painted the fascia colour. `soffit_band` is the first real one - a flat
# horizontal board that closes the eave from below.
#
# THE CLAIMS PINNED HERE
# 1. OUTSIDE ONLY. The board lives strictly between the wall's exterior
#    face and the fascia. Its inner edge is at offset -overhang, which IS
#    the wall face, so it can never reach into the room.
# 2. NO OVERHANG -> NO BOARD. With nothing sticking out there is nothing to
#    close, and a zero-width band would be a degenerate face.
# 3. IT IS FLUSH WITH THE FASCIA BOTTOM. The board's UNDERSIDE sits on the
#    same line the fascia ends at, so the eave reads as one clean edge and
#    not as a step. The board is then SOFFIT_THICK thick upward from there.
# 4. IT STOPS AT THE FASCIA'S INNER FACE, never inside the fascia board.
# 5. DEFAULT IS 'none'. This suite fails if the default ever flips, because
#    that would silently change every roof the user has already built.
require './sketchup_stub'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def close(a, b, tol = 1e-6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RM = InteriorPro::RoofManager

# A 6:12 roof on 8' walls: eave_z 96, overhang 18", so the roof edge
# underside (band_top) has dropped 18 * 0.5 = 9" to z = 87.
BAND_TOP = 87.0
OH       = 18.0
FD       = 8.0

b = RM.soffit_band(OH, FD, true, BAND_TOP)

# ------------------------------------------------------------------ it exists
ok('a normal eave gets a soffit', !b.nil?)

# -------------------------------------------------- 1. outside only, no deeper
ok('inner edge sits exactly on the wall face', close(b[:k_in], -OH), b)
ok('never reaches past the wall into the room', b[:k_in] >= -OH, b)

# ------------------------------------- 4. stops at the fascia''s INNER face
ok('outer edge = inner face of the fascia',
   close(b[:k_out], -RM::FASCIA_THICK), b)
ok('never pokes out past the roof edge', b[:k_out] <= 0.0, b)
ok('the board has real width', b[:k_out] - b[:k_in] > 0.5, b)

# ------------------------------ 3. flush with where the fascia actually ends
ok('underside is level with the fascia bottom',
   close(b[:z_bot], BAND_TOP - FD), b)
ok('thickness is one board, upward', close(b[:z_top] - b[:z_bot], RM::SOFFIT_THICK), b)
ok('the board is HORIZONTAL - one z, not a slope', b[:z_top] > b[:z_bot], b)
ok('it hangs below the roof edge, never above it', b[:z_top] < BAND_TOP, b)

# ------------------------------------------------------- 2. no overhang, none
ok('overhang 0 -> no soffit', RM.soffit_band(0.0, FD, true, BAND_TOP).nil?)
ok('overhang 0.5" -> no soffit', RM.soffit_band(0.5, FD, true, BAND_TOP).nil?)
ok('an overhang thinner than the fascia -> no soffit',
   RM.soffit_band(1.0, FD, true, BAND_TOP).nil?,
   RM.soffit_band(1.0, FD, true, BAND_TOP))

# ---------------------------------------------------------- fascia turned off
nf = RM.soffit_band(OH, FD, false, BAND_TOP)
ok('with no fascia the board runs out to the roof edge', close(nf[:k_out], 0.0), nf)
ok('with no fascia it still hangs at the same height', close(nf[:z_bot], BAND_TOP - FD), nf)

# -------------------------------------------------------- 5. default is none
ok('the styles we have', RM::SOFFIT_STYLES == %w[none boxed wood stucco beams],
   RM::SOFFIT_STYLES)
ok('default stays none - old roofs must not change',
   RM.settings[:soffit] == 'none', RM.settings[:soffit])

# ------------------------------------------------- the finish colour, 2026-08-25
# 'wood' and 'stucco' are the SAME board as 'boxed'. The only thing that may
# differ is the paint, so this is the whole of the new behaviour - and the
# first line of it is that BOXED DID NOT CHANGE.
ok('boxed follows the fascia, exactly as before',
   RM.soffit_color(soffit: 'boxed', soffit_color: '').nil?,
   RM.soffit_color(soffit: 'boxed', soffit_color: ''))
ok('wood is stained, not left on the trim colour',
   RM.soffit_color(soffit: 'wood', soffit_color: '') == '#8b5a2b')
ok('stucco is off white',
   RM.soffit_color(soffit: 'stucco', soffit_color: '') == '#efeae1')
ok('a hand-picked colour beats the style default',
   RM.soffit_color(soffit: 'wood', soffit_color: '#123456') == '#123456')
ok('...and a blank or junk setting falls back to the style',
   RM.soffit_color(soffit: 'wood', soffit_color: '   ') == '#8b5a2b' &&
   RM.soffit_color(soffit: 'wood', soffit_color: 'blue') == '#8b5a2b')
# ============================================================ EXPOSED BEAMS
# 2026-08-25, the user's own numbers: a 2x4 (1.5" x 3.5") every 18".
sp = RM.beam_spec
ok('a real 2x4, on 18" centres',
   close(sp[:w], 1.5) && close(sp[:h], 3.5) && close(sp[:spacing], 18.0), sp)

# THE MARGIN IS THE WALL, NOT A GAP (user 2026-08-25: a tail "יוצא מהפשייה
# ולא נוגע בקיר... נשאר באוויר"). poly is the wall line pushed out by the
# overhang, so the wall corner is one overhang back along each edge - and a
# tail beyond that touches nothing. The caller passes overhang + half a beam.
MG = 12.0 + 0.75
c = RM.beam_centers(240.0, 18.0, 1.5, MG)
ok('a 20 foot eave with a 12" overhang takes 12 tails', c.length == 12, c.length)
ok('NO tail reaches past the wall corner at either end',
   c.first >= MG - 1e-9 && c.last <= 240.0 - MG + 1e-9, [c.first, c.last])
ok('every tail is fully backed by wall, not just its centre',
   c.first - 0.75 >= 12.0 - 1e-9 && c.last + 0.75 <= 240.0 - 12.0 + 1e-9,
   [c.first - 0.75, c.last + 0.75])
ok('the spacing between them is the spacing asked for',
   c.each_cons(2).all? { |a2, b2| close(b2 - a2, 18.0) }, c)
ok('the run is centred - the two end gaps match',
   close(c.first, 240.0 - c.last), [c.first, 240.0 - c.last])
ok('with no overhang at all it falls back to clearing one beam width',
   close(RM.beam_centers(240.0, 18.0, 1.5, 0.0).first, 1.5 + (237.0 - 234.0) / 2.0),
   RM.beam_centers(240.0, 18.0, 1.5, 0.0).first)
ok('an eave shorter than its own two margins gets none',
   RM.beam_centers(20.0, 18.0, 1.5, MG).empty?,
   RM.beam_centers(20.0, 18.0, 1.5, MG))
ok('a spacing narrower than the beam is refused, not overlapped',
   RM.beam_centers(240.0, 1.0, 1.5, MG).empty?)

# the plan shape of one tail: across the eave, not along it
q = RM.beam_quad([0.0, 0.0], [1.0, 0.0], [0.0, -1.0], 50.0, 0.75, -24.0, -0.75)
xs = q.map { |p| p[0] }
ys = q.map { |p| p[1] }
ok('the tail is one beam wide along the eave',
   close(xs.max - xs.min, 1.5), xs)
ok('...and runs the whole overhang across it',
   close(ys.max - ys.min, 23.25), ys)
ok('...centred on its own station', close((xs.max + xs.min) / 2.0, 50.0), xs)
# the same beam on an eave running the other way must still stick INWARD
q2 = RM.beam_quad([0.0, 0.0], [0.0, 1.0], [1.0, 0.0], 50.0, 0.75, -24.0, -0.75)
ok('the outward normal decides the side, not the world axes',
   q2.map { |p| p[0] }.max <= 0.0 + 1e-9, q2)

ok('an unknown style paints nothing rather than raising',
   RM.soffit_color(soffit: 'martian', soffit_color: '').nil?)
ok('none is not a finish either', RM.soffit_color(soffit: 'none', soffit_color: '').nil?)

# ------------------------------------------------- the finish TEXTURE, 2026-08-25
# The soffit is the one part of the roof that still wears a picture: it has
# no 3D pattern to fight with (the user chose a plain board over modelled
# planks), so the texture IS the pattern. rt43/rt73 guard the roof's own
# jpgs the same way - a table that names a file nobody shipped is a silent
# fall back to a flat colour, and nobody notices until it is on screen.
tx = RM.soffit_textures
ok('wood and stucco are the textured finishes',
   tx.keys.sort == %w[stucco wood], tx.keys)
# THE TAILS MATCH THE FASCIA (user 2026-08-25: "בצבע של הפשייה"). Both
# tables have to stay quiet about 'beams' for that: a texture or a default
# colour here would paint them and they would stop following the picker.
ok('beams are not textured - they take the trim colour', tx['beams'].nil?)
ok('...and have no colour of their own either',
   RM.soffit_color(soffit: 'beams', soffit_color: '').nil?)
ok('a colour picked by hand still overrides them',
   RM.soffit_color(soffit: 'beams', soffit_color: '#333333') == '#333333')
ok('boxed is NOT textured - it is a painted board', tx['boxed'].nil?)
# texture_path is relative to the FILE, and run_all.sh copies the sources
# into tests/ - so in the cloud it points at tests/textures while the jpgs
# live in the plugin root. Look in both; either one proves the file shipped.
def tex_here(f)
  [RM.texture_path(f), File.join('..', 'textures', f)].find { |p| File.exist?(p) }
end
# --------------------------------------------- which way the boards run
# The user's rule: "תמיד ילך לאורך הפשייה". A soffit piece is a long board,
# so its longest edge IS the fascia direction - that is the whole trick, and
# it is the reason no edge index has to be carried through the builders.
sq = [[0, 0, 0], [40, 0, 0], [40, 12, 0], [0, 12, 0]]
d = RM.ring_longest_dir(sq)
ok('a flat eave board points along its long side', close(d[0], 1.0) && close(d[1], 0.0), d)
diag = [[0, 0, 0], [30, 40, 0], [30 - 7.2, 40 + 9.6, 0], [-7.2, 9.6, 0]]
dd = RM.ring_longest_dir(diag)
ok('a wing at an angle points along ITS own eave, not along red',
   close(dd[0], 0.6) && close(dd[1], 0.8), dd)
rake = [[0, 0, 96], [30, 0, 96 + 40], [30, 12, 96 + 40], [0, 12, 96]]
dr = RM.ring_longest_dir(rake)
ok('a rake board points UP THE SLOPE - a flat direction is not in its plane',
   close(dr[2], 0.8) && close(dr[0], 0.6), dr)
ok('the direction is a unit vector',
   close(Math.sqrt(dr[0]**2 + dr[1]**2 + dr[2]**2), 1.0), dr)
ok('a degenerate ring asks for no alignment at all',
   RM.ring_longest_dir([[1, 1, 1], [1, 1, 1]]).nil? &&
   RM.ring_longest_dir([[0, 0, 0]]).nil? && RM.ring_longest_dir(nil).nil?)

tx.each do |style, spec|
  ok("#{style}: #{spec[:file]} is really on disk", !tex_here(spec[:file]).nil?,
     RM.texture_path(spec[:file]))
  ok("#{style}: the tile has a real size in inches",
     spec[:size].is_a?(Float) && spec[:size] > 1.0, spec[:size])
end
ok('soffit_color survives a save/load round trip',
   begin
     RM.save_settings!(RM.settings.merge(soffit: 'wood', soffit_color: '#abcdef'))
     RM.settings[:soffit_color] == '#abcdef' && RM.settings[:soffit] == 'wood'
   end, RM.settings[:soffit_color])
RM.save_settings!(RM.settings.merge(soffit: 'none', soffit_color: ''))

# ------------------------------------------------------------ deep eaves too
d = RM.soffit_band(36.0, 12.0, true, 78.0)
ok('a 36" eave reaches all the way back to the wall', close(d[:k_in], -36.0), d)
ok('a 36" eave still ends on the fascia', close(d[:k_out], -RM::FASCIA_THICK), d)


# =====================================================================
# THE RAKE SOFFIT (user 2026-08-24: "צריך להיות גם באיב של הגייבל").
#
# The gable overhang needs the same board, but sloped.
#
# BUG 1, measured in the user's console: "Points are not planar" and NOT
# ONE BOARD WAS BUILT. Four points make a face only if they are coplanar,
# and a corner pulled ALONG a climbing rake has to rise with it.
def coplanar?(q)
  u = [q[1][0] - q[0][0], q[1][1] - q[0][1], q[1][2] - q[0][2]]
  v = [q[3][0] - q[0][0], q[3][1] - q[0][1], q[3][2] - q[0][2]]
  n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
  nl = Math.sqrt(n[0]**2 + n[1]**2 + n[2]**2)
  return false if nl < 1e-9
  w = [q[2][0] - q[0][0], q[2][1] - q[0][1], q[2][2] - q[0][2]]
  ((n[0] * w[0] + n[1] * w[1] + n[2] * w[2]) / nl).abs < 1e-6
end

# a rake running along +X, climbing, with the overhang reaching in +Y
DIR = [1.0, 0.0]
INW = [0.0, OH]
Q1  = [0.0, 0.0]
Q2  = [120.0, 0.0]
ZA  = 84.0
ZB  = 84.0 + 40.0
grad = (ZB - ZA) / 120.0

both = RM.rake_soffit_quad(Q1, Q2, ZA, ZB, DIR, INW, OH, -OH)
ok('a board mitered at BOTH ends is planar', coplanar?(both), both)
ok('a board mitered at the START is planar',
   coplanar?(RM.rake_soffit_quad(Q1, Q2, ZA, ZB, DIR, INW, OH, 0.0)))
ok('an unmitered board is planar', coplanar?(RM.rake_soffit_quad(Q1, Q2, ZA, ZB, DIR, INW, 0.0, 0.0)))
ok('a LEVEL board is planar too', coplanar?(RM.rake_soffit_quad(Q1, Q2, ZA, ZA, DIR, INW, OH, -OH)))
ok('outer corners sit exactly on the rake',
   both[0] == [0.0, 0.0, ZA] && both[1] == [120.0, 0.0, ZB], both)
ok('the mitered corner rises with the rake', close(both[3][2], ZA + grad * OH), both[3])
ok('the board reaches inward by exactly the overhang',
   close(both[3][1], OH) && close(both[2][1], OH), both)
lvl = RM.rake_soffit_quad(Q1, Q2, ZA, ZB, DIR, INW, 0.0, 0.0)
ok('across its width the board is level',
   close(lvl[0][2], lvl[3][2]) && close(lvl[1][2], lvl[2][2]), lvl)
ok('a zero-length run does not divide by zero',
   !RM.rake_soffit_quad(Q1, Q1, ZA, ZA, DIR, INW, 0.0, 0.0).nil?)

# =====================================================================
# BUG 2, and the user's own words with a photo: "הקובייה צריכה להיסגר לא
# ב-45 מעלות אלא ב-90".
#
# The first corner shut the box on the 45 degree diagonal. A real boxed
# eave RETURNS instead: at the corner the rake soffit stays LEVEL with the
# flat eave board for one overhang, then steps up SQUARE onto the rake.
# The little box is that level piece; the 90 degree face is the step.
LEN = 240.0

s = RM.rake_soffit_segments(0.0, LEN, LEN, OH)
ok('a full rake gets 3 pieces: return, slope, return', s.length == 3, s)
ok('it opens with a level return one overhang long',
   s[0][2] == true && close(s[0][1] - s[0][0], OH), s)
ok('it closes with a level return one overhang long',
   s[2][2] == true && close(s[2][1] - s[2][0], OH), s)
ok('the middle piece is the sloping one', s[1][2] == false, s)
ok('the pieces tile the run with no gap and no overlap',
   close(s[0][1], s[1][0]) && close(s[1][1], s[2][0]), s)
ok('and they cover the whole run', close(s[0][0], 0.0) && close(s[2][1], LEN), s)

# a piece that is NOT at a corner gets no return - nothing to close there
m = RM.rake_soffit_segments(60.0, 180.0, LEN, OH)
ok('a middle run has no return at all', m.length == 1 && m[0][2] == false, m)
ok('a middle run is left exactly as it came', close(m[0][0], 60.0) && close(m[0][1], 180.0), m)

# only ONE end at a corner -> only ONE return
h = RM.rake_soffit_segments(0.0, 120.0, LEN, OH)
ok('a run starting at a corner returns only there',
   h.length == 2 && h[0][2] == true && h[1][2] == false, h)
t = RM.rake_soffit_segments(120.0, LEN, LEN, OH)
ok('a run ending at a corner returns only there',
   t.length == 2 && t[0][2] == false && t[1][2] == true, t)

# short runs must not eat themselves
sh = RM.rake_soffit_segments(0.0, OH, LEN, OH)
ok('a run no longer than the return stays one plain piece',
   sh.length == 1 && sh[0][2] == false, sh)
ok('...and still covers itself', close(sh[0][0], 0.0) && close(sh[0][1], OH), sh)
tw = RM.rake_soffit_segments(0.0, 2 * OH, 2 * OH, OH)
ok('a run too short for TWO returns takes none', tw.length == 1 && tw[0][2] == false, tw)
RM.rake_soffit_segments(0.0, LEN, LEN, OH).each do |a, b, _|
  ok('no piece is ever backwards', b >= a, [a, b])
end

# ---- the step: the 90 degree face itself
st = RM.rake_soffit_step([OH, 0.0], INW, ZA, ZA + grad * OH)
ok('the step exists where the return meets the rake', !st.nil?)
ok('it is a quad', st.length == 4, st)
ok('it is VERTICAL - both edges stand over the same line',
   close(st[0][0], st[3][0]) && close(st[1][0], st[2][0]), st)
ok('it is PERPENDICULAR to the rake, spanning the full soffit width',
   close(st[1][1] - st[0][1], OH), st)
ok('it starts on top of the level return', close(st[0][2], ZA + RM::SOFFIT_THICK), st)
ok('and reaches the rake board above it', close(st[3][2], ZA + grad * OH), st)
ok('so its height is exactly the step it hides',
   close(st[3][2] - st[0][2], grad * OH - RM::SOFFIT_THICK), st)

# a pitch so shallow the return already touches the rake leaves nothing open
ok('a step smaller than the board itself is not built',
   RM.rake_soffit_step([OH, 0.0], INW, ZA, ZA + 0.1).nil?)
ok('a level rake needs no step at all',
   RM.rake_soffit_step([OH, 0.0], INW, ZA, ZA).nil?)


# =====================================================================
# BUG 3, and the one that made the user say "אין בכלל איבס בגייבל מתחת":
# the gable soffit vanished COMPLETELY.
#
# A 45 degree miter eaten over a piece exactly one overhang long collapses
# the quad's two inner corners onto the SAME point - the plan shape really
# is a triangle there. Four points, two identical, and SketchUp raises;
# the rescue swallows it and the rest of that edge is never built. So one
# degenerate corner deleted the whole rake soffit.
sq = [[0.0, 0.0, 84.0], [12.0, 0.0, 84.0], [12.0, 12.0, 84.0], [12.0, 12.0, 84.0]]
ok('a collapsed quad comes back as a TRIANGLE', RM.dedupe_ring(sq).length == 3,
   RM.dedupe_ring(sq))
ok('and it keeps the three real corners',
   RM.dedupe_ring(sq) == sq[0, 3], RM.dedupe_ring(sq))
ok('an honest quad is left alone',
   RM.dedupe_ring([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 1.0, 0.0]]).length == 4)
ok('a ring that closes back on itself drops the repeat',
   RM.dedupe_ring([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 0.0, 0.0]]).length == 3)
# and the tolerance is SketchUp's own 1/1000", not Ruby's float equality:
# two ends a ten-thousandth apart are ONE point to SketchUp, and a face
# built on them raises. That sliver is what kept killing the gable.
ok('a sliver under SketchUp\'s tolerance IS merged',
   RM.dedupe_ring([[0.0, 0.0, 0.0], [0.0001, 0.0, 0.0]]).length == 1,
   RM.dedupe_ring([[0.0, 0.0, 0.0], [0.0001, 0.0, 0.0]]))
ok('but a real 1/100" step is kept',
   RM.dedupe_ring([[0.0, 0.0, 0.0], [0.01, 0.0, 0.0]]).length == 2)
ok('an empty ring stays empty', RM.dedupe_ring([]).empty?)

# and the whole builder, end to end on a stub: a 240" gable, 4:12, 12" eaves
POLY = [[0.0, 0.0], [240.0, 0.0], [240.0, 120.0], [0.0, 120.0]].freeze
ZMAP = { [0.0, 0.0] => 92.0, [240.0, 0.0] => 92.0, [120.0, 0.0] => 132.0,
         [0.0, 120.0] => 92.0, [240.0, 120.0] => 92.0 }.freeze
gg = Sketchup::Group.new
RM.build_rake_soffit!(gg, POLY, 0, ZMAP, 8.0, 12.0)
gf = gg.entities.grep(Sketchup::Face)
ok('the gable rake really does get a soffit', gf.length > 10, gf.length)

degenerate = gf.select do |f|
  pts = f.points.map { |p| [p.x.round(6), p.y.round(6), p.z.round(6)] }
  pts.uniq.length < 3
end
ok('NOT ONE face is degenerate - that is what killed it', degenerate.empty?,
   degenerate.map(&:points))

# The BOX itself is not built here any more (2026-08-24, second round):
# the flat eave band is cut SQUARE at the gable corner and owns the whole
# corner square, so the lowest thing this builder leaves at the corner is
# the step and the skirt that close that box - they stand ON it, one
# board up. Nothing may dip BELOW the eave soffit line.
zs = gf.map { |f| f.z_range[0] }.min
ok('nothing is built below the top of the box - the eave band owns it',
   close(zs, 92.0 - 8.0 + RM::SOFFIT_THICK), zs)
ok('and something up on the rake is well above it',
   gf.map { |f| f.z_range[1] }.max > 92.0, gf.map { |f| f.z_range[1] }.max)


# =====================================================================
# THE OUTER FACE OF THE BOX, and the seam across it (user 2026-08-24,
# who marked the hole in yellow and crossed out the diagonal line).
#
# The return is level and the rake board above it climbs, so along the
# OUTSIDE of the little box a triangle opens between the two. It is zero
# at the corner - there the two touch - and its far end is as high as the
# rake has risen, less one board.
GR = 1.0 / 3.0 # a 4:12 rake

cross = RM.rake_skirt_cross(0.0, 12.0, GR)
ok('the hole starts where the rake clears the top of the board',
   close(cross, RM::SOFFIT_THICK / GR), cross)
ok('it starts INSIDE the return, never before it', cross >= 0.0, cross)
ok('and never past the step', cross <= 12.0, cross)
ok('a steeper rake clears sooner', RM.rake_skirt_cross(0.0, 12.0, 1.0) < cross)
ok('a level rake never clears - no hole at all',
   close(RM.rake_skirt_cross(0.0, 12.0, 0.0), 12.0))
ok('the far-end return measures backwards',
   close(RM.rake_skirt_cross(12.0, 0.0, GR), 12.0 - RM::SOFFIT_THICK / GR),
   RM.rake_skirt_cross(12.0, 0.0, GR))
ok('...and stays inside its own return too', RM.rake_skirt_cross(12.0, 0.0, GR) >= 0.0)

sk = RM.rake_return_skirt([2.25, 0.0], [12.0, 0.0], ZA, ZA + 4.0)
ok('the hole gets a face', !sk.nil?)
ok('it is a triangle', sk.length == 3, sk)
ok('it stands on top of the return board', close(sk[0][2], ZA + RM::SOFFIT_THICK), sk)
ok('and reaches the rake board above it', close(sk[2][2], ZA + 4.0), sk)
ok('it is a closed wedge: two corners low, one high',
   close(sk[0][2], sk[1][2]) && sk[2][2] > sk[1][2], sk)
ok('it sits on the OUTER line, not inward - all three share it',
   close(sk[0][1], 0.0) && close(sk[1][1], 0.0) && close(sk[2][1], 0.0), sk)
ok('a rake that never clears the board leaves no hole to fill',
   RM.rake_return_skirt([2.25, 0.0], [12.0, 0.0], ZA, ZA + 0.1).nil?)

# and end to end: the box is closed on every side now
gg2 = Sketchup::Group.new
RM.build_rake_soffit!(gg2, POLY, 0, ZMAP, 8.0, 12.0)
f2 = gg2.entities.grep(Sketchup::Face)
skirts = f2.select do |f|
  pts = f.points
  pts.length == 3 && pts.all? { |q| q.y.abs < 1e-6 } && pts.map(&:z).uniq.length == 2
end
ok('both returns get their outer face', skirts.length == 2, skirts.length)

# softening the seam must never blow up, stub or not
ok('soften_seams! is safe with nothing to do',
   RM.soften_seams!(gg2, []).nil? || true)
ok('soften_seams! is safe on a group with no edges',
   RM.soften_seams!(gg2, [[[0.0, 0.0, 0.0], [1.0, 1.0, 0.0]]]).nil? || true)


# =====================================================================
# THE DIAGONAL ACROSS THE SOFFIT (user 2026-08-24, twice).
#
# offset_polygon miters every corner of the band, and on a board you look
# straight up at, that miter reads as a diagonal scratch across the
# ceiling. The fascia has the identical seams and nobody minds - there
# they are vertical and an inch long. band_corner_seams is how they are
# found so they can be softened; it must find EVERY corner, on BOTH faces
# of the board, or a stray line is left behind.
SQ = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]].freeze
cs = RM.band_corner_seams(SQ, -12.0, -0.75, 84.0, 84.75)
ok('every corner is found, on both faces', cs.length == 8, cs.length)
ok('each seam runs from the OUTER corner inward', cs[0][0][2] == 84.0, cs[0])
ok('both faces of the board are covered',
   cs.map { |a, _| a[2] }.uniq.sort == [84.0, 84.75], cs.map { |a, _| a[2] }.uniq)
ok('a seam is a real line, not a point',
   cs.all? { |a, b| (a[0] - b[0]).abs + (a[1] - b[1]).abs > 1.0 }, cs.first)
ok('both ends of a seam sit at the same height',
   cs.all? { |a, b| close(a[2], b[2]) }, cs.first)
ok('the seam reaches from the roof edge back to the wall',
   close(Math.sqrt((cs[0][0][0] - cs[0][1][0])**2 + (cs[0][0][1] - cs[0][1][1])**2),
         Math.sqrt(2) * 11.25), cs[0])
ok('a polygon that cannot be offset gives no seams, not a crash',
   RM.band_corner_seams([[0.0, 0.0], [1.0, 0.0]], -12.0, -0.75, 84.0, 84.75).is_a?(Array))


# =====================================================================
# ONE BOARD, NOT TWO (user 2026-08-24: "תעשה אותו יחידה אחת עם הפאשיה").
#
# The skirt triangle's long side lies exactly along the bottom of the rake
# fascia and in the same vertical plane, so SketchUp draws a joint there
# and the eye reads a diagonal scratch across one board. These pin that
# the line really is shared - if it ever stopped coinciding, softening it
# would be hiding the wrong edge and a gap would open instead.
SKIRT = RM.rake_return_skirt([2.25, 0.0], [12.0, 0.0], ZA, ZA + 4.0)
ok('the triangle stands in the plane of the rake - one y for all of it',
   SKIRT.map { |p| p[1] }.uniq.length == 1, SKIRT)
hyp_a = SKIRT[0]
hyp_b = SKIRT[2]
ok('its long side starts on top of the return board',
   close(hyp_a[2], ZA + RM::SOFFIT_THICK), hyp_a)
ok('and ends where the rake board is', close(hyp_b[2], ZA + 4.0), hyp_b)
ok('so the side really does climb - it is the diagonal, not a flat edge',
   hyp_b[2] > hyp_a[2] && hyp_b[0] > hyp_a[0], [hyp_a, hyp_b])

# and the softener has to be able to find that line from either direction
ggs = Sketchup::Group.new
ok('softening a seam given backwards is not an error',
   RM.soften_seams!(ggs, [[hyp_b, hyp_a]]).nil? || true)


# =====================================================================
# FINDING A SEAM THAT HAS BEEN SPLIT (2026-08-24).
#
# Softening by endpoints alone did not hold: every face added on the same
# line splits that edge, and the halves no longer start and end where the
# seam does, so the softener walked straight past them and the diagonal
# stayed. An edge now counts if it simply LIES ON the seam.
P0 = [0.0, 0.0, 84.0]
P1 = [12.0, 12.0, 84.0]
ok('an endpoint of the seam is on it', RM.on_segment?(P0, P0, P1, 0.01))
ok('the far end is on it', RM.on_segment?(P1, P0, P1, 0.01))
ok('the MIDDLE is on it - this is the half a split leaves',
   RM.on_segment?([6.0, 6.0, 84.0], P0, P1, 0.01))
ok('a point just off the line is not', !RM.on_segment?([6.0, 6.5, 84.0], P0, P1, 0.01))
ok('a point at the right height but past the end is not',
   !RM.on_segment?([13.0, 13.0, 84.0], P0, P1, 0.01))
ok('a point above the line is not - height counts too',
   !RM.on_segment?([6.0, 6.0, 85.0], P0, P1, 0.01))
ok('a hair off is forgiven, so float noise does not lose a seam',
   RM.on_segment?([6.0, 6.0, 84.005], P0, P1, 0.01))
ok('a zero-length seam matches nothing instead of dividing by zero',
   !RM.on_segment?(P0, P0, P0, 0.01))


# =====================================================================
# ONE RULE FOR ALL OF THEM (2026-08-24, after three rounds of the user
# pointing at yet another diagonal).
#
# Chasing seams one at a time kept missing one. The rule instead: inside
# the soffit, an edge with a face on each side and BOTH FACES IN THE SAME
# PLANE is a joint between flush boards, not a corner, and is softened.
# It must NOT touch a real corner - the 90 degree step is the whole point
# of the box and has to keep its line.
ok('softening a flush seam is safe with nothing to soften',
   RM.soften_flush_seams!([]).nil? || true)
ok('...and with faces that have no edges at all, as in the stub',
   RM.soften_flush_seams!(Sketchup::Group.new.entities.grep(Sketchup::Face)).nil? || true)

# the geometry that rule has to leave alone: the step really is a corner.
# its face is VERTICAL while the boards either side of it are not.
STEP = RM.rake_soffit_step([12.0, 0.0], INW, ZA, ZA + 4.0)
ok('the step face is vertical - never in the plane of a board',
   close(STEP[0][0], STEP[3][0]) && close(STEP[0][1], STEP[3][1]), STEP)
BOARD = RM.rake_soffit_quad([0.0, 0.0], [12.0, 0.0], ZA, ZA, DIR, INW, OH, 0.0)
ok('the return board is level - so the two are NOT coplanar',
   BOARD.map { |p| p[2] }.uniq.length == 1, BOARD)


# =====================================================================
# THE SQUARE END (2026-08-24, second round - and the one that finally
# killed the diagonal instead of trying to hide it).
#
# Measured on the user's model: the flat eave board ended on a 45 degree
# miter 0.75" back from the corner, the rake return filled the other half
# of the corner square and ran all the way out to the poly line - which
# is INSIDE the rake board. Two boards sharing one underside plane draw a
# line no amount of soft+smooth can take away.
#
# So: no diagonal at all. At a gable corner the flat band runs straight
# across the corner square and is cut SQUARE on the rake band's own outer
# line, and the rake soffit starts where that box ends.
# WHERE the cut goes is the whole of it. The first try cut on the
# soffit's own k_out, 0.75" back from the poly line - and the rake board
# does NOT stand there: build_rake_board! pushes it OUTWARD from the poly
# line, so the board stopped short and the user could see daylight
# between it and the rake fascia. The cut line is the poly line, k = 0.
SQP = [[0.0, 0.0], [240.0, 0.0], [240.0, 120.0], [0.0, 120.0]].freeze
K_IN = -12.0
K_OUT = -0.75

sqc = RM.band_square_corner(SQP, 0, 1, K_IN, 0.0)
ok('the square corner reaches the rake board\'s inner face - the poly line',
   close(sqc[0], 240.0), sqc)
ok('...and stays on its OWN inner line - the cut is perpendicular',
   close(sqc[1], 12.0), sqc)
sqo = RM.band_square_corner(SQP, 0, 1, K_OUT, 0.0)
ok('the outer corner is cut on the same line, so the end really is square',
   close(sqo[0], sqc[0]), [sqc, sqo])
ok('...and it is the only thing that moved out there',
   close(sqo[1], 0.75), sqo)
mit = RM.offset_polygon(SQP, K_IN)[1]
ok('the mitered corner it replaces stopped 12" short', close(mit[0], 228.0), mit)
ok('cutting on k_out instead is what left the gap',
   close(RM.band_square_corner(SQP, 0, 1, K_IN, K_OUT)[0], 239.25))
ok('two parallel lines never cross, and nil means "leave the miter alone"',
   RM.band_square_corner([[0.0, 0.0], [10.0, 0.0], [20.0, 0.0], [0.0, 5.0]],
                         0, 1, K_IN, 0.0).nil?)

# end to end on the stub: with the flag the band really does reach across
GB_FLAGS = [false, true, false, false].freeze
plain = Sketchup::Group.new
RM.build_band!(plain, SQP, K_IN, K_OUT, 84.75, 84.0, GB_FLAGS, nil)
sqrd = Sketchup::Group.new
RM.build_band!(sqrd, SQP, K_IN, K_OUT, 84.75, 84.0, GB_FLAGS, nil, GB_FLAGS)
reach = lambda do |g, y|
  g.entities.grep(Sketchup::Face).flat_map(&:points)
   .select { |p| close(p.y, y, 1e-4) }.map(&:x).max
end
ok('mitered, the inner edge stops one overhang short',
   close(reach.call(plain, 12.0), 228.0), reach.call(plain, 12.0))
ok('squared, it runs all the way to the rake board',
   close(reach.call(sqrd, 12.0), 240.0), reach.call(sqrd, 12.0))
ok('and so does the outer edge - a rectangle, not a wedge',
   close(reach.call(sqrd, 0.75), 240.0), reach.call(sqrd, 0.75))
ok('the gable edge itself still gets no flat band either way',
   plain.entities.grep(Sketchup::Face).length ==
     sqrd.entities.grep(Sketchup::Face).length)

# and the rake soffit meets that same line from the other side
gy = Sketchup::Group.new
RM.build_rake_soffit!(gy, POLY, 0, ZMAP, 8.0, 12.0)
ys = gy.entities.grep(Sketchup::Face).flat_map(&:points).map(&:y)
ok('the rake soffit reaches the poly line, flush under the rake board',
   close(ys.min, 0.0), ys.min)
ok('...and never wider than the overhang', close(ys.max, 12.0), ys.max)

puts($fails.zero? ? 'rt84 ALL PASS' : "rt84 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

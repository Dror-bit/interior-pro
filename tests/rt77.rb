# encoding: utf-8
# rt77 - the four roof tile pieces (2026-08-19, hybrid roof step 2).
#
# THE WHOLE POINT OF THE FILE UNDER TEST
# Instant Roof's 63x59ft roof carries ONE repeated 3D piece - va_BirdStop,
# 408 instances of a definition holding a SINGLE face (valiroof_report.txt).
# One definition, hundreds of instances: SketchUp stores it once and draws it
# hundreds of times. Everything below exists to keep that true.
#
# So this suite pins two things and they are both about cost:
#   1. a piece is CHEAP           - <= 8 faces, always
#   2. a piece is BUILT ONCE      - ask twice, get the same definition back
#                                   and no new geometry
# and one about correctness:
#   3. it is modelled in the plane's own frame (+X across, +Y up the slope,
#      +Z out of the roof) so the placer can put it anywhere with
#      Transformation.axes and no world-axis assumptions.
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RTP = InteriorPro::RoofTileParts
RTM = InteriorPro::RoofTileMath
M = Sketchup.active_model

def faces_of(d)
  d.entities.grep(Sketchup::Face)
end

def pts_of(d)
  faces_of(d).flat_map(&:points)
end

# ------------------------------------------------------------ they build
PIECES = %w[eave rake ridge hip].freeze
PIECES.each do |p|
  d = RTP.send(p, M, 'barrel')
  ok("#{p}: a definition comes back", !d.nil?)
  ok("#{p}: it holds geometry", !d.nil? && faces_of(d).length > 0,
     d && faces_of(d).length)
end

# ------------------------------------------------------------ they are cheap
# The budget is the reason this file exists. 8 faces is already generous for
# something the eye reads as a curved tile from 30 feet away.
PIECES.each do |p|
  d = RTP.send(p, M, 'barrel')
  ok("#{p}: 8 faces or fewer", faces_of(d).length <= 8, faces_of(d).length)
end

total = PIECES.sum { |p| faces_of(RTP.send(p, M, 'barrel')).length }
ok('>>> a whole material costs about 30 unique faces, whatever the house',
   total <= 32, total)

# ------------------------------------------------------- built ONCE, cached
# If this ever breaks, every instance on the roof becomes unique geometry and
# the whole approach is gone - silently, with the roof still looking right.
PIECES.each do |p|
  first = RTP.send(p, M, 'barrel')
  n1 = faces_of(first).length
  again = RTP.send(p, M, 'barrel')
  ok("#{p}: asking twice gives the SAME definition", first.equal?(again))
  ok("#{p}: and builds nothing the second time", faces_of(again).length == n1,
     [n1, faces_of(again).length])
end

before = M.definitions.length
3.times { RTP.all(M, 'barrel') }
ok('asking for the whole set again adds no definitions',
   M.definitions.length == before, [before, M.definitions.length])

# A DIFFERENT material must NOT reuse the first one's geometry - that is the
# reload!/frozen-constant trap one level up (2026-08-14, 2026-08-18), where
# the numbers changed on disk and the old shape stayed in memory.
slate = RTP.eave(M, 'slate')
barrel = RTP.eave(M, 'barrel')
ok('a different material gets its OWN definition', !slate.equal?(barrel))
ok('and the name says which is which',
   slate.name.include?('slate') && barrel.name.include?('barrel'),
   [slate.name, barrel.name])

# ------------------------------------------------------------- the frame
# +X across the slope, +Y up it, +Z out of the roof. The placer relies on
# this and nothing else.
e = RTP.eave(M, 'barrel')
w = RTM.shape('barrel')[:tile_w]
xs = pts_of(e).map(&:x)
ys = pts_of(e).map(&:y)
zs = pts_of(e).map(&:z)
ok('the eave piece is exactly one tile wide across the slope',
   (xs.max - xs.min - w).abs < 0.01, xs.max - xs.min)
ok('and centred on x = 0, so a slot centre is the whole placement',
   (xs.max + xs.min).abs < 0.01, [xs.min, xs.max])
ok('it hangs out PAST the roof edge, like a real tile',
   ys.min < -0.5, ys.min)
ok('and reaches up the slope by the nose the user chose',
   (ys.max - RTP.eave_nose).abs < 0.01, ys.max)
ok('it sits ON the plane and stands out of it, never into it',
   zs.min > -0.001 && zs.max > 0.3, [zs.min, zs.max])

# ------------------------------------------------------ the flat materials
# Slate and standing seam have no barrel, so they get a plain square nose -
# same budget, right silhouette. A round profile on a slate roof would be
# wrong AND more expensive.
flat_prof = RTP.profile(12.0, 1.2, false)
round_prof = RTP.profile(12.0, 1.2, true)
ok('a flat material gets a plain rectangle', flat_prof.length == 4, flat_prof.length)
ok('a round one gets more points than that', round_prof.length > 4, round_prof.length)
ok('no two profile points are ever identical (add_face refuses those)',
   round_prof.each_cons(2).none? { |a, b| (a[0] - b[0]).abs < 1e-9 && (a[1] - b[1]).abs < 1e-9 })
ok('the round profile starts and ends on the plane',
   round_prof.first[1].abs < 1e-9 && round_prof.last[1].abs < 1e-9,
   [round_prof.first, round_prof.last])
ok('and never dips below it', round_prof.map { |p| p[1] }.min > -1e-9)

# ------------------------------------------------------------- no crashes
ok('an unknown material gives nil, not a crash', RTP.eave(M, 'nonsense').nil?)
ok('a material with no courses still gets an eave piece', !RTP.eave(M, 'seam').nil?)
ok('all() answers for every piece', RTP.all(M, 'barrel').keys.sort == %i[eave hip rake ridge])

# ----------------------------------------------------------- it is wired in
ok('main.rb loads the file', File.read('run_all.sh').include?('roof_tile_parts.rb'))
src = File.read('roof_tile_parts.rb', encoding: 'UTF-8')
ok('every piece is stamped with what it is', src.scan(/'part',\s*'?tile_/).length >= 2)
ok('and with the width it covers, so spacing never guesses from a bounding box',
   src.include?("'coverage_w'"))
ok('nothing here CALLS pushpull (it invents internal faces)',
   !src.include?('.pushpull'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

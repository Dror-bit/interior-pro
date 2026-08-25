# encoding: utf-8
# rt87 - THE GUTTER, step 1: the shape and the sweep (2026-08-28).
#
# WHAT THIS IS
# The user asked for gutters and answered the two shape questions himself:
# all THREE profiles - K-style, half round, box - and "רק באיב", never on
# the gable rake. This step builds neither into a roof. It adds the pure
# cross section and a generic sweep, and nothing calls them yet, so no
# roof already in his model can move.
#
# THE CLAIMS PINNED HERE
# 1. THE TROUGH IS HOLLOW. A gutter you can see into. The section is the
#    folded metal only - a fraction of the area of the box that contains
#    it. If this ever passes with a solid block the shape is wrong.
# 2. IT NEVER REACHES BACK OVER THE FASCIA. Every point of the section
#    has k >= 0, and k = 0 IS the fascia's outer face (build_band! puts
#    the fascia at -FASCIA_THICK..0). So the gutter cannot eat the soffit
#    or the wall, and the fascia stays exactly where it was.
# 3. THE SECTION IS BUILDABLE. No repeated point - real SketchUp refuses
#    a face with one, and the stub refuses it too (2026-08-24).
# 4. ROUND IS A TRUE HALF PIPE, hung on a straight lip. The lip is not
#    decoration: a bare semicircle's inner rim tilts UP off the first
#    sampled segment and the gutter pokes past the roof edge.
# 5. K-STYLE IS AN OGEE, NOT A BOX. Its bottom is narrower than its top,
#    and its front lip reaches the full width.
# 6. EAVES ONLY. Handed the roof's gable_flags, the sweep builds NOTHING
#    on a flagged edge. This is the user's "רק באיב", pinned.
# 7. THE RAKE CORNER IS CUT SQUARE. With square_flags the run stops flat
#    on the neighbour's line instead of running out past the building
#    corner on a 45 degree diagonal - the same diagonal that came off the
#    soffit on 2026-08-24.
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
W  = 5.0
H  = 4.5
T  = RM::GUTTER_WALL
D  = RM::GUTTER_DROP

def area(sec)
  a = 0.0
  n = sec.length
  n.times do |i|
    p = sec[i]
    q = sec[(i + 1) % n]
    a += p[0] * q[1] - q[0] * p[1]
  end
  (a / 2.0).abs
end

# ------------------------------------------------ all three shapes exist
secs = {}
RM::GUTTER_PROFILES.each do |pr|
  s = RM.gutter_section(pr, W, H)
  secs[pr] = s
  ok("#{pr}: there is a section at all", !s.nil? && s.length >= 6, s && s.length)
end
ok('the user got all three profiles he asked for',
   RM::GUTTER_PROFILES.sort == %w[box k round], RM::GUTTER_PROFILES)

secs.each do |pr, s|
  next if s.nil?
  ks = s.map { |p| p[0] }
  zs = s.map { |p| p[1] }

  # ------------------------------------------- 2. never back over the fascia
  ok("#{pr}: nothing reaches back past the fascia face", ks.min >= -1e-9, ks.min)
  ok("#{pr}: it hangs outside, not inside", ks.max > 1.0, ks.max)
  ok("#{pr}: it never pokes up past the roof edge", zs.max <= -D + 1e-9, zs.max)

  # ------------------------------------------------------- 1. it is hollow
  box = (ks.max - ks.min) * (zs.max - zs.min)
  ok("#{pr}: the trough is hollow, not a solid block",
     area(s) < 0.35 * box, [area(s).round(3), box.round(3)])
  ok("#{pr}: but it is real metal, not a zero-thickness sheet",
     area(s) > 0.5 * T, area(s).round(3))

  # -------------------------------------------------- 3. SketchUp can build it
  dup = false
  s.each_with_index do |p, i|
    q = s[(i + 1) % s.length]
    dup = true if (p[0] - q[0]).abs < 1e-4 && (p[1] - q[1]).abs < 1e-4
  end
  ok("#{pr}: no repeated point - SketchUp will take the face", !dup)
end

# --------------------------------------------- 4. round is a true half pipe
r   = W / 2.0
lip = RM::GUTTER_LIP
out = RM.gutter_path('round', W, H)
arc = out[1..-2]
ok('round: the pipe itself is a circle of radius w/2',
   arc.all? { |k, z| close(Math.hypot(k - r, z + D + lip), r, 1e-6) }, arc.first)
ok('round: it hangs exactly lip + w/2 deep',
   close(out.map { |_k, z| z }.min, -D - lip - r), out)
ok('round: it has a straight lip at each end, so its rim is level',
   close(out.first[1], -D) && close(out.last[1], -D), [out.first, out.last])

# ------------------------------------------------ 5. K-style is an ogee
kp = RM.gutter_path('k', W, H)
bottom = kp.select { |_k, z| close(z, -D - H, 1e-6) }.map { |k, _z| k }
ok('k: its bottom is narrower than its top', bottom.max < W - 0.5, bottom)
ok('k: its front lip still reaches the full width',
   close(kp.map { |k, _z| k }.max, W), kp.map { |k, _z| k }.max)
ok('k: and it is NOT the box', kp != RM.gutter_path('box', W, H))

# ================================================== 6. EAVES ONLY ==========
# A 100 x 60 rectangle, counter-clockwise. Outward is to the RIGHT of the
# direction of travel, so edge 0 (y = 0, heading +x) grows into -y.
POLY = [[0.0, 0.0], [100.0, 0.0], [100.0, 60.0], [0.0, 60.0]]
GABLE = [false, true, false, true]   # the two short ends are gable rakes
ZREF  = 87.0

def build(section, flags, sq = nil)
  g = Sketchup.active_model.entities.add_group
  RM.build_profile_band!(g, POLY, section, ZREF, flags, nil, sq, 0.0)
  g.entities.grep(Sketchup::Face)
end

sec = secs['box']
all_faces = build(sec, nil)
eave_only = build(sec, GABLE)

ok('with no flags it runs the whole way round', all_faces.length > 0)
ok('flagging the rakes builds strictly less',
   eave_only.length < all_faces.length, [eave_only.length, all_faces.length])
ok('and it is exactly half - two eaves of four edges',
   eave_only.length * 2 == all_faces.length, [eave_only.length, all_faces.length])

pts = eave_only.flat_map(&:points)
ok('every bit of gutter sits on an eave, none on a rake',
   pts.all? { |p| p.y <= 1e-6 || p.y >= 60.0 - 1e-6 },
   pts.reject { |p| p.y <= 1e-6 || p.y >= 60.0 - 1e-6 }.first)
ok('it hangs OUTSIDE the eave line, never over the roof',
   pts.all? { |p| p.y <= 1e-6 || p.y >= 60.0 - 1e-6 })
ok('it hangs below the roof edge', pts.map(&:z).max <= ZREF - D + 1e-6,
   pts.map(&:z).max)
ok('and no deeper than the section says',
   close(pts.map(&:z).min, ZREF - D - H), pts.map(&:z).min)

# =========================================== 7. the rake corner is square ==
sq_faces = build(sec, GABLE, GABLE)
sq_pts = sq_faces.flat_map(&:points)
ok('square corner: nothing runs out past the building corner',
   sq_pts.all? { |p| p.x >= -1e-6 && p.x <= 100.0 + 1e-6 },
   sq_pts.reject { |p| p.x >= -1e-6 && p.x <= 100.0 + 1e-6 }.first)
ok('the mitered version DOES run out past it - so the flag is doing work',
   pts.any? { |p| p.x > 100.0 + 1e-6 || p.x < -1e-6 })

# ---------------------------------------------------------- rubbish in, nil out
ok('a zero width gutter is no gutter', RM.gutter_section('box', 0.0, H).nil?)
ok('metal thicker than the gutter is no gutter',
   RM.gutter_section('box', W, H, W).nil?)

puts($fails.zero? ? 'ALL OK' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

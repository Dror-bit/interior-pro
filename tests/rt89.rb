# encoding: utf-8
# rt89 - THE DOWNSPOUT, step 1: shape, path and places (2026-08-29).
#
# WHAT THIS IS
# The user asked for downspouts AUTOMATIC, with a click to take one off
# afterwards ("אוטומטי ולחיצה אם אני רוצה להוריד אותם"). This is the
# automatic half's maths only - nothing calls any of it, so no roof he has
# already built can change.
#
# THE CLAIMS PINNED HERE
# 1. THE PIPE FOLLOWS THE GUTTER. Round gutter -> round pipe, anything
#    else -> rectangular. One control fewer, which is the standing UI rule.
# 2. IT STARTS IN THE GUTTER AND ENDS AT THE GROUND, and in between it
#    comes in to the wall on a 45 and hugs it all the way down.
# 3. IT CLEARS THE SOFFIT. The elbow starts at z_turn, which the caller
#    sets below the soffit board - a pipe that turns too high runs
#    straight through it.
# 4. NO WALL, NO PIPE. Too little height to come down -> nil, not a
#    folded-up tangle.
# 5. THE BENDS ARE MITERED. A ring at a corner is wider across than the
#    plain profile, by exactly 1/cos of the half angle - the same rule
#    the gutter's own metal is folded by.
# 6. ONE PER CORNER, NEVER ON A RAKE. A gable house gets four; so does a
#    hip, whose gutter runs right round and has no ends of its own.
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

# ------------------------------------------------------- 1. the profile
rect  = RM.downspout_profile('k')
round = RM.downspout_profile('round')
ok('a K-style gutter gets a rectangular pipe', rect.length == 4, rect.length)
ok('a box gutter too', RM.downspout_profile('box').length == 4)
ok('a half round gutter gets a round pipe', round.length >= 12, round.length)
ok('the rectangle is DS_WIDTH across the eave',
   close(rect.map { |a, _b| a }.max - rect.map { |a, _b| a }.min, RM::DS_WIDTH))
ok('...and DS_DEPTH out from the wall',
   close(rect.map { |_a, b| b }.max - rect.map { |_a, b| b }.min, RM::DS_DEPTH))
ok('the round pipe is a circle of radius DS_WIDTH/2',
   round.all? { |a, b| close(Math.hypot(a, b), RM::DS_WIDTH / 2.0, 1e-9) })
ok('every profile is centred on the path', close(rect.map { |a, _b| a }.sum, 0.0, 1e-9))

# ---------------------------------------------------------- 2/3. the path
ZTOP = -5.0      # inside the gutter trough
ZTURN = -9.0     # below the soffit board
KSTART = 2.5     # out at the gutter
KWALL = -17.0    # in at the wall face
ZGND = -90.0     # the ground, relative to band_top

path = RM.downspout_path(ZTOP, ZTURN, KSTART, KWALL, ZGND)
ok('there is a path', !path.nil? && path.length >= 4, path && path.length)
ok('it starts up inside the gutter', close(path.first[1], ZTOP) &&
   close(path.first[0], KSTART), path.first)
ok('it drops STRAIGHT before it turns - no diagonal against the fascia',
   close(path[0][0], path[1][0]) && close(path[1][1], ZTURN), path[0..1])
ok('the elbow does not start above the soffit', path[1][1] <= ZTURN + 1e-9,
   path[1][1])
ok('the elbow comes in to the wall at 45 degrees',
   close((path[2][0] - path[1][0]).abs, (path[2][1] - path[1][1]).abs),
   [path[1], path[2]])
ok('...and lands ON the wall line', close(path[2][0], KWALL), path[2])
ok('then it hugs the wall straight down', close(path[3][0], KWALL), path[3])
ok('the boot kicks back OUT, away from the footing',
   path.last[0] > KWALL, path.last)
ok('and it stops above the ground, not under it',
   path.last[1] > ZGND && path.last[1] < ZGND + 3.0 * RM::DS_KICK,
   [path.last[1], ZGND])
ok('nothing on the path is below the ground',
   path.all? { |_k, z| z >= ZGND }, path.reject { |_k, z| z >= ZGND })

# ----------------------------------------------- 4. nowhere to come down
ok('a wall too short for a pipe gives nothing back',
   RM.downspout_path(-5.0, -9.0, 2.5, -17.0, -30.0).nil?,
   RM.downspout_path(-5.0, -9.0, 2.5, -17.0, -30.0))
ok('no overhang at all is still fine - it just comes straight down',
   (p2 = RM.downspout_path(-5.0, -9.0, 0.0, 0.0, ZGND)) &&
   p2.all? { |k, _z| close(k, 0.0) || close(k, RM::DS_KICK) }, nil)

# ------------------------------------------------- 5. the bends are mitered
rings = RM.tube_rings(path, rect)
ok('one ring per point of the path', rings.length == path.length, rings.length)
ok('every ring is the whole profile', rings.all? { |r| r.length == rect.length })
straight = rings[3].map { |_a, k, _z| k }
straight_w = straight.max - straight.min
# The turn here is 45 degrees (a vertical run meeting a 45 elbow), so the
# metal is pushed out by 1/cos(22.5).
bend = rings[2].map { |_a, k, z| Math.hypot(k - path[2][0], z - path[2][1]) }
ok('a straight run keeps the pipe its own depth',
   close(straight_w, RM::DS_DEPTH), straight_w)
ok('the 45 degree bend is stretched by 1/cos of its half angle',
   close(bend.max, (RM::DS_DEPTH / 2.0) / Math.cos(Math::PI / 8.0), 1e-9),
   bend.max)
ok('...and a straight point is not stretched at all',
   close(rings[3].map { |_a, k, _z| (k - path[3][0]).abs }.max,
         RM::DS_DEPTH / 2.0, 1e-9),
   rings[3].map { |_a, k, _z| (k - path[3][0]).abs }.max)
ok('the pipe never runs backwards through the wall',
   rings.flatten(1).all? { |_a, k, _z| k >= KWALL - RM::DS_DEPTH / 2.0 - 1e-6 },
   rings.flatten(1).map { |_a, k, _z| k }.min)

# ================================================== 6. WHERE THEY GO ======
POLY  = [[0.0, 0.0], [100.0, 0.0], [100.0, 60.0], [0.0, 60.0]]
GABLE = [false, true, false, true]

hip = RM.downspout_spots(POLY, nil)
ok('a hip roof gets one at every corner', hip.length == 4, hip.length)

gab = RM.downspout_spots(POLY, GABLE)
ok('a gable roof gets one at every corner too', gab.length == 4, gab.length)
ok('EVERY ONE STANDS ON AN EAVE, never on a rake',
   gab.all? { |_p, e| !GABLE[e] }, gab.map { |_p, e| e })
ok('...set back from the corner, not on it',
   gab.all? { |p, _e| POLY.none? { |q| close(p[0], q[0], 1e-9) && close(p[1], q[1], 1e-9) } },
   gab.map { |p, _e| p })
ok('...and by exactly DS_INSET when there is no overhang',
   gab.all? { |p, _e| POLY.map { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) }.min
                        .round(6) == RM::DS_INSET.round(6) },
   gab.map { |p, _e| POLY.map { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) }.min })

# THE ONE THAT COST A ROUND (2026-08-29). `poly` is the EAVE outline, and
# its corner stands one overhang further along the edge than the WALL
# corner. Measure the set back from the poly corner and the pipe lands a
# whole overhang PAST the end of the wall, hanging in the air beside the
# building - which is what the user photographed twice: "זה עדיין לא
# יושב על הקיר".
OH = 18.0
oh_spots = RM.downspout_spots(POLY, GABLE, OH)
ok('with an overhang the set back grows by exactly that overhang',
   oh_spots.all? { |p, _e| POLY.map { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) }
                               .min.round(6) == (OH + RM::DS_INSET).round(6) },
   oh_spots.map { |p, _e| POLY.map { |q| Math.hypot(p[0] - q[0], p[1] - q[1]) }.min })
# The pipe stays ON the eave line - the sideways step to the wall is the
# k half of the job. What has to be right here is how far ALONG the eave
# it sits: DS_INSET past where the end of the wall projects onto it,
# which for this box is OH in from each poly corner.
along = oh_spots.map { |p, _e| [(p[0] - OH).abs, (100.0 - OH - p[0]).abs].min }
ok('...so it stands DS_INSET past the END OF THE WALL, not of the roof',
   along.all? { |a| a.round(6) == RM::DS_INSET.round(6) }, along)
ok('...and every pipe is over the wall it comes down, never off its end',
   oh_spots.all? { |p, _e| p[0] >= OH - 1e-9 && p[0] <= 100.0 - OH + 1e-9 },
   oh_spots.map { |p, _e| p })
ok('a wall too short to take one is skipped, not crammed',
   RM.downspout_spots(POLY, GABLE, 45.0).empty?,
   RM.downspout_spots(POLY, GABLE, 45.0))
ok('all four are different places', gab.map { |p, _e| p.map { |v| v.round(3) } }
                                       .uniq.length == 4)
ok('an edge with no room for one is skipped, not crammed',
   RM.downspout_spots([[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0]], nil).empty?)

# ----------------------------------------------------- it actually builds
g = Sketchup.active_model.entities.add_group
RM.build_tube!(g, POLY, 0, gab.first[0], rings)
fs = g.entities.grep(Sketchup::Face)
ok('the pipe builds as a closed run of faces',
   fs.length == 2 + (rings.length - 1) * rect.length, fs.length)
pts = fs.flat_map(&:points)
# Edge 0 runs +x, so outward is -y and the wall is at +y. The pipe has to
# live between the gutter it hangs off and the wall it comes down, and
# nowhere else.
ok('it never reaches out past the gutter',
   pts.map(&:y).min >= -(KSTART + RM::DS_DEPTH / 2.0) - 1e-6, pts.map(&:y).min)
ok('and never in past the wall it hugs',
   pts.map(&:y).max <= -KWALL + RM::DS_DEPTH / 2.0 + 1e-6, pts.map(&:y).max)
ok('it stands at the spot it was given, DS_WIDTH across the eave',
   close(pts.map(&:x).max - pts.map(&:x).min, RM::DS_WIDTH, 1e-6) &&
   close((pts.map(&:x).max + pts.map(&:x).min) / 2.0, gab.first[0][0], 1e-6),
   [pts.map(&:x).min, pts.map(&:x).max])
ok('and it comes down - top to bottom, not flat',
   pts.map(&:z).max - pts.map(&:z).min > 50.0,
   pts.map(&:z).max - pts.map(&:z).min)

# ============================================ 7. IT IS HOLLOW ============
# "הם צריכים להיות חלולים" (2026-08-29). A pipe you can see down, not a
# stick with a lid on it. The inner skin is the outer one stepped inward
# by one metal thickness, all the way round.
inner_rect = RM.offset_closed_left(rect, RM::DS_WALL)
ok('the rectangle has an inner skin', inner_rect.length == rect.length,
   inner_rect.length)
ok('...one metal thickness in on every side',
   close(rect.map { |a, _b| a }.max - inner_rect.map { |a, _b| a }.max, RM::DS_WALL) &&
   close(inner_rect.map { |_a, b| b }.min - rect.map { |_a, b| b }.min, RM::DS_WALL),
   [rect.map { |a, _b| a }.max, inner_rect.map { |a, _b| a }.max])
ok('...and it really is inside, not outside',
   inner_rect.all? { |a, b| a.abs < RM::DS_WIDTH / 2.0 && b.abs < RM::DS_DEPTH / 2.0 })
inner_round = RM.offset_closed_left(round, RM::DS_WALL)
# A sampled circle is a 16-gon, so stepping every FACE in by t leaves a
# radius of r - t/cos(pi/16), not r - t. The metal is one thickness
# everywhere, which is the claim that matters.
ok('the round pipe too - a smaller circle, still round',
   inner_round.map { |a, b| Math.hypot(a, b).round(6) }.uniq.length == 1 &&
   close(inner_round.map { |a, b| Math.hypot(a, b) }.max,
         RM::DS_WIDTH / 2.0 - RM::DS_WALL, 0.01),
   inner_round.map { |a, b| Math.hypot(a, b).round(4) }.uniq)

g2 = Sketchup.active_model.entities.add_group
RM.build_tube!(g2, POLY, 0, gab.first[0], rings,
               RM.tube_rings(path, inner_rect))
f2 = g2.entities.grep(Sketchup::Face)
ok('a hollow pipe has both skins and two rings of metal at its ends',
   f2.length == 2 + 2 * (rings.length - 1) * rect.length, f2.length)
ok('...which is strictly more than the solid one had', f2.length > fs.length)

# ==================================== 8. IT HANGS OFF THE FLAT BOTTOM =====
# A pipe centred on the gutter's mid width comes out through the FRONT of
# a K-style, because that shape's bottom is only its first 42%. The user
# saw it at once: "צריך להיות מחובר מהלמטה של הגאטרס".
GW = 5.0
GH = GW * RM::GUTTER_H_RATIO
# ACROSS the gutter the pipe is DS_DEPTH wide, not DS_WIDTH - a real
# 2x3 downspout turns its 3" face along the wall. That 2" is what has to
# land on the bottom of the trough.
HALF = RM::DS_DEPTH / 2.0
def bottom_span(pr)
  gp = RM.gutter_path(pr, GW, GH)
  zlo = gp.map { |(_k, z)| z }.min
  ks = gp.select { |(_k, z)| z <= zlo + 0.05 }.map { |(k, _z)| k }
  [ks.min, ks.max]
end
%w[k round box].each do |pr|
  ko = RM.gutter_outlet_k(pr, GW, GH)
  lo, hi = bottom_span(pr)
  ok("#{pr}: the outlet is centred on the lowest part of the trough",
     ko >= lo - 1e-9 && ko <= hi + 1e-9, [pr, ko, lo, hi])
end
%w[k box].each do |pr|
  ko = RM.gutter_outlet_k(pr, GW, GH)
  lo, hi = bottom_span(pr)
  ok("#{pr}: the WHOLE hole is on the flat bottom, not through the front",
     ko - HALF >= lo - 1e-9 && ko + HALF <= hi + 1e-9,
     [pr, ko - HALF, ko + HALF, lo, hi])
end
ok('k-style: the OLD centre-of-the-gutter outlet would have missed it',
   (GW / 2.0) + HALF > bottom_span('k')[1] + 1e-9,
   [(GW / 2.0) + HALF, bottom_span('k')[1]])
ok('k-style: the outlet is NOT the middle of the gutter',
   (RM.gutter_outlet_k('k', GW, GH) - GW / 2.0).abs > 0.5,
   RM.gutter_outlet_k('k', GW, GH))
ok('box: the middle IS the bottom, so it stays in the middle',
   close(RM.gutter_outlet_k('box', GW, GH), GW / 2.0),
   RM.gutter_outlet_k('box', GW, GH))

puts($fails.zero? ? 'ALL OK' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

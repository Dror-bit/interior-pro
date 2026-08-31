# encoding: utf-8
# rt128 - THE DUTCH GABLE, STEP 1: dutch_poly (2026-09-09).
#
# WHY
# The user asked for a Dutch gable off two photos of his own: the SAME
# roof - same ridge, same height - with a small hip apron climbing from
# the fascia and a vertical gable standing on it up to the ridge. He
# picked the one number that drives it: how deep that apron is, measured
# IN FROM THE FASCIA. See DUTCH_GABLE_PROPOSAL.md.
#
# WHAT IS PINNED HERE
# Only the pure step: the ring the skeleton will be built on. The marked
# edge moves inward by the depth, its two neighbours follow it, and every
# other corner stays EXACTLY where it was - because the fascia, the
# soffit and the trim on all the other edges must not move by a
# thousandth of an inch when a Dutch depth is typed.
# And the refusals: a depth of zero or less, and a push so deep the edge
# collapses or turns back on itself, both return nil so the caller falls
# back to the plain gable it builds today.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

RM = InteriorPro::RoofManager

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    FAILS << name
    puts "FAIL  #{name}   << #{extra.inspect}"
  end
end
def close(a, b, tol = 0.001)
  !a.nil? && !b.nil? && (a - b).abs < tol
end
def pt_close(p, q, tol = 0.001)
  !p.nil? && close(p[0], q[0], tol) && close(p[1], q[1], tol)
end

# a plain CCW rectangle, 240 x 120, corner at the origin
SQ = [[0.0, 0.0], [240.0, 0.0], [240.0, 120.0], [0.0, 120.0]]

ok('dutch_poly is there', RM.respond_to?(:dutch_poly))

# ---- edge 0 is the south side (y = 0). Inward is +y. ------------------
out = RM.dutch_poly(SQ, 0, 24.0)
ok('a 24" push returns a ring', !out.nil? && out.length == 4, out)
ok('...the marked edge sits 24" in', out && close(out[0][1], 24.0) &&
   close(out[1][1], 24.0), out && [out[0], out[1]])
ok('...and keeps its x, because its neighbours are square to it',
   out && close(out[0][0], 0.0) && close(out[1][0], 240.0),
   out && [out[0], out[1]])
ok('...while the OTHER two corners do not move at all',
   out && pt_close(out[2], SQ[2]) && pt_close(out[3], SQ[3]),
   out && [out[2], out[3]])
ok('...and the original ring is untouched', pt_close(SQ[0], [0.0, 0.0]))

# ---- edge 3 is the west side (x = 0). Inward is +x. -------------------
w = RM.dutch_poly(SQ, 3, 18.0)
ok('the west edge pushes the other way',
   w && close(w[3][0], 18.0) && close(w[0][0], 18.0), w && [w[3], w[0]])
ok('...and the east corners stay put',
   w && pt_close(w[1], SQ[1]) && pt_close(w[2], SQ[2]), w && [w[1], w[2]])

# ---- the refusals -----------------------------------------------------
ok('zero depth is nil - the caller keeps the plain gable',
   RM.dutch_poly(SQ, 0, 0.0).nil?)
ok('a negative depth is nil', RM.dutch_poly(SQ, 0, -10.0).nil?)
ok('a push right through the roof is nil',
   RM.dutch_poly(SQ, 0, 130.0).nil?, RM.dutch_poly(SQ, 0, 130.0))
ok('a push to the far wall is nil too',
   RM.dutch_poly(SQ, 0, 120.0).nil?, RM.dutch_poly(SQ, 0, 120.0))
ok('nil ring is nil', RM.dutch_poly(nil, 0, 24.0).nil?)

# ---- a splayed corner: the neighbour is NOT square to the edge --------
# the west side leans, so pushing the south edge in must slide its left
# end ALONG that leaning wall, not straight up.
TR = [[0.0, 0.0], [240.0, 0.0], [240.0, 120.0], [60.0, 120.0]]
t = RM.dutch_poly(TR, 0, 24.0)
ok('a leaning neighbour still meets the pushed line',
   t && close(t[0][1], 24.0) && close(t[1][1], 24.0), t && [t[0], t[1]])
# the west wall runs (0,0) -> (60,120): at y = 24 it is at x = 12
ok('...and it lands ON that wall, not beside it',
   t && close(t[0][0], 12.0), t && t[0])
ok('...the far corners are still untouched',
   t && pt_close(t[2], TR[2]) && pt_close(t[3], TR[3]), t && [t[2], t[3]])

# ---- the ring stays usable: same length, same winding ----------------
def ring_area(r)
  a = 0.0
  n = r.length
  n.times { |k| j = (k + 1) % n; a += r[k][0] * r[j][1] - r[j][0] * r[k][1] }
  a / 2.0
end
ok('the ring keeps its length', out && out.length == SQ.length)
ok('...its winding is still CCW', out && ring_area(out) > 0.0,
   out && ring_area(out))
ok('...and it is smaller than the roof it came from',
   out && ring_area(out) < ring_area(SQ),
   out && [ring_area(out), ring_area(SQ)])

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

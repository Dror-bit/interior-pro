# encoding: utf-8
# rt72 — roof_tile_math.rb: the pure foundation for 3D tile courses.
# No SketchUp, no model, no geometry: plain numbers in, plain numbers out.
# If this suite is green the maths is trustworthy BEFORE any roof is touched.
#
# The shape of the answer came from MEASURING a real Instant Roof roof in the
# user's own project (debug_valiroof.rb, 2026-08-18): course strips + a
# texture, 3D only where the silhouette shows.
require './roof_tile_math'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); !a.nil? && !b.nil? && (a - b).abs < tol; end

RTM = InteriorPro::RoofTileMath

# A 6:12 plane: 200" along the eave, 100" of PLAN run, rising toward +Y.
#   z = 0.5 * y, so 100" of run is 111.803" of real roof.
SQ = [[0.0, 0.0, 0.0], [200.0, 0.0, 0.0], [200.0, 100.0, 50.0], [0.0, 100.0, 50.0]]
NRM = [0.0, -0.4472135955, 0.894427191]
TRUE_RUN = 100.0 * Math.sqrt(1.25)     # 111.8034

# ------------------------------------------------------------------ frame

fr = RTM.plane_frame(NRM)
ok('plane_frame -> nil on a zero vector',  RTM.plane_frame([0.0, 0.0, 0.0]).nil?)
ok('plane_frame -> nil on a WALL (vertical)', RTM.plane_frame([1.0, 0.0, 0.0]).nil?)
ok('a dead level plane is flagged flat',   RTM.plane_frame([0.0, 0.0, 1.0])[:flat])
ok('a sloped plane is not flagged flat',   !fr[:flat])
ok('the normal is flipped to point UP',
   RTM.plane_frame([0.0, 0.4472135955, -0.894427191])[:n][2] > 0)
ok('6:12 plane reports pitch 6', close(fr[:pitch], 6.0, 1e-6), fr[:pitch])
ok('u runs along the eave (+X here)',
   close(fr[:u][0], 1.0) && close(fr[:u][2], 0.0), fr[:u])
ok('u is HORIZONTAL - a course line is level', close(fr[:u][2], 0.0), fr[:u][2])
ok('v climbs the slope', fr[:v][2] > 0, fr[:v])
# the frame must be right handed or every strip is built inside out
cr = RTM.vcross(fr[:u], fr[:v])
ok('u x v = n (right handed frame)',
   close(cr[0], fr[:n][0]) && close(cr[1], fr[:n][1]) && close(cr[2], fr[:n][2]), cr)

# ------------------------------------------------------------------- plane

pl = RTM.plane_uv(SQ, NRM)
ok('plane_uv -> nil with fewer than 3 points', RTM.plane_uv([[0, 0, 0], [1, 1, 1]], NRM).nil?)
ok('plane_uv -> nil on a wall', RTM.plane_uv(SQ, [1.0, 0.0, 0.0]).nil?)
ok('v = 0 sits on the eave', close(pl[:poly].map { |p| p[1] }.min, 0.0), pl[:poly])
ok('u = 0 sits on the left edge', close(pl[:poly].map { |p| p[0] }.min, 0.0), pl[:poly])
ok('u_span is the eave length', close(pl[:u_span], 200.0, 1e-6), pl[:u_span])
ok('v_span is the TRUE slope length, not the plan run',
   close(pl[:v_span], TRUE_RUN, 1e-6), pl[:v_span])
ok('...and it is longer than the plan run', pl[:v_span] > 100.0 + 1.0, pl[:v_span])
# a point put back through the frame must land where it started
back = RTM.unproject(pl[:poly][2], pl[:origin], pl[:u], pl[:v])
ok('project then unproject returns the same 3D point',
   close(back[0], 200.0, 1e-6) && close(back[1], 100.0, 1e-6) && close(back[2], 50.0, 1e-6), back)

# ---------------------------------------------------------------- scanline

RECT = [[0.0, 0.0], [200.0, 0.0], [200.0, 100.0], [0.0, 100.0]]
ok('a rectangle gives one span', RTM.spans_at(RECT, 50.0).length == 1)
ok('...the full width', close(RTM.spans_at(RECT, 50.0)[0][1] -
                              RTM.spans_at(RECT, 50.0)[0][0], 200.0), RTM.spans_at(RECT, 50.0))
ok('below the plane gives nothing', RTM.spans_at(RECT, -5.0).empty?)
ok('above the plane gives nothing', RTM.spans_at(RECT, 105.0).empty?)
ok('exactly at the top edge gives nothing (half open)', RTM.spans_at(RECT, 100.0).empty?)
ok('exactly at the eave gives the full width',
   close(RTM.spans_at(RECT, 0.0)[0][1], 200.0), RTM.spans_at(RECT, 0.0))

# a hip: the course must get SHORTER as it climbs
HIP = [[0.0, 0.0], [200.0, 0.0], [100.0, 100.0]]
w0 = RTM.spans_at(HIP, 0.0)[0]
w5 = RTM.spans_at(HIP, 50.0)[0]
w9 = RTM.spans_at(HIP, 90.0)[0]
ok('hip: bottom course is full width', close(w0[1] - w0[0], 200.0), w0)
ok('hip: halfway up it is half', close(w5[1] - w5[0], 100.0), w5)
ok('hip: near the apex it is a sliver', close(w9[1] - w9[0], 20.0), w9)
ok('hip: the span stays centred', close((w5[0] + w5[1]) / 2.0, 100.0), w5)
ok('hip: the apex itself is empty', RTM.spans_at(HIP, 100.0).empty?)

# a plane with a dormer punched out of it: TWO spans, no special case
NOTCH = [[0.0, 0.0], [200.0, 0.0], [200.0, 100.0], [120.0, 100.0],
         [120.0, 50.0], [80.0, 50.0], [80.0, 100.0], [0.0, 100.0]]
sp = RTM.spans_at(NOTCH, 75.0)
ok('a notch splits the course in two', sp.length == 2, sp)
ok('...left piece is 0..80',  close(sp[0][0], 0.0) && close(sp[0][1], 80.0), sp)
ok('...right piece is 120..200', close(sp[1][0], 120.0) && close(sp[1][1], 200.0), sp)
ok('below the notch it is whole again', RTM.spans_at(NOTCH, 25.0).length == 1)
ok('min_len drops a sliver', RTM.spans_at(HIP, 99.5, 5.0).empty?, RTM.spans_at(HIP, 99.5))

# ----------------------------------------------------------------- courses

vs = RTM.course_vs(100.0, 14.0)
ok('the bottom course sits ON the eave', close(vs.first, 0.0), vs)
ok('courses step by the exposure', close(vs[1] - vs[0], 14.0), vs)
ok('no course lands past the ridge', vs.last < 100.0, vs)
ok('the right number of courses', vs.length == 8, vs.length)
ok('zero exposure means no courses at all', RTM.course_vs(100.0, 0.0).empty?)
ok('a plane with no height has no courses', RTM.course_vs(0.0, 14.0).empty?)
ok('max_courses is a real cap', RTM.course_vs(1e6, 1.0, 0.0, 50).length <= 51,
   RTM.course_vs(1e6, 1.0, 0.0, 50).length)

res = RTM.courses(pl, 'barrel')
ok('barrel lays courses on a real plane', res[:courses].length == 8, res[:courses].length)
ok('every course is cut to the plane',
   res[:courses].all? { |c| c[:spans].length == 1 && close(c[:spans][0][1], 200.0) })
ok('nothing is truncated on a normal roof', !res[:truncated])
ok('standing seam asks for NO courses', RTM.courses(pl, 'seam')[:courses].empty?)
ok('courses? agrees with it', RTM.courses?('barrel') && !RTM.courses?('seam'))
ok('an unknown material is empty, not a crash', RTM.courses(pl, 'nope')[:courses].empty?)

# ----------------------------------------------------------------- scallop

flat = RTM.scallop(0.0, 100.0, 13.0, 0.0)
ok('amp 0 gives a plain straight step', flat.length == 2 &&
   close(flat[0][1], 0.0) && close(flat[1][1], 0.0), flat)
sc = RTM.scallop(0.0, 39.0, 13.0, 1.1, segments: 4)
ok('the scallop starts exactly at u1', close(sc.first[0], 0.0), sc.first)
ok('the scallop ends exactly at u2', close(sc.last[0], 39.0), sc.last)
ok('it runs left to right', sc.each_cons(2).all? { |a, b| b[0] > a[0] - 1e-9 })
ok('it never hangs above the course line', sc.all? { |p| p[1] >= -1e-9 }, sc.map { |p| p[1] }.min)
ok('it never hangs below the amplitude', sc.all? { |p| p[1] <= 1.1 + 1e-9 }, sc.map { |p| p[1] }.max)
ok('a crest sits on the tile grid', close(RTM.drop_at(0.0, 13.0, 1.1), 1.1))
ok('a trough sits half a tile away', close(RTM.drop_at(6.5, 13.0, 1.1), 0.0))
ok('three tiles give three crests',
   sc.count { |p| p[1] > 1.09 } >= 3, sc.count { |p| p[1] > 1.09 })
# the phase is GLOBAL: two spans of one course keep the same rhythm
ok('the wave keeps its rhythm across a dormer',
   close(RTM.drop_at(120.0, 13.0, 1.1), RTM.drop_at(120.0 + 13.0, 13.0, 1.1)))

# ------------------------------------------------------------ edge pieces

sl = RTM.edge_slots(0.0, 39.0, 13.0)
ok('three whole tiles give three pieces', sl.length == 3, sl)
ok('the first piece is centred on its tile', close(sl[0], 6.5), sl)
ok('no piece pokes past the end', sl.all? { |c| c + 6.5 <= 39.0 + 1e-9 }, sl)
ok('a partial tile gets no piece', RTM.edge_slots(0.0, 20.0, 13.0).length == 1,
   RTM.edge_slots(0.0, 20.0, 13.0))
ok('a span narrower than one tile gets nothing', RTM.edge_slots(0.0, 5.0, 13.0).empty?)
ok('pieces sit UNDER the crests, not between them',
   close(RTM.drop_at(sl[0] - 6.5, 13.0, 1.1), 1.1), sl[0])
ok('a shifted span still lands on the global grid',
   RTM.edge_slots(13.0, 39.0, 13.0).length == 2, RTM.edge_slots(13.0, 39.0, 13.0))

ok('a staggered course is offset by half a tile',
   close(RTM.course_phase(0, 12.0, true), 0.0) &&
   close(RTM.course_phase(1, 12.0, true), 6.0))
ok('barrel never staggers',
   close(RTM.course_phase(1, 13.0, false), 0.0))

# -------------------------------------------------------------- estimate

est = RTM.estimate(pl, 'barrel')
ok('the estimate counts the courses', est[:courses] == 8, est)
ok('the estimate counts faces, and it is CHEAP',
   est[:faces] > 100 && est[:faces] < 2000, est[:faces])
ok('standing seam estimates nothing to step', RTM.estimate(pl, 'seam')[:faces].zero?)
ok('an unknown material estimates nothing', RTM.estimate(pl, 'nope')[:faces].zero?)

# ---------------------------------------------------------------- shapes

# FIVE since 2026-08-21: Metal Roof Tiles joined, from the user's second
# reference. It is deliberately NOT the same thing as 'seam' - standing seam
# is one unbroken sheet, metal tile is pressed into courses - so both are here
# and neither replaced the other. (This line said four; it was updated rather
# than deleted, the rt65 rule.)
ok('five materials are described', RTM.shapes.length == 5, RTM.shapes.keys)
ok('every one names its texture',
   RTM.shapes.values.all? { |s| s[:texture].to_s.end_with?('.jpg') })
ok('and no two share a texture file',
   RTM.shapes.values.map { |s| s[:texture] }.uniq.length == RTM.shapes.length,
   RTM.shapes.values.map { |s| s[:texture] })
# WAS: only metaltile. Flat tile joined on 2026-08-21c - it is pressed into
# courses for the same reason metal is, because each tile LAPS the one below
# rather than running unbroken from ridge to eave. Clay is still the odd one
# out and that is what this line is really guarding.
ok('flat tile and metal tile are pressed into courses - clay is one pipe',
   RTM.shapes.keys.select { |k| RTM.run_courses?(k) }.sort ==
     %w[metaltile slate],
   RTM.shapes.keys.select { |k| RTM.run_courses?(k) })
ok('standing seam is left exactly as it was, sheet not tile',
   !RTM.run_courses?('seam') && RTM.shapes['seam'][:exposure].zero?)
# Only the flat tile staggers, and as of 2026-08-21c the flag finally DOES
# something: RoofTilePlace.flat_slots reads course_phase and shifts every other
# course half a tile. Until then `stagger` was a description with no builder
# behind it, which is why the first flat-tile build came out in straight
# columns and the user had to ask for the broken bond by name.
ok('only the flat tile staggers',
   RTM.shapes.select { |_, s| s[:stagger] }.keys == ['slate'],
   RTM.shapes.select { |_, s| s[:stagger] }.keys)
ok('barrel is the waviest',
   RTM.shapes['barrel'][:scallop] > RTM.shapes['roman'][:scallop])
ok('slate and seam are dead flat',
   RTM.shapes['slate'][:scallop].zero? && RTM.shapes['seam'][:scallop].zero?)

# ---------------------------------------------- how many courses actually wave
#
# Added 2026-08-19, when the builder went in and the bill came with it. The
# wave is only visible in SILHOUETTE, and only the eave course has one - so
# only the eave course pays for it. Measured on the user's own roof
# (756" eave, 4:12, barrel): every course wavy = 12,663 faces per plane;
# bottom course only = 599. Same picture from the ground, 21x the cost.
b = RTM.shape('barrel')
ok('by default only the bottom course waves',
   RTM.scallop_amp(0, b) > 0 && RTM.scallop_amp(1, b).zero?)
ok('asking for three gets three', RTM.scallop_amp(2, b, 3) > 0 &&
                                  RTM.scallop_amp(3, b, 3).zero?)
ok('nil means every course waves', RTM.scallop_amp(99, b, nil) > 0)
ok('zero means none of them do', RTM.scallop_amp(0, b, 0).zero?)
ok('a flat material never waves, whatever you ask for',
   RTM.scallop_amp(0, RTM.shape('slate'), nil).zero?)
ok('no shape at all is 0, not a crash', RTM.scallop_amp(0, nil).zero?)

# The estimate has to speak the same policy, or it stops predicting the build.
big = RTM.plane_uv([[0, 0, 0], [756.0, 0, 0], [756.0, 354.0, 118.0], [0, 354.0, 118.0]],
                   RTM.vnorm(RTM.vcross([756.0, 0, 0], [0, 354.0, 118.0])))
all_wavy = RTM.estimate(big, 'barrel', scallop_courses: nil)[:faces]
one_wavy = RTM.estimate(big, 'barrel')[:faces]
none     = RTM.estimate(big, 'barrel', scallop_courses: 0)[:faces]
ok('the estimate defaults to the cheap policy', one_wavy < all_wavy / 10, [one_wavy, all_wavy])
ok('and the user roof lands near what Vali actually built (~2,500 for 4 planes)',
   one_wavy * 4 > 1_500 && one_wavy * 4 < 4_000, one_wavy * 4)
ok('every course wavy really is the 50,000 I was wrong about',
   all_wavy * 4 > 40_000, all_wavy * 4)
ok('no wave at all is cheapest of the three', none < one_wavy, [none, one_wavy])
ok('but the course COUNT never changes - only how the butt is drawn',
   RTM.estimate(big, 'barrel', scallop_courses: nil)[:courses] ==
   RTM.estimate(big, 'barrel', scallop_courses: 0)[:courses])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

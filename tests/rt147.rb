# encoding: utf-8
# rt147 - THE SIDING RUNS INTO THE ROOF, IT IS NOT CUT SHORT ABOVE IT
# (2026-09-13B).
#
# He sent a picture of the dormer cheek with a red line drawn along the
# ends of the boards: a staircase of square ends hanging in the air, with
# daylight between them and the roof. `gable_course_runs` stopped a course
# the moment the roof had climbed past its BOTTOM, so the last board of
# every course died a full step early.
#
# TWO DIAGONAL CUTS WERE TRIED AND BOTH THROWN OUT ON SIGHT - first as a
# plain slab pushed out ("זה נראה איום ונורא"), then as the same lap wedge
# built by hand with a raked foot ("לא טוב"). DO NOT BRING THEM BACK
# without asking him first.
#
# What is built: the board RUNS ON UNDER THE ROOF and the roof covers it.
#
# WHAT IS PINNED HERE: the course reaches past the crossing point, and a
# board the roof has completely swallowed is still never built.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager

# the same two outlines rt142 uses: a flat gable triangle, and a dormer
# cheek whose floor climbs 0 -> 50 across 120
FLAT  = [[0.0, 96.0], [120.0, 156.0], [240.0, 96.0], [240.0, 0.0], [0.0, 0.0]].freeze
CHEEK = [[0.0, 0.0], [0.0, 60.0], [120.0, 110.0], [120.0, 50.0]].freeze

# a course from 10 to 16. The roof crosses its BOTTOM at t=24 and its TOP
# at t=38.4.
runs = RF.gable_course_runs(CHEEK, 0.0, 120.0, 10.0, 16.0, 6.0)
far = runs.map { |_a, b, _z| b }.max.to_f

ok('the course is built', !runs.empty?, runs)

ok('IT DOES NOT STOP WHERE THE ROOF CROSSES ITS BOTTOM',
   far > 24.0 + 1e-6, far)

ok('it carries on until the roof has nearly swallowed it', far >= 36.0, far)

ok('but it stops before the roof has passed its top',
   far <= 42.0 + 1e-6, far)

ok('no gap: the boards cover the run in one piece',
   runs.each_cons(2).all? { |a, b| (b[0] - a[1]).abs < 1e-6 }, runs)

ok('a board the roof has completely swallowed is never built',
   runs.none? do |ta, tb, z|
     [RF.tz_bot_at(CHEEK, ta + 0.001), RF.tz_bot_at(CHEEK, tb - 0.001)].min >= z
   end, runs)

ok('nothing pokes out through the roof above it',
   runs.all? { |ta, tb, z| z <= [RF.tz_top_at(CHEEK, ta), RF.tz_top_at(CHEEK, tb)].min + 1e-6 },
   runs)

ok('a course buried along its whole length builds nothing',
   RF.gable_course_runs(CHEEK, 100.0, 118.0, 124.0, 130.0, 6.0).empty?, nil)

# ---- the gable triangle is untouched --------------------------------
flat = RF.gable_course_runs(FLAT, 0.0, 240.0, 0.0, 6.0, 6.0)
ok('the gable triangle still gets ONE full-width board',
   flat.length == 1 && flat[0][0] == 0.0 && flat[0][1] == 240.0, flat)

high = RF.gable_course_runs(FLAT, 0.0, 240.0, 132.0, 138.0, 6.0)
ok('a course up inside the triangle is still stepped', high.length > 1, high.length)
ok('...and still never pokes through the rake',
   high.all? { |ta, tb, zt| zt <= [RF.tz_top_at(FLAT, ta), RF.tz_top_at(FLAT, tb)].min + 1e-6 },
   high)

# the raked builder is GONE and must stay gone unless he asks
src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('no diagonal-foot builder is wired in', !src.include?('build_raked_siding_board!'), nil)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

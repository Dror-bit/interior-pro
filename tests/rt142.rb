# encoding: utf-8
# rt142 - A WALL THAT STANDS ON A SLOPE (2026-09-13).
#
# The gablet's cheeks got real boards, and he sent a picture from inside
# the attic: "תראה מבתוכו הקווים נמשכים לתוך הבית" - every batten ran
# straight down through the roof and hung in the room.
#
# THE CAUSE: the board builder was written for a gable triangle, which
# sits FLAT on the wall under it, so it started every board at the
# outline's single lowest z. A dormer cheek does not sit flat - it sits
# ON THE ROOF, and its bottom edge climbs with the slope. Starting at the
# lowest corner put most of the board below the roof.
#
# WHAT IS PINNED HERE: the outline's own floor at each t, and that a flat
# bottomed outline - every gable triangle in the model - is unchanged.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager

# a gable triangle: 240 wide, wall top at 96, ridge at 156, flat floor
FLAT = [[0.0, 96.0], [120.0, 156.0], [240.0, 96.0], [240.0, 0.0], [0.0, 0.0]].freeze
# a dormer cheek: the bottom climbs 0 -> 50 across 120, the top is the
# gablet's own roof line
CHEEK = [[0.0, 0.0], [0.0, 60.0], [120.0, 110.0], [120.0, 50.0]].freeze

ok('flat outline: the floor is 0 at the left', RF.tz_bot_at(FLAT, 0.0) == 0.0,
   RF.tz_bot_at(FLAT, 0.0))
ok('flat outline: the floor is still 0 in the middle',
   RF.tz_bot_at(FLAT, 120.0) == 0.0, RF.tz_bot_at(FLAT, 120.0))
ok('flat outline: and 0 at the right', RF.tz_bot_at(FLAT, 240.0) == 0.0,
   RF.tz_bot_at(FLAT, 240.0))

ok('cheek: the floor starts at 0', (RF.tz_bot_at(CHEEK, 0.0) - 0.0).abs < 1e-6,
   RF.tz_bot_at(CHEEK, 0.0))
ok('cheek: half way along it has climbed to 25',
   (RF.tz_bot_at(CHEEK, 60.0) - 25.0).abs < 1e-6, RF.tz_bot_at(CHEEK, 60.0))
ok('cheek: at the far end it is 50',
   (RF.tz_bot_at(CHEEK, 120.0) - 50.0).abs < 1e-6, RF.tz_bot_at(CHEEK, 120.0))
ok('the floor is never above the ceiling',
   (0..120).step(10).all? { |t| RF.tz_bot_at(CHEEK, t.to_f) <= RF.tz_top_at(CHEEK, t.to_f) })

# ---- horizontal courses do not hang below the floor ------------------
# a course sitting at z=10 may only be laid where the floor is <= 10.
runs = RF.gable_course_runs(CHEEK, 0.0, 120.0, 10.0, 16.0, 6.0)
# 2026-09-13B: the rule CHANGED here. It used to stop a course as soon as
# the roof had climbed past its bottom, and that is what left the staircase
# of square ends floating above the roof in his photo. Now the board RUNS
# ON UNDER THE ROOF and the roof covers it. What must still hold is what
# this test was really guarding: a board the roof has completely swallowed
# is never built, so nothing hangs in the room below.
ok('a course is laid only while some of it is still above the roof',
   runs.all? do |ta, tb, z|
     [RF.tz_bot_at(CHEEK, ta + 0.001), RF.tz_bot_at(CHEEK, tb - 0.001)].min < z
   end, runs)
ok('and it does not run the whole length',
   runs.empty? || runs.map { |_a, b, _z| b }.max < 120.0, runs)

# the flat triangle is untouched: a course at its own floor still runs
# right across
flat_runs = RF.gable_course_runs(FLAT, 0.0, 240.0, 0.0, 6.0, 6.0)
ok('the gable triangle still gets its full-width bottom course',
   !flat_runs.empty? && flat_runs.first[0] == 0.0 &&
   flat_runs.map { |_a, b, _z| b }.max == 240.0, flat_runs)

# ---- the foot is cut on the slope, not left standing on a wedge -----
# He photographed the gap under the battens on the cheek: "הם צריכים
# להיכנס טיפה לתוך הגג או להיחתך באלכסון". The two ends of a batten's
# foot now take their own z off the outline, so the cut lies along the
# roof; the stub cannot push-pull, so the shape is read off the source.
src = File.read('roof_manager.rb', encoding: 'UTF-8')
bat = src[/half_w = wt::BATTEN_WIDTH.*?built \+= 1/m].to_s
ok('there is a tuck constant for the foot',
   RF.const_defined?(:BATTEN_FOOT_TUCK) && RF::BATTEN_FOOT_TUCK > 0.0,
   RF.const_defined?(:BATTEN_FOOT_TUCK))
ok('the two ends of the foot get their own z off the outline',
   bat.include?('zl = tz_bot_at(tz, t - half_w)') &&
   bat.include?('zr = tz_bot_at(tz, t + half_w)'), nil)
ok('and the batten is built as an upright face pushed OUT, ' \
   'which is the only way a slanted foot can be made',
   bat.include?('fc.pushpull((fc.normal % outn)') &&
   bat.include?('wt::BATTEN_DEPTH :'), nil)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt198 - THE SHOWER FLOOR LOOP (2026-09-22, step 1).
#
# His call: the floor is drawn corner by corner and closed, because his
# showers are not always a rectangle ("מקלחת שיש לה 5 דפנות"). Three
# things have to hold:
#   1. a right angle WINS - the direction comes from the axis and only
#      the LENGTH comes from where he points (CLAUDE.md, 2026-09-24),
#   2. a click on the first corner closes the loop, and only from three
#      corners on,
#   3. the loop that reaches add_face has no doubled points, and its
#      area is the real one.
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor

# ---- 1. the right angle wins -----------------------------------------
# 60" along x and 5" off: 4.8 degrees, inside the window, so it lands on
# the axis - and the LENGTH is the reach along that axis, not the hypot.
p1 = SF.ortho_point(0.0, 0.0, 60.0, 5.0)
ok('a near-straight pull lands on the axis', p1[1].abs < 1e-9, p1)
ok('and keeps the reach along it', (p1[0] - 60.0).abs < 1e-9, p1)

p2 = SF.ortho_point(10.0, 10.0, 10.0, -26.0)
ok('it works the other way down too', (p2[0] - 10.0).abs < 1e-9 && (p2[1] + 26.0).abs < 1e-9, p2)

# 20 degrees off is a real diagonal - it is left alone.
p3 = SF.ortho_point(0.0, 0.0, 60.0, 21.8)
ok('a real diagonal is left alone', (p3[1] - 21.8).abs < 1e-9, p3)

# The bug this law exists to stop: 89.9 degree corners. A 12" wall drawn
# with half an inch of mouse wobble must come out dead straight.
p4 = SF.ortho_point(0.0, 0.0, 0.5, 36.0)
ok('half an inch of wobble over three feet is still straight', p4[0].abs < 1e-9, p4)

# ---- 2. closing ------------------------------------------------------
sq = [[0.0, 0.0], [60.0, 0.0], [60.0, 36.0], [0.0, 36.0]]
ok('a click on the first corner closes it', SF.closes?(sq, 1.0, 1.0))
ok('a click away from it does not', !SF.closes?(sq, 20.0, 20.0))
ok('two corners can never close', !SF.closes?(sq[0, 2], 0.0, 0.0), sq[0, 2])

# ---- 3. the loop and its size ----------------------------------------
dirty = [[0.0, 0.0], [0.0, 0.0], [60.0, 0.0], [60.0, 36.0], [0.0, 36.0], [0.0, 0.0]]
clean = SF.clean_loop(dirty)
ok('doubled and closing points are dropped', clean == sq, clean)
ok('a 60 x 36 floor is 15 sq ft', (SF.area_sqft(dirty) - 15.0).abs < 1e-9, SF.area_sqft(dirty))

# His five-sided shower: the 60 x 36 rectangle with a 12 x 12 corner cut.
five = [[0.0, 0.0], [60.0, 0.0], [60.0, 36.0], [12.0, 36.0], [12.0, 24.0], [0.0, 24.0]]
ok('a five-sided floor keeps all its corners', SF.clean_loop(five).length == 6, SF.clean_loop(five).length)
ok('and its area is the rectangle minus the cut',
   (SF.area_sqft(five) - (15.0 - 1.0)).abs < 1e-9, SF.area_sqft(five))

ok('two corners are not a floor', SF.clean_loop([[0.0, 0.0], [10.0, 0.0]]).length == 2)
ok('the kill switch is there', SF.const_defined?(:USE_SHOWER_FLOOR))

puts($fails.zero? ? 'rt198 OK' : "rt198 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

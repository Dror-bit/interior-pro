# encoding: utf-8
# rt133 - A STOREY UNDER ANOTHER STOREY GETS NO ROOF (2026-09-11).
#
# WHY
# The user stacked a second storey exactly on the first and the first
# grew a roof band right round itself, under the walls above ("אם
# לקירות התחתונים יש מעליהם עוד קומה לא צריך להיווצר גג"). The code that
# cuts a lower roof at the upper walls (exposed_polygon) answers nil both
# when NOTHING CROSSES and when NOTHING IS OPEN - and nil fell through to
# the plain full loop. This pins the pure test that tells the two apart.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

RF = InteriorPro::RoofManager

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}#{extra.nil? ? '' : "   << #{extra.inspect}"}"
    FAILS << name
  end
end

BASE = [[0.0, 0.0], [360.0, 0.0], [360.0, 240.0], [0.0, 240.0]]

ok('the same outline covers itself', RF.covered_polygon?(BASE, BASE))
ok('a bigger storey above covers it too',
   RF.covered_polygon?(BASE, [[-12.0, -12.0], [372.0, -12.0], [372.0, 252.0], [-12.0, 252.0]]))
ok('a storey above on HALF of it does not',
   !RF.covered_polygon?(BASE, [[0.0, 0.0], [180.0, 0.0], [180.0, 240.0], [0.0, 240.0]]))
ok('a storey above that misses it entirely does not',
   !RF.covered_polygon?(BASE, [[500.0, 0.0], [800.0, 0.0], [800.0, 240.0], [500.0, 240.0]]))
ok('a storey above that leaves one small corner open does not',
   !RF.covered_polygon?(BASE, [[0.0, 0.0], [360.0, 0.0], [360.0, 240.0], [60.0, 240.0],
                              [60.0, 180.0], [0.0, 180.0]]))
ok('a degenerate outline is never "covered"', !RF.covered_polygon?([[0, 0], [1, 1]], BASE))
ok('a tiny step still samples something', RF.covered_polygon?(BASE, BASE, 1.0))

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

# encoding: utf-8
# rt315 - A PLATE ON THE KITCHEN BACKSPLASH STANDS ON ITS FACE (2026-10-14 20:20, his "כל פלאג או שקע שיושב על באק ספלאש
# או טייל על קיר צריך לעבור לקידמת הטיל"): a thin kitchen piece over the plate pushes it out; a cabinet does not; nothing
# over it = 0. And check / refront! use it.
require './sketchup_stub'
require './electrical_library'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::ElectricalLibrary
ok('kill switch is there and on', L::USE_KITCHEN_FRONT == true)
#          kind        u0   u1   z0  z1   o0    o1
boxes = [['worktop',    0, 240,  36, 54,  0.0, 0.38],    # the backsplash run
         ['worktop',    0, 240,  34, 36, -0.1, 25.5],    # the countertop slab - deep, not a face
         ['cabinet',   90, 126,  54, 84,  0.0, 12.0],    # an upper cabinet
         ['kitchen_unit', 0, 240, 0, 90, 0.0, 25.5]]
ok('over the backsplash: out to its face', (L.kitchen_front(95.8, 98.5, 39.8, 44.3, boxes) - 0.38).abs < 1e-9, L.kitchen_front(95.8, 98.5, 39.8, 44.3, boxes))
ok('higher, under the cabinet only: nothing pushes it', L.kitchen_front(95.8, 98.5, 60, 64.5, boxes) == 0.0)
ok('past the run: nothing', L.kitchen_front(250, 253, 40, 44, boxes) == 0.0)
ok('a piece behind the face does not count', L.kitchen_front(10, 13, 40, 44, [['worktop', 0, 240, 36, 54, -2.0, 0.3]]) == 0.0)
ok('the deepest thin piece wins', (L.kitchen_front(10, 13, 40, 44, [['worktop', 0, 240, 36, 54, 0, 0.34], ['backsplash', 0, 240, 36, 54, 0, 0.5]]) - 0.5).abs < 1e-9)
src = File.read('./electrical_library.rb')
m = src[/def self\.check\(.*?\n    end\n/m].to_s
ok('check takes the larger of the tile and the kitchen face', m.include?('kitchen_front(u0, u1, z0, z1, kboxes)') && m.include?('out = kf if kf > out'))
ok('refront! is there for the plates already placed', src.include?('def self.refront!') && src[/def self\.refront!.*?\n    end\n/m].to_s.include?('transform!'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

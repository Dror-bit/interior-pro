# encoding: utf-8
# rt143 - THE BOARDS WALK ROUND THE WINDOW (2026-09-13).
#
# The gablet's cheeks got real boards; the front wall was left bare on
# purpose, because a batten must not run across the glass. He asked for
# it next: "בוא נמשיך לפרונט שלו".
#
# HOW IT KNOWS WHERE THE WINDOW IS: it is not told. punch_window! leaves
# the opening as an INNER LOOP on the wall's outer face, and the board
# builder already measures everything off that face - so the hole comes
# with it. That is also why the front wall's boards are built after the
# window and not inside paint_wall! with the cheeks'.
#
# WHAT IS PINNED HERE: the two pure cutters, and the order of the calls.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager

# ---- 1. taking a span out of a span ---------------------------------
ok('nothing to cut leaves the span whole',
   RF.subtract_span(0.0, 10.0, []) == [[0.0, 10.0]],
   RF.subtract_span(0.0, 10.0, []))
ok('a cut in the middle leaves two pieces',
   RF.subtract_span(0.0, 10.0, [[4.0, 6.0]]) == [[0.0, 4.0], [6.0, 10.0]],
   RF.subtract_span(0.0, 10.0, [[4.0, 6.0]]))
ok('a cut that covers it leaves nothing',
   RF.subtract_span(0.0, 10.0, [[-1.0, 11.0]]) == [],
   RF.subtract_span(0.0, 10.0, [[-1.0, 11.0]]))
ok('a cut off the end does not touch it',
   RF.subtract_span(0.0, 10.0, [[10.0, 20.0]]) == [[0.0, 10.0]],
   RF.subtract_span(0.0, 10.0, [[10.0, 20.0]]))
ok('two cuts leave three pieces',
   RF.subtract_span(0.0, 10.0, [[2.0, 3.0], [6.0, 7.0]]).length == 3,
   RF.subtract_span(0.0, 10.0, [[2.0, 3.0], [6.0, 7.0]]))

# ---- 2. a batten that crosses a window ------------------------------
HOLE = [[10.0, 30.0, 40.0, 70.0]].freeze   # t 10..30, z 40..70

ok('a batten beside the window is one full piece',
   RF.batten_bands(0.0, 100.0, HOLE, 0.0, 2.0) == [[0.0, 100.0]],
   RF.batten_bands(0.0, 100.0, HOLE, 0.0, 2.0))
ok('a batten across the window is cut in two',
   RF.batten_bands(0.0, 100.0, HOLE, 19.0, 21.0) ==
     [[0.0, 40.0], [70.0, 100.0]],
   RF.batten_bands(0.0, 100.0, HOLE, 19.0, 21.0))
ok('and neither piece is inside the glass',
   RF.batten_bands(0.0, 100.0, HOLE, 19.0, 21.0)
     .none? { |a, b| b > 40.01 && a < 69.99 })
ok('a batten just past the window edge is whole again',
   RF.batten_bands(0.0, 100.0, HOLE, 30.0, 32.0) == [[0.0, 100.0]],
   RF.batten_bands(0.0, 100.0, HOLE, 30.0, 32.0))

# ---- 3. the wiring ---------------------------------------------------
rsrc = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('the builder reads the openings off the face itself',
   rsrc.include?('holes = face_holes_tz(outer, p0, d)'), nil)
ok('the battens are cut by them', rsrc.include?('bands = batten_bands('), nil)
ok('and so are the horizontal courses',
   rsrc.include?('subtract_span(ta, tb, cuts)'), nil)

dsrc = File.read('dormer_manager.rb', encoding: 'UTF-8')
ok('the front wall is boarded AFTER the window is punched',
   dsrc.index('punch_window!(wall, fr, at, wr)') <
   dsrc.index('build_wall_siding!(wall, Array(spec[:wall_names]).first'),
   nil)
ok('and the window-only rebuild boards it again',
   dsrc.include?("build_wall_siding!(wall, Array(names).first"), nil)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

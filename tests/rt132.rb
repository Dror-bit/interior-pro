# encoding: utf-8
# rt132 - THE ABUT / RAKE CORNER (2026-09-11).
#
# WHY
# A lower roof whose rake runs into the upper storey's wall. The user
# circled three things at that one corner: a grey flap sticking out of
# the wall, an open fascia end, and a soffit that stopped short. Measured
# on his model, all three were ONE assumption: the corner code took the
# abut edge's neighbour for a level EAVE. The rake soffit built a box
# "return" for its last overhang (12" of nothing, a step face at
# y=239.25) and the closure plate was drawn at eave height, 30" under
# the rake it was meant to close.
#
# WHAT IS PINNED HERE - the pure half
# rake_soffit_segments with `returns`: an end told "no return" runs the
# sloped piece straight to the corner; nil keeps yesterday's answer
# exactly (rt84 pins that shape). rake_returns: the end of a rake that
# shares its corner with an abut edge is the one that loses its return.
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

LEN = 100.0
OH = 12.0

# --- nil = exactly what it did before ---------------------------------
old = RF.rake_soffit_segments(0.0, LEN, LEN, OH)
new_nil = RF.rake_soffit_segments(0.0, LEN, LEN, OH, nil)
ok('returns=nil changes nothing', old == new_nil, [old, new_nil])
ok('...and a full run still returns at BOTH ends',
   old.first[2] == true && old.last[2] == true, old)

# --- an abut TAIL: the sloped piece runs to the corner ----------------
seg = RF.rake_soffit_segments(0.0, LEN, LEN, OH, [true, false])
ok('no tail return: the last piece is the sloped one',
   seg.last[2] == false, seg)
ok('...and it reaches the corner itself', (seg.last[1] - LEN).abs < 1.0e-9, seg)
ok('...while the head return is still there',
   seg.first[2] == true && (seg.first[1] - OH).abs < 1.0e-9, seg)

# --- an abut HEAD ------------------------------------------------------
seg2 = RF.rake_soffit_segments(0.0, LEN, LEN, OH, [false, true])
ok('no head return: the first piece starts at 0 and slopes',
   seg2.first[2] == false && seg2.first[0].abs < 1.0e-9, seg2)
ok('...tail return kept', seg2.last[2] == true, seg2)

# --- both off: one sloped piece, corner to corner ----------------------
seg3 = RF.rake_soffit_segments(0.0, LEN, LEN, OH, [false, false])
ok('both off: a single sloped piece, corner to corner',
   seg3.length == 1 && seg3[0][2] == false &&
   seg3[0][0].abs < 1.0e-9 && (seg3[0][1] - LEN).abs < 1.0e-9, seg3)

# --- rake_returns reads the abut flags at the two corners --------------
poly = [[0, 0], [100, 0], [100, 60], [0, 60]]
# edge 1 (east) is the rake; edge 2 (north) is the abut edge
ab = [false, false, true, false]
ok('the corner shared with the abut edge loses its return',
   RF.rake_returns(poly, 1, ab) == [true, false], RF.rake_returns(poly, 1, ab))
ok('the other neighbour keeps its return',
   RF.rake_returns(poly, 3, ab) == [false, true], RF.rake_returns(poly, 3, ab))
ok('no abut flags at all = nil = unchanged behaviour',
   RF.rake_returns(poly, 1, nil).nil?)
ok('no abut edges = both returns allowed',
   RF.rake_returns(poly, 1, [false] * 4) == [true, true])

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

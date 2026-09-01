# encoding: utf-8
# rt129 - WHICH EDGE IS DUTCH (2026-09-11).
#
# WHY
# Until today the Dutch depth was one number that turned EVERY marked
# gable end Dutch at once. The user asked for the choice to work the way
# the gable mark itself works: "so I can pick which edge is a Dutch
# gable". One button, three states - hip -> gable -> Dutch -> hip - and a
# second, smaller list of wall ids saying which of the gable ends are
# Dutch.
#
# WHAT IS PINNED HERE
# 1. No Dutch marks = every side comes back not-Dutch. A model that never
#    touched the new state builds exactly the roof it built yesterday.
# 2. Marking ONE of two gable ends makes that side Dutch and leaves the
#    other side a plain gable - the whole point of the change.
# 3. A Dutch mark on a side that is NOT a gable end does nothing. Dutch
#    is a KIND of gable, never a way to create one.
# 4. plan[:dutch_edges] names only the poly edges on the Dutch ends, so
#    build_roof! can strip the rake dress off those and leave the plain
#    gable ends wearing theirs.
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

# a plain 480 x 300 rectangle, CCW, one wall id per edge
#   edge 0 = south (y=0), 1 = east (x=480), 2 = north (y=300), 3 = west
RECT = [[0.0, 0.0], [480.0, 0.0], [480.0, 300.0], [0.0, 300.0]].freeze
IDS = %w[s e n w].freeze

# --- 1. no Dutch marks: nothing is Dutch -----------------------------
p0 = RF.framed_plan(RECT, IDS, %w[e w], 'hip')
ok('the two marked ends gable', p0 && p0[:g][:e] && p0[:g][:w], p0 && p0[:g])
ok('no Dutch marks -> no side is Dutch',
   p0 && [:n, :s, :e, :w].none? { |sd| p0[:d][sd] }, p0 && p0[:d])
ok('...and no poly edge is a Dutch edge', p0 && p0[:dutch_edges].empty?,
   p0 && p0[:dutch_edges])

# --- 2. one of the two ends marked Dutch -----------------------------
p1 = RF.framed_plan(RECT, IDS, %w[e w], 'hip', ['e'])
ok('both ends are still gable ends', p1 && p1[:g][:e] && p1[:g][:w], p1 && p1[:g])
ok('the marked end is Dutch', p1 && p1[:d][:e], p1 && p1[:d])
ok('and the other end is NOT', p1 && !p1[:d][:w], p1 && p1[:d])
ok('exactly one poly edge is Dutch', p1 && p1[:dutch_edges].length == 1,
   p1 && p1[:dutch_edges])
ok('...and it is the EAST edge (index 1)', p1 && p1[:dutch_edges] == [1],
   p1 && p1[:dutch_edges])
ok('while both ends are still in the gable edge list',
   p1 && p1[:edges].sort == [1, 3], p1 && p1[:edges])

# --- 3. Dutch on a side that is not a gable end does nothing ---------
p2 = RF.framed_plan(RECT, IDS, %w[e w], 'hip', ['n'])
ok('a Dutch mark cannot create a gable end', p2 && !p2[:g][:n] && !p2[:d][:n],
   p2 && [p2[:g], p2[:d]])
ok('...and it adds no Dutch edge', p2 && p2[:dutch_edges].empty?,
   p2 && p2[:dutch_edges])

# --- 4. both ends marked = what the single number used to do ---------
p3 = RF.framed_plan(RECT, IDS, %w[e w], 'hip', %w[e w])
ok('marking both gives both, like the old one-number behaviour',
   p3 && p3[:d][:e] && p3[:d][:w] && p3[:dutch_edges].sort == [1, 3],
   p3 && p3[:dutch_edges])

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

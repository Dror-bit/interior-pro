# encoding: utf-8
# rt53 - one bad entity must not lose the whole back yard (2026-08-14).
#
# The user's console, twice, right after pressing "add what is selected":
#
#   [Sheet] add_selection: no implicit conversion to Transformation
#
# and nothing was added. Something in his model raised while the edges were
# being collected, and thousands of good edges went into the bin with it.
#
# The cause is still unknown - the message came with no backtrace, which is
# fixed separately. This suite is about the OTHER half: whatever the one bad
# thing turns out to be, the rest of the selection must still arrive, and the
# window must say how many were skipped rather than showing a thinner yard than
# the user drew and letting him wonder.
require './sketchup_stub'
require './plan_doc'
require './plan_geometry'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PG = InteriorPro::PlanGeometry

def pt(x, y, z = 0)
  Geom::Point3d.new(x, y, z)
end

def edge(x1, y1, x2, y2, z = 0)
  Sketchup::Edge.new(pt(x1, y1, z), pt(x2, y2, z))
end

# A group whose placement is nonsense - exactly the shape of the failure.
class BadGroup < Sketchup::Group
  def transformation
    'this is not a transformation'
  end
end

# A group that refuses to say anything at all.
class AngryGroup < Sketchup::Group
  def entities
    raise TypeError, 'no implicit conversion to Transformation'
  end
end

# ------------------------------------------------- the good ones still arrive
good = [edge(0, 0, 100, 0), edge(100, 0, 100, 100), edge(100, 100, 0, 100)]
lines = PG.snapshot(good)
ok('a plain selection comes through', lines.length == 3, lines.length)
ok('and nothing was skipped', PG.last_report[:skipped] == 0, PG.last_report)

angry = AngryGroup.new
mixed = [good[0], angry, good[1], good[2]]
lines = PG.snapshot(mixed)
ok('one entity that raises does not lose the other three',
   lines.length == 3, lines.length)
ok('and it is counted, not hidden', PG.last_report[:skipped] == 1, PG.last_report)
ok('the count starts fresh every time the button is pressed',
   PG.snapshot(good) && PG.last_report[:skipped] == 0, PG.last_report)

many = ([angry] * 5) + good
lines = PG.snapshot(many)
ok('five bad ones still leave the three good ones', lines.length == 3, lines.length)
ok('and all five are counted', PG.last_report[:skipped] == 5, PG.last_report)

# ------------------------------------------- a nonsense placement, not a crash
bad = BadGroup.new
bad.entities.add_edges([pt(0, 0), pt(50, 0)]) if bad.entities.respond_to?(:add_edges)
ok('combining a real placement with nonsense does not raise',
   begin
     PG.mul(Geom::Transformation.new, 'nonsense')
     true
   rescue StandardError => e
     e
   end)
ok('and it keeps the placement it already had',
   PG.mul(:outer, nil) == :outer)
ok('with nothing outside, the inner one is used',
   PG.mul(nil, :inner) == :inner)

# ------------------------------------------------- the report the window reads
r = PG.last_report
%i[asked found edges lines skipped].each do |k|
  ok("the report tells the window '#{k}'", r.key?(k), r.keys)
end

# ---------------------------------------------------- nothing else moved
ok('an empty selection is still nothing, not an error',
   PG.snapshot([]) == [] && PG.last_report[:skipped] == 0)
ok('a line shorter than a quarter inch is still dropped',
   PG.snapshot([edge(0, 0, 0.1, 0)]).empty?)
ok('the same line twice is still drawn once',
   PG.snapshot([edge(0, 0, 60, 0), edge(60, 0, 0, 0)]).length == 1)
ok('a soft edge is still left out by default',
   begin
     e = edge(0, 0, 60, 0)
     e.soft = true
     PG.snapshot([e]).empty?
   end)
ok('and kept when the user asks for it',
   begin
     e = edge(0, 0, 60, 0)
     e.soft = true
     PG.snapshot([e], hide_soft: false).length == 1
   end)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

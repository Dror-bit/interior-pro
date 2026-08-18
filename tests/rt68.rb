# encoding: utf-8
# rt68 - moving a wall must not drag the floor below with it (2026-08-17).
#
# WHAT THE USER WAS ACTUALLY DOING, which matters more than the symptom:
#
#   "אבל אני כן מנסה שהם ישבו אחת על השני והוא לא הושיב לי אותם אחד על השני
#    ומכאן התחיל כל הבלאגן"
#
# He was lining an upstairs wall up OVER the one downstairs - the ordinary
# thing you do when walls stack. Every time he moved the wall in his hand, the
# wall he was aiming AT moved by the same amount. You cannot land a wall on a
# target that runs away from you, so he moved it again, and again, and the
# model turned into a mess. He reported the mess. The mess was this bug.
#
# THE CAUSE: move_wall_sideways! decides who follows the moving wall by
# comparing start_x/start_y/end_x/end_y - flat numbers, no height, no storey.
# A wall on the floor below stands on the SAME FOOTPRINT by definition, so
# every one of those distance tests passed and it was treated as a corner
# partner.
#
# wall_tool.rb already knew: "Filtering is by the 'level' attribute (NOT
# base_z)". The editor filters by level when it READS walls. Only its move
# never got the rule.
#
# NOT by z: a garage sits lower than the house and is still level 1. Comparing
# heights would part it from its own neighbours, which is a different bug in
# the opposite direction.
require 'json'
require './sketchup_stub'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SRC = File.read('./plan_editor.rb', encoding: 'UTF-8')

# The neighbour scan, from the top of the method to the end of the loop.
SCAN = SRC[/def move_wall_sideways!.*?^        by_wall = /m].to_s
ok('the neighbour scan is where it always was', !SCAN.empty?)

# ---------------------------------------------------------------------------
# 1. the rule itself
# ---------------------------------------------------------------------------
ok('the moving wall knows which storey it is on',
   SCAN.include?("moving_level = (wall.get_attribute('InteriorPro', 'level') || 1).to_i"),
   SCAN[/moving_level.*/])
ok('A WALL ON ANOTHER STOREY IS SKIPPED  <<< the bug',
   SCAN.include?("next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == moving_level"),
   SCAN.scan(/next unless.*level.*/).first)

# A wall with no level attribute at all is level 1 - every model made before
# levels existed is full of them, and they must still join each other.
ok('a wall with no storey recorded counts as the first one, on both sides',
   SCAN.scan(/get_attribute\('InteriorPro', 'level'\) \|\| 1/).length >= 2,
   SCAN.scan(/get_attribute\('InteriorPro', 'level'\) \|\| 1/).length)

# Comments stripped: the note above the fix QUOTES wall_tool's "NOT base_z"
# warning, and a check that trips over its own documentation is one nobody
# keeps (learned on t46 the same day).
CODE = SCAN.gsub(/^\s*#.*$/, '')
ok('the test is by storey, NOT by height',
   !CODE.match?(/base_z|\.origin\.z|position\.z/), CODE[/.*base_z.*/])

# The skip has to happen BEFORE any distance is measured, or a wall downstairs
# can still be recorded as a corner partner and pulled.
li = SCAN.index('== moving_level')
di = SCAN.index('Math.sqrt((osx - sx)')
ok('the storey is checked before any distance is measured',
   li && di && li < di, [li, di])

# ---------------------------------------------------------------------------
# 2. the same rule, actually applied - the geometry of his case
# ---------------------------------------------------------------------------
# Two walls on exactly the same footprint, one upstairs, one down. Everything
# the scan measures matches; only the storey tells them apart.
def wall(level, sx, sy, ex, ey)
  { 'level' => level, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey }
end

MOVING = wall(2, 0.0, 0.0, 120.0, 0.0)
BELOW  = wall(1, 0.0, 0.0, 120.0, 0.0)     # directly underneath
CORNER = wall(2, 120.0, 0.0, 120.0, 96.0)  # a real corner partner, same storey
FAR    = wall(2, 600.0, 600.0, 700.0, 600.0)

# The rule as the file now states it, so this suite fails if the file's idea of
# "same storey" and this test's ever drift apart.
def same_storey?(a, b)
  (a['level'] || 1).to_i == (b['level'] || 1).to_i
end

def touches?(a, b, tol = 6.0)
  [[a['start_x'], a['start_y']], [a['end_x'], a['end_y']]].any? do |ax, ay|
    [[b['start_x'], b['start_y']], [b['end_x'], b['end_y']]].any? do |bx, by|
      Math.sqrt((ax - bx)**2 + (ay - by)**2) < tol
    end
  end
end

ok('the wall below LOOKS like a corner partner - that is the whole trap',
   touches?(MOVING, BELOW), 'it does not, so this suite proves nothing')
ok('and the flat numbers cannot tell them apart',
   MOVING['start_x'] == BELOW['start_x'] && MOVING['end_y'] == BELOW['end_y'])
ok('THE STOREY CAN', !same_storey?(MOVING, BELOW))

follows = ->(other) { same_storey?(MOVING, other) && touches?(MOVING, other) }
ok('the wall downstairs does not follow', !follows.call(BELOW))
ok('the real corner partner still does  <<< the fix must not break joining',
   follows.call(CORNER))
ok('a wall nowhere near still does not', !follows.call(FAR))

ok('a pre-levels model still joins itself',
   begin
     a = wall(nil, 0.0, 0.0, 120.0, 0.0)
     b = wall(nil, 120.0, 0.0, 120.0, 96.0)
     same_storey?(a, b) && touches?(a, b)
   end)
ok('and a level-1 wall joins a wall with no level recorded',
   same_storey?(wall(1, 0, 0, 1, 0), wall(nil, 0, 0, 1, 0)))

# ---------------------------------------------------------------------------
# 3. what must NOT have changed
# ---------------------------------------------------------------------------
ok('"keep joined" still lets an interior wall follow an exterior one',
   SCAN.include?('same_cat || keep_corners'), SCAN[/same_cat \|\|.*/])
ok('detaching still means nothing follows',
   SCAN.include?('next unless keep_corners'))
ok('tee joints are still found', SCAN.include?('linked: :tee'))
ok('the move is still one undoable step',
   SRC.include?("model.start_operation('Move Wall', true)"))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

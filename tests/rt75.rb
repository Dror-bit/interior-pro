# encoding: utf-8
# rt75 - deleting a wall upstairs must not touch the wall downstairs
#        (2026-08-19).
#
# WHAT HAPPENS TODAY WHEN A WALL IS DELETED
# Every wall whose drawn end sat on the deleted wall's end is reset to a plain
# SQUARE end and then re-joined, so the miter that pointed at the wall that is
# now gone disappears with it. Correct - for the walls on that floor.
#
# THE BUG
# That list was collected by POSITION alone. The user builds floor 2 by
# copying floor 1, so an upstairs wall's ends sit exactly over a downstairs
# wall's ends - all the comparisons are z-flattened, so they match to the
# inch. Delete a wall upstairs and a perfectly good mitered corner downstairs
# was squared off and rebuilt, leaving the white end cap he reported on
# 2026-08-17 in a room he had not touched.
#
# WHAT THIS PINS
# neighbor_walls - pulled out of delete_wall! so the decision can be tested
# without waking half the plugin - returns walls on the SAME level only.
# Same guard, same wording, as WallTool.find_neighbor_at.
require './sketchup_stub'
require './wall_split_tool'
require './wall_delete_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

WDT = InteriorPro::WallDeleteTool
M = Sketchup.active_model

def wall!(id, sx, sy, ex, ey, level = 1, th = 5.0, lift = nil)
  g = M.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy,
    'end_x' => ex, 'end_y' => ey, 'thickness' => th, 'level' => level,
    'anchor' => 'bottom-left', 'wall_category' => 'exterior' }
    .each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g.transformation = Geom::Transformation.new(Geom::Point3d.new(0, 0, lift)) if lift
  g
end

def ids(list)
  list.map { |g| g.get_attribute('InteriorPro', 'id') }.sort
end

# The user's own shape: floor 1 drawn, floor 2 copied straight up on top of
# it, so every x and y is identical and only z differs.
up   = wall!('up',   0, 0, 120, 0, 2, 5.0, 106.0)
up_p = wall!('up_p', 120, 0, 120, 90, 2, 5.0, 106.0)
dn   = wall!('dn',   0, 0, 120, 0, 1)
dn_p = wall!('dn_p', 120, 0, 120, 90, 1)
far  = wall!('far',  500, 500, 620, 500, 2, 5.0, 106.0)

n_up = WDT.neighbor_walls(up, M)
ok('the upstairs wall finds its own upstairs neighbour', ids(n_up) == ['up_p'], ids(n_up))
ok('>>> THE BUG: it does NOT find the wall downstairs', !ids(n_up).include?('dn'))
ok('    nor the downstairs neighbour', !ids(n_up).include?('dn_p'))
ok('a wall nowhere near is not a neighbour', !ids(n_up).include?('far'))

n_dn = WDT.neighbor_walls(dn, M)
ok('and it works the same way round: downstairs finds downstairs',
   ids(n_dn) == ['dn_p'], ids(n_dn))
ok('downstairs does not reach up either', !ids(n_dn).include?('up_p'))

# Two walls that really do share a corner on the SAME floor must still be
# found - the whole point of the list. This is the promise that the fix
# cannot quietly turn the feature off.
ok('the neighbour on the same floor is still there', n_up.length == 1, n_up.length)

# A wall with no level attribute counts as level 1, like everywhere else, so
# a model made before levels existed keeps working.
old_a = wall!('old_a', 0, 900, 120, 900, 1)
old_b = wall!('old_b', 120, 900, 120, 990, 1)
[old_a, old_b].each { |g| g.delete_attribute('InteriorPro', 'level') } if old_a.respond_to?(:delete_attribute)
n_old = WDT.neighbor_walls(old_a, M)
ok('a wall with no level still finds its neighbour', ids(n_old) == ['old_b'], ids(n_old))

# Rubbish in, no crash out.
ok('a nil wall gives an empty list, not a crash', WDT.neighbor_walls(nil, M) == [])
bare = M.entities.add_group
ok('a group that is not a wall gives an empty list', WDT.neighbor_walls(bare, M) == [])

# The guard is really in the code, not just in this test's head.
src = File.read('wall_delete_tool.rb', encoding: 'UTF-8')
ok('delete_wall! uses the extracted list, not its own copy of the scan',
   src.include?('neighbors = neighbor_walls(wall, model)'))
ok('the list is filtered by level',
   src[/def self\.neighbor_walls.*?\n    end/m].to_s.include?("'level'"))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

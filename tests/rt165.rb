# encoding: utf-8
# rt165 - THE TILE COUNT ON THE REAL FLOORS (2026-09-06).
# TileCount does the arithmetic; this is the layer that feeds it from the
# model - the room's own outline, and the floor's own tile size, joint,
# start point and pattern. A floor laid without a unit (a slab, carpet)
# has nothing to count and says so instead of inventing a number.
require './sketchup_stub'
require './tile_count'
require './tile_takeoff'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TT = InteriorPro::TileTakeoff

# ---- 1. the outline comes back as pairs ------------------------------
ok('a flat list becomes x/y pairs',
   TT.outline([0, 0, 60, 0, 60, 96, 0, 96]) == [[0.0, 0.0], [60.0, 0.0], [60.0, 96.0], [0.0, 96.0]])
ok('too short is nothing', TT.outline([0, 0, 1, 1]) == [])
ok('nil is nothing', TT.outline(nil) == [])

# ---- 2. what can be counted ------------------------------------------
sq = [[0.0, 0.0], [60.0, 0.0], [60.0, 96.0], [0.0, 96.0]]
ok('a floor with a tile size and an outline counts',
   TT.countable?({ tw: 24.0, tl: 48.0, poly: sq }))
ok('a floor with no unit size does not',
   !TT.countable?({ tw: 0.0, tl: 0.0, poly: sq }))
ok('nor one with no outline', !TT.countable?({ tw: 24.0, tl: 48.0, poly: [] }))

ok('a running bond is staggered half a tile', TT.stagger_for('running bond') == 0.5)
ok('a stack bond is not', TT.stagger_for('stack') == 0.0)
ok('no pattern at all is not', TT.stagger_for('') == 0.0)

# ---- 3. a real model --------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
def grp(m, a)
  g = m.entities.add_group
  a.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  g
end
grp(m, type: 'room', id: 'r1', name: 'Room 1', area_sqft: 40.0,
       boundary_xy: [0, 0, 60, 0, 60, 96, 0, 96])
grp(m, type: 'floor', room_id: 'r1', floor_type: 'Porcelain', area_sqft: 40.0,
       unit_w: 24.0, unit_l: 48.0, pattern: 'stack')
grp(m, type: 'room', id: 'r2', name: 'Room 2', area_sqft: 20.0,
       boundary_xy: [0, 0, 48, 0, 48, 60, 0, 60])
grp(m, type: 'floor', room_id: 'r2', floor_type: 'Concrete', area_sqft: 20.0)

fl = TT.floors(m)
ok('both floors are found', fl.length == 2, fl.map { |f| f[:name] })
ok('the bigger one first', fl[0][:name] == 'Room 1')
ok('each carries its room outline', fl[0][:poly].length == 4)
ok('...its tile size', fl[0][:tw] == 24.0 && fl[0][:tl] == 48.0)

res = TT.count_floor(fl[0])
ok('the tiled floor is counted - 4 whole, 2 cuts from 1 tile',
   res[:full] == 4 && res[:cut_pieces] == 2 && res[:cut_tiles] == 1, res)
ok('...so 5 tiles to buy, not 6', res[:tiles] == 5, res)
ok('the concrete floor has nothing to count', TT.count_floor(fl[1]).nil?)

# ---- 4. a room bound to Invoice Studio shows THAT name ---------------
m.entities.grep(Sketchup::Group).each do |g|
  next unless g.get_attribute('InteriorPro', 'id') == 'r1'
  g.set_attribute('InteriorPro', 'studio_room_name', 'Kitchen')
end
ok('the count is reported under the Studio name',
   TT.floors(m)[0][:name] == 'Kitchen', TT.floors(m)[0][:name])

# ---- 5. the threshold is his to change --------------------------------
grp(m, type: 'room', id: 'r3', name: 'Strip', area_sqft: 35.0,
       boundary_xy: [0, 0, 52, 0, 52, 96, 0, 96])
grp(m, type: 'floor', room_id: 'r3', floor_type: 'Porcelain', area_sqft: 35.0,
       unit_w: 24.0, unit_l: 48.0)
f3 = TT.floors(m).find { |f| f[:name] == 'Strip' }
r20 = TT.count_floor(f3, 20.0)
r10 = TT.count_floor(f3, 10.0)
ok('at 20% the two 4" strips are waste, each on its own tile',
   r20[:small_pieces] == 2 && r20[:tiles] == 6, r20)
ok('at 10% they are paired instead',
   r10[:small_pieces].zero? && r10[:paired] == 1 && r10[:tiles] == 5, r10)

puts($fails.zero? ? 'rt165 OK' : "rt165 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

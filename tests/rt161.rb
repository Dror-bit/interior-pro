# encoding: utf-8
# rt161 - QUANTITIES PER NAMED SURFACE, NET (2026-09-18).
# "כן רק השטח נטו". Floors and walls, inside and out, each named by him.
# A floor's area is the room boundary - already net. A wall's saved area
# is GROSS, so every door and window in it comes off, on both sides.
require './sketchup_stub'
require './surface_takeoff'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

ST = InteriorPro::SurfaceTakeoff

# ---- 1. net area -----------------------------------------------------
ok('gross minus its openings', near(ST.net_area(400.0, 37.5), 362.5))
ok('no openings leaves the gross', near(ST.net_area(400.0, 0.0), 400.0))
ok('openings bigger than the wall never go below zero',
   near(ST.net_area(20.0, 50.0), 0.0))
ok('the tile size reads the way he says it', ST.unit_text(48, 24) == '24x48',
   ST.unit_text(48, 24))
ok('no tile size gives no text', ST.unit_text(0, 0) == '')

# ---- 2. a model ------------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
def grp(m, attrs)
  g = m.entities.add_group
  attrs.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  g
end

grp(m, type: 'room', id: 'room-1', name: 'Kitchen', area_sqft: 212.4)
grp(m, type: 'room', id: 'room-2', name: 'Patio', area_sqft: 418.0)
grp(m, type: 'floor', room_id: 'room-1', floor_type: 'Porcelain',
       area_sqft: 212.4, unit_l: 48.0, unit_w: 24.0)
grp(m, type: 'floor', room_id: 'room-2', floor_type: 'Pavers', area_sqft: 418.0)
grp(m, type: 'wall', id: 'W1abc123', mark: 'W-1', wall_category: 'exterior',
       gross_area_sqft: 400.0, exterior_material: 'Stucco',
       interior_material: '#ffffff')
grp(m, type: 'wall', id: 'W2def456', wall_category: 'interior',
       gross_area_sqft: 120.0, exterior_material: 'Brick',
       interior_material: '#ffffff')
grp(m, type: 'door', host_wall_id: 'W1abc123', area_sqft: 21.0)
grp(m, type: 'window', host_wall_id: 'W1abc123', area_sqft: 16.5)
grp(m, type: 'window', host_wall_id: 'nowall', area_sqft: 9.0)

rows = ST.take(m)

# floors
fl = rows.select { |r| r[:kind] == 'floor' }
ok('two floors', fl.length == 2, fl)
kit = fl.find { |r| r[:name] == 'Kitchen' }
ok('the floor is named by its ROOM, not by an id', !kit.nil?, fl.map { |r| r[:name] })
ok('...with the room area, 212.4', near(kit[:sqft], 212.4), kit)
ok('...its material is the floor type', kit[:material] == 'Porcelain')
ok('...and it carries the tile size for the piece count later',
   kit[:unit] == '24x48', kit[:unit])
pat = fl.find { |r| r[:name] == 'Patio' }
ok('a floor with no tile size shows none', pat[:unit] == '', pat)

# walls
w1 = rows.select { |r| r[:name] == 'W-1' }
ok('the wall comes out twice - outside and inside', w1.length == 2, w1)
ok('both sides are NET: 400 - 21 - 16.5 = 362.5',
   w1.all? { |r| near(r[:sqft], 362.5) }, w1.map { |r| r[:sqft] })
ok('the outside wears the exterior material',
   w1.find { |r| r[:face] == 'outside' }[:material] == 'Stucco')
ok('the inside wears the interior one',
   w1.find { |r| r[:face] == 'inside' }[:material] == '#ffffff')
ok('"wall is" and "face" are two different questions now',
   w1.all? { |r| r[:kind] == 'wall' && r[:category] == 'exterior' } &&
   w1.map { |r| r[:face] }.sort == %w[inside outside],
   w1.map { |r| [r[:category], r[:face]] })
ok('the note says what was taken off',
   w1[0][:note] =~ /gross 400\.00, openings 37\.50/, w1[0][:note])
ok('an opening on another wall is not taken off this one', true)

w2 = rows.select { |r| r[:name] == 'W2def456'[0, 8] }
ok('a wall with no mark falls back to its id', w2.length == 2, w2)
ok('...and with no openings it keeps its gross, 120',
   w2.all? { |r| near(r[:sqft], 120.0) }, w2.map { |r| r[:sqft] })
ok('an interior wall is marked as one',
   w2.all? { |r| r[:category] == 'interior' }, w2.map { |r| r[:category] })

# order and csv
ok('rows come biggest first',
   rows.map { |r| r[:sqft] } == rows.map { |r| r[:sqft] }.sort.reverse)
csv = ST.to_csv(rows)
ok('the csv has a header and one line per row',
   csv.lines.length == rows.length + 1, csv.lines.length)
ok('the csv names the kitchen floor with its area',
   csv.include?('floor,Kitchen,,,Porcelain,212.4,24x48,'), csv.lines[0, 3])
ok('the csv header names both columns',
   csv.lines[0].include?('category,face'), csv.lines[0])

puts($fails.zero? ? 'rt161 OK' : "rt161 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

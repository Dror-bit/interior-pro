# encoding: utf-8
# rt160 - HOW MUCH OF EACH MATERIAL (2026-09-18).
# He does not want a material card in the plugin - his business software
# holds supplier, code and price already. What only the MODEL knows is
# how much of each material the design uses: "Stone - 412 sq ft". It
# feeds the table he types into his software and the plans he prints.
#
# The two rules that decide whether the number is right:
#   1. a face with no material of its own wears its GROUP's material -
#      that is what SketchUp shows, so that is what gets counted;
#   2. a material is charged by its permanent id, never by its name.
require './sketchup_stub'
require './material_ids'
require './material_takeoff'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def near(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs <= tol
end

MT = InteriorPro::MaterialTakeoff
MI = InteriorPro::MaterialIds

# ---- 1. the pure arithmetic -----------------------------------------
ok('144 square inches is one square foot', near(MT.sqft(144.0), 1.0))
ok('a 24x48 tile is 8 sq ft', near(MT.sqft(24 * 48), 8.0))
t = MT.tally([['A', 100.0], ['B', 50.0], ['A', 44.0]])
ok('the same material adds up', near(t['A'][0], 144.0), t)
ok('...and its faces are counted', t['A'][1] == 2, t)
ok('a zero or negative area is not counted',
   MT.tally([['A', 0.0], ['B', -3.0]]).empty?)
ok('a nil material is not counted', MT.tally([[nil, 10.0]]).empty?)

rs = MT.rows(t, { 'A' => 'Stone', 'B' => 'Oak' })
ok('rows come biggest first', rs.map { |r| r[:name] } == %w[Stone Oak], rs)
ok('Stone is 1 sq ft', near(rs[0][:sqft], 1.0), rs[0])
ok('a key with no name shows the key itself',
   MT.rows({ 'IP_MAT_0009' => [144.0, 1] })[0][:name] == 'IP_MAT_0009')

csv = MT.to_csv(rs)
ok('the csv has a header and a line per material', csv.lines.length == 3, csv)
ok('the csv carries the id, not just the name',
   csv.lines[1].start_with?('A,Stone,1.0,144.0,2'), csv.lines[1])
ok('a name with a comma is quoted',
   MT.to_csv(MT.rows({ 'X' => [144.0, 1] }, { 'X' => 'Oak, light' }))
     .lines[1].include?('"Oak, light"'))

# ---- 2. a model ------------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
stone = m.materials.add('Stone')
oak   = m.materials.add('Oak')
MI.ensure_id!(stone, m)
MI.ensure_id!(oak, m)

def square(ents, side, mat = nil)
  f = ents.add_face([Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(side, 0, 0),
                     Geom::Point3d.new(side, side, 0), Geom::Point3d.new(0, side, 0)])
  f.material = mat if mat
  f
end

square(m.entities, 12.0, stone)          # 1 sq ft
square(m.entities, 24.0, oak)            # 4 sq ft
rows = MT.take(m)
ok('two materials come out', rows.length == 2, rows.map { |r| r[:name] })
ok('Oak is the bigger one, 4 sq ft', near(rows[0][:sqft], 4.0), rows[0])
ok('Stone is 1 sq ft', near(rows[1][:sqft], 1.0), rows[1])
ok('each is charged to its ID, not its name',
   rows.map { |r| r[:key] }.sort == %w[IP_MAT_0001 IP_MAT_0002],
   rows.map { |r| r[:key] })

# ---- 3. a face with no material wears the group's --------------------
g = m.entities.add_group
g.material = stone
square(g.entities, 12.0)                 # bare face inside a Stone group
rows = MT.take(m)
st = rows.find { |r| r[:key] == MI.id_of(stone) }
ok('the bare face in the Stone group is charged to Stone, 2 sq ft now',
   near(st[:sqft], 2.0), st)
ok('...and nothing landed under "(no material)"',
   rows.none? { |r| r[:key] == InteriorPro::MaterialTakeoff::NO_MATERIAL },
   rows.map { |r| r[:key] })

# ---- 4. a face with no material anywhere is still reported -----------
square(m.entities, 12.0)
rows = MT.take(m)
none = rows.find { |r| r[:key] == InteriorPro::MaterialTakeoff::NO_MATERIAL }
ok('a truly bare face is reported, not swallowed', none && near(none[:sqft], 1.0), none)

# ---- 5. renaming a material does not split its total -----------------
stone.name = 'Stone #1'
rows = MT.take(m)
st = rows.find { |r| r[:key] == 'IP_MAT_0001' }
ok('after a rename the total is still one row of 2 sq ft',
   st && near(st[:sqft], 2.0), st)
ok('...and it shows the new name', st[:name] == 'Stone #1', st[:name])

puts($fails.zero? ? 'rt160 OK' : "rt160 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

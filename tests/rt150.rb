# encoding: utf-8
# rt150 - ONE ROOF PER BUILDING (2026-09-14).
#
# "צריך לייצר גג נגיד לעוד בית בצד או ADU כי כרגע שאני עושה גג הוא
# מייחס את זה רק למבנה אחד". eave_polygon traces the LARGEST loop of the
# storey's walls, so a detached garage or an ADU on the same storey never
# got a roof. Now the storey's walls are split into buildings - walls that
# touch end to end - and a `level:` build makes one roof per building.
#
# WHAT IS PINNED HERE: the split itself, that a single building is left
# exactly as it was, and that a rebuild only takes down the roof of the
# building it stands on.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RF = InteriorPro::RoofManager

def wall(m, id, s, e)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => 'bottom-center', 'height' => 96.0, 'base_z' => 0.0,
    'level' => 1, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

Sketchup.reset_model!
m = Sketchup.active_model
# the house: 40 x 30 ft
house = [wall(m, 'h1', [0, 0], [480, 0]), wall(m, 'h2', [480, 0], [480, 360]),
         wall(m, 'h3', [480, 360], [0, 360]), wall(m, 'h4', [0, 360], [0, 0])]
# the ADU: 20 x 16 ft, thirty feet away
adu = [wall(m, 'a1', [840, 0], [1080, 0]), wall(m, 'a2', [1080, 0], [1080, 192]),
       wall(m, 'a3', [1080, 192], [840, 192]), wall(m, 'a4', [840, 192], [840, 0])]

groups = RF.buildings_of(house + adu)
ok('TWO BUILDINGS ARE TWO GROUPS', groups.length == 2, groups.length)
ok('the house comes first, being the larger',
   groups[0] && groups[0].map { |w| w.get_attribute('InteriorPro', 'id') }.sort == %w[h1 h2 h3 h4],
   groups[0] && groups[0].map { |w| w.get_attribute('InteriorPro', 'id') })
ok('...and the ADU is whole on its own',
   groups[1] && groups[1].map { |w| w.get_attribute('InteriorPro', 'id') }.sort == %w[a1 a2 a3 a4],
   groups[1] && groups[1].map { |w| w.get_attribute('InteriorPro', 'id') })
ok('no wall is lost between them', groups.flatten.length == 8, groups.flatten.length)

one = RF.buildings_of(house)
ok('a single building is ONE group with every wall in it',
   one.length == 1 && one[0].length == 4, one.map(&:length))
ok('a storey with too few walls is handed back untouched',
   RF.buildings_of(house.first(2)) == [house.first(2)], nil)

# a roof remembers its walls, and is only taken down by its own building
roof = m.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
roof.set_attribute('InteriorPro', 'level', 1)
roof.set_attribute('InteriorPro', 'set_walls', %w[h1 h2 h3 h4])
ok('the house roof stands on the house walls', RF.roof_on_walls?(roof, house), nil)
ok('...and NOT on the ADU walls', !RF.roof_on_walls?(roof, adu), nil)
old_roof = m.entities.add_group
old_roof.set_attribute('InteriorPro', 'type', 'roof')
ok('a roof from before walls were saved on it answers yes, as before',
   RF.roof_on_walls?(old_roof, adu), nil)

src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('build_roof! takes a building', src.include?('level: nil, replace: nil, building: nil)'), nil)
ok('a level build makes one roof per building',
   src.include?('build_roof!(**kw, level: lvl, building: b)'), nil)
ok('a rebuild keeps to the building the old roof stood on',
   src.include?("own = Array(replace.get_attribute('InteriorPro', 'set_walls'))"), nil)
ok('and dooms only the roofs standing on that building',
   src.include?('building.nil? || roof_on_walls?(r, walls)'), nil)
ok('a single building keeps the very same wall list',
   src.include?('walls = bldgs.first if (many || !building.nil?) && bldgs.first'), nil)

# ---- the storey above: only the building that stands OVER this one -------
# (2026-09-14: a detached building drawn on level 2 made the house's ground
# floor "not covered", and it grew a roof band under its own second storey)
def upwall(m, id, s, e)
  w = wall(m, id, s, e)
  w.set_attribute('InteriorPro', 'level', 2)
  w.set_attribute('InteriorPro', 'base_z', 106.0)
  w
end
up_house = [upwall(m, 'u1', [0, 0], [480, 0]), upwall(m, 'u2', [480, 0], [480, 360]),
            upwall(m, 'u3', [480, 360], [0, 360]), upwall(m, 'u4', [0, 360], [0, 0])]
# a BIGGER detached building on level 2, far away - the largest loop
up_far = [upwall(m, 'f1', [2000, 0], [2800, 0]), upwall(m, 'f2', [2800, 0], [2800, 600]),
          upwall(m, 'f3', [2800, 600], [2000, 600]), upwall(m, 'f4', [2000, 600], [2000, 0])]
over = RF.upper_over(house, up_house + up_far)
ok('only the upper building standing over the house is kept',
   over.map { |w| w.get_attribute('InteriorPro', 'id') }.sort == %w[u1 u2 u3 u4],
   over.map { |w| w.get_attribute('InteriorPro', 'id') })
ok('so the ground floor is still seen as covered',
   RF.storey_covered?(house, over), nil)
ok('...where the raw list, led by the far building, said it was not',
   !RF.storey_covered?(house, up_house + up_far), nil)
ok('a single upper building comes back exactly as given',
   RF.upper_over(house, up_house) == up_house, nil)
ok('nothing over the ADU: an empty list',
   RF.upper_over(adu, up_house + up_far).empty?, RF.upper_over(adu, up_house + up_far).length)
ok('build_roof! asks for it', src.include?('uppers = upper_over(walls, uppers) if uppers.length >= 3'), nil)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

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
   src.include?('building.nil? || roof_on_walls?(r, own_walls)'), nil)
ok('a single building keeps the very same wall list',
   src.include?('own_walls = cur[:walls]') && src.include?('walls = own_walls + closers'), nil)

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

# ---- one roof per WALL HEIGHT: the dropped garage (2026-09-14) ------------
# "אני רוצה שהגג ירד לגובה הקירות כי אם אני ארצה להגביה את הגג אני אגביה
# את הקירות". A garage dropped 18" hangs off the house's east wall.
def gwall(m, id, s, e, base, h)
  w = wall(m, id, s, e)
  w.set_attribute('InteriorPro', 'base_z', base)
  w.set_attribute('InteriorPro', 'height', h)
  w
end
Sketchup.reset_model!
m2 = Sketchup.active_model
hs = [gwall(m2, 'n', [0, 0], [480, 0], 0.0, 96.0), gwall(m2, 'e', [480, 0], [480, 360], 0.0, 96.0),
      gwall(m2, 's', [480, 360], [0, 360], 0.0, 96.0), gwall(m2, 'w', [0, 360], [0, 0], 0.0, 96.0)]
# the garage: three walls 18" lower, hanging off the east wall
gr = [gwall(m2, 'g1', [480, 60], [720, 60], -18.0, 96.0),
      gwall(m2, 'g2', [720, 60], [720, 300], -18.0, 96.0),
      gwall(m2, 'g3', [720, 300], [480, 300], -18.0, 96.0)]
sts = RF.storeys_of(RF.buildings_of(hs + gr))
ids = lambda { |ws| ws.map { |w| w.get_attribute('InteriorPro', 'id') }.sort }
ok('the house and the dropped garage are TWO buildings', sts.length == 2, sts.length)
house_b = sts.find { |b| b[:closers].empty? }
gar_b = sts.find { |b| !b[:closers].empty? }
ok('the house keeps its four walls and needs no closer',
   house_b && ids.call(house_b[:walls]) == %w[e n s w], house_b && ids.call(house_b[:walls]))
ok('THE GARAGE IS ITS OWN BUILDING, ON ITS OWN THREE WALLS',
   gar_b && ids.call(gar_b[:walls]) == %w[g1 g2 g3], gar_b && ids.call(gar_b[:walls]))
ok('...closed by the house wall it hangs off, which becomes its abut edge',
   gar_b && ids.call(gar_b[:closers]) == %w[e], gar_b && ids.call(gar_b[:closers]))
ok('the garage roof sits at the garage wall top, 18" under the house eave',
   gar_b && (RF.eave_z(gar_b[:walls]) - 78.0).abs < 1e-6 && (RF.eave_z(house_b[:walls]) - 96.0).abs < 1e-6,
   gar_b && RF.eave_z(gar_b[:walls]))

# a house whose walls all share one top is left exactly as it was
same = RF.storeys_of(RF.buildings_of(hs))
ok('one height = one building, untouched', same.length == 1 && same[0][:walls] == hs && same[0][:closers].empty?, nil)
# a single stepped wall cannot close a loop - it stays with the house
hs2 = hs + [gwall(m2, 'x', [480, 100], [600, 100], -18.0, 96.0)]
ok('one lone lower wall does not become a building of its own',
   RF.storeys_of(RF.buildings_of(hs2)).length == 1, RF.storeys_of(RF.buildings_of(hs2)).length)

src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('the eave height is the roof\x27s OWN walls, never the closers',
   src.include?('z0 = eave_z(own_walls) +') && !src.include?('z0 = eave_z(walls) +'), nil)
ok('the closers become abut edges - the roof dies into them',
   src.include?('abut_ids = (abut_ids + forced_abut).uniq unless forced_abut.empty?'), nil)
ok('a rebuild dooms by the roof\x27s own walls, so the house roof survives a garage build',
   src.include?('building.nil? || roof_on_walls?(r, own_walls)'), nil)

# ---- his real house (buildings_report 2026-09-14): the garage is a ROOM ----
# The wall between house and garage is INTERIOR and 96" under a 102"
# house; the house's own loop is open where the garage was, and only that
# interior wall closes it. The garage's loop closes on the same wall.
Sketchup.reset_model!
m3 = Sketchup.active_model
hw = lambda { |id, s, e| gwall(m3, id, s, e, 0.0, 102.0) }
lw = lambda { |id, s, e| gwall(m3, id, s, e, -18.0, 102.0) }
ext = [hw.call('east', [0, 0], [0, 520]), hw.call('north', [0, 520], [-604, 520]),
       hw.call('west_hi', [-604, 520], [-604, 0]), lw.call('west_lo', [-604, 0], [-604, -365]),
       lw.call('south_g', [-604, -365], [-315, -365]), lw.call('east_g', [-315, -365], [-315, 0]),
       hw.call('south_h', [-315, 0], [0, 0])]
div = gwall(m3, 'divider', [-315, 0], [-604, 0], 0.0, 96.0)
div.set_attribute('InteriorPro', 'wall_category', 'interior')
sts3 = RF.storeys_of(RF.buildings_of(ext), ext + [div])
ok('his house splits into house + garage', sts3.length == 2, sts3.length)
hb = sts3.find { |b| b[:abut] == false }
gb = sts3.find { |b| b[:abut] == true }
ok('the house loop is closed by the interior divider, though it is shorter',
   hb && ids.call(hb[:closers]).include?('divider'), hb && ids.call(hb[:closers]))
ok('...and the house roof stays at the house wall top',
   hb && (RF.eave_z(hb[:walls]) - 102.0).abs < 1e-6, hb && RF.eave_z(hb[:walls]))
ok('the garage dies into the divider and the tall west wall',
   gb && (ids.call(gb[:closers]) & %w[divider west_hi]).length == 2, gb && ids.call(gb[:closers]))
ok('BOTH loops close', !RF.eave_polygon(hb[:walls] + hb[:closers], 12.0).nil? &&
   !RF.eave_polygon(gb[:walls] + gb[:closers], 12.0).nil?, nil)

# ---- the jog where the divider meets the front wall (roof_parts_report) --
# his real numbers: divider y 2.8 (-318.4..-601.5), front wall y 2.5
# (-313.4..0), west wall ending at (-604, 0.5). Two rails 0.3" apart put
# their corner 7000" away and a trim face ran x -7178..2127.
Sketchup.reset_model!
m4 = Sketchup.active_model
hw4 = lambda { |id, s, e| gwall(m4, id, s, e, 0.0, 102.0) }
loop4 = [hw4.call('east', [-2.5, 0], [-2.5, 523.8]), hw4.call('north', [0, 521.3], [-606.5, 521.3]),
         hw4.call('west_hi', [-604, 523.8], [-604, 0.5]), hw4.call('front', [-313.4, 2.5], [0, 2.5])]
div4 = gwall(m4, 'divider', [-318.4, 2.8], [-601.5, 2.8], 0.0, 96.0)
div4.set_attribute('InteriorPro', 'wall_category', 'interior')
raw = RF.eave_polygon(loop4 + [div4], 12.0)
ok('WITHOUT the flat-corner pass the jog is a fifth corner, 0.3" off the line',
   raw && raw[:pts].length == 5, raw && raw[:pts].length)
fixed = RF.eave_polygon(loop4 + [div4], 12.0, 3.0)
ok('with it the outline stays around the house',
   fixed && fixed[:pts].none? { |p| p[0].abs > 700 || p[1].abs > 700 }, fixed && fixed[:pts])
ok('...four corners, the jog gone', fixed && fixed[:pts].length == 4, fixed && fixed[:pts].length)
ok('...and the merged front edge keeps the LONGER wall, the exterior one',
   fixed && fixed[:wall_ids].include?('front') && !fixed[:wall_ids].include?('divider'), fixed && fixed[:wall_ids])
src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('build_roof! asks for it only when closers were added',
   src.include?("closers.empty? ? nil : 3.0) : nil"), nil)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

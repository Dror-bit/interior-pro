# encoding: utf-8
# rt317 - "KITCHEN" IN THE ELEVATIONS LIST (2026-10-15 10:48, his "אתה לא חושב שהוא צריך להראות לי אופציה של מטבח? ... אני לא
# רוצה שהסלון יהיה באליוויישן"): the kitchen's room, but only the walls with kitchen on them, on a sheet called Kitchen.
require './sketchup_stub'
require './electrical_library'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
src = File.read('./elevation_tool.rb')
ok('kill switch is there and on', ET::USE_KITCHEN_PICK == true && ET::KITCHEN_LABEL == 'Kitchen')
poly = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(200, 0, 0), Geom::Point3d.new(200, 150, 0), Geom::Point3d.new(0, 150, 0)]
Box = Struct.new(:min, :max)
Ent = Struct.new(:x0, :x1, :y0, :y1, :tag) do
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1, y1, 36)); end
  def valid?; true; end
  def entities; []; end
  def get_attribute(d, k); d == 'KitchenLab' && k == 'data' && tag ? "{\"wall\":\"#{tag}\"}" : nil; end
end
xf = Geom::Transformation.new
run = Ent.new(10, 130, 0, 25, 'A')        # the base run along the y=0 wall
island = Ent.new(60, 120, 60, 100, 'I')   # an island in the middle
names = ET.sides(poly).map(&:name)
got = ET.kitchen_sides(poly, [[run, 'kitchen_unit', xf], [island, 'kitchen_unit', xf]], 0.0)
ok('one wall has kitchen on it, the one the run stands against', got.size == 1 && names.include?(got.first), [got, names])
ok('no kitchen: no walls', ET.kitchen_sides(poly, [], 0.0).empty?)
# 11:22, his sheet had four walls: the one box of the countertop / backsplash run spans the whole L - it does not count
ell = Ent.new(0, 200, 0, 150)
got2 = ET.kitchen_sides(poly, [[run, 'kitchen_unit', xf], [ell, 'worktop', xf]], 0.0)
ok('the run of countertop / backsplash adds no wall', got2 == got, got2)
# 11:49, measured: the tall cabinet in the corner touches the next wall with its side; the lone microwave base on the far
# wall goes with its letter - neither adds a wall
tall = Ent.new(0, 16, 0, 25, 'A')          # in the corner: touches x=0 (its side) and y=0 (its back)
lone = Ent.new(190, 200, 100, 130, 'A')    # against x=200, alone, but letter A = the y=0 run
got3 = ET.kitchen_sides(poly, [[run, 'kitchen_unit', xf], [tall, 'kitchen_unit', xf], [lone, 'kitchen_unit', xf]], 0.0)
ok('a corner cabinet\'s side and a lone cabinet of the same letter add no wall', got3 == got, got3)
b_run = Ent.new(0, 25, 20, 120, 'B')       # the other leg of the L, letter B, on x=0
got4 = ET.kitchen_sides(poly, [[run, 'kitchen_unit', xf], [b_run, 'kitchen_unit', xf]], 0.0)
ok('two letters: two walls', got4.size == 2, got4)
nolet = Ent.new(0, 16, 0, 25, nil)
ok('no letter: the wall it touches most', ET.kitchen_sides(poly, [[nolet, 'kitchen_unit', xf]], 0.0).size == 1)
ok('the Kitchen sheet keeps the floors down in its plan', src.include?("keep_down = label == KITCHEN_LABEL ? PLAN_NO_FLOOR : []") && ET::PLAN_NO_FLOOR.include?('floor_pattern'))
ok('shoot! takes only the walls asked for, under the label', src.include?('next if sides && !sides.include?(side.name)') && src.include?('name = label || room_name(room)'))
ok('make_kitchen! is there and goes through make! with the kitchen walls and the label', src.include?("make!(room, cut: cut, style: style, sides: names, label: KITCHEN_LABEL)"))
dsrc = File.read('./elevation_dialog.rb')
ok('the window lists Kitchen first and sends it as K', dsrc.include?('data-i=\"K\"') && dsrc.include?("make_kitchen!(cut: kc") && dsrc.include?('#{kopt}#{opts}'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

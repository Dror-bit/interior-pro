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
# 12:26 (USE_KITCHEN_FACING), measured kitchen_dims_report: every cabinet carries the letter A, so the letter picked ONE
# wall and West went missing. Now a wall counts when a cabinet stands on it with its BACK (its cabinet's +y), whatever
# the letter; a corner cabinet on both; his "כל קבינט שקשור לחדר המטבח הוא חלק ממנו" - a lone one on a far wall counts.
ok('kill switch for the facing rule is there and on', ET::USE_KITCHEN_FACING == true)
Cab = Struct.new(:ang, :kind) do
  def transformation; Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), ang * Math::PI / 180.0); end
  def get_attribute(d, k)
    return nil unless d == 'KitchenLab'
    k == 'kind' ? 'cabinet' : (k == 'data' ? "{\"kind\":\"#{kind}\",\"wall\":\"A\"}" : nil)
  end
end
Unit = Struct.new(:x0, :x1, :y0, :y1, :cab) do
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1, y1, 36)); end
  def valid?; true; end
  def entities; [cab]; end
  def get_attribute(_d, _k); nil; end
end
y0w = ET.sides(poly).find { |s| s.inward.y > 0.5 }.name     # the wall at y = 0
x0w = ET.sides(poly).find { |s| s.inward.x > 0.5 }.name     # the wall at x = 0
x2w = ET.sides(poly).find { |s| s.inward.x < -0.5 }.name    # the wall at x = 200
frun = Unit.new(16, 130, 0, 25, Cab.new(180, 'doors'))       # back to y = 0
ftall = Unit.new(0, 16, 0, 25, Cab.new(180, 'tall'))         # in the corner, back to y = 0, its SIDE on x = 0
flone = Unit.new(175, 200, 100, 130, Cab.new(-90, 'microwave'))  # alone, back to x = 200
fcorner = Unit.new(0, 38, 0, 38, Cab.new(0, 'corner_base'))  # the corner of the L: both
back = ET.kitchen_back(frun, xf)
ok('a cabinet\'s back looks at its wall (+y of its cabinet turned 180 = -y)', back && back.y < -0.9, back && [back.x, back.y])
g5 = ET.kitchen_sides(poly, [[frun, 'kitchen_unit', xf], [ftall, 'kitchen_unit', xf]], 0.0)
ok('the tall one in the corner: its side on the next wall adds no wall', g5 == [y0w], g5)
g6 = ET.kitchen_sides(poly, [[frun, 'kitchen_unit', xf], [flone, 'kitchen_unit', xf]], 0.0)
ok('a lone cabinet on a far wall is part of the kitchen (same letter A)', g6.sort == [y0w, x2w].sort, g6)
g7 = ET.kitchen_sides(poly, [[fcorner, 'kitchen_unit', xf]], 0.0)
ok('a corner cabinet stands on both of its walls', g7.sort == [y0w, x0w].sort, g7)
ok('the Kitchen sheet keeps the floors down in its plan', src.include?("keep_down = label == KITCHEN_LABEL ? PLAN_NO_FLOOR : []") && ET::PLAN_NO_FLOOR.include?('floor_pattern'))
ok('shoot! takes only the walls asked for, under the label', src.include?('next if sides && !sides.include?(side.name)') && src.include?('name = label || room_name(room)'))
ok('make_kitchen! is there and goes through make! with the kitchen walls and the label', src.include?("make!(room, cut: cut, style: style, sides: names, label: KITCHEN_LABEL)"))
dsrc = File.read('./elevation_dialog.rb')
ok('the window lists Kitchen first and sends it as K', dsrc.include?('data-i=\"K\"') && dsrc.include?("make_kitchen!(cut: kc") && dsrc.include?('#{kopt}#{opts}'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

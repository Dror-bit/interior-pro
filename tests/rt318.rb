# encoding: utf-8
# rt318 - THE KITCHEN'S NUMBERS ON ITS ELEVATION (2026-10-15 12:17, his "אין מידות לארונות... המידות מבולגנות"):
# orange (g 'kitchen'): the base cabinets' widths in a chain under the floor, the uppers' over the ceiling, the heights by
# the nearer wall; an appliance 35 15/16 wide says 36; the electric rows of one half never on each other.
require './sketchup_stub'
require './electrical_library'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switches are there and on', ET::USE_KITCHEN_DIMS == true && ET::USE_ELEC_STACK == true)
# his West wall as measured (kitchen_dims_report 12:24): a = along from side.a
side = ET::Side.new('West', Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(214.5, 0, 0), 214.5, Geom::Vector3d.new(0, 1, 0), 200.0)
cab = ->(a0, a1, z0, z1) { { kind: 'cabinet', a0: a0, a1: a1, z0: z0, z1: z1, w: a1 - a0, name: 'x' } }
items = [cab.(0, 38, 0, 34.5), cab.(38, 47, 0, 34.5), cab.(47, 83, 0, 34.5), cab.(83, 92, 0, 34.5), cab.(92, 110, 0, 34.5),
         cab.(110, 134, 0, 90), cab.(0, 24, 54, 84), { kind: 'counter', a0: 0, a1: 110, z0: 36, z1: 36 }]
ds = ET.dims_clean(side, 96.0, items)
k = ds.select { |d| d['g'] == 'kitchen' }
base = k.select { |d| d['k'] == 'h' && !d['up'] }.sort_by { |d| d['u'][0] }.map { |d| d['t'] }
ok('the base chain under the floor, left to right as the picture shows it, corner to corner', base == ['80 1/2"', '24"', '18"', '9"', '36"', '9"', '38"'], base)
ok('the base chain is the first row, the wall\'s length the second', k.select { |d| d['k'] == 'h' && !d['up'] }.all? { |d| d['row'] == 1 } &&
   ds.find { |d| d['t'] == '214 1/2"' && d['k'] == 'h' }['row'] == 2)
up = k.select { |d| d['up'] }.sort_by { |d| d['u'][0] }
ok('the uppers\' chain over the ceiling (v = the ceiling), the cabinet and the rest of the wall', up.map { |d| d['t'] } == ['190 1/2"', '24"'] &&
   up.all? { |d| (d['v'] - (ET::MARGIN + 96.0) / (96.0 + 2 * ET::MARGIN)).abs < 1e-9 }, up)
r = up.find { |d| d['t'] == '24"' }['r']
ok('its witness lines start at the cabinet\'s top (84)', r && r.compact.all? { |v| (v - (ET::MARGIN + 84.0) / 120.0).abs < 1e-9 }, r)
hs = k.select { |d| d['k'] == 'v' }.map { |d| d['t'] }.sort
ok('heights: the upper floor -> counter -> bottom -> top (36, 18, 30), the tall one 90; the counter not twice', hs == ['18"', '30"', '36"', '90"'], hs)
ok('an appliance 35 15/16 wide says 36', ET.fmt_in(35.9375) == '36"')
ok('no kitchen: no orange', ET.dims_clean(side, 96.0, []).none? { |d| d['g'] == 'kitchen' })
# the electric rows of his West wall: plates at 48 (46..50) and 42 (40..44) - their rows 10" apart, under all the plates
el = [{ kind: 'elec', a0: 92.0, a1: 92.0, z0: 48.0, z1: 48.0, lo: 46.0, hi: 50.0, l: 91.0, r: 93.0 },
      { kind: 'elec', a0: 80.5, a1: 80.5, z0: 42.0, z1: 42.0, lo: 40.0, hi: 44.0, l: 79.5, r: 81.5 }]
rows = ET.dims_clean(side, 96.0, el).select { |d| d['k'] == 'hi' }.map { |d| d['v'] }.uniq.sort
ok('two rows of electric distances stand 10" apart, both under all the plates', rows.size == 2 && ((rows[1] - rows[0]) * 120.0 - 10.0).abs < 1e-6 &&
   rows.max * 120.0 - ET::MARGIN <= 40.0 - ET::ELEC_ROW + 1e-6, rows.map { |v| v * 120 - ET::MARGIN })
# kitchen_items off a model: a unit on the wall with its back to it counts, one beside it with its side does not
Box = Struct.new(:min, :max)
Cab = Struct.new(:ang) do
  def transformation; Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), ang * Math::PI / 180.0); end
  def get_attribute(d, k); d == 'KitchenLab' ? (k == 'kind' ? 'cabinet' : (k == 'data' ? '{"kind":"doors"}' : nil)) : nil; end
end
Unit = Struct.new(:x0, :x1, :y0, :y1, :z1, :cab, :name) do
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1, y1, z1)); end
  def valid?; true; end
  def entities; cab ? [cab] : []; end
  def get_attribute(_d, _k); nil; end
end
xf = Geom::Transformation.new
on = Unit.new(47, 83, 0, 25, 34.5, Cab.new(180), 'Kitchen / doors')
sideways = Unit.new(190, 214.5, 0, 16, 90, Cab.new(-90), 'Kitchen / tall')
top = Unit.new(0, 110, 0, 110, 36, nil, 'Kitchen / Continuous countertop')
its = ET.kitchen_items(side, [[on, 'kitchen_unit', xf], [sideways, 'kitchen_unit', xf], [top, 'worktop', xf]], 0.0)
ok('kitchen_items: the cabinet with its back on the wall, the countertop\'s top; not the one with its side to it',
   its.map { |i| i[:kind] } == ['cabinet', 'counter'] && its[0][:w] == 36.0 && its[1][:z1] == 36.0, its)
src = File.read('./elevation_tool.rb')
ok('shoot! hands the kitchen to the numbers', src.include?('safely_items(side, s[:cut], all, base_z, kit_d)'))
ok('the kitchen is read BEFORE any wall puts its far cabinets aside (12:44: South lost its cabinet)', src.include?('kit_d = USE_KITCHEN_DIMS ? (USE_ON_WALL_ONLY ? kitchen : kitchen_tops(model)) : nil') && !src.include?('kit_d ||='))
ok('the row of pictures leaves room over them for the uppers\' row', src.include?('row_boxes(pc.pic_area(pg), sizes, cols, ups)'))
bx0 = ET.row_boxes([0.5, 1.5, 30.0, 20.0], [[2000, 1440]], [[0, 1]])
bx1 = ET.row_boxes([0.5, 1.5, 30.0, 20.0], [[2000, 1440]], [[0, 1]], 1)
ok('with an uppers\' row the picture stands lower by a row', bx1[0][1] + bx1[0][3] < bx0[0][1] + bx0[0][3] - 0.4, [bx0, bx1])
pc = File.read('./plan_canvas.rb')
ok('the sheet: kitchen orange, its own layer, a row over its line', pc.include?("'kitchen' => '#c8731e'") &&
   pc.include?('%w[tile plumbing electric kitchen]') && pc.include?("sg = d['up'] ? -1.0 : 1.0"))
ok('the window lists KITCHEN among the layers', File.read('./plan_sheet_dialog.rb').include?("['electric','ELECTRICAL'],['kitchen','KITCHEN']"))
# 13:00 South's black shape (south_black_report): the continuous backsplash = ONE worktop group over the L; its far piece
# is put aside for this wall's picture, its near piece stays
ok('kill switch for the worktop pieces is there and on', ET::USE_WORKTOP_PIECES == true)
Piece = Struct.new(:x0, :x1, :y0, :y1) do
  attr_accessor :hidden
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(x0, y0, 36), Geom::Point3d.new(x1, y1, 66)); end
  def valid?; true; end
end
near = Piece.new(0, 100, 0, 1.5)
far = Piece.new(0, 25, 104.5, 214.5)
Run = Struct.new(:kids) do
  def transformation; Geom::Transformation.new; end
  def bounds; Box.new(Geom::Point3d.new(0, 0, 36), Geom::Point3d.new(100, 214.5, 66)); end
  def valid?; true; end
  def entities; kids; end
end
run = Run.new([near, far])
if defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:box_in_frame)
  aside = ET.off_wall(side, [], [[run, 'worktop', xf]], 0.0)
  ok('the worktop group stays, only its far piece is put aside', aside == [far], aside.map { |a| a.class.name })
end
ok(%q(16:51: the cabinets numbers only on the Kitchen sheet), ET::USE_KITCHEN_DIMS_ONLY_KITCHEN == true && src.include?(%q(kit_d = nil if USE_KITCHEN_DIMS_ONLY_KITCHEN && label != KITCHEN_LABEL)))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

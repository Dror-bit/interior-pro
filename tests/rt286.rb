# encoding: utf-8
# rt286 - Elevations: a fixture made of parts is measured part by part, at each
# part's MIDDLE (2026-10-08 13:44, his "1"): the height of the middle from the
# floor, and where the middle stands along the wall - no width, no bottom/top.
# Numbers: his shower set on the North wall of Room 2 (debug_fixture_parts.rb, 13:42).
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
require './tile_niche'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
P = Geom::Point3d

north = ET::Side.new('North', P.new(-443.0, 402.5, 0), P.new(-530.1, 402.5, 0), 87.1, Geom::Vector3d.new(0, -1, 0), 70.08)
def box8(x0, x1, y0, y1, z0, z1)
  [x0, x1].product([y0, y1], [z0, z1]).map { |x, y, z| P.new(x, y, z) }
end

model = Sketchup.active_model
fx = model.entities.add_group
fx.set_attribute('InteriorPro', 'type', 'fixture')
head = fx.entities.add_group
valve = fx.entities.add_group
hand = fx.entities.add_group
BOXES = {
  fx => box8(-477.74, -459.26, 381.21, 401.88, 18.86, 81.18),
  head => box8(-469.10, -459.26, 381.21, 401.88, 75.45, 81.18),
  valve => box8(-466.87, -461.49, 398.62, 401.88, 43.88, 53.38),
  hand => box8(-477.74, -469.97, 391.21, 401.88, 18.86, 72.52)
}
# the stub has no real boxes: answer his measured ones
ET.define_singleton_method(:world_box) { |t| BOXES[t.ent] }
th = ET::Thing.new(fx, fx.transformation, 'fixture')

ok('the set is three parts', ET.part_boxes(th).size == 3, ET.part_boxes(th))
its = ET.side_items(north, 33.0, [th], 0.0)
ok('three things measured, one a part', its.size == 3 && its.all? { |i| i[:kind] == 'part' }, its)
mids = its.map { |i| [i[:a0].round(2), i[:z0].round(2)] }.sort
ok('each at its middle: head and valve 21.18 along, the hand 30.86; heights 78.32, 48.63, 45.69',
   mids == [[21.18, 48.63], [21.18, 78.32], [30.86, 45.69]], mids)

d = ET.dims_for(north, 96.0, its)
row1 = d.select { |x| x['k'] == 'h' && x['row'] == 1 }.map { |x| x['t'] }
ok('the chain: corner -> the hand\'s middle -> the valve and head\'s middle -> corner (no widths)',
   row1 == ['56 1/4"', '9 11/16"', '21 3/16"'], row1)
cols = d.select { |x| x['k'] == 'v' }.group_by { |x| x['col'] }.map { |_, xs| xs.map { |x| x['t'] } }
ok('one height each, floor to the middle, then the wall',
   cols[0..2].map(&:size).uniq == [1] && cols[0..2].flatten.sort == ['45 11/16"', '48 5/8"', '78 5/16"'].sort && cols[3] == ['96"'], cols)
ok('every height starts at the floor', d.select { |x| x['k'] == 'v' }.all? { |x| (x['v'][0] - 12.0 / 120.0).abs < 1e-9 })

# a fixture with one part (a tub, a toilet) keeps the old box
tub = model.entities.add_group
tub.set_attribute('InteriorPro', 'type', 'fixture')
one = tub.entities.add_group
BOXES[tub] = box8(-473.0, -443.0, 371.0, 402.0, 0.0, 18.19)
BOXES[one] = BOXES[tub]
ti = ET.side_items(north, 33.0, [ET::Thing.new(tub, tub.transformation, 'fixture')], 0.0)
ok('one part: the old box, width and height', ti.size == 1 && ti[0][:kind] == 'fixture' && (ti[0][:z1] - 18.19).abs < 0.01, ti)

ET.send(:remove_const, :USE_PART_MIDDLES)
ET.const_set(:USE_PART_MIDDLES, false)
off = ET.side_items(north, 33.0, [th], 0.0)
ok('switched off: the whole set as one box, as before', off.size == 1 && off[0][:kind] == 'fixture' &&
   (off[0][:z0] - 18.86).abs < 0.01 && (off[0][:z1] - 81.18).abs < 0.01, off)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

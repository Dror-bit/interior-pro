# encoding: utf-8
# rt286 - Elevations: a fixture made of parts is measured part by part, at each
# part's MIDDLE (2026-10-08 13:44, his "1"): the height of the middle from the
# floor, and where the middle stands along the wall - no width, no bottom/top.
# Numbers: his shower set on the North wall of Room 2 (debug_fixture_parts.rb, 13:42).
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      []
    end
  end
end
require './door_library'
require './plan_generator'
require './plan_doc'
require './plan_tables'
require './plan_geometry'
require './plan_canvas'
require './plan_pdf'
require './tile_niche'
require './elevation_tool'
# this file pins the long chain and the heights on the right (before 15:57) - rt288 holds the clean ones
InteriorPro::ElevationTool.send(:remove_const, :USE_CLEAN_DIMS)
InteriorPro::ElevationTool.const_set(:USE_CLEAN_DIMS, false)
InteriorPro::ElevationTool.send(:remove_const, :DIM_STEP)
InteriorPro::ElevationTool.const_set(:DIM_STEP, 16)   # the sixteenths of the day (16:32: halves since)

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

# 13:54 "שהקווים יגעו בנקודה": the lines run TO each part's middle
vz = ->(z) { (12.0 + z) / 120.0 }
ux = ->(a) { (12.0 + 87.1 - a) / 111.1 }
hs = d.select { |x| x['k'] == 'h' && x['row'] == 1 }
ok('the chain: the hand\'s stop reaches 45.69 up, the head/valve stop the head\'s 78.32 (the higher), the corners the floor',
   (hs[0]['r'][0].nil? && (hs[0]['r'][1] - vz.call(45.69)).abs < 1e-3 &&
   (hs[1]['r'][0] - vz.call(45.69)).abs < 1e-3 && (hs[1]['r'][1] - vz.call(78.315)).abs < 1e-3 &&
   (hs[2]['r'][0] - vz.call(78.315)).abs < 1e-3 && hs[2]['r'][1].nil?), hs.map { |x| x['r'] })
vs = d.select { |x| x['k'] == 'v' && x['u0'] }
ok('each part\'s height carries where its middle stands', vs.size == 3 &&
   vs.map { |x| x['u0'].round(4) }.sort == [ux.call(21.18), ux.call(21.18), ux.call(30.855)].map { |v| v.round(4) }.sort, vs.map { |x| x['u0'] })
ok('the wall\'s height has none', d.find { |x| x['t'] == '96"' }['u0'].nil?)

# drawn on paper: a picture 11.11 x 12 paper inches = 0.1 paper inch a model inch
lay = Object.new
def lay.lines; @lines ||= []; end
def lay.line(x1, y1, x2, y2, *_); lines << [x1, y1, x2, y2]; end
def lay.text(*_); end
main = { x: 0.0, y: 0.0, w: 11.11, h: 12.0, placed: true, rot: 0.0 }
PC = InteriorPro::PlanCanvas
PC.draw_elev_dim(lay, main, hs[1])
xh = (12.0 + 87.1 - 30.855) * 0.1
up = lay.lines.find { |l| (l[0] - xh).abs < 1e-3 && (l[2] - xh).abs < 1e-3 && [l[1], l[3]].max > 1.3 }
ok('the chain\'s line at the hand goes up to the hand\'s middle (45.69" over the floor)', up && ([up[1], up[3]].max - (12.0 + 45.69) * 0.1).abs < 2e-3, lay.lines)
lay.lines.clear
vh = vs.find { |x| x['t'] == '78 5/16"' }
PC.draw_elev_dim(lay, main, vh)
yt = (12.0 + 78.315) * 0.1
across = lay.lines.find { |l| (l[1] - yt).abs < 2e-3 && (l[3] - yt).abs < 2e-3 && (l[2] - l[0]).abs > 0.5 }
ok('the head\'s height line starts at the head\'s middle', across && ([across[0], across[2]].min - (12.0 + 87.1 - 21.18) * 0.1).abs < 2e-3, lay.lines)
ET.send(:remove_const, :USE_PART_REACH)
ET.const_set(:USE_PART_REACH, false)
d2 = ET.dims_for(north, 96.0, its)
ok('reach switched off: no r, no u0 - the lines stop at the floor and the corner', d2.none? { |x| x.key?('r') || x.key?('u0') }, d2)

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

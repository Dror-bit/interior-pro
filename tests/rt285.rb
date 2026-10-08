# encoding: utf-8
# rt285 - Elevations: the automatic dimensions (2026-10-08).
#
# His Room 2, measured (debug_elev_items.rb, 12:57): North 87.1" with the tub
# 0..30.62 along it (18.19" high) and the tile 0.62..43.61; East 70.08" with a
# niche 36 x 18 at 42" up, 17.1..53.1 along, and the tub along its whole length.
# What is checked: the numbers (dims_for), the niche read off the wall's own
# row (side_items), and the lines and words laid over the picture on its sheet
# (PlanCanvas.place_elev_dims!), and the switch.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
require 'tmpdir'
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
require './plan_sheet_dialog'
require './tile_niche'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
PC = InteriorPro::PlanCanvas

ok('to the sixteenth', %w[87.1 18.19 36 0.5 12.99].map { |v| ET.fmt_in(v.to_f) } == ['87 1/8"', '18 3/16"', '36"', '1/2"', '13"'],
   %w[87.1 18.19 36 0.5 12.99].map { |v| ET.fmt_in(v.to_f) })

north = ET::Side.new('North', Geom::Point3d.new(-443.0, 402.5, 0), Geom::Point3d.new(-530.1, 402.5, 0), 87.1,
                     Geom::Vector3d.new(0, -1, 0), 70.08)
items = [{ kind: 'fixture', a0: 0.0, a1: 30.62, z0: 0.0, z1: 18.19 },
         { kind: 'tile_wall', a0: 0.62, a1: 43.61, z0: 0.0, z1: 96.0 }]
d = ET.dims_for(north, 96.0, items)
row1 = d.select { |x| x['k'] == 'h' && x['row'] == 1 }.map { |x| x['t'] }
ok('North: the chain under the floor, left to right as the picture shows it', row1 == ['43 1/2"', '13"', '30 5/8"'], row1)
ok('North: the whole wall in the second row', d.any? { |x| x['k'] == 'h' && x['row'] == 2 && x['t'] == '87 1/8"' }, d)
ok('the tile\'s 5/8" off the corner is not a dimension of its own', row1.none? { |t| t == '5/8"' })
col = d.select { |x| x['k'] == 'v' }.map { |x| [x['col'], x['t']] }
ok('North: the tub\'s height, then the wall\'s', col == [[1, '18 3/16"'], [2, '96"']], col)
first = d.find { |x| x['k'] == 'h' && x['row'] == 1 }
ok('the picture looks at the wall: side.b (87.1) is at the left, 12" in', (first['u'][0] - 12.0 / 111.1).abs < 1e-6, first['u'])
ok('the floor is 12" up the picture', (first['v'] - 12.0 / 120.0).abs < 1e-6, first['v'])

east = ET::Side.new('East', Geom::Point3d.new(-443.0, 332.42, 0), Geom::Point3d.new(-443.0, 402.5, 0), 70.08,
                    Geom::Vector3d.new(-1, 0, 0), 87.1)
ei = [{ kind: 'niche', a0: 17.1, a1: 53.1, z0: 42.0, z1: 60.0 },
      { kind: 'fixture', a0: 0.62, a1: 69.46, z0: 0.0, z1: 18.19 }]
de = ET.dims_for(east, 96.0, ei)
row1 = de.select { |x| x['k'] == 'h' && x['row'] == 1 }.map { |x| x['t'] }
ok('East: the niche\'s width in the chain, and where it stands from each corner', row1 == ['17"', '36"', '17 1/8"'], row1)
cols = de.select { |x| x['k'] == 'v' }.group_by { |x| x['col'] }.map { |c, xs| [c, xs.map { |x| x['t'] }] }
ok('East: the niche: up from the floor, then its own height; the tub; the wall',
   cols.sort == [[1, ['18 3/16"']], [2, ['42"', '18"']], [3, ['96"']]], cols)

# the niche read off the wall's own row, on the face looking into the room
model = Sketchup.active_model
wall = model.entities.add_group
wall.set_attribute('InteriorPro', 'type', 'wall')
wall.set_attribute('InteriorPro', 'id', 'w6')
# the East wall of Room 2 runs south -> north on x = -440.5 (5" thick, centred): side 'a' is the left = west = into the room
{ 'start_x' => -440.5, 'start_y' => 327.42, 'end_x' => -440.5, 'end_y' => 407.5, 'thickness' => 5.0, 'height' => 96.0 }.each { |k, v| wall.set_attribute('InteriorPro', k, v) }
wall.set_attribute('InteriorPro', 'niches', [['a', 22.1, 42.0, 36.0, 18.0, 4.0]])
# the real API answers the wall's box; the stub's has no min - the wall stands on the floor
def wall.bounds; Struct.new(:min).new(Geom::Point3d.new(-443.0, 327.42, 0.0)); end
th = ET::Thing.new(wall, wall.transformation, 'wall')
got = ET.side_items(east, 33.0, [th], 0.0)
ok('the niche is found on the East wall, from the wall\'s numbers', got.size == 1 && got[0][:kind] == 'niche', got)
if got[0]
  ok('17.1..53.1 along, 42..60 up', (got[0][:a0] - 17.1).abs < 0.05 && (got[0][:a1] - 53.1).abs < 0.05 &&
     (got[0][:z0] - 42.0).abs < 0.01 && (got[0][:z1] - 60.0).abs < 0.01, got[0])
end
ok('and not on the North wall (it does not look into it there)', ET.side_items(north, 33.0, [th], 0.0).empty?)

# onto the sheet
psd = InteriorPro::PlanSheetDialog
st = psd.load_state
st['images'] = ['/e/Room_2_North_lines.png']
psd.save_state(st)
ET.add_to_sheet!(['/e/Room_2_North_lines.png'], { '/e/Room_2_North_lines.png' => 'Room 2 - North' },
                 { '/e/Room_2_North_lines.png' => d })
st = psd.load_state
ok('the dimensions survive save_state', st['image_dims'].is_a?(Hash) && st['image_dims']['/e/Room_2_North_lines.png'] == JSON.parse(d.to_json), st['image_dims'])
psd.instance_variable_set(:@doc, nil)
doc = psd.document
pg = doc.pages.find { |p| p.kind == 'image' }
lay = pg && pg.layers.find { |l| l.name == PC::ELEV_DIM_LAYER }
words = lay ? lay.shapes.select { |s| s[:type] == :text }.map { |s| s[:text] } : []
ok('the words are on the picture\'s sheet', %w[43\ 1/2" 13" 30\ 5/8" 87\ 1/8" 18\ 3/16" 96"].all? { |w| words.include?(w) }, words)
main = pg.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
t87 = lay.shapes.find { |s| s[:type] == :text && s[:text] == '87 1/8"' }
fy = main[:y] + 0.1 * main[:h]
ok('the whole wall runs under the floor, inside the picture\'s width',
   t87[:x] > main[:x] && t87[:x] < main[:x] + main[:w] && t87[:y] < fy && t87[:y] > fy - 3 * PC::ELEV_ROW, [t87[:x], t87[:y], main.values_at(:x, :y, :w, :h)])
t96 = lay.shapes.find { |s| s[:type] == :text && s[:text] == '96"' }
ok('the wall\'s height stands upright, right of the room\'s corner', t96[:rotation] == 90.0 && t96[:x] > main[:x] + main[:w] * (99.1 / 111.1), t96)
ok('every line is a line on paper (some ticks, some witness lines)', lay.shapes.count { |s| s[:type] == :line } >= 4 * 6, lay.shapes.size)

PC.send(:remove_const, :USE_ELEV_DIMS)
PC.const_set(:USE_ELEV_DIMS, false)
psd.instance_variable_set(:@doc, nil)
doc = psd.document
pg = doc.pages.find { |p| p.kind == 'image' }
ok('switched off: the picture alone', pg.layers.none? { |l| l.name == PC::ELEV_DIM_LAYER && !l.shapes.empty? })

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

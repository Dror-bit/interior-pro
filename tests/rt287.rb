# encoding: utf-8
# rt287 - Elevations: a room's walls on ONE sheet (2026-10-08 14:00, "ניראה מעולה"
# on a picture of the four walls in a row). The first wall owns the sheet, the others
# are pictures beside it, each in its own box, at one scale, in the top half; every
# one carries its own dimensions; a box he moved stays when the pictures are taken again.
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
# Pin the legacy row path; the enabled sheet-size grid is exercised by rt326.
ET.send(:remove_const, :USE_SHEET_SIZE)
ET.const_set(:USE_SHEET_SIZE, false)
PC = InteriorPro::PlanCanvas
psd = InteriorPro::PlanSheetDialog

# the row, by itself: his four pictures (1333 / 1129 px wide, 1440 high)
area = [0.5, 1.5, 16.0, 9.0]
sizes = [[1333, 1440], [1129, 1440], [1333, 1440], [1129, 1440]]
bx = ET.row_boxes(area, sizes, [4, 3, 1, 1])
ok('four boxes', bx.size == 4, bx)
k = bx.map { |b| b[2] / 1.0 }.zip(sizes).map { |w, s| w / s[0] }
ok('one scale for all of them', k.uniq.size == 1 || (k.max - k.min) < 1e-9, k)
ok('their tops on the top of the area', bx.all? { |b| (b[1] + b[3] - 10.5).abs < 1e-9 }, bx)
ok('in the top half', bx.all? { |b| b[1] >= 1.5 + 4.5 - 1e-9 - 3 * PC::ELEV_ROW }, bx)
ok('side by side, left to right, room for the heights between', (0..2).all? { |i| bx[i + 1][0] >= bx[i][0] + bx[i][2] + PC::ELEV_ROW }, bx)
ok('the last one and its heights inside the area', bx[3][0] + bx[3][2] + 1 * PC::ELEV_ROW + ET::ROW_GAP <= 16.5 + 1e-9, bx)

# the real road: the room's pictures onto one sheet
st = psd.load_state
st['images'] = ['/e/Other_render.png', '/e/Room_2_East_lines.png']   # an old sheet a wall
st['image_titles'] = { '/e/Room_2_East_lines.png' => 'Room 2 - East' }
st['pics'] = [{ 'path' => '/e/photo.jpg', 'on' => 'image:1' }]         # something he put on the East sheet
psd.save_state(st)
paths = %w[/e/Room_2_North_lines.png /e/Room_2_East_lines.png /e/Room_2_South_lines.png /e/Room_2_West_lines.png]
dim = [{ 'k' => 'h', 'row' => 1, 'u' => [0.1, 0.9], 'v' => 0.1, 't' => '87 1/8"' },
       { 'k' => 'v', 'col' => 1, 'v' => [0.1, 0.9], 'u' => 0.1, 't' => '96"' }]
dims = paths.each_with_object({}) { |p, h| h[p] = dim }
ET.add_room_sheet!(paths, 'Room 2', dims)
st = psd.load_state
ok('the walls\' old sheet is gone; the room has one sheet, its first wall owns it',
   st['images'] == ['/e/Other_render.png', '/e/Room_2_North_lines.png'], st['images'])
ok('the sheet is called after the room', st['image_titles']['/e/Room_2_North_lines.png'] == 'Room 2', st['image_titles'])
mine = st['pics'].select { |r| r['on'] == 'image:1' }.map { |r| r['path'] }
ok('the other three walls beside it', mine == paths[1..3], st['pics'])
ok('what was on the old East sheet went with it', st['pics'].none? { |r| r['path'] == '/e/photo.jpg' }, st['pics'])
boxes = [st['image_geo']['1']['box']] + st['pics'].select { |r| r['on'] == 'image:1' }.map { |r| r['box'] }
ok('every wall got a box', boxes.all? { |b| b.is_a?(Array) && b.size == 4 }, boxes)
ok('in a row', (0..2).all? { |i| boxes[i + 1][0] > boxes[i][0] + boxes[i][2] }, boxes)
ok('every wall keeps its dimensions', paths.all? { |p| st['image_dims'][p] == JSON.parse(dim.to_json) }, st['image_dims'].keys)

psd.instance_variable_set(:@doc, nil)
doc = psd.document
pg = doc.pages.find { |p| p.kind == 'image' && p.ref == 1 }
lay = pg.layers.find { |l| l.name == PC::ELEV_DIM_LAYER }
n96 = lay ? lay.shapes.count { |s| s[:type] == :text && s[:text] == '96"' } : 0
ok('the sheet carries the numbers of all four walls', n96 == 4, n96)
imgs = pg.layer(InteriorPro::PlanDoc::IMAGE_LAYER).shapes.select { |s| s[:type] == :image }
t96 = lay.shapes.select { |s| s[:type] == :text && s[:text] == '96"' }.map { |s| s[:x] }.sort
ok('each wall\'s height stands right of its own picture',
   imgs.sort_by { |s| s[:x] }.zip(t96).all? { |im, x| x > im[:x] + im[:w] - 1e-6 && x < im[:x] + im[:w] + 3 * PC::ELEV_ROW }, [imgs.map { |s| [s[:x], s[:w]] }, t96])

# he moves the South wall; the pictures are taken again: it stays
st = psd.load_state
j = st['pics'].index { |r| r['path'] == '/e/Room_2_South_lines.png' }
st['pics'][j]['box'] = [3.0, 2.0, 2.0, 2.2]
st['pics'][j]['auto'] = false                    # what the window writes when he moves it
st['image_geo']['1'] = { 'box' => [9.0, 2.0, 2.5, 2.7], 'rot' => 0.0, 'crop' => [0, 0, 0, 0] }   # and the first wall, as the window writes it
west0 = st['pics'].find { |r| r['path'] == '/e/Room_2_West_lines.png' }['box']
st['pics'].find { |r| r['path'] == '/e/Room_2_West_lines.png' }['box'] = [0.0, 0.0, 1.0, 1.0]   # laid here, never moved
psd.save_state(st)
ET.add_room_sheet!(paths, 'Room 2', dims)
st = psd.load_state
ok('taken again: still one sheet, nothing doubled', st['images'] == ['/e/Other_render.png', '/e/Room_2_North_lines.png'] &&
   st['pics'].count { |r| r['on'] == 'image:1' } == 3, [st['images'], st['pics']])
ok('the wall he moved stays where he put it', st['pics'].find { |r| r['path'] == '/e/Room_2_South_lines.png' }['box'] == [3.0, 2.0, 2.0, 2.2], st['pics'])
ok('the first wall he moved stays too', st['image_geo']['1']['box'] == [9.0, 2.0, 2.5, 2.7], st['image_geo'])
ok('a wall he never moved is laid again in its place in the row', st['pics'].find { |r| r['path'] == '/e/Room_2_West_lines.png' }['box'] == west0, st['pics'])
ok('the window marks a moved picture as his', File.read('./plan_sheet_dialog.rb', encoding: 'utf-8').include?('STATE.pics[nm.n].auto=false;'))

ok('switch: USE_ONE_SHEET', ET::USE_ONE_SHEET == true)
src = File.read('./elevation_tool.rb', encoding: 'utf-8')
ok('make! goes to one sheet only when switched on', src.include?('n = USE_ONE_SHEET ? add_room_sheet!(paths, title, dims) : add_to_sheet!('))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

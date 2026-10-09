# encoding: utf-8
# rt288 - Elevations: one or two numbers a thing, by the nearer wall (2026-10-08 15:57,
# after his Chief Architect sheet: "רק צריך מידה אחת או שתיים לכל דבר ... וגם לפזר את
# המידות וגם לכתוב ליד הדבר עצמו"). His Room 2: the shower set on North (13:42), the
# niche on East (12:57).
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

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
PC = InteriorPro::PlanCanvas
P = Geom::Point3d
ok('switched on', ET::USE_CLEAN_DIMS == true)
ok('to the half inch, no finer (16:33: "סליחה, רק חצי")',
   %w[87.1 45.69 48.63 78.315 21.18 30.855 0.3 0.74 96].map { |v| ET.fmt_in(v.to_f) } == ['87"', '45 1/2"', '48 1/2"', '78 1/2"', '21"', '31"', '1/2"', '1/2"', '96"'],
   %w[87.1 45.69 48.63 78.315 21.18 30.855 0.3 0.74 96].map { |v| ET.fmt_in(v.to_f) })

north = ET::Side.new('North', P.new(-443.0, 402.5, 0), P.new(-530.1, 402.5, 0), 87.1, Geom::Vector3d.new(0, -1, 0), 70.08)
items = [{ kind: 'part', a0: 21.18, a1: 21.18, z0: 78.315, z1: 78.315 },
         { kind: 'part', a0: 21.18, a1: 21.18, z0: 48.63, z1: 48.63 },
         { kind: 'part', a0: 30.855, a1: 30.855, z0: 45.69, z1: 45.69 },
         { kind: 'tile_wall', a0: 0.62, a1: 43.61, z0: 0.0, z1: 96.0 }]
d = ET.dims_for(north, 96.0, items)
under = d.select { |x| x['k'] == 'h' }
ok('under the floor only the whole wall', under.map { |x| x['t'] } == ['87"'] && under[0]['row'] == 1, under)
vs = d.select { |x| x['k'] == 'v' }
ok('the shower set is by the right wall (21" off it, 66" off the left): its heights stand on the right',
   vs.all? { |x| x['side'] == 'R' }, vs)
ok('one height a part, then the wall', vs.map { |x| x['t'] }.sort == ['45 1/2"', '48 1/2"', '78 1/2"', '96"'].sort && vs.last['t'] == '96"', vs.map { |x| x['t'] })
hi = d.select { |x| x['k'] == 'hi' }
ok('and how far it is from that wall, at the thing itself - once for the valve and the head over it', hi.map { |x| x['t'] }.sort == ['21"', '31"'], hi.map { |x| x['t'] })
ok('the valve\'s distance at the valve (the lower of the two)', (hi.find { |x| x['t'] == '21"' }['v'] - (12.0 + 48.63) / 120.0).abs < 1e-6)
ok('the hand 3" under the valve: its words go under its line (16:05)', hi.find { |x| x['t'] == '31"' }['below'] == true && !hi.find { |x| x['t'] == '21"' }['below'])
vz = ->(z) { (12.0 + z) / 120.0 }
h_hand = hi.find { |x| x['t'] == '31"' }
ok('the hand\'s distance is drawn at the hand\'s height, from the right wall to its middle',
   (h_hand['v'] - vz.call(45.69)).abs < 1e-6 && (h_hand['u'][1] - (12.0 + 87.1) / 111.1).abs < 1e-6, h_hand)
ok('the tiles get no number', d.none? { |x| x['t'] == '43"' || x['t'] == '42 15/16"' })
ok('two numbers a thing at most (one height, one distance)', d.size == 1 + 4 + 2, d.size)

# 16:13 "זה הכי מבולגן בעולם": a set made of parts gets ONE distance - to its valve
set = [{ kind: 'part', a0: 21.18, a1: 21.18, z0: 78.315, z1: 78.315, fix: 1, name: 'X_shower_set_DAWN_head' },
       { kind: 'part', a0: 21.18, a1: 21.18, z0: 48.63, z1: 48.63, fix: 1, name: 'X_shower_set_DAWN_valve' },
       { kind: 'part', a0: 30.855, a1: 30.855, z0: 45.69, z1: 45.69, fix: 1, name: 'X_shower_set_DAWN_hand' }]
ds = ET.dims_for(north, 96.0, set)
his = ds.select { |x| x['k'] == 'hi' }
ok('one distance for the whole set, to the valve, at the valve', his.size == 1 && his[0]['t'] == '21"' &&
   (his[0]['v'] - (12.0 + 48.63) / 120.0).abs < 1e-6 && !his[0]['below'], his)
ok('still one height a part', ds.count { |x| x['k'] == 'v' } == 4)
# 16:15 "המדידה הכי נמוכה צריכה להיות קרובה לבית והגבוהה רחוקה מהבית"
order = ds.select { |x| x['k'] == 'v' }.sort_by { |x| x['col'] }.map { |x| x['t'] }
ok('the columns: the lowest nearest the wall, then up, the wall\'s height farthest', order == ['45 1/2"', '48 1/2"', '78 1/2"', '96"'], order)
ok('they are numbered 1, 2, 3, 4', ds.select { |x| x['k'] == 'v' }.map { |x| x['col'] }.sort == [1, 2, 3, 4])
set2 = set.map { |x| x.merge(name: 'part') }
ok('no valve by name: the middle part (by height) carries it', ET.dims_for(north, 96.0, set2).select { |x| x['k'] == 'hi' }.map { |x| x['t'] } == ['21"'])
src = File.read('./elevation_tool.rb', encoding: 'utf-8')
ok('the parts carry their set and their name from the model', src.include?('fix: t.ent.object_id, name: names[pi].to_s'))

# the shower set stands on the North wall: from the East wall it is seen side-on, 16" in - no numbers there (16:05)
model = Sketchup.active_model
fx = model.entities.add_group
fx.set_attribute('InteriorPro', 'type', 'fixture')
k1 = fx.entities.add_group
k2 = fx.entities.add_group
def box8(x0, x1, y0, y1, z0, z1)
  [x0, x1].product([y0, y1], [z0, z1]).map { |x, y, z| P.new(x, y, z) }
end
BOXES = { fx => box8(-477.74, -459.26, 381.21, 401.88, 18.86, 81.18),
          k1 => box8(-466.87, -461.49, 398.62, 401.88, 43.88, 53.38),
          k2 => box8(-477.74, -469.97, 391.21, 401.88, 18.86, 72.52) }
ET.define_singleton_method(:world_box) { |t| BOXES[t.ent] }
th = ET::Thing.new(fx, fx.transformation, 'fixture')
eastw = ET::Side.new('East', P.new(-443.0, 332.42, 0), P.new(-443.0, 402.5, 0), 70.08, Geom::Vector3d.new(-1, 0, 0), 87.1)
ok('on the North wall it is measured', ET.side_items(north, 48.0, [th], 0.0).size == 2)

# 16:25 "מספרים שלמים כמו המידות שאני מכניס בגבהים בכלי": the numbers he typed, off the fixture and its wall
require './tile_wall'
require './fixture_library'
nw = model.entities.add_group
nw.set_attribute('InteriorPro', 'type', 'wall')
nw.set_attribute('InteriorPro', 'id', 'w-north')
# the North wall of Room 2: 5" thick, centred on y = 405, run east -> west so its left ('a') looks south, into the room
{ 'start_x' => -440.5, 'start_y' => 405.0, 'end_x' => -532.6, 'end_y' => 405.0, 'thickness' => 5.0, 'height' => 96.0 }.each { |k, v| nw.set_attribute('InteriorPro', k, v) }
def nw.bounds; Struct.new(:min, :max).new(P.new(-532.6, 402.5, 0.0), P.new(-440.5, 407.5, 96.0)); end
fx.set_attribute('InteriorPro', 'host_wall_id', 'w-north')
fx.set_attribute('InteriorPro', 'side', 'a')
fx.set_attribute('InteriorPro', 'u_in', 23.5)
cfgp = { 'head' => { 'on' => true, 'h' => 80, 'side' => 0 }, 'valve' => { 'on' => true, 'h' => 48, 'side' => 0 },
         'hand' => { 'on' => true, 'h' => 60, 'side' => 12 }, 'spout' => { 'on' => false, 'h' => 22, 'side' => 0 } }
fx.set_attribute('InteriorPro', 'cfg_json', JSON.generate('kind' => 'shower_set', 'parts' => cfgp))
wth = ET::Thing.new(nw, nw.transformation, 'wall')
fr = InteriorPro::TileWall.frame_for(nw, 'a')
ok('the wall\'s face looks into the room', fr && (fr[:ny] - -1.0).abs < 1e-9, fr)
typed = ET.side_items(north, 48.0, [th, wth], 0.0)
ok('three parts, the spout (off) not among them', typed.size == 3 && typed.map { |x| x[:name] }.sort == %w[hand head valve], typed)
ok('at the heights he typed: 80, 48, 60 - whole numbers', typed.map { |x| [x[:name], x[:z1]] }.sort == [['hand', 60.0], ['head', 80.0], ['valve', 48.0]], typed)
dir = Geom::Vector3d.new(-1, 0, 0)
al = ->(p) { (p.x - north.a.x) * dir.x + (p.y - north.a.y) * dir.y }
pv = P.new(*InteriorPro::TileWall.world(fr, 23.5, 48.0))
ph = P.new(*InteriorPro::TileWall.world(fr, 35.5, 60.0))
ok('along the wall at his line (u_in), the hand 12" to the side', (typed.find { |x| x[:name] == 'valve' }[:a0] - al.call(pv)).abs < 1e-6 &&
   (typed.find { |x| x[:name] == 'hand' }[:a0] - al.call(ph)).abs < 1e-6, typed)
ok('the valve and the head on one line', typed.find { |x| x[:name] == 'valve' }[:a0] == typed.find { |x| x[:name] == 'head' }[:a0])
dd = ET.dims_for(north, 96.0, typed)
ok('so the sheet says 48", 60", 80" and 96"', dd.select { |x| x['k'] == 'v' }.sort_by { |x| x['col'] }.map { |x| x['t'] } == ['48"', '60"', '80"', '96"'], dd.select { |x| x['k'] == 'v' })
fx.set_attribute('InteriorPro', 'host_wall_id', 'no-such-wall')
back = ET.side_items(north, 48.0, [th, wth], 0.0).map { |x| x[:z1].round(2) }.sort
ok('its wall not found: the boxes\' middles, as before', back == [45.69, 48.63], back)
ok('on the East wall it is not', ET.side_items(eastw, 48.0, [th], 0.0).empty?, ET.side_items(eastw, 48.0, [th], 0.0))

east = ET::Side.new('East', P.new(-443.0, 332.42, 0), P.new(-443.0, 402.5, 0), 70.08, Geom::Vector3d.new(-1, 0, 0), 87.1)
de = ET.dims_for(east, 96.0, [{ kind: 'niche', a0: 17.1, a1: 53.1, z0: 42.0, z1: 60.0 }])
lv = de.select { |x| x['k'] == 'v' && x['side'] == 'L' }
ok('the niche is nearer the picture\'s LEFT wall: its heights stand on the left', lv.map { |x| x['t'] } == ['42"', '18"'], de)
nh = de.select { |x| x['k'] == 'hi' }
ok('its width just under it, and how far it is from that wall', nh.map { |x| x['t'] }.sort == ['17"', '36"'] &&
   nh.all? { |x| (x['v'] - vz.call(36.0)).abs < 1e-6 && (x['from'] - vz.call(42.0)).abs < 1e-6 }, nh)
ok('the wall\'s height on the right', de.find { |x| x['t'] == '96"' }['side'] == 'R')

# a tub (one part) keeps its width under the floor and gets one height
dt = ET.dims_for(north, 96.0, [{ kind: 'fixture', a0: 0.0, a1: 30.62, z0: 0.0, z1: 18.19 }])
ok('a tub: its width in the chain under the floor, the whole wall under that, one height',
   dt.select { |x| x['k'] == 'h' && x['row'] == 1 }.map { |x| x['t'] } == ['56 1/2"', '30 1/2"'] &&
   dt.any? { |x| x['row'] == 2 && x['t'] == '87"' } && dt.count { |x| x['k'] == 'v' } == 2, dt)

# drawn: a picture 11.11 x 12 paper inches
lay = Object.new
def lay.lines; @lines ||= []; end
def lay.texts; @texts ||= []; end
def lay.line(x1, y1, x2, y2, *_); lines << [x1, y1, x2, y2]; end
def lay.text(w, x, y, o = {}); texts << [w, x, y, o]; end
main = { x: 2.0, y: 0.0, w: 11.11, h: 12.0, placed: true, rot: 0.0 }
de.each { |x| PC.draw_elev_dim(lay, main, x) }
t42 = lay.texts.find { |t| t[0] == '42"' }
ok('a left column is drawn left of the picture', t42 && t42[1] < 2.0, t42)
t96 = lay.texts.find { |t| t[0] == '96"' }
ok('the wall\'s height right of it', t96 && t96[1] > 13.11, t96)
t36 = lay.texts.find { |t| t[0] == '36"' }
ok('the niche\'s width is inside the picture, just under the niche', t36 && t36[1] > 2.0 && t36[1] < 13.11 &&
   t36[2] < (12.0 + 42.0) * 0.1 && t36[2] > (12.0 + 30.0) * 0.1, t36)

# room for the columns on both sides when the walls stand in a row
bx = ET.row_boxes([0.5, 1.5, 16.0, 9.0], [[1333, 1440], [1129, 1440]], [[0, 4], [2, 1]])
ok('the first picture starts past nothing on its left; the second leaves room for its two left columns and the first one\'s four right',
   bx[1][0] - (bx[0][0] + bx[0][2]) >= 6 * PC::ELEV_ROW - 1e-9 && (bx[0][0] - 0.5).abs < 1e-9, bx)

ET.send(:remove_const, :USE_CLEAN_DIMS)
ET.const_set(:USE_CLEAN_DIMS, false)
ok('switched off: the long chain again', ET.dims_for(north, 96.0, items).any? { |x| x['k'] == 'h' && x['row'] == 2 })

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

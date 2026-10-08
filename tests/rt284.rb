# encoding: utf-8
# rt284 - Elevations, step 1 (2026-10-08).
#
# Four elevations of a room, one per wall, taken off the model with a
# parallel camera and a section plane `cut` inches from the wall, and put on
# the Sheet window as picture sheets. The stub has no camera and no section
# plane, so the SHOT itself is measured only on his machine
# (elevation_trace.txt); here: the room's outline is read in the world (not
# shifted by the room group a second time - the bug of 10:25), the sides,
# the way in, the depth, where the eye and the plane stand, the file names,
# and that the pictures land in st['images'] once each.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
require 'tmpdir'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map do |o|
        { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f }
      end
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
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

ET = InteriorPro::ElevationTool
ok('the switch is there and on', ET.const_defined?(:USE_ELEVATIONS) && ET::USE_ELEVATIONS == true)

model = Sketchup.active_model
# the house in one plain group, the room inside it - as his model stands
house = model.entities.add_group
house.name = 'house'
room = house.entities.add_group
room.set_attribute('InteriorPro', 'type', 'room')
room.set_attribute('InteriorPro', 'name', 'Bath 1')
room.set_attribute('InteriorPro', 'number', 2)
# his Room 2: 87" by 70", written in the container's coordinates, clockwise
room.set_attribute('InteriorPro', 'boundary_xy', [-443.0, 332.4, -443.0, 402.5, -530.1, 402.5, -530.1, 332.4])
# the group itself sits at the room's middle, as room_manager leaves it
room.transformation = Geom::Transformation.new(Geom::Point3d.new(-486.55, 367.46, 0.25))
wall = house.entities.add_group
wall.set_attribute('InteriorPro', 'type', 'wall')
wall.set_attribute('InteriorPro', 'id', 'w1')
wall.set_attribute('InteriorPro', 'height', 96.0)
room.set_attribute('InteriorPro', 'bounding_wall_ids', ['w1'])

rooms = ET.rooms(model)
ok('the room inside the house group is found', rooms.size == 1 && ET.room_name(rooms[0]) == 'Bath 1', rooms.map { |r| ET.room_name(r) })
poly = ET.room_poly(rooms[0])
ok('the outline is read in the world, not shifted by the group again',
   poly && (poly[0].x - -443.0).abs < 0.01 && (poly[0].y - 332.4).abs < 0.01, poly && poly.map { |p| [p.x.round(1), p.y.round(1)] })
ok('the height comes from the bounding wall', ET.room_height(rooms[0], model) == 96.0)

sides = ET.sides(poly)
ok('four sides, named the way they face: East North West South', sides.map(&:name) == %w[East North West South], sides.map(&:name))
a = sides[0]
ok('the East wall is 70.1"', (a.len - 70.1).abs < 0.05, a.len)
ok('looking at the East wall = looking east, in is west', a.inward.x < -0.99 && a.inward.y.abs < 0.01, a.inward.to_a)
ok('the room is 87.1" deep behind the East wall', (a.depth - 87.1).abs < 0.05, a.depth)
ok('a wall facing north-east is NorthEast; one 10 degrees off east is East',
   ET.compass(Geom::Vector3d.new(1, 1, 0)) == 'NorthEast' && ET.compass(Geom::Vector3d.new(0.985, 0.174, 0)) == 'East')
lpoly = [[0, 0], [100, 0], [100, 50], [60, 50], [60, 100], [0, 100]].map { |x, y| Geom::Point3d.new(x, y, 0) }
ok('an L-shaped room: the two walls that face the same way are numbered',
   ET.sides(lpoly).map(&:name) == %w[South East North East2 North2 West], ET.sides(lpoly).map(&:name))
b = sides[1]
ok('the North wall is 87.1", in = south', (b.len - 87.1).abs < 0.05 && b.inward.y < -0.99, [b.len, b.inward.to_a])

# the shot: whole room = plane half an inch inside the far wall, eye half an inch before it
s = ET.shot(a, 96.0, nil, 0.25)
ok('whole room: cut is the depth less half an inch', (s[:cut] - 86.6).abs < 0.05, s[:cut])
ok('the plane stands cut inches into the room from the wall', (s[:plane_pt].x - (-443.0 - 86.6)).abs < 0.05, s[:plane_pt].x)
ok('the eye stands inside the room, half an inch before the plane', (s[:eye].x - (-443.0 - 86.1)).abs < 0.05, s[:eye].x)
ok('the normal points at the wall, away from the eye', s[:normal].x > 0.99, s[:normal].to_a)
ok('the target is the middle of the wall at half height', (s[:target].y - 367.45).abs < 0.05 && (s[:target].z - 48.25).abs < 0.01, s[:target].to_a)
ok('the picture holds the wall and 12" of air', s[:height] == 120.0 && s[:h_px] == 1440 && s[:w_px] == ((70.1 + 24) * 12).round, [s[:height], s[:w_px], s[:h_px]])
s24 = ET.shot(a, 96.0, 24.0, 0.25)
ok('24" asked = 24" cut', s24[:cut] == 24.0 && (s24[:plane_pt].x - -467.0).abs < 0.01, [s24[:cut], s24[:plane_pt].x])
sbig = ET.shot(a, 96.0, 500.0, 0.25)
ok('more than the room = the whole room', (sbig[:cut] - 86.6).abs < 0.05, sbig[:cut])
wide = ET::Side.new('North', Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(600, 0, 0), 600.0, Geom::Vector3d.new(0, 1, 0), 200.0)
sw = ET.shot(wide, 96.0, nil, 0)
ok('a 50 ft wall is capped at MAX_PX wide and keeps its shape', sw[:w_px] == ET::MAX_PX && (sw[:h_px] - ET::MAX_PX * 120.0 / 624.0).abs < 1, [sw[:w_px], sw[:h_px]])

# names
ok('file name = room_side_style.png', ET.file_for('/x', 'Bath 1', 'A', 'lines') == '/x/Bath_1_A_lines.png', ET.file_for('/x', 'Bath 1', 'A', 'lines'))
ok('a Hebrew room name keeps its letters', ET.slug('חדר רחצה') == 'חדר_רחצה', ET.slug('חדר רחצה'))

# onto the sheet: once each, in order, after what was there
psd = InteriorPro::PlanSheetDialog
st = psd.load_state
st['images'] = ['/renders/old.png']
psd.save_state(st)
n = ET.add_to_sheet!(['/e/Bath_1_A_lines.png', '/e/Bath_1_B_lines.png'])
st = psd.load_state
ok('two pictures went on, after the old one', n == 2 && st['images'] == ['/renders/old.png', '/e/Bath_1_A_lines.png', '/e/Bath_1_B_lines.png'], st['images'])
ET.add_to_sheet!(['/e/Bath_1_A_lines.png'])
st = psd.load_state
ok('made again = the same sheet, not a second one', st['images'].count('/e/Bath_1_A_lines.png') == 1 && st['images'].size == 3, st['images'])
ok('nothing to add = nothing changed', ET.add_to_sheet!([]) == 0)

# the files land beside the model
model.path = 'C:/jobs/6 Bronco/6 Bronco Ln.skp'
ok('pictures go to <model folder>/InteriorPro_sheet/elevations', ET.out_dir(model) == 'C:/jobs/6 Bronco/InteriorPro_sheet/elevations', ET.out_dir(model))

# ---- several rooms, the wet one first, each sheet named (2026-10-08, 11:38)
dry = house.entities.add_group
dry.set_attribute('InteriorPro', 'type', 'room')
dry.set_attribute('InteriorPro', 'name', 'Hall')
dry.set_attribute('InteriorPro', 'boundary_xy', [0.0, 0.0, 100.0, 0.0, 100.0, 80.0, 0.0, 80.0])
# a shower floor standing in Bath 1: a group whose body sits at the room's middle
fx = house.entities.add_group
fx.set_attribute('InteriorPro', 'type', 'shower_floor')
# the real API answers bounds in the parent's coordinates; the stub's box is empty,
# so the body is said to stand at the room's middle
def fx.bounds; Sketchup::BBox.new(Geom::Point3d.new(-486.0, 367.0, 9.0)); end
rooms = ET.rooms(model)
ok('the room with plumbing stands first in the list', rooms.map { |r| ET.room_name(r) } == ['Bath 1', 'Hall'], rooms.map { |r| ET.room_name(r) })
ok('wet_count says how many are ticked by default', ET.wet_count(rooms, model) == 1, ET.wet_count(rooms, model))
titles = ET.titles_for(rooms[0], ['/e/Bath_1_North_lines.png', '/e/Bath_1_North2_lines.png'])
ok('a sheet is named room - side', titles == { '/e/Bath_1_North_lines.png' => 'Bath 1 - North', '/e/Bath_1_North2_lines.png' => 'Bath 1 - North2' }, titles)
ET.add_to_sheet!(['/e/Bath_1_North_lines.png', '/e/Bath_1_North2_lines.png'], titles)
st = psd.load_state
ok('the names survive save_state', st['image_titles'] == titles, st['image_titles'])
st['images'] = st['images'] - ['/e/Bath_1_North2_lines.png']
psd.save_state(st)
ET.add_to_sheet!(['/e/Hall_North_lines.png'], { '/e/Hall_North_lines.png' => 'Hall - North' })
st = psd.load_state
ok('a picture that left takes its name with it', st['image_titles'].keys.sort == ['/e/Bath_1_North_lines.png', '/e/Hall_North_lines.png'], st['image_titles'].keys)
# the sheet carries the name: plan_canvas names the page and the title block by it
st = psd.load_state
st['images'] = ['/renders/old.png', '/e/Bath_1_A_lines.png']
st['image_titles'] = { '/e/Bath_1_A_lines.png' => 'Bath 1 - A' }
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
doc = psd.document
imgs = doc.pages.select { |pg| pg.kind == 'image' }
ok('the render keeps RENDERING 1, the elevation sheet is Bath 1 - A', imgs.map(&:name) == ['RENDERING 1', 'Bath 1 - A'], imgs.map(&:name))
ok('the title block of that sheet says Bath 1 - A', imgs[1].layers.any? { |l| l.shapes.any? { |sh| sh.inspect.include?('Bath 1 - A') } })
ok('and not RENDERING', imgs[1].layers.none? { |l| l.shapes.any? { |sh| sh.inspect.include?('RENDERING') } })
# several rooms in one go: make_all! walks them in order (the shot is stubbed here)
class << ET
  alias_method :real_shoot!, :shoot!
  def shoot!(room, cut: nil, style: 'lines', model: nil)
    ['A', 'B'].map { |sd| "/e/#{slug(room_name(room))}_#{sd}_#{style}.png" }
  end
end
got = ET.make_all!(rooms, cut: 24, style: 'lines')
ok('two rooms = four pictures, the wet room first', got == %w[/e/Bath_1_A_lines.png /e/Bath_1_B_lines.png /e/Hall_A_lines.png /e/Hall_B_lines.png], got)
st = psd.load_state
# since 14:00 (USE_ONE_SHEET): a room is ONE sheet named after it, its other walls beside the first (rt287)
ok('one sheet a room, named after it, the other wall beside it',
   st['image_titles']['/e/Bath_1_A_lines.png'] == 'Bath 1' && st['image_titles']['/e/Hall_A_lines.png'] == 'Hall' &&
   st['images'].last == '/e/Hall_A_lines.png' && !st['images'].include?('/e/Hall_B_lines.png') &&
   st['pics'].any? { |r| r['path'] == '/e/Hall_B_lines.png' && r['on'] == "image:#{st['images'].index('/e/Hall_A_lines.png')}" }, [st['images'], st['image_titles'], st['pics']])
ET.send(:remove_const, :USE_ONE_SHEET)
ET.const_set(:USE_ONE_SHEET, false)
ET.make_all!(rooms, cut: 24, style: 'lines')
st = psd.load_state
ok('switched off: all four are on the sheet with their names, one sheet a wall', st['image_titles']['/e/Hall_B_lines.png'] == 'Hall - B' && st['images'].last == '/e/Hall_B_lines.png', st['image_titles'])
ET.send(:remove_const, :USE_ONE_SHEET)
ET.const_set(:USE_ONE_SHEET, true)

# ---- the distance: one for the house, one for a room, one for a wall (2026-10-08, 11:59)
h = { 'house' => '60', 'room' => '', 'walls' => { 'A' => '12' } }
ok('the wall\'s own number wins', ET.cut_for(h, 'A') == 12.0, ET.cut_for(h, 'A'))
ok('no number for the wall = the room\'s, none = the house\'s', ET.cut_for(h, 'B') == 60.0, ET.cut_for(h, 'B'))
ok('the room\'s number beats the house\'s', ET.cut_for({ 'house' => '60', 'room' => '24' }, 'B') == 24.0)
ok('nothing anywhere = the whole room (nil)', ET.cut_for({ 'house' => '', 'room' => nil }, 'A').nil?)
ok('a plain number still works', ET.cut_for(24, 'A') == 24)
seen = []
class << ET
  def shoot!(room, cut: nil, style: 'lines', model: nil)
    $seen_cuts << [room_name(room), cut]
    ["/e/#{slug(room_name(room))}_A_#{style}.png"]
  end
end
$seen_cuts = []
ET.make_all!(rooms, cut: [{ 'house' => '60', 'room' => '24' }, { 'house' => '60' }], style: 'lines')
ok('each room gets its own cuts, in order', $seen_cuts == [['Bath 1', { 'house' => '60', 'room' => '24' }], ['Hall', { 'house' => '60' }]], $seen_cuts)

# the floor, the ceiling and the roof are put aside for the shot - a line, not a slab (12:08)
ok('floor, ceiling, roof, the room\'s name lying on the floor are set aside', %w[floor floor_pattern ceiling roof foundation shower_floor shower_pattern shower_curb room].all? { |t| ET.set_aside?(t) })
ok('walls, tile, plumbing, the shower pan, doors and windows stay', %w[wall tile_wall tile_niche fixture door window].none? { |t| ET.set_aside?(t) })
# a reload reads the list again (12:33, measured on his model: the list loaded was the first one,
# without shower_*, so the shower pan stayed in the picture as a dark strip under the tiles)
ET.send(:remove_const, :SET_ASIDE)
ET.const_set(:SET_ASIDE, %w[floor ceiling].freeze)
$VERBOSE = nil
load './elevation_tool.rb'
ok('a reload reads SET_ASIDE again (the shower pan is set aside after reload)', ET.set_aside?('shower_floor') && ET.set_aside?('shower_curb'), ET::SET_ASIDE)
puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

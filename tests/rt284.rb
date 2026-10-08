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
ok('four sides, A to D', sides.map(&:name) == %w[A B C D], sides.map(&:name))
a = sides[0]
ok('side A is the 70.1" east wall', (a.len - 70.1).abs < 0.05, a.len)
ok('side A looks INTO the room (west)', a.inward.x < -0.99 && a.inward.y.abs < 0.01, a.inward.to_a)
ok('the room is 87.1" deep behind side A', (a.depth - 87.1).abs < 0.05, a.depth)
b = sides[1]
ok('side B is the 87.1" north wall, in = south', (b.len - 87.1).abs < 0.05 && b.inward.y < -0.99, [b.len, b.inward.to_a])

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
wide = ET::Side.new('A', Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(600, 0, 0), 600.0, Geom::Vector3d.new(0, 1, 0), 200.0)
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

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

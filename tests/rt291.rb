# encoding: utf-8
# rt291 - Elevations: each wall's picture gets its lines as numbers beside it, so the sheet's tools
# can lock onto corners and line ends (2026-10-08 19:19; measured 19:21, debug_elev_snaps.rb).
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
require './plan_sheet_dialog'
require './tile_niche'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
P = Geom::Point3d
ok('the switch is on', ET::USE_ELEV_SNAPS == true)
ok('the lines sit beside the picture', ET.snaps_file('C:/a/Room_2_North_lines.png') == 'C:/a/Room_2_North_lines.snaps.json')

# his Room 2: 87.1 x 70.08; the North wall - looked at from inside, side.a on the right
poly = [P.new(-530.1, 332.42, 0), P.new(-443.0, 332.42, 0), P.new(-443.0, 402.5, 0), P.new(-530.1, 402.5, 0)]
north = ET.sides(poly).find { |sd| sd.name == 'North' }
ok('the North wall is found', north && (north.len - 87.1).abs < 1e-6, ET.sides(poly).map(&:name))
len = north.len
pw = len + 2 * ET::MARGIN
ph = 96.0 + 2 * ET::MARGIN
# a valve plate 12" off the wall's line, an edge of it up the middle of the wall, 40..52 high
mid_x = (north.a.x + north.b.x) / 2.0
on_wall = [P.new(mid_x, 402.5 - 1.0, 40.0), P.new(mid_x, 402.5 - 1.0, 52.0)]
behind = [P.new(mid_x, 402.5 + 3.0, 40.0), P.new(mid_x, 402.5 + 3.0, 52.0)]       # inside the wall
past_cut = [P.new(mid_x, 402.5 - 60.0, 40.0), P.new(mid_x, 402.5 - 60.0, 52.0)]   # 60" into the room
end_on = [P.new(mid_x, 402.5 - 1.0, 40.0), P.new(mid_x, 402.5 - 5.0, 40.0)]       # pointing at the eye
segs = ET.side_segs(north, 48.0, 96.0, 0.0, [on_wall, behind, past_cut, end_on])
ok('only the edge in front of the wall, within the cut, not one seen end-on', segs.size == 1, segs)
u1, v1, u2, v2 = segs.first
ok('laid on the picture the way dims_for lays it: the middle of the wall at u 0.5', (u1 - 0.5).abs < 1e-4 && (u2 - 0.5).abs < 1e-4, segs)
ok('its heights from the floor, with the margin', (v1 - (ET::MARGIN + 40.0) / ph).abs < 1e-4 && (v2 - (ET::MARGIN + 52.0) / ph).abs < 1e-4, segs)
a_pt = [P.new(north.b.x, 402.5 - 1.0, 0.0), P.new(north.b.x, 402.5 - 1.0, 96.0)]
s2 = ET.side_segs(north, 48.0, 96.0, 0.0, [a_pt]).first
ok('side.b stands on the LEFT of the picture (the margin)', s2 && (s2[0] - ET::MARGIN / pw).abs < 1e-4, s2)
ok('on a second floor the heights are from that floor',
   (ET.side_segs(north, 48.0, 96.0, 120.0, [on_wall.map { |p| P.new(p.x, p.y, p.z + 120.0) }]).first[1] - v1).abs < 1e-9)
ok('the same edge twice is one line', ET.side_segs(north, 48.0, 96.0, 0.0, [on_wall, on_wall]).size == 1)

src = File.read('./elevation_tool.rb', encoding: 'utf-8')
ok('written after each wall\'s picture, only with the switch on, and it says how many in the trace',
   src.include?('if USE_ELEV_SNAPS') && src.include?('File.write(snaps_file(path), JSON.generate(\'segs\' => kept, ') &&
   src.include?('snaps #{kept.size} of #{segs.size} lines kept'))
ok('the model\'s edges are walked once a room, not once a wall', src.include?('snap_edges ||= model_edges(model.entities)') && src.include?("snap_edges = nil\n"))
ok('a hidden or soft edge, or one on a tag that is off, is no line', src.include?('next if e.hidden? || e.soft? || !e.layer.visible?'))
ok('only the lines the picture shows are kept (a dark pixel near five points of it)', src.include?('kept = segs.select { |sg| score.call(sg, down) >= need }'))
ok('a failure says so in the trace and the pictures go on', src.include?('snaps NOT written - '))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

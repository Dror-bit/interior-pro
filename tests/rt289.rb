# encoding: utf-8
# rt289 - Elevations: the room seen from above, first on the room's sheet (2026-10-08 16:10,
# the next of his list; the sheet he okayed at 14:00 had it on the left of the walls).
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
# his Room 2: 87.1 x 70.08, at x -530.1..-443, y 332.42..402.5
poly = [P.new(-530.1, 332.42, 0), P.new(-443.0, 332.42, 0), P.new(-443.0, 402.5, 0), P.new(-530.1, 402.5, 0)]
s = ET.top_shot(poly, 0.0, 96.0)
ok('the eye over the middle of the room, under the cut, looking straight down',
   (s[:eye].x - -486.55).abs < 1e-6 && (s[:eye].y - 367.46).abs < 1e-6 && (s[:eye].z - 95.0).abs < 1e-6 &&
   (s[:target].z - 0.0).abs < 1e-6 && s[:target].x == s[:eye].x, s)
ok('north up the picture', s[:up].y == 1 && s[:up].x == 0)
ok('the plane just under the ceiling keeps everything in the room (16:27)', (s[:plane_pt].z - 95.5).abs < 1e-6 && s[:normal].z == -1, s)
ok('no room height given: 48" as a plan', (ET.top_shot(poly, 0.0)[:plane_pt].z - 48.0).abs < 1e-6)
ok('12 px an inch, a foot of air round it - the walls\' scale', s[:w_px] == ((87.1 + 24) * 12).round && s[:h_px] == ((70.08 + 24) * 12).round, [s[:w_px], s[:h_px]])
ok('the camera sees the room and its air', (s[:height] - 94.08).abs < 1e-6)
ok('on a second floor it stands on that floor', (ET.top_shot(poly.map { |p| P.new(p.x, p.y, 120.0) }, 120.0, 96.0)[:plane_pt].z - 215.5).abs < 1e-6)
ok('the shot is taken at the room\'s height', File.read('./elevation_tool.rb', encoding: 'utf-8').include?('s = top_shot(poly, base_z, wall_h)'))

src = File.read('./elevation_tool.rb', encoding: 'utf-8')
ok('the shot is taken only with both switches on, and goes FIRST', src.include?('if USE_TOP_VIEW && USE_ONE_SHEET') && src.include?('paths.unshift(path) if ok'))
ok('the walls\' floor/ceiling lines are taken away before it', src.include?('model.entities.erase_entities(gone) unless gone.empty?'))
ok('the tile lines of the floor and the pan (soft, hidden edges - 16:39) are shown for the shot',
   src.include?("next unless %w[floor_pattern shower_pattern].include?(t.type)") && src.include?('ed.hidden = false if ed.hidden?') &&
   src.include?('ed.soft = false if ed.soft?') && src.include?('ed.smooth = false if ed.smooth?'))
ok('the walls alone are cut at 48" inside their own groups, so the door and the window show (18:01)',
   src.include?('wsp = t.ent.entities.add_section_plane([lp, ln])') &&
   src.include?('base_z + PLAN_CUT).transform(inv)'))
ok('the plan\'s own door and window symbols (leaf, swing, jambs) are drawn under the cut for the shot (18:04)',
   src.include?('pg.send(:draw_door_symbols, sym.entities, d,') &&
   src.include?('base_z + PLAN_CUT - 0.5 - pg::PLAN_Z'))
ok('the doors are put away; a window is cut with its wall and gets no symbol (18:18)',
   src.include?("next unless t.type == 'door' && t.ent.respond_to?(:hidden=) && !t.ent.hidden?") &&
   src.include?("next unless %w[wall window].include?(t.type) && t.ent.respond_to?(:entities)") &&
   !src.include?('draw_window_symbols, sym.entities') && !src.include?('window_frames('))
ok('a white face under each swing, from the same hinge and sweep as the arc', src.include?('swing_faces(pg, sym.entities, d, mine)') &&
   src.include?("f.material = white"))
ok('from above the floor, the shower pan, its drain and curb are back; only what is over the room stays aside (16:14)',
   ET::TOP_ASIDE == %w[ceiling roof dormer skylight downspout plan2d sketch2d room] &&
   src.include?("hidden.each { |e| e.hidden = false if e.valid? && !TOP_ASIDE.include?(e.get_attribute(D, 'type').to_s) }"))

# onto the sheet: the view from above owns it and stands first in the row
psd = InteriorPro::PlanSheetDialog
st = psd.load_state
st['images'] = ['/e/Room_2_East_lines.png']
st['pics'] = %w[North South West].map { |w| { 'path' => "/e/Room_2_#{w}_lines.png", 'on' => 'image:0', 'box' => [1, 1, 1, 1], 'auto' => true } }
psd.save_state(st)
paths = %w[/e/Room_2_Plan_lines.png /e/Room_2_East_lines.png /e/Room_2_North_lines.png /e/Room_2_West_lines.png /e/Room_2_South_lines.png]
ET.add_room_sheet!(paths, 'Room 2', {})
st = psd.load_state
ok('the view from above owns the room\'s sheet now; the old one went', st['images'] == ['/e/Room_2_Plan_lines.png'], st['images'])
ok('the four walls beside it, nothing doubled', st['pics'].map { |r| [r['path'], r['on']] }.sort == paths[1..4].map { |p| [p, 'image:0'] }.sort, st['pics'])
b0 = st['image_geo']['0']['box']
ok('it stands first, left of every wall', st['pics'].all? { |r| r['box'][0] > b0[0] + b0[2] }, [b0, st['pics'].map { |r| r['box'] }])

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

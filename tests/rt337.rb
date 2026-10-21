# encoding: utf-8
# rt337 - a wall that ends up between two rooms turns interior - only the
#         stretch that has a room on both sides - and back (wall_inside.rb,
#         wall_tool.rb tee_at_existing_corner!, 2026-10-20).
#
# His picture (13:46): Room 3 added on the outside of the house's left wall.
# Blue = the part of the left wall between Room 1 and Room 3 -> interior.
# Green = the new outside walls, making a real corner with what stays
# exterior. His exact numbers from wall_inside_report.txt.
require './sketchup_stub'
%i[WallTool WallSplitTool RoomManager WallInside].each { |c| InteriorPro.send(:remove_const, c) if InteriorPro.const_defined?(c, false) }
require './arc_math'
require './wall_tool'
require './wall_split_tool'
require './room_manager'
require './wall_inside'

# the stub has no attribute_dictionary; split_wall! reads the wall's whole dictionary
class Sketchup::Group
  def attribute_dictionary(name)
    h = (instance_variable_get(:@attrs) || {})[name]
    return nil unless h
    d = Object.new
    d.define_singleton_method(:to_h) { h.dup }
    d.define_singleton_method(:keys) { h.keys }
    d
  end
end unless Sketchup::Group.method_defined?(:attribute_dictionary)

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
WT = InteriorPro::WallTool
WI = InteriorPro::WallInside

def wall(m, s, e, id, th: 5.0, cat: 'exterior')
  g = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1], 'end_x' => e[0], 'end_y' => e[1],
    'thickness' => th, 'height' => 96.0, 'anchor' => 'bottom-left', 'wall_category' => cat, 'level' => 1,
    'exterior_material' => 'Stucco', 'interior_material' => '#ffffff', 'side_a_color' => '#ffffff', 'side_b_color' => '#ffffff' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  t = WT.new
  d = t.wall_data(g)
  t.save_corners_attr(g, t.perpendicular_corners_xy(Geom::Point3d.new(s[0], s[1], 0), Geom::Point3d.new(e[0], e[1], 0), d[:thickness], d[:h_anchor]))
  g
end
def cs(g); g.get_attribute('InteriorPro', 'corners_xy').each_slice(2).map { |x, y| [x.round(2), y.round(2)] }; end
def has?(g, pts); c = cs(g); pts.all? { |p| c.any? { |q| (q[0] - p[0]).abs < 0.02 && (q[1] - p[1]).abs < 0.02 } }; end
def walls(m); m.entities.to_a.select { |g| g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' }; end
def by_end(m, x, y); walls(m).find { |w| [[w.get_attribute('InteriorPro', 'start_x'), w.get_attribute('InteriorPro', 'start_y')], [w.get_attribute('InteriorPro', 'end_x'), w.get_attribute('InteriorPro', 'end_y')]].any? { |p| (p[0].to_f - x).abs < 0.01 && (p[1].to_f - y).abs < 0.01 } && yield(w) }; end
def detect; InteriorPro::RoomManager.detect_rooms!(verbose: false, level: 1); end

Sketchup.reset_model!
m = Sketchup.active_model
house = [wall(m, [-702, 407.5], [-702, 183], 'c8a403d4'), wall(m, [-702, 183], [-438, 183], '045fe78b'),
         wall(m, [-438, 183], [-438, 407.5], '6269165a'), wall(m, [-438, 407.5], [-702, 407.5], '3b85b93f')]
house.each { |w| WT.new.join_corners(w, m) }
ok('the house alone: one room', detect.size == 1, detect.size)
ok('the house alone: nothing turns interior', !WI.update!(detect, m))
ok('...and no wall was cut', walls(m).size == 4)

# Room 3, his three walls (2D, 13:36)
new3 = [wall(m, [-702, 256.4], [-770, 256.4], '396e3a97'), wall(m, [-770, 256.4], [-770, 183], 'c75cfac3'), wall(m, [-770, 183], [-702, 183], '691a9bd7')]
new3.each { |w| WT.new.join_corners(w, m) }
ok('two rooms now', detect.size == 2, detect.size)
ok('update! changes something', WI.update!(detect, m))
ws = walls(m)
ok('the left wall is cut in two: 8 walls', ws.size == 8, ws.size)
up = ws.find { |w| w.get_attribute('InteriorPro', 'id') == 'c8a403d4A' }
lo = ws.find { |w| w.get_attribute('InteriorPro', 'id') == 'c8a403d4B' }
ok('the cut is at the new wall end: upper piece ends at y=256.4', up && up.get_attribute('InteriorPro', 'end_y').to_f.round(1) == 256.4, up && up.get_attribute('InteriorPro', 'end_y'))
ok('upper piece stays EXTERIOR (blue in his picture is only the lower part)', up && up.get_attribute('InteriorPro', 'wall_category') == 'exterior')
ok('lower piece (between Room 1 and Room 3) is INTERIOR', lo && lo.get_attribute('InteriorPro', 'wall_category') == 'interior')
ok('...and marked as turned by the plugin', lo && lo.get_attribute('InteriorPro', 'auto_interior') == true)
top = ws.find { |w| w.get_attribute('InteriorPro', 'id') == '396e3a97' }
ok('upper piece + Room 3 top wall: a real mitered corner (-702,256.4 / -697,251.4)',
   has?(up, [[-702, 256.4], [-697, 251.4]]) && has?(top, [[-702, 256.4], [-697, 251.4]]), [cs(up), cs(top)])
ok('lower piece stops at the top wall face (y=251.4) and on the bottom line (y=188)',
   has?(lo, [[-702, 251.4], [-697, 251.4], [-702, 188], [-697, 188]]), cs(lo))
ok('same thickness, same line - nothing moved', lo.get_attribute('InteriorPro', 'thickness').to_f == 5.0 && lo.get_attribute('InteriorPro', 'start_x').to_f == -702.0)
ok('running it again changes nothing', !WI.update!(detect, m))
ok('...still 8 walls', walls(m).size == 8)

# Room 3 deleted again -> the lower piece is an outside wall again
new3.each { |w| m.entities.erase_entities([w]) if w.valid? }
ok('update! turns it back', WI.update!(detect, m))
ok('lower piece is EXTERIOR again', lo.get_attribute('InteriorPro', 'wall_category') == 'exterior' && lo.get_attribute('InteriorPro', 'auto_interior').nil?)

# a wall the USER made interior is never touched
Sketchup.reset_model!
m = Sketchup.active_model
house = [wall(m, [0, 0], [200, 0], 'a'), wall(m, [200, 0], [200, 100], 'b'), wall(m, [200, 100], [0, 100], 'c'), wall(m, [0, 100], [0, 0], 'd')]
house.each { |w| WT.new.join_corners(w, m) }
part = wall(m, [100, 5], [100, 95], 'p', th: 4.5, cat: 'interior')
WI.update!(detect, m)
ok('his own interior wall stays interior even with the loop', part.get_attribute('InteriorPro', 'wall_category') == 'interior')

# kill switch
WI.send(:remove_const, :USE_AUTO_INTERIOR)
WI.const_set(:USE_AUTO_INTERIOR, false)
ok('switched off = does nothing', !WI.update!(detect, m))

puts($fails.zero? ? 'rt337 OK' : "rt337 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

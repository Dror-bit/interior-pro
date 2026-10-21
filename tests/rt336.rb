# encoding: utf-8
# rt336 - a new wall that runs on in line from a house wall and ends ON the
#         house's corner makes a T, not a flipped corner (wall_tool.rb,
#         tee_at_existing_corner!, 2026-10-20).
#
# His words: "ציירתי 3 קירות חוץ ... את הקיר האחרון חיברתי לפינה ואז הוא
# שבר אותה". His exact numbers (room_add_watch.txt, 13:15): house left wall
# c8a403d4 (-702,407.5)->(-702,183), house bottom wall 045fe78b
# (-702,183)->(-438,183), new wall 73994996 (-752,183)->(-702,183), all
# exterior, 5", bottom-left. The old code mitered the new wall against the
# left wall: its corner went to inside -697,183 / outside -702,188.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

WT = InteriorPro::WallTool

def wall(m, s, e, th: 5.0)
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', "w#{m.entities.length}")
  g.set_attribute('InteriorPro', 'start_x', s[0]); g.set_attribute('InteriorPro', 'start_y', s[1])
  g.set_attribute('InteriorPro', 'end_x',   e[0]); g.set_attribute('InteriorPro', 'end_y',   e[1])
  g.set_attribute('InteriorPro', 'thickness', th)
  g.set_attribute('InteriorPro', 'height', 96.0)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-left')
  g.set_attribute('InteriorPro', 'wall_category', 'exterior')
  g.set_attribute('InteriorPro', 'level', 1)
  t = WT.new
  d = t.wall_data(g)
  t.save_corners_attr(g, t.perpendicular_corners_xy(Geom::Point3d.new(s[0], s[1], 0), Geom::Point3d.new(e[0], e[1], 0), d[:thickness], d[:h_anchor]))
  g
end

def cs(g); g.get_attribute('InteriorPro', 'corners_xy').each_slice(2).map { |x, y| [x.round(2), y.round(2)] }; end
def has?(g, pts); c = cs(g); pts.all? { |p| c.any? { |q| (q[0] - p[0]).abs < 0.01 && (q[1] - p[1]).abs < 0.01 } }; end

def house(m)
  left = wall(m, [-702, 407.5], [-702, 183])
  bottom = wall(m, [-702, 183], [-438, 183])
  WT.new.join_corners(bottom, m)
  [left, bottom]
end

# ---- his house corner, as it was before
Sketchup.reset_model!
m = Sketchup.active_model
left, bottom = house(m)
ok('the house corner starts as his model had it (inside -697,188 / outside -702,183)',
   has?(left, [[-697, 188], [-702, 183]]) && has?(bottom, [[-697, 188], [-702, 183]]), [cs(left), cs(bottom)])

# ---- the new wall that continues the bottom wall and ends on the corner
nw = wall(m, [-752, 183], [-702, 183])
WT.new.join_corners(nw, m)
ok('the left wall is NOT flipped - no point at -697,183', !has?(left, [[-697, 183]]), cs(left))
ok('the left wall stops on the bottom line: -697,188 and -702,188', has?(left, [[-697, 188], [-702, 188]]), cs(left))
ok('the bottom wall end is square: -702,188 and -702,183', has?(bottom, [[-702, 188], [-702, 183]]), cs(bottom))
ok('the new wall end is square, flush with it', has?(nw, [[-702, 188], [-702, 183]]), cs(nw))
ok('the bottom wall far end is untouched', has?(bottom, [[-438, 188], [-438, 183]]), cs(bottom))

# ---- joining the LEFT wall again later (a stretch, a neighbour deleted) keeps the T
WT.new.join_corners(left, m)
ok('joining the left wall again keeps the T',
   has?(left, [[-697, 188], [-702, 188]]) && has?(bottom, [[-702, 188], [-702, 183]]) && has?(nw, [[-702, 188], [-702, 183]]), [cs(left), cs(bottom), cs(nw)])
WT.new.join_corners(bottom, m)
ok('joining the bottom wall again keeps the T too', has?(left, [[-697, 188], [-702, 188]]) && has?(bottom, [[-702, 188], [-702, 183]]), [cs(left), cs(bottom)])

# ---- the new wall deleted: the house corner comes back (what delete_wall! does)
m.entities.erase_entities([nw])
t = WT.new
[left, bottom].each { |g| d = t.wall_data(g); c = t.compute_perpendicular_corners_from_data(d); t.save_corners_attr(g, c); t.rebuild_wall_geometry(g, c, d) }
[left, bottom].each { |g| t.join_corners(g, m, allow_centerline_fallback: true) }
ok('after the new wall is gone the corner is mitered again', has?(left, [[-697, 188], [-702, 183]]) && has?(bottom, [[-697, 188], [-702, 183]]), [cs(left), cs(bottom)])

# ---- a plain corner (only two walls) is not touched by this
Sketchup.reset_model!
m = Sketchup.active_model
a = wall(m, [0, 0], [100, 0])
b = wall(m, [100, 0], [100, 100])
ok('two walls only - no T', !WT.new.tee_at_existing_corner!(b, :start, m))

# ---- different thickness in line: old path
Sketchup.reset_model!
m = Sketchup.active_model
left, bottom = house(m)
thin = wall(m, [-752, 183], [-702, 183], th: 4.5)
ok('a thinner wall in line is not a flush T - old path', !WT.new.tee_at_existing_corner!(thin, :end, m))

# ---- kill switch
Sketchup.reset_model!
m = Sketchup.active_model
left, bottom = house(m)
nw = wall(m, [-752, 183], [-702, 183])
WT.send(:remove_const, :USE_TEE_AT_CORNER)
WT.const_set(:USE_TEE_AT_CORNER, false)
WT.new.join_corners(nw, m)
ok('switched off = the old flip comes back (proves the test sees the bug)', has?(left, [[-697, 183]]), cs(left))

puts($fails.zero? ? 'rt336 OK' : "rt336 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

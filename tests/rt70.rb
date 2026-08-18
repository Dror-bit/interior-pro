# encoding: utf-8
# rt70 - a corner that was MEANT but missed by a hair closes itself
#        (wall_tool.rb, 2026-08-18).
#
# WHAT THE USER ASKED FOR, in his words:
#   "אם הם נכנסים אחד לתוך השני ואמורה להיות שם פינה שיתקן וישלים אותה
#    אוטומטית שהיא תיראה טוב"
#
# WHY IT WAS BROKEN. find_neighbor_at matches DRAWN ends within 0.001". An
# end left 0.3" short is invisible to it, so no miter is cut and the end
# keeps its plain square cap - and paint_wall_long_faces! only paints the
# long faces, so that cap shows up WHITE. Measured on his model: three
# corners open and five ends still square - white wedges on screen.
#
# THE RULE NOW: no exact neighbour, but one within a wall thickness on the
# SAME storey and the SAME anchor side -> this wall's end is pulled onto it
# and the normal miter runs.
#
# THE THREE THINGS IT MUST REFUSE, each of which would be a worse bug:
#   - another storey  (that is the 2026-08-17 "the target runs away" bug)
#   - another anchor side (drawn ends there are a thickness apart even when
#     the corner is PERFECT - welding would break a good corner)
#   - further than a thickness (a gap drawn on purpose)
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

WT = InteriorPro::WallTool

def wall(m, s, e, level: 1, anchor: 'bottom-left', th: 5.0)
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', "w#{m.entities.length}")
  g.set_attribute('InteriorPro', 'start_x', s[0]); g.set_attribute('InteriorPro', 'start_y', s[1])
  g.set_attribute('InteriorPro', 'end_x',   e[0]); g.set_attribute('InteriorPro', 'end_y',   e[1])
  g.set_attribute('InteriorPro', 'thickness', th)
  g.set_attribute('InteriorPro', 'height', 96.0)
  g.set_attribute('InteriorPro', 'anchor', anchor)
  g.set_attribute('InteriorPro', 'wall_category', 'exterior')
  g.set_attribute('InteriorPro', 'level', level)
  tool = WT.new
  d = tool.wall_data(g)
  c = tool.perpendicular_corners_xy(Geom::Point3d.new(s[0], s[1], 0),
                                    Geom::Point3d.new(e[0], e[1], 0),
                                    d[:thickness], d[:h_anchor])
  tool.save_corners_attr(g, c)
  g
end

def ends_of(g)
  [[g.get_attribute('InteriorPro', 'start_x').to_f, g.get_attribute('InteriorPro', 'start_y').to_f],
   [g.get_attribute('InteriorPro', 'end_x').to_f,   g.get_attribute('InteriorPro', 'end_y').to_f]]
end

def dist(a, b)
  Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2)
end

# ---------------------------------------------------------------- it closes
Sketchup.reset_model!
m = Sketchup.active_model
a = wall(m, [0, 0], [100, 0])
b = wall(m, [100.212, 0.212], [100.212, 100.212])   # 0.3" short of a's end
before_a = ends_of(a)
tool = WT.new
tool.weld_drifted_end!(b, :start, m)
ok('the drifted end is pulled onto its neighbour',
   dist(ends_of(b)[0], [100.0, 0.0]) < 1e-6, ends_of(b)[0])
ok('the NEIGHBOUR is never moved', ends_of(a) == before_a, ends_of(a))
ok('the wall keeps its own far end', dist(ends_of(b)[1], [100.212, 100.212]) < 1e-6, ends_of(b)[1])

# the footprint is rebuilt from the new end, not left where it was
fp = b.get_attribute('InteriorPro', 'corners_xy')
ok('the footprint follows the moved end',
   fp.each_slice(2).any? { |x, y| dist([x, y], [100.0, 0.0]) < 6.0 }, fp)

# ------------------------------------------------- it refuses another storey
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0], level: 1)
up = wall(m, [100.212, 0.212], [100.212, 100.212], level: 2)
before = ends_of(up)
ok('a wall on another storey is NOT welded to',
   WT.new.weld_drifted_end!(up, :start, m) == false)
ok('and it did not move', ends_of(up) == before, ends_of(up))

# --------------------------------------------- it refuses another anchor side
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0], anchor: 'bottom-left')
r = wall(m, [100.212, 0.212], [100.212, 100.212], anchor: 'bottom-right')
before = ends_of(r)
ok('a wall anchored on the other side is NOT welded to',
   WT.new.weld_drifted_end!(r, :start, m) == false)
ok('and it did not move', ends_of(r) == before, ends_of(r))

# ------------------------------------------------- it refuses a real gap
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0], th: 5.0)
far = wall(m, [106.0, 0], [106.0, 100.0], th: 5.0)   # 6" away, more than a thickness
before = ends_of(far)
ok('a gap wider than a wall thickness is left alone',
   WT.new.weld_drifted_end!(far, :start, m) == false)
ok('and it did not move', ends_of(far) == before, ends_of(far))

# a hair under a thickness IS closed
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0], th: 5.0)
near = wall(m, [104.5, 0], [104.5, 100.0], th: 5.0)  # 4.5" - under the 5" thickness
ok('a gap under a wall thickness IS closed',
   WT.new.weld_drifted_end!(near, :start, m) == true)
ok('and it landed exactly on the neighbour',
   dist(ends_of(near)[0], [100.0, 0.0]) < 1e-6, ends_of(near)[0])

# --------------------------------------------------- an exact corner is not touched
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0])
exact = wall(m, [100.0, 0.0], [100.0, 100.0])
before = ends_of(exact)
ok('an end that already meets is left alone',
   WT.new.weld_drifted_end!(exact, :start, m) == false)
ok('and it did not move', ends_of(exact) == before, ends_of(exact))

# --------------------------------------------------------- nothing nearby
Sketchup.reset_model!
m = Sketchup.active_model
lonely = wall(m, [0, 0], [100, 0])
ok('a wall with no neighbour at all is left alone',
   WT.new.weld_drifted_end!(lonely, :start, m) == false)

# ------------------------------------------------------------ kill switch
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0])
k = wall(m, [100.212, 0.212], [100.212, 100.212])
before = ends_of(k)
WT.send(:remove_const, :AUTO_WELD_ENDS)
WT.const_set(:AUTO_WELD_ENDS, false)
ok('AUTO_WELD_ENDS = false turns the whole thing off',
   WT.new.weld_drifted_end!(k, :start, m) == false)
ok('and nothing moved', ends_of(k) == before, ends_of(k))
WT.send(:remove_const, :AUTO_WELD_ENDS)
WT.const_set(:AUTO_WELD_ENDS, true)

# -------------------------------------------- join_corners uses it by itself
# The point of the whole change: nobody has to call the weld. Joining the
# corners of a wall that missed by a hair closes it.
Sketchup.reset_model!
m = Sketchup.active_model
wall(m, [0, 0], [100, 0])
j = wall(m, [100.212, 0.212], [100.212, 100.212])
WT.new.join_corners(j, m)
ok('join_corners closes the missed corner on its own',
   dist(ends_of(j)[0], [100.0, 0.0]) < 1e-6, ends_of(j)[0])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

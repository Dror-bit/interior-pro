# encoding: utf-8
# rt57 - landscape/fence_tool.rb: the fence really gets BUILT, and it really
# gets its numbers from fence_math.
#
# This suite is deliberately not a second copy of rt56. rt56 proves the maths.
# What can still go wrong after that is the thing that has bitten this project
# twice already: code that is written but never reached, or a builder that
# quietly grew its own arithmetic instead of calling the tested one.
#
# So every check here RUNS the real tool object and then asks who it called.
# The spies below replace FenceMath's functions with counting wrappers that
# still return the real answers - if the tool ever stops going through them,
# the counts drop to zero and this suite goes red.
require './sketchup_stub'
require './fence_math'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

# Every part of a fence is its own little group since 2026-08-16 (it stops two
# touching boards welding into one solid, and stops a glass panel dragging its
# colour onto the rail it leans on). The faces are therefore one level down.
# Nothing else in this suite changed - every claim below is the same claim.
def faces_in(e)
  out = []
  ents = e.respond_to?(:entities) ? e.entities : e
  ents.each do |x|
    if x.is_a?(Sketchup::Face)
      out << x
    elsif x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance)
      out.concat(faces_in(x))
    end
  end
  out
end

# ---- the axis magnet spy -------------------------------------------------
# In SketchUp this lives on WallTool. The fence must CALL it, not copy it.
$magnet_calls = 0
module InteriorPro
  module WallTool
    def self.apply_axis_magnet(a, b, _model = nil)
      $magnet_calls += 1
      [a, b]
    end
  end
end

require './fence_tool'

FM = InteriorPro::Landscape::FenceMath
FT = InteriorPro::Landscape::FenceTool

# ---- spies on the maths --------------------------------------------------
$calls = Hash.new(0)
module InteriorPro
  module Landscape
    module FenceMath
      class << self
        %i[layout board_runs top_at bottom_at point_at].each do |m|
          orig = instance_method(m)
          define_method(m) do |*a, **kw, &blk|
            $calls[m] += 1
            kw.empty? ? orig.bind(self).call(*a, &blk) : orig.bind(self).call(*a, **kw, &blk)
          end
        end
      end
    end
  end
end

def fresh_tool
  $calls.clear
  $magnet_calls = 0
  Sketchup.reset_model!
  FT.new
end

def build(tool, ax, ay, bx, by)
  tool.instance_variable_set(:@p1, Geom::Point3d.new(ax, ay, 0))
  tool.instance_variable_set(:@p2, Geom::Point3d.new(bx, by, 0))
  tool.send(:build_it, Object.new.tap { |v| def v.invalidate; true; end })
  Sketchup.active_model.entities.grep(Sketchup::Group)
          .find { |g| g.get_attribute('LandscapePro', 'type') == 'fence' }
end

# ------------------------------------------------------------------ the tool

t = FT.new
ok('the tool exists and can be made', !t.nil?)
ok('it answers the SketchUp tool API',
   %i[activate deactivate draw onLButtonDown onMouseMove getExtents].all? { |m| t.respond_to?(m) },
   %i[activate deactivate draw onLButtonDown onMouseMove getExtents].reject { |m| t.respond_to?(m) })
ok('default height is 72', close(t.height, 72.0), t.height)
ok('default ground is level at both ends', close(t.ground_start, 0.0) && close(t.ground_end, 0.0))
ok('default slope mode is rake', t.mode == :rake, t.mode)

# ------------------------------------------------------- a level fence gets built

t = fresh_tool
g = build(t, 0, 0, 240, 0)
ok('a fence group is created', !g.nil?)
ok('it is tagged as a fence, in its OWN dictionary',
   g.get_attribute('LandscapePro', 'type') == 'fence')
ok('it is NOT mistakable for a wall',
   g.get_attribute('InteriorPro', 'type').nil?,
   g.get_attribute('InteriorPro', 'type'))
ok('the group is named for Landscape Pro', g.name == 'LandscapePro_Fence', g.name)

# The two numbers that make terrain possible later.
ok('ground_start is stored', g.get_attribute('LandscapePro', 'ground_start') == 0.0)
ok('ground_end is stored',   g.get_attribute('LandscapePro', 'ground_end') == 0.0)
ok('BOTH ground numbers exist, not one',
   g.get_attribute('LandscapePro', 'ground_start') &&
   g.get_attribute('LandscapePro', 'ground_end'))

ok('the ends are stored so it can be rebuilt',
   close(g.get_attribute('LandscapePro', 'start_x').to_f, 0.0) &&
   close(g.get_attribute('LandscapePro', 'end_x').to_f, 240.0))
ok('the slope mode is stored', g.get_attribute('LandscapePro', 'slope_mode') == 'rake')
ok('it counted 4 posts', g.get_attribute('LandscapePro', 'posts') == 4,
   g.get_attribute('LandscapePro', 'posts'))
ok('it counted 3 bays',  g.get_attribute('LandscapePro', 'bays') == 3,
   g.get_attribute('LandscapePro', 'bays'))

# ---- accessibility: it went through the tested maths, not its own ----------

ok('the tool CALLED FenceMath.layout', $calls[:layout] > 0, $calls)
ok('the tool CALLED FenceMath.board_runs', $calls[:board_runs] > 0, $calls)
ok('the tool CALLED FenceMath.top_at', $calls[:top_at] > 0, $calls)
ok('board_runs was asked once per bay', $calls[:board_runs] == 3, $calls[:board_runs])
ok('the tool CALLED the wall axis magnet', $magnet_calls == 1, $magnet_calls)

# ---- accessibility: real geometry came out ---------------------------------

faces = faces_in(g)
ok('faces were actually made', faces.length > 0, faces.length)
ok('every face was pushed out into a solid',
   faces.all? { |f| f.pushpulls.length == 1 },
   faces.map { |f| f.pushpulls.length }.uniq)
ok('nothing was pushed by zero', faces.none? { |f| f.pushpulls.first.abs < 1e-9 })
ok('every face got painted', faces.all? { |f| !f.material.nil? })

# 4 posts + 3 bays of boards. 80" bay, 4" post -> 76" clear, 5.5" boards -> 14 each.
posts = faces.select { |f| f.points.map(&:z).uniq.length == 1 }   # flat bottom square
ok('one flat starter face per post', posts.length == 4, posts.length)
ok('a post was pushed UP by its full height',
   posts.all? { |f| close(f.pushpulls.first.abs, 72.0) },
   posts.map { |f| f.pushpulls.first })

boards = faces - posts
ok('boards were built in every bay', boards.length >= 3 * 10, boards.length)
ok('every board was pushed by its thickness',
   boards.all? { |f| close(f.pushpulls.first.abs, 0.75) },
   boards.map { |f| f.pushpulls.first.abs }.uniq)
ok('level fence: every board is the same height',
   boards.map { |f| (f.points.map(&:z).max - f.points.map(&:z).min).round(6) }.uniq.length == 1,
   boards.map { |f| (f.points.map(&:z).max - f.points.map(&:z).min).round(3) }.uniq)
ok('level fence: every board top is 72',
   boards.all? { |f| close(f.points.map(&:z).max, 72.0) },
   boards.map { |f| f.points.map(&:z).max.round(3) }.uniq)

# ----------------------------------------------------- a fence down a slope

t = fresh_tool
t.ground_end = -24.0
g = build(t, 0, 0, 240, 0)
ok('slope: a fence group is created', !g.nil?)
ok('slope: ground_end really stored as -24',
   close(g.get_attribute('LandscapePro', 'ground_end').to_f, -24.0),
   g.get_attribute('LandscapePro', 'ground_end'))

faces = faces_in(g)
posts = faces.select { |f| f.points.map(&:z).uniq.length == 1 }
boards = faces - posts

ok('slope: still 4 posts', posts.length == 4, posts.length)
ok('slope: the posts sit at four DIFFERENT heights',
   posts.map { |f| f.points.first.z.round(6) }.uniq.length == 4,
   posts.map { |f| f.points.first.z.round(3) })
ok('slope: the lowest post base is -24',
   close(posts.map { |f| f.points.first.z }.min, -24.0),
   posts.map { |f| f.points.first.z }.min)
ok('slope: every post is still 72 tall',
   posts.all? { |f| close(f.pushpulls.first.abs, 72.0) },
   posts.map { |f| f.pushpulls.first.abs }.uniq)

tops = boards.map { |f| f.points.map(&:z).max }
ok('slope (rake): the board tops are NOT all equal',
   tops.map { |z| z.round(4) }.uniq.length > 1, tops.map { |z| z.round(2) }.uniq.length)
# The tallest BOARD is a touch under 72: it starts half a post clear of the
# first post, and by then the ground has already dropped a little. The POST
# is the thing that is exactly 72 - checked above.
ok('slope (rake): the highest board top is just under the first post',
   tops.max < 72.0 && tops.max > 71.5, tops.max)
ok('slope (rake): the lowest board top is near 48',
   tops.min > 47.0 && tops.min < 49.0, tops.min)
ok('slope (rake): no board pokes above its own post', tops.max <= 72.0 + 1e-9, tops.max)

# ------------------------------------------------------- the STEP mode really differs

t = fresh_tool
t.ground_end = -24.0
t.mode = :step
g = build(t, 0, 0, 240, 0)
ok('step: stored as step', g.get_attribute('LandscapePro', 'slope_mode') == 'step',
   g.get_attribute('LandscapePro', 'slope_mode'))
faces = faces_in(g)
posts = faces.select { |f| f.points.map(&:z).uniq.length == 1 }
boards = faces - posts
tops = boards.map { |f| f.points.map(&:z).max.round(6) }
ok('step: only three different board tops - one per bay',
   tops.uniq.length == 3, tops.uniq)
ok('step: the top bay is at 72', close(tops.max, 72.0), tops.max)

# A level fence must come out IDENTICAL in both modes, or picking a mode
# quietly changes a flat fence nobody meant to change.
t = fresh_tool
g1 = build(t, 0, 0, 240, 0)
z1 = faces_in(g1).map { |f| f.points.map { |p| p.z.round(9) } }.sort
t = fresh_tool
t.mode = :step
g2 = build(t, 0, 0, 240, 0)
z2 = faces_in(g2).map { |f| f.points.map { |p| p.z.round(9) } }.sort
ok('a LEVEL fence is identical in rake and step', z1 == z2)

# --------------------------------------------------------------- refusals

t = fresh_tool
g = build(t, 0, 0, 0.4, 0)
ok('a mis-click builds nothing', g.nil?)
ok('and does not leave a half-open operation',
   Sketchup.active_model.ops.count { |o| o[0] == :start } ==
   Sketchup.active_model.ops.count { |o| o[0] == :commit || o[0] == :abort },
   Sketchup.active_model.ops)

# A real fence DOES open and close exactly one operation, so one Undo takes
# the whole fence away rather than one board at a time.
t = fresh_tool
build(t, 0, 0, 240, 0)
ops = Sketchup.active_model.ops
ok('one fence = one undo step',
   ops.count { |o| o[0] == :start } == 1 && ops.count { |o| o[0] == :commit } == 1,
   ops)

# ------------------------------------------------------- a diagonal fence

t = fresh_tool
g = build(t, 0, 0, 180, 240)
ok('diagonal: built', !g.nil?)
ok('diagonal: length stored is 300',
   close(g.get_attribute('LandscapePro', 'length_in').to_f, 300.0),
   g.get_attribute('LandscapePro', 'length_in'))
faces = faces_in(g)
posts = faces.select { |f| f.points.map(&:z).uniq.length == 1 }
ok('diagonal: 5 posts', posts.length == 5, posts.length)
ok('diagonal: posts are square, not stretched',
   posts.all? { |f|
     p = f.points
     e1 = Math.hypot(p[1].x - p[0].x, p[1].y - p[0].y)
     e2 = Math.hypot(p[2].x - p[1].x, p[2].y - p[1].y)
     close(e1, 4.0, 1e-6) && close(e2, 4.0, 1e-6)
   },
   posts.map { |f| p = f.points; [Math.hypot(p[1].x - p[0].x, p[1].y - p[0].y).round(3),
                                  Math.hypot(p[2].x - p[1].x, p[2].y - p[1].y).round(3)] }.uniq)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

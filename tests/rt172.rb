# encoding: utf-8
# rt172 - the floor anchor moves the walls ALREADY IN THE MODEL (2026-09-24).
#
# alignPendingToOrigin moved only the blue walls. But a click on the door or
# window button runs Apply by itself, so by the time he anchors, most of the
# floor is in the model already - half moved, half did not: "it sent each
# floor somewhere different". Now the window sends the same corner + turn to
# Ruby and transform_walls! gives the model walls the same rigid move.
# transform_walls! is also what translate_walls! runs through (rt14 guards
# that the shift-only case is unchanged).
require './sketchup_stub'

module InteriorPro
  module WallTool
    # wall_data is truthy so the door/window loop runs; there is no
    # geometry to rebuild in the stub, so corners come back nil.
    class StubInstance
      def wall_data(_g); {}; end
      def read_corners_attr(_g); nil; end
      def compute_perpendicular_corners_from_data(_d); nil; end
    end
    def self.new; StubInstance.new; end
  end
end

require './plan_editor'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
PE = InteriorPro::PlanEditor

def make_wall(m, id, sx, sy, ex, ey)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', sx); w.set_attribute('InteriorPro', 'start_y', sy)
  w.set_attribute('InteriorPro', 'end_x', ex);   w.set_attribute('InteriorPro', 'end_y', ey)
  w.set_attribute('InteriorPro', 'thickness', 5.0)
  w.set_attribute('InteriorPro', 'corners_xy', [sx, sy, ex, ey, ex, ey + 5.0, sx, sy + 5.0])
  w
end

def pts(g); %w[start_x start_y end_x end_y].map { |k| g.get_attribute('InteriorPro', k).to_f }; end
def near(a, b, tol = 1e-6); a.zip(b).all? { |x, y| (x - y).abs < tol }; end

# The same move the align_walls callback builds: corner (cx,cy) to (0,0),
# then a turn of ang about the origin.
def anchor_tr(cx, cy, ang)
  Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), ang) *
    Geom::Transformation.translation(Geom::Vector3d.new(-cx, -cy, 0))
end

# --- a floor drawn at (500,500), direction along +X: pure shift ------------
Sketchup.reset_model!
m = Sketchup.active_model
a = make_wall(m, 'a', 500.0, 500.0, 740.0, 500.0)
b = make_wall(m, 'b', 740.0, 500.0, 740.0, 680.0)
n = PE.send(:transform_walls!, %w[a b], anchor_tr(500.0, 500.0, 0.0))
ok('both walls processed', n == 2, n)
ok('the picked corner sits on (0,0)', near(pts(a), [0.0, 0.0, 240.0, 0.0]), pts(a))
ok('the next wall came along', near(pts(b), [240.0, 0.0, 240.0, 180.0]), pts(b))

# --- the same floor with the direction picked along +Y: a quarter turn -----
# He picked the corner and then a point UP the side wall, so that side
# must become the +X axis: everything turns -90 degrees.
Sketchup.reset_model!
m = Sketchup.active_model
a = make_wall(m, 'a', 500.0, 500.0, 740.0, 500.0)
b = make_wall(m, 'b', 500.0, 500.0, 500.0, 680.0)
d = m.entities.add_group
d.set_attribute('InteriorPro', 'type', 'door')
d.set_attribute('InteriorPro', 'host_wall_id', 'b')
d.set_attribute('InteriorPro', 'face_x', 500.0)
d.set_attribute('InteriorPro', 'face_y', 560.0)
PE.send(:transform_walls!, %w[a b], anchor_tr(500.0, 500.0, -Math::PI / 2))
ok('the side wall now runs along +X', near(pts(b), [0.0, 0.0, 180.0, 0.0]), pts(b))
ok('the front wall turned with it', near(pts(a), [0.0, 0.0, 0.0, -240.0]), pts(a))
c2 = b.get_attribute('InteriorPro', 'corners_xy')
ok('corners stay a FLAT 8-array', c2.is_a?(Array) && c2.length == 8, c2)
ok('and were turned, not just shifted', near(c2[0, 4], [0.0, 0.0, 180.0, 0.0]), c2)
ok('the door on the side wall rode along (face point)',
   (d.get_attribute('InteriorPro', 'face_x') - 60.0).abs < 1e-6 &&
   d.get_attribute('InteriorPro', 'face_y').abs < 1e-6,
   [d.get_attribute('InteriorPro', 'face_x'), d.get_attribute('InteriorPro', 'face_y')])
o = d.transformation.origin
# its origin (0,0): shift by (-500,-500) -> (-500,-500); turn -90: (x,y)->(y,-x) -> (-500, 500)
ok('and its instance was moved by the same transformation',
   (o.x + 500.0).abs < 1e-6 && (o.y - 500.0).abs < 1e-6, o)

# --- two floors drawn apart land on top of each other ---------------------
Sketchup.reset_model!
m = Sketchup.active_model
f1 = make_wall(m, 'f1', 500.0, 500.0, 740.0, 500.0)
f2 = make_wall(m, 'f2', -900.0, 300.0, -900.0, 540.0)
PE.send(:transform_walls!, %w[f1], anchor_tr(500.0, 500.0, 0.0))
PE.send(:transform_walls!, %w[f2], anchor_tr(-900.0, 300.0, -Math::PI / 2))
ok('floor 1 and floor 2 end up identical', near(pts(f1), pts(f2)), [pts(f1), pts(f2)])

# --- a target that is not the origin (2026-09-24): the ADU's upper floor
# lands on the ADU's ground floor, and the house next to it is not touched
# because the window only sends the selected ids.
def target_tr(cx, cy, ang, tx, ty)
  Geom::Transformation.translation(Geom::Vector3d.new(tx, ty, 0)) *
    Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), ang) *
    Geom::Transformation.translation(Geom::Vector3d.new(-cx, -cy, 0))
end
Sketchup.reset_model!
m = Sketchup.active_model
house = make_wall(m, 'house', 0.0, 0.0, 240.0, 0.0)
adu   = make_wall(m, 'adu', 900.0, 900.0, 900.0, 1100.0)
PE.send(:transform_walls!, %w[adu], target_tr(900.0, 900.0, -Math::PI / 2, 600.0, 100.0))
ok('the ADU wall lands on the target corner and direction', near(pts(adu), [600.0, 100.0, 800.0, 100.0]), pts(adu))
ok('the house was not touched', near(pts(house), [0.0, 0.0, 240.0, 0.0]), pts(house))

ok('unknown ids -> 0, no crash', PE.send(:transform_walls!, %w[nope], anchor_tr(0, 0, 0)) == 0)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

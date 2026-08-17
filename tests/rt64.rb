# encoding: utf-8
# rt64 - landscape/garden_wall_tool.rb: the garden wall (חומה), step 1, the body.
#
# What has to be proved before he looks at it in SketchUp:
#
#   * it is stored under LandscapePro, NOT InteriorPro - because everything in
#     the plugin that hunts for building walls (rooms, floors, molding, roofs,
#     the 2D plan, the wall edit/move/split tools) finds them by exactly the
#     'InteriorPro' dictionary and type 'wall'. This is THE thing that keeps a
#     garden wall out of the house.
#   * the solid lands where he clicked: centred on the line, the right
#     thickness across, the right height up - whichever way he drew it.
#   * it is built UP, not down into the ground, no matter the click order.
#   * the finish is painted on every face but the underside.
#   * a mis-click builds nothing and does not raise.
require './sketchup_stub'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

$magnet_calls = 0
module InteriorPro
  PLUGIN_DIR = File.expand_path('..', __dir__) unless const_defined?(:PLUGIN_DIR)
  module WallTool
    def self.apply_axis_magnet(a, b, _model = nil)
      $magnet_calls += 1
      [a, b]
    end
  end
  $tags = []
  def self.assign_tag(_e, name); $tags << name; true; end
end

require './garden_wall_tool'
GW = InteriorPro::Landscape::GardenWallTool

def pt(x, y); Geom::Point3d.new(x, y, 0); end
def fresh(t = 8.0, h = 36.0, m = 'Stucco')
  Sketchup.reset_model!
  $magnet_calls = 0
  $tags = []
  GW.new(t, h, m)
end
def walls
  Sketchup.active_model.entities.grep(Sketchup::Group)
          .select { |g| g.get_attribute('LandscapePro', 'type') == 'garden_wall' }
end

# --------------------------------------------------- the footprint, as numbers

t = fresh(8.0, 36.0)
fp = t.footprint(pt(0, 0), pt(120, 0))
ok('four floor corners', fp.length == 4, fp.length)
ok('the wall is CENTRED on the line - 4" each side of a 8" wall',
   fp.map { |p| p.y.round(6) }.sort == [-4.0, -4.0, 4.0, 4.0],
   fp.map { |p| [p.x.round(2), p.y.round(2)] })
ok('it runs the full length he clicked',
   fp.map { |p| p.x.round(6) }.sort == [0.0, 0.0, 120.0, 120.0],
   fp.map(&:x))
ok('the footprint sits on the ground', fp.all? { |p| close(p.z, 0.0) }, fp.map(&:z))

# Drawn the other way round, the wall must occupy the SAME ground.
back = t.footprint(pt(120, 0), pt(0, 0))
ok('drawing it right-to-left covers the same ground',
   back.map { |p| [p.x.round(4), p.y.round(4)] }.sort ==
   fp.map { |p| [p.x.round(4), p.y.round(4)] }.sort,
   back.map { |p| [p.x.round(2), p.y.round(2)] })

# On a diagonal the thickness is measured ACROSS the run, not along the axes.
d = t.footprint(pt(0, 0), pt(100, 100))
mid_a = Geom::Point3d.new((d[0].x + d[3].x) / 2.0, (d[0].y + d[3].y) / 2.0, 0)
ok('a diagonal wall still starts on the line he clicked',
   close(mid_a.x, 0.0, 1e-9) && close(mid_a.y, 0.0, 1e-9), [mid_a.x, mid_a.y])
w = Math.sqrt((d[0].x - d[3].x)**2 + (d[0].y - d[3].y)**2)
ok('a diagonal wall is 8" thick across the run, not 8" in x', close(w, 8.0, 1e-9), w)

ok('a zero-length line has no footprint', t.footprint(pt(5, 5), pt(5, 5)).nil?)

# A thicker wall is thicker, and the thickness comes from the tool.
ok('thickness follows the setting',
   begin
     f2 = fresh(16.0).footprint(pt(0, 0), pt(50, 0))
     close((f2[0].y - f2[3].y).abs, 16.0, 1e-9)
   end)

# ---------------------------------------------------------------- building it

t = fresh(8.0, 36.0, 'Stucco')
g = t.build!(pt(0, 0), pt(120, 0))
ok('a group is created', !g.nil?)
ok('there is exactly one garden wall in the model', walls.length == 1, walls.length)
ok('it carries the Landscape Pro group name',
   g.name == 'LandscapePro_GardenWall', g.name)
ok('it is tagged LP/Walls', $tags == ['LP/Walls'], $tags)

# THE important one.
ok('type garden_wall lives under the LandscapePro dictionary',
   g.get_attribute('LandscapePro', 'type') == 'garden_wall',
   g.get_attribute('LandscapePro', 'type'))
ok('NOTHING is written under InteriorPro - the house tools must never see it',
   g.get_attribute('InteriorPro', 'type').nil?,
   g.get_attribute('InteriorPro', 'type'))
ok('it is not called a wall anywhere',
   g.get_attribute('LandscapePro', 'type') != 'wall')

ok('thickness stored', close(g.get_attribute('LandscapePro', 'thickness'), 8.0))
ok('height stored',    close(g.get_attribute('LandscapePro', 'height'), 36.0))
ok('finish stored',    g.get_attribute('LandscapePro', 'material') == 'Stucco')
ok('both ends stored', close(g.get_attribute('LandscapePro', 'start_x'), 0.0) &&
                       close(g.get_attribute('LandscapePro', 'end_x'), 120.0))
ok('length stored',    close(g.get_attribute('LandscapePro', 'length_in'), 120.0))
ok('BOTH ground numbers are stored, ready for terrain',
   g.get_attribute('LandscapePro', 'ground_start') == 0.0 &&
   g.get_attribute('LandscapePro', 'ground_end') == 0.0)

faces = g.entities.grep(Sketchup::Face)
ok('one footprint face was drawn', faces.length == 1, faces.length)
f = faces.first
ok('it was pushed exactly once', f.pushpulls.length == 1, f.pushpulls)
# The sign has to come out positive-upwards WHICHEVER way the face happened
# to face. That is the whole point of asking face.normal instead of assuming.
signed = f.pushpulls.first * (f.normal.z < 0 ? -1.0 : 1.0)
ok('the wall was pushed UP by its height, not down into the ground',
   close(signed, 36.0, 1e-9), [f.pushpulls.first, f.normal.z])

# Drawn the other way, it still goes up.
t = fresh(8.0, 36.0)
g2 = t.build!(pt(120, 40), pt(0, 40))
f2 = g2.entities.grep(Sketchup::Face).first
signed2 = f2.pushpulls.first * (f2.normal.z < 0 ? -1.0 : 1.0)
ok('drawn right-to-left it STILL goes up', close(signed2, 36.0, 1e-9),
   [f2.pushpulls.first, f2.normal.z])

# ------------------------------------------------------------------- finishes

t = fresh(8.0, 36.0, 'Stucco')
g = t.build!(pt(0, 0), pt(120, 0))
painted = g.entities.grep(Sketchup::Face).reject { |x| x.material.nil? }
ok('the finish was painted', painted.length >= 1, painted.length)
ok('the material is namespaced so it cannot collide with a house material',
   painted.first.material.name == 'LandscapePro_Stucco', painted.first.material.name)
ok('back_material is cleared', painted.all? { |x| x.back_material.nil? })

# A finish with no .jpg yet must still come out looking like something.
ok('a finish with no texture file gets a stand-in colour, not flat white',
   begin
     m = GW.finish_material('Stack Stone')
     !m.nil? && (!m.color.nil? || !m.texture.nil?)
   end)
ok('every listed finish can be made',
   GW::MATERIALS.all? { |n| !GW.finish_material(n).nil? }, GW::MATERIALS)
ok('the same finish is reused, not remade',
   GW.finish_material('Stucco').equal?(GW.finish_material('Stucco')))
ok('his list is his own, not the house wall list',
   GW::MATERIALS == ['Stucco', 'Stack Stone', 'Block Wall'], GW::MATERIALS)

# ------------------------------------------------------------- the mis-clicks

t = fresh
ok('a zero-length click builds nothing and does not raise',
   t.build!(pt(10, 10), pt(10, 10)).nil?)
ok('and left no group behind', walls.length.zero?, walls.length)

# ---------------------------------------------------------- the mouse, end to end

view = Object.new
def view.invalidate; true; end
def view.inputpoint(x, y); Struct.new(:position).new(Geom::Point3d.new(x, y, 0)); end

t = fresh(10.0, 48.0, 'Block Wall')
t.onLButtonDown(0, 0, 0, view)
ok('one click builds nothing yet', walls.length.zero?, walls.length)
t.onLButtonDown(0, 200, 0, view)
ok('the second click builds it', walls.length == 1, walls.length)
ok('the axis magnet was borrowed from the wall tool, once', $magnet_calls == 1, $magnet_calls)
gw = walls.first
ok('the settings he picked are the ones that got built',
   close(gw.get_attribute('LandscapePro', 'thickness'), 10.0) &&
   close(gw.get_attribute('LandscapePro', 'height'), 48.0) &&
   gw.get_attribute('LandscapePro', 'material') == 'Block Wall',
   [gw.get_attribute('LandscapePro', 'thickness'),
    gw.get_attribute('LandscapePro', 'height'),
    gw.get_attribute('LandscapePro', 'material')])

ops = Sketchup.active_model.ops
ok('one wall = one undo step',
   ops.count { |o| o[0] == :start } == 1 && ops.count { |o| o[0] == :commit } == 1, ops)

# A second click on the same spot must not build a zero-length wall.
t = fresh
t.onLButtonDown(0, 50, 50, view)
t.onLButtonDown(0, 50, 50, view)
ok('clicking the same spot twice builds nothing', walls.length.zero?, walls.length)

# ------------------------------------------------------- length typed, not clicked

t = fresh(8.0, 36.0)
t.onLButtonDown(0, 0, 0, view)
t.onMouseMove(0, 10, 0, view)
t.onUserText("10'", view)
ok('a typed length builds the wall', walls.length == 1, walls.length)
ok("10' came out as 120 inches along the direction of the cursor",
   close(walls.first.get_attribute('LandscapePro', 'length_in'), 120.0, 1e-6),
   walls.first.get_attribute('LandscapePro', 'length_in'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

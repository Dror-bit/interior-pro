# encoding: utf-8
# rt63 - landscape/fence_ref_tool.rb: HIS fence, laid along a line.
#
# The tool draws no geometry. It loads a .skp he made, finds the repeating
# UNIT (post + panel) and the CLOSER (the lone post at the far end), and lays
# instances of them along the two clicks. So what has to be proved is:
#
#   * it reads the shape correctly - the unit, the closer, which way it runs
#   * it places n units so they fill the length exactly, evenly stretched
#   * the closer lands where the next post would have been
#   * every placed thing is an instance of HIS definition, nothing invented
#   * a model that runs along Y comes out along the fence line all the same
#
# The stub cannot parse a .skp, so the suite builds a definition shaped
# exactly like his 'cable railing.skp' as measured by debug_fence_parts.rb:
# three units of Component#2 (3.9" post + panel, 78.7" pitch) along Y, and
# a lone Component#38 post at the far end.
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
  def self.assign_tag(*_a); true; end
end

require './fence_ref_tool'
FRT = InteriorPro::Landscape::FenceRefTool

# ------------------------------------------------- a stand-in for his file
#
# Everything is a box made of one face with the right corners; the reader
# only ever measures corners.
def box_def(name, x0, y0, z0, x1, y1, z1)
  d = Sketchup::ComponentDefinition.new(name)
  d.entities.add_face([Geom::Point3d.new(x0, y0, z0), Geom::Point3d.new(x1, y0, z0),
                       Geom::Point3d.new(x1, y1, z1), Geom::Point3d.new(x0, y1, z1)])
  d
end

# His unit: a post 3.875 wide (along Y!) x 3.9 across, 45 tall, then a
# panel 74.8 long x 2.4 across, from z=8 to z=45. Total pitch 78.688 along Y.
UNIT_ALONG = 78.688
POST_W     = 3.875
def his_fence(along_axis)
  fence = Sketchup::ComponentDefinition.new('cable railing')
  unit  = Sketchup::ComponentDefinition.new('Component#2')
  post  = box_def('Component#38', 0, 0, 0, POST_W, 3.9, 45.0)
  panel = box_def('Group#118', 0.75, POST_W, 8.0, 3.15, UNIT_ALONG, 45.0)   # runs along Y inside unit
  if along_axis == :y
    unit.entities.add_instance(post, Geom::Transformation.new)
    unit.entities.add_instance(panel, Geom::Transformation.new)
    3.times do |i|
      fence.entities.add_instance(unit, Geom::Transformation.translation(Geom::Vector3d.new(0, i * UNIT_ALONG, 0)))
    end
    fence.entities.add_instance(post, Geom::Transformation.translation(Geom::Vector3d.new(0, 3 * UNIT_ALONG, 0)))
  else
    # Same thing turned to run along X: swap x/y in the boxes.
    postx  = box_def('Component#38', 0, 0, 0, 3.9, POST_W, 45.0)
    panelx = box_def('Group#118', POST_W, 0.75, 8.0, UNIT_ALONG, 3.15, 45.0)
    unit.entities.add_instance(postx, Geom::Transformation.new)
    unit.entities.add_instance(panelx, Geom::Transformation.new)
    3.times do |i|
      fence.entities.add_instance(unit, Geom::Transformation.translation(Geom::Vector3d.new(i * UNIT_ALONG, 0, 0)))
    end
    fence.entities.add_instance(postx, Geom::Transformation.translation(Geom::Vector3d.new(3 * UNIT_ALONG, 0, 0)))
  end
  fence
end

require 'tmpdir'
REFDIR = Dir.mktmpdir('ip_fence_refs')
def fresh(along_axis = :y)
  Sketchup.reset_model!
  $magnet_calls = 0
  # The tool checks the file exists before it asks SketchUp to load it, so
  # the stand-in has to be a real (empty) file on disk with the definition
  # registered against its path.
  path = File.join(REFDIR, "cable railing #{along_axis}.skp")
  File.write(path, '') unless File.exist?(path)
  Sketchup.active_model.definitions.register!(path, his_fence(along_axis))
  FRT.new(path)
end

def build(tool, ax, ay, bx, by)
  tool.instance_variable_set(:@shape, tool.send(:read_shape!))
  tool.instance_variable_set(:@p1, Geom::Point3d.new(ax, ay, 0))
  tool.instance_variable_set(:@p2, Geom::Point3d.new(bx, by, 0))
  tool.send(:build_it, Object.new.tap { |v| def v.invalidate; true; end })
  Sketchup.active_model.entities.grep(Sketchup::Group)
          .find { |g| g.get_attribute('LandscapePro', 'type') == 'fence' }
end

def instances(g); g.entities.grep(Sketchup::ComponentInstance); end

# ------------------------------------------------------------- reading it

t = fresh(:y)
shape = t.send(:read_shape!)
ok('the file was read', !shape.nil?)
ok('it saw that his model runs along Y', shape[:run_axis] == 1, shape[:run_axis])
ok('it read it as UNIT mode - one big repeating component', shape[:mode] == :unit, shape[:mode])
ok('it found the unit - the thing that repeats', shape[:pieces][0][0].name == 'Component#2', shape[:pieces][0][0].name)
ok('it counted three of them in his model', shape[:unit_count_in_model] == 3, shape[:unit_count_in_model])
ok('it measured the unit pitch', close(shape[:unit_along], UNIT_ALONG, 1e-3), shape[:unit_along])
ok('it found the closer - the lone post at the end', shape[:closer_pieces][0] && shape[:closer_pieces][0][0].name == 'Component#38',
   shape[:closer_pieces].map { |(d, _t)| d.name })
ok('it measured the height', close(shape[:height], 45.0, 1e-6), shape[:height])

# A tool made from nothing must say so, not crash.
Sketchup.reset_model!
bad = FRT.new('/refs/nothing here.skp')
ok('a missing file reads as nil, not a crash', bad.send(:read_shape!).nil?)

# ------------------------------------------------------------- the layout

t = fresh(:y)
t.instance_variable_set(:@shape, t.send(:read_shape!))
lay = t.send(:layout_for, 3 * UNIT_ALONG)
ok('exactly three pitches -> three units, no stretch', lay[:n] == 3 && close(lay[:stretch], 1.0), lay)
lay = t.send(:layout_for, 240.0)
ok("240\" -> three units", lay[:n] == 3, lay)
ok('stretched so three fill 240 exactly', close(lay[:n] * lay[:pitch], 240.0), lay[:n] * lay[:pitch])
ok('and the stretch is small', (lay[:stretch] - 1.0).abs < 0.05, lay[:stretch])
lay = t.send(:layout_for, 400.0)
ok("400\" -> five units", lay[:n] == 5, lay)
lay = t.send(:layout_for, 30.0)
ok('shorter than one unit -> one unit, squeezed', lay[:n] == 1 && lay[:stretch] < 1.0, lay)
ok('a mis-click is refused', t.send(:layout_for, 0.4).nil?)

# ------------------------------------------------------------ building it

t = fresh(:y)
g = build(t, 0, 0, 240, 0)
ok('a fence group is created', !g.nil?)
ok('it is a fence, in the LandscapePro dictionary', g.get_attribute('LandscapePro', 'type') == 'fence')
ok('it says it came from his file', g.get_attribute('LandscapePro', 'reference') == 'cable railing y')
ok('kind = reference, so nothing mistakes it for the parametric one',
   g.get_attribute('LandscapePro', 'kind') == 'reference')
ok('BOTH ground numbers are stored', g.get_attribute('LandscapePro', 'ground_start') == 0.0 &&
                                     g.get_attribute('LandscapePro', 'ground_end') == 0.0)
ok('the axis magnet was called', $magnet_calls == 1, $magnet_calls)

inst = instances(g)
units   = inst.select { |i| i.definition.name == 'Component#2' }
closers = inst.select { |i| i.definition.name == 'Component#38' }
ok('three units were placed', units.length == 3, units.length)
ok('one closer was placed', closers.length == 1, closers.length)
ok('and NOTHING else - no geometry of our own', inst.length == 4 && g.entities.grep(Sketchup::Face).empty?,
   [inst.length, g.entities.grep(Sketchup::Face).length])
ok('every unit is an instance of HIS definition, the very same object',
   units.all? { |i| i.definition.equal?(t.instance_variable_get(:@shape)[:pieces][0][0]) })

# Where did they land? Push the unit's own corner (its post's origin) through.
origins = units.map { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation) }
xs = origins.map(&:x).sort
ok('the first unit starts at the first click', close(xs[0], 0.0, 1e-6), xs)
ok('the units are spaced one stretched pitch apart',
   close(xs[1] - xs[0], 240.0 / 3.0, 1e-6) && close(xs[2] - xs[1], 240.0 / 3.0, 1e-6), xs)
ok('the units sit ON the fence line (y = 0 within a post half-width)',
   origins.all? { |o| o.y.abs < 3.0 }, origins.map(&:y))
ok('the units sit on the ground', origins.all? { |o| close(o.z, 0.0) }, origins.map(&:z))

# The far end of the LAST unit is the second click.
far = Geom::Point3d.new(0, UNIT_ALONG, 0)   # in HIS model the unit runs along Y
far_world = units.map { |i| far.transform(i.transformation) }.max_by(&:x)
ok('the last unit ends at the second click', close(far_world.x, 240.0, 1e-6), far_world.x)

# The closer sits where the fourth post would be: at x = 240.
c = closers.first
c0 = Geom::Point3d.new(0, 0, 0).transform(c.transformation)
ok('the closer stands at the end of the fence', close(c0.x, 240.0, 1e-6), c0.x)
ok('the closer is NOT stretched',
   close(Geom::Point3d.new(0, POST_W, 0).transform(c.transformation).x - c0.x, POST_W, 1e-6))

# The unit IS stretched, along the run only: its post is a touch wider.
u0 = units.min_by { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation).x }
pw = Geom::Point3d.new(0, POST_W, 0).transform(u0.transformation).x -
     Geom::Point3d.new(0, 0, 0).transform(u0.transformation).x
ok('the unit post is stretched by the same factor as the bay',
   close(pw, POST_W * (240.0 / (3 * UNIT_ALONG)), 1e-6), [pw, POST_W * (240.0 / (3 * UNIT_ALONG))])
across = Geom::Point3d.new(POST_W, 0, 0).transform(u0.transformation).y -
         Geom::Point3d.new(0, 0, 0).transform(u0.transformation).y
ok('but NOT across - the fence is exactly as thick as he made it', close(across.abs, POST_W, 1e-6), across)

# ------------------------------------------------- a model that runs along X

t = fresh(:x)
g = build(t, 0, 0, 240, 0)
sh = t.instance_variable_get(:@shape)
ok('an X-running model is read as X', sh[:run_axis] == 0)
xs = instances(g).select { |i| i.definition.name == 'Component#2' }
                 .map { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation).x }.sort
ok('an X-running model lays out identically', xs.length == 3 && close(xs[0], 0.0) && close(xs[1], 80.0), xs)

# ---------------------------------------------------- along a diagonal

t = fresh(:y)
g = build(t, 0, 0, 180, 240)   # length 300 -> 4 units
inst = instances(g).select { |i| i.definition.name == 'Component#2' }
ok('a diagonal fence gets four units', inst.length == 4, inst.length)
# The unit is centred ACROSS on the line, so its post's centre - not its
# corner - is what should sit on the diagonal.
# (in the Y-running stand-in the unit is POST_W across, in local X)
mid = inst.map { |i| Geom::Point3d.new(POST_W / 2.0, 0, 0).transform(i.transformation) }
ok('and every unit CENTRE lies ON the diagonal',
   mid.all? { |p| (p.x * 240.0 - p.y * 180.0).abs < 1e-3 * 300 }, mid.map { |p| [p.x.round(2), p.y.round(2)] })
along = mid.map { |p| (p.x * 180.0 + p.y * 240.0) / 300.0 }.sort
ok('spaced 75 apart along it',
   along.each_cons(2).all? { |a, b| close(b - a, 75.0, 1e-3) }, along)

# ---------------------------------------------- PARTS mode: his second file
#
# His second cable railing was NOT unit-based: thirty loose cables, loose
# posts, loose rails, all direct children of the model. The first reader
# picked a cable as "the unit" and laid eight cables in a row - a pencil
# line (2026-08-17). This is that file, as a stand-in: posts every 30" of
# Component#11 (2.375 sq x 41.28 tall), 8 cables per bay of Component#5
# (28.4 x 0.125 x 0.125), a top rail per bay, and a closer post at the end.
def his_parts_fence
  fence = Sketchup::ComponentDefinition.new('cable railing 2')
  post  = box_def('Component#11', 0, 0, 0, 2.375, 2.375, 41.28)
  cable = box_def('Component#5',  0, 0, 0, 0.125, 28.4, 0.125)     # runs along Y
  rail  = box_def('Group#7',      0, 0, 0, 2.375, 27.6, 1.5)
  pitch = 30.0
  bays  = 4
  (0..bays).each do |i|
    fence.entities.add_instance(post, Geom::Transformation.translation(Geom::Vector3d.new(0, i * pitch, 0)))
  end
  bays.times do |i|
    y0 = i * pitch + 2.375 + 0.2                       # just past the post
    8.times do |c|
      fence.entities.add_instance(cable, Geom::Transformation.translation(Geom::Vector3d.new(1.125, y0, 8.0 + c * 4.0)))
    end
    fence.entities.add_instance(rail, Geom::Transformation.translation(Geom::Vector3d.new(0, y0 + 0.4, 39.78)))
  end
  fence
end

Sketchup.reset_model!
$magnet_calls = 0
ppath = File.join(REFDIR, 'cable railing parts.skp')
File.write(ppath, '')
Sketchup.active_model.definitions.register!(ppath, his_parts_fence)
t = FRT.new(ppath)
sh = t.send(:read_shape!)
ok('parts file: it was read at all', !sh.nil?)
ok('parts file: it is read as PARTS mode, not unit mode', sh[:mode] == :parts, sh[:mode])
ok('parts file: the cable was NOT mistaken for the unit',
   sh[:pieces].none? { |(d, _t)| d.name == 'Component#5' && sh[:pieces].length == 1 })
ok('parts file: the post is the first piece of the assembled unit',
   sh[:pieces][0][0].name == 'Component#11', sh[:pieces][0][0].name)
ok('parts file: the assembled unit holds the post, 8 cables and a rail',
   sh[:pieces].length == 10, sh[:pieces].map { |(d, _t)| d.name }.tally)
ok('parts file: the pitch is post-to-post, 30', close(sh[:unit_along], 30.0, 1e-6), sh[:unit_along])
ok('parts file: four bays were counted in his model', sh[:unit_count_in_model] == 4, sh[:unit_count_in_model])
ok('parts file: the closer is the last post', sh[:closer_pieces][0][0].name == 'Component#11')
ok('parts file: the unit is as tall as the fence', close(sh[:unit_max][2] - sh[:unit_min][2], 41.28, 1e-6),
   sh[:unit_max][2] - sh[:unit_min][2])

g = build(t, 0, 0, 240, 0)
ok('parts file: a fence was built', !g.nil?)
inst = instances(g)
posts  = inst.select { |i| i.definition.name == 'Component#11' }
cables = inst.select { |i| i.definition.name == 'Component#5' }
rails  = inst.select { |i| i.definition.name == 'Group#7' }
ok('parts file: 240" -> 8 bays -> 8 posts + 1 closer = 9 posts', posts.length == 9, posts.length)
ok('parts file: 8 cables per bay -> 64 cables', cables.length == 64, cables.length)
ok('parts file: one rail per bay -> 8 rails', rails.length == 8, rails.length)
ok('parts file: it is HIS fence, nothing of ours',
   inst.length == 9 + 64 + 8 && g.entities.grep(Sketchup::Face).empty?, inst.length)
pxs = posts.map { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation).x }.sort
ok('parts file: the posts are 30 apart, first at 0, last at 240',
   close(pxs.first, 0.0, 1e-6) && close(pxs.last, 240.0, 1e-6) &&
   pxs.each_cons(2).all? { |a, b| close(b - a, 30.0, 1e-6) }, pxs.map { |x| x.round(2) })
# A cable in bay 3 sits three pitches after the same cable in bay 0.
c0 = cables.map { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation).x }.sort
ok('parts file: the cables march along with the bays',
   close(c0[8] - c0[0], 30.0, 1e-6) && close(c0[24] - c0[0], 90.0, 1e-6), [c0[0], c0[8], c0[24]].map { |x| x.round(2) })
ok('parts file: the fence is as thick as he made it - the cable box did not become the unit box',
   (Geom::Point3d.new(2.375, 0, 0).transform(posts.first.transformation).y -
    Geom::Point3d.new(0, 0, 0).transform(posts.first.transformation).y).abs > 2.0)

# ---------------------------------------------- WHOLE mode: his third file
#
# His second cable railing turned out to be a raw model: 57 loose components
# AND 5868 loose faces straight in the definition, a post of one definition
# at the start and a post of ANOTHER definition at the end (Component#17 at
# x=0.75, Component#11 at x=180.75), the cables of only the first bay as
# components. Unit and parts mode both quietly dropped the loose faces and he
# got a skeleton (2026-08-17). So: any loose faces -> the whole definition is
# the unit, one instance per bay, and the pitch is post-to-post so the end
# post of one unit sits exactly on the start post of the next.
def his_raw_fence
  fence = Sketchup::ComponentDefinition.new('cable railing raw')
  post_a = box_def('Component#17', 0, 0, 0, 2.375, 2.375, 41.28)
  post_b = box_def('Component#11', 0, 0, 0, 2.375, 2.375, 41.28)
  fence.entities.add_instance(post_a, Geom::Transformation.translation(Geom::Vector3d.new(0.75, 0.8, 3.0)))
  fence.entities.add_instance(post_b, Geom::Transformation.translation(Geom::Vector3d.new(180.75, 0.8, 3.0)))
  # A continuous top rail and a middle post as LOOSE faces.
  fence.entities.add_face([Geom::Point3d.new(0.75, 0.5, 42.1), Geom::Point3d.new(183.1, 0.5, 42.1),
                           Geom::Point3d.new(183.1, 3.5, 45.0), Geom::Point3d.new(0.75, 3.5, 45.0)])
  fence.entities.add_face([Geom::Point3d.new(60.3, 0.8, 3.0), Geom::Point3d.new(62.7, 0.8, 3.0),
                           Geom::Point3d.new(62.7, 3.2, 44.3), Geom::Point3d.new(60.3, 3.2, 44.3)])
  # Anchor bolts BELOW the plate, so the lowest z is 1.5, not 0.
  fence.entities.add_face([Geom::Point3d.new(1.0, 1.0, 1.5), Geom::Point3d.new(1.5, 1.0, 1.5),
                           Geom::Point3d.new(1.5, 1.5, 3.0), Geom::Point3d.new(1.0, 1.5, 3.0)])
  fence
end

Sketchup.reset_model!
$magnet_calls = 0
rpath = File.join(REFDIR, 'cable railing raw.skp')
File.write(rpath, '')
Sketchup.active_model.definitions.register!(rpath, his_raw_fence)
t = FRT.new(rpath)
sh = t.send(:read_shape!)
ok('raw file: it is read at all - never "could not read a fence" again', !sh.nil?)
ok('raw file: it is read as WHOLE mode because of the loose faces', sh[:mode] == :whole, sh[:mode])
ok('raw file: it saw the loose faces', sh[:loose_faces] == 3, sh[:loose_faces])
ok('raw file: the unit is the whole definition, ONE piece',
   sh[:pieces].length == 1 && sh[:pieces][0][0].equal?(sh[:defn]), sh[:pieces].length)
ok('raw file: the pitch is post-to-post (180), not the box (182.35)',
   close(sh[:unit_along], 180.0, 1e-6), sh[:unit_along])
ok('raw file: it counted the two posts', sh[:post_count] == 2, sh[:post_count])
ok('raw file: the height includes the loose top rail', close(sh[:height], 45.0 - 1.5, 1e-6), sh[:height])

g = build(t, 0, 0, 360, 0)
ok('raw file: a fence was built', !g.nil?)
inst = instances(g)
ok('raw file: 360" -> two whole units', inst.length == 2, inst.length)
ok('raw file: both are instances of HIS whole definition',
   inst.all? { |i| i.definition.equal?(sh[:defn]) })
xs = inst.map { |i| Geom::Point3d.new(0.75, 0, 0).transform(i.transformation).x }.sort
ok('raw file: the second unit starts exactly one pitch after the first, so its start post sits ON the first end post',
   close(xs[1] - xs[0], 180.0, 1e-6), xs)
ok('raw file: the first unit starts at the click', close(xs[0], 0.0, 1e-6), xs[0])
z = Geom::Point3d.new(0, 0, 3.0).transform(inst.first.transformation).z
ok('raw file: HIS z is kept - the plate stays at 3.0, the bolts hang below ground as he drew them',
   close(z, 3.0, 1e-6), z)

# ------------------------------------------------------- one undo step

t = fresh(:y)
build(t, 0, 0, 240, 0)
ops = Sketchup.active_model.ops
ok('one fence = one undo step', ops.count { |o| o[0] == :start } == 1 && ops.count { |o| o[0] == :commit } == 1, ops)

# ------------------------------------------------------- the folder listing

ok('references lists .skp files by name (folder may be empty in the cloud)',
   FRT.references.is_a?(Array))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

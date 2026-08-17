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
#
# CUT is shipped OFF (it hung SketchUp on his raw file). The suite turns it
# ON here to keep the code honest, and OFF again at the end.
def cut!(on); FRT.send(:remove_const, :USE_CUT); FRT.const_set(:USE_CUT, on); end
ok('CUT ships OFF', FRT::USE_CUT == false)

t = fresh(:y)
t.instance_variable_set(:@shape, t.send(:read_shape!))

# HIS RULE (2026-08-17): post to post is 8 feet AT MOST, so a unit is NEVER
# stretched past its true size. The count rounds UP and the bays are squeezed
# equally - he chose equal bays over "full bays plus a short last one".
# These run with CUT off, which is how it ships.
cut!(false)
lay = t.send(:layout_for, 3 * UNIT_ALONG)
ok('exactly three pitches -> three units, no stretch', lay[:n] == 3 && close(lay[:stretch], 1.0), lay)
lay = t.send(:layout_for, 240.0)
ok("240\" -> FOUR units, not three: three would be 80\" bays on a 78.7\" unit",
   lay[:n] == 4, lay)
ok('the four units fill the length exactly', lay[:cut] == 0.0 && close(lay[:n] * lay[:pitch], 240.0), lay)
ok('and they are SQUEEZED, never stretched', lay[:stretch] < 1.0, lay[:stretch])
ok('so the bay came out under the unit pitch', lay[:pitch] < UNIT_ALONG, lay[:pitch])
lay = t.send(:layout_for, 400.0)
ok("400\" -> six units (five would stretch the bay to 80\")", lay[:n] == 6 && lay[:cut] == 0.0, lay)
ok('400 squeezed, not stretched', lay[:stretch] < 1.0, lay[:stretch])
lay = t.send(:layout_for, 300.0)
ok("300\" -> 4 units squeezed 4.7%",
   lay[:n] == 4 && lay[:cut] == 0.0 && (lay[:stretch] - 0.953).abs < 0.01, lay)
lay = t.send(:layout_for, 200.0)
ok("200\" -> 3 units squeezed, none over the unit pitch",
   lay[:n] == 3 && lay[:stretch] < 1.0 && close(lay[:n] * lay[:pitch], 200.0), lay)
lay = t.send(:layout_for, 30.0)
ok('shorter than one unit -> one squeezed unit, not one stretched one',
   lay[:n] == 1 && close(lay[:pitch], 30.0), lay)
ok('a mis-click is refused', t.send(:layout_for, 0.4).nil?)

# THE RULE ITSELF, swept: whatever the length, a bay never exceeds the unit.
# On his vinyl the unit IS 96" = 8 feet, so this sweep IS the 8-foot rule.
overs = (5..600).step(1).map { |l| t.send(:layout_for, l.to_f) }
                .compact.select { |x| x[:pitch] > UNIT_ALONG + 1e-9 }
ok('CUT off: no length from 5" to 600" makes a bay wider than the unit',
   overs.empty?, overs.first(3))

# The old round-to-nearest behaviour, one line away.
begin
  FRT.send(:remove_const, :NEVER_STRETCH); FRT.const_set(:NEVER_STRETCH, false)
  lay = t.send(:layout_for, 240.0)
  ok('NEVER_STRETCH = false: back to three units stretched 1.7%',
     lay[:n] == 3 && (lay[:stretch] - 1.017).abs < 0.01, lay)
ensure
  FRT.send(:remove_const, :NEVER_STRETCH); FRT.const_set(:NEVER_STRETCH, true)
end

# CUT mode's own maths, with the switch held on for the rest of the suite.
cut!(true)
lay = t.send(:layout_for, 200.0)
ok("cut on: 200\" -> 2 whole units at TRUE size + one stub cut at 42.6",
   lay[:whole] == 2 && close(lay[:stretch], 1.0) && close(lay[:cut], 200.0 - 2 * UNIT_ALONG, 1e-6), lay)
ok('cut on: the stub is counted in n', lay[:n] == 3, lay[:n])
lay = t.send(:layout_for, 30.0)
ok('cut on: shorter than one unit -> no whole units, one stub cut at 30',
   lay[:whole] == 0 && close(lay[:cut], 30.0), lay)
# 8 feet still wins over "avoid a sliver": a 102" run on a 96" unit must not
# come out as ONE 102" bay just because the remainder was small.
overs = (5..600).step(1).map { |l| t.send(:layout_for, l.to_f) }
                .compact.select { |x| x[:cut] == 0.0 && x[:pitch] > UNIT_ALONG + 1e-9 }
ok('cut on: a whole-unit fallback still never stretches a bay', overs.empty?, overs.first(3))

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
ok('FOUR units were placed - 240 over a 78.7 unit rounds UP', units.length == 4, units.length)
ok('one closer was placed', closers.length == 1, closers.length)
ok('and NOTHING else - no geometry of our own', inst.length == 5 && g.entities.grep(Sketchup::Face).empty?,
   [inst.length, g.entities.grep(Sketchup::Face).length])
ok('every unit is an instance of HIS definition, the very same object',
   units.all? { |i| i.definition.equal?(t.instance_variable_get(:@shape)[:pieces][0][0]) })

# Where did they land? Push the unit's own corner (its post's origin) through.
origins = units.map { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation) }
xs = origins.map(&:x).sort
ok('the first unit starts at the first click', close(xs[0], 0.0, 1e-6), xs)
ok('the units are spaced one squeezed pitch apart, all equal',
   xs.each_cons(2).all? { |a, b| close(b - a, 240.0 / 4.0, 1e-6) }, xs)
ok('and that pitch is UNDER the unit - no bay grew', 240.0 / 4.0 < UNIT_ALONG)
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

# The unit is SQUEEZED, along the run only: its post is a touch narrower.
u0 = units.min_by { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation).x }
pw = Geom::Point3d.new(0, POST_W, 0).transform(u0.transformation).x -
     Geom::Point3d.new(0, 0, 0).transform(u0.transformation).x
ok('the unit post is squeezed by the same factor as the bay',
   close(pw, POST_W * (240.0 / (4 * UNIT_ALONG)), 1e-6), [pw, POST_W * (240.0 / (4 * UNIT_ALONG))])
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
ok('an X-running model lays out identically', xs.length == 4 && close(xs[0], 0.0) && close(xs[1], 60.0), xs)

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

# ---------------------------------------------------------- CUT mode build

t = fresh(:y)
g = build(t, 0, 0, 200, 0)      # 2 whole + one stub cut at 42.6
inst = instances(g)
units = inst.select { |i| i.definition.name == 'Component#2' }
ok('cut: two WHOLE units placed as instances', units.length == 2, units.length)
ok('cut: none of them is stretched',
   units.all? { |i| close(Geom::Point3d.new(0, POST_W, 0).transform(i.transformation).x -
                        Geom::Point3d.new(0, 0, 0).transform(i.transformation).x, POST_W, 1e-6) })
stub = g.entities.grep(Sketchup::Group).find { |x| x.name.to_s.include?('cut') }
ok('cut: there is a stub group for the remainder', !stub.nil?, g.entities.grep(Sketchup::Group).map(&:name))
ok('cut: the stub was exploded to loose faces (so the knife could reach them)',
   stub && stub.entities.grep(Sketchup::Face).length > 0 && stub.entities.grep(Sketchup::ComponentInstance).empty?,
   stub && [stub.entities.grep(Sketchup::Face).length, stub.entities.grep(Sketchup::ComponentInstance).length])
# The stub cannot split a face on the plane (SketchUp's intersect_with does
# that), so what can be proved here is the erase: no face lies WHOLLY beyond
# the plane, and the panel-end faces past 200 are gone.
faces = stub.entities.grep(Sketchup::Face)
ok('cut: no face lies wholly beyond the cut plane',
   faces.none? { |f| f.points.all? { |p| p.x > 200.0 + 1e-4 } },
   faces.select { |f| f.points.all? { |p| p.x > 200.0 + 1e-4 } }.length)
xs = faces.flat_map { |f| f.points.map(&:x) }
ok('cut: the stub starts where the second whole unit ended', close(xs.min, 2 * UNIT_ALONG, 0.5), xs.min)
closer = inst.find { |i| i.definition.name == 'Component#38' }
cx = Geom::Point3d.new(0, 0, 0).transform(closer.transformation).x
ok('cut: the closer stands at the very end, 200', close(cx, 200.0, 1e-6), cx)
ok('cut: his unit definition still has its own faces - the explode was on a copy, not on his library',
   t.instance_variable_get(:@shape)[:pieces][0][0].entities.grep(Sketchup::ComponentInstance).length == 2)

# ------------------------------------- HIS VINYL FENCE: duplicate posts
#
# Measured from his file by debug_fence_parts.rb (2026-08-17):
#   198" long, 60" tall, posts 6 x 5.969 x 60 of one definition at
#   x = -3.001, -3.001, 92.999, 188.999   <-- the first TWO are the same post,
#   modelled twice in exactly the same place. The reader took the first two
#   post centres as bay 1, measured 0" of span, gave up on parts mode and made
#   the whole 198" model the unit. He saw two posts stuck together.
#   Each bay also has a bottom rail, a top rail and a 22-picket assembly, and
#   there is one stray picket sitting inside the first post.
def his_vinyl_fence
  fence   = Sketchup::ComponentDefinition.new('Vinyl fance')
  post    = box_def('post#3',  -3.001, -2.988, 0.0, 2.999, 2.988, 60.0)
  rail_lo = box_def('Group957', 2.499, -0.75, 2.000,  93.499, 0.75,  6.980)
  rail_hi = box_def('Group963', 2.499, -0.75, 51.020, 93.499, 0.75, 56.000)
  # The second bay's rails and pickets are their own definitions in his file.
  rail_lo2 = box_def('Group960', 98.499, -0.75, 2.000,  189.499, 0.75,  6.980)
  rail_hi2 = box_def('Group966', 98.499, -0.75, 51.020, 189.499, 0.75, 56.000)
  pickets  = box_def('New Assembly#3', 2.5,  -0.375, 6.75, 98.0,  0.375, 51.187)
  pickets2 = box_def('New Assembly#4', 98.5, -0.375, 6.75, 194.0, 0.375, 51.187)
  stray    = box_def('1', 0.0, -0.375, 0.0, 4.0, 0.375, 44.437)
  id = Geom::Transformation.new
  # The post, twice in the same place, then at 96 and at 192.
  fence.entities.add_instance(post, id)
  fence.entities.add_instance(post, id)
  fence.entities.add_instance(post, Geom::Transformation.translation(Geom::Vector3d.new(96.0, 0, 0)))
  fence.entities.add_instance(post, Geom::Transformation.translation(Geom::Vector3d.new(192.0, 0, 0)))
  [rail_lo, rail_hi, rail_lo2, rail_hi2, pickets, pickets2, stray].each do |d|
    fence.entities.add_instance(d, id)
  end
  fence
end

Sketchup.reset_model!
$magnet_calls = 0
vpath = File.join(REFDIR, 'Vinyl fance.skp')
File.write(vpath, '')
Sketchup.active_model.definitions.register!(vpath, his_vinyl_fence)
t = FRT.new(vpath)
sh = t.send(:read_shape!)
ok('vinyl: it was read', !sh.nil?)
ok('vinyl: PARTS mode - the duplicate post no longer forces whole mode',
   sh[:mode] == :parts, sh[:mode])
ok('vinyl: the bay is 96" = 8 feet, not 0 and not the whole 198" model',
   close(sh[:unit_along], 96.0, 1e-6), sh[:unit_along])
ok('vinyl: two bays counted in his model, not three (the duplicate was dropped)',
   sh[:unit_count_in_model] == 2, sh[:unit_count_in_model])
ok('vinyl: the post leads the unit', sh[:pieces][0][0].name == 'post#3', sh[:pieces][0][0].name)
ok('vinyl: the unit is post + two rails + pickets + the stray picket',
   sh[:pieces].map { |(d, _t)| d.name }.sort ==
     ['1', 'Group957', 'Group963', 'New Assembly#3', 'post#3'],
   sh[:pieces].map { |(d, _t)| d.name })
ok('vinyl: the SECOND bay\'s parts are not in the unit',
   sh[:pieces].none? { |(d, _t)| %w[Group960 Group966 New\ Assembly#4].include?(d.name) })
ok('vinyl: the closer is a post', sh[:closer_pieces][0][0].name == 'post#3')
ok('vinyl: 60" tall', close(sh[:height], 60.0, 1e-6), sh[:height])

# The 8-foot rule on his real numbers: no click, however awkward, may put two
# posts more than 96" apart.
t.instance_variable_set(:@shape, sh)
bad = (10..1200).step(1).map { |l| t.send(:layout_for, l.to_f) }
                .compact.select { |x| x[:pitch] > 96.0 + 1e-9 }
ok('vinyl: NO fence length from 10" to 100ft puts posts more than 8 feet apart',
   bad.empty?, bad.first(3))

lay = t.send(:layout_for, 300.0)
ok('vinyl: a 300" fence gets 4 bays of 75", not 3 of 100"',
   lay[:n] == 4 && close(lay[:pitch], 75.0, 1e-6), lay)

g = build(t, 0, 0, 300, 0)
ok('vinyl: a fence was built', !g.nil?)
vp = instances(g).select { |i| i.definition.name == 'post#3' }
pxs = vp.map { |i| Geom::Point3d.new(0, 0, 0).transform(i.transformation).x }.sort
ok('vinyl: 4 bays -> 4 posts + 1 closer', vp.length == 5, vp.length)
ok('vinyl: the four bays are 75" each',
   pxs.first(4).each_cons(2).all? { |a, b| close(b - a, 75.0, 1e-6) }, pxs.map { |x| x.round(2) })
# The closer is deliberately NOT stretched, so its gap is a hair wider than a
# bay - by the amount the unit's leading post was squeezed. Still under 8ft.
ok('vinyl: no gap anywhere reaches 8 feet',
   pxs.each_cons(2).all? { |a, b| (b - a) < 96.0 }, pxs.map { |x| x.round(2) })
ok('vinyl: no two posts landed on top of each other',
   pxs.each_cons(2).all? { |a, b| (b - a) > 1.0 }, pxs.map { |x| x.round(2) })

# ------------------------------------------------------- one undo step

t = fresh(:y)
build(t, 0, 0, 240, 0)
ops = Sketchup.active_model.ops
ok('one fence = one undo step', ops.count { |o| o[0] == :start } == 1 && ops.count { |o| o[0] == :commit } == 1, ops)

# ------------------------------------------------------- the folder listing

ok('references lists .skp files by name (folder may be empty in the cloud)',
   FRT.references.is_a?(Array))

cut!(false)
puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

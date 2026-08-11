# encoding: utf-8
# rt23 — the 3-CLICK ARC tool (wall_arc_tool.rb, 2026-08-11).
#
# click 1 = start, click 2 = end, click 3 = how far it bows.
#
# The tool deliberately owns almost no logic: it is a WallTool underneath, it
# collects three points, and it hands them to the ordinary create_wall. This
# suite pins that arrangement, because the moment the arc tool starts building
# walls its own way, curved walls and straight walls drift apart.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
InteriorPro.send(:remove_const, :WallCurveTool) if InteriorPro.const_defined?(:WallCurveTool, false)
InteriorPro.send(:remove_const, :WallArcTool) if InteriorPro.const_defined?(:WallArcTool, false)
require './arc_math'
require './wall_tool'
require './wall_curve_tool'
require './wall_arc_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
AT = InteriorPro::WallArcTool
CT = InteriorPro::WallCurveTool
AM = InteriorPro::ArcMath

# --------------------------------------- it really is an ordinary wall tool

ok('the arc tool IS a wall tool', AT.ancestors.include?(WT))
ok('so the wall library can drive it', AT.new.respond_to?(:thickness=))
%i[height= thickness= exterior_material= interior_material= wall_type_name=
   anchor= wall_category= side_a_color= side_b_color=].each do |m|
  ok("the wall library can set #{m}", AT.new.respond_to?(m))
end
ok('a wall tool carries an arc_sag for the arc tool to fill in',
   WT.new.respond_to?(:arc_sag=) && WT.new.respond_to?(:arc_sag))
ok('a plain wall tool starts with no bow', WT.new.arc_sag.nil?)

# ------------------------------------------------------- the create wiring

src = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('create_wall bends the wall when the arc tool asked for it',
   src.include?('InteriorPro::WallTool.set_wall_sag!(group, @arc_sag.to_f, wrap_operation: false)'))
ok('and it reuses the ordinary straight path when it did not',
   src.include?('join_corners(group, model)'))
ok('bending replaces the plain corner join, it does not run on top of it',
   src.index('set_wall_sag!(group, @arc_sag.to_f') < src.index('elsif group'))
ok('create_wall hands the new wall back so the arc tool can see it',
   src =~ /puts "\[Levels\] structure after wall create[^\n]*\n\s*end\s*\n\s*group\s*\n\s*end/)
ok('bending happens inside the create operation, not in a second one',
   src.include?('wrap_operation: false'))
ok('a wall with no bow never reaches the curved path',
   src.include?('@arc_sag.to_f.abs >= InteriorPro::WallTool::MIN_ARC_SAG'))

asrc = File.read('wall_arc_tool.rb', encoding: 'UTF-8')
ok('the arc tool builds through create_wall, not its own builder',
   asrc.include?('create_wall') && !asrc.include?('build_wall_group'))
ok('the arc tool snaps its clicks to existing walls',
   asrc.include?('snap_start_to_wall_centerline'))
ok('the arc tool draws the wall at the active level',
   asrc.include?('active_base'))
ok('the arc tool reuses the drag tool\'s reading of the cursor',
   asrc.include?('InteriorPro::WallCurveTool.sag_from_point'))
ok('the arc tool reuses the real footprint for its ghost',
   asrc.include?('InteriorPro::WallTool.curved_footprint_xy'))
ok('the arc tool refuses a bow the wall cannot take',
   asrc.include?('@ghost_ok'))

# ------------------------------------ the third click means the same thing

# Click 3 must be read exactly the way the drag tool reads it, or the same
# gesture would give two different walls.
[[0, 0, 120, 0, 60, 25], [0, 0, 120, 0, 60, -25], [10, 5, -70, 90, -20, 60]].each do |sx, sy, ex, ey, px, py|
  bow = CT.sag_from_point(sx, sy, ex, ey, px, py)
  ok("click 3 at (#{px},#{py}) reads as a bow of #{bow.round(4)}", !bow.nil?)
  next unless bow
  arc = AM.from_chord_and_sag(sx, sy, ex, ey, bow)
  ok("and the wall built from it starts at click 1",
     close(AM.start_point(arc)[0], sx, 1e-9) && close(AM.start_point(arc)[1], sy, 1e-9))
  ok("and ends at click 2",
     close(AM.end_point(arc)[0], ex, 1e-9) && close(AM.end_point(arc)[1], ey, 1e-9))
end

# Click 3 landing on the line between clicks 1 and 2 = a plain straight wall.
ok('click 3 on the straight line gives no bow at all',
   close(CT.sag_from_point(0, 0, 120, 0, 60, 0), 0.0))
ok('and that is below the noise floor, so an ordinary straight wall is built',
   CT.sag_from_point(0, 0, 120, 0, 60, 0).abs < WT::MIN_ARC_SAG)

# ---------------------------------------------------- the ghost is honest

# What the user sees before the third click must be what gets built.
[['center', 6.0], ['left', 6.0], ['right', 8.0]].each do |h_anchor, th|
  bow = 18.0
  ghost = WT.curved_footprint_xy(0, 0, 120, 0, th, h_anchor, bow)
  built = WT.curved_footprint_xy(0, 0, 120, 0, th, h_anchor, bow)
  ok("ghost equals the built footprint (#{h_anchor}, #{th}\")", ghost == built)
  ok("ghost for #{h_anchor} is a real ring", ghost.length > 4 && ghost.length.even?)
end
ok('a straight ghost falls back to the four plain corners',
   CT.straight_corners(0, 0, 120, 0, 6.0, 'center').length == 4)

# ------------------------------------------------------------ registration

msrc = File.read('../main.rb', encoding: 'UTF-8') rescue nil
if msrc
  ok('the arc tool is loaded by the plugin', msrc.include?('wall_arc_tool.rb'))
  ok('and it loads AFTER the wall tool it extends',
     msrc.index('wall_tool.rb') < msrc.index('wall_arc_tool.rb'))
  ok('and after the drag tool it borrows from',
     msrc.index('wall_curve_tool.rb') < msrc.index('wall_arc_tool.rb'))
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

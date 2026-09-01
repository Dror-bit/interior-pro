# encoding: utf-8
# rt138 - 3D SIDING IS MEASURED IN THE WALL'S OWN SPACE (2026-09-12).
#
# WHY
# MEASURED on his model (gable_siding_report.txt, 2026-09-12):
#   wall 8479bf36  ext="Board and Batten"  base_z=106  height=96
#   bounds z 106..308        <- it should end at 202
# 308 = 202 + 106: the battens were built one whole storey too high, and
# they came out through the roof as thin sticks (his photo).
#
# THE CAUSE: `group.bounds` is in the PARENT's coordinates, and every
# board is built in the group's OWN. set_wall_base! translates an upper
# storey wall by the storey height, so the two differ by exactly that.
# A ground floor wall has base_z 0, the two are equal, and this sat in the
# code unnoticed since the day upper storeys arrived.
#
# SECOND HALF OF THE SAME BUG: the old boards are part of the group, so
# measuring before taking them off measured the wall PLUS yesterday's
# boards - every rebuild grew the wall again.
#
# WHAT IS PINNED HERE
# 1. The pure rule: the range is the bounds MINUS the group's own origin.
# 2. A ground floor wall is completely unaffected (origin 0).
# 3. Both builders use it, and both clear the old boards BEFORE measuring.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

WT = InteriorPro::WallTool

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}#{extra.nil? ? '' : "   << #{extra.inspect}"}"
    FAILS << name
  end
end

# --- 1. the ground floor wall: nothing changes ------------------------
ok('a ground floor 106" wall measures 0..106',
   WT.siding_z_range(0.0, 106.0, 0.0) == [0.0, 106.0],
   WT.siding_z_range(0.0, 106.0, 0.0))

# --- 2. HIS WALL: 96" tall, standing on 106" --------------------------
r = WT.siding_z_range(106.0, 202.0, 106.0)
ok('THE BUG: an upper storey wall measures 0..96, not 106..202',
   r == [0.0, 96.0], r)
ok('...so the boards are 96 tall, not 202', (r[1] - r[0] - 96.0).abs < 1e-9, r)

# --- 3. a wall on the third storey -----------------------------------
ok('a third storey wall measures its own height too',
   WT.siding_z_range(202.0, 298.0, 202.0) == [0.0, 96.0],
   WT.siding_z_range(202.0, 298.0, 202.0))

# --- 4. both builders use it, and clear the old boards first ----------
src = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('the rule is used, not group.bounds.min.z',
   src.scan(/local_z_range\(group\)/).length >= 2,
   src.scan(/local_z_range\(group\)/).length)
ok('no builder reads the raw world bounds any more',
   !src.include?('z_min = group.bounds.min.z'), nil)
ok('yesterday boards come off BEFORE the wall is measured',
   src.scan(/clear_siding!\(group\)\n\s+z_min, z_max = InteriorPro::WallTool\.local_z_range/).length >= 2,
   src.scan(/clear_siding!\(group\)/).length)
ok('clear_siding! really erases the siding group',
   src =~ /def clear_siding!.*?g\.erase! if g\.valid\? && g\.name == SIDING_GROUP_NAME/m, nil)

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

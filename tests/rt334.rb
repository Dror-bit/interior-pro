# encoding: utf-8
# rt334 - the snap lines are cut down to the room once, not walked 170k at a time for every wall (2026-10-18).
# His "יש דרך לקצר?". Measured: snap_time2_report - 170,557 edges, side_segs 1.1..2.1 s a wall.
require './sketchup_stub'
require './elevation_tool'
$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
P = Geom::Point3d
poly = [P.new(0, 0, 0), P.new(100, 0, 0), P.new(100, 80, 0), P.new(0, 80, 0)]
e_in     = [P.new(10, 10, 5), P.new(50, 10, 60)]       # in the room
e_cut    = [P.new(-40, 20, 5), P.new(-40, 20, 70)]     # 40 outside, within reach 48 + margin
e_far    = [P.new(-200, 20, 5), P.new(-200, 20, 70)]   # far away (the next room's fixture)
e_long   = [P.new(-500, 40, 5), P.new(500, 40, 5)]     # crosses the room: one end far, still touches
e_high   = [P.new(10, 10, 200), P.new(50, 10, 220)]    # above the ceiling
e_below  = [P.new(10, 10, -30), P.new(50, 10, -20)]    # the storey below
all = [e_in, e_cut, e_far, e_long, e_high, e_below]
ok('the switch is OFF by default (measured 20:35: it saved nothing)', !ET::USE_SNAP_NEAR)
ET.send(:remove_const, :USE_SNAP_NEAR); ET.const_set(:USE_SNAP_NEAR, true)
near = ET.near_room(all, poly, 0.0, 96.0, 48.0)
ok('in the room: kept', near.include?(e_in))
ok('within the cut outside the outline: kept', near.include?(e_cut))
ok('far away: gone', !near.include?(e_far))
ok('a long line through the room: kept', near.include?(e_long))
ok('above the ceiling: gone', !near.include?(e_high))
ok('the storey below: gone', !near.include?(e_below))
ok('switched off = everything, untouched', (ET.const_defined?(:USE_SNAP_NEAR) && ET.near_room(all, nil, 0, 96, 48).equal?(all)))
# the same lines come out of side_segs either way
north = ET::Side.new('North', P.new(100, 80, 0), P.new(0, 80, 0), 100.0, Geom::Vector3d.new(0, -1, 0), 80.0) rescue nil
if north
  a = ET.side_segs(north, 48.0, 96.0, 0.0, all)
  b = ET.side_segs(north, 48.0, 96.0, 0.0, near)
  ok('side_segs gives the same lines from the cut-down list', a == b, [a.size, b.size])
end
src = File.read('./elevation_tool.rb')
ok('cut down ONCE a room (near_edges.nil?)', src.include?('near_edges = near_room(snap_edges, poly, base_z, wall_h,') && src.include?('if near_edges.nil?'))
ok('and side_segs reads the cut-down list', src.include?('segs = side_segs(side, s[:cut], wall_h, base_z, near_edges)'))
ok('the reach is the deepest cut of the room', src.include?('snap_reach = capture_sides.map'))
puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

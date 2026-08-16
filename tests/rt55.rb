# encoding: utf-8
# rt55 - the axis magnet (2026-08-14).
#
# He drew a building at 179.7666 degrees. Four perfect 90 corners, the label
# said a round 180, and the whole plan sat a quarter of a degree off the axes:
# two inches over forty-one feet. He found it by eye, days later, after the
# floors had already inherited it.
#
# His instruction, in his words: "fix everything so it does not happen again."
#
# So a wall within one degree of an axis now lands ON the axis, at the moment
# it is built - in build_wall_group, the one door every wall comes through.
#
# The dangerous half is the half this file spends most of its time on: a wall
# whose end is already sitting on another wall's end must NOT be swung, or the
# corner tears open. That is the failure this would cause if it were written
# carelessly, and it would show up as a gap in his rooms, not as an error.

require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}   << #{extra.inspect}"
    FAILS << name
  end
end

WT = InteriorPro::WallTool

def pt(x, y, z = 0)
  Geom::Point3d.new(x, y, z)
end

def bearing(a, b)
  Math.atan2(b.y - a.y, b.x - a.x) * 180.0 / Math::PI
end

def off(a, b)
  o = bearing(a, b) % 90.0
  o -= 90.0 if o > 45.0
  o
end

# ------------------------------------------------------- the numbers he had
puts '-- his building --'

# 491" at 179.7666 degrees - the long exterior wall, measured from his model
ang = 179.7666 * Math::PI / 180.0
s = pt(0, 0)
e = pt(491 * Math.cos(ang), 491 * Math.sin(ang))
ok('his wall really is off the axis to begin with', off(s, e).abs > 0.2, off(s, e))

s2, e2 = WT.apply_axis_magnet(s, e, nil)
ok('the magnet lands it exactly on the axis', off(s2, e2).abs < 1.0e-9, off(s2, e2))
ok('the pinned end did not move', s2.x == s.x && s2.y == s.y, [s2.x, s2.y])
ok('the wall keeps its length',
   (Math.hypot(e2.x - s2.x, e2.y - s2.y) - 491).abs < 1.0e-6,
   Math.hypot(e2.x - s2.x, e2.y - s2.y))
ok('and the far end moved about two inches, which is the drift he saw',
   (Math.hypot(e2.x - e.x, e2.y - e.y) - 2.0).abs < 0.1,
   Math.hypot(e2.x - e.x, e2.y - e.y))

# the 322" wall at 89.7666 - the other pair
ang2 = 89.7666 * Math::PI / 180.0
s3 = pt(100, 50)
e3 = pt(100 + 322 * Math.cos(ang2), 50 + 322 * Math.sin(ang2))
a3, b3 = WT.apply_axis_magnet(s3, e3, nil)
ok('his other wall lands on the axis too', off(a3, b3).abs < 1.0e-9, off(a3, b3))

# ------------------------------------------------- what it must NOT touch
puts
puts '-- what it leaves alone --'

[['30 degrees', 30.0], ['45 degrees', 45.0], ['60 degrees', 60.0],
 ['22.5 degrees', 22.5], ['15 degrees', 15.0], ['5 degrees', 5.0],
 ['1.5 degrees', 1.5]].each do |name, deg|
  r = deg * Math::PI / 180.0
  a = pt(0, 0)
  b = pt(200 * Math.cos(r), 200 * Math.sin(r))
  x, y = WT.apply_axis_magnet(a, b, nil)
  ok("a wall drawn at #{name} is left exactly as drawn",
     x.x == a.x && x.y == a.y && (y.x - b.x).abs < 1.0e-9 && (y.y - b.y).abs < 1.0e-9,
     [b.x, b.y, y.x, y.y])
end

# right on the edge of the window
[[0.999, true], [1.001, false]].each do |deg, should_move|
  r = deg * Math::PI / 180.0
  a = pt(0, 0)
  b = pt(300 * Math.cos(r), 300 * Math.sin(r))
  _, y = WT.apply_axis_magnet(a, b, nil)
  moved = (y.y - b.y).abs > 1.0e-9
  ok("#{deg} degrees #{should_move ? 'is caught' : 'is left alone'}",
     moved == should_move, [deg, moved])
end

# a wall that is already perfect must come back bit for bit
[[0, 0, 240, 0], [0, 0, 0, 240], [0, 0, -240, 0], [50, 50, 50, -190]].each do |x1, y1, x2, y2|
  a = pt(x1, y1)
  b = pt(x2, y2)
  u, v = WT.apply_axis_magnet(a, b, nil)
  ok("a wall already on the axis (#{x1},#{y1})-(#{x2},#{y2}) is untouched",
     u.x == a.x && u.y == a.y && v.x == b.x && v.y == b.y, [v.x, v.y])
end

# a wall too short to have a direction must not blow up
z1, z2 = WT.apply_axis_magnet(pt(0, 0), pt(0.0001, 0), nil)
ok('a wall with no length is handed straight back', z1 && z2)

# ----------------------------------------- the corner it must not tear open
puts
puts '-- the corner it must not tear open --'

ok('off_axis_deg reads a quarter turn as zero', WT.off_axis_deg(0, 100).abs < 1.0e-12)
ok('off_axis_deg is signed - it says WHICH way',
   WT.off_axis_deg(1000, 4) > 0 && WT.off_axis_deg(1000, -4) < 0,
   [WT.off_axis_deg(1000, 4), WT.off_axis_deg(1000, -4)])
ok('off_axis_deg never claims more than 45',
   (0..359).all? { |d| r = d * Math::PI / 180.0
                       WT.off_axis_deg(Math.cos(r), Math.sin(r)).abs <= 45.0 + 1.0e-9 })

src = File.read(File.join(__dir__, 'wall_tool.rb'), encoding: 'UTF-8')
mag = src[/def self\.apply_axis_magnet.*?\n    end/m].to_s
ok('the magnet asks whether each end is pinned before it swings anything',
   mag.include?('end_is_pinned?(start_pt') && mag.include?('end_is_pinned?(end_pt'),
   mag[0, 300])
ok('with BOTH ends pinned it refuses to touch the wall at all',
   /return \[start_pt, end_pt\] if start_pinned && end_pinned/.match?(mag))
ok('with the END pinned it swings the START instead, so the corner holds',
   /if end_pinned/.match?(mag) && mag.include?('# swing the START about the pinned end'))
ok('a pin is judged within an inch, the same tolerance the corner code uses',
   /AXIS_PIN_TOL\s*=\s*1\.0/.match?(src))
ok('the window is one degree, nowhere near 15 / 30 / 45',
   /AXIS_MAGNET_DEG\s*=\s*1\.0/.match?(src))
ok('a broken model can never stop a wall being built',
   /rescue StandardError\n      false      # never let the magnet stop a wall from being built/.match?(src))

# ------------------------------------------ ACCESSIBILITY - is it reached?
puts
puts '-- is it actually reached? --'

bwg = src[/def build_wall_group.*?\n      len = Math\.sqrt/m].to_s
ok('build_wall_group calls the magnet',
   bwg.include?('InteriorPro::WallTool.apply_axis_magnet(start_pt, end_pt, model)'),
   bwg[0, 400])
ok('and it calls it BEFORE any number is worked out from the two points',
   bwg.index('apply_axis_magnet') < bwg.index('dx = end_pt.x - start_pt.x'),
   [bwg.index('apply_axis_magnet'), bwg.index('dx = end_pt.x')])
ok('the SketchUp wall tool reaches build_wall_group through create_wall',
   /def create_wall.*?build_wall_group\(@start_point, @end_point, attrs, model\)/m.match?(src))

ed = File.join(__dir__, 'plan_editor.rb')
if File.exist?(ed)
  esrc = File.read(ed, encoding: 'UTF-8')
  ok('and Apply to Model in the 2D editor comes through the same door',
     esrc.include?('wt.build_wall_group(s, e, attrs, model)'),
     'the editor builds walls some other way now')
else
  puts 'SKIP  plan_editor.rb not copied in'
end

puts
if FAILS.empty?
  puts 'ALL PASS'
  exit 0
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

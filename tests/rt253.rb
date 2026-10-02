# encoding: utf-8
# rt253 - THE OPENING IN THE CORNER IS CLOSED (2026-10-02, hip into hip).
#
# His picture: a small white opening where the end of the house roof meets the
# garage roof's back line. Measured (corner_hole_report.txt): it was a HOLE IN
# THE GARAGE ROOF - a triangle (-134.5,464.5) (-151.5,481.5) (-134,481.5) cut
# out of its east slope, the house's white eave boards showing through.
# valley_inside_regions cuts the low roof back wherever it lies under the
# plane of the taller roof that faces it - and on a hip house that plane,
# carried on past its rib, is higher than the roof that really stands there
# (the house's east slope, 2.9" BELOW the garage).
#
# Pinned: the low roof is cut only under the taller roof's own face; where it
# ends on its abut line standing over the other slope, the slit is closed;
# a gable house is untouched; the kill switch.
ENV['REAL_ROOMS'] = '1'
require 'stringio'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager
def set_const(name, val)
  RF.send(:remove_const, name) if RF.const_defined?(name, false)
  RF.const_set(name, val)
end
set_const(:USE_ROOF_VALLEY, true)
ok('the code is loaded', RF.respond_to?(:valley_abut_steps) && RF.respond_to?(:valley_abut_risers!))

# ---- 1. the pure rule: the step on the abut line, on HIS numbers ---------------
GAR = { pts: [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]],
        slope: 0.25, deck_z: 81.0, ridge_z: 116.5, gables: [0], level: 1 }.freeze
HOUSE = { pts: [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]],
          slope: 0.25, deck_z: 99.0, ridge_z: 145.25, gables: [], level: 1 }.freeze
if RF.respond_to?(:valley_abut_steps)
  lw = RF.edge_plane(GAR, 2)
  le = RF.edge_plane(GAR, 4)
  hs = RF.edge_plane(HOUSE, 1)
  he = RF.edge_plane(HOUSE, 2)
  abut = [[-146.0, 481.5], [-1.0, 0.0]]
  st = RF.valley_abut_steps(lw, le, hs, RF.valley_other_planes(HOUSE, 1), abut, 188.5)
  ok('a hip house: ONE stretch - the garage\'s east slope over the house\'s east slope',
     st.length == 1 && st[0][0] == le && st[0][1] == he, st.map { |x| x[2, 2] })
  ok('...from the end of the abut line (x -146) to where the house\'s rib crosses it (x -163)',
     st[0] && st[0][2, 2].map { |q| q.map { |v| v.round(2) } }.sort == [[-163.0, 481.5], [-146.0, 481.5]], st[0] && st[0][2, 2])
  ok('a gable house: no other slope reaches the abut line - nothing',
     RF.valley_abut_steps(lw, le, hs, RF.valley_other_planes(HOUSE.merge(gables: [0, 2]), 1), abut, 188.5) == [])
  ok('no other planes handed in: nothing', RF.valley_abut_steps(lw, le, hs, [], abut, 188.5) == [])
end

# ---- 2. the real path, on his walls ----------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'], ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'], ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'], ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'], ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'], ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'], ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def build(style)
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  old = $stdout
  $stdout = StringIO.new
  begin
    RF.build_roof!(level: 1, style: style, pitch: 3.0, soffit: 'boxed')
    log = $stdout.string
  ensure
    $stdout = old
  end
  g = RF.roof_of_wall_id('gS')
  # the garage is the SECOND roof built: its own lines are the ones after the house's first "over level" line
  glog = log.split(/over level 1: eave 104[^\n]*\n/)[1].to_s
  [glog, g ? g.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } } : []]
end
def has?(fs, pts); fs.any? { |f| f.sort == pts.sort }; end

log, fs = build('hip')
ok('hip into hip: the garage is cut back on ONE side only - the west, under the house\'s south slope',
   log =~ /valley: 1 region\(s\) cut off on the meeting line/, log.lines.grep(/region/))
ok('...and the slit on the abut line is closed with one face', log =~ /valley: 1 step face\(s\) on the abut line/, log.lines.grep(/step face/))
ok('that face: from the garage\'s deck down to the house\'s top skin, x -163 to the end of the abut line',
   has?(fs, [[-148.5, 481.5, 107.5], [-163.0, 481.5, 111.12], [-163.0, 481.5, 108.77], [-148.5, 481.5, 105.14]]),
   fs.select { |f| f.all? { |p| (p[1] - 481.5).abs < 0.01 } && f.any? { |p| (p[0] + 163.0).abs < 0.01 } })

lg, = build('gable')
ok('gable into gable: both sides are cut back on the valley, as before', lg =~ /valley: 2 region\(s\) cut off on the meeting line/,
   lg.lines.grep(/region/))
ok('...and no step face is built anywhere', lg !~ /step face/, lg.lines.grep(/step face/))

# ---- 3. the kill switch -------------------------------------------------------------
set_const(:USE_VALLEY_HIP_CARRY, false)
lk, = build('hip')
ok('kill switch: the east side is cut back again, and no step face',
   lk =~ /valley: 2 region\(s\) cut off on the meeting line/ && lk !~ /step face/, lk.lines.grep(/region|step/))
set_const(:USE_VALLEY_HIP_CARRY, true)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

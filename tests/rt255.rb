# encoding: utf-8
# rt255 - THE RIB CAP STARTS WHERE THE LOWER ROOF'S RIDGE ARRIVES (2026-10-02).
#
# His picture, hip into hip: a green line from the garage's ridge on up the
# house's corner rib - "the ridge cap has to carry on with the green line" -
# and a red triangle below it - "there the shingles have to lie nicely, not the
# way it looks now". The garage's ridge reaches the house's rib at (-192.5, 511);
# from there DOWN to the house's corner the garage's slope lies on the rib, but
# the house laid its hip caps the whole way down, across a surface that is flat.
#
# Pinned: the point is found; the cap line is cut there and the lower half is
# dropped; a gable house loses nothing; the kill switch.
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
ok('the code is loaded', RF.respond_to?(:valley_cap_trims) && RF.respond_to?(:valley_trim_cap_lines) && RF.respond_to?(:valley_ridge_pair))

# ---- 1. the pure rules, on HIS numbers (the garage already set 2.875" lower) -----
GAR = { pts: [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]],
        slope: 0.25, deck_z: 78.125, ridge_z: 113.625, gables: [0], level: 1 }.freeze
HOUSE = { pts: [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]],
          slope: 0.25, deck_z: 99.0, ridge_z: 145.25, gables: [], level: 1 }.freeze
if RF.respond_to?(:valley_ridge_pair)
  w = RF.edge_plane(GAR, 2)
  e = RF.edge_plane(GAR, 4)
  ok('a hip garage has two facing pairs; the one whose ridge runs INTO the house\'s south eave is west + east',
     RF.valley_ridge_pair(GAR, [1.0, 0.0]) == [w, e], RF.valley_ridge_pair(GAR, [1.0, 0.0]))
  turned = GAR.merge(pts: GAR[:pts].rotate(2), gables: [3])
  ok('...whatever corner the outline happens to start on',
     RF.valley_ridge_pair(turned, [1.0, 0.0]) == [RF.edge_plane(turned, 0), RF.edge_plane(turned, 2)], RF.valley_ridge_pair(turned, [1.0, 0.0]))
  hs = RF.edge_plane(HOUSE, 1)
  he = RF.edge_plane(HOUSE, 2)
  rib = RF.planes_meet(hs, he)
  trim = { j: [-192.5, 511.0], rib: rib, lo: [w, e], hp: hs }
  sides = [[1.0, -0.2], [-1.0, -0.2]]
  line = [[-319.0, 637.5], 145.77, [-134.0, 452.5], 99.52, sides]            # the house's whole corner rib, top skin
  far = [[-564.0, 637.5], 145.77, [-319.0, 637.5], 145.77, sides]            # its ridge
  got = RF.valley_trim_cap_lines([line, far], [trim])
  ok('the ridge is not on that rib: untouched', got.include?(far))
  kept = got - [far]
  ok('the rib is cut at (-192.5, 511) and only the UPPER half is left',
     kept.length == 1 && kept[0][0] == [-319.0, 637.5] && kept[0][2] == [-192.5, 511.0], kept.map { |l| [l[0], l[2]] })
  ok('...at the height the rib has there (114.14 on the top skin)', kept[0] && (kept[0][3] - 114.145).abs < 0.01, kept[0] && kept[0][3])
  ok('...with its two sides as they were', kept[0] && kept[0][4] == sides)
  low_only = [[-134.0, 452.5], 99.52, [-160.0, 478.5], 106.02, sides]
  ok('a line that lies wholly on the taken-over stretch goes whole', RF.valley_trim_cap_lines([low_only], [trim]) == [])
  ok('nothing to trim: the lines come back as they were', RF.valley_trim_cap_lines([line, far], []) == [line, far])
  high = { j: [-192.5, 511.0], rib: rib, lo: [RF.edge_plane(GAR.merge(deck_z: 81.0), 2), RF.edge_plane(GAR.merge(deck_z: 81.0), 4)], hp: hs }
  ok('the garage standing 2.9" OVER the rib (it could not come down): the same cut',
     (RF.valley_trim_cap_lines([line], [high]).map { |l| [l[0], l[2]] }) == [[[-319.0, 637.5], [-192.5, 511.0]]])
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
  h = RF.roof_of_wall_id('h2')
  [log, h ? h.entities.grep(Sketchup::Group).count { |g| g.name.to_s =~ /RidgeCap/ } : 0]
end

log, caps = build('hip')
ok('hip into hip: the house says it left 83" of rib cap off (the corner to where the garage\'s ridge arrives)',
   log =~ /valley: 83" of rib cap left off/, log.lines.grep(/rib cap/))
set_const(:USE_VALLEY_CAP_TRIM, false)
lk, caps_all = build('hip')
ok('kill switch: nothing is left off', lk !~ /rib cap left off/, lk.lines.grep(/rib cap/))
ok('...and the house then carries more cap pieces than with the trim', caps_all > caps && caps > 0, [caps_all, caps])
set_const(:USE_VALLEY_CAP_TRIM, true)
set_const(:USE_VALLEY_FLUSH, false)
ln, = build('hip')
ok('the garage NOT brought down (a step on the rib): the same stretch is left off', ln =~ /valley: 83" of rib cap left off/, ln.lines.grep(/rib cap/))
set_const(:USE_VALLEY_FLUSH, true)
lg, = build('gable')
ok('gable into gable: the house has no rib there - nothing is left off', lg !~ /rib cap left off/, lg.lines.grep(/rib cap/))

# ---- 3. the two caps are ONE line: they meet as a junction (2026-10-02) ----------
# He looked at the trimmed rib: "much better, but the garage's ridge cap has to be
# CONNECTED to the roof's ridge cap". Two roofs are two calls of the cap builder;
# each saw its line end in mid air - the garage's cap ended square at the point and
# the house's rib cap took the pinched end a hip has at an eave. An end that meets
# another roof's cap is named now, and gets what every Y on a hip roof gets: the
# level ridge runs half a cap past the point, the rib stops short under it.
def cap_pts(roof)
  roof.entities.grep(Sketchup::Group).select { |c| c.name.to_s =~ /RidgeCap/ }
      .flat_map { |c| c.entities.grep(Sketchup::Face).flat_map { |f| f.points.map { |p| [p.x.to_f, p.y.to_f, p.z.to_f] } } }
end
def build2(style)
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
  ensure
    $stdout = old
  end
  [RF.roof_of_wall_id('h2'), RF.roof_of_wall_id('gS')]
end
J = [-192.5, 511.0].freeze
dist = lambda { |p| Math.hypot(p[0] - J[0], p[1] - J[1]) }
h, g = build2('hip')
gp = cap_pts(g)
hp2 = cap_pts(h)
ok('the garage\'s ridge cap RUNS past the point where it meets the rib: half a cap (6") further up',
   (gp.map { |p| p[1] }.max - 517.0).abs < 0.1, gp.map { |p| p[1] }.max)
near = hp2.select { |p| dist.call(p) < 20.0 }
ok('the house\'s rib cap stops 2" short of that point, under it', near.any? && (near.map { |p| dist.call(p) }.min - 2.0).abs < 0.3,
   near.map { |p| dist.call(p) }.min)
# its first piece is FULL width there - not the pinched end an eave corner gets:
# across the rib (the direction (1,1)/sqrt2 in plan) the piece spans the whole cap
along = lambda { |p| (-(p[0] - J[0]) + (p[1] - J[1])) / Math.sqrt(2.0) }
across = near.select { |p| along.call(p) > 1.5 && along.call(p) < 3.0 }.map { |p| (p[0] + p[1]) / Math.sqrt(2.0) }
ok('...and its end there is cut full width, not pinched to a point', across.any? && across.max - across.min > 10.0, across.any? && (across.max - across.min))
set_const(:USE_VALLEY_CAP_TRIM, false)
h0, g0 = build2('hip')
ok('kill switch: the garage\'s cap ends ON the point again', (cap_pts(g0).map { |p| p[1] }.max - 511.0).abs < 0.1, cap_pts(g0).map { |p| p[1] }.max)
set_const(:USE_VALLEY_CAP_TRIM, true)
hg, gg = build2('gable')
ok('gable into gable: the garage\'s carried cap ends on the apex, as before', (cap_pts(gg).map { |p| p[1] }.max - 522.5).abs < 0.1, cap_pts(gg).map { |p| p[1] }.max)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt254 - THE LOW ROOF COMES DOWN TO THE TALLER ROOF'S SLOPE (2026-10-02).
#
# Hip into hip on his Aetna model: the garage's east slope ran parallel to the
# house's east slope, 2.9" above it (his wall heights: the garage is 83.5" wider
# and 18" lower; one surface wants 20.9"). Carried on to the house's rib it left
# a step along it. He looked at it: "it does not work like this, the slope of
# the roof has to come down" - and "it lowers by itself".
#
# Pinned: the drop is the 2.875" between the two parallel planes; it is never
# more than the heel; the roof built is that much lower and meets the taller
# roof with no step; gable into gable is not moved; the kill switch.
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
ok('the code is loaded', RF.respond_to?(:valley_flush_drop) && RF.respond_to?(:valley_flush_drop_for) &&
                         RF.const_defined?(:USE_VALLEY_FLUSH, false))

# ---- 1. the pure rule, on HIS numbers ------------------------------------------
GAR = { pts: [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]],
        slope: 0.25, deck_z: 81.0, ridge_z: 116.5, gables: [0], level: 1 }.freeze
HOUSE = { pts: [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]],
          slope: 0.25, deck_z: 99.0, ridge_z: 145.25, gables: [], level: 1 }.freeze
if RF.respond_to?(:valley_flush_drop)
  lw = RF.edge_plane(GAR, 2)
  le = RF.edge_plane(GAR, 4)
  hs = RF.edge_plane(HOUSE, 1)
  oth = RF.valley_other_planes(HOUSE, 1)
  abut = [[-146.0, 481.5], [-1.0, 0.0]]
  d = RF.valley_flush_drop(lw, le, hs, oth, abut, 188.5, 6.0)
  ok('his two roofs on Hip: the garage comes down 2.875"', (d - 2.875).abs < 0.001, d)
  ok('a heel of 2" cannot give 2.875": the roof stays where it is', RF.valley_flush_drop(lw, le, hs, oth, abut, 188.5, 2.0) == 0.0)
  ok('a gable house has no slope parallel to the garage\'s: nothing',
     RF.valley_flush_drop(lw, le, hs, RF.valley_other_planes(HOUSE.merge(gables: [0, 2]), 1), abut, 188.5, 6.0) == 0.0)
  # once it is down, the two planes are one and nothing more is asked
  low = GAR.merge(deck_z: 81.0 - 2.875)
  ok('already down: nothing more', RF.valley_flush_drop(RF.edge_plane(low, 2), RF.edge_plane(low, 4), hs, oth, abut, 188.5, 6.0) == 0.0)
  ok('...and then the garage\'s ridge, the valley and the house\'s rib meet in ONE point, (-192.5, 511)',
     RF.valley_carry_tris(RF.edge_plane(low, 2), RF.edge_plane(low, 4), hs, abut, 188.5, oth)
       .map { |_, t| t.map { |q| q.map { |v| v.round(2) } } } ==
       [[[-222.0, 481.5], [-192.5, 481.5], [-192.5, 511.0]], [[-163.0, 481.5], [-192.5, 481.5], [-192.5, 511.0]]],
     RF.valley_carry_tris(RF.edge_plane(low, 2), RF.edge_plane(low, 4), hs, abut, 188.5, oth).map { |_, t| t })
  # a garage of another PITCH is not parallel to anything
  steep = GAR.merge(slope: 0.5)
  ok('another pitch: no parallel slope, nothing', RF.valley_flush_drop(RF.edge_plane(steep, 2), RF.edge_plane(steep, 4), hs, oth, abut, 188.5, 6.0) == 0.0)
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

def build(style, **kw)
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
    RF.build_roof!(level: 1, style: style, pitch: 3.0, soffit: 'boxed', **kw)
    log = $stdout.string
  ensure
    $stdout = old
  end
  g = RF.roof_of_wall_id('gS')
  h = RF.roof_of_wall_id('h2')
  [log, g, h, g ? g.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } } : []]
end
def has?(fs, pts); fs.any? { |f| f.sort == pts.sort }; end

log, g, h, fs = build('hip')
ok('hip into hip: the builder says the garage is set 2.88" lower', log =~ /this roof is set 2\.88" lower/, log.lines.grep(/lower/))
ok('the garage stands at 83.125 (78 + its 8" heel - 2.875), the house where it was',
   g && (g.get_attribute('InteriorPro', 'eave_z').to_f - 83.125).abs < 0.001 && (h.get_attribute('InteriorPro', 'eave_z').to_f - 104.0).abs < 0.001,
   [g && g.get_attribute('InteriorPro', 'eave_z'), h && h.get_attribute('InteriorPro', 'eave_z')])
ok('no step is left: not on the rib, not on the abut line', log !~ /step face/, log.lines.grep(/step face/))
ok('the carried deck is two triangles that meet the house\'s rib in one point',
   has?(fs, [[-222.0, 481.5, 108.25], [-192.5, 481.5, 115.63], [-192.5, 511.0, 115.63]]) &&
   has?(fs, [[-192.5, 511.0, 115.63], [-192.5, 481.5, 115.63], [-163.0, 481.5, 108.25]]),
   fs.select { |f| f.any? { |p| p[1] > 481.6 } })
he = RF.edge_plane(RF.roof_geom(h), (0...4).find { |i| RF.edge_inward(RF.roof_geom(h)[:pts], i) == [-1.0, 0.0] } || 0) if h
ok('...and its east triangle lies IN the house\'s east slope', he && [[-192.5, 511.0, 115.63], [-163.0, 481.5, 108.25]].all? { |x, y, z| (RF.plane_z(he, x, y) - z).abs < 0.01 }, he)
log2 = nil
old = $stdout
$stdout = StringIO.new
begin
  2.times { RF.roofs.each { |r| RF.build_roof!(replace: r) } }
  log2 = $stdout.string
ensure
  $stdout = old
end
g2 = RF.roof_of_wall_id('gS')
ok('rebuilt twice the usual way: the garage is still at 83.125 - it does not creep down',
   g2 && (g2.get_attribute('InteriorPro', 'eave_z').to_f - 83.125).abs < 0.001, g2 && g2.get_attribute('InteriorPro', 'eave_z'))

lg, gg, = build('gable')
ok('gable into gable: the garage is not moved', lg !~ /set .* lower/ && (gg.get_attribute('InteriorPro', 'eave_z').to_f - 86.0).abs < 0.001,
   [lg.lines.grep(/lower/), gg.get_attribute('InteriorPro', 'eave_z')])
ln, gn, = build('hip', fascia: false)
ok('no fascia = no heel to give: the garage stays on its wall top and the step is closed instead',
   ln !~ /set .* lower/ && (gn.get_attribute('InteriorPro', 'eave_z').to_f - 78.0).abs < 0.001 && ln =~ /step face/,
   [ln.lines.grep(/lower|step/), gn.get_attribute('InteriorPro', 'eave_z')])

# ---- 3. the kill switch -------------------------------------------------------------
set_const(:USE_VALLEY_FLUSH, false)
lk, gk, = build('hip')
ok('kill switch: the garage stays at 86 and the step is closed with the upright faces',
   lk !~ /set .* lower/ && (gk.get_attribute('InteriorPro', 'eave_z').to_f - 86.0).abs < 0.001 && lk =~ /step face/,
   [lk.lines.grep(/lower|step/), gk.get_attribute('InteriorPro', 'eave_z')])
set_const(:USE_VALLEY_FLUSH, true)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

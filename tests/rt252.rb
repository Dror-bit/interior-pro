# encoding: utf-8
# rt252 - A HIP GARAGE RUNS INTO A HIP HOUSE (2026-10-02).
#
# His words: "in a hip roof the roof does not join properly". Measured on his
# Aetna model with both roofs on Hip (roof_meet_report.txt + pictures): the
# garage roof stopped dead on its back line (116.5 at the ridge, over a house
# roof at 108) and nothing was carried on. valley_extend! wanted a low roof
# with exactly two slopes - a hip front is a third - and the carried planes
# ran to ONE plane of the taller roof, while on a hip house the garage's ridge
# reaches the south slope right at the house's corner rib.
#
# Pinned: the two flanking sides are found; the carried pieces are cut on the
# taller roof's rib and the step there is closed; a gable into a gable is
# untouched; the kill switch.
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
ok('the code is loaded', RF.respond_to?(:valley_flank_sides) && RF.respond_to?(:valley_other_planes) &&
                         RF.respond_to?(:valley_rib_risers!) && RF.const_defined?(:USE_VALLEY_HIP_CARRY, false))
def r2(pts); pts.map { |p| [p[0].round(2), p[1].round(2)] }; end

# ---- 1. the pure rules, on HIS numbers (roof_meet_report.txt) --------------------
# his garage as it stands on Hip: 5 corners, edge 0 the back wall's gable stretch,
# edge 1 the abut line, 2 west, 3 the hip front, 4 east
GAR = { pts: [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]],
        slope: 0.25, deck_z: 81.0, ridge_z: 116.5, gables: [0], level: 1 }.freeze
HOUSE = { pts: [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]],
          slope: 0.25, deck_z: 99.0, ridge_z: 145.25, gables: [], level: 1 }.freeze
if RF.respond_to?(:valley_flank_sides)
  ok('a hip garage: of its three slopes, the two that flank the abut line are the west and the east',
     RF.valley_flank_sides(GAR, [2, 3, 4], 1) == [2, 4], RF.valley_flank_sides(GAR, [2, 3, 4], 1))
  ok('one slope only beside the abut line: nothing to run a valley with', RF.valley_flank_sides(GAR, [2, 3], 1).nil?)
  la = RF.edge_plane(GAR, 2)
  lb = RF.edge_plane(GAR, 4)
  hs = RF.edge_plane(HOUSE, 1)                       # the house's south slope
  oth = RF.valley_other_planes(HOUSE, 1)
  ok('a hip house has three other slopes', oth.length == 3, oth.length)
  ok('a GABLE house (its two ends are gables) has one: the far slope',
     RF.valley_other_planes(HOUSE.merge(gables: [0, 2]), 1).length == 1)
  abut = [[-146.0, 481.5], [-1.0, 0.0]]
  plain = RF.valley_carry_tris(la, lb, hs, abut, 188.5)
  ok('with no other planes handed in: the two triangles, to the apex, as before',
     plain.map { |_, t| r2(t) } == [[[-233.5, 481.5], [-192.5, 481.5], [-192.5, 522.5]], [[-151.5, 481.5], [-192.5, 481.5], [-192.5, 522.5]]],
     plain.map { |_, t| r2(t) })
  cut = RF.valley_carry_tris(la, lb, hs, abut, 188.5, oth)
  ok('a hip house: the WEST piece is cut on the house\'s rib - four corners, the valley ends at (-198.25, 516.75)',
     r2(cut[0][1]) == [[-233.5, 481.5], [-192.5, 481.5], [-192.5, 511.0], [-198.25, 516.75]], cut[0] && r2(cut[0][1]))
  ok('...and the EAST piece stops on the rib too: it starts at x -163, not at the leg\'s foot',
     cut[1] && r2(cut[1][1]).sort == [[-192.5, 481.5], [-192.5, 511.0], [-163.0, 481.5]], cut[1] && r2(cut[1][1]))
  gab = RF.valley_carry_tris(la, lb, hs, abut, 188.5, RF.valley_other_planes(HOUSE.merge(gables: [0, 2]), 1))
  ok('a gable house: its far slope cuts nothing - the very same two triangles',
     gab.map { |_, t| r2(t) } == plain.map { |_, t| r2(t) }, gab.map { |_, t| r2(t) })
  on_rib = RF.plane_z(lb, -163.0, 481.5) - RF.plane_z(RF.edge_plane(HOUSE, 2), -163.0, 481.5)
  ok('the step on the rib is the 2.9" his wall heights give', (on_rib - 2.875).abs < 0.01, on_rib)
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

def build(style, thickness = 0.5)
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
    RF.build_roof!(level: 1, style: style, pitch: 3.0, soffit: 'boxed', thickness: thickness)
    log = $stdout.string
  ensure
    $stdout = old
  end
  g = RF.roof_of_wall_id('gS')
  [log, g ? g.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } } : []]
end
def has?(fs, pts); fs.any? { |f| f.sort == pts.sort }; end
past = lambda { |fs| fs.select { |f| f.any? { |p| p[1] > 481.6 } } }

log, fs = build('hip')
ok('both roofs on Hip: the garage\'s planes ARE carried on to the house roof', log =~ /valley: 2 plane\(s\) carried on to the roof above/,
   log.lines.grep(/carried|valley_extend/))
ok('the deck, west: from the leg\'s foot to the house\'s rib (the stub\'s walls stand 2" higher than his)',
   has?(fs, [[-233.5, 481.5, 108.25], [-192.5, 481.5, 118.5], [-192.5, 511.0, 118.5], [-198.25, 516.75, 117.06]]), past.call(fs))
ok('the deck, east: a triangle that stops on the rib',
   has?(fs, [[-192.5, 511.0, 118.5], [-192.5, 481.5, 118.5], [-163.0, 481.5, 111.13]]), past.call(fs))
ok('the top skin too, half an inch higher', log =~ /the top skin carried on too \(2 face/ &&
   has?(fs, [[-192.5, 511.0, 119.02], [-192.5, 481.5, 119.02], [-163.0, 481.5, 111.64]]), past.call(fs))
ok('the step on the rib is closed: one upright face a side', log =~ /valley: 2 step face\(s\)/, log.lines.grep(/step face/))
ok('...the east one a strip 2.9" tall from the back line up to the ridge',
   has?(fs, [[-192.5, 511.0, 119.02], [-163.0, 481.5, 111.64], [-163.0, 481.5, 108.77], [-192.5, 511.0, 116.14]]), past.call(fs))
ok('...the west one a sliver that runs out to nothing where the valley reaches the rib',
   has?(fs, [[-192.5, 511.0, 119.02], [-198.25, 516.75, 117.58], [-192.5, 511.0, 116.14]]), past.call(fs))
ok('nothing of the garage roof lies past the house\'s rib', past.call(fs).flatten(1).none? { |p| p[1] > -p[0] + 318.5 + 0.05 },
   past.call(fs).flatten(1).select { |p| p[1] > -p[0] + 318.5 + 0.05 })
ok('the ridge cap runs on over the carried ridge', log =~ /valley: \d+" of ridge cap carried on/, log.lines.grep(/ridge cap/))

log0, fs0 = build('hip', 0.0)
ok('a roof with no thickness: the deck is carried on and the step is closed off the deck',
   log0 =~ /2 plane\(s\) carried on/ && log0 =~ /valley: 2 step face\(s\)/ && log0 !~ /top skin carried/, log0.lines.grep(/carried|step/))

# ---- 3. a gable into a gable is not touched, and the kill switch ------------------
_lg, gable_on = build('gable')
set_const(:USE_VALLEY_HIP_CARRY, false)
lk, fk = build('hip')
ok('kill switch: the hip garage stops on its back line, as before', lk !~ /carried on to the roof above/ && past.call(fk).empty?,
   [lk.lines.grep(/carried/), past.call(fk).length])
_lg, gable_off = build('gable')
ok('gable into gable: the very same garage roof with the switch on and off', gable_on.map(&:sort).sort == gable_off.map(&:sort).sort,
   [gable_on.length, gable_off.length])
set_const(:USE_VALLEY_HIP_CARRY, true)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

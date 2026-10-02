# encoding: utf-8
# rt242 - A GABLE ROOF THAT DIES INTO A WALL GABLES ITS FAR END (2026-10-01).
#
# His Aetna garage, style Gable, no marks: ONE slope, ridge 218.25", no
# ridge cap (the roof audit he ran, section 1). The automatic pick gabled
# the two SIDES of a garage that is 284 x 280.5 - and the side against the
# house does not move either - so only the front edge rose: a shed. Marking
# the front wall by hand gave two slopes and ridge 149" (116.5" at 3:12).
# The stamped roof plan draws the same thing: the ridge runs into the house.
#
# Pinned on the pure rule, then on the real path with his walls: the garage
# comes out two-sided with no mark at all, the pitch changes the HEIGHT and
# not the shape, and the house roof is not touched by any of it.
ENV['REAL_ROOMS'] = '1'
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

# ---- 1. the pure rule ------------------------------------------------------
SQ = [[-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0], [-50.5, 481.5]].freeze
ok('four edges, one abut edge: the gable is the edge facing it',
   RF.abut_gable_edges(SQ, %w[gW gS gE div], ['div']) == [1], RF.abut_gable_edges(SQ, %w[gW gS gE div], ['div']))
ok('the same roof walked from another corner gives the same wall',
   RF.abut_gable_edges(SQ.rotate(3), %w[div gW gS gE], ['div']) == [2])
ok('no abut edge: nil, the old pick stands', RF.abut_gable_edges(SQ, %w[a b c d], []).nil?)
ok('two abut edges: nil', RF.abut_gable_edges(SQ, %w[a b c d], %w[a b]).nil?)
ok('not four-sided: nil', RF.abut_gable_edges(SQ + [[-100.0, 500.0]], %w[a b c d e], ['d']).nil?)

# ---- 2. the real path, on his walls -----------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def build(pitch)
  Sketchup.reset_model!
  m = Sketchup.active_model
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = m.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  RF.build_roof!(level: 1, style: 'gable', pitch: pitch)
  gar = RF.roof_of_wall_id('gS')
  hse = RF.roof_of_wall_id('h2')
  [gar, hse]
end

def gable_walls(roof)
  fp = Array(roof.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).to_a
  Array(roof.get_attribute('InteriorPro', 'gable_edges')).map do |i|
    a = fp[i]
    b = fp[(i + 1) % fp.length]
    [((a[0] + b[0]) / 2.0).round(1), ((a[1] + b[1]) / 2.0).round(1)]
  end
end

g6, h6 = build(6.0)
ok('the garage roof was built', !g6.nil?)
if g6
  ok('ONE gable end, and it is the front of the garage (the edge on y = 201)',
     gable_walls(g6) == [[-192.5, 201.0]], gable_walls(g6))
  rise6 = g6.get_attribute('InteriorPro', 'ridge_z').to_f - (g6.get_attribute('InteriorPro', 'eave_z').to_f - 0.5 * 12.0)
  ok('the ridge stands over the MIDDLE of the garage: half its width up the slope (142" x 6:12 = 71")',
     (rise6 - 71.0).abs < 0.6, rise6)
  house6 = gable_walls(h6)
  g3, h3 = build(3.0)
  rise3 = g3.get_attribute('InteriorPro', 'ridge_z').to_f - (g3.get_attribute('InteriorPro', 'eave_z').to_f - 0.25 * 12.0)
  ok('3:12 changes the height (35.5")...', (rise3 - 35.5).abs < 0.6, rise3)
  ok('...and not the shape: the same gable end', gable_walls(g3) == [[-192.5, 201.0]], gable_walls(g3))
  ok('the house roof picks its own gable ends exactly as at 6:12', gable_walls(h3) == house6, [gable_walls(h3), house6])
end

# ---- 3. the kill switch: the old single slope --------------------------------
RF.send(:remove_const, :USE_ABUT_GABLE_PICK)
RF.const_set(:USE_ABUT_GABLE_PICK, false)
g_old, h_old = build(6.0)
old_rise = g_old.get_attribute('InteriorPro', 'ridge_z').to_f - (g_old.get_attribute('InteriorPro', 'eave_z').to_f - 6.0)
ok('kill switch: the garage is the one long slope again (280.5" x 6:12)', old_rise > 130.0, old_rise)
ok('kill switch: the house is the same either way', gable_walls(h_old) == house6, [gable_walls(h_old), house6])

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt243 - THE ROOF RUNS STRAIGHT ACROSS A NARROW RECESS (2026-10-01).
#
# His Aetna house: an entry recess 45.5" wide and 35" deep in the front
# wall. The eave outline followed it, so the roof had a 21.5" slot in it and
# the front of the house became two "wings" - and the Gable style stood a
# full cross gable on each one (four gable walls; his screenshot, and the
# roof audit he ran). The stamped roof plan A-1.0 draws ONE slope across the
# whole front, and ridge east-west.
#
# Pinned on the pure rule, then on the real path with his walls: the house
# outline is a plain rectangle, Gable gives two gable ENDS and nothing else,
# every wall of the recess still belongs to the roof, a WIDE recess is left
# alone, and the kill switch brings the four gables back.
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

# ---- 1. the pure rule, on his own outline ------------------------------------
HIS = [[-749.0, 822.5], [-749.0, 452.5], [-440.5, 452.5], [-440.5, 487.5],
       [-419.0, 487.5], [-419.0, 453.0], [-134.0, 453.0], [-134.0, 822.5]].freeze
IDS = %w[h2 h4 h3 h1 h6 div h7 h8].freeze
pts, ids, lost = RF.bridge_notches(HIS, IDS)
ok('his outline becomes a plain rectangle, the half-inch jog gone with it',
   pts == [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]], pts)
ok('the front edge keeps the wall of its longer stretch', ids == %w[h2 h4 h7 h8], ids)
ok('the three recess walls and the shorter stretch are handed back as lost', lost.sort == %w[div h1 h3 h6], lost)
ok('the caller\'s arrays are not touched', HIS.length == 8 && IDS.length == 8)

wide = HIS.map { |x, y| [x < -430 ? x : x + 60.0, y] }          # the recess 81.5" wide
pw, iw, lw = RF.bridge_notches(wide, IDS)
ok('a WIDE recess is a real one and is left alone', pw == wide && iw == IDS && lw.empty?, pw)

pk, _ik, lk = RF.bridge_notches(HIS, IDS, ['h1'])
ok('a recess with an abut edge in it is left alone', pk == HIS.map { |p| p.map(&:to_f) } && lk.empty?, pk)

rect = [[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [0.0, 50.0]]
ok('a plain rectangle is handed back as it came', RF.bridge_notches(rect, %w[a b c d]) == [rect, %w[a b c d], []])

# the two stretches are NOT in line (a 6" step): bridge the mouth only
step = [[-749.0, 822.5], [-749.0, 452.5], [-440.5, 452.5], [-440.5, 487.5],
        [-419.0, 487.5], [-419.0, 458.5], [-134.0, 458.5], [-134.0, 822.5]]
ps, is, ls = RF.bridge_notches(step, IDS)
ok('stretches that do not line up: the mouth is bridged and both stretches stay',
   ps == [[-749.0, 822.5], [-749.0, 452.5], [-440.5, 452.5], [-419.0, 458.5], [-134.0, 458.5], [-134.0, 822.5]] &&
   is == ['h2', 'h4', nil, 'div', 'h7', 'h8'] && ls.sort == %w[h1 h3 h6], [ps, is, ls])

# ---- 2. the real path, on his walls --------------------------------------------
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

def build(style)
  Sketchup.reset_model!
  m = Sketchup.active_model
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = m.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  RF.build_roof!(level: 1, style: style, pitch: 6.0)
  [RF.roof_of_wall_id('h2'), RF.roof_of_wall_id('gS')]
end

def footprint(r)
  Array(r.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.round(2), y.round(2)] }
end

def gable_mids(r)
  fp = footprint(r)
  Array(r.get_attribute('InteriorPro', 'gable_edges')).map do |i|
    a = fp[i]
    b = fp[(i + 1) % fp.length]
    [((a[0] + b[0]) / 2.0).round(1), ((a[1] + b[1]) / 2.0).round(1)]
  end.sort
end

house, garage = build('gable')
ok('the house roof was built', !house.nil?)
if house
  ok('the house roof stands on a plain rectangle',
     footprint(house).sort == [[-749.0, 452.5], [-749.0, 822.5], [-134.0, 452.5], [-134.0, 822.5]].sort, footprint(house))
  ok('Gable gives TWO gable ends - the west and east walls - and no cross gables',
     gable_mids(house) == [[-749.0, 637.5], [-134.0, 637.5]], gable_mids(house))
  rise = house.get_attribute('InteriorPro', 'ridge_z').to_f - (house.get_attribute('InteriorPro', 'eave_z').to_f - 6.0)
  ok('the ridge runs east-west over the middle of the house (185" x 6:12 = 92.5")', (rise - 92.5).abs < 0.6, rise)
  own = RF.roof_wall_ids(house)
  ok('the three walls of the recess still belong to the house roof', (%w[h1 h3 h6] - own).empty?, own)
  ok('...and so does the wall 68ea', own.include?('h5'), own)
  # (rt246: plus the point on the back line where the back wall's own stretch
  # starts, and that stretch as a second gable end)
  ok('the garage roof is untouched by this: same corners, the gable end at the front',
     garage && footprint(garage).sort == [[-334.5, 201.0], [-334.5, 481.5], [-148.5, 481.5], [-50.5, 201.0], [-50.5, 481.5]].sort &&
     gable_mids(garage) == [[-192.5, 201.0], [-99.5, 481.5]], garage && [footprint(garage), gable_mids(garage)])
end
hip, = build('hip')
ok('Hip on the same house: four eaves and no gable at all',
   hip && footprint(hip).length == 4 && gable_mids(hip).empty?, hip && [footprint(hip), gable_mids(hip)])

# ---- 3. the kill switch ---------------------------------------------------------
RF.send(:remove_const, :USE_NOTCH_BRIDGE)
RF.const_set(:USE_NOTCH_BRIDGE, false)
old, = build('gable')
ok('kill switch: the recess is back in the outline (8 corners)', footprint(old).length == 8, footprint(old))
ok('kill switch: and so are the two cross gables (4 gable edges)', gable_mids(old).length == 4, gable_mids(old))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

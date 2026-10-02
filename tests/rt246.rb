# encoding: utf-8
# rt246 - THE BACK WALL'S STRETCH OF THE ROOF EDGE IS A GABLE END (2026-10-01).
#
# rt245 carried his garage's back wall (4b76e4cc) up to the roof. The roof
# still stuck 11.5" out past that wall with a bare edge: no board, no soffit.
# That edge is an ABUT edge - the line the garage roof dies into the house
# on - and an abut edge gets no trim at all, because the taller wall is
# supposed to stand there. Over this wall nothing stands there.
#
# So the stretch of the abut edge over a wall of the roof's OWN, with no
# taller wall behind it, is cut out as an edge of its own and made a gable
# end: it gets the rake board, the rake soffit and the corner every gable
# end gets. It lies on the old line and runs at speed 0 like the abut edge
# did, so no roof plane moves.
#
# Pinned on the two pure rules, then on the real path with his walls.
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

# ---- 1. the pure rule: cutting a stretch out of an edge -----------------------
ok('the code is loaded', RF.respond_to?(:split_edge_spans) && RF.respond_to?(:stub_spans))
RECT = [[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [0.0, 50.0]].freeze
IDS = %w[a b c d].freeze
if RF.respond_to?(:split_edge_spans)
  r = RF.split_edge_spans(RECT, IDS, [0], { 2 => [0.0, 30.0, 'x'] })
  ok('a stretch at the START of an edge: one new point, the stretch takes the new id and is a gable',
     r == [[[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [70.0, 50.0], [0.0, 50.0]], %w[a b x c d], [0, 2]], r)
  r = RF.split_edge_spans(RECT, IDS, [0], { 2 => [40.0, 100.0, 'x'] })
  ok('a stretch at the END of an edge',
     r == [[[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [60.0, 50.0], [0.0, 50.0]], %w[a b c x d], [0, 3]], r)
  r = RF.split_edge_spans(RECT, IDS, [0], { 2 => [30.0, 60.0, 'x'] })
  ok('a stretch in the MIDDLE: two new points, the edge keeps its id on both sides',
     r == [[[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [70.0, 50.0], [40.0, 50.0], [0.0, 50.0]], %w[a b c x c d], [0, 3]], r)
  r = RF.split_edge_spans(RECT, IDS, [2], { 0 => [20.0, 50.0, 'x'] })
  ok('a gable edge AFTER the cut keeps its flag under its new number',
     r == [[[0.0, 0.0], [20.0, 0.0], [50.0, 0.0], [100.0, 0.0], [100.0, 50.0], [0.0, 50.0]], %w[a x a b c d], [1, 4]], r)
  r = RF.split_edge_spans(RECT, IDS, [0], { 2 => [0.5, 99.6, 'x'] })
  ok('a stretch that is the whole edge: no new point, the edge changes hands',
     r == [RECT.map(&:dup), %w[a b x d], [0, 2]], r)
  r = RF.split_edge_spans(RECT, IDS, [0], {})
  ok('nothing to cut: handed back as it came', r == [RECT.map(&:dup), IDS.dup, [0]], r)
  ok('the caller\'s arrays are not touched', RECT.length == 4 && IDS == %w[a b c d])
end

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

def add_wall(id, sx, sy, ex, ey, th, bz, cat)
  g = Sketchup.active_model.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
    'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
    'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end

def build(style, **kw)
  Sketchup.reset_model!
  WALLS.each { |w| add_wall(*w) }
  old = $stdout
  $stdout = StringIO.new
  begin
    RF.build_roof!(level: 1, style: style, pitch: 3.0, **kw)
    log = $stdout.string
  ensure
    $stdout = old
  end
  [RF.roof_of_wall_id('h2'), RF.roof_of_wall_id('gS'), log]
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

# the roof group's OWN faces (boards, deck), as sorted point lists
def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } }
end

def has_face?(fs, pts)
  fs.any? { |f| f.sort == pts.sort }
end

def wall_tops(r)
  r.entities.grep(Sketchup::Group).select { |g| g.name == 'InteriorPro_GableWall' }.flat_map do |g|
    g.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } }
  end
end

OUTER = [[-50.5, 481.5, 83.0], [-148.5, 481.5, 107.5], [-148.5, 481.5, 99.5], [-50.5, 481.5, 75.0]].freeze
SOFFIT = [[-62.5, 480.75, 78.0], [-148.5, 480.75, 99.5], [-148.5, 469.5, 99.5], [-62.5, 469.5, 78.0]].freeze

house, garage, log = build('gable', soffit: 'boxed')
ok('both roofs were built', house && garage)
if house && garage
  fs = faces(garage)
  ok('the builder says the wall is a gable end', log =~ /wall gN stands on the line this roof dies against with nothing behind it - a gable end/,
     log.lines.grep(/gable end/))
  ok('the garage stands on its four corners, with ONE more point on the back line where the house wall starts',
     footprint(garage) == [[-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0], [-50.5, 481.5], [-148.5, 481.5]], footprint(garage))
  ok('two gable ends: the front, and the back wall\'s stretch (98" of the back line)',
     gable_mids(garage) == [[-192.5, 201.0], [-99.5, 481.5]], gable_mids(garage))
  ok('the back wall is one of the roof\'s walls, the house walls it dies into are not',
     RF.roof_wall_ids(garage).sort == %w[gE gN gS gW], RF.roof_wall_ids(garage))
  ok('RAKE BOARD: 8" deep on the roof\'s edge, from the east corner up to the house wall',
     has_face?(fs, OUTER), fs.select { |f| f.all? { |p| (p[1] - 481.5).abs < 0.01 } })
  ok('...and 3/4" thick (its inner face)',
     has_face?(fs, OUTER.map { |x, _y, z| [x, 480.75, z] }))
  ok('RAKE SOFFIT: from the wall line out to the board, flush with the board\'s bottom',
     has_face?(fs, SOFFIT), fs.select { |f| f.all? { |p| p[1] > 469.0 && p[1] < 481.0 } })
  plate = fs.select do |f|
    f.all? { |p| (p[0] - -148.5).abs < 0.01 } &&
      f.map { |p| p[1] }.minmax.reduce(:-).abs > 2.0 && f.map { |p| p[2] }.minmax.reduce(:-).abs > 2.0
  end
  ok('no closing plate is stood in the face of the house wall', plate.empty?, plate)
  old_cap = fs.select { |f| f.length == 5 && f.all? { |p| (p[1] - 481.5).abs < 0.01 && p[0] > -63.0 } }
  ok('the old end plate at the east corner is gone - the board turns the corner instead', old_cap.empty?, old_cap)
  back = wall_tops(garage).select { |f| f.all? { |p| (p[1] - 470.0).abs < 0.01 } }
  ok('the wall still goes up to the roof on its OWN face (y = 470), once', back.length == 1 && wall_tops(garage).length == 2, wall_tops(garage))
  ok('the house roof is what it was: a plain rectangle, two gable ends',
     footprint(house).sort == [[-749.0, 452.5], [-749.0, 822.5], [-134.0, 452.5], [-134.0, 822.5]].sort &&
     gable_mids(house) == [[-749.0, 637.5], [-134.0, 637.5]], [footprint(house), gable_mids(house)])
end
on_ridge = garage && garage.get_attribute('InteriorPro', 'ridge_z').to_f
on_eave = garage && garage.get_attribute('InteriorPro', 'eave_z').to_f
on_west = garage ? faces(garage).select { |f| f.all? { |p| p[0] < -150.0 } }.map(&:sort).sort : []

_h, g_none, = build('gable')
if g_none
  fn = faces(g_none)
  ok('soffit "None": the board is there, no soffit', has_face?(fn, OUTER) && !has_face?(fn, SOFFIT))
end

# Both roofs on Hip: since 2026-10-02 the garage is set 2.875" lower, to make one
# surface with the house's east slope (rt254) - the board and the soffit come down with it.
_h, g_hip, = build('hip', soffit: 'boxed')
down = lambda { |pts| pts.map { |x, y, z| [x, y, (z - 2.875).round(2)] } }
ok('Hip: the same stretch gets the same board and soffit (2.875" lower, with the roof)',
   g_hip && has_face?(faces(g_hip), down.call(OUTER)) && has_face?(faces(g_hip), down.call(SOFFIT)) &&
   gable_mids(g_hip) == [[-99.5, 481.5]], g_hip && [gable_mids(g_hip), faces(g_hip).select { |f| f.all? { |p| (p[1] - 481.5).abs < 0.01 } }.first(4)])

# ---- 3. which stretch: the model rule -------------------------------------------
if RF.respond_to?(:stub_spans)
  build('gable')
  poly = [[-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0], [-50.5, 481.5]]
  ids = %w[gW gS gE div]
  own = %w[gW gS gE gN]
  sw = { 'div' => %w[gN h5] }
  r = RF.stub_spans(poly, ids, ['div'], sw, own, [], 12.0)
  ok('his back wall: the stretch runs from the corner to the wall\'s far end',
     r.keys == [3] && r[3][0].abs < 0.01 && (r[3][1] - 98.0).abs < 0.01 && r[3][2] == 'gN', r)
  ok('a wall that is not this roof\'s own is never a gable end here',
     RF.stub_spans(poly, ids, ['div'], sw, %w[gW gS gE], [], 12.0).empty?)
  ok('no merged walls at all: nothing', RF.stub_spans(poly, ids, ['div'], nil, own, [], 12.0).empty?)
  ok('an edge that is not an abut edge is left alone', RF.stub_spans(poly, ids, [], sw, own, [], 12.0).empty?)
  half = add_wall('cv', -100.0, 470.0, -146.0, 470.0, 5.0, 0, 'exterior')
  r = RF.stub_spans(poly, ids, ['div'], sw, own, [half], 12.0)
  ok('a taller wall behind HALF of it: only the open half is a gable end',
     r[3] && r[3][0].abs < 0.01 && (r[3][1] - 47.0).abs < 0.01, r)
  full = add_wall('cw', -62.5, 470.0, -146.0, 470.0, 5.0, 0, 'exterior')
  ok('a taller wall behind ALL of it: no gable end', RF.stub_spans(poly, ids, ['div'], sw, own, [full], 12.0).empty?)
  cross = add_wall('cx', -100.0, 470.0, -100.0, 600.0, 5.0, 0, 'exterior')
  r = RF.stub_spans(poly, ids, ['div'], sw, own, [cross], 12.0)
  ok('a taller wall that only CROSSES the line does not count', r[3] && (r[3][1] - 98.0).abs < 0.01, r)
end

# ---- 4. the kill switch ---------------------------------------------------------
RF.send(:remove_const, :USE_STUB_RAKE) if RF.const_defined?(:USE_STUB_RAKE, false)
RF.const_set(:USE_STUB_RAKE, false)
_k, gk, lk = build('gable', soffit: 'boxed')
if gk
  fk = faces(gk)
  ok('kill switch: the plain four-corner outline and the one gable end',
     footprint(gk).sort == [[-334.5, 201.0], [-334.5, 481.5], [-50.5, 201.0], [-50.5, 481.5]].sort &&
     gable_mids(gk) == [[-192.5, 201.0]], [footprint(gk), gable_mids(gk)])
  ok('kill switch: the bare edge - no board, no soffit', !has_face?(fk, OUTER) && !has_face?(fk, SOFFIT))
  ok('kill switch: nothing is said about a gable end', lk !~ /a gable end,/)
  ok('kill switch: the wall top of rt245 is still built', wall_tops(gk).any? { |f| f.all? { |p| (p[1] - 470.0).abs < 0.01 } })
  ok('either way the roof itself is the same: same ridge, same eave',
     (gk.get_attribute('InteriorPro', 'ridge_z').to_f - on_ridge).abs < 0.001 &&
     (gk.get_attribute('InteriorPro', 'eave_z').to_f - on_eave).abs < 0.001)
  off_west = fk.select { |f| f.all? { |p| p[0] < -150.0 } }.map(&:sort).sort
  ok('either way everything on the HOUSE side of that wall is face for face the same', off_west == on_west && !on_west.empty?,
     [on_west.length, off_west.length, (on_west - off_west).first(3), (off_west - on_west).first(3)])
end

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

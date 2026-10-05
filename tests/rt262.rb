# encoding: utf-8
# rt262 - AN EAVE PULLED OUT (2026-10-05, step 2 of the roof-edge pull).
#
# Asked with a picture of his own roof (next_question.png: 1 = an ordinary side
# of the roof can be pulled out too - "הגג ממשיך שם החוצה ולמטה", 2 = drag with
# the mouse), he answered 1.
#
# A gable end only gets longer; an eave must carry its own plane on, out and
# DOWN. So the roof is built exactly as it was, one more piece of the same plane
# is laid from the old eave line to the new one, and that edge wears its fascia,
# drip and soffit at its own height: slope x pull under every other eave.
#
# WHAT IS PINNED HERE:
#   * the pure rules: which eaves with a number are pulled (and why not), how far
#     a rake beside one reaches, a box return of another length, a profile with a
#     node on a straight line taken out;
#   * a plain gable house, one eave pulled: the roof above it did not move, the
#     piece of plane (both skins, its edge), the fascia / drip / soffit at the new
#     line and the lower height, the rakes beside it in ONE piece down to the new
#     corner, their box returns, the outline the roof says is its own;
#   * his walls, the front eave beside the pulled-out gable: an inside corner -
#     the short eave of the gable keeps its own dress, the box of the pulled eave
#     is closed on that line, and the garage roof is the roof it was;
#   * where it is not built, and that it says so; the Roof End menu; the switch.
#
# THE SAME DAY, AFTER HE SAW IT ("מפריע לי וגם הגג כאילו עלה בגובה"; asked with
# corner_options.png he answered 1: "הכלי לא משנה גובה אלא מותח את הגג"): at the
# foot of the pulled-out gable the short eave (no wall of its own) goes OUT WITH
# the eave - both planes carry on, the valley runs on to the new corner, the two
# eaves still meet at one height. USE_EAVE_CORNER_FOLLOW = false is the morning's
# roof (the short eave only gets shorter), pinned below as it was.
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
require './roof_gable_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager

# ---- 1. the pure rules --------------------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:eave_pull_plan) && RF.respond_to?(:eave_reach) && RF.const_defined?(:USE_EAVE_PULL, false))
SQ = [[0.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
IDS = %w[a b c d].freeze
# a wing pulled out of the south side: a | (short edge, no wall) | x | b ...
WING = [[0.0, 0.0], [330.0, 0.0], [330.0, -36.0], [600.0, -36.0], [600.0, 300.0], [0.0, 300.0]].freeze
WIDS = ['a', nil, 'x', 'b', 'c', 'd'].freeze
if RF.respond_to?(:eave_pull_plan)
  r = RF.eave_pull_plan(SQ, IDS, [1, 3], { 'a' => 24.0 }, { 1 => true, 3 => true })
  ok('an eave between two gable ends that close their own body', r == [{ 0 => 24.0 }, {}], r)
  r = RF.eave_pull_plan(SQ, IDS, [1, 3], { 'a' => 24.0, 'c' => 10.0 }, { 1 => true, 3 => true })
  ok('both eaves of the same roof, each by its own number', r[0] == { 0 => 24.0, 2 => 10.0 } && r[1] == {}, r)
  r = RF.eave_pull_plan(SQ, IDS, [1, 3], { 'b' => 24.0 }, { 1 => true, 3 => true })
  ok('a gable end is not an eave: left, with the reason', r[0] == {} && r[1]['b'] =~ /gable end/, r)
  r = RF.eave_pull_plan(SQ, IDS, [1, 3], { 'a' => 24.0 }, { 1 => true })
  ok('a gable beside it that runs on past its own body: left', r[0] == {} && r[1]['a'] =~ /runs on past its own body/, r)
  r = RF.eave_pull_plan(SQ, IDS, [], { 'a' => 24.0 })
  ok('an eave at an outside (hip) corner: left', r[0] == {} && r[1]['a'] =~ /hip corner/, r)
  r = RF.eave_pull_plan(WING, WIDS, [2, 5], { 'a' => 24.0 }, { 2 => true, 5 => true })
  ok('his front eave: a gable end on one side; the short eave of the pulled-out gable on the other goes out WITH it', r == [{ 0 => 24.0, 1 => 24.0 }, {}], r)
  r = RF.eave_pull_plan(WING, WIDS, [2, 5], { 'a' => 24.0 }, { 5 => true })
  ok('...only when the gable it stands on closes its own body - otherwise it stays and gets shorter', r == [{ 0 => 24.0 }, {}], r)
  r = RF.eave_pull_plan(WING, ['a', 'k', 'x', 'b', 'c', 'd'], [2, 5], { 'a' => 24.0 }, { 2 => true, 5 => true })
  ok('...and only an edge with no wall of its own: one that has a wall stays', r == [{ 0 => 24.0 }, {}], r)
  RF.send(:remove_const, :USE_EAVE_CORNER_FOLLOW)
  RF.const_set(:USE_EAVE_CORNER_FOLLOW, false)
  r = RF.eave_pull_plan(WING, WIDS, [2, 5], { 'a' => 24.0 }, { 2 => true, 5 => true })
  ok('switched off: the short eave stays', r == [{ 0 => 24.0 }, {}], r)
  RF.send(:remove_const, :USE_EAVE_CORNER_FOLLOW)
  RF.const_set(:USE_EAVE_CORNER_FOLLOW, true)
  r = RF.pull_edges(WING, WIDS, nil, { 0 => 24.0, 1 => 24.0 })
  ok('the outline with both out: the inside corner moves along the valley, the gable edge gets longer',
     r[0] == [[0.0, -24.0], [306.0, -24.0], [306.0, -36.0], [600.0, -36.0], [600.0, 300.0], [0.0, 300.0]] && r[1] == WIDS, r)
  r = RF.eave_pull_plan(WING, WIDS, [2, 5], { 'a' => 36.0 }, { 2 => true, 5 => true })
  ok('...but not as far as that short eave is long', r[0] == {} && r[1]['a'] =~ /not longer than the pull/, r)
  r = RF.eave_pull_plan([[0.0, 0.0], [330.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]], %w[a x b c d], [1, 2, 4], { 'a' => 24.0 }, { 1 => true, 2 => true, 4 => true })
  ok('an eave that runs straight on into a gable in the middle: left', r[0] == {} && r[1]['a'] =~ /runs straight on/, r)
  r = RF.eave_pull_plan(SQ, %w[a b a d], [1, 3], { 'a' => 24.0 }, { 1 => true, 3 => true })
  ok('a wall with two edges: left', r[0] == {} && r[1]['a'] =~ /more than one/, r)
  ok('nothing asked: nothing', RF.eave_pull_plan(SQ, IDS, [1, 3], {}) == [{}, {}])
end
if RF.respond_to?(:eave_reach)
  ok('a rake beside a pulled eave reaches on to the new corner - at its start', RF.eave_reach([24.0, 324.0], 4, 1, { 0 => 24.0 }) == [0.0, 324.0])
  ok('...at its end', RF.eave_reach([0.0, 300.0], 4, 3, { 0 => 24.0 }) == [0.0, 324.0])
  ok('no pulled eave, or no reach: untouched', RF.eave_reach([0.0, 300.0], 4, 1, {}) == [0.0, 300.0] && RF.eave_reach(nil, 4, 1, { 0 => 24.0 }).nil?)
end
ok('a box return keeps one overhang when nothing says otherwise', RF.rake_soffit_segments(0.0, 200.0, 200.0, 12.0) == [[0.0, 12.0, true], [12.0, 188.0, false], [188.0, 200.0, true]])
ok('...and is as long as the wider board of a pulled eave where there is one',
   RF.rake_soffit_segments(0.0, 200.0, 200.0, 12.0, nil, [36.0, 12.0]) == [[0.0, 36.0, true], [36.0, 188.0, false], [188.0, 200.0, true]],
   RF.rake_soffit_segments(0.0, 200.0, 200.0, 12.0, nil, [36.0, 12.0]))
ZM = { [0.0, 0.0] => 90.0, [0.0, 24.0] => 96.0, [0.0, 124.0] => 121.0, [0.0, 224.0] => 96.0 }.freeze
ch = RF.edge_profile_chain([[0.0, 0.0], [0.0, 224.0], [-50.0, 224.0], [-50.0, 0.0]], 0, ZM)
ok('a profile keeps every node by default', ch.map { |c| c[0] } == [0.0, 24.0, 124.0, 224.0], ch)
ch = RF.edge_profile_chain([[0.0, 0.0], [0.0, 224.0], [-50.0, 224.0], [-50.0, 0.0]], 0, ZM, straight: true)
ok('straight: the node on the straight line is taken out, the ridge stays', ch.map { |c| c[0] } == [0.0, 124.0, 224.0], ch)

def quiet
  old = $stdout
  $stdout = StringIO.new
  begin
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end

def add_walls(list)
  list.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => (th || 5.0), 'base_z' => (bz || 0).to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => (cat || 'exterior'), 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
end

def wall(id)
  Sketchup.active_model.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == id }
end

def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } }
end

def norm(fs)
  fs.map(&:sort).sort
end

def has?(fs, pts)
  fs.any? { |f| f.sort == pts.sort }
end

def fp(r)
  Array(r.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.to_f.round(1), y.to_f.round(1)] }
end

def lowest_over(fs, x, y)
  best = nil
  fs.each do |ps|
    next if ps.map { |p| p[0] }.uniq.length < 2 || ps.map { |p| p[1] }.uniq.length < 2
    inside = false
    ps.each_with_index do |a, k|
      b = ps[(k + 1) % ps.length]
      next unless (a[1] > y) != (b[1] > y)
      inside = !inside if x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
    end
    next unless inside
    p0 = ps[0]
    z = nil
    ps.each_cons(2) do |p1, p2|
      nx = (p1[1] - p0[1]) * (p2[2] - p0[2]) - (p1[2] - p0[2]) * (p2[1] - p0[1])
      ny = (p1[2] - p0[2]) * (p2[0] - p0[0]) - (p1[0] - p0[0]) * (p2[2] - p0[2])
      nz = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0])
      next if nz.abs < 1.0e-6
      z = p0[2] - (nx * (x - p0[0]) + ny * (y - p0[1])) / nz
      break
    end
    next if z.nil?
    best = z if best.nil? || z < best
  end
  best
end

KW = { style: 'gable', overhang: 12.0, fascia: true, fascia_depth: 6.0, drip: true, soffit: 'boxed', gutter: false }.freeze

# ---- 2. a plain gable house, 3:12 - the south eave (wall a) pulled 24" ------------------------
Sketchup.reset_model!
add_walls([['a', 0.0, 0.0, 400.0, 0.0], ['b', 400.0, 0.0, 400.0, 240.0], ['c', 400.0, 240.0, 0.0, 240.0], ['d', 0.0, 240.0, 0.0, 0.0]])
def box_roof(marks, pulls, **kw)
  RF.roofs.each(&:erase!)
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  log = quiet { RF.build_roof!(level: 1, pitch: 3.0, **KW, **kw) }
  [RF.roofs.first, log]
end
plain, = box_roof([], {})
pf = faces(plain)
r, log = box_roof([], { 'a' => 24.0 })
f = faces(r)
ok('the builder says so, and how much lower it ends', log =~ /eave a pulled out 24" - it ends 6\.0" lower/, log.lines.grep(/pull|eave/))
ok('the roof above the old eave line did not move: the same eave height, the same ridge',
   r.get_attribute('InteriorPro', 'eave_z') == plain.get_attribute('InteriorPro', 'eave_z') &&
   r.get_attribute('InteriorPro', 'ridge_z') == plain.get_attribute('InteriorPro', 'ridge_z'))
big = pf.select { |ps| ps.map { |p| p[0] }.minmax.reduce { |a, b| b - a } > 300.0 && ps.map { |p| p[2] }.minmax.reduce { |a, b| b - a } > 10.0 }
ok('every slope of the plain roof is still there, corner for corner', big.length >= 4 && big.all? { |ps| has?(f, ps) }, big.reject { |ps| has?(f, ps) })
# 3:12, overhang 12: the deck's underside on the old eave line is 102 - 3 = 99; 24" further out it is 6 lower
ok('one more piece of the same plane, from the old eave line out to the new one - the underside',
   has?(f, [[-12.0, -12.0, 99.0], [-12.0, -36.0, 93.0], [412.0, -36.0, 93.0], [412.0, -12.0, 99.0]]), f.select { |ps| ps.map { |p| p[1] }.min == -36.0 }.first(4))
top = f.find { |ps| ps.length == 4 && ps.map { |p| p[1] }.sort == [-36.0, -36.0, -12.0, -12.0] && ps.map { |p| p[2] }.min > 93.0 && ps.map { |p| p[2] }.max < 100.5 && ps.map { |p| p[0] }.minmax == [-12.0, 412.0] }
ok('...and the top skin over it', !top.nil?)
dz = top ? top.map { |p| p[2] }.min - 93.0 : 0.0
ok('...closed along the new edge', has?(f, [[-12.0, -36.0, 93.0], [412.0, -36.0, 93.0], [412.0, -36.0, (93.0 + dz).round(2)], [-12.0, -36.0, (93.0 + dz).round(2)]]))
ok('the builder hides the old eave line in both skins', log =~ /2 edge\(s\) hidden on the old eave line/)
ok('the fascia stands on the new line, 6" lower than the others: 93 down to 87',
   has?(f, [[-12.0, -36.0, 93.0], [412.0, -36.0, 93.0], [412.0, -36.0, 87.0], [-12.0, -36.0, 87.0]]), f.select { |ps| ps.all? { |p| p[1] == -36.0 } })
ok('...and none is left on the old line', f.none? { |ps| ps.all? { |p| p[1] == -12.0 } && ps.map { |p| p[2] }.minmax == [93.0, 99.0] && ps.map { |p| p[0] }.max - ps.map { |p| p[0] }.min > 100.0 })
ok('the far eave keeps its own, at 99', has?(f, [[412.0, 252.0, 99.0], [-12.0, 252.0, 99.0], [-12.0, 252.0, 93.0], [412.0, 252.0, 93.0]]))
ok('the drip edge on the new line too', f.any? { |ps| ps.all? { |p| p[1] < -36.0 && p[1] > -36.2 } && ps.map { |p| p[2] }.minmax == [91.0, 93.0] })
[[-30.0, 87.0], [-20.0, 87.0], [-13.0, 87.0], [-2.0, 87.0]].each do |y, want|
  z = lowest_over(f, 200.0, y)
  ok(format('under the pulled eave at y %.0f: its soffit, %.0f, all the way back to the wall', y, want), z && (z - want).abs < 0.01, z)
end
ok('under the far eave: the soffit where it always was', (lowest_over(f, 200.0, 246.0).to_f - 93.0).abs < 0.01 && (lowest_over(pf, 200.0, 246.0).to_f - 93.0).abs < 0.01)
ok('the rake board beside it is ONE board, from the ridge down to the new corner',
   f.any? { |ps| ps.sort == [[412.0, 120.0, 132.0], [412.0, -36.0, 93.0], [412.0, -36.0, 87.0], [412.0, 120.0, 126.0]].sort }, f.select { |ps| ps.all? { |p| p[0] == 412.0 } && ps.map { |p| p[1] }.min < 0 }.first(4))
ok('...the other rake too', f.any? { |ps| ps.sort == [[-12.0, 120.0, 132.0], [-12.0, -36.0, 93.0], [-12.0, -36.0, 87.0], [-12.0, 120.0, 126.0]].sort })
ok('the box return under the rake is as long as the wider board: its step stands on the wall line, 87.75 up to 96',
   f.any? { |ps| ps.all? { |p| p[1] == 0.0 } && ps.map { |p| p[2] }.minmax == [87.75, 96.0] && ps.map { |p| p[0] }.min >= 400.0 }, f.select { |ps| ps.all? { |p| p[1] == 0.0 } && ps.map { |p| p[2] }.min < 90 })
ok('the outline it says is its own is the one its planes rise from', fp(r) == fp(plain), fp(r))
ok('...and it says which eave is pulled, and how far', Array(r.get_attribute('InteriorPro', 'eave_pulls')) == [0, 24.0], r.get_attribute('InteriorPro', 'eave_pulls'))
ok('the plain roof says nothing of the kind', plain.get_attribute('InteriorPro', 'eave_pulls').nil?)
r0, = box_roof([], { 'a' => 0.0 })
ok('0 = face for face the roof with no pull', norm(faces(r0)) == norm(pf))
r2, log = box_roof(%w[b], { 'b' => 20.0, 'a' => 24.0 })
ok('a gable end AND the eave beside it, both pulled: the piece of plane runs to the new gable edge',
   log =~ /edge b pulled out 20"/ && log =~ /eave a pulled out 24"/ &&
   has?(faces(r2), [[-12.0, -12.0, 99.0], [-12.0, -36.0, 93.0], [432.0, -36.0, 93.0], [432.0, -12.0, 99.0]]), log.lines.grep(/pull/))

# ---- 3. where it is not built -------------------------------------------------------------------
r, log = box_roof([], { 'a' => 24.0 }, style: 'hip')
ok('a hip roof: left out, and it says so', log =~ /an eave pulled out is not built on this kind of roof yet/, log.lines.grep(/pull|eave/))
r, log = box_roof([], { 'a' => 24.0 }, gutter: true)
ok('with a gutter: the eave is pulled, and it says no gutter hangs there yet', log =~ /no gutter on a pulled-out eave yet/ && log =~ /eave a pulled out 24"/, log.lines.grep(/gutter|pull/))
RF.send(:remove_const, :USE_EAVE_PULL)
RF.const_set(:USE_EAVE_PULL, false)
r, log = box_roof([], { 'a' => 24.0 })
ok('switched off: the eave stays where it was - face for face - and it says so', norm(faces(r)) == norm(pf) && log =~ /carry a pull but are not Gable ends/, log.lines.grep(/pull/))
RF.send(:remove_const, :USE_EAVE_PULL)
RF.const_set(:USE_EAVE_PULL, true)

# ---- 4. his walls: the front eave beside the pulled-out gable ---------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],   # his ccdf86de: the long front wall
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],   # his 68ea3160
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def his(marks, pulls)
  Sketchup.reset_model!
  add_walls(WALLS)
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  quiet { RF.build_roof!(level: 1, pitch: 3.0, **KW) }
end

def house
  RF.roof_of_wall_id('h2')
end

def garage
  RF.roof_of_wall_id('gS')
end

his(%w[h5], { 'h5' => 36.0 })
B4 = { house: faces(house), garage: norm(faces(garage)), fp: fp(house), ridge: house.get_attribute('InteriorPro', 'ridge_z') }.freeze
log = his(%w[h5], { 'h5' => 36.0, 'h4' => 24.0 })
h = house
f = faces(h)
ok('his front eave is pulled 24" beside the gable that is pulled 36"', log =~ /edge h5 pulled out 36"/ && log =~ /eave h4 pulled out 24" - it ends 6\.0" lower/ &&
                                                                  log !~ /is not pulled out/, log.lines.grep(/pull/))
ok('the outline her planes rise from is the one she had; her ridge did not move', fp(h) == B4[:fp] && h.get_attribute('InteriorPro', 'ridge_z') == B4[:ridge], fp(h))
ok('...and the short eave of the gable goes out with it, and says so', log =~ /the short eave beside it \(no wall of its own\) goes out 24" with it/, log.lines.grep(/short eave/))
ok('the piece of plane of the long eave: from the old line (99) out 24" (93) - and it ends on the VALLEY, at the new corner',
   has?(f, [[-749.0, 452.5, 99.0], [-749.0, 428.5, 93.0], [-443.0, 428.5, 93.0], [-419.0, 452.5, 99.0]]), f.select { |ps| ps.include?([-749.0, 428.5, 93.0]) })
ok('the piece of plane of the gable s side: from ITS old line (99) out 24" (93), valley to the gable edge',
   has?(f, [[-419.0, 452.5, 99.0], [-443.0, 428.5, 93.0], [-443.0, 416.5, 93.0], [-419.0, 416.5, 99.0]]), f.select { |ps| ps.include?([-443.0, 416.5, 93.0]) }.first(3))
ok('the two meet at ONE height at the new corner - the fascia of the long eave, 93 down to 87, ends there',
   has?(f, [[-749.0, 428.5, 93.0], [-443.0, 428.5, 93.0], [-443.0, 428.5, 87.0], [-749.0, 428.5, 87.0]]), f.select { |ps| ps.all? { |p| p[1] == 428.5 } })
ok('...and the fascia of the short one starts there, at the same height',
   has?(f, [[-443.0, 428.5, 93.0], [-443.0, 416.5, 93.0], [-443.0, 416.5, 87.0], [-443.0, 428.5, 87.0]]), f.select { |ps| ps.all? { |p| p[0] == -443.0 } })
ok('the valley runs on to the new corner with no line drawn on it, like the valley above (both skins)', log =~ /2 edge\(s\) hidden on the valley between two pulled-out pieces/, log.lines.grep(/hidden/))
ok('nothing is left standing on the old line of the short eave (the wedge he saw)', f.none? { |ps| ps.all? { |p| p[0] == -419.0 } }, f.select { |ps| ps.all? { |p| p[0] == -419.0 } })
ok('the rake of the pulled-out gable is ONE board from its ridge down to the new corner',
   f.any? { |ps| ps.all? { |p| p[1] == 416.5 } && ps.include?([-443.0, 416.5, 93.0]) && ps.include?([-443.0, 416.5, 87.0]) && ps.include?([-276.5, 416.5, 134.63]) },
   f.select { |ps| ps.all? { |p| p[1] == 416.5 } && ps.map { |p| p[0] }.min < -420.0 })
[[-700.0, 440.0], [-500.0, 455.0], [-745.0, 450.0], [-445.0, 450.0]].each do |x, y|
  z = lowest_over(f, x, y)
  ok(format('under the long eave at (%.0f,%.0f): its flat soffit at 87, back to the wall', x, y), z && (z - 87.0).abs < 0.01, z)
end
# NO BOX AT THE FOOT OF THE GABLE (he, on the 36" box that stood there: "לפני שנגעת היא לא הייתה שם,
# אנחנו תיקנו אותה ביחד"): the side of the gable wears no flat board, the gable's own sloped board runs
# down over it to the corner, where it hangs at the height the long eave's flat board ends at.
[[-441.0, 450.0], [-430.0, 450.0], [-430.0, 462.0], [-441.0, 420.0], [-425.0, 422.0], [-410.0, 430.0], [-409.0, 463.0]].each do |x, y|
  z = lowest_over(f, x, y)
  want = 87.0 + 0.25 * (x + 443.0)
  ok(format('under the side of the gable at (%.0f,%.0f): the gable s own sloped board, %.2f - no flat board, no step', x, y, want), z && (z - want).abs < 0.01, z)
end
ok('...ONE board from behind the short fascia up to the ridge, all the way in to the wall',
   has?(f, [[-442.25, 417.25, 87.19], [-276.5, 417.25, 128.63], [-276.5, 464.5, 128.63], [-442.25, 464.5, 87.19]]),
   f.select { |ps| ps.any? { |p| p[0] == -442.25 && p[2] > 87.1 && p[2] < 87.3 } })
ok('no box stands at the foot of the gable: no step on the wall line, no skirt under the rake board',
   f.none? { |ps| ps.all? { |p| p[0] == -407.0 } && ps.map { |p| p[2] }.min < 90.0 } &&
   f.none? { |ps| ps.length == 3 && ps.all? { |p| p[1] == 417.25 } && ps.map { |p| p[0] }.min < -400.0 },
   f.select { |ps| ps.all? { |p| p[0] == -407.0 } })
ok('the long eave s flat board is cut square on the line of the short one (behind its fascia)',
   f.any? { |ps| ps.all? { |p| p[0] == -442.25 } && ps.map { |p| p[1] }.minmax == [429.25, 464.5] && ps.map { |p| p[2] }.minmax == [87.0, 87.75] })
ok('she says which eaves went out: the long one and the short one', Array(h.get_attribute('InteriorPro', 'eave_pulls')).each_slice(2).map { |_i, v| v } == [24.0, 24.0], h.get_attribute('InteriorPro', 'eave_pulls'))
ok('the west rake is one board down to the new corner (93 at y 428.5)',
   f.any? { |ps| ps.all? { |p| p[0] == -749.0 } && ps.include?([-749.0, 428.5, 93.0]) && ps.include?([-749.0, 428.5, 87.0]) && ps.map { |p| p[1] }.max > 600.0 })
ok('the garage roof is face for face the roof it was', norm(faces(garage)) == B4[:garage])
ok('under the pulled-out gable nothing changed', [[-380.0, 430.0], [-300.0, 460.0]].all? { |x, y| (lowest_over(f, x, y).to_f - lowest_over(B4[:house], x, y).to_f).abs < 0.01 })
log = his(%w[h5], { 'h5' => 36.0, 'h8' => 24.0 })
ok('her back eave: the gable beside it runs on past its own body (the pulled gable s side) - left, and it says so',
   log =~ /edge h8 is not pulled out: the gable beside it runs on past its own body/ && norm(faces(house)) == norm(B4[:house]), log.lines.grep(/pull/))
log = his(%w[h5], { 'h4' => 24.0 })
ok('the front eave with the gable NOT pulled: it runs straight on into the gable - left, and it says so',
   log =~ /edge h4 is not pulled out: the edge beside it runs straight on/, log.lines.grep(/pull/))
log = his([], { 'h5' => 24.0 })
ok('a wall with no edge of its own: said, nothing pulled', log =~ /1 wall\(s\) carry a pull but have no edge of their own on this roof/, log.lines.grep(/pull/))

# ---- 4b. USE_EAVE_CORNER_FOLLOW = false: the short eave stays and gets shorter, as it was ----
RF.send(:remove_const, :USE_EAVE_CORNER_FOLLOW)
RF.const_set(:USE_EAVE_CORNER_FOLLOW, false)
log = his(%w[h5], { 'h5' => 36.0, 'h4' => 24.0 })
fo = faces(house)
ok('switched off: only the long eave is pulled', log =~ /eave h4 pulled out 24"/ && log !~ /short eave beside it/, log.lines.grep(/pull|short/))
ok('off: the piece of plane: from the old eave line (99) out 24" (93), from the west gable to the foot of the pulled gable',
   has?(fo, [[-749.0, 452.5, 99.0], [-749.0, 428.5, 93.0], [-419.0, 428.5, 93.0], [-419.0, 452.5, 99.0]]))
ok('off: its fascia on the new line, 93 down to 87', has?(fo, [[-749.0, 428.5, 93.0], [-419.0, 428.5, 93.0], [-419.0, 428.5, 87.0], [-749.0, 428.5, 87.0]]),
   fo.select { |ps| ps.all? { |p| p[1] == 428.5 } })
[[-700.0, 440.0], [-500.0, 455.0], [-430.0, 462.0], [-745.0, 450.0]].each do |x, y|
  z = lowest_over(fo, x, y)
  ok(format('off: under it at (%.0f,%.0f): its soffit at 87, back to the wall', x, y), z && (z - 87.0).abs < 0.01, z)
end
# the inside corner, at the foot of the pulled-out gable (x -419)
ok('off: the short eave of the gable keeps its fascia on the stretch the outline lost (x -419, y 428.5..452.5, 93..99)',
   fo.any? { |ps| ps.all? { |p| p[0] == -419.0 } && ps.map { |p| p[1] }.minmax == [428.5, 452.5] && ps.map { |p| p[2] }.minmax == [93.0, 99.0] },
   fo.select { |ps| ps.all? { |p| p[0] == -419.0 } })
[[-413.0, 440.0], [-413.0, 458.0], [-413.0, 420.0]].each do |x, y|
  z = lowest_over(fo, x, y)
  ok(format('off: ...and its soffit at 93 under its own overhang at (%.0f,%.0f)', x, y), z && (z - 93.0).abs < 0.01, z)
end
ok('off: the box of the pulled eave is closed on that line: one upright face, 87 up to 93, from its fascia back to the wall',
   has?(fo, [[-419.0, 429.25, 87.0], [-419.0, 464.5, 87.0], [-419.0, 464.5, 93.0], [-419.0, 429.25, 93.0]]), fo.select { |ps| ps.all? { |p| p[0] == -419.0 } && ps.map { |p| p[2] }.min < 90 })
RF.send(:remove_const, :USE_EAVE_CORNER_FOLLOW)
RF.const_set(:USE_EAVE_CORNER_FOLLOW, true)

# ---- 5. the Roof End menu ------------------------------------------------------------------------------
class FakeView
  def initialize(w, pt); @w = w; @pt = pt; end
  def pick_helper; self; end
  def do_pick(_x, _y); 1; end
  def count; 1; end
  def path_at(_i); [@w]; end
  def inputpoint(_x, _y); Struct.new(:position).new(Geom::Point3d.new(@pt[0], @pt[1], 0.0)); end
  def invalidate; end
end
his(%w[h5], { 'h5' => 36.0 })
tool = InteriorPro::RoofGableTool.new
UI.next_inputbox = ['Hip', '24']
log = quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h4'), [-600.0, 464.5])) }
ok('the menu on the long front wall: Hip stays, 24 is saved, the eave is built', RF.edge_pulls == { 'h5' => 36.0, 'h4' => 24.0 } && RF.gable_wall_ids == %w[h5] &&
                                                                              log =~ /eave h4 pulled out 24"/, [RF.edge_pulls, RF.gable_wall_ids, log.lines.grep(/pull/)])
ok('...the same roof one Apply from nothing builds', norm(faces(house)) == norm(f))
UI.next_inputbox = ['Hip', '0']
quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h4'), [-600.0, 464.5])) }
ok('0 puts the eave back: face for face the roof before', RF.edge_pulls == { 'h5' => 36.0 } && norm(faces(house)) == norm(B4[:house]))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

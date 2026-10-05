# encoding: utf-8
# rt261 - A ROOF EDGE PULLED OUT (2026-10-05).
#
# "כלי משיכת קצוות של גגות" - and of the gable in the middle of his Aetna house:
# "הגג הקדמי של הגמלון צריך לבלוט קדימה כמו בתוכנית". Asked with a picture of his
# own roof (pull_question.png: 1 = click an edge and the whole edge comes out,
# 2 = only the tip of the ridge), he answered 1.
#
# The number lives on the model by wall id, beside the roof-end marks; the menu
# the Roof End tool opens for an edge carries it ("Pull out (in)"); the builder
# moves that edge of the outline straight out before anything else is worked out.
# Step 1: gable ends only.
#
# WHAT IS PINNED HERE:
#   * the pure rules: the outline with an edge pulled out; what he typed, in inches;
#   * the numbers saved on the model: set, changed, taken off, a wall that is gone;
#   * a plain gable house: the end comes out, nothing rises or drops, the wall of
#     the gable stays on its wall, the rake's soffit reaches the wall;
#   * an edge that is not a gable end, and a roof that dies into a wall: said, and
#     the roof is the roof it was;
#   * his walls: the gable in the middle pulled out - a wing now, but the mother
#     still gives up the triangle under it, still says it is a gable in the middle
#     and how far it is pulled, and the garage still meets it as one surface;
#   * the real path: the Roof End tool's own click, and the garage follows;
#   * the kill switch.
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

# ---- 1. the pure rules ------------------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:pull_edges) && RF.respond_to?(:edge_pulls) && RF.respond_to?(:save_edge_pull!) &&
                         RF.respond_to?(:set_edge_pull!) && RF.respond_to?(:parse_pull) && RF.const_defined?(:USE_EDGE_PULL, false))
SQ = [[0.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
HIS = [[0.0, 0.0], [330.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
if RF.respond_to?(:pull_edges)
  r = RF.pull_edges(SQ, %w[a b c d], { 'b' => 24.0 })
  ok('an end between two corners: it moves out, its two neighbours get longer',
     r == [[[0.0, 0.0], [624.0, 0.0], [624.0, 300.0], [0.0, 300.0]], %w[a b c d], { 'b' => 24.0 }], r)
  r = RF.pull_edges(SQ, %w[a b c d], { 'a' => 10.0 })
  ok('out is away from the house, whichever way the edge runs', r[0] == [[0.0, -10.0], [600.0, -10.0], [600.0, 300.0], [0.0, 300.0]], r[0])
  r = RF.pull_edges(HIS, %w[a x b c d], { 'x' => 36.0 })
  ok('the gable in the middle: a short edge with no wall joins it to the eave it stood on, the corner side just gets longer',
     r == [[[0.0, 0.0], [330.0, 0.0], [330.0, -36.0], [600.0, -36.0], [600.0, 300.0], [0.0, 300.0]], ['a', nil, 'x', 'b', 'c', 'd'], { 'x' => 36.0 }], r)
  r = RF.pull_edges([[0.0, 0.0], [200.0, 0.0], [400.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]], %w[a x a2 b c d], { 'x' => 20.0 })
  ok('a stretch with eave on BOTH sides: a short edge at each foot',
     r[0] == [[0.0, 0.0], [200.0, 0.0], [200.0, -20.0], [400.0, -20.0], [400.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]] &&
     r[1] == ['a', nil, 'x', nil, 'a2', 'b', 'c', 'd'], r)
  r = RF.pull_edges(SQ, %w[a b c d], { 'a' => 10.0, 'b' => 24.0 })
  ok('two neighbours pulled: the corner moves out both ways', r[0] == [[0.0, -10.0], [624.0, -10.0], [624.0, 300.0], [0.0, 300.0]], r[0])
  ok('nothing to pull: the very same outline', RF.pull_edges(SQ, %w[a b c d], {}) == [SQ, %w[a b c d], {}] &&
                                             RF.pull_edges(SQ, %w[a b c d], { 'zz' => 30.0 })[0] == SQ.map(&:dup))
  ok('an edge with no wall is never pulled', RF.pull_edges(SQ, ['a', nil, 'c', 'd'], { nil => 30.0 })[0] == SQ.map(&:dup))
  ok('a wild number is held to the limit', RF.pull_edges(SQ, %w[a b c d], { 'b' => 9999.0 })[0][1][0] == 600.0 + RF::EDGE_PULL_MAX)
end
if RF.respond_to?(:parse_pull)
  ok('typed: a bare number is inches', RF.parse_pull('36') == 36.0 && RF.parse_pull(' 12.5 ') == 12.5 && RF.parse_pull('24"') == 24.0)
  ok('typed: feet, and feet and inches', (RF.parse_pull("2'") - 24.0).abs < 0.001 && (RF.parse_pull("2'6\"") - 30.0).abs < 0.001, [RF.parse_pull("2'"), RF.parse_pull("2'6\"")])
  ok('typed: nothing, rubbish and a minus are 0', RF.parse_pull('') == 0.0 && RF.parse_pull('abc') == 0.0 && RF.parse_pull('-5') == 0.0 && RF.parse_pull(nil) == 0.0)
end

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

def fp(r)
  Array(r.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.to_f.round(1), y.to_f.round(1)] }
end

def gable_walls(r)
  r.entities.grep(Sketchup::Group).select { |e| e.name == 'InteriorPro_GableWall' }.map do |e|
    ps = e.entities.grep(Sketchup::Face).flat_map { |f| f.points.map { |p| [p.x.to_f.round(1), p.y.to_f.round(1)] } }
    [ps.map(&:first).minmax, ps.map(&:last).minmax]
  end
end

# the lowest face over plan point (x, y), on its own plane (nil = open)
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

KW = { style: 'gable', overhang: 12.0, fascia: true, fascia_depth: 6.0, drip: true, soffit: 'boxed' }.freeze

# ---- 2. the numbers saved on the model ----------------------------------------------------
Sketchup.reset_model!
BOX = [['a', 0.0, 0.0, 400.0, 0.0], ['b', 400.0, 0.0, 400.0, 240.0], ['c', 400.0, 240.0, 0.0, 240.0], ['d', 0.0, 240.0, 0.0, 0.0]].freeze
add_walls(BOX)
ok('a new model carries no pull', RF.edge_pulls == {})
quiet { RF.save_edge_pull!('b', 30) }
ok('saved by wall id', RF.edge_pulls == { 'b' => 30.0 }, RF.edge_pulls)
quiet { RF.save_edge_pull!('d', 12.5); RF.save_edge_pull!('b', 18) }
ok('a second wall, and the first one changed', RF.edge_pulls == { 'b' => 18.0, 'd' => 12.5 }, RF.edge_pulls)
quiet { RF.save_edge_pull!('d', 0) }
ok('0 takes it off', RF.edge_pulls == { 'b' => 18.0 }, RF.edge_pulls)
Sketchup.active_model.set_attribute('InteriorPro', 'roof_pull_wall_ids', %w[b gone])
Sketchup.active_model.set_attribute('InteriorPro', 'roof_pull_in', [18.0, 40.0])
quiet { RF.save_edge_pull!('a', -7) }
ok('a wall that is gone loses its number at the next save; a minus is 0', RF.edge_pulls == { 'b' => 18.0 }, RF.edge_pulls)
quiet { RF.save_edge_pull!('b', 0) }

# ---- 3. a plain gable house: one end pulled out ---------------------------------------------
def box_roof(marks, pulls, **kw)
  RF.roofs.each(&:erase!)
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  log = quiet { RF.build_roof!(level: 1, pitch: 4.0, **KW, **kw) }
  [RF.roofs.first, log]
end
plain, = box_roof(%w[b], {})
pf = norm(faces(plain))
r, log = box_roof(%w[b], { 'b' => 30.0 })
ok('the builder says so', log =~ /edge b pulled out 30"/, log.lines.grep(/pull/))
ok('that end stands 30" further out, the other three where they were',
   fp(r) == [[-12.0, -12.0], [442.0, -12.0], [442.0, 252.0], [-12.0, 252.0]] && fp(plain) == [[-12.0, -12.0], [412.0, -12.0], [412.0, 252.0], [-12.0, 252.0]], fp(r))
ok('nothing rose and nothing dropped', r.get_attribute('InteriorPro', 'eave_z') == plain.get_attribute('InteriorPro', 'eave_z') &&
                                      (r.get_attribute('InteriorPro', 'ridge_z').to_f - plain.get_attribute('InteriorPro', 'ridge_z').to_f).abs < 0.001)
ok('it is still a gable end, and so is the far one', r.get_attribute('InteriorPro', 'gable_edges') == plain.get_attribute('InteriorPro', 'gable_edges'))
ok('the wall of the gable stays ON its wall', gable_walls(r).map(&:first).sort == gable_walls(plain).map(&:first).sort &&
                                               gable_walls(r).map(&:first).include?([400.0, 400.0]), gable_walls(r))
fs = faces(r)
z_in = lowest_over(fs, 405.0, 60.0)
z_out = lowest_over(fs, 438.0, 60.0)
ok('under the long overhang the rake s soffit runs from the edge all the way in to the wall',
   z_in && z_out && (z_in - z_out).abs < 0.01 && lowest_over(faces(plain), 405.0, 60.0).to_f == z_in.to_f, [z_out, z_in, lowest_over(faces(plain), 405.0, 60.0)])
ok('past the old edge the plain roof had nothing', lowest_over(faces(plain), 438.0, 60.0).nil?)
r0, = box_roof(%w[b], { 'b' => 0.0 })
ok('0 = face for face the roof with no pull', norm(faces(r0)) == pf)

# ---- 4. where it is not built: said, and the roof is the roof it was ---------------------------
auto, = box_roof([], {})
af = norm(faces(auto))
r, log = box_roof([], { 'b' => 30.0 })
ok('a gable the STYLE chose, not he: not pulled, and it says why', log =~ /edge b is not pulled out: it is a gable end/ && norm(faces(r)) == af, log.lines.grep(/pull/))
RF.send(:remove_const, :USE_EAVE_PULL)
RF.const_set(:USE_EAVE_PULL, false)
r, log = box_roof(%w[b], { 'a' => 30.0 })
ok('an eave, with the eave pull switched off (step 1): not pulled, and it says so', log =~ /carry a pull but are not Gable ends.*: a$/ && norm(faces(r)) == pf, log.lines.grep(/pull/))
RF.send(:remove_const, :USE_EAVE_PULL)
RF.const_set(:USE_EAVE_PULL, true)
r, log = box_roof(%w[b], { 'b' => 30.0 }, style: 'shed')
ok('a shed: left out, and it says so', log =~ /a pulled edge is not built on this kind of roof yet/, log.lines.grep(/pull/))

# ---- 5. his walls: the gable in the middle pulled out -------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],   # his 68ea3160
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']   # his 4743a286
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

flog = his(%w[h5], {})
FLAT = { house: norm(faces(house)), garage: norm(faces(garage)), ge: garage.get_attribute('InteriorPro', 'eave_z').to_f,
         hr: house.get_attribute('InteriorPro', 'ridge_z').to_f }.freeze
cap0 = flog[/valley: (\d+)" of ridge cap left off/, 1].to_i
log = his(%w[h5], { 'h5' => 36.0 })
h = house
ok('the house says so, and still says it is a gable in the middle of her roof',
   log =~ /edge h5 pulled out 36"/ && log =~ /a gable in the middle of the roof: 285" wide/ && log !~ /not built here/, log.lines.grep(/pull|middle/))
ok('her outline: the gable s edge 36" out, joined to the eave by a short edge',
   fp(h).include?([-419.0, 452.5]) && fp(h).include?([-419.0, 416.5]) && fp(h).include?([-134.0, 416.5]) && fp(h).length == 6, fp(h))
ci = fp(h).index([-419.0, 416.5])
ok('she tells the roofs that meet her which edge it is, on which wall, and how far out',
   Array(h.get_attribute('InteriorPro', 'cross_edges')) == [ci] && Array(h.get_attribute('InteriorPro', 'cross_walls')) == %w[h5] &&
   Array(h.get_attribute('InteriorPro', 'cross_pulls')) == [36.0],
   [ci, h.get_attribute('InteriorPro', 'cross_edges'), h.get_attribute('InteriorPro', 'cross_pulls')])
ok('her ridge did not move', (h.get_attribute('InteriorPro', 'ridge_z').to_f - FLAT[:hr]).abs < 0.001)
ok('the wall of the gable stays on the wall (y 464.5), 48" behind the edge', gable_walls(h).any? { |xs, ys| xs == [-407.0, -146.0] && ys[0] == 464.5 }, gable_walls(h))
hf = faces(h)
[[-380.0, 420.0], [-380.0, 450.0], [-380.0, 460.0], [-300.0, 463.0], [-200.0, 440.0]].each do |x, y|
  want = 93.0 + ([x + 419.0, -134.0 - x].min) * 0.25
  z = lowest_over(hf, x, y)
  ok(format('under the gable at (%.0f,%.0f): its own soffit, %.2f - no shelf of the mother s eave, nothing open', x, y, want), z && (z - want).abs < 0.02, z)
end
ok('the short edge is an eave of its own: flat soffit at 93.0 under it', lowest_over(hf, -413.0, 430.0) == 93.0, lowest_over(hf, -413.0, 430.0))
ok('the garage still comes down 2.875" onto the gable s slope', (garage.get_attribute('InteriorPro', 'eave_z').to_f - FLAT[:ge]).abs < 0.001 &&
                                                              log =~ /set 2\.8[78]" lower/, [garage.get_attribute('InteriorPro', 'eave_z'), FLAT[:ge]])
cap1 = log[/valley: (\d+)" of ridge cap left off/, 1].to_i
ok('its ridge cap stops on the gable s edge - 36" sooner than before', cap0 > 0 && cap1 == cap0 + 36, [cap0, cap1])
ok('it still closes the wall of the gable above it, and ends on the gable', log =~ /closed the wall of the gable above this roof/ && log =~ /stands a gable here/)
PULLED = { house: norm(hf), garage: norm(faces(garage)) }.freeze

# ---- 6. the real path: the Roof End tool s own click ------------------------------------------------
class FakeView
  def initialize(w, pt); @w = w; @pt = pt; end
  def pick_helper; self; end
  def do_pick(_x, _y); 1; end
  def count; 1; end
  def path_at(_i); [@w]; end
  def inputpoint(_x, _y); Struct.new(:position).new(Geom::Point3d.new(@pt[0], @pt[1], 0.0)); end
  def invalidate; end
end
his(%w[h5], {})
tool = InteriorPro::RoofGableTool.new
UI.next_inputbox = ['Gable', '36']
g_before = garage
log = quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
box = UI.last_inputbox
ok('the menu of the edge shows its kind and its pull', box && box[:prompts] == ['Roof end', 'Pull out (in)'] && box[:defaults] == %w[Gable 0], box)
ok('the click saves the number', RF.edge_pulls == { 'h5' => 36.0 }, RF.edge_pulls)
ok('...the house is rebuilt with it, and the garage follows', log =~ /edge h5 pulled out 36"/ && !g_before.valid? &&
                                                             log =~ /the roof above changed - this roof is built again to meet it/, log.lines.grep(/pull|valley: the roof/))
ok('...and the two roofs are face for face what one Apply from nothing builds', norm(faces(house)) == PULLED[:house] && norm(faces(garage)) == PULLED[:garage])
UI.next_inputbox = ['Gable', '36']
quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
ok('opened again, the menu shows 36', UI.last_inputbox[:defaults] == %w[Gable 36], UI.last_inputbox[:defaults])
UI.next_inputbox = ['Gable', '0']
quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
ok('0 in the menu puts the edge back: face for face the roofs before the pull', RF.edge_pulls == {} && norm(faces(house)) == FLAT[:house] &&
                                                                              norm(faces(garage)) == FLAT[:garage])
UI.next_inputbox = ['Hip', '36']
log = quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
ok('a pull typed on a Hip end is saved (an eave, step 2) - and this wall, with no edge of its own, says why it is not built',
   RF.edge_pulls == { 'h5' => 36.0 } && RF.gable_wall_ids == [] && log !~ /pulled out 36"/, [RF.edge_pulls, log.lines.grep(/pull/)])
UI.next_inputbox = ['Dutch gable', '36']
quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
ok('a pull typed on a Dutch end is not saved', RF.edge_pulls == {}, RF.edge_pulls)
UI.next_inputbox = ['Hip', '0']
quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
UI.next_inputbox = nil
quiet { tool.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
ok('Cancel changes nothing', RF.edge_pulls == {} && RF.gable_wall_ids == [])

# ---- 7. set_edge_pull!: one call, the roofs that meet follow ------------------------------------------
his(%w[h5], {})
log = quiet { RF.set_edge_pull!(wall('h5'), 36) }
ok('set_edge_pull!: saved, built, followed - the same two roofs', RF.edge_pulls == { 'h5' => 36.0 } && norm(faces(house)) == PULLED[:house] &&
                                                               norm(faces(garage)) == PULLED[:garage] && log =~ /built again to meet it/)

# ---- 8. the kill switch -----------------------------------------------------------------------------------
RF.send(:remove_const, :USE_EDGE_PULL)
RF.const_set(:USE_EDGE_PULL, false)
log = his(%w[h5], { 'h5' => 36.0 })
ok('switched off: the number is ignored - face for face the roofs with no pull', norm(faces(house)) == FLAT[:house] && norm(faces(garage)) == FLAT[:garage] &&
                                                                              log !~ /pulled out/ && house.get_attribute('InteriorPro', 'cross_pulls').nil?)
RF.send(:remove_const, :USE_EDGE_PULL)
RF.const_set(:USE_EDGE_PULL, true)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

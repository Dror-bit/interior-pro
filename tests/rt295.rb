# encoding: utf-8
# rt295 - A GABLE END PULLED IN: A MINUS NUMBER (2026-10-09).
#
# He clicked the front gable of his garage (Aetna, wall 56280eb8) with the new
# Pull Roof Edge button, typed 24, and nothing moved: the garage's back runs into
# the house, the roof is built by the skeleton, and every pull on such a roof was
# refused. His words: "אני רוצה שהגמלון שאני נוגע בו יזוז".
#
# WHAT IS PINNED HERE:
#   * the pure rule: which edge of such a roof may come out, and why not;
#   * his walls: the garage's front gable 24" out - the outline, nothing rises or
#     drops, the wall of the gable stays on its wall, the soffit runs in to it with
#     no gap, the house roof is untouched;
#   * the real path: the button's own click; 0 puts it back face for face;
#   * where it is still not built (an eave, the gable on the line it dies into): said;
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
require './roof_pull_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager
TRACE = File.join(__dir__, 'roof_pull_trace.txt')
module UI
  class << self
    attr_accessor :said
    def messagebox(m); (@said ||= []) << m.to_s; nil; end
  end
end
UI.said = []

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

# ---- 1. the pure rule ------------------------------------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:abut_pull_plan) && RF.const_defined?(:USE_ABUT_PULL, false) && RF::USE_ABUT_PULL == true)
# a garage: edge 0 the line it dies into, 1 west eave, 2 front gable, 3 east eave
G = [[0.0, 300.0], [0.0, 0.0], [280.0, 0.0], [280.0, 300.0]].freeze
IDS = %w[ab w f e].freeze
t, w = RF.abut_pull_plan(G, IDS, [2], %w[ab], { 'f' => 24.0 })
ok('its front gable, square between two eaves: it comes out', t == { 'f' => 24.0 } && w.empty?, [t, w])
t, w = RF.abut_pull_plan(G, IDS, [2], %w[ab], { 'ab' => 24.0, 'w' => 10.0, 'zz' => 5.0 })
ok('the wall it dies into, an eave, a wall not on it: not taken, each with its reason',
   t.empty? && w['ab'] =~ /dies into/ && w['w'] =~ /not a gable end/ && w['zz'] =~ /no edge of its own/, w)
t, w = RF.abut_pull_plan(G, %w[ab w f e], [0, 2], %w[w], { 'ab' => 24.0 })
ok('a gable beside the wall it dies into: not taken', t.empty? && w['ab'] =~ /beside it/, w)
t, = RF.abut_pull_plan(G, IDS, [2], %w[ab], { 'f' => 9999.0 })
ok('a wild number is held to the limit', t == { 'f' => RF::EDGE_PULL_MAX }, t)

# ---- 2. his walls: the garage's front gable --------------------------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],   # his 56280eb8
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
KW = { style: 'gable', overhang: 12.0, fascia: true, fascia_depth: 6.0, drip: true, soffit: 'boxed' }.freeze

def his(marks, pulls)
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey, 'thickness' => th,
      'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1, 'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  quiet { RF.build_roof!(level: 1, pitch: 3.0, **KW) }
end

def wall(id)
  Sketchup.active_model.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == id }
end
def garage; RF.roof_of_wall_id('gS'); end
def house; RF.roof_of_wall_id('h2'); end
def fp(r); Array(r.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.to_f.round(1), y.to_f.round(1)] }; end
def faces(r); r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } }; end
def norm(fs); fs.map(&:sort).sort; end
def rawfaces(r, out = [])
  r.entities.each do |e|
    out << e.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } if e.is_a?(Sketchup::Face)
    rawfaces(e, out) if e.is_a?(Sketchup::Group)
  end
  out
end
def gable_walls(r)
  r.entities.grep(Sketchup::Group).select { |e| e.name == 'InteriorPro_GableWall' }.map do |e|
    ps = e.entities.grep(Sketchup::Face).flat_map { |f| f.points.map { |p| [p.x.to_f.round(1), p.y.to_f.round(1), p.z.to_f.round(1)] } }
    [ps.map { |p| p[0] }.minmax, ps.map { |p| p[1] }.minmax, ps.map { |p| p[2] }.minmax]
  end.sort
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

# ---- what this file pins (the header above is rt294's helpers, reused) ----------------------------------
# His rule: "אם זה מספר רגיל הוא יזוז קדימה ואם זה מינוס הוא יזוז אחורה, אבל לא יכול להיכנס לתוך הבית -
# זאת ההגבלה שלו". A minus number moves a gable end back towards its body, never past the wall it stands on.
#   * the pure rules: typed, saved, the outline, the floor at the overhang;
#   * a box roof: a gable pulled in 6" - the edge in, nothing rises or drops, the wall stays on its wall;
#     asked past the wall: held at the overhang, and it says so;
#   * an eave and a gable in the middle of a roof: refused, with a line;
#   * his garage (dies into a wall): its front gable pulled in, the back one too; the button; 0 puts it back;
#   * the kill switch.
BOXW = [['a', 0.0, 0.0, 400.0, 0.0], ['b', 400.0, 0.0, 400.0, 240.0], ['c', 400.0, 240.0, 0.0, 240.0], ['d', 0.0, 240.0, 0.0, 0.0]].freeze
def box_roof(marks, pulls, **kw)
  Sketchup.reset_model!
  BOXW.each do |id, sx, sy, ex, ey|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey, 'thickness' => 5.0,
      'base_z' => 0.0, 'height' => 96.0, 'level' => 1, 'wall_category' => 'exterior', 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  log = quiet { RF.build_roof!(level: 1, pitch: 4.0, **KW, **kw) }
  [RF.roofs.first, log]
end

# ---- 1. the pure rules --------------------------------------------------------------------------------------
ok('the code is loaded', RF.const_defined?(:USE_PULL_IN, false) && RF::USE_PULL_IN == true && RF.respond_to?(:pull_in_floor))
ok('typed: a minus number is a minus number, feet too', RF.parse_pull('-6') == -6.0 && RF.parse_pull('- 12') == -12.0 && (RF.parse_pull("-1'") + 12.0).abs < 0.001 &&
                                                       RF.parse_pull('6') == 6.0 && RF.parse_pull('0') == 0.0, [RF.parse_pull('-6'), RF.parse_pull("-1'")])
Sketchup.reset_model!
quiet { RF.save_edge_pull!('b', -6) }
ok('saved as a minus', RF.edge_pulls == { 'b' => -6.0 }, RF.edge_pulls)
quiet { RF.save_edge_pull!('b', -9999) }
ok('a wild minus is held to the limit', RF.edge_pulls == { 'b' => -RF::EDGE_PULL_MAX }, RF.edge_pulls)
quiet { RF.save_edge_pull!('b', 0) }
ok('0 takes it off', RF.edge_pulls == {})
sq = [[0.0, 0.0], [400.0, 0.0], [400.0, 240.0], [0.0, 240.0]]
r = RF.pull_edges(sq, %w[a b c d], { 'b' => -6.0 })
ok('the outline: the end moves IN, its two neighbours get shorter', r == [[[0.0, 0.0], [394.0, 0.0], [394.0, 240.0], [0.0, 240.0]], %w[a b c d], { 'b' => -6.0 }], r)
ok('the floor: never past the wall s outer face (overhang less half the wall)', RF.pull_in_floor({ 'b' => -6.0, 'c' => -30.0, 'd' => 4.0 }, 12.0, { 'c' => 2.5 }) == [{ 'b' => -6.0, 'c' => -9.5, 'd' => 4.0 }, { 'c' => -9.5 }])

# ---- 2. a box roof: a gable pulled in -------------------------------------------------------------------------
plain, = box_roof(%w[b], {})
PF = norm(faces(plain))
pfp = fp(plain)
pgw = gable_walls(plain)
r, log = box_roof(%w[b], { 'b' => -6.0 })
ok('the builder says so', log =~ /edge b pulled in 6"/ && log !~ /pulled out/, log.lines.grep(/pull/))
ok('that end stands 6" further in, the other three where they were', fp(r) == [[-12.0, -12.0], [406.0, -12.0], [406.0, 252.0], [-12.0, 252.0]] && pfp == [[-12.0, -12.0], [412.0, -12.0], [412.0, 252.0], [-12.0, 252.0]], fp(r))
ok('nothing rose and nothing dropped', r.get_attribute('InteriorPro', 'eave_z') == plain.get_attribute('InteriorPro', 'eave_z') &&
                                      (r.get_attribute('InteriorPro', 'ridge_z').to_f - plain.get_attribute('InteriorPro', 'ridge_z').to_f).abs < 0.001)
ok('the wall of the gable stays on its wall, as tall as it was', gable_walls(r) == pgw, [pgw, gable_walls(r)])
fs = rawfaces(r)
zs = [120.0, 60.0].map { |y| lowest_over(fs, 402.0, y) }
ok('under the 6" that is left: closed (the rake soffit, climbing with the gable)', zs.none?(&:nil?) && zs[0] > zs[1], zs)
IN6 = norm(faces(r))
r, log = box_roof(%w[b], { 'b' => -30.0 })
ok('asked past the wall: held at the wall s outer face (12 - 2.5), and it says so', log =~ /edge b pulled in only 9\.5" - the roof ends on the wall s outer face, never inside the house/ && log =~ /edge b pulled in 10"/, log.lines.grep(/pull/))
ok('...the edge lands on the wall s outer face (x 402.5), nothing goes inside', fp(r)[1] == [402.5, -12.0] && fp(r)[2] == [402.5, 252.0], fp(r))
r, log = box_roof(%w[b], { 'a' => -6.0 })
ok('an eave: not pulled in, and it says why', log =~ /edge a is not pulled out: an eave cannot be pulled in/ && norm(faces(r)) == PF, log.lines.grep(/pull/))

# ---- 3. his garage: in, from the button -------------------------------------------------------------------------
class FakeView
  def initialize(w); @w = w; end
  def pick_helper; self; end
  def do_pick(_x, _y); 1; end
  def count; 1; end
  def path_at(_i); [@w]; end
  def inputpoint(_x, _y); Struct.new(:position).new(Geom::Point3d.new(0.0, 0.0, 0.0)); end
  def invalidate; end
end
def click(id, typed)
  UI.next_inputbox = [typed]
  UI.said = []
  quiet { InteriorPro::RoofPullTool.new.onLButtonDown(0, 10, 10, FakeView.new(wall(id))) }
end
his(%w[h5], {})
F = { g: norm(faces(garage)), h: norm(faces(house)), fp: fp(garage), gw: gable_walls(garage) }
log = click('gS', '-6')
ok('the front gable of the garage, -6 from the button: built, no box', log =~ /edge gS pulled in 6"/ && UI.said.empty? && RF.edge_pulls == { 'gS' => -6.0 }, [log.lines.grep(/pull/), UI.said])
ok('its front edge stands 6" further in, the rest where it was', fp(garage) == F[:fp].map { |x, y| [x, y == 201.0 ? 207.0 : y] }, fp(garage))
ok('the wall of the gable stays on its wall; the house is untouched', gable_walls(garage) == F[:gw] && norm(faces(house)) == F[:h])
click('gS', '-40')
ok('past the wall: held at the wall s outer face (y 210.5), built, no box', fp(garage).include?([-334.5, 210.5]) && UI.said.empty?, [fp(garage), UI.said])
click('gS', '0')
ok('0 puts it back', RF.edge_pulls == {} && norm(faces(garage)) == F[:g])
log = click('gN', '-6')
ok('the back wall (on the line it dies into), -6: in along the house, the short edge runs the other way', log =~ /edge gN pulled in 6"/ && fp(garage).include?([-50.5, 475.5]) && fp(garage).include?([-148.5, 475.5]), [log.lines.grep(/pull/), fp(garage)])
click('gN', '0')
ok('0 puts it back', RF.edge_pulls == {} && norm(faces(garage)) == F[:g])
log = click('h5', '-6')
ok('a gable in the middle of the house roof: a minus is refused, with a line, and the roof is the roof it was',
   log =~ /a gable in the middle of the roof cannot be pulled in/ && norm(faces(house)) == F[:h] && UI.said.length == 1, [log.lines.grep(/pull/), UI.said])
click('h5', '0')

# ---- 4. the kill switch ---------------------------------------------------------------------------------------
RF.send(:remove_const, :USE_PULL_IN)
RF.const_set(:USE_PULL_IN, false)
r, log = box_roof(%w[b], { 'b' => -6.0 })
ok('switched off: a minus is read as 0, and it says so', log =~ /1 minus number\(s\) read as 0/ && norm(faces(r)) == PF, log.lines.grep(/minus|pull/))
quiet { RF.save_edge_pull!('b', -6) }
ok('...and the menu cannot save one', RF.edge_pulls == {}, RF.edge_pulls)
RF.send(:remove_const, :USE_PULL_IN)
RF.const_set(:USE_PULL_IN, true)

File.delete(TRACE) if File.exist?(TRACE)
puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

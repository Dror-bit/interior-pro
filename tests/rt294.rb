# encoding: utf-8
# rt294 - A GABLE END PULLED OUT ON A ROOF THAT DIES INTO A WALL (2026-10-09).
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

flog = his(%w[h5], {})
FLAT = { garage: norm(faces(garage)), house: norm(faces(house)), fp: fp(garage), gw: gable_walls(garage),
         ge: garage.get_attribute('InteriorPro', 'eave_z').to_f, gr: garage.get_attribute('InteriorPro', 'ridge_z').to_f }.freeze
ok('the garage really is a roof that dies into a wall, built by the skeleton (or this checks nothing)',
   flog =~ /the ridge runs INTO the wall this roof dies against/ && flog =~ /plan not decomposable/, flog.lines.grep(/INTO|decomposable/))
log = his(%w[h5], { 'gS' => 24.0 })
g = garage
ok('the garage says so', log =~ /edge gS pulled out 24"/ && log !~ /pull\(s\) left out/, log.lines.grep(/pull/))
ok('its front edge stands 24" further out, the rest of the outline where it was',
   fp(g) == FLAT[:fp].map { |x, y| [x, y == 201.0 ? 177.0 : y] } && FLAT[:fp].count { |_x, y| y == 201.0 } == 2, [FLAT[:fp], fp(g)])
ok('nothing rose and nothing dropped', (g.get_attribute('InteriorPro', 'eave_z').to_f - FLAT[:ge]).abs < 0.001 &&
                                      (g.get_attribute('InteriorPro', 'ridge_z').to_f - FLAT[:gr]).abs < 0.001)
ok('the wall of the gable stays on its wall, as tall as it was', gable_walls(g) == FLAT[:gw] && FLAT[:gw].any? { |_xs, ys, _zs| ys == [213.0, 213.0] },
   [FLAT[:gw], gable_walls(g)])
fs = rawfaces(g)
fs0 = nil
[-200.0, -320.0].each do |x|
  zs = [178.5, 185.0, 195.0, 200.0, 205.0, 209.0].map { |y| lowest_over(fs, x, y) }
  ok(format('under the new piece at x %.0f: closed from the new edge to the wall, at one height', x),
     zs.none?(&:nil?) && zs.uniq.length == 1, zs)
end
ok('the house roof is face for face what it was', norm(faces(house)) == FLAT[:house])
ok('the garage still comes down onto the house roof s slope', log =~ /valley: this roof is set 2\.8[78]" lower/ || flog !~ /set 2\.8[78]" lower/)
PULLED = norm(faces(g))

# ---- 3. the real path: the button ------------------------------------------------------------------------
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
log = click('gS', '24')
ok('his click on the garage front, 24: built, no box', log =~ /edge gS pulled out 24"/ && UI.said.empty? && RF.edge_pulls == { 'gS' => 24.0 }, [log.lines.grep(/pull/), UI.said])
ok('...face for face what one Apply from nothing builds', norm(faces(garage)) == PULLED && norm(faces(house)) == FLAT[:house])
click('gS', '0')
ok('0 puts it back: face for face the garage before', RF.edge_pulls == {} && norm(faces(garage)) == FLAT[:garage])

# ---- 4. where it is still not built: said ----------------------------------------------------------------
log = click('gW', '24')
ok('an eave of the garage: not pulled, and the box says why', log =~ /edge gW is not pulled out: it is not a gable end/ &&
                                                              UI.said.length == 1 && UI.said[0] =~ /not a gable end/ && norm(faces(garage)) == FLAT[:garage], [log.lines.grep(/pull/), UI.said])
click('gW', '0')
log = click('gN', '24')
ok('the gable on the line it dies into: built now (section 5), no box, nothing about the roofs meeting', log =~ /edge gN pulled out 24"/ && UI.said.empty?, [log.lines.grep(/pull/), UI.said])
click('gN', '0')

# ---- 5. the BACK wall of the garage: on the line it dies into, pulled back along the house ----------------
# He clicked it next (4b76e4cc, "1 wall(s) carry a pull but have no edge of their own") and said: "עד שהוא נוגע
# בגג אחר וזאת המגבלה - הוא לא יכול לגעת בגג בשיפוע מולו". Measured on his model (abut_back_report.txt): behind
# that wall the house roof only climbs away, so 120" touches nothing.
ok("the pure helpers are loaded", RF.respond_to?(:abut_pull_room) && RF.respond_to?(:abut_side_edges) && RF.respond_to?(:abut_side_index) &&
                                 RF.respond_to?(:faces_lowest_z) && RF.respond_to?(:roof_face_polys))
t, w = RF.abut_pull_plan([[0.0, 300.0], [0.0, 0.0], [280.0, 0.0], [280.0, 300.0], [100.0, 300.0]], %w[w f e bk ab], [1, 3], %w[ab], { "bk" => 120.0 })
ok("the plan: a gable on the line it dies into, between an eave and that line running straight on - it comes out", t == { "bk" => 120.0 } && w.empty?, [t, w])
p3, w3, = RF.pull_edges([[0.0, 300.0], [0.0, 0.0], [280.0, 0.0], [280.0, 300.0], [100.0, 300.0]], %w[w f e bk ab], { "bk" => 120.0 })
ok("the outline: the gable 120\" out, a short edge with no wall along the line it dies into",
   p3 == [[0.0, 300.0], [0.0, 0.0], [280.0, 0.0], [280.0, 420.0], [100.0, 420.0], [100.0, 300.0]] && w3 == ["w", "f", "e", "bk", nil, "ab"], [p3, w3])
ok("...and that short edge is known by name", RF.abut_side_edges(p3, w3, %w[ab]) == [[[100.0, 420.0], [100.0, 300.0]]] &&
                                             RF.abut_side_index(p3, w3, [[[100.0, 420.0], [100.0, 300.0]]]) == [4])
flat = [[[0.0, 0.0, 50.0], [100.0, 0.0, 50.0], [100.0, 100.0, 50.0], [0.0, 100.0, 50.0]]]
ok("the lowest face over a point", RF.faces_lowest_z(flat, 50.0, 50.0) == 50.0 && RF.faces_lowest_z(flat, 150.0, 50.0).nil? &&
                                   RF.faces_lowest_z(flat + [[[0.0, 0.0, 40.0], [100.0, 0.0, 40.0], [100.0, 100.0, 60.0], [0.0, 100.0, 60.0]]], 50.0, 50.0) == 50.0)
sq = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]]
ok("the room: nothing in front - all of it", RF.abut_pull_room(sq, 2, 60.0, ->(_x, _y) { 80.0 }, []) == 60.0)
ok("the room: a roof down on it 30\" out - it stops one step before", RF.abut_pull_room(sq, 2, 60.0, ->(_x, _y) { 80.0 }, [[[[-10.0, 130.0, 70.0], [110.0, 130.0, 70.0], [110.0, 200.0, 90.0], [-10.0, 200.0, 90.0]]]]) == 29.0)
ok("the room: a roof that climbs over it is no limit", RF.abut_pull_room(sq, 2, 60.0, ->(_x, _y) { 80.0 }, [[[[-10.0, 100.0, 81.0], [110.0, 100.0, 81.0], [110.0, 200.0, 120.0], [-10.0, 200.0, 120.0]]]]) == 60.0)

log = his(%w[h5], { "gN" => 120.0 })
g = garage
ok("his back wall, 120\": the garage says so, and the short edge along the house", log =~ /edge gN pulled out 120"/ && log =~ /a short edge along the wall behind, 120" long/ &&
                                                                                 log !~ /no edge of their own/ && log !~ /held to/, log.lines.grep(/pull|short edge|edge of their own/))
ok("its outline: the gable 120\" back, a short edge along the house wall, the rest where it was",
   fp(g) == [[-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0], [-50.5, 601.5], [-148.5, 601.5], [-148.5, 481.5]], fp(g))
ok("nothing rose and nothing dropped - and it still comes down onto the house", (g.get_attribute("InteriorPro", "eave_z").to_f - FLAT[:ge]).abs < 0.001 &&
                                                                               (g.get_attribute("InteriorPro", "ridge_z").to_f - FLAT[:gr]).abs < 0.001 && log =~ /set 2\.8[78]" lower/)
ok("the FRONT gable stays whole (not handed half to the eave by the new notch)", gable_walls(g) == FLAT[:gw], [FLAT[:gw], gable_walls(g)])
ok("the roofs that meet it read the short edge as no slope", Array(g.get_attribute("InteriorPro", "gable_edges")).map(&:to_i).sort == [1, 3, 4] &&
                                                             g.get_attribute("InteriorPro", "footprint_xy").length == 12, g.get_attribute("InteriorPro", "gable_edges"))
fs = rawfaces(g)
[-145.0, -100.0, -60.0].each do |x|
  zs = [470.0, 500.0, 540.0, 590.0, 600.0].map { |y| lowest_over(fs, x, y) }
  ok(format("under the new piece at x %.0f: closed from the house line to the new gable, at one height", x), zs.none?(&:nil?) && zs.uniq.length == 1, zs)
end
ok("the house roof is face for face what it was", norm(faces(house)) == FLAT[:house])
BACK = norm(faces(g))
his(%w[h5], {})
log = click("gN", "120")
ok("from the button: built, no box, face for face", log =~ /edge gN pulled out 120"/ && UI.said.empty? && norm(faces(garage)) == BACK, [log.lines.grep(/pull/), UI.said])
click("gN", "0")
ok("0 puts it back", RF.edge_pulls == {} && norm(faces(garage)) == FLAT[:garage])
log = his(%w[h5], { "gN" => 120.0, "gS" => 24.0 })
ok("front and back together: both out, the house untouched", log =~ /edge gN pulled out 120"/ && log =~ /edge gS pulled out 24"/ &&
                                                             fp(garage) == [[-334.5, 481.5], [-334.5, 177.0], [-50.5, 177.0], [-50.5, 601.5], [-148.5, 601.5], [-148.5, 481.5]] &&
                                                             norm(faces(house)) == FLAT[:house], fp(garage))

# ---- 6. the limit: a roof in front of it ---------------------------------------------------------------------
SHED = [["sW", -140.0, 760.0, -140.0, 700.0, 5.0, -18, "exterior"], ["sS", -140.0, 700.0, -60.0, 700.0, 5.0, -18, "exterior"],
        ["sE", -60.0, 700.0, -60.0, 760.0, 5.0, -18, "exterior"], ["sN", -60.0, 760.0, -140.0, 760.0, 5.0, -18, "exterior"]].freeze
def his3(marks, pulls)
  Sketchup.reset_model!
  (WALLS + SHED).each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { "type" => "wall", "id" => id, "start_x" => sx, "start_y" => sy, "end_x" => ex, "end_y" => ey, "thickness" => th,
      "base_z" => bz.to_f, "height" => 96.0, "level" => 1, "wall_category" => cat, "anchor" => "bottom-left" }.each { |k, v| g.set_attribute("InteriorPro", k, v) }
  end
  m = Sketchup.active_model
  m.set_attribute("InteriorPro", "roof_gable_wall_ids", marks)
  m.set_attribute("InteriorPro", "roof_pull_wall_ids", pulls.keys)
  m.set_attribute("InteriorPro", "roof_pull_in", pulls.values)
  quiet { RF.build_roof!(level: 1, pitch: 3.0, **KW) }
end
his3(%w[h5], {})
sh = RF.roof_of_wall_id("sS")
ok("a third building behind the garage, its eave facing it, its roof edge at y 688 (or this checks nothing)", RF.roofs.length == 3 && fp(sh).include?([-48.0, 688.0]), fp(sh))
log = his3(%w[h5], { "gN" => 240.0 })
ok("asked 240\": held where it would touch that roof, and it says so", log =~ /edge gN is held to 206" \(asked 240"\)/ && log =~ /edge gN pulled out 206"/, log.lines.grep(/held|pulled out/))
ok("...the new gable stands just short of that roof s edge", fp(garage).include?([-50.5, 687.5]) && fp(garage).include?([-148.5, 687.5]), fp(garage))
his3(%w[h5], {})
log = click("gN", "240")
ok("from the button: the number is kept, the roof is built held, and he is told once", RF.edge_pulls == { "gN" => 240.0 } && log =~ /held to 206"/ && UI.said.length == 1 && UI.said[0] =~ /\Aedge gN is held to 206" \(asked 240"\)/, UI.said)

# ---- 7. the kill switch -----------------------------------------------------------------------------------
RF.send(:remove_const, :USE_ABUT_PULL)
RF.const_set(:USE_ABUT_PULL, false)
log = his(%w[h5], { 'gS' => 24.0 })
ok('switched off: left out with the old line, face for face the garage with no pull',
   log =~ /a pulled edge is not built on this kind of roof yet.*gS/ && norm(faces(garage)) == FLAT[:garage], log.lines.grep(/pull/))
RF.send(:remove_const, :USE_ABUT_PULL)
RF.const_set(:USE_ABUT_PULL, true)

File.delete(TRACE) if File.exist?(TRACE)
puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt257 - A GABLE IN THE MIDDLE OF A ROOF (2026-10-02).
#
# "גמלון שהוא המשך של הקיר באמצע גג" - and, with the stamped Aetna roof plan
# and a red sketch on his own roof: "קודם אנחנו קובעים את גג האמא, הגג הגדול".
#
# MEASURED on his model the same day (gable_mark_report.txt): the wall he
# clicks, 68ea3160, lies on the line of the longer divider 4743a286 and
# behind the bridged entry recess - no edge of its own. A Gable mark on it
# was dropped: "[Roof] ignoring 1 stale/off-loop gable mark(s)" (item 2 of
# the roof audit he ran with ChatGPT), and nothing was built.
#
# WHAT IS PINNED HERE:
#   * the pure rule that finds that wall's own stretch of the eave;
#   * the pure rule that turns it into a wing with no depth;
#   * the real path, on his walls: the stretch becomes an edge of its own,
#     a gable stands on it, the mother slope is cut on its two valleys, and
#     nothing about the mark is "ignored" by the house roof any more;
#   * Hip style takes it too; no mark = the roof it always was;
#   * the kill switch brings the old answer back;
#   * the roof BELOW (his garage) meets it: set 2.875" lower onto its east
#     slope, not carried on, its cap stopped on the gable's edge, and what
#     lies under or in the gable cut off (USE_CROSS_JOIN);
#   * the wall of the gable, between the lower roof and the head of that wall,
#     is closed by the lower roof (USE_CROSS_WALL_CLOSE).
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

# ---- 1. the pure rule: which stretch of the eave is the marked wall's own --------
ok('the code is loaded', RF.respond_to?(:cross_gable_spans) && RF.respond_to?(:cross_wings))
RECT = [[0.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
IDS = %w[a b c d].freeze
# the outline before a recess was bridged: a | recess | k, with x merged into k
PRE = [[0.0, 0.0], [280.0, 0.0], [280.0, 40.0], [320.0, 40.0], [320.0, 0.5], [600.0, 0.5], [600.0, 300.0], [0.0, 300.0]].freeze
PRE_IDS = %w[a r1 r2 r3 k b c d].freeze
if RF.respond_to?(:cross_gable_spans)
  r = RF.cross_gable_spans(RECT, IDS, [], %w[x], PRE, PRE_IDS, { 'k' => %w[x] }, %w[a b c d x])
  ok('a marked wall merged into k: the stretch k covered before the recess was bridged', r == { 0 => [320.0, 600.0, 'x'] }, r)
  r = RF.cross_gable_spans(RECT, IDS, [], %w[k], PRE, PRE_IDS, {}, %w[a b c d k])
  ok('a marked wall that lost its own edge to the bridge: the same stretch, under its own id', r == { 0 => [320.0, 600.0, 'k'] }, r)
  r = RF.cross_gable_spans(RECT, IDS, [], %w[a], PRE, PRE_IDS, { 'k' => %w[x] }, %w[a b c d x])
  ok('a marked wall that HAS an edge is left to the old rule', r == {}, r)
  r = RF.cross_gable_spans(RECT, IDS, [], %w[x], PRE, PRE_IDS, { 'k' => %w[x] }, %w[a b c d])
  ok('a wall that is not this roof s own is not touched', r == {}, r)
  r = RF.cross_gable_spans(RECT, IDS, %w[a], %w[x], PRE, PRE_IDS, { 'k' => %w[x] }, %w[a b c d x])
  ok('never on an abut edge', r == {}, r)
  r = RF.cross_gable_spans(RECT, IDS, [], %w[r2], PRE, PRE_IDS, {}, %w[a b c d r2])
  ok('a wall at the back of the recess lies on no eave: nothing', r == {}, r)
  r = RF.cross_gable_spans(RECT, IDS, [], %w[x], nil, nil, { 'k' => %w[x] }, %w[x])
  ok('no outline to read: nothing, and no error', r == {}, r)
end

# ---- 2. the pure rule: a wing with no depth ---------------------------------------
if RF.respond_to?(:cross_wings)
  main = [0.0, 0.0, 600.0, 300.0]
  g = { n: false, s: false, e: true, w: true }
  poly = [[0.0, 0.0], [320.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]]
  ids = %w[a x b c d]
  w = RF.cross_wings(main, g, poly, ids, %w[x])
  ok('on the south slope: a rect lying on the eave line, mouth to the north',
     w == [{ rect: [320.0, 0.0, 600.0, 0.0], mouth: :n, gabled: true, cross: true }], w)
  w = RF.cross_wings(main, g, [[0.0, 0.0], [600.0, 0.0], [600.0, 300.0], [320.0, 300.0], [0.0, 300.0]], %w[a b x c d], %w[x])
  ok('on the north slope: mouth to the south',
     w == [{ rect: [320.0, 300.0, 600.0, 300.0], mouth: :s, gabled: true, cross: true }], w)
  w = RF.cross_wings(main, g, [[0.0, 0.0], [600.0, 0.0], [600.0, 100.0], [600.0, 300.0], [0.0, 300.0]], %w[a x b c d], %w[x])
  ok('on a gable END of the mother: cannot be built, says so with nil', w.nil?, w)
  w = RF.cross_wings(main, g, [[0.0, 0.0], [290.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]], %w[a x b c d], %w[x])
  ok('wider than the mother is deep (its ridge would reach hers): nil', w.nil?, w)
end

# ---- 3. the real path, on his walls ------------------------------------------------
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

def build(style, marks)
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  old = $stdout
  $stdout = StringIO.new
  begin
    RF.build_roof!(level: 1, style: style, pitch: 3.0)
    log = $stdout.string
  ensure
    $stdout = old
  end
  [RF.roof_of_wall_id('h2'), log]
end

def footprint(r)
  Array(r.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.round(2), y.round(2)] }
end

def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(1), p.y.to_f.round(1), p.z.to_f.round(1)] } }
end

def has_face?(fs, pts)
  fs.any? { |f| f.sort == pts.sort }
end

# the house roof's own lines of the log: everything up to its closing line
def house_log(log)
  out = []
  log.lines.each do |l|
    out << l
    break if l =~ /over level 1: eave 104/
  end
  out.join
end

plain, plog = build('gable', [])
pf = footprint(plain)
ok('no mark: the house outline is the four corners it always was', pf.length == 4, pf)
ok('no mark: gable ends on the two short ends only', plain.get_attribute('InteriorPro', 'gable_edges') == [0, 2],
   plain.get_attribute('InteriorPro', 'gable_edges'))
ok('no mark: no word about a gable in the middle', plog !~ /gable in the middle/)
plain_faces = faces(plain)

h, log = build('gable', %w[h5])
fp = footprint(h)
ge = Array(h.get_attribute('InteriorPro', 'gable_edges'))
ok('the marked wall s stretch is an edge of its own: from the recess to the corner',
   fp.include?([-419.0, 452.5]) && fp.length == 5, fp)
ci = fp.index([-419.0, 452.5])
ok('...and that edge is a gable end, beside the two the Gable style already had',
   ci && ge.include?(ci) && ge.length == 3, [ci, ge])
ok('the builder says so', log =~ /a gable in the middle of the roof: 285" wide, its ridge runs 142" into the slope/, house_log(log))
ok('the house roof no longer ignores the mark', house_log(log) !~ /ignoring \d+ stale/, house_log(log))
ok('the mark is kept on the roof', Array(h.get_attribute('InteriorPro', 'set_gables')) == %w[h5],
   h.get_attribute('InteriorPro', 'set_gables'))
ok('the ridge of the mother did not move', (h.get_attribute('InteriorPro', 'ridge_z').to_f - plain.get_attribute('InteriorPro', 'ridge_z').to_f).abs < 0.001)
fs = faces(h)
# eave underside 101.0 on the stub (z0 104 less 3" of overhang); the gable's ridge 142.5 * 0.25 = 35.6 higher
ok('the west slope of the gable: from the eave up to its own ridge and back to the valley point',
   has_face?(fs, [[-419.0, 452.5, 101.0], [-276.5, 452.5, 136.6], [-276.5, 595.0, 136.6]]), fs.select { |f| f.length == 3 })
ok('the east slope of the gable',
   has_face?(fs, [[-134.0, 452.5, 101.0], [-276.5, 452.5, 136.6], [-276.5, 595.0, 136.6]]))
ok('the mother slope is cut on the two valleys - no shelf of eave across the foot of the gable',
   has_face?(fs, [[-749.0, 452.5, 101.0], [-419.0, 452.5, 101.0], [-276.5, 595.0, 136.6], [-134.0, 452.5, 101.0],
                  [-134.0, 637.5, 147.3], [-749.0, 637.5, 147.3]]))
ok('the gable stays under the mother s ridge', fs.flatten(1).map { |p| p[2] }.max <= 147.8 + 0.01)
north = [[-134.0, 822.5, 101.0], [-749.0, 822.5, 101.0], [-749.0, 637.5, 147.3], [-134.0, 637.5, 147.3]]
ok('the far slope of the mother is the face it always was', has_face?(fs, north) && has_face?(plain_faces, north))

hh, hlog = build('hip', %w[h5])
ok('Hip style takes it too: one gable end, the one in the middle',
   Array(hh.get_attribute('InteriorPro', 'gable_edges')).length == 1 && hlog =~ /a gable in the middle of the roof/,
   [hh.get_attribute('InteriorPro', 'gable_edges'), house_log(hlog)])

# ---- 4. the kill switch ---------------------------------------------------------------
RF.send(:remove_const, :USE_CROSS_GABLE)
RF.const_set(:USE_CROSS_GABLE, false)
off, olog = build('gable', %w[h5])
ok('switched off: the outline is the four corners again', footprint(off).length == 4, footprint(off))
ok('switched off: the mark is ignored, as before', house_log(olog) =~ /ignoring 1 stale\/off-loop gable mark/, house_log(olog))
ok('switched off: face for face the roof with no mark', faces(off).map(&:sort).sort == plain_faces.map(&:sort).sort)
RF.send(:remove_const, :USE_CROSS_GABLE)
RF.const_set(:USE_CROSS_GABLE, true)

# ---- 5. THE ROOF BELOW MEETS THAT GABLE (USE_CROSS_JOIN) -------------------------------
# "קודם אנחנו קובעים את גג האמא, הגג הגדול, ואליו הגג של הגראז' מתחבר ומשתנה לפי גג
# האמא" / "החיבור הזה צריך להיות המשך לגג, אחרת המים ייתקעו". Measured on his model
# (cross_gable_report.txt + pictures): the garage's ridge ran on up the gable's east
# slope, 2.875" proud of it.
ok('the join code is loaded', RF.respond_to?(:cross_plane_over) && RF.respond_to?(:cross_flush_drop) &&
                              RF.respond_to?(:cross_trim_cap_lines) && RF.respond_to?(:cross_inside_regions))
if RF.respond_to?(:cross_plane_over)
  # his numbers: the gable from x -419 to -134 on the eave y 452.5, deck 99 on the edge, 3:12
  a = [-419.0, 452.5]
  b = [-134.0, 452.5]
  cr = [{ edge: 3, a: a, b: b, d: [1.0, 0.0], inw: [0.0, 1.0], len: 285.0,
          p0: RF.plane_abc(a, [1.0, 0.0], 0.25, 99.0), p1: RF.plane_abc(b, [-1.0, 0.0], 0.25, 99.0),
          base: RF.plane_abc(a, [0.0, 1.0], 0.25, 99.0) }]
  q = RF.cross_plane_over(cr, -240.0, 505.5)
  ok('over a point under the gable: its east plane', q && (RF.plane_z(q, -240.0, 505.5) - 125.5).abs < 0.01, q)
  ok('in front of its edge: not the gable', RF.cross_plane_over(cr, -240.0, 440.0).nil?)
  ok('past its valley, where the slope it stands on is higher: not the gable', RF.cross_plane_over(cr, -150.0, 500.0).nil?)
  ok('beside it: not the gable', RF.cross_plane_over(cr, -500.0, 500.0).nil?)
  # his garage: ridge on x -192.5, deck 81 on its edges at x -334.5 and -50.5
  gw = RF.plane_abc([-334.5, 300.0], [1.0, 0.0], 0.25, 81.0)
  ge = RF.plane_abc([-50.5, 300.0], [-1.0, 0.0], 0.25, 81.0)
  abut = [[-146.0, 481.5], [-1.0, 0.0]]
  d = RF.cross_flush_drop(gw, ge, abut, 188.5, cr, 6.0)
  ok('the garage comes down 2.875" onto the gable s east slope', (d - 2.875).abs < 0.001, d)
  ok('...never further than it is allowed', RF.cross_flush_drop(gw, ge, abut, 188.5, cr, 2.0) == 0.0)
  ok('no gable overhead: nothing', RF.cross_flush_drop(gw, ge, abut, 188.5, [], 6.0) == 0.0)
  # the garage's ridge cap, on its top skin after the drop, against the gable's top skin
  lift = 0.5 * Math.sqrt(1.0 + 0.0625)
  zr = 81.0 - 2.875 + 0.25 * 142.0 + lift
  ln = [[[-192.5, 201.0], zr, [-192.5, 481.5], zr, nil]]
  t = RF.cross_trim_cap_lines(ln, cr, lift)
  ok('the cap stops where the gable s roof begins', t.length == 1 && (t[0][2][1] - 452.5).abs < 0.01 && (t[0][0][1] - 201.0).abs < 0.01, t)
  hi = [[[-192.5, 201.0], zr + 2.875, [-192.5, 481.5], zr + 2.875, nil]]
  ok('a ridge that stands OVER the gable keeps its cap', RF.cross_trim_cap_lines(hi, cr, lift) == hi)
end

def garage_of
  RF.roof_of_wall_id('gS')
end

h, jlog = build('gable', %w[h5])
gar = garage_of
glog = jlog.split(/over level 1: eave 104.*\n/, 2)[1].to_s      # everything after the house's first build
ok('the mother says which of her edges is the gable in the middle',
   Array(h.get_attribute('InteriorPro', 'cross_edges')) == [footprint(h).index([-419.0, 452.5])], h.get_attribute('InteriorPro', 'cross_edges'))
_, plain_log = build('gable', [])
pg = garage_of.get_attribute('InteriorPro', 'eave_z').to_f
ok('with no gable up there the garage stands where it always stood, and is carried on',
   plain_log =~ /plane\(s\) carried on to the roof above/ && plain_log !~ /stands a gable here/, plain_log.lines.grep(/valley/).first(3))
build('gable', %w[h5])
gar = garage_of
ok('the garage roof is set 2.875" lower', (pg - gar.get_attribute('InteriorPro', 'eave_z').to_f - 2.875).abs < 0.001,
   [pg, gar.get_attribute('InteriorPro', 'eave_z')])
ok('...and says so', glog =~ /this roof is set 2\.8[78]" lower/, glog.lines.grep(/lower/))
ok('it is not carried on to a slope that is not there', glog =~ /stands a gable here - this roof ends on it/ && glog !~ /carried on to the roof above/)
ok('its ridge cap stops on the gable s edge', glog =~ /29" of ridge cap left off where this ridge runs into the gable/, glog.lines.grep(/cap/))
ok('what stands under the gable, or lies in its sheet, is cut off', glog =~ /3 region\(s\) of this roof cut off under the gable of the roof above \(1 of them lying in its sheet\)/,
   glog.lines.grep(/region/))
ok('the garage roof has no cross edge of its own', gar.get_attribute('InteriorPro', 'cross_edges').nil?)
if RF.respond_to?(:cross_inside_regions)
  gf = footprint(gar)
  flags = Array.new(gf.length, false)
  Array(gar.get_attribute('InteriorPro', 'gable_edges')).each { |i| flags[i] = true }
  rg = RF.cross_inside_regions(gf, flags, 0.25, gar.get_attribute('InteriorPro', 'eave_z').to_f - 3.0,
                               gar.get_attribute('InteriorPro', 'ridge_z').to_f, 1, gar)
  fl = rg.find { |r| r[:flush] }
  want = [[-192.5, 452.5], [-134.0, 452.5], [-163.0, 481.5], [-192.5, 481.5]]
  got = fl ? fl[:poly].map { |p| [p[0].round(1), p[1].round(1)] } : nil
  ok('the piece lying IN the gable s sheet: from the gable s edge back, between the garage s ridge and the valley',
     got && got.sort == want.sort, got)
  und = rg.reject { |r| r[:flush] }
  ok('the pieces UNDER the gable start on its WALL line - the strip under its rake overhang is kept',
     und.length == 2 && und.all? { |r| (r[:poly].map { |p| p[1] }.min - 464.5).abs < 0.01 }, und.map { |r| r[:poly].map { |p| p[1].round(1) }.min })
end

# ---- 6. NO LINE WHERE THE TWO ARE ONE SHEET (USE_CROSS_SEAM_HIDE) -------------------------
# Measured on his model (cross_join_top.png): the gable's own roof edge was drawn from
# the garage's ridge to the corner, across what is one surface. The stub's faces have no
# edges to hide, so what is pinned is WHICH lines each roof hands to the hide pass.
ok('the seam code is loaded', RF.respond_to?(:cross_cover_seams) && RF.respond_to?(:cross_region))
if RF.respond_to?(:cross_cover_seams)
  hm, = build('gable', %w[h5])
  mf = footprint(hm)
  sm = RF.cross_cover_seams(mf, 0.25, hm.get_attribute('InteriorPro', 'eave_z').to_f - 3.0,
                            hm.get_attribute('InteriorPro', 'ridge_z').to_f, 1, hm,
                            Array(hm.get_attribute('InteriorPro', 'cross_edges')))
  ends = sm.map { |_q, a2, b2| [a2, b2].map { |v| [v[0].round(1), v[1].round(1)] }.sort }
  ok('the mother hides her own gable edge from the garage s ridge to the corner - and nothing else',
     ends == [[[-192.5, 452.5], [-134.0, 452.5]]], ends)
  ok('...at the height of the gable s own plane there',
     sm.length == 1 && (RF.plane_z(sm[0][0], -192.5, 452.5) - (hm.get_attribute('InteriorPro', 'eave_z').to_f - 3.0 + 0.25 * 58.5)).abs < 0.01)
  ok('a roof with no gable in the middle hands out nothing',
     RF.cross_cover_seams(mf, 0.25, 101.0, 147.25, 1, hm, []) == [])
  RF.send(:remove_const, :USE_CROSS_SEAM_HIDE)
  RF.const_set(:USE_CROSS_SEAM_HIDE, false)
  ok('switched off: nothing is handed out',
     RF.cross_cover_seams(mf, 0.25, hm.get_attribute('InteriorPro', 'eave_z').to_f - 3.0,
                          hm.get_attribute('InteriorPro', 'ridge_z').to_f, 1, hm,
                          Array(hm.get_attribute('InteriorPro', 'cross_edges'))) == [])
  RF.send(:remove_const, :USE_CROSS_SEAM_HIDE)
  RF.const_set(:USE_CROSS_SEAM_HIDE, true)
end

# ---- 7. THE WALL OF THE GABLE, ABOVE THE LOWER ROOF (USE_CROSS_WALL_CLOSE) ----------------
# Measured on his model (white_tri_report.txt): a white triangle over the garage roof on
# the gable's wall line, x -317.5 .. -263, up to 96" - the inner wall between the house
# and the garage (4743a286, white), showing between the garage roof and the head of the
# wall the gable stands on. The garage roof closes it with one face in that wall's
# outside material.
ok('the closing code is loaded', RF.respond_to?(:cross_wall_closer) && RF.respond_to?(:cross_wall_closers))
if RF.respond_to?(:cross_wall_closer)
  a = [-419.0, 452.5]
  b = [-134.0, 452.5]
  c = { edge: 2, a: a, b: b, d: [1.0, 0.0], inw: [0.0, 1.0], len: 285.0,
        p0: RF.plane_abc(a, [1.0, 0.0], 0.25, 99.0), p1: RF.plane_abc(b, [-1.0, 0.0], 0.25, 99.0),
        base: RF.plane_abc(a, [0.0, 1.0], 0.25, 99.0) }
  gp = [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]]
  # his garage after it came down: deck 78.125 on its edges
  gw = RF.plane_abc([-334.5, 300.0], [1.0, 0.0], 0.25, 78.125)
  ge = RF.plane_abc([-50.5, 300.0], [-1.0, 0.0], 0.25, 78.125)
  r3 = lambda { |f| f && f.map { |p| p.map { |v| v.round(3) } } }
  f = r3.call(RF.cross_wall_closer(gp, 12.0, gw, ge, c, 12.0, 96.0))
  ok('his numbers: a triangle from the garage s wall line to where its roof reaches the head of the wall',
     f == [[-322.5, 464.5, 81.125], [-263.0, 464.5, 96.0], [-322.5, 464.5, 96.0]], f)
  ok('the slope that lies in the gable s sheet stands over the head of the wall: nothing',
     RF.cross_wall_closer(gp, 12.0, ge, gw, c, 12.0, 96.0).nil?)
  ok('a head of wall under the lower roof: nothing', RF.cross_wall_closer(gp, 12.0, gw, ge, c, 12.0, 80.0).nil?)
  f = r3.call(RF.cross_wall_closer(gp, 12.0, gw, ge, c, 12.0, 140.0))
  ok('a head of wall over the lower roof s ridge: four corners, and it stops on that ridge',
     f == [[-322.5, 464.5, 81.125], [-192.5, 464.5, 113.625], [-192.5, 464.5, 140.0], [-322.5, 464.5, 140.0]], f)
  far = gp.map { |x, y| [x, y - 300.0] }
  ok('a roof that never reaches the gable s wall line: nothing', RF.cross_wall_closer(far, 12.0, gw, ge, c, 12.0, 96.0).nil?)
end
hc, clog = build('gable', %w[h5])
gar = garage_of
ok('the mother says which wall her gable stands on',
   Array(hc.get_attribute('InteriorPro', 'cross_walls')) == %w[h5], hc.get_attribute('InteriorPro', 'cross_walls'))
gz = gar.get_attribute('InteriorPro', 'eave_z').to_f
xr = -322.5 + (96.0 - gz) / 0.25
tri = [[-322.5, 464.5, gz.round(1)], [xr.round(1), 464.5, 96.0], [-322.5, 464.5, 96.0]]
ok('the real path: the garage roof carries that face', has_face?(faces(gar), tri), [tri, faces(gar).select { |f| f.all? { |p| p[1] == 464.5 } }])
ok('...and says so', clog =~ /closed the wall of the gable above this roof, \d+" x \d+"/, clog.lines.grep(/closed/))
_, plog7 = build('gable', [])
ok('no gable up there: no such face', plog7 !~ /closed the wall of the gable/ && !has_face?(faces(garage_of), tri))
RF.send(:remove_const, :USE_CROSS_WALL_CLOSE) if RF.const_defined?(:USE_CROSS_WALL_CLOSE, false)
RF.const_set(:USE_CROSS_WALL_CLOSE, false)
_, olog7 = build('gable', %w[h5])
ok('switched off: not built', olog7 !~ /closed the wall of the gable/ && !has_face?(faces(garage_of), tri))
RF.send(:remove_const, :USE_CROSS_WALL_CLOSE)
RF.const_set(:USE_CROSS_WALL_CLOSE, true)

# the join switch alone: the gable stays, the garage is built as if it were not there
RF.send(:remove_const, :USE_CROSS_JOIN)
RF.const_set(:USE_CROSS_JOIN, false)
_, nlog = build('gable', %w[h5])
ok('join switched off: the garage is carried on as before and stands where it stood',
   nlog =~ /plane\(s\) carried on to the roof above/ && nlog !~ /stands a gable here/ &&
   (garage_of.get_attribute('InteriorPro', 'eave_z').to_f - pg).abs < 0.001)
RF.send(:remove_const, :USE_CROSS_JOIN)
RF.const_set(:USE_CROSS_JOIN, true)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

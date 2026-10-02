# encoding: utf-8
# rt245 - THE GARAGE'S BACK WALL GOES UP TO ITS ROOF (2026-10-01).
#
# His Aetna garage is wider than the house behind it: 83.5" of its back wall
# (4b76e4cc, drawn -62.5..-146 on y=470) has no house behind it. That wall
# is in line with the house wall the garage roof dies into, so the roof edge
# there is an ABUT edge: no eave, no gable, and the roof runs over the wall
# at full height. The wall stops at its own top (78") under a roof that is
# 85" to 107" up there - an open triangle. He looked at it twice: "החלק
# האחורי של הגראג' עדיין פתוח".
#
# Pinned on the pure rule, then on the real path with his walls: the wall is
# carried up to the roof's underside on its own outer face, standing on its
# own top, a wall thick; nothing is built over the part the house covers;
# the outline and the gable ends are what they were; Flat, "gable walls off"
# and the kill switch all leave it alone.
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
P3 = Struct.new(:x, :y)

# ---- 1. the pure rule ---------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:build_stub_wall_tops!) && RF.respond_to?(:wall_face_inboard))
if RF.respond_to?(:wall_face_inboard)
  # an edge running WEST from (-50.5, 481.5): inboard is south
  a = [-50.5, 481.5]
  d = [-1.0, 0.0]
  seg = { s: P3.new(-62.5, 467.5), e: P3.new(-146.0, 467.5) }
  ok('a 5" wall with its centreline 14" in has its outer face 11.5" in',
     (RF.wall_face_inboard(seg, a, d, 5.0) - 11.5).abs < 1e-6, RF.wall_face_inboard(seg, a, d, 5.0))
  ok('a wall that cannot be read gives nil', RF.wall_face_inboard(nil, a, d, 5.0).nil?)
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

def build(style, **kw)
  Sketchup.reset_model!
  m = Sketchup.active_model
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = m.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
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

# every wall-top prism of a roof: [[x, y, z] ..., push-pull depth]
def tops(r)
  r.entities.grep(Sketchup::Group).select { |g| g.name == 'InteriorPro_GableWall' }.flat_map do |g|
    g.entities.grep(Sketchup::Face).map { |f| [f.points.map { |p| [p.x.to_f, p.y.to_f, p.z.to_f] }, f.pushpulls] }
  end
end

def on_line(tops, y)
  tops.select { |pts, _| pts.all? { |p| (p[1] - y).abs < 0.01 } }
end

house, garage, log = build('gable')
ok('both roofs were built', house && garage)
if house && garage
  back = on_line(tops(garage), 470.0)
  ok('ONE wall top stands on the back wall\'s own outer face (y = 470)', back.length == 1, tops(garage))
  if back.length == 1
    pts, pp = back[0]
    xs = pts.map { |p| p[0] }
    zs = pts.map { |p| p[2] }
    ok('it runs the length of the wall the house does not cover (-60 to -148.5)',
       (xs.max - -60.0).abs < 0.6 && (xs.min - -148.5).abs < 0.6, [xs.min, xs.max])
    ok('it stands on the wall\'s own top, 78"', (zs.min - 78.0).abs < 0.01, zs.min)
    # underside of the deck: 83" at the eave line x = -50.5, rising 3:12 westward
    want = lambda { |x| 83.0 + (-50.5 - x) * 0.25 }
    top_pts = pts.select { |p| p[2] > 78.01 }
    ok('its top is the roof\'s underside: 85.4" at the east end, 107.5" at the house',
       top_pts.length >= 2 && top_pts.all? { |p| (p[2] - want.call(p[0])).abs < 0.1 },
       top_pts.map { |p| [p[0], p[2], want.call(p[0])] })
    ok('it is as thick as the wall (5")', pp.length == 1 && (pp[0].abs - 5.0).abs < 0.01, pp)
  end
  ok('the front gable end still has its own top, and there is nothing else',
     on_line(tops(garage), 213.0).length == 1 && tops(garage).length == 2, tops(garage).length)
  ok('nothing was stood on the HOUSE roof for it', on_line(tops(house), 470.0).empty? && on_line(tops(house), 464.5).empty?)
  ok('the builder says so in the console', log =~ /back wall gN raised to the roof/, log.lines.grep(/back wall/))
  # (rt246: the wall's stretch of the back line is an edge of its own now -
  # one more point ON the old line, and a second gable end)
  ok('the garage stands on the same four corners, its ridge on the same gable end',
     footprint(garage).sort == [[-334.5, 201.0], [-334.5, 481.5], [-148.5, 481.5], [-50.5, 201.0], [-50.5, 481.5]].sort &&
     gable_mids(garage) == [[-192.5, 201.0], [-99.5, 481.5]], [footprint(garage), gable_mids(garage)])
  ok('the house outline and its two gable ends are what they were',
     footprint(house).sort == [[-749.0, 452.5], [-749.0, 822.5], [-134.0, 452.5], [-134.0, 822.5]].sort &&
     gable_mids(house) == [[-749.0, 637.5], [-134.0, 637.5]], [footprint(house), gable_mids(house)])
  ok('the back wall still belongs to the garage roof', RF.roof_wall_ids(garage).include?('gN'), RF.roof_wall_ids(garage))
end

# Hip: the same wall, the same open end, the same closure
_h, gh, = build('hip')
bh = gh ? on_line(tops(gh), 470.0) : []
ok('Hip: the back wall is raised too', bh.length == 1, gh && tops(gh))
if bh.length == 1
  zs = bh[0][0].map { |p| p[2] }
  ok('Hip: from the wall top up to the roof', (zs.min - 78.0).abs < 0.01 && zs.max > 100.0, [zs.min, zs.max])
end

_f, gf, = build('flat')
ok('Flat: nothing is raised', gf.nil? || on_line(tops(gf), 470.0).empty?, gf && tops(gf))

_o, go, = build('gable', gable_walls: false)
ok('"gable walls" off: nothing is raised', go && tops(go).empty?, go && tops(go))

# ---- 3. the kill switch ---------------------------------------------------------
RF.send(:remove_const, :USE_STUB_WALL_TOPS) if RF.const_defined?(:USE_STUB_WALL_TOPS, false)
RF.const_set(:USE_STUB_WALL_TOPS, false)
_k, gk, lk = build('gable')
ok('kill switch: the back wall is left as it was (only the front gable top)',
   gk && on_line(tops(gk), 470.0).empty? && tops(gk).length == 1, gk && tops(gk).length)
ok('kill switch: and nothing is said about it', lk !~ /back wall/)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

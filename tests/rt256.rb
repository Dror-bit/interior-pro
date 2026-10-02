# encoding: utf-8
# rt256 - ONE SURFACE, ONE SHEET (2026-10-02, hip into hip, the garage brought down).
#
# The pictures after the caps were sorted: thin black lines across the flat
# stretch under the meeting point - the back line of the garage, the old rib,
# and the outline of the house roof's corner. Measured (corner_hole_report.txt):
# the house's east slope still ran whole into its corner UNDER the garage roof,
# in the very same plane (99.0 / 99.5 on both roofs).
#
# Pinned: the taller roof gives up the part of its other slope the lower roof
# lies on; the edges the two then share are named, on both roofs, and hidden;
# a gable house and a roof standing over a step are left alone where they
# should be; the kill switch.
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
ok('the code is loaded', RF.respond_to?(:valley_cover_polys) && RF.respond_to?(:valley_abut_flush) &&
                         RF.respond_to?(:valley_flush_rib_edges) && RF.respond_to?(:valley_hide_seams!))
def r2(pts); pts.map { |p| [p[0].round(2), p[1].round(2)] }; end

# ---- 1. the pure rules, on HIS numbers (the garage already 2.875" down) ----------
GAR = { pts: [[-50.5, 481.5], [-146.0, 481.5], [-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0]],
        slope: 0.25, deck_z: 78.125, ridge_z: 113.625, gables: [0], level: 1 }.freeze
HOUSE = { pts: [[-749.0, 822.5], [-749.0, 452.5], [-134.0, 452.5], [-134.0, 822.5]],
          slope: 0.25, deck_z: 99.0, ridge_z: 145.25, gables: [], level: 1 }.freeze
if RF.respond_to?(:valley_cover_polys)
  w = RF.edge_plane(GAR, 2)
  e = RF.edge_plane(GAR, 4)
  hs = RF.edge_plane(HOUSE, 1)
  he = RF.edge_plane(HOUSE, 2)
  oth = RF.valley_other_planes(HOUSE, 1)
  trim = { j: [-192.5, 511.0], rib: RF.planes_meet(hs, he), lo: [w, e], hp: hs, q: he, others: oth, lo_pts: GAR[:pts] }
  cv = RF.valley_cover_polys(HOUSE[:pts], [trim])
  ok('the house gives up ONE piece of its east slope: the corner under the garage roof',
     cv.length == 1 && (r2(cv[0][:poly]) - [[-146.0, 481.5]]).sort == [[-163.0, 481.5], [-134.0, 452.5], [-134.0, 481.5]] &&
     (RF.poly_area2(cv[0][:poly]).abs / 2.0 - 420.5).abs < 0.1, cv.map { |c| r2(c[:poly]) })   # 29 x 29 / 2; the garage's own corner at -146 rides along on the back line
  ok('...at the height of that slope (99 at the eave, 106.25 where the rib crosses the garage\'s back line)',
     cv[0] && cv[0][:poly].all? { |p| (p[2] - RF.plane_z(he, p[0], p[1])).abs < 0.001 } &&
     cv[0][:poly].map { |p| p[2].round(2) }.minmax == [99.0, 106.25], cv[0] && cv[0][:poly])
  seams = cv[0] ? cv[0][:seams].map { |a, b| r2([a, b]).sort } : []
  back = seams.select { |sg| sg.all? { |v| v[1] == 481.5 } }
  ok('the edges left on the open slope: the garage\'s back line across it, x -163 to -134...',
     back.flatten(1).map { |v| v[0] }.minmax == [-163.0, -134.0] && (back.sum { |a, b| (a[0] - b[0]).abs } - 29.0).abs < 0.01, seams)
  ok('...and the rib from there up to where the garage\'s ridge arrives', seams.include?([[-192.5, 511.0], [-163.0, 481.5]]), seams)
  # (2026-10-02, second run on his model: the skin's edge face on the house's eave still stood under the garage roof,
  #  its top edge 29" of black line IN the garage's sheet - so the eave side of the cut is one of them too)
  ok('...and the house\'s own eave under the garage roof, y 452.5 to 481.5', seams.include?([[-134.0, 452.5], [-134.0, 481.5]]), seams)
  ok('nothing to trim (a gable house): nothing is given up', RF.valley_cover_polys(HOUSE[:pts], []) == [])

  abut = [[-146.0, 481.5], [-1.0, 0.0]]
  fl = RF.valley_abut_flush(w, e, hs, oth, abut, 188.5, HOUSE[:pts])
  ok('the garage ends IN the house\'s east slope from the rib (x -163) to the house\'s own eave (x -134) - 12" past the abut edge',
     fl.length == 1 && r2(fl[0][2, 2]).sort == [[-163.0, 481.5], [-134.0, 481.5]], fl.map { |x| r2(x[2, 2]) })
  hi = GAR.merge(deck_z: 81.0)
  ok('the garage standing 2.9" over that slope: no flush stretch (the step faces close it instead)',
     RF.valley_abut_flush(RF.edge_plane(hi, 2), RF.edge_plane(hi, 4), hs, oth, abut, 188.5, HOUSE[:pts]) == [])
  polys = RF.valley_carry_tris(w, e, hs, abut, 188.5, oth)
  fe = RF.valley_flush_rib_edges(polys, hs, oth).map { |_pl, a, b| r2([a, b]).sort }
  ok('of the carried pieces\' edges, the one lying IN the house\'s rib is the east piece\'s', fe == [[[-192.5, 511.0], [-163.0, 481.5]]], fe)
  ok('...and none when the garage stands over the rib', RF.valley_flush_rib_edges(RF.valley_carry_tris(RF.edge_plane(hi, 2), RF.edge_plane(hi, 4), hs, abut, 188.5, oth), hs, oth) == [])
end

# ---- 2. hiding: only the stretch, only at that height ---------------------------
if RF.respond_to?(:valley_hide_seams!)
  P = Geom::Point3d
  Sketchup.reset_model!
  g = Sketchup.active_model.entities.add_group
  pl = [-0.25, 0.0, 65.5]                                         # the house's east slope
  on = g.entities.add_line(P.new(-163.0, 481.5, 106.25), P.new(-146.0, 481.5, 102.0))
  below = g.entities.add_line(P.new(-163.0, 481.5, 105.73), P.new(-146.0, 481.5, 101.48))   # the deck's edge, half an inch under
  off = g.entities.add_line(P.new(-163.0, 470.0, 106.25), P.new(-146.0, 470.0, 102.0))
  past = g.entities.add_line(P.new(-134.0, 481.5, 99.0), P.new(-50.5, 481.5, 78.125))
  n = RF.valley_hide_seams!(g, [[pl, [-163.0, 481.5], [-134.0, 481.5]]])
  ok('the edge on the stretch is hidden', on.hidden?)
  # (measured on his model: smoothing it smeared the garage's slope dark - the edge also carries the slab's upright strip)
  ok('...HIDDEN only: it is not smoothed, so the sheet\'s shading is not blended with an upright face', !on.soft? && !on.smooth?)
  ok('the deck edge under it is not touched - nobody sees it, and it is another height', !below.hidden?)
  ok('an edge beside the line is not touched', !off.hidden?)
  ok('an edge past the end of the stretch is not touched', !past.hidden?)
  ok('it says how many', n >= 1, n)
end

# ---- 3. the real path, on his walls ----------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'], ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'], ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'], ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'], ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'], ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'], ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze
def build(style)
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
    RF.build_roof!(level: 1, style: style, pitch: 3.0, soffit: 'boxed')
    $stdout.string
  ensure
    $stdout = old
  end
end
log = build('hip')
ok('hip into hip: the house cuts its east slope where the garage lies on it',
   log =~ /face\(s\) of this roof taken out where the lower roof lies on its other slope/, log.lines.grep(/taken out where/))
ok('...and hides the edges it shares with the garage', log =~ /edge\(s\) hidden where this roof and the lower one are one surface/, log.lines.grep(/hidden where/))
ok('the garage hides its own edges on the same lines', log =~ /edge\(s\) hidden where this roof and the taller one are one surface/, log.lines.grep(/hidden where/))
ok('...and the joint between its own sheet and the piece carried on (the line that stayed from the ridge to the rib)',
   log =~ /edge\(s\) hidden on the line where this roof's sheet carries on/, log.lines.grep(/hidden/))
lg = build('gable')
ok('gable into gable: nothing is taken out and nothing is hidden this way', lg !~ /taken out where the lower roof lies/ && lg !~ /are one surface/,
   lg.lines.grep(/taken out where|one surface/))
set_const(:USE_VALLEY_FLUSH_CLEAN, false)
lk = build('hip')
ok('kill switch: both roofs are left as they were', lk !~ /taken out where the lower roof lies/ && lk !~ /edge\(s\) hidden where/, lk.lines.grep(/taken out where|hidden where/))
set_const(:USE_VALLEY_FLUSH_CLEAN, true)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

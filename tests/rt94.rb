# encoding: utf-8
# rt94 - A SHED'S LEVEL TOP EDGE GETS ITS EAVE DRESS (2026-08-26).
#
# WHAT THIS IS
# The top edge of a shed sat in `gables`, so it got a rake board and no
# fascia, no drip, no soffit - and the eave bands are all built at
# band_top, the LOW eave's height, a storey below it. The user marked
# the bare top edge in yellow and asked for the same dress the low eave
# has ("וגם תתקן את הפשייה והאיבס"), and approved the section sketch.
#
# THE CLAIMS PINNED HERE
# 1. level_gable_edges tells a shed's level top edge from a real rake
#    BY SHAPE - and calls NO edge of a plain gable end level.
# 2. level_edge_band_top reads the roof underside ON the edge's own
#    line - the analogue of band_top = z0 - slope*overhang for the low
#    eave, a storey higher.
# 3. THE REAL BUILD: the top edge carries a fascia band hanging from
#    that height, a drip on its outer face, and a soffit board under
#    its overhang - while the low eave's own bands stay where they were.
#
# Fails against the code before the fix: level_edge_band_top does not
# exist there, and no band face sits anywhere near the top edge height.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

module Sketchup
  class Face
    attr_accessor :pts, :pulled, :material, :back_material
    def normal
      a, b, c = @pts[0], @pts[1], @pts[2]
      u = Geom::Vector3d.new(b.x - a.x, b.y - a.y, b.z - a.z)
      v = Geom::Vector3d.new(c.x - a.x, c.y - a.y, c.z - a.z)
      (u * v).normalize
    end
    def pushpull(d); @pulled = d; end
    def reverse!; @pts = @pts.reverse; self; end
  end
  class Entities
    def add_face(pts)
      f = Face.new
      f.pts = pts
      @list << f
      f
    end
  end
end

require './room_manager'
require './level_manager'
require './roof_manager'

# THE RAISED HEEL IS OFF IN HERE (2026-09-06). Every z in this suite was
# measured when the roof's underside met the wall top exactly, and the
# eave tail fell slope x overhang BELOW it. He asked for that tail to be
# lifted level with the wall corner instead, which moves every roof up by
# that same amount - so the whole roof, not this suite's subject, would be
# under test. rt118 pins the heel itself; here it stays off, exactly the
# way rt85 already switches off the abut cap.
module InteriorPro
  module RoofManager
    def self.heel_lift(_overhang, _slope, _drop = 0.0)
      0.0
    end
  end
end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.05)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RM = InteriorPro::RoofManager

# ---------------- 1. level_gable_edges - PURE, by shape
SQ = [[0.0, 0.0], [400.0, 0.0], [400.0, 300.0], [0.0, 300.0]]
ONE = [{ pts: SQ, eave: 0 }]       # one plane, draining to edge 0 (a shed)
ok('on a shed, the edge OPPOSITE the eave is level',
   RM.level_gable_edges(SQ, [1, 2, 3], ONE) == [2],
   RM.level_gable_edges(SQ, [1, 2, 3], ONE))
# a gable: two cells, each draining to its own eave; the gable ends (1
# and 3) run square to their own eave, so NONE of them is level
TWO = [{ pts: [[0.0, 0.0], [400.0, 0.0], [400.0, 150.0], [0.0, 150.0]], eave: 0 },
       { pts: [[0.0, 150.0], [400.0, 150.0], [400.0, 300.0], [0.0, 300.0]], eave: 2 }]
ok('on a plain gable, no gable end is level',
   RM.level_gable_edges(SQ, [1, 3], TWO) == [],
   RM.level_gable_edges(SQ, [1, 3], TWO))
ok('no cells, no level edges', RM.level_gable_edges(SQ, [1, 2, 3], nil) == [])

# ---------------- 2. level_edge_band_top - PURE
SLOPE = 1.0 / 3.0
Z0 = 102.0
OH = 12.0
# the roof underside ON edge 2 (the line y = 300): band_top + slope * 300
zt = RM.level_edge_band_top(SQ, 2, ONE, Z0, SLOPE, OH)
ok('the top edge band hangs from the roof underside on its own line',
   close(zt, 98.0 + SLOPE * 300.0, 0.02), zt)
ok('...a full storey above band_top, not at it', zt - 98.0 > 60.0, zt)
ok('no surface, no height', RM.level_edge_band_top(SQ, 2, nil, Z0, SLOPE, OH).nil?)

# ---------------- 3. THE REAL BUILD - the user's own rectangle
def make_wall(m, id, s, e)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => 'bottom-center', 'height' => 102.0, 'base_z' => 0.0,
    'level' => 1, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'D', [-218.5, 2.5], [-2.5, 2.5])       # south - the low eave
make_wall(m, 'A', [-2.5, 2.5], [-2.5, 208.7])       # east  - rakes
make_wall(m, 'B', [-2.5, 208.7], [-218.5, 208.7])   # north - the high wall
make_wall(m, 'C', [-218.5, 208.7], [-218.5, 2.5])   # west  - rakes
m.set_attribute('InteriorPro', 'roof_shed_wall_ids', ['D'])

FD = 6.0
roof = RM.build_roof!(style: 'shed', pitch: 4, overhang: 12, thickness: 0.5,
                      ridge_cap: true, fascia: true, drip: true,
                      soffit: 'boxed', fascia_depth: FD)
ok('the shed builds', !roof.nil?)

# the top poly edge: the building's outer face (y=211.2) plus the
# overhang - the eave polygon runs on the OUTER faces, not the
# centrelines (measured off the real build, 2026-08-26)
YT = 211.2 + 12.0
YLOW = -12.0                       # the low eave line, same rule
ZE = 98.0 + SLOPE * (YT - YLOW)    # roof underside on the top line: 176.4
faces = roof.entities.grep(Sketchup::Face)

on_line = lambda do |f, ylo, yhi, zlo, zhi|
  ys = f.pts.map(&:y)
  zs = f.pts.map(&:z)
  ys.min >= ylo - 0.05 && ys.max <= yhi + 0.05 &&
    zs.min >= zlo - 0.05 && zs.max <= zhi + 0.05
end

# fascia: k in [-0.75, 0] of the top line, hanging FD + 1/4 down from
# ZE - the extra quarter inch lands it flush with the rake board's
# bottom at the shared corner (the user, 2026-08-26)
fas = faces.select { |f| on_line.call(f, YT - 0.8, YT, ZE - FD - 0.25, ZE) }
ok('the top edge has fascia faces at ITS height', fas.length >= 4, fas.length)
ok('...hanging from the roof underside there',
   fas.flat_map { |f| f.pts.map(&:z) }.max.then { |z| close(z, ZE, 0.1) },
   fas.flat_map { |f| f.pts.map(&:z) }.max)
ok('...a quarter inch deeper than the eave depth, flush with the rake',
   fas.flat_map { |f| f.pts.map(&:z) }.min
      .then { |z| close(z, ZE - FD - 0.25, 0.05) },
   fas.flat_map { |f| f.pts.map(&:z) }.min)
ok('...and spanning most of the edge',
   fas.flat_map { |f| f.pts.map(&:x) }.minmax
      .then { |lo, hi| hi - lo > 150.0 },
   fas.flat_map { |f| f.pts.map(&:x) }.minmax)

# drip: just outside the top line
drp = faces.select { |f| on_line.call(f, YT, YT + 0.15, ZE - 2.1, ZE) }
ok('the top edge has a drip on its outer face', drp.length >= 4, drp.length)

# THE CLOSED CORNER (2026-08-26, the user's red circles): the fascia is
# cut SQUARE and runs through the corner onto the rake board's OUTER
# face, and the drip one drip-thickness further, onto the rake drip's
# outer face. A mitred 45 end stopped short and left a notch beside the
# rake's top end.
# THE RAKE MOVED IN (2026-09-09): it used to stand 0.75 OUTSIDE the poly
# line, so these two wraps ran to 12.75 and 12.85. Now the rake fascia
# fills -0.75..0 like the eave's - its outer face IS the poly line at
# x=12 - so the fascia wraps to 12.0 and the drip to 12.1.
# `fas` also catches the drip's own end cap (a face planar at y=YT), so
# the fascia's reach is read off the faces that go the board's full
# depth, deeper than the 2" drip.
fx = fas.select { |f| f.pts.map(&:z).min < ZE - 2.5 }
        .flat_map { |f| f.pts.map(&:x) }.max
ok('the fascia wraps the corner onto the rake board outer face',
   close(fx, 12.0, 0.1), fx)
dx = drp.flat_map { |f| f.pts.map(&:x) }.max
ok('...and the drip wraps one step further, onto the rake drip',
   close(dx, 12.1, 0.1), dx)

# ...and the LOW eave's metal edge wraps its two corners the same way
# (2026-08-26, the user: every corner, not just two). Its band is just
# outside the low line y=-12, and its ends now run onto the rake drips.
lowdrp = faces.select { |f| on_line.call(f, YLOW - 0.15, YLOW, 95.8, 98.1) }
ok('the low eave has its drip', lowdrp.length >= 4, lowdrp.length)
lx = lowdrp.flat_map { |f| f.pts.map(&:x) }.minmax
ok('...and it wraps BOTH low corners onto the rake drips',
   close(lx[1], 12.1, 0.1) && close(lx[0], -233.1, 0.1), lx)

# soffit: the board under the top overhang, one fascia depth down
sof = faces.select { |f| on_line.call(f, YT - 12.5, YT - 0.7, ZE - FD - 0.6, ZE - FD + 1.0) }
ok('the top edge has a soffit board under its overhang', sof.length >= 4,
   sof.length)

# BOARDS MEET, THEY NEVER RUN INSIDE EACH OTHER (the user's law,
# 2026-08-26): the rake board used to run through the corner block the
# fascia now owns - two solids in one space, seams on the face. Its top
# end is cut back one fascia-thickness, to end flush on the fascia's
# inner face at y = YT - 0.75.
# the rake board's end cap is a face with one y, spanning the board's
# own 3/4" of x, deeper than any fascia edge (z well below ZE).
# THE BOARD MOVED IN (2026-09-09): it used to sit at x 12..12.75, OUTSIDE
# the poly line, and stuck out 3/4" past the perpendicular eave's fascia.
# It now fills 11.25..12 - flush with it - so the cap does too.
cap_at = lambda do |ycap|
  faces.any? do |f|
    ys = f.pts.map(&:y)
    xs = f.pts.map(&:x)
    zs = f.pts.map(&:z)
    (ys.max - ys.min) < 0.05 && (ys.max - ycap).abs < 0.05 &&
      xs.min > 11.15 && xs.min < 11.35 && xs.max < 12.05 && zs.min < ZE - 0.5
  end
end
ok('the rake board ends flush on the fascia inner face',
   cap_at.call(YT - 0.75))
ok('...and no longer runs through to the poly corner', !cap_at.call(YT))

# THE DECK ENDS AT THE END (2026-08-26, the user's corner mock-up): a
# strip along each rake, top flush with the deck TOP (above ZE, the
# underside), reaching out over the rake trim. Before it, nothing on the
# rake stood above the underside line - the bare white ledge.
dstrip = faces.select do |f|
  xs = f.pts.map(&:x)
  zs = f.pts.map(&:z)
  xs.min > 11.95 && xs.max < 12.95 && zs.max > ZE + 0.1 && zs.max < ZE + 1.5
end
ok('the deck runs out over the rake trim, flush with its own top',
   dstrip.length >= 1, dstrip.length)

# the LOW eave's own bands did not move: fascia still at band_top = 98
lof = faces.select { |f| on_line.call(f, YLOW - 0.8, YLOW, 98.0 - FD, 98.0) }
ok('the low eave keeps its own fascia where it was', lof.length >= 4,
   lof.length)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

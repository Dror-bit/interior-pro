# encoding: utf-8
# rt12 — molding on levels: miter/tee/butt resolvers pair runs only WITHIN
# one level (walls of different floors share the same x/y footprint), and
# an upper-level wall ignores the level-1 room polygons in sides_for.
require './sketchup_stub'

module Geom
  class Vector3d
    def dot(o); self % o; end unless method_defined?(:dot)
  end
end

require './molding_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
MM = InteriorPro::MoldingManager

def mk_wall(cat, level)
  w = Sketchup::Group.new
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'wall_category', cat)
  w.set_attribute('InteriorPro', 'level', level) unless level.nil?
  w
end

# Two exterior runs meeting at a corner (100,0): r runs +X, o runs +Y.
def corner_plan(lvl_r, lvl_o)
  r = { wall: mk_wall('exterior', lvl_r), side: :pos,
        geo: { p0: Geom::Point3d.new(0, 0, 0), u: Geom::Vector3d.new(1, 0, 0),
               nd: Geom::Vector3d.new(0, 1, 0), len: 100.0 },
        shifts: { start: 0, end: 0 }, tee_gaps: [], build: true }
  o = { wall: mk_wall('exterior', lvl_o), side: :pos,
        geo: { p0: Geom::Point3d.new(100, 0, 0), u: Geom::Vector3d.new(0, 1, 0),
               nd: Geom::Vector3d.new(-1, 0, 0), len: 80.0 },
        shifts: { start: 0, end: 0 }, tee_gaps: [], build: true }
  [r, o]
end

# ---- miters stay inside one level ---------------------------------------
r, o = corner_plan(1, 1)
MM.resolve_miters!([r, o])
ok('same level: corner gets a miter shear', r[:shifts][:end] != 0 && o[:shifts][:start] != 0,
   [r[:shifts], o[:shifts]])

r, o = corner_plan(1, 2)
MM.resolve_miters!([r, o])
ok('levels 1+2: NO cross-level miter', r[:shifts][:end] == 0 && o[:shifts][:start] == 0,
   [r[:shifts], o[:shifts]])

r, o = corner_plan(2, 2)
MM.resolve_miters!([r, o])
ok('level 2 alone still miters its corners', r[:shifts][:end] != 0 && o[:shifts][:start] != 0,
   [r[:shifts], o[:shifts]])

r, o = corner_plan(nil, 1)
MM.resolve_miters!([r, o])
ok('legacy wall (no level attr) counts as level 1', r[:shifts][:end] != 0,
   r[:shifts])

# ---- tees stay inside one level ------------------------------------------
# stub run ends mid-span of the crossing run (both interior).
def tee_plan(lvl_stub, lvl_run)
  stub = { wall: mk_wall('interior', lvl_stub), side: :pos,
           geo: { p0: Geom::Point3d.new(50, -40, 0), u: Geom::Vector3d.new(0, 1, 0),
                  nd: Geom::Vector3d.new(1, 0, 0), len: 40.0 },
           shifts: { start: 0, end: 0 }, tee_gaps: [], build: true }
  run = { wall: mk_wall('interior', lvl_run), side: :pos,
          geo: { p0: Geom::Point3d.new(0, 0, 0), u: Geom::Vector3d.new(1, 0, 0),
                 nd: Geom::Vector3d.new(0, -1, 0), len: 100.0 },
          shifts: { start: 0, end: 0 }, tee_gaps: [], build: true }
  [stub, run]
end

stub, run = tee_plan(1, 1)
MM.resolve_tees!([stub, run])
ok('same level: T-stub gets its shear', stub[:shifts][:end] != 0, stub[:shifts])

stub, run = tee_plan(2, 1)
MM.resolve_tees!([stub, run])
ok('levels 2 vs 1: NO cross-level T', stub[:shifts][:end] == 0, stub[:shifts])

# ---- flush butts stay inside one level -----------------------------------
def butt_plan(lvl_i, lvl_o)
  ri = { wall: mk_wall('interior', lvl_i), side: :pos,
         geo: { p0: Geom::Point3d.new(100, 0, 0), u: Geom::Vector3d.new(1, 0, 0),
                nd: Geom::Vector3d.new(0, 1, 0), len: 60.0 },
         shifts: { start: 5, end: 0 }, tee_gaps: [], build: true }
  ro = { wall: mk_wall('exterior', lvl_o), side: :pos,
         geo: { p0: Geom::Point3d.new(0, 0, 0), u: Geom::Vector3d.new(1, 0, 0),
                nd: Geom::Vector3d.new(0, 1, 0), len: 100.0 },
         shifts: { start: 0, end: 5 }, tee_gaps: [], build: true }
  [ri, ro]
end

ri, ro = butt_plan(1, 1)
MM.resolve_flush_butts!([ri, ro])
ok('same level: flush butt squares the seam', ri[:shifts][:start] == 0 && ro[:shifts][:end] == 0,
   [ri[:shifts], ro[:shifts]])

ri, ro = butt_plan(2, 1)
MM.resolve_flush_butts!([ri, ro])
ok('levels 2 vs 1: NO cross-level flush butt', ri[:shifts][:start] == 5 && ro[:shifts][:end] == 5,
   [ri[:shifts], ro[:shifts]])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

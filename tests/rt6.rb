# encoding: utf-8
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

# plan_generator needs a couple more shims than the editor does
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map do |o|
        { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f }
      end
    end
  end
end
module Sketchup
  class Entities
    def add_edges(pts); pts.each_cons(2) { |a, b| @list << Edge.new(a, b) }; @list.last(pts.length - 1); end
  end
end

require './plan_generator'
require 'json'
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def near(a, b, t = 0.6); (a - b).abs <= t; end
PG = InteriorPro::PlanGenerator

def wall(sx, sy, ex, ey, th: 6, cat: 'exterior', ops: [], id: nil)
  m = Sketchup.active_model
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', id || "w#{m.entities.length}")
  g.set_attribute('InteriorPro', 'start_x', sx); g.set_attribute('InteriorPro', 'start_y', sy)
  g.set_attribute('InteriorPro', 'end_x', ex);   g.set_attribute('InteriorPro', 'end_y', ey)
  g.set_attribute('InteriorPro', 'thickness', th)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-left')
  g.set_attribute('InteriorPro', 'wall_category', cat)
  g.set_attribute('InteriorPro', 'door_openings', ops)
  g
end

# a 240 x 144 box of 6 in walls
def box_model
  Sketchup.reset_model!
  wall(0, 0, 240, 0)
  wall(240, 0, 240, 144)
  wall(240, 144, 0, 144)
  wall(0, 144, 0, 0)
end

box_model
m = Sketchup.active_model
info = PG.send(:chain_wall_info, m)
ok('every wall became a world quad', info.length == 4, info.length)
box = PG.send(:chain_box, info)
ok('the box spans the outer faces', near(box[:x0], 0) && near(box[:x1], 240) &&
                                    near(box[:y0], 0) && near(box[:y1], 144), box)

# a plain box has nothing between its ends on the X chain
segx = PG.send(:chain_segment_stops, info, :x, box[:x0], box[:x1])
ok('a plain box needs no segment stops', segx.length == 2, segx)

# add an interior wall across the middle -> it becomes a stop
wall(120, 0, 120, 144, th: 4, cat: 'interior')
info = PG.send(:chain_wall_info, m)
box = PG.send(:chain_box, info)
segx = PG.send(:chain_segment_stops, info, :x, box[:x0], box[:x1])
ok('a cross wall adds its two faces as stops', segx.length == 4, segx)
# bottom-left anchor puts the 4 in wall body at x 116..120
ok('and they sit where the wall is', near(segx[1], 116) && near(segx[2], 120), segx)
ok('the outer ends are still there', near(segx.first, 0) && near(segx.last, 240), segx)

# a wall running ALONG the chain must not add stops
segy = PG.send(:chain_segment_stops, info, :y, box[:y0], box[:y1])
ok('the same wall is ignored on the other axis', segy.length == 2, segy)

# openings: two windows on the bottom wall
Sketchup.reset_model!
wall(0, 0, 240, 0, ops: [[60, 36, 48], [180, 36, 48]])
wall(240, 0, 240, 144)
wall(240, 144, 0, 144)
wall(0, 144, 0, 0)
m = Sketchup.active_model
info = PG.send(:chain_wall_info, m)
box = PG.send(:chain_box, info)
ops_low = PG.send(:chain_opening_stops, info, :x, :low, box)
# two 36 in windows at t=60 and t=180 -> edges at 42/78 and 162/198, plus the ends
ok('the band uses opening EDGES, not centres', ops_low.length == 6, ops_low)
ok('window 1 reads 42 to 78', near(ops_low[1], 42) && near(ops_low[2], 78), ops_low)
ok('window 2 reads 162 to 198', near(ops_low[3], 162) && near(ops_low[4], 198), ops_low)
ok('so the band gives width and gap', near(ops_low[2] - ops_low[1], 36) &&
                                      near(ops_low[3] - ops_low[2], 84), 
   [ops_low[2] - ops_low[1], ops_low[3] - ops_low[2]])
ops_high = PG.send(:chain_opening_stops, info, :x, :high, box)
ok('the top chain does not borrow them', ops_high.length == 2, ops_high)

# which bands each side gets
rows_low = PG.send(:chain_rows, info, box, :x, :low)
ok('the side with windows gets an opening band', rows_low.length >= 2, rows_low.map { |r| r[:stops].length })
ok('the last band is always the overall one', rows_low.last[:stops] == [box[:x0], box[:x1]], rows_low.last)
rows_high = PG.send(:chain_rows, info, box, :x, :high)
ok('a blank side gets only the overall band', rows_high.length == 1, rows_high.map { |r| r[:stops].length })

# the whole thing runs and draws without raising
ents = Sketchup.active_model.entities
before = ents.length
PG.send(:draw_dim_chains, ents, m)
ok('chains drew some geometry', ents.length > before, [before, ents.length])

# a tiny model is skipped
Sketchup.reset_model!
wall(0, 0, 12, 0)
m2 = Sketchup.active_model
n2 = m2.entities.length
PG.send(:draw_dim_chains, m2.entities, m2)
ok('a model too small for chains is skipped', m2.entities.length == n2, m2.entities.length)

# no walls at all is safe
Sketchup.reset_model!
m3 = Sketchup.active_model
PG.send(:draw_dim_chains, m3.entities, m3)
ok('an empty model is safe', true)

# ---- the per-wall exterior rows are really gone ------------------------
Sketchup.reset_model!
wall(0, 0, 240, 0, ops: [[60, 36, 48]])
wall(240, 0, 240, 144); wall(240, 144, 0, 144); wall(0, 144, 0, 0)
m4 = Sketchup.active_model
d4 = PG.send(:wall_attrs, m4.entities.grep(Sketchup::Group).first)
rows = []
PG.define_singleton_method(:dim_row) { |_e, _d, segs, off, dist, _h| rows << [off, dist, segs.length] }
PG.send(:draw_wall_dim, m4.entities, d4)
ok('a wall no longer draws exterior rows', rows.all? { |r| r[0] == d4[:off_pos] }, rows)
ok('but it still draws the inside clear span', rows.length == 1, rows)

# ---- an L-shaped building still gets sane chains -----------------------
Sketchup.reset_model!
wall(0, 0, 240, 0); wall(240, 0, 240, 96); wall(240, 96, 120, 96)
wall(120, 96, 120, 144); wall(120, 144, 0, 144); wall(0, 144, 0, 0)
m5 = Sketchup.active_model
i5 = PG.send(:chain_wall_info, m5)
b5 = PG.send(:chain_box, i5)
ok('L shape: box covers the whole footprint', near(b5[:x1], 240) && near(b5[:y1], 144), b5)
sx5 = PG.send(:chain_segment_stops, i5, :x, b5[:x0], b5[:x1])
ok('L shape: the step shows up as a stop', sx5.length >= 3, sx5)
n5 = m5.entities.length
PG.send(:draw_dim_chains, m5.entities, m5)
ok('L shape: chains drew without raising', m5.entities.length > n5)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

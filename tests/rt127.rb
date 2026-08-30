# encoding: utf-8
# rt127 - TWO SOFFIT BOARDS NEVER COVER THE SAME SPOT (2026-09-09).
#
# WHY
# The user photographed a triangle of lines under the eave at his south-
# west inner corner. debug_click_probe measured what he clicked on:
# TWO flat soffit faces, both at z=197, both InteriorPro_Roof_ffffff,
# covering the same 11.25 x 11.25 corner square - the west run mitred on
# the diagonal and the south run squared straight across on top of it.
# Boards inside each other (CLAUDE.md's law), and the lines he saw are
# where the two cross.
#
# THE CAUSE
# The west outline edge is marked as a gable, but over the wing it is a
# plain LEVEL eave - and its own board IS built there, mitred, by the
# gable_spans branch of build_band!. The square-end rule read the coarse
# per-EDGE gable_flags, so the south board squared across a corner whose
# neighbour was not a rake at all. rake_corners already answers per END
# (2026-09-08, rt126); the flat soffit reads it now too.
#
# WHAT IS PINNED
# Over the whole soffit plane of HIS house - his walls, his two gable
# marks, his settings - no point is covered by two boards, and the corner
# square is not left open either. Against the code before the fix the
# samples above the corner diagonal come back 2.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

# the same Face the roof suites use (rt93/rt96)
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

RM = InteriorPro::RoofManager

def wall(m, id, s, e, anchor)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => anchor, 'height' => 96.0, 'base_z' => 106.0,
    'level' => 2, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

Sketchup.reset_model!
m = Sketchup.active_model
# his six walls, attribute for attribute (house_dump_report 2026-09-08)
wall(m, 'north', [1144.5, 520.0], [878.0, 520.0], 'bottom-left')
wall(m, 'east',  [1144.5, 270.0], [1144.5, 520.0], 'bottom-left')
wall(m, 'south-main', [994.5, 270.0], [1144.5, 270.0], 'bottom-left')
wall(m, 'east-wing',  [994.5, 141.5], [994.5, 270.0], 'bottom-right')
wall(m, 'south-wing', [878.0, 141.5], [994.5, 141.5], 'bottom-left')
wall(m, 'west', [878.0, 520.0], [878.0, 141.5], 'bottom-left')

# his three gable marks, click for click
# his TWO gable marks, click for click (house_dump_report 2026-09-09 -
# the south wing is no longer marked, which is exactly why its eave
# carries a flat soffit board that can collide with the west one)
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', %w[west east])
m.set_attribute('InteriorPro', 'roof_gable_click_xy',
                [878.0, 299.82139255037674, 1144.5, 428.4524886768684])

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    FAILS << name
    puts "FAIL  #{name}   << #{extra.inspect}"
  end
end

roof = RM.build_roof!(style: 'hip', pitch: 5, overhang: 12.0, level: 2,
                      fascia: true, fascia_depth: 8.0, drip: true,
                      soffit: 'boxed', soffit_slope: false,
                      gable_walls: true, gutter: true, gutter_profile: 'box',
                      gutter_width: 4.0, ridge_cap: true,
                      roof_material: 'metaltile', thickness: 0.5)
abort 'build_roof! -> NIL' if roof.nil?

# every FLAT face (all its corners at one z) the roof group owns, at any
# depth - the soffit boards, the fascia bottoms, the drip bottoms
flats = []
walk = lambda do |ents, depth|
  ents.to_a.each do |e|
    if e.is_a?(Sketchup::Face) && e.pts && e.pts.length >= 3
      zs = e.pts.map(&:z)
      flats << e.pts if (zs.max - zs.min) < 0.005
    elsif e.is_a?(Sketchup::Group) && depth < 5
      walk.call(e.entities, depth + 1)
    end
  end
end
walk.call(roof.entities, 0)
ok('the roof has flat trim faces', flats.length > 4, flats.length)

# the soffit's underside is the lowest flat plane on the roof
zlo = flats.map { |pts| pts.first.z }.min
board = flats.select { |pts| (pts.first.z - zlo).abs < 0.01 }
ok('...and several boards share its lowest plane', board.length >= 4,
   [zlo, board.length])

def inside?(pts, x, y)
  hit = false
  n = pts.length
  n.times do |i|
    j = (i + 1) % n
    a = pts[i]
    b = pts[j]
    next if (a.y > y) == (b.y > y)
    xc = a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)
    hit = !hit if x < xc
  end
  hit
end

# HIS CORNER: the south-west inner corner of the wing. The west wall's
# outside face is x=878-12=866 after the overhang, the south wing's is
# y=141.5-12=129.5, the fascia is 3/4" thick, so the boarded square is
# x 866.75..878 by y 130.25..141.5. Sampled off its edges, so no point
# ever lands ON a boundary line.
X0 = 866.75
X1 = 878.0
Y0 = 130.25
Y1 = 141.5
doubled = []
holes = []
x = X0 + 0.5
while x < X1 - 0.4
  y = Y0 + 0.5
  while y < Y1 - 0.4
    c = board.count { |pts| inside?(pts, x, y) }
    doubled << [x.round(2), y.round(2), c] if c > 1
    holes << [x.round(2), y.round(2)] if c.zero?
    y += 0.75
  end
  x += 0.75
end
ok('no spot in his corner square carries TWO soffit boards',
   doubled.empty?, doubled.first(4))
ok('...and none carries none - the square is closed', holes.empty?,
   holes.first(4))

# ...and the same claim over the WHOLE soffit plane, so a fix that only
# moves the fault to another corner does not pass.
xs = board.flat_map { |pts| pts.map(&:x) }
ys = board.flat_map { |pts| pts.map(&:y) }
anywhere = []
x = xs.min + 0.4
while x < xs.max
  y = ys.min + 0.4
  while y < ys.max
    anywhere << [x.round(2), y.round(2)] if board.count { |pts| inside?(pts, x, y) } > 1
    y += 1.0
  end
  x += 1.0
end
ok('no two soffit boards overlap anywhere on the roof',
   anywhere.empty?, anywhere.first(4))

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

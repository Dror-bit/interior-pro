# encoding: utf-8
# MEASURE ONLY. Builds HIS house (house_dump_report, 2026-09-08) in the
# stub with whichever roof_manager file ARGV[0] names, and prints the top
# skin outline - so two versions of the code can be compared shape against
# shape without touching SketchUp.
#   ruby debug_roofdiff.rb <roof_manager file> <tag>
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
m.set_attribute('InteriorPro', 'roof_gable_wall_ids',
                %w[south-wing west east])
m.set_attribute('InteriorPro', 'roof_gable_click_xy',
                [978.3671059629412, 141.5, 878.0, 299.82139255037674,
                 1144.5, 428.4524886768684])

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
                      soffit: 'boxed', gable_walls: true, gutter: true,
                      roof_material: 'shingle', thickness: 0.5)
abort 'build_roof! -> NIL' if roof.nil?
rows = []
walk = lambda do |ents, label, depth|
  ents.to_a.each do |e|
    if e.is_a?(Sketchup::Face) && e.pts
      rows << [label, e.pts]
    elsif e.is_a?(Sketchup::Group)
      p = e.get_attribute('InteriorPro', 'part').to_s
      walk.call(e.entities, p.empty? ? label : p, depth + 1) if depth < 5
    end
  end
end
walk.call(roof.entities, 'roof', 0)
trim = rows.select { |lb, _p| lb == 'roof' }

# THE BREAK POINT MEETS ON ONE PLANE (2026-09-08, the user's two green
# circles). The west edge (x=866) carries a gable stretch AND the wing's
# level stretch on the same outline edge; every trim piece - rake board,
# rake soffit, fascia, drip, flat soffit - must END on the meet plane
# y=258.0: not 0.1" past it (the ragged cover-sampler end), and not on a
# skewed mitre reaching 258.3 / 262.3.
stray = []
trim.each do |_lb, pts|
  pts.each do |p|
    next unless p.z > 192.0 && p.z < 205.6
    next unless p.x < 879.0 && p.x > 865.0
    stray << [p.x, p.y, p.z] if p.y > 258.02 && p.y < 262.4
  end
end
ok('every west-edge trim piece ends ON the break plane y=258',
   stray.empty?, stray.first(4))

# THE GUTTER MOUTH IS CAPPED at the mid-edge break - a plate across the
# section at y=258, not an open tube showing its insides.
cap = rows.any? do |_lb, pts|
  pts.length >= 4 &&
    pts.all? { |p| (p.y - 258.0).abs < 0.01 } &&
    pts.all? { |p| p.x < 866.01 } &&
    pts.map(&:z).min > 199.0 && pts.map(&:z).max < 205.6
end
ok('the west gutter run ends in an end cap on the break plane', cap)

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

# encoding: utf-8
# rt125 - THE VALLEY EDGES ARE CLOSED (2026-09-08).
#
# The deck is two skins half an inch apart. Where a wing's roof dives
# onto its parent plane - the over-framed valley - both skins simply
# ENDED: four diagonal edges carrying one face each, measured in his
# model (long_edges_report). The deck stood hollow there, and the bare
# edge of the top skin was the black diagonal line in his photos:
# "זה הקצה של החומר שעל הגג... תראה שהוא חלול".
#
# Now the framed builder records each kept dive edge and the slab gets
# the same closing strip on it that the outline always had. A TUCKED
# wing records nothing - its mouth edge is inside the parent already.
#
# Against the old code: the four valley edges carry one face and this
# fails.
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
    def add_face(pts); f = Face.new; f.pts = pts; @list << f; f; end
  end
end
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

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
# his six walls, corner squared (house_dump_report 2026-09-08)
wall(m, 'north', [1144.5, 520.0], [878.0, 520.0], 'bottom-left')
wall(m, 'east',  [1144.5, 270.0], [1144.5, 520.0], 'bottom-left')
wall(m, 'south-main', [994.5, 270.0], [1144.5, 270.0], 'bottom-left')
wall(m, 'east-wing',  [994.5, 141.5], [994.5, 270.0], 'bottom-right')
wall(m, 'south-wing', [878.0, 141.5], [994.5, 141.5], 'bottom-left')
wall(m, 'west', [878.0, 520.0], [878.0, 141.5], 'bottom-left')
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', %w[south-wing west east])
m.set_attribute('InteriorPro', 'roof_gable_click_xy',
                [978.4, 141.5, 878.0, 299.8, 1144.5, 428.5])
roof = RM.build_roof!(style: 'hip', pitch: 5, overhang: 12.0, level: 2,
                      fascia: true, fascia_depth: 8.0, drip: true,
                      soffit: 'boxed', gable_walls: true,
                      roof_material: 'shingle', thickness: 0.5)
ok('his house builds framed', !roof.nil?)

# count faces on every edge of the DECK (the roof group's own faces,
# sub-groups excluded - trim lives in the same list here, fine)
faces = []
walk = lambda do |ents, depth|
  ents.to_a.each do |e|
    if e.is_a?(Sketchup::Face) && e.pts
      faces << e.pts
    elsif e.is_a?(Sketchup::Group) && depth < 4
      walk.call(e.entities, depth + 1)
    end
  end
end
walk.call(roof.entities, 0)
use = Hash.new(0)
key = lambda { |p| [p.x.round(2), p.y.round(2), p.z.round(2)] }
faces.each do |pts|
  pts.each_index do |i|
    a = key.call(pts[i]); b = key.call(pts[(i + 1) % pts.length])
    use[[a, b].sort] += 1
  end
end

# the four dive edges of the wing (underside + top skin, west + east).
# heights here are pre-heel stub numbers: eave underside 205, top 205.54,
# pen at 235.31 / 235.85.
edges = [
  [[866.0, 258.0, 205.0],  [938.75, 330.75, 235.31]],
  [[1011.5, 258.0, 205.0], [938.75, 330.75, 235.31]],
  [[866.0, 258.0, 205.54], [938.75, 330.75, 235.85]],
  [[1011.5, 258.0, 205.54], [938.75, 330.75, 235.85]]
]
edges.each do |a, b|
  n = use[[a, b].sort]
  ok("valley edge #{a[0]}/#{a[2]} -> pen carries TWO faces (closed), not one",
     n >= 2, n)
end

# and the closing strips are honest geometry: a strip's top edge equals
# the top skin edge, its bottom the underside edge - so the pen corner
# (938.75, 330.75) appears at BOTH skins' z on some face
zs = faces.flatten.select { |p| (p.x - 938.75).abs < 0.01 && (p.y - 330.75).abs < 0.01 }
          .map { |p| p.z.round(2) }.uniq.sort
ok('the pen corner exists at both skins', zs.include?(235.31) && zs.include?(235.85), zs)

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

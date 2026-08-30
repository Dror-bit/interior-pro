# which deck faces touch the west edge x=866 - full vertex lists
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
load './live_roof.rb'
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
abort 'NIL' if roof.nil?
roof.entities.to_a.each do |e|
  next unless e.is_a?(Sketchup::Face) && e.pts
  next unless e.pts.any? { |p| (p.x - 866.0).abs < 0.01 }
  puts e.pts.map { |p| format('(%.1f,%.1f,%.2f)', p.x, p.y, p.z) }.join(' ')
end

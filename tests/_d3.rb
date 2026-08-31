ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
module Sketchup
  class Face
    attr_accessor :pts, :pulled, :material, :back_material
    def normal
      a, b, c = @pts[0], @pts[1], @pts[2]
      u = Geom::Vector3d.new(b.x-a.x, b.y-a.y, b.z-a.z)
      v = Geom::Vector3d.new(c.x-a.x, c.y-a.y, c.z-a.z)
      (u*v).normalize
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
RM = InteriorPro::RoofManager
def wall(m, id, s, e, anchor)
  w = m.entities.add_group
  { 'type'=>'wall','id'=>id,'start_x'=>s[0],'start_y'=>s[1],'end_x'=>e[0],'end_y'=>e[1],
    'thickness'=>5.0,'anchor'=>anchor,'height'=>96.0,'base_z'=>0.0,'level'=>1,
    'wall_category'=>'exterior' }.each { |k,v| w.set_attribute('InteriorPro',k,v) }
  w
end
def build(dd)
  Sketchup.reset_model!
  m = Sketchup.active_model
  wall(m,'s',[0.0,0.0],[300.0,0.0],'bottom-left')
  wall(m,'e',[300.0,0.0],[300.0,200.0],'bottom-left')
  wall(m,'n',[300.0,200.0],[0.0,200.0],'bottom-left')
  wall(m,'w',[0.0,200.0],[0.0,0.0],'bottom-left')
  RM.build_roof!(style:'gable', pitch:5, overhang:12.0, level:1, fascia:true,
                 fascia_depth:8.0, drip:true, soffit:'boxed', soffit_slope:false,
                 dutch_depth:dd, gable_walls:true, roof_material:'metaltile', thickness:0.5)
end
[24.0].each do |dd|
  r = build(dd)
  next puts("dd=#{dd} NIL") if r.nil?
  fs = []
  wk = nil
  wk = lambda { |e,d| e.to_a.each { |x|
    fs << x if x.is_a?(Sketchup::Face) && x.pts
    wk.call(x.entities, d+1) if x.is_a?(Sketchup::Group) && d < 3 } }
  wk.call(r.entities, 0)
  puts "== dd=#{dd}"
  # every tile PART on the west end (x < 60), with its extent
  walk2 = nil
  parts = []
  walk2 = lambda { |e,d| e.to_a.each { |x|
    if x.is_a?(Sketchup::Group)
      pp = x.get_attribute('InteriorPro','part').to_s
      parts << [pp, x] unless pp.empty?
      walk2.call(x.entities, d+1) if d < 3
    end } }
  walk2.call(r.entities, 0)
  parts.each do |pp, g2|
    pts2 = []
    wk2 = nil
    wk2 = lambda { |e,d| e.to_a.each { |x|
      pts2.concat(x.pts.to_a) if x.is_a?(Sketchup::Face) && x.pts
      if x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance)
        sub = x.is_a?(Sketchup::Group) ? x.entities : (x.respond_to?(:definition) ? x.definition.entities : nil)
        wk2.call(sub, d+1) if sub && d < 4
      end } }
    wk2.call(g2.entities, 0)
    next if pts2.empty?
    xs = pts2.map(&:x)
    next if xs.min > 80.0
    zs = pts2.map(&:z)
    puts format('  %-12s x %7.2f..%7.2f  z %7.2f..%7.2f', pp, xs.min, xs.max, zs.min, zs.max)
  end
end

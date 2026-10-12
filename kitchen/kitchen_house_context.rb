# Read-only reference adapter. Never calls Interior Pro's builders or mutates
# its entities. Bounds are display references, not editable house source data.
module KitchenLab
  def self.house_context
    guard!
    level=Spatial.pose(settings)['level']
    entities=@model.entities.to_a.select { |e| e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance) }
    walls=entities.select { |e| e.get_attribute('InteriorPro','type')=='wall' }.to_h { |e| [e.get_attribute('InteriorPro','id'),e] }
    items=entities.filter_map do |e|
      type=e.get_attribute('InteriorPro','type')
      next unless %w[wall door window fixture].include?(type)
      host=walls[e.get_attribute('InteriorPro','host_wall_id')]
      lvl=e.get_attribute('InteriorPro','level',host ? host.get_attribute('InteriorPro','level',1) : 1).to_i
      next unless lvl==level
      points=nil;measurement_safe=false
      if type=='wall'
        corners=e.get_attribute('InteriorPro','corners_xy')
        sag=e.get_attribute('InteriorPro','sag',0).to_f
        if corners.is_a?(Array) && corners.length==8 && sag.abs<0.0625
          points=corners.each_slice(2).map { |x,y| p=Geom::Point3d.new(x,y,0).transform(e.transformation);[p.x.to_f,p.y.to_f] }
          measurement_safe=true
        end
      end
      unless points
        b=e.bounds
        next if b.empty?
        points=[[b.min.x.to_f,b.min.y.to_f],[b.max.x.to_f,b.min.y.to_f],[b.max.x.to_f,b.max.y.to_f],[b.min.x.to_f,b.max.y.to_f]]
      end
      {'id'=>e.get_attribute('InteriorPro','id').to_s,'type'=>type,'points'=>points,'measurement_safe'=>measurement_safe}
    end
    {'level'=>level,'items'=>items,'reference_only'=>true}
  end
end

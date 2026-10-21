# Approved window appearance. Inches; operates only on window body entities.
module InteriorPro
  module WindowAppearance
    ENABLED = true unless const_defined?(:ENABLED, false)
    def self.apply!(group, type, unit, normal, clicked_side)
      return true unless ENABLED
      load File.join(__dir__, 'door_leaf_styles.rb') unless defined?(InteriorPro::DoorLeafStyles)
      load File.join(__dir__, 'door_exterior_details.rb') unless defined?(InteriorPro::DoorExteriorDetails)
      axes = Geom::Transformation.axes(ORIGIN, unit, normal, Z_AXIS)
      mirror = clicked_side.to_f < 0 ? Geom::Transformation.scaling(1,-1,1) : IDENTITY
      canonical = mirror * axes.inverse
      entities = group.entities
      entities.transform_entities(canonical, entities.to_a)
      begin
        # Bake transformed nested bodies before measuring local profile bounds.
        entities.grep(Sketchup::Group).each { |g| InteriorPro::DoorExteriorDetails.normalize_leaf(g) }
        Builder.new.upgrade(group, type)
      ensure
        entities.transform_entities(canonical.inverse, entities.to_a)
      end
      true
    end
    class Builder
      def initialize
        @frame=material('InteriorPro_Window_Charcoal',[47,49,51],1.0)
        @white=@frame
        @steel=material('InteriorPro_Window_Stainless',[177,181,184],1.0)
        @seal=material('InteriorPro_Window_Gasket',[58,61,63],1.0)
        @metal=material('InteriorPro_Window_Hardware',[105,109,112],1.0)
        @glass=material('InteriorPro_Window_ClearGlass',[190,207,215],0.24)
      end
      def material(name,color,alpha)
        model=Sketchup.active_model
        mat=model.materials[name]
        return mat if mat
        mat=model.materials.add(name);mat.color=color;mat.alpha=alpha;mat
      end
  def offset_polygon(points,normal,distance)
    center=Geom::Point3d.new(points.map(&:x).sum/points.length,points.map(&:y).sum/points.length,points.map(&:z).sum/points.length)
    lines=points.each_with_index.map do |a,i|
      edge=points[(i+1)%points.length]-a
      inward=normal.cross(edge).normalize
      inward.reverse! if (center-a).dot(inward)<0
      [a.offset(inward,distance),edge]
    end
    lines.each_index.map do |i|
      Geom.intersect_line_line(lines[(i-1)%lines.length],lines[i]) || points[i]
    end
  end
  def profile_ring(ents,name,points,normal,profile,mat)
    g=ents.add_group;g.name=name;g.material=mat
    rings=profile.map{|distance,depth|offset_polygon(points,normal,distance).map{|p|p.offset(normal,depth)}}
    # Work enlarged, as for the existing approved small door hardware.
    rings.map!{|ring|ring.map{|p|Geom::Point3d.new(p.x*100,p.y*100,p.z*100)}}
    rings.each_with_index do |ring,j|
      other=rings[(j+1)%rings.length]
      ring.each_index do |i|
        k=(i+1)%ring.length
        f=g.entities.add_face([ring[i],ring[k],other[k],other[i]])
        f.material=mat if f
      end
    end
    g.entities.transform_entities(Geom::Transformation.scaling(0.01),g.entities.to_a)
    InteriorPro::DoorLeafStyles.soften_rounds!(g.entities,25.degrees)
    g
  end
  def glazing_detail(ents,points,normal)
    profile_ring(ents,'Glazing bead - bevelled white profile',points,normal,
      [[-0.16,-0.015],[-0.16,0.035],[-0.11,0.10],[-0.025,0.10],[0.02,0.04],[0.02,-0.015]],@white)
    profile_ring(ents,'Thin glazing gasket',points,normal,
      [[0.02,-0.005],[0.02,0.045],[0.075,0.045],[0.075,-0.005]],@seal)
  end
  def box(ents,name,x0,x1,y0,y1,z0,z1,mat=nil)
    InteriorPro::DoorExteriorDetails.round_box(ents,name,x0,x1,y0,y1,z0,z1,mat || @metal)
  end
 def latch(e,b)
  g=e.add_group;g.name='Compact stainless latch and strike'
  x=b.center.x.to_f;y=b.min.y.to_f;z=b.max.z.to_f-0.33
  box(g.entities,'Thin mounting plate',x-0.70,x+0.70,y-0.065,y+0.015,z-0.18,z+0.18,@steel)
  box(g.entities,'Latch body',x-0.50,x+0.32,y-0.19,y-0.05,z-0.125,z+0.125,@steel)
  box(g.entities,'Slim thumb lever',x-0.12,x+0.72,y-0.28,y-0.16,z-0.075,z+0.075,@steel)
  box(g.entities,'Thumb grip',x+0.58,x+0.78,y-0.35,y-0.17,z-0.12,z+0.12,@steel)
  box(g.entities,'Separate strike',x-0.45,x+0.45,y-0.10,y+0.015,z+0.21,z+0.30,@steel)
  g
 end
 def casement(e,b,right=false)
  g=e.add_group;g.name='Slim stainless cam handle'
  x=right ? b.min.x.to_f+0.38 : b.max.x.to_f-0.38
  y=b.min.y.to_f;z=b.center.z.to_f
  box(g.entities,'Cam mounting plate',x-0.17,x+0.17,y-0.07,y+0.01,z-0.70,z+0.70,@steel)
  box(g.entities,'Cam handle neck',x-0.11,x+0.11,y-0.39,y-0.06,z-0.08,z+0.13,@steel)
  box(g.entities,'Cam handle grip',x-0.10,x+0.10,y-0.43,y-0.29,z-1.30,z+0.13,@steel)
  g
 end
 def paint(e)
  e.grep(Sketchup::Group).each do |g|
   if ['Jamb','Sash','Frame','Grid'].include?(g.name)||g.name.start_with?('Glazing bead')
    g.material=@frame
    recolor(g.entities)
   elsif g.name=='GardenWindow'
    paint(g.entities)
    g.entities.grep(Sketchup::Face).each{|f|f.material=@frame if f.material && f.material.name=='InteriorPro_Window_Frame'}
   end
  end
 end
 def recolor(e)
  e.each do |p|
   if p.is_a?(Sketchup::Face)
    p.material=@frame;p.back_material=@frame
   elsif p.is_a?(Sketchup::Group)
    p.material=@frame;recolor(p.entities)
   end
  end
 end
  def upgrade(g,type)
    ents=g.entities
    sashes=ents.grep(Sketchup::Group).select{|p|p.name=='Sash'}
    rounded=0
    (sashes+ents.grep(Sketchup::Group).select{|p|p.name=='Jamb'}).each do |part|
      if part.name=='Sash'
        b=part.bounds
        part.transform!(Geom::Transformation.scaling(b.center,(b.width.to_f-0.12)/b.width.to_f,1,(b.depth.to_f-0.12)/b.depth.to_f))
        InteriorPro::DoorExteriorDetails.normalize_leaf(part)
      end
      rounded+=1 if InteriorPro::DoorExteriorDetails.round_leaf(part)
    end
    glass=ents.grep(Sketchup::Group).select{|p|p.name=='Glass'}
    glass.each do |pane|
      faces=pane.entities.grep(Sketchup::Face)
      candidates=faces.select{|f|f.normal.y.abs>0.99}
      face=candidates.min_by{|f|[f.bounds.center.y.to_f,-f.area.to_f]}
      next unless face
      points=face.outer_loop.vertices.map{|v|v.position.transform(pane.transformation)}
      glazing_detail(ents,points,Geom::Vector3d.new(0,-1,0))
      pane.material=@glass
      faces.each{|f|f.material=@glass;f.back_material=@glass}
    end
    garden=ents.grep(Sketchup::Group).find{|p|p.name=='GardenWindow'}
    if garden
      InteriorPro::DoorExteriorDetails.normalize_leaf(garden)
      old=Sketchup.active_model.materials['InteriorPro_Glass']
      garden.entities.grep(Sketchup::Face).select{|f|f.material==old||f.back_material==old}.each do |face|
        normal=face.normal
        normal.reverse! if (face.bounds.center-garden.bounds.center).dot(normal)<0
        glazing_detail(garden.entities,face.outer_loop.vertices.map(&:position),normal)
        face.material=@glass;face.back_material=@glass
      end
    end
    # The lower hung sash sits on the room-side track; keep its glazing together.
    if type=='Single Hung'
      ents.grep(Sketchup::Group).each do |part|
        next unless ['Sash','Glass','Grid','Glazing bead - bevelled white profile','Thin glazing gasket'].include?(part.name)
        z=part.bounds.center.z.to_f
        next if z.abs<0.01
        part.transform!(Geom::Transformation.translation([0,z<0 ? -1.25 : 1.25,0]))
      end
    end
    sashes=sashes.sort_by{|part|part.bounds.center.x}
    case type
    when 'Single Hung'
      latch(ents,sashes.min_by{|part|part.bounds.center.z}.bounds) unless sashes.empty?
    when 'XOX Single Hung'
      sashes.select{|part|part.bounds.center.z<0}.each{|part|latch(ents,part.bounds)}
    when 'Casement','Casement XX'
      sashes.each_with_index{|part,i|casement(ents,part.bounds,i==1)}
    when 'Slider XO','Slider XOX'
      chosen=type=='Slider XO' ? sashes.first(1) : [sashes.first,sashes.last].compact.uniq
      chosen.each_with_index{|part,i|casement(ents,part.bounds,i==1)}
    end
    paint(ents)
    {rounded_frames:rounded,glazed_panes:glass.length,garden:!garden.nil?,hardware:ents.grep(Sketchup::Group).count{|p|p.name.match?(/latch|cam handle/i)}}
  end
    end
  end
end

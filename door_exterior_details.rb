# Approved exterior-door details. Body geometry only; no wall calls or operations.
module InteriorPro
  module DoorExteriorDetails
    ENABLED = true unless const_defined?(:ENABLED, false)
    PATIO_HANDLES = true unless const_defined?(:PATIO_HANDLES, false)
    HANDLE_STYLES = ['Patio Lever', 'Sliding Flush Pull'].freeze unless const_defined?(:HANDLE_STYLES, false)

    def self.apply!(ents,type,unit,n,thickness,settings)
      return true unless ENABLED || PATIO_HANDLES
      axes=Geom::Transformation.axes(ORIGIN,unit,n,Z_AXIS)
      inverse=axes.inverse
      ents.transform_entities(inverse,ents.to_a) unless axes.identity?
      begin
        if ENABLED
          upgrade(ents,type,thickness,settings)
        elsif PATIO_HANDLES
          leaves=ents.grep(Sketchup::Group).select{|g|g.name.start_with?('Leaf') && !g.name.include?('Sidelite')}
          mat=InteriorPro::DoorLeafStyles.get_or_create_material(Sketchup.active_model,'InteriorPro_Exterior_Aluminium',[155,158,161],1.0)
          leaves.each{|g|normalize_leaf(g)}
          add_patio_handles(ents,type,leaves.map{|g|[g,g.bounds]},settings,mat)
        end
      ensure
        ents.transform_entities(axes,ents.to_a) unless axes.identity?
      end
      true
    end
    def self.normalize_leaf(g)
      tr=g.transformation
      unless tr.identity?
        g.entities.transform_entities(tr,g.entities.to_a)
        g.transformation=Geom::Transformation.new
      end
    end
  def self.face_copy(ents,face)
    f=ents.add_face(face.outer_loop.vertices.map{|v|v.position})
    return unless f
    f.reverse! if f.normal.dot(face.normal)<0
    f.material=face.material;f.back_material=face.back_material
    face.loops.reject(&:outer?).each{|l|h=ents.add_face(l.vertices.map{|v|v.position});h.erase! if h}
  end
  def self.round_leaf(g)
    fs=g.entities.grep(Sketchup::Face);return false if fs.empty?
    box=Geom::BoundingBox.new;fs.each{|f|f.vertices.each{|v|box.add(v.position)}}
    a=box.min;b=box.max;eps=0.0001
    caps=[a.y,b.y].map{|y|fs.select{|f|f.vertices.all?{|v|(v.position.y-y).abs<eps} && f.outer_loop.vertices.length==4}.max_by(&:area)}
    return false unless caps.all? && b.x-a.x>2 && b.z-a.z>2 && b.y-a.y>0.2
    shell=fs.select{|f|[[:x,a.x],[:x,b.x],[:z,a.z],[:z,b.z]].any?{|axis,val|f.vertices.all?{|v|(v.position.public_send(axis)-val).abs<eps}}}
    neo=g.entities.add_group;neo.name='Rounded outer edges - 1.5 mm'
    neo.material=g.material
    InteriorPro::DoorLeafStyles.build_rounded_slab!(neo.entities,a.x,b.x,a.z,b.z,a.y,b.y,X_AXIS,Y_AXIS)
    caps.each do |cap|
      cap.loops.reject(&:outer?).each do |loop|
        cut=neo.entities.add_face(loop.vertices.map{|v|v.position})
        cut.erase! if cut
      end
    end
    (fs-shell-caps).each{|f|face_copy(neo.entities,f)}
    neo.entities.grep(Sketchup::Face).each{|f|f.material=g.material unless f.material}
    # Replacement is confined to this independent proposal copy.
    g.entities.erase_entities(fs+g.entities.grep(Sketchup::Edge))
    true
  end
  def self.unique_tree(g)
    g.make_unique
    g.definition.entities.grep(Sketchup::Group).each{|c|unique_tree(c)}
  end
  def self.round_box(ents,name,x0,x1,y0,y1,z0,z1,mat)
    g=ents.add_group;g.name=name;g.material=mat
    r=[(y1-y0),(z1-z0)].min/5.0
    pts=[[y0+r,z0+r,Math::PI],[y1-r,z0+r,1.5*Math::PI],[y1-r,z1-r,0],[y0+r,z1-r,0.5*Math::PI]].flat_map do |y,z,a|
      5.times.map{|i|q=a+i*Math::PI/8;[x0*100,(y+r*Math.cos(q))*100,(z+r*Math.sin(q))*100]}
    end
    f=g.entities.add_face(pts);f.reverse! if f.normal.x<0;f.pushpull((x1-x0)*100)
    g.entities.transform_entities(Geom::Transformation.scaling(0.01),g.entities.to_a)
    InteriorPro::DoorLeafStyles.soften_rounds!(g.entities,25.degrees)
    g
  end
  def self.upgrade(ents,type,thickness,settings)
    aluminum=Sketchup.active_model.materials['InteriorPro_Exterior_Aluminium']||Sketchup.active_model.materials.add('InteriorPro_Exterior_Aluminium')
    aluminum.color=[155,158,161]
    seal=Sketchup.active_model.materials['InteriorPro_Exterior_Seal']||Sketchup.active_model.materials.add('InteriorPro_Exterior_Seal');seal.color=[55,57,59]
    leaves=ents.grep(Sketchup::Group).select{|g|g.name.start_with?('Leaf') && !g.name.include?('Glass') && !g.name.include?('Grid') && !g.name.include?('Sidelite') && !g.name.include?('Transom')}
    changes=[]
    leaves.each{|g|normalize_leaf(g)}
    original_bounds=leaves.map{|g|[g,g.bounds]}
    count=leaves.count{|g|round_leaf(g)}
    changes<<"Rounded outer edges on #{count} leaves" if count>0
    if %w[Arched].include?(type) || type=='Front Door' || type=='French Hinged' || type=='4-Panel Center Hinged'
      ents.grep(Sketchup::Group).select{|g|g.name=='Hinges'}.each(&:erase!) if type=='Arched'
      candidates=original_bounds.reject{|g,b|g.name=='Leaf_Front_ArchFill'}
      if type=='Front Door' && settings[:front_config].to_s=='double' && candidates.length==1 && candidates.first[0].name=='Leaf_Front_ArchRing'
        leaf,b=candidates.first;mid=b.center.x
        left=Geom::BoundingBox.new;left.add(b.min);left.add([mid,b.max.y,b.max.z])
        right=Geom::BoundingBox.new;right.add([mid,b.min.y,b.min.z]);right.add(b.max)
        candidates=[[leaf,left],[leaf,right]]
      end
      candidates=candidates.sort_by{|g,b|b.center.x}[1..2] if type=='4-Panel Center Hinged'
      candidates.each_with_index do |(leaf,b),i|
        side=candidates.length==1 ? (settings[:swing_direction].to_s=='right' ? 1 : -1) : (i==0 ? -1 : 1)
        u=side<0 ? b.min.x : b.max.x
        top=type=='Arched' ? b.max.z-b.width/2.0 : b.max.z
        InteriorPro::DoorLeafStyles.build_hinges!(ents,u,side,b.min.z,top,b.min.y,b.max.y,-1,X_AXIS,Y_AXIS,seal)
      end
      changes<<'Three detailed hinges per operating leaf'
    elsif type.match?(/Folding/)
      sorted=original_bounds.sort_by{|g,b|b.center.x}
      sorted.each_cons(2).with_index do |((l,lb),(r,rb)),i|
        u=(lb.max.x+rb.min.x)/2
        z0=lb.min.z;z1=lb.max.z;y=[lb.min.y,rb.min.y].min-0.24
        [z0+9,(z0+z1)/2,z1-9].each do |z|
          InteriorPro::DoorLeafStyles.hinge_cylinder!(ents,'Folding joint barrel',[u,y,z-1.5],Z_AXIS,0.18,3)
          round_box(ents,'Folding hinge leaf',u-1.1,u-0.10,y-0.04,y+0.07,z-1.4,z+1.4,aluminum)
          round_box(ents,'Folding hinge leaf',u+0.10,u+1.1,y-0.04,y+0.07,z-1.4,z+1.4,aluminum)
        end
      end
      changes<<'Visible folding-joint hinges'
    end
    threshold=ents.grep(Sketchup::Group).find{|g|g.name=='Threshold'}
    if threshold
      b=threshold.bounds;x0=b.min.x;x1=b.max.x;z=b.min.z
      # A sloping sill nose, raised inner stop and drip break, all real geometry.
      g=ents.add_group;g.name='Detailed aluminium sill';g.material=aluminum
      profile=[[-1,z],[-1,z+0.05],[-0.8,z+0.10],[0,z+0.125],[thickness-0.3,z+0.125],[thickness-0.3,z+0.32],[thickness+0.2,z+0.32],[thickness+0.2,z-0.03],[-0.75,z-0.03]]
      f=g.entities.add_face(profile.map{|y,w|[x0,y,w]});f.reverse! if f.normal.x<0;f.pushpull(x1-x0)
      threshold.erase!
      g.name='Threshold'
      if type.include?('Sliding') || type.include?('Folding')
        ys=original_bounds.map{|leaf,bb|bb.center.y}.uniq
        ys.each{|y|round_box(ents,'Rounded running rail',x0+0.1,x1-0.1,y-0.045,y+0.045,z+0.125,z+0.205,aluminum)}
        changes<<'Separate running rails and sloping sill'
      else
        changes<<'Sloping sill with drip break and inner stop'
      end
    elsif type=='Garage Door'
      b=Geom::BoundingBox.new;ents.each{|e|b.add(e.bounds) if e.respond_to?(:bounds)}
      round_box(ents,'Bottom weather seal',b.min.x,b.max.x,-2.1,0.1,b.min.z-0.30,b.min.z+0.03,seal)
      changes<<'Rounded rubber bottom seal'
    end
    add_patio_handles(ents,type,original_bounds,settings,aluminum) if PATIO_HANDLES
    changes
  end
    def self.add_patio_handles(ents,type,leaves,settings,mat)
      style=settings[:handle_style].to_s
      return if style.empty? || style=='none'
      hinged=['French Hinged','4-Panel Center Hinged'].include?(type)
      sliding=type=='Sliding' || type.match?(/\A\d+-Panel (Sliding|Folding)\z/)
      return unless hinged || sliding
      return unless HANDLE_STYLES.include?(style)
      selected=leaves.sort_by{|g,b|b.center.x}
      if type=='Sliding'
        index=settings[:slide_direction].to_s=='right' ? 0 : 1
        selected=[selected.fetch(index)]
      elsif type!='French Hinged'
        mid=selected.length/2
        selected=selected[[mid-1,0].max,2]
      end
      selected.each do |leaf,b|
        lock_right=type=='Sliding' ? b.center.x>0 : b.center.x<0
        setback=[settings[:stile_width].to_f/2.0,0.8].max
        setback=[setback,(b.width-1.0)/2.0].min
        u=lock_right ? b.max.x-setback : b.min.x+setback
        w=b.min.z+36.0
        [[b.min.y,-1],[b.max.y,1]].each do |v,sign|
          if sliding
            flush_pull(ents,leaf,u,v,w,sign,b.max.y-b.min.y,mat)
          else
            patio_lever(ents,u,v,w,sign,lock_right ? -1 : 1,mat)
          end
        end
      end
    end

    def self.patio_lever(ents,u,v,w,sign,xsign,mat)
      h=ents.add_group;h.name='Patio Lever'
      a,b=[v-sign*0.015,v+sign*0.09].minmax
      round_box(h.entities,'Escutcheon',u-0.46,u+0.46,a,b,w-3.25,w+3.25,mat)
      a,b=[v+sign*0.09,v+sign*1.20].minmax
      round_box(h.entities,'Spindle cover',u-0.23,u+0.23,a,b,w-0.23,w+0.23,mat)
      x0,x1=[u-0.20*xsign,u+2.70*xsign].minmax
      a,b=[v+sign*1.04,v+sign*1.42].minmax
      round_box(h.entities,'Lever',x0,x1,a,b,w-0.19,w+0.19,mat)
      h
    end

    def self.flush_pull(ents,leaf,u,v,w,sign,depth,mat)
      body=leaf.entities.grep(Sketchup::Group).find{|g|g.name.start_with?('Rounded outer edges')}
      body_ents=body ? body.entities : leaf.entities
      # A real recess; the exposed rim projects only 0.035 in into the track gap.
      recess=body_ents.add_face([[u-0.29,v,w-2.1],[u+0.29,v,w-2.1],[u+0.29,v,w+2.1],[u-0.29,v,w+2.1]])
      raise 'Sliding pull recess could not be built' unless recess
      recess.reverse! if recess.normal.y*sign<0
      recess.pushpull(-[0.15,depth*0.25].min)
      h=ents.add_group;h.name='Sliding Flush Pull'
      a,b=[v-sign*0.015,v+sign*0.035].minmax
      [[u-0.43,u-0.29,w-2.30,w+2.30],[u+0.29,u+0.43,w-2.30,w+2.30],
       [u-0.29,u+0.29,w-2.30,w-2.10],[u-0.29,u+0.29,w+2.10,w+2.30]].each do |x0,x1,z0,z1|
        round_box(h.entities,'Flush rim',x0,x1,a,b,z0,z1,mat)
      end
      h
    end
  end
end

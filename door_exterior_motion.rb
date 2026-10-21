# Body-only door articulation in the exterior builder's canonical X/Y axes.
# No transactions, wall access or accumulated transformations: every rebuild
# starts from the closed geometry, including handles and glass.
module InteriorPro
  module DoorExteriorMotion
    ENABLED = true unless const_defined?(:ENABLED, false)
    HINGED = ['Front Door', 'French Hinged', 'Arched', '4-Panel Center Hinged'].freeze unless const_defined?(:HINGED, false)

    def self.side(clicked_side, action)
      sign = clicked_side.to_i < 0 ? -1 : 1
      action.to_s == 'reverse' ? -sign : sign
    end

    def self.leaves(ents)
      ents.grep(Sketchup::Group).select do |g|
        g.name.start_with?('Leaf') && !g.name.match?(/Sidelite|Transom|_Lines|ArchFill|ArchGlass/)
      end.sort_by{|g|g.bounds.center.x}
    end

    # The legacy steel-arch double is drawn as one ring with a center bar.
    # Partition its existing faces, retaining that design, into two assemblies.
    def self.prepare!(ents,type,settings)
      return unless ENABLED && type=='Front Door' && settings[:front_config].to_s=='double'
      originals=ents.grep(Sketchup::Group).select{|g|g.name.match?(/\ALeaf_Front_Arch(?:Ring|Fill|Glass)\z/)}
      return if originals.empty?
      originals.each{|g|DoorExteriorDetails.normalize_leaf(g)}
      all=Geom::BoundingBox.new;originals.each{|g|all.add(g.bounds)}
      mid=all.center.x
      [-1,1].each do |side|
        leaf=ents.add_group;leaf.name=side<0 ? 'Leaf_Front_L' : 'Leaf_Front_R'
        originals.each do |source|
          part=leaf.entities.add_group;part.name=source.name;part.material=source.material
          source.entities.grep(Sketchup::Face).each do |face|
            mesh=face.mesh(0)
            mesh.polygons.each do |polygon|
              pts=polygon.map{|index|mesh.point_at(index.abs)}
              clipped=[]
              pts.each_with_index do |a,i|
                b=pts[(i+1)%pts.length]
                ia=(a.x-mid).to_f*side>=-1e-7;ib=(b.x-mid).to_f*side>=-1e-7
                clipped<<a if ia
                if ia!=ib
                  t=(mid-a.x)/(b.x-a.x)
                  clipped<<Geom::Point3d.new(mid,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
                end
              end
              # SketchUp Length comparisons apply a model tolerance. Compare
              # Floats here, or even identical points can survive a tiny '<'.
              clipped=clipped.each_with_object([]){|p,out|out<<p unless out.any?{|q|p.distance(q).to_f<1e-5}}
              next if clipped.length<3
              area=Geom::Vector3d.new(0,0,0)
              clipped.each_with_index do |p,k|
                q=clipped[(k+1)%clipped.length]
                area.x+=p.y*q.z-p.z*q.y;area.y+=p.z*q.x-p.x*q.z;area.z+=p.x*q.y-p.y*q.x
              end
              longest=clipped.each_with_index.map{|p,k|p.distance(clipped[(k+1)%clipped.length]).to_f}.max
              next if area.length.to_f/[longest,1e-8].max<1e-5
              # Clipping at the center can leave narrow triangles. Use the
              # same large-scale construction as the approved small hardware.
              begin
                f=part.entities.add_face(clipped.map{|p|Geom::Point3d.new(p.x*100,p.y*100,p.z*100)})
              rescue ArgumentError=>error
                raise ArgumentError,"Steel arch half: #{error.message}; points=#{clipped.map(&:to_a).inspect}; area=#{area.length}"
              end
              next unless f
              f.reverse! if f.normal.dot(face.normal)<0
              f.material=face.material;f.back_material=face.back_material
            end
          end
          part.entities.grep(Sketchup::Edge).select{|e|e.vertices.all?{|v|(v.position.x-mid*100).to_f.abs<1e-4}}.each{|e|e.find_faces if e.valid?}
          part.entities.grep(Sketchup::Edge).each do |e|
            fs=e.faces
            if fs.length==2 && fs[0].normal.dot(fs[1].normal)>0.999999
              e.soft=true;e.smooth=true;e.hidden=true
            end
          end
          part.entities.transform_entities(Geom::Transformation.scaling(0.01),part.entities.to_a)
        end
      end
      ents.erase_entities(originals)
    end

    def self.apply!(ents, type, settings)
      return unless ENABLED
      return garage!(ents) if type == 'Garage Door' && settings[:door_state].to_s == 'half_open'
      return if type == 'Garage Door'
      ls = leaves(ents)
      return if ls.empty?
      ls.each{|g|DoorExteriorDetails.normalize_leaf(g)}
      boxes = ls.map(&:bounds)
      assemblies = ls.map{|g|[g]}
      # Geometry split by the original front-door builder still belongs to the
      # same leaf (modern grooves, steel arch glass and corner fills).
      extras = ents.grep(Sketchup::Group).select{|g|g.name.start_with?('Leaf') && !ls.include?(g) && !g.name.match?(/Sidelite|Transom/)}
      handles = ents.grep(Sketchup::ComponentInstance) + ents.grep(Sketchup::Group).select{|g|['Patio Lever','Sliding Flush Pull'].include?(g.name)}
      (extras+handles).each do |p|
        i = boxes.each_index.min_by{|k|((boxes[k].center.x-p.bounds.center.x)**2 + (boxes[k].center.y-p.bounds.center.y)**2)}
        assemblies[i] << p
      end
      if HINGED.include?(type)
        indices = type == '4-Panel Center Hinged' ? [1,2] : ls.each_index.to_a
        hinged!(ents, indices.map{|i|assemblies[i]}, indices.map{|i|boxes[i]}, settings)
      elsif settings[:door_state].to_s == 'half_open'
        if type.include?('Sliding')
          sliding!(ents, type, assemblies, boxes, settings)
        elsif type.include?('Folding')
          folding!(ents, assemblies, boxes, settings)
        end
      end
    end

    def self.hinged!(ents, assemblies, boxes, settings)
      sign = settings[:opening_sign].to_f < 0 ? -1 : 1
      assemblies.each_with_index do |parts,i|
        b=boxes[i]
        side = boxes.length==1 ? (settings[:swing_direction].to_s=='right' ? 1 : -1) : (i.zero? ? -1 : 1)
        hinges=ents.grep(Sketchup::Group).select{|g|g.name.start_with?("Hinge_#{side<0 ? 'Left' : 'Right'}_")}
        # The approved hinge starts on the -Y face. Mirror its mounting across
        # this leaf's depth for the opposite opening face; frame stays fixed.
        if sign > 0
          mirror=Geom::Transformation.translation(Geom::Vector3d.new(0,b.min.y+b.max.y,0))*Geom::Transformation.scaling(ORIGIN,1,-1,1)
          ents.transform_entities(mirror,hinges) unless hinges.empty?
        end
        next unless settings[:door_state].to_s=='half_open'
        pivot=Geom::Point3d.new(side<0 ? b.min.x : b.max.x, (sign<0 ? b.min.y : b.max.y)+sign*0.18, 0)
        tr=Geom::Transformation.rotation(pivot,Z_AXIS,-side*sign*Math::PI/4)
        ents.transform_entities(tr,parts)
        hinges.each do |h|
          moving=h.entities.grep(Sketchup::Group).select{|p|p.name=='Leaf plate'||p.name=='Leaf screw'}
          h.entities.transform_entities(h.transformation.inverse*tr*h.transformation,moving) unless moving.empty?
        end
      end
    end

    def self.sliding!(ents,type,assemblies,boxes,settings)
      right=settings[:slide_direction].to_s=='right'
      if type=='Sliding'
        i=right ? 0 : 1
        amount=boxes[i].width*0.5*(right ? 1 : -1)
        ents.transform_entities(Geom::Transformation.translation(Geom::Vector3d.new(amount,0,0)),assemblies[i])
      else
        target=right ? boxes.last.center.x : boxes.first.center.x
        boxes.each_with_index do |b,i|
          dx=(target-b.center.x)*0.5
          ents.transform_entities(Geom::Transformation.translation(Geom::Vector3d.new(dx,0,0)),assemblies[i]) unless dx.abs<1e-8
        end
      end
    end

    def self.folding!(ents,assemblies,boxes,settings)
      right=settings[:slide_direction].to_s=='right'
      sign=settings[:opening_sign].to_f < 0 ? -1 : 1
      order=boxes.each_index.to_a
      order.reverse! if right
      direction=right ? -1 : 1
      first=boxes[order.first]
      hinge=Geom::Point3d.new(right ? first.max.x : first.min.x,sign>0 ? first.max.y+0.24 : first.min.y-0.24,0)
      transforms={}
      joints={}
      joint_faces={}
      order.each_with_index do |i,k|
        b=boxes[i]
        start_front = k.zero? ? sign<0 : joint_faces.fetch([i,order[k-1]].min)
        old=Geom::Point3d.new(right ? b.max.x : b.min.x,start_front ? b.min.y-0.24 : b.max.y+0.24,0)
        angle=direction*sign*(k.even? ? 1 : -1)*Math::PI/4
        rotation=Geom::Transformation.rotation(old,Z_AXIS,angle)
        tr=Geom::Transformation.translation(hinge-old)*rotation
        transforms[i]=tr
        ents.transform_entities(tr,assemblies[i])
        end_front = sign*(k.even? ? 1 : -1)>0
        far=Geom::Point3d.new(right ? b.min.x : b.max.x,end_front ? b.min.y-0.24 : b.max.y+0.24,0).transform(tr)
        next_i=order[k+1]
        if next_i
          nb=boxes[next_i]
          gap=right ? b.min.x-nb.max.x : nb.min.x-b.max.x
          hinge=far.offset(X_AXIS,direction*gap)
          joints[[i,next_i].min]=Geom::Point3d.new((far.x+hinge.x)/2,(far.y+hinge.y)/2,0)
          joint_faces[[i,next_i].min]=end_front
        end
      end
      ents.grep(Sketchup::Group).each do |p|
        if p.name=='Folding hinge leaf'
          i=boxes.each_index.min_by{|k|(p.bounds.center.x-boxes[k].center.x).abs}
          j=(0...boxes.length-1).min_by{|k|(p.bounds.center.x-(boxes[k].max.x+boxes[k+1].min.x)/2).abs}
          mirror=joint_faces[j] ? Geom::Transformation.new : Geom::Transformation.translation(Geom::Vector3d.new(0,boxes[i].min.y+boxes[i].max.y,0))*Geom::Transformation.scaling(ORIGIN,1,-1,1)
          ents.transform_entities(transforms[i]*mirror,[p])
        elsif p.name=='Folding joint barrel'
          i=(0...boxes.length-1).min_by{|k|(p.bounds.center.x-(boxes[k].max.x+boxes[k+1].min.x)/2).abs}
          old=Geom::Point3d.new((boxes[i].max.x+boxes[i+1].min.x)/2,boxes[i].min.y-0.24,0)
          ents.transform_entities(Geom::Transformation.translation(joints.fetch(i)-old),[p])
        end
      end
    end

    # Follow the existing overhead track: vertical, quarter circle, horizontal.
    # Each complete section (with its windows/relief) moves as a rigid unit.
    def self.garage!(ents)
      sections=ents.grep(Sketchup::Group).select{|g|g.name.match?(/\ASection_[1-4]\z/)}.sort_by{|g|g.name}
      return unless sections.length==4
      boxes=sections.map(&:bounds)
      bottom=boxes.first.min.z;top=boxes.last.max.z
      center_y=boxes.first.center.y
      tracks=ents.grep(Sketchup::Group).select{|g|g.name.start_with?('Track_')}
      return if tracks.empty?
      sign=tracks.first.bounds.center.y<center_y ? 1 : -1
      radius=12.0;horizontal=top+1.0;vertical=horizontal-radius-bottom
      lift=(top-bottom)*0.5
      parts=ents.grep(Sketchup::Group).select{|p|sections.include?(p)||p.name.match?(/\AS[0-3]_|\AFV_|\ABottom weather seal\z/)}
      parts.group_by{|p|boxes.each_index.min_by{|i|(boxes[i].center.z-p.bounds.center.z).abs}}.each do |i,group|
        old=Geom::Point3d.new(0,center_y,boxes[i].center.z)
        s=old.z-bottom+lift
        if s<=vertical
          target=Geom::Point3d.new(0,center_y,bottom+s);angle=0
        elsif s<=vertical+radius*Math::PI/2
          angle=(s-vertical)/radius
          target=Geom::Point3d.new(0,center_y-sign*radius*(1-Math.cos(angle)),horizontal-radius+radius*Math.sin(angle))
        else
          angle=Math::PI/2
          target=Geom::Point3d.new(0,center_y-sign*(radius+s-vertical-radius*Math::PI/2),horizontal)
        end
        tr=Geom::Transformation.translation(target-old)*Geom::Transformation.rotation(old,X_AXIS,sign*angle)
        ents.transform_entities(tr,group)
      end
    end
  end
end

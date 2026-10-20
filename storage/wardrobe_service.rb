require_relative '../laundry/service'
require_relative 'wardrobe_domain'
module InteriorPro
  module Storage
    # Reuses the tested transaction + native-sync lifecycle, with separate source,
    # validation, materials and renderer. No kitchen/vanity state is consulted.
    class WardrobeService < Laundry::Service
      def domain_name; 'wardrobe'; end
      def validator; WardrobeDomain.method(:validate); end
      def material_namespace; 'Wardrobe'; end
      def finish_palette;super.merge('rod'=>'#A8ADAE');end
      def build(c,doc,g=nil)
        g||=@model.entities.add_group;g.name="Storage / Wardrobe / #{c['width']} in"
        @store.stamp(g,doc,c['id'])
        e=g.entities;geom=Cabinetry::Geometry
        w=c['width'];h=c['height'];d=c['depth'];toe=4.0;t=0.75
        mat=material(c['finish'],{'ivory'=>'#E8E4D9','white'=>'#F5F5F0','gray'=>'#969C9B'}.fetch(c['finish']))
        [[0,'Left side'],[w-t,'Right side']].each { |x,name|geom.box(e,name,x,-d+t,toe,t,d-t,h-toe,mat) }
        geom.box(e,'Back',t,-0.5,toe,w-2*t,0.5,h-toe,mat)
        geom.box(e,'Bottom',t,-d+t,toe,w-2*t,d-1.25,t,mat)
        geom.box(e,'Top',t,-d+t,h-t,w-2*t,d-1.25,t,mat)
        geom.box(e,'Toe kick',0,-d+3,0,w,t,toe,mat)
        rows=Cabinetry.section_layout(c['sections'],start:toe+t)
        rows.each_with_index do |row,index|
          section=c['sections'][index];z=row['bottom'];sh=row['height']
          geom.box(e,"Section #{index+1} shelf",t,-d+1,row['top']-t,w-2*t,d-1.5,t,mat) if index<rows.length-1
          if section['kind']=='hanging'
            metal=material('rod','#A8ADAE');rod=e.add_group;rod.name="Section #{index+1} hanging rod"
            circle=rod.entities.add_circle([t,-d/2.0,row['top']-3],X_AXIS,0.625,24)
            face=rod.entities.add_face(circle);face.reverse! if face.normal.x<0;face.pushpull(w-2*t);rod.material=metal
          elsif section['kind']=='drawer'
            # Nominal row remains exact; reveal and box deductions only affect
            # the manufactured pieces, never the section/drawer dimension.
            fd=c['front']=='open' ? d : d-2.0
            geom.front(e,0.875,row['face_bottom'],w-1.75,row['face_height'],fd,c['style'],mat)
            bx=1.5;bw=w-3;by=-d+(c['front']=='open' ? 2 : 3);bdepth=-1-by;bh=sh-1.5
            geom.box(e,'Drawer bottom',bx,by,z+0.5,bw,bdepth,0.5,mat)
            [[bx,'Drawer left'],[bx+bw-0.5,'Drawer right']].each { |x,name|geom.box(e,name,x,by,z+1,0.5,bdepth,bh-0.5,mat) }
            geom.box(e,'Drawer back',bx+0.5,by+bdepth-0.5,z+1,bw-1,0.5,bh-0.5,mat)
            pull(e,c,w/2.0-2.5,-fd-0.75,z+sh/2.0,mat) unless c['handle']=='none'
          end
        end
        unless c['front']=='open'
          count=c['front']=='double' ? 2 : 1;fw=(w-0.25-(count-1)*0.125)/count
          count.times do |i|
            x=0.125+i*(fw+0.125)
            geom.front(e,x,toe+0.0625,fw,h-toe-0.125,d,c['style'],mat)
            unless c['handle']=='none'
              metal=material(c['handle'],c['handle']=='brass' ? '#B39456' : '#242729')
              hx=count==2 && i==1 ? x+1 : x+fw-1.32
              geom.box(e,'Door pull',hx,-d-1,toe+(h-toe)/2-2.5,0.32,0.32,5,metal)
              [0.35,4.35].each { |delta|geom.box(e,'Door pull mount',hx,-d-0.68,toe+(h-toe)/2-2.5+delta,0.3,0.68,0.3,metal) }
            end
          end
        end
        g.transformation=transform_for(c);g
      end
      def pull(entities,c,x,y,z,_mat)
        geom=Cabinetry::Geometry;metal=material(c['handle'],c['handle']=='brass' ? '#B39456' : '#242729')
        geom.box(entities,'Drawer pull',x,y,z-0.16,5,0.32,0.32,metal)
        [0.35,4.35].each { |delta|geom.box(entities,'Drawer pull mount',x+delta,y+0.32,z-0.16,0.3,0.43,0.3,metal) }
      end
    end
  end
end

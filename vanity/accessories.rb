module InteriorPro
  module Vanity
    remove_const(:USE_VANITY_ACCESSORIES) if const_defined?(:USE_VANITY_ACCESSORIES,false)
    USE_VANITY_ACCESSORIES=true
    module Accessories
      module_function
      def items(c); USE_VANITY_ACCESSORIES ? c.fetch('accessories',[]) : []; end
      def mirror_options(a)
        {'frame'=>false,'frame_width'=>0.125,'frame_color'=>'black','front_light'=>false,'back_light'=>false,'light_color'=>'warm'}.merge(a)
      end
      def mirror_colors
        {'black'=>'#25272A','white'=>'#F5F5F0','nickel'=>'#B8B6AF','brass'=>'#C4A568','warm'=>'#FFF0BC','neutral'=>'#FFFBEF','cool'=>'#E4F3FF'}
      end
      def center(c,a)
        ref=a.fetch('mirror_ref',-1)
        if a['kind']=='light' && ref!=-1
          mirror=c.fetch('accessories',[])[ref]
          raise ArgumentError,'בחר מראה קיימת למנורה' unless mirror && mirror['kind']=='mirror'
          x,z=center(c,mirror);gap=a.fetch('mirror_gap',3);side=a.fetch('mirror_side','right')
          if side=='above'
            z+=mirror['height']/2+gap+a['height']/2
          else
            x+=(side=='left' ? -1 : 1)*(mirror['width']/2+gap+a['width']/2)
          end
          return [x,z+a.fetch('height_offset',0)]
        end
        row=Domain.column_layout(c).fetch(a['part'])
        [row['x']+row['width']/2+a['offset'],c['height']+Surfaces.settings(c)['countertop_thickness']+a['above']+a['height']/2]
      end
      def validate(c)
        list=c.fetch('accessories',[])
        raise ArgumentError,'רשימת מראות ומנורות לא תקינה' unless list.is_a?(Array) && list.length<=18
        list.each do |a|
          raise ArgumentError,'פריט לא תקין' unless a.is_a?(Hash) && %w[mirror light].include?(a['kind'])
          linked=a['kind']=='light' && a.fetch('mirror_ref',-1).is_a?(Integer) && a.fetch('mirror_ref',-1)>=0
          raise ArgumentError,'בחר חלק קיים למראה או למנורה' unless linked || (a['part'].is_a?(Integer) && a['part'].between?(0,Domain.front_columns(c).length-1))
          {'width'=>[2,120],'height'=>[2,100],'above'=>[0,100],'offset'=>[-120,120]}.each do |k,r|
            Cabinetry.number!(a[k]);raise ArgumentError,"מידה לא תקינה: #{k}" unless a[k].between?(*r)
          end
          if a['kind']=='mirror'
            raise ArgumentError,'צורת מראה לא תקינה' unless %w[rectangle rounded oval arch].include?(a['shape'])
            raise ArgumentError,'מראת קשת צריכה להיות גבוהה מחצי רוחבה' if a['shape']=='arch' && a['height']<a['width']/2
            o=mirror_options(a)
            %w[frame front_light back_light].each { |k|raise ArgumentError,'אפשרות מראה לא תקינה' unless [true,false].include?(o[k]) }
            raise ArgumentError,'צבע מסגרת לא תקין' unless %w[black white nickel brass].include?(o['frame_color'])
            raise ArgumentError,'גוון תאורה לא תקין' unless %w[warm neutral cool].include?(o['light_color'])
            Cabinetry.number!(o['frame_width'])
            raise ArgumentError,'רוחב מסגרת: 1/16 עד 3 אינץ׳' unless o['frame_width'].between?(0.0625,3)
            inset=(o['frame'] ? o['frame_width'] : 0)+(o['front_light'] ? 1.0 : 0)
            raise ArgumentError,'המראה קטנה מדי למסגרת ולתאורה שבחרת' if [a['width'],a['height']].min<=2*inset+1
            inset=[inset,o['back_light'] ? 0.5 : 0].max
            raise ArgumentError,'המראה נמוכה מדי למסגרת הקשת' if a['shape']=='arch' && inset>0 && a['height']-a['width']/2<=inset
          else
            ref=a.fetch('mirror_ref',-1)
            raise ArgumentError,'שיוך מראה לא תקין' unless ref.is_a?(Integer) && (ref==-1 || (ref>=0 && list[ref].is_a?(Hash) && list[ref]['kind']=='mirror'))
            raise ArgumentError,'צד מנורה לא תקין' unless %w[left right above].include?(a.fetch('mirror_side','right'))
            {'mirror_gap'=>[0,60,3],'height_offset'=>[-100,100,0]}.each do |key,(lo,hi,default)|
              value=a.fetch(key,default);Cabinetry.number!(value)
              raise ArgumentError,'מרחק או גובה מנורה לא תקינים' unless value.between?(lo,hi)
            end
            raise ArgumentError,'מנורה מעל מראה חייבת להישאר מעל הקצה העליון שלה' if ref>=0 && a.fetch('mirror_side','right')=='above' && a.fetch('mirror_gap',3)+a.fetch('height_offset',0)<0
            raise ArgumentError,'בחר מנורה מגלריית החשמל' unless defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.products('wall_light').include?(a['product'])
          end
        end
        list.select { |a|a['kind']=='light' }.each do |light|
          raise ArgumentError,'המנורה חופפת למראה. בחר מיקום מעל או בצד והגדל מרווח.' if light_overlaps_mirror?(c,light)
        end
      end
      def light_overlaps_mirror?(c,light)
        x,z=center(c,light)
        items(c).select { |a|a['kind']=='mirror' }.any? do |m|
          mx,mz=center(c,m)
          (x-mx).abs<(light['width']+m['width'])/2-1e-6 && (z-mz).abs<(light['height']+m['height'])/2-1e-6
        end
      end
      def catalog
        return [] unless defined?(InteriorPro::ElectricalLibrary)
        lib=InteriorPro::ElectricalLibrary
        lib.products('wall_light').map do |name|
          path=lib.thumb_path('wall_light',name)
          {'name'=>name,'image'=>File.exist?(path) ? 'file:///'+path.tr('\\','/') : ''}
        end
      end
      def outline(a)
        w=a['width'];h=a['height']
        case a['shape']
        when 'oval'
          Array.new(64) { |i|t=i*Math::PI/32;[Math.cos(t)*w/2,Math.sin(t)*h/2] }
        when 'arch'
          [[-w/2,-h/2],[w/2,-h/2]]+Array.new(33) { |i|t=i*Math::PI/32;[Math.cos(t)*w/2,h/2-w/2+Math.sin(t)*w/2] }
        when 'rounded'
          r=[w,h].min*0.12
          [[w/2-r,h/2-r,0],[-w/2+r,h/2-r,90],[-w/2+r,-h/2+r,180],[w/2-r,-h/2+r,270]].flat_map do |cx,cz,angle|
            Array.new(9) { |i|t=(angle+i*90.0/8)*Math::PI/180;[cx+r*Math.cos(t),cz+r*Math.sin(t)] }
          end
        else
          [[-w/2,-h/2],[w/2,-h/2],[w/2,h/2],[-w/2,h/2]]
        end
      end
      def mirror_ring(entities,name,a,x,z,inset,width,y,depth,material)
        outer=outline(a.merge('width'=>a['width']-2*inset,'height'=>a['height']-2*inset))
        inner=outline(a.merge('width'=>a['width']-2*(inset+width),'height'=>a['height']-2*(inset+width)))
        g=entities.add_group;g.name=name;g.material=material
        pt=->(p,dy){[x+p[0],y+dy,z+p[1]]}
        outer.each_index do |i|
          j=(i+1)%outer.length
          [[pt.call(outer[i],0),pt.call(outer[j],0),pt.call(inner[j],0),pt.call(inner[i],0)],
           [pt.call(outer[j],depth),pt.call(outer[i],depth),pt.call(inner[i],depth),pt.call(inner[j],depth)],
           [pt.call(outer[i],depth),pt.call(outer[j],depth),pt.call(outer[j],0),pt.call(outer[i],0)],
           [pt.call(inner[i],0),pt.call(inner[j],0),pt.call(inner[j],depth),pt.call(inner[i],depth)]].each { |points|g.entities.add_face(points) }
        end
        g.entities.grep(Sketchup::Face).each { |f|f.material=material;f.back_material=material }
        soften_mirror(g)
        g
      end
      def soften_mirror(g)
        g.entities.grep(Sketchup::Edge).each do |e|
          next unless e.faces.length==2 && e.faces[0].normal.dot(e.faces[1].normal)>0.97
          e.soft=true;e.smooth=true
        end
      end
      def build_mirrors(entities,c,material,finish=nil)
        items(c).select { |a|a['kind']=='mirror' }.each do |a|
          o=mirror_options(a);x,z=center(c,a);g=entities.add_group;g.name='Vanity mirror'
          inset=o['frame'] ? o['frame_width'] : 0
          glass=g.entities.add_group;glass.name='Mirror glass';glass.material=material
          face=glass.entities.add_face(outline(a.merge('width'=>a['width']-2*inset,'height'=>a['height']-2*inset)).map { |dx,dz|[x+dx,-0.5,z+dz] })
          face.reverse! if face.normal.y>0;face.pushpull(0.25)
          glass.entities.grep(Sketchup::Face).each { |f|f.material=material;f.back_material=material }
          soften_mirror(glass)
          color=->(key){finish ? finish.call(key,mirror_colors.fetch(key)) : material}
          mirror_ring(g.entities,'Mirror frame',a,x,z,0,inset,-0.85,0.5,color.call(o['frame_color'])) if o['frame']
          mirror_ring(g.entities,'Mirror front LED',a,x,z,inset+0.5,0.25,-0.78,0.02,color.call(o['light_color'])) if o['front_light']
          mirror_ring(g.entities,'Mirror back LED',a,x,z,0.25,0.25,-0.30,0.10,color.call(o['light_color'])) if o['back_light']
          o.each { |k,v|g.set_attribute('InteriorPro::VanityMirror',k,v) }
        end
      end
      def owned(model,assembly,id)
        model.entities.grep(Sketchup::Group).select { |g|g.valid? && g.get_attribute('InteriorPro::VanityLighting','assembly')==assembly && g.get_attribute('InteriorPro::VanityLighting','cabinet')==id }
      end
      # Lights stay at model root: the existing electrical plan reader scans it.
      # The host operation belongs to Vanity; never nest an electrical operation.
      def sync_lights(service,c,id)
        old=owned(service.model,service.assembly_id,id)
        lights=c ? items(c).select { |a|a['kind']=='light' } : []
        old.each(&:erase!)
        return if lights.empty?
        lib=InteriorPro::ElectricalLibrary;tw=InteriorPro::TileWall
        tr=service.transform(c);back=Geom::Point3d.new(0,0,0).transform(tr)
        normal=Geom::Vector3d.new(0,-1,0).transform(tr)
        choices=[]
        service.model.entities.grep(Sketchup::Group).each do |wall|
          next unless wall.get_attribute('InteriorPro','type')=='wall'
          %w[a b].each do |side|
            fr=tw.frame_for(wall,side);next unless fr
            next unless fr[:nx]*normal.x+fr[:ny]*normal.y>0.99
            origin=tw.world(fr,0,0);distance=((back.x-origin[0])*fr[:nx]+(back.y-origin[1])*fr[:ny]).abs
            next if distance>6
            choices<<[distance,wall,side,fr]
          end
        end
        lights.each do |a|
          x,z=center(c,a);point=Geom::Point3d.new(x,0,z).transform(tr)
          match=choices.sort_by(&:first).find do |_,wall,side,fr|
            origin=tw.world(fr,0,0);u=(point.x-origin[0])*fr[:ux]+(point.y-origin[1])*fr[:uy]
            lo,hi=tw.face_limits(wall,fr,u)
            u-a['width']/2>=lo && u+a['width']/2<=hi && point.z-a['height']/2>=origin[2] && point.z+a['height']/2<=origin[2]+tw.wall_height(wall)
          end
          raise ArgumentError,'להצבת מנורות יש להצמיד את הוונטי לקיר ישר מתאים' unless match
          _,wall,side,fr=match;origin=tw.world(fr,0,0)
          u=(point.x-origin[0])*fr[:ux]+(point.y-origin[1])*fr[:uy]
          cfg={'kind'=>'wall_light','product'=>a['product'],'height'=>point.z-origin[2],'gangs'=>1,'turn'=>0}
          parts=lib.layout(service.model,cfg);raise 'לא ניתן לטעון את המנורה' if parts.empty?
          p=parts.first;w=p[:maxx]-p[:minx];h=p[:maxz]-p[:minz]
          raise 'מידות מקור של מנורה לא תקינות' unless w>0 && h>0
          sx=a['width']/w;sz=a['height']/h
          name="Vanity light size / #{a['product']} / #{a['width']} / #{a['height']}"
          d=service.model.definitions[name] || service.model.definitions.add(name)
          d.entities.add_instance(p[:defn],Geom::Transformation.scaling(sx,1,sz)) if d.entities.length==0
          p=p.merge(defn:d,ax:p[:ax]*sx,az:p[:az]*sz,minx:p[:minx]*sx,maxx:p[:maxx]*sx,minz:p[:minz]*sz,maxz:p[:maxz]*sz)
          check=lib.check(wall,side,fr,u,[p],tw.wall_height(wall))
          raise ArgumentError,'המנורה חורגת מהקיר או מתנגשת בפתח; שנה גודל או מיקום' unless check[:ok]
          g=lib.place!(wall:wall,side:side,fr:fr,u:u,cfg:cfg,parts:[p],outs:check[:outs],op:false)
          raise 'הצבת המנורה נכשלה' unless g
          g.set_attribute('InteriorPro::VanityLighting','assembly',service.assembly_id)
          g.set_attribute('InteriorPro::VanityLighting','cabinet',id)
        end
      end
    end
  end
end

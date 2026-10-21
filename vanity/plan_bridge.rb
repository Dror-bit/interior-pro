module InteriorPro
  module Vanity
    remove_const(:USE_PLUMBING_PLACEMENT) if const_defined?(:USE_PLUMBING_PLACEMENT,false)
    USE_PLUMBING_PLACEMENT=true
    module PlanBridge
      module_function
      def armed(c)
        s=Surfaces.settings(c);height=c['height']+s['countertop_thickness']+s['backsplash_height']
        {'kind'=>'plumb','plumb'=>true,'fkind'=>'vanity_builder','product'=>'Vanity','sign'=>'vanity',
         'hw'=>c['width']/2.0,'bo'=>0,'a0'=>0,'a1'=>c['depth']+0.5,
         'height'=>c['position']['z']+height/2,'hh'=>height/2}
      end
      def on_wall(c,wall,side,fr,u)
        raise 'הצבת Vanity ב־2D זמינה כרגע במפלס הרצפה הראשי' if fr[:floor_z].to_f.abs>0.001
        a=armed(c)
        part={minx:-a['hw'],maxx:a['hw'],minz:0,maxz:2*a['hh'],
              ax:0,az:0,du:0,h:c['position']['z'],gap:0}
        check=InteriorPro::FixtureLibrary.check(wall,side,fr,u,[part],'vanity',InteriorPro::TileWall.wall_height(wall))
        raise 'אין מקום לארון בנקודה הזאת: בדוק קצה קיר ופתחים' unless check[:ok]
        nx=fr[:nx];ny=fr[:ny];dx=-ny;dy=nx
        x=fr[:ox]+fr[:ux]*u;y=fr[:oy]+fr[:uy]*u
        copy=Cabinetry.copy(c)
        copy['position']=c['position'].merge('x'=>x-dx*c['width']/2,'y'=>y-dy*c['width']/2,
          'angle'=>Math.atan2(dy,dx)*180/Math::PI)
        copy
      end
      def place(editor,r,c,assembly:'main',existing:nil)
        wall=editor.send(:find_wall,r['wall_id'].to_s)
        raise 'הקיר לא נמצא' unless wall
        tw=InteriorPro::TileWall
        pt=Geom::Point3d.new(r['px'].to_f,r['py'].to_f,0).transform(wall.transformation.inverse)
        fa=tw.frame_for(wall,'a');fb=tw.frame_for(wall,'b')
        raise 'נדרש קיר ישר' unless fa && fb
        side,u=editor.send(:elec_side_u,fa,fb,pt.x.to_f,pt.y.to_f);fr=side=='a' ? fa : fb
        if r['dist'] && r['dist'].to_f>0
          lo,hi=tw.face_limits(wall,fr,u)
          u=InteriorPro::FixtureLibrary.u_from_corner(r['dist'].to_f,lo,hi,u)
        end
        item=on_wall(c,wall,side,fr,u);item['id']=existing || "v-#{SecureRandom.hex(8)}"
        s=Service.new(Sketchup.active_model,assembly)
        command=existing ? {'type'=>'update','id'=>existing,'changes'=>{'position'=>item['position']}} : {'type'=>'add','cabinet'=>item}
        s.execute([command],s.document['revision'])
        {ok:true,why:''}
      rescue StandardError=>e
        {ok:false,why:e.message}
      end
      def move(editor,r)
        _,assembly,id=r['id'].split('/')
        s=Service.new(Sketchup.active_model,assembly);c=s.document['cabinets'].find { |a|a['id']==id }
        return {ok:false,why:'Vanity not found'} unless c
        place(editor,r,c,assembly:assembly,existing:id)
      end
      def remove(id)
        _,assembly,cabinet=id.split('/')
        s=Service.new(Sketchup.active_model,assembly)
        s.execute([{'type'=>'remove','id'=>cabinet}],s.document['revision'])
        {ok:true,why:''}
      rescue StandardError=>e
        {ok:false,why:e.message}
      end
      def payload(model)
        dict=model.attribute_dictionary(Cabinetry::ModelStore::DICTIONARY,false)
        return [] unless dict
        level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level : 1
        return [] unless level.to_i==1
        dict.keys.grep(/\Avanity:/).flat_map do |key|
          Service.new(model,key.split(':',2).last).document['cabinets'].map do |c|
            p=c['position'];a=p['angle']*Math::PI/180;dx=Math.cos(a);dy=Math.sin(a)
            {'id'=>"vanity/#{key.split(':',2).last}/#{c['id']}",'kind'=>'plumb','sign'=>'vanity','product'=>'Vanity',
             'x'=>p['x']+dx*c['width']/2,'y'=>p['y']+dy*c['width']/2,'nx'=>dy,'ny'=>-dx,
             'w'=>c['width'],'a0'=>0,'a1'=>c['depth']+0.5,'h'=>p['z']+c['height']/2,'hh'=>c['height']/2}
          end
        end
      end
    end
  end
end

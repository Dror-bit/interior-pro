require_relative 'domain'
require_relative 'gallery'
require_relative '../cabinetry/model_store'
require_relative '../cabinetry/geometry'
module InteriorPro
  module Vanity
    remove_const(:USE_VANITY) if const_defined?(:USE_VANITY,false)
    USE_VANITY=true
    remove_const(:USE_FINISH_REFERENCES) if const_defined?(:USE_FINISH_REFERENCES,false)
    USE_FINISH_REFERENCES=true
    remove_const(:USE_SIMPLE_VANITY_LAYOUT) if const_defined?(:USE_SIMPLE_VANITY_LAYOUT,false)
    USE_SIMPLE_VANITY_LAYOUT=true
    class Service
      def handle_sku(id)
        {'keaton'=>'86715','warwick'=>'86705','globe'=>'86152-no-disc','hunter'=>'86702'}.fetch(id)
      end
      attr_reader :model,:assembly_id,:gallery
      def initialize(model,assembly_id='main',gallery=Gallery.new)
        @model=model;@assembly_id=Cabinetry.identifier!(assembly_id);@gallery=gallery
        @store=Cabinetry::ModelStore.new(model)
      end
      def document
        @store.read(domain:'vanity',assembly_id:@assembly_id) || Cabinetry.create(domain:'vanity',assembly_id:@assembly_id)
      end
      def groups
        @model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'domain')=='vanity' &&
            g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'assembly_id')==@assembly_id &&
            g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'role')=='cabinet'
        end
      end
      def transform(c)
        p=c['position']
        Geom::Transformation.translation([p['x'],p['y'],p['z']]) * Geom::Transformation.rotation(ORIGIN,Z_AXIS,p['angle']*Math::PI/180)
      end
      def execute(commands,revision,transparent:false,refresh_geometry:false)
        raise 'Vanity is disabled' unless USE_VANITY
        raise 'Exit component editing first' if @model.active_path
        source=document
        candidate=Cabinetry.plan(source,commands,expected_revision:revision,validator:Domain.method(:validate))
        before=source['cabinets'].to_h { |c|[c['id'],c] }
        refresh_ids=refresh_geometry ? commands.select { |cmd|cmd['type']=='update' }.map { |cmd|cmd['id'] } : []
        rebuilding=candidate['cabinets'].select do |c|
          previous=before[c['id']]
          refresh_ids.include?(c['id']) || !previous || geometry_key(previous)!=geometry_key(c)
        end
        rebuilding.select { |c|c['product_id']=='gallery' }.each do |c|
          a=@gallery.entry(c['asset_id'])
          raise ArgumentError,'Imported cabinets keep their original dimensions' unless a['dimensions'].zip(%w[width depth height]).all? { |n,k|(n-c[k]).abs<1e-6 }
        end
        return source if candidate==source && rebuilding.empty?
        prepare_assets(candidate.merge('cabinets'=>rebuilding)) unless transparent
        @busy=true
        @model.start_operation('Vanity: edit',true,false,transparent)
        begin
          @store.write(source,expected_revision:nil) unless @store.read(domain:'vanity',assembly_id:@assembly_id)
          @store.write(candidate,expected_revision:revision)
          old=source['cabinets'].to_h { |c|[c['id'],c] };now=candidate['cabinets'].to_h { |c|[c['id'],c] }
          (old.keys|now.keys).each do |id|
            next if old[id]==now[id] && !refresh_ids.include?(id)
            owned=groups.select { |g|g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id')==id }
            if !refresh_ids.include?(id) && old[id] && now[id] && geometry_key(old[id])==geometry_key(now[id]) && owned.length==1
              owned.first.transformation=transform(now[id])
            else
              raise 'Duplicate Vanity identity' if owned.length>1
              if now[id]
                root=owned.first
                root.entities.clear! if root
                build(now[id],candidate,root)
              else
                owned.each(&:erase!)
              end
            end
          end
          @model.commit_operation
        rescue Exception
          @model.abort_operation;raise
        ensure
          @busy=false
        end
        candidate
      end
      def geometry_key(c)
        key=c.reject { |k,_|k=='position' }
        if c['product_id']=='vanity' && Domain.front_columns(c).any? { |col|col['kind']=='makeup' }
          key=key.merge('makeup_floor_reach'=>c['position']['z'])
        end
        key
      end
      # Materials persist in SketchUp's palette independently of cabinet Undo.
      # Prepare them before the document/geometry transaction, so deferred
      # material observers do not insert a Properties step after undoing a cabinet.
      def prepare_assets(doc)
        palette={'white'=>'#F5F5F0','ivory'=>'#E8E4D9','gray'=>'#969C9B','brass'=>'#B39456','black'=>'#242729','white_oak'=>'#D9C7A9','chrome'=>'#BAC2C7'}
        palette.merge!(Faucets.colors)
        faucets=doc['cabinets'].select { |c|Faucets.selected(c) }.map { |c|c['faucet_id'] }.uniq
        muse=doc['cabinets'].any? { |c|c['product_id']=='vanity' && MuseSink.selected(Surfaces.settings(c)) }
        handles=doc['cabinets'].map { |c|c['handle'] }.select { |id|%w[keaton warwick globe hunter].include?(id) }.uniq
        @handle_definitions||={}
        handles.each do |id|
          next if @handle_definitions[id] && @handle_definitions[id].valid?
          sku=handle_sku(id)
          path=File.expand_path(File.join(__dir__,'handles',sku,'handle.skp')).tr('\\','/').downcase
          @handle_definitions[id]=@model.definitions.find do |definition|
            definition.get_attribute('InteriorPro::VanityAssets','handle')==id ||
              (!definition.path.empty? && File.expand_path(definition.path).tr('\\','/').downcase==path)
          end
        end
        assets=doc['cabinets'].select { |c|c['product_id']=='gallery' }.map { |c|c['asset_id'] }.uniq
        reference=finish_definition
        faces=reference ? reference.entities.grep(Sketchup::Face) : []
        needed=palette.any? do |key,color|
          face=faces.find { |f|f.get_attribute('InteriorPro::VanityAssets','finish')==key }
          !face || !face.material || !face.material.valid? || (key=='white_oak' ? !face.material.texture : face.material.color.to_a!=Sketchup::Color.new(color).to_a)
        end
        needed||=assets.any? { |id|!@definitions || !@definitions[id] || !@definitions[id].valid? }
        needed||=handles.any? { |id|!@handle_definitions || !@handle_definitions[id] || !@handle_definitions[id].valid? }
        needed||=faucets.any? { |id|!Faucets.find(@model,id) }
        needed||=muse && !MuseSink.find(@model)
        return unless needed
        @busy=true;@model.start_operation('Vanity: prepare gallery and finishes',true)
        begin
          if USE_FINISH_REFERENCES
            unless reference
              reference=@model.definitions.add('InteriorPro_Vanity_Finish_References')
              reference.set_attribute('InteriorPro::VanityAssets','role','finish_references')
              @finish_definition=reference
            end
            palette.each_with_index do |(key,color),i|
              face=faces.find { |f|f.get_attribute('InteriorPro::VanityAssets','finish')==key }
              mat=material(key,color)
              face||=reference.entities.add_face([i,0,0],[i+0.25,0,0],[i,0.25,0])
              face.set_attribute('InteriorPro::VanityAssets','finish',key)
              face.material=mat;face.back_material=mat
            end
          else
            palette.each { |k,color|material(k,color) }
          end
          @definitions||={}
          @handle_definitions||={}
          handles.each do |id|
            next if @handle_definitions[id] && @handle_definitions[id].valid?
            sku=handle_sku(id)
            before=@model.materials.to_a
            @handle_definitions[id]=@model.definitions.load(File.join(__dir__,'handles',sku,'handle.skp'))
            @handle_definitions[id].set_attribute('InteriorPro::VanityAssets','handle',id)
            if defined?(InteriorPro::MaterialIds)
              (@model.materials.to_a-before).each { |mat|InteriorPro::MaterialIds.ensure_id!(mat,@model) }
            end
          end
          assets.each do |id|
            next if @definitions[id] && @definitions[id].valid?
            before=@model.materials.to_a;@definitions[id]=@gallery.definition(@model,id)
            if defined?(InteriorPro::MaterialIds)
              (@model.materials.to_a-before).each { |mat|InteriorPro::MaterialIds.ensure_id!(mat,@model) }
            end
          end
          faucets.each { |id|Faucets.definition(@model,id,material('black',palette.fetch('black'))) }
          MuseSink.definition(@model) if muse
          @model.commit_operation
          true
        rescue Exception
          @model.abort_operation;raise
        ensure
          @busy=false
        end
      end
      def finish_definition
        return nil unless USE_FINISH_REFERENCES
        return @finish_definition if @finish_definition && @finish_definition.valid?
        @finish_definition=@model.definitions.find { |d|d.get_attribute('InteriorPro::VanityAssets','role')=='finish_references' }
      end
      def synchronize_native
        return if @busy || !USE_VANITY || @model.active_path
        reconcile_native
      end
      def reconcile_native
        # SketchUp changes the apparent transforms while a group is open.
        # Never interpret edit-context transforms as native Move/Eraser commands.
        return if @model.active_path
        doc=document;commands=[]
        doc['cabinets'].each do |c|
          list=groups.select { |g|g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id')==c['id'] }
          raise 'Duplicate Vanity identity; use the editor to add cabinets' if list.length>1
          if list.empty?
            commands << {'type'=>'remove','id'=>c['id']};next
          end
          t=list.first.transformation
          next if t.to_a.zip(transform(c).to_a).all? { |a,b|(a-b).abs<1e-6 }
          raise 'Vanity supports Move and horizontal rotation, not Scale or tilt' unless
            [t.xaxis,t.yaxis,t.zaxis].all? { |a|(a.length-1).abs<1e-6 } &&
            t.zaxis.dot(Z_AXIS)>1-1e-6 && t.xaxis.cross(t.yaxis).dot(t.zaxis)>1-1e-6
          p=t.origin;position={'x'=>p.x.to_f,'y'=>p.y.to_f,'z'=>p.z.to_f,'angle'=>Math.atan2(t.xaxis.y,t.xaxis.x)*180/Math::PI}
          position['z']=0.0 if position['z'].abs<1e-6
          commands << {'type'=>'update','id'=>c['id'],'changes'=>{'position'=>position}}
        end
        execute(commands,doc['revision'],transparent:true) unless commands.empty?
      rescue StandardError => e
        # Return owned geometry to its last valid source after rejected native edits.
        @busy=true;@model.start_operation('Vanity: restore invalid placement',true,false,true)
        groups.each do |g|
          c=doc['cabinets'].find { |v|v['id']==g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id') }
          g.transformation=transform(c) if c
        end
        @model.commit_operation
        warn "[Vanity] #{e.message}"
      ensure
        @busy=false
      end
      def material(name,color)
        definition=finish_definition
        face=definition && definition.entities.grep(Sketchup::Face).find { |f|f.get_attribute('InteriorPro::VanityAssets','finish')==name }
        mat=(face && face.material) || @model.materials["InteriorPro_Vanity_#{name}"] ||
          @model.materials["Vanity / #{name}"] || @model.materials["Vanity _ #{name}"] || @model.materials.add("InteriorPro_Vanity_#{name}")
        desired=Sketchup::Color.new(color)
        mat.color=desired unless (name=='white_oak' && mat.texture) || mat.color.to_a==desired.to_a
        if Faucets.colors.key?(name) && mat.respond_to?(:metallic_factor=)
          metal=name=='matte_black' ? 0.25 : 1.0
          rough=name=='matte_black' ? 0.55 : 0.3
          mat.metalness_enabled=true unless mat.metalness_enabled?
          mat.roughness_enabled=true unless mat.roughness_enabled?
          mat.metallic_factor=metal unless mat.metallic_factor==metal
          mat.roughness_factor=rough unless mat.roughness_factor==rough
        end
        if name=='white_oak' && !mat.texture
          mat.texture=File.join(__dir__,'textures','white_oak.jpg')
          mat.texture.size=[24,16]
        end
        InteriorPro::MaterialIds.ensure_id!(mat,@model) if defined?(InteriorPro::MaterialIds)
        mat
      end
      def build(c,doc,g=nil)
        g||=@model.entities.add_group;g.name="Vanity / #{c['product_id']} / #{c['id']}"
        @store.stamp(g,doc,c['id']);g.transformation=transform(c)
        if c['product_id']=='gallery'
          a=@gallery.entry(c['asset_id']);definition=@definitions.fetch(c['asset_id'])
          g.entities.add_instance(definition,Geom::Transformation.translation([-a['min'][0],-a['max'][1],-a['min'][2]]))
          return g
        end
        geo=Cabinetry::Geometry;e=g.entities;w=c['width'];d=c['depth'];h=c['height'];b=Domain.body_bottom(c);t=0.75
        mat=material(c['finish'],{'white'=>'#F5F5F0','ivory'=>'#E8E4D9','gray'=>'#969C9B','white_oak'=>'#D9C7A9'}.fetch(c['finish']))
        box=lambda do |name,x,y,z,bw,bd,bh,m=mat|
          pieces=name.start_with?('Drawer') ? Surfaces.clear_drawer(c,[x,y,z,bw,bd,bh]) : [[x,y,z,bw,bd,bh]]
          pieces.each { |p|geo.box(e,name,*p,m) }
        end
        edge_cols=c['product_id']=='vanity' ? Domain.front_columns(c) : []
        [0,w-t].each_with_index do |x,i|
          makeup=!edge_cols.empty? && edge_cols[i==0 ? 0 : -1]['kind']=='makeup'
          bottom=makeup ? -c['position']['z'] : b
          box.call('Side',x,-d+t,bottom,t,d-t,h-bottom)
        end
        if c['product_id']=='vanity'
          cols=Domain.front_columns(c);layout=Domain.column_layout(c)
          if cols.any? { |col|col['kind']=='makeup' }
            cols.each_with_index do |col,i|
              next if col['kind']=='makeup'
              start=layout[i]['x'];bay=layout[i]['width']
              left=i==0 ? t : t/2;right=i==cols.length-1 ? t : t/2
              box.call('Bottom',start+left,-d+t,b,bay-left-right,d-t,t)
              box.call('Back lower rail',start+left,-t,b+t,bay-left-right,t,3)
            end
          else
            box.call('Bottom',t,-d+t,b,w-2*t,d-t,t)
            box.call('Back lower rail',t,-t,b+t,w-2*t,t,3)
          end
          box.call('Back upper rail',t,-t,h-3,w-2*t,t,3)
          if USE_SIMPLE_VANITY_LAYOUT && c['front_columns'].is_a?(Array) && !c['front_columns'].empty?
            cols=Domain.front_columns(c);layout=Domain.column_layout(c)
            cols.each_with_index do |col,i|
              start=layout[i]['x'];bay=layout[i]['width']
              count=col['count'];makeup=col['kind']=='makeup';drawer=col['kind']=='drawers' || makeup
              combined=col['kind']=='doors_drawer'
              if combined
                x=start+0.125;z=h-5+0.0625;fw=bay-0.25;fh=4.875
                front(e,geo,c,mat,x,z,fw,fh,d,horizontal:true)
                box.call('Drawer bottom',x+1,-d+1,z+0.75,fw-2,d-2,0.5)
                [x+1,x+fw-1.5].each { |sx|box.call('Drawer side',sx,-d+1,z+1.25,0.5,d-2.5,[fh-1.5,4].min) }
                box.call('Drawer back',x+1.5,-1.5,z+1.25,fw-3,0.5,[fh-1.5,4].min)
              end
              count.times do |j|
                fw=drawer ? bay-0.25 : (bay-0.125)/count-0.125
                fh=makeup ? 4.875 : drawer ? (h-b)/count-0.125 : h-b-(combined ? 5 : 0)-0.125
                x=start+0.125+(drawer ? 0 : j*(bay-0.125)/count)
                z=makeup ? h-5.0 : b+0.0625+(drawer ? j*(h-b)/count : 0)
                front(e,geo,c,mat,x,z,fw,fh,d,horizontal:drawer,handle_left:!drawer && Domain.handle_left?(col,j))
                if drawer
                  box.call('Drawer bottom',x+1,-d+1,z+0.75,fw-2,d-2,0.5)
                  [x+1,x+fw-1.5].each { |sx|box.call('Drawer side',sx,-d+1,z+1.25,0.5,d-2.5,[fh-1.5,4].min) }
                  box.call('Drawer back',x+1.5,-1.5,z+1.25,fw-3,0.5,[fh-1.5,4].min)
                end
              end
              if i>0
                box.call('Divider',start-t/2,-d+t,b+t,t,d-2*t,h-b-t)
              end
            end
          else
          c['basins'].times do |i|
            bay=w/c['basins'];fw=(bay-0.375)/2
            [0,1].each { |j|front(e,geo,c,mat,i*bay+0.125+j*(fw+0.125),b+0.0625,fw,h-b-0.125,d,handle_left:j.odd?) }
          end
          end
          if USE_VANITY_SURFACES && c.key?('surfaces')
            colors={'white'=>'#F5F5F0','ivory'=>'#E8E4D9','gray'=>'#969C9B','black'=>'#242729','chrome'=>'#BAC2C7','brass'=>'#B39456'}
            colors.merge!(Faucets.colors)
            Surfaces.build(e,c,lambda { |key|material(key,colors.fetch(key)) })
            Faucets.build(e,c,@model,lambda { |key|material(key,colors.fetch(key)) })
          elsif USE_SIMPLE_VANITY_LAYOUT && c['countertop']=='white'
            box.call('White countertop',0,-d-0.5,h,w,d+0.5,0.75,material('white','#F5F5F0'))
          end
        else
          if USE_VANITY_SURFACES && c.key?('surfaces')
            colors={'white'=>'#F5F5F0','ivory'=>'#E8E4D9','gray'=>'#969C9B','black'=>'#242729'}
            Surfaces.build(e,c,lambda { |key|material(key,colors.fetch(key)) })
          else
            box.call('Makeup top',0,-d,h,w,d,t,material('white','#F5F5F0'))
          end
          if c['drawer']
            dz=h-t-5
            front(e,geo,c,mat,0.125,dz,w-0.25,4.875,d,horizontal:true)
            box.call('Drawer bottom',1,-d+1.5,dz+0.5,w-2,d-2,0.5)
            [1,w-1.5].each { |x|box.call('Drawer side',x,-d+1.5,dz+1,0.5,d-2,3) }
            box.call('Drawer back',1.5,-1,dz+1,w-3,0.5,3)
          end
        end
        if c['legs']
          if c.fetch('leg_style','square')=='plinth'
            layout=c['product_id']=='vanity' ? Domain.column_layout(c) : [{'x'=>0,'width'=>w}]
            cols=c['product_id']=='vanity' ? Domain.front_columns(c) : [{'kind'=>'doors'}]
            layout.each_with_index do |row,i|
              next if cols[i]['kind']=='makeup'
              box.call('Plinth',row['x']+0.75,-d+2,0,row['width']-1.5,d-2,b)
            end
          else
            leg_positions(c).each { |x|[-d+1.5,-3].each do |y|
              if c.fetch('leg_style','square')=='round'
                leg=e.add_group;leg.name='Round leg';leg.material=mat
                circle=leg.entities.add_circle([x+0.75,y+0.75,0],[0,0,1],0.75,24)
                face=leg.entities.add_face(circle);face.reverse! if face.normal.z<0;face.pushpull(b)
              else
                box.call('Leg',x,y,0,1.5,1.5,b)
              end
            end }
          end
        end
        g
      end
      def leg_positions(c)
        return [1,c['width']-2.5] unless c['product_id']=='vanity'
        cols=Domain.front_columns(c);layout=Domain.column_layout(c)
        cols.each_index.flat_map do |i|
          next [] if cols[i]['kind']=='makeup'
          start=layout[i]['x'];bay=layout[i]['width']
          positions=[]
          positions<<start+1 if i==0 || cols[i-1]['kind']=='makeup'
          positions<<start+bay-2.5 if i==cols.length-1 || cols[i+1]['kind']=='makeup'
          positions
        end
      end
      def front(e,geo,c,mat,x,z,w,h,d,horizontal:false,handle_left:false)
        geo.front(e,x,z,w,h,d,c['style'],mat)
        return if c['handle']=='none'
        if %w[keaton warwick globe hunter].include?(c['handle'])
          @handle_definitions||={}
          unless @handle_definitions[c['handle']] && @handle_definitions[c['handle']].valid?
            sku=handle_sku(c['handle'])
            path=File.expand_path(File.join(__dir__,'handles',sku,'handle.skp')).tr('\\','/').downcase
            @handle_definitions[c['handle']]=@model.definitions.find { |definition|definition.get_attribute('InteriorPro::VanityAssets','handle')==c['handle'] || (!definition.path.empty? && File.expand_path(definition.path).tr('\\','/').downcase==path) }
          end
          vertical=!horizontal && %w[keaton warwick].include?(c['handle'])
          cx=horizontal ? x+w/2 : (handle_left ? x+1 : x+w-1);cz=horizontal ? (c['style']=='shaker' && %w[keaton warwick].include?(c['handle']) ? z+h-1 : z+h/2) : z+h-[3.0,h/2].min
          cz=z+h/2 if vertical && h<7
          axes=vertical ? [[0,0,1],[-1,0,0],[0,-1,0]] : [[1,0,0],[0,0,1],[0,-1,0]]
          axes=[[0,0,-1],[1,0,0],[0,-1,0]] if vertical && handle_left
          instance=e.add_instance(@handle_definitions.fetch(c['handle']),Geom::Transformation.axes([cx,-d,cz],*axes))
          instance.name="Vanity handle / #{c['handle']}"
          return
        end
        metal=material(c['handle'],c['handle']=='brass' ? '#B39456' : '#242729')
        pull=[4,w*0.6].min
        geo.box(e,'Pull',x+(w-pull)/2,-d-0.75,z+h/2-0.125,pull,0.75,0.25,metal)
      end
    end
  end
end

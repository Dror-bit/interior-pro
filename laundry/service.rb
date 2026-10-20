require_relative 'domain'
require_relative '../cabinetry/model_store'
require_relative '../cabinetry/geometry'
require 'securerandom'
module InteriorPro
  module Laundry
    remove_const(:USE_FINISH_REFERENCES) if const_defined?(:USE_FINISH_REFERENCES,false)
    USE_FINISH_REFERENCES=true
    class Service
      attr_reader :model,:assembly_id
      def initialize(model,assembly_id='main')
        @model=model;@assembly_id=Cabinetry.identifier!(assembly_id);@store=Cabinetry::ModelStore.new(model)
      end
      def document
        @store.read(domain:domain_name,assembly_id:@assembly_id) || Cabinetry.create(domain:domain_name,assembly_id:@assembly_id)
      end
      def domain_name; 'laundry'; end
      def validator; Domain.method(:validate); end
      def material_namespace; 'Laundry'; end
      def finish_palette
        palette={'ivory'=>'#E8E4D9','white'=>'#F5F5F0','gray'=>'#969C9B','brass'=>'#B39456','black'=>'#242729'}
        return palette unless domain_name=='laundry' && Laundry::USE_APPLIANCE_PRODUCTS
        palette.merge('appliance_white'=>'#F3F3F1','appliance_glass'=>'#26353E','appliance_metal'=>'#ADB3B6')
      end
      def finish_definition
        return nil unless Laundry::USE_FINISH_REFERENCES
        return @finish_definition if @finish_definition && @finish_definition.valid?
        @finish_definition=@model.definitions.find { |definition|definition.get_attribute('InteriorPro::StorageAssets','domain')==domain_name && definition.get_attribute('InteriorPro::StorageAssets','role')=='finish_references' }
      end
      # Asset initialization is separate from the single source/geometry edit.
      # An uninstantiated definition holds finish references, so undoing the
      # last cabinet never makes V-Ray recreate a material or split the edit.
      # This adds no scene entity and changes no other tool's materials.
      def prepare_materials!
        return false unless Laundry::USE_FINISH_REFERENCES
        definition=finish_definition
        faces=definition ? definition.entities.grep(Sketchup::Face) : []
        ready=finish_palette.all? do |name,color|
          face=faces.find { |f|f.get_attribute('InteriorPro::StorageAssets','finish')==name }
          face && face.material && face.material.valid? && face.material.color.to_a==Sketchup::Color.new(color).to_a
        end
        return false if ready
        @model.start_operation('Storage: initialize finish assets',true)
        begin
          unless definition
            definition=@model.definitions.add("InteriorPro_#{material_namespace}_Finish_References")
            definition.set_attribute('InteriorPro::StorageAssets','domain',domain_name)
            definition.set_attribute('InteriorPro::StorageAssets','role','finish_references')
            @finish_definition=definition
          end
          finish_palette.each_with_index do |(name,color),i|
            mat=material(name,color)
            face=faces.find { |f|f.get_attribute('InteriorPro::StorageAssets','finish')==name }
            face||=definition.entities.add_face([i,0,0],[i+0.25,0,0],[i,0.25,0])
            face.set_attribute('InteriorPro::StorageAssets','finish',name)
            face.material=mat;face.back_material=mat
          end
          @model.commit_operation
        rescue Exception
          @model.abort_operation
          raise
        end
        true
      end
      def groups
        @model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'domain')==domain_name &&
            g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'assembly_id')==@assembly_id &&
            g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'role')=='cabinet'
        end
      end
      def execute(commands,revision)
        raise ArgumentError,'Close the group editing context first' if @model.active_path
        source=document
        candidate=Cabinetry.plan(source,commands,expected_revision:revision,validator:validator)
        return source if candidate==source
        prepare_materials!
        @executing=true
        @model.start_operation("#{material_namespace}: edit cabinets",true)
        begin
          @store.write(source,expected_revision:nil) unless @store.read(domain:domain_name,assembly_id:@assembly_id)
          @store.write(candidate,expected_revision:revision)
          old=source['cabinets'].to_h { |c|[c['id'],c] };now=candidate['cabinets'].to_h { |c|[c['id'],c] }
          changed=(old.keys|now.keys).select { |id|old[id]!=now[id] }
          existing=groups.to_h { |g|[g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id'),g] }
          changed.each do |id|
            g=existing[id]
            if now[id]
              g.entities.clear! if g
              build(now[id],candidate,g)
            else
              g.erase! if g
            end
          end
          @model.commit_operation
        rescue Exception
          @model.abort_operation
          raise
        ensure
          @executing=false
        end
        candidate
      end
      def executing?; !!@executing; end
      def native_z_allowed?(c,z)
        if domain_name=='laundry' && c['product_id']=='upper'
          z.between?(12,108) && (z*8-(z*8).round).abs<1e-6
        else
          z.abs<1e-6
        end
      end

      def transform_for(c)
        p=c['position']
        Geom::Transformation.translation(Geom::Vector3d.new(p['x'],p['y'],p['z'])) * Geom::Transformation.rotation(ORIGIN,Z_AXIS,p['angle']*Math::PI/180)
      end

      # Called only after a native transaction has committed. Source-only sync
      # transparently joins that native Move/Rotate/Eraser undo step.
      def sync_native!
        return if executing? || @model.active_path
        source=@store.read(domain:domain_name,assembly_id:@assembly_id)
        return unless source
        owned=groups.group_by { |g|g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id') }
        commands=[];restore=[]
        source['cabinets'].each do |c|
          matches=owned.fetch(c['id'],[])
          if matches.empty?
            commands<<{'type'=>'remove','id'=>c['id']}
            next
          end
          # Copy/Paste is not an add command; do not bind a duplicate ID.
          raise ArgumentError,'Copied cabinets are not supported; use Place new cabinet' if matches.length!=1
          g=matches.first;t=g.transformation;expected=transform_for(c)
          next if t.to_a.zip(expected.to_a).all? { |a,b|(a-b).abs<1e-6 }
          restore<<[g,expected]
          matrix=t.to_a
          x=Geom::Vector3d.new(*matrix.values_at(0,1,2))
          y=Geom::Vector3d.new(*matrix.values_at(4,5,6))
          z=Geom::Vector3d.new(*matrix.values_at(8,9,10))
          unless [matrix[15]-1,x.length-1,y.length-1,z.length-1,x.z,y.z,z.x,z.y,z.z-1,x.dot(y),x.cross(y).z-1].all? { |v|v.abs<1e-6 } && native_z_allowed?(c,t.origin.z.to_f)
            raise ArgumentError,'Use Move on the floor or Rotate about the vertical axis; edit sizes in Storage'
          end
          p=t.origin
          commands<<{'type'=>'update','id'=>c['id'],'changes'=>{'position'=>{'x'=>p.x.to_f,'y'=>p.y.to_f,'z'=>c['product_id']=='upper' ? p.z.to_f : 0.0,'angle'=>Math.atan2(x.y,x.x)*180/Math::PI}}}
        end
        return if commands.empty?
        candidate=Cabinetry.plan(source,commands,expected_revision:source['revision'],validator:validator)
        @executing=true
        @model.start_operation('Storage: synchronize native edit',true,false,true)
        @store.write(candidate,expected_revision:source['revision'])
        @model.commit_operation
        nil
      rescue ArgumentError=>e
        # Validate before opening the transparent operation. A rejected native
        # transform is restored within the same undo step, without aborting it.
        if restore && !restore.empty? && source
          @executing=true
          @model.start_operation('Storage: restore unsupported placement',true,false,true)
          source['cabinets'].each do |c|
            matches=owned.fetch(c['id'],[]).select(&:valid?)
            if matches.empty?
              build(c,source)
            else
              matches.each { |g|g.transformation=transform_for(c) }
            end
          end
          @model.commit_operation
        end
        e.message
      rescue Exception
        @model.abort_operation if @executing
        raise
      ensure
        @executing=false
      end
      def material(name,color)
        # V-Ray normalizes '/' to '_' in material names. Looking up only the old
        # slash name then recreates materials during every rebuild and breaks
        # the native operation through material-sync observers. Keep a safe
        # canonical name and recognize both legacy spellings without renaming.
        safe="InteriorPro_#{material_namespace}_#{name}"
        definition=finish_definition
        reference=definition && definition.entities.grep(Sketchup::Face).find { |f|f.get_attribute('InteriorPro::StorageAssets','finish')==name }
        mat=(reference && reference.material) || @model.materials[safe] || @model.materials["#{material_namespace} / #{name}"] || @model.materials["#{material_namespace} _ #{name}"] || @model.materials.add(safe)
        desired=Sketchup::Color.new(color)
        mat.color=desired unless mat.color.to_a==desired.to_a
        # Stamp within the edit operation. Otherwise the deferred house material
        # watcher adds a separate Properties undo step after cabinet creation.
        InteriorPro::MaterialIds.ensure_id!(mat,@model) if defined?(InteriorPro::MaterialIds) && InteriorPro::MaterialIds::USE_MATERIAL_IDS
        mat
      end
      def build(c,doc,g=nil)
        return build_appliance(c,doc,g) if Appliances.appliance?(c)
        return build_upper(c,doc,g) if c['product_id']=='upper'
        g||=@model.entities.add_group
        g.name="Laundry / Base / #{c['width']} in"
        @store.stamp(g,doc,c['id'])
        geom=Cabinetry::Geometry;e=g.entities
        w=c['width'];h=c['height'];d=c['depth'];toe=4.0
        mat=material(c['finish'],{'ivory'=>'#E8E4D9','white'=>'#F5F5F0','gray'=>'#969C9B'}.fetch(c['finish']))
        [[0,'Left side'],[w-0.75,'Right side']].each { |x,name|geom.box(e,name,x,-d+0.75,toe,0.75,d-0.75,h-toe,mat) }
        geom.box(e,'Back',0.75,-0.5,toe,w-1.5,0.5,h-toe,mat)
        geom.box(e,'Bottom',0.75,-d+0.75,toe,w-1.5,d-1.25,0.75,mat)
        geom.box(e,'Top rear support',0.75,-3,h-0.75,w-1.5,2.5,0.75,mat)
        geom.box(e,'Top front support',0.75,-d+0.75,h-0.75,w-1.5,2.5,0.75,mat)
        geom.box(e,'Toe kick',0,-d+3,0,w,0.75,toe,mat)
        rows = c['front']=='drawers' ? Cabinetry.divide(h-toe,3) : [h-toe]
        z=toe
        rows.each do |nominal|
          fh=nominal-0.125;fz=z+0.0625;double=c['front']=='double'
          fw=double ? (w-0.375)/2 : w-0.25
          (double ? [0.125,fw+0.25] : [0.125]).each_with_index do |x,i|
            geom.front(e,x,fz,fw,fh,d,c['style'],mat)
            unless c['handle']=='none'
              metal=material(c['handle'],c['handle']=='brass' ? '#B39456' : '#242729')
              drawer=c['front']=='drawers'
              hx=drawer ? x+(fw-5)/2 : (double && i==1 ? x+1 : x+fw-1.32)
              hz=drawer ? fz+(fh-0.32)/2 : fz+fh-7
              geom.box(e,'Pull',hx,-d-1.0,hz,drawer ? 5 : 0.32,0.32,drawer ? 0.32 : 5,metal)
              mounts=drawer ? [[hx+0.35,hz],[hx+4.35,hz]] : [[hx,hz+0.35],[hx,hz+4.35]]
              mounts.each { |mx,mz|geom.box(e,'Pull mount',mx,-d-0.68,mz,0.3,0.68,0.3,metal) }
            end
          end
          z+=nominal
        end
        g.transformation=transform_for(c)
        g
      end
      # Fixed-dimension planning representation; decorative details are schematic.
      def build_appliance(c,doc,g=nil)
        g||=@model.entities.add_group;g.name="Laundry / #{c['model_id']} / planning model"
        @store.stamp(g,doc,c['id']);e=g.entities
        if c['product_id']=='stack' || Appliances.model(c)['parts']
          parts=c['product_id']=='stack' ? [['washer',0.0,0.0],['dryer',0.0,39.0]] : Appliances.model(c)['parts'].each_with_index.map{|product,i|[product,i*28.0,0.0]}
          parts.each do |product,x,z|
            spec=Appliances::MODELS.fetch(product);part=e.add_group;part.name=spec['model']
            draw_machine(part.entities,product,spec)
            part.transformation=Geom::Transformation.translation([x,0,z])
          end
          g.set_attribute('InteriorPro::StorageAssets','stacking_kit','LG KSTK4 required') if c['product_id']=='stack'
        else
          draw_machine(e,c['product_id'],Appliances.model(c))
        end
        g.set_attribute('InteriorPro::StorageAssets','representation','schematic_dimensioned')
        g.set_attribute('InteriorPro::StorageAssets','source',Appliances.model(c)['source'])
        g.transformation=transform_for(c);g
      end
      def draw_machine(e,product,spec)
        geom=Cabinetry::Geometry;w=spec['width'];h=spec['height'];d=spec['depth']
        white=material('appliance_white',finish_palette['appliance_white']);glass=material('appliance_glass',finish_palette['appliance_glass']);metal=material('appliance_metal',finish_palette['appliance_metal'])
        if %w[washer_top dryer_rear].include?(product)
          inset=product=='washer_top' ? 0 : 1.25
          geom.box(e,'Rear-console enclosure',0,-d+inset,0,w,d-inset,h-5,white)
          geom.box(e,'Rear control console',0,-4,h-5,w,4,5,white)
          if product=='washer_top'
            geom.box(e,'Top-load lid frame',1,-d+1,h-5,w-2,d-6,0.5,metal)
            geom.box(e,'Top-load glass lid',2,-d+2,h-4.5,w-4,d-8,0.25,glass)
          else
            # The matching rear-console dryer still loads from its FRONT.
            geom.front(e,2,4,w-4,h-12,d-0.5,'slab',white)
            geom.box(e,'Dryer door pull',w-5,-d,19,2,0.5,0.5,metal)
          end
          geom.box(e,'Rear display',w-9,-4.25,h-4,7,0.25,2,glass)
          appliance_disc(e,'Rear dial',[w/2,-4,h-2.5],1.25,0.5,metal)
        else
          geom.box(e,'Appliance enclosure',0,-d+1.25,0,w,d-1.25,h,white)
          geom.box(e,'Control panel',0.5,-d+0.75,h-5,w-1,0.5,4,white)
          geom.box(e,'Display',w-9,-d+0.5,h-4,7,0.25,2,glass)
          appliance_disc(e,'Control dial',[w/2,-d+0.75,h-2.75],1.25,0.75,metal)
          appliance_disc(e,'Door surround',[w/2,-d+1.25,18],10,0.75,metal)
          appliance_disc(e,'Door glass',[w/2,-d+0.5,18],8.8,0.5,glass)
        end
      end
      def appliance_disc(entities,name,center,radius,depth,mat)
        group=entities.add_group;group.name=name
        edges=group.entities.add_circle(center,Geom::Vector3d.new(0,-1,0),radius,48)
        face=group.entities.add_face(edges);face.reverse! if face.normal.y>0;face.pushpull(depth)
        group.material=mat;group
      end
      def build_upper(c,doc,g=nil)
        g||=@model.entities.add_group;g.name="Laundry / Upper / #{c['width']} in"
        @store.stamp(g,doc,c['id']);geom=Cabinetry::Geometry;e=g.entities
        w=c['width'];h=c['height'];d=c['depth'];t=0.75
        mat=material(c['finish'],finish_palette.fetch(c['finish']))
        [[0,'Left side'],[w-t,'Right side']].each{|x,name|geom.box(e,name,x,-d+t,0,t,d-t,h,mat)}
        geom.box(e,'Back',t,-0.5,0,w-2*t,0.5,h,mat)
        [0,h-t].each{|z|geom.box(e,z==0 ? 'Bottom' : 'Top',t,-d+t,z,w-2*t,d-1.25,t,mat)}
        count=c['shelves']
        count.times{|i|z=t+(h-2*t)*(i+1)/(count+1.0)-t/2;geom.box(e,"Shelf #{i+1}",t,-d+1,z,w-2*t,d-1.5,t,mat)}
        n=c['front']=='double' ? 2 : 1;fw=(w-0.25-(n-1)*0.125)/n
        n.times do |i|
          x=0.125+i*(fw+0.125);geom.front(e,x,0.0625,fw,h-0.125,d,c['style'],mat)
          next if c['handle']=='none'
          metal=material(c['handle'],finish_palette.fetch(c['handle']));hx=n==2 && i==1 ? x+1 : x+fw-1.32
          geom.box(e,'Upper pull',hx,-d-1,2,0.32,0.32,5,metal)
          [2.35,6.35].each{|z|geom.box(e,'Upper pull mount',hx,-d-0.68,z,0.3,0.68,0.3,metal)}
        end
        g.transformation=transform_for(c);g
      end
    end
  end
end

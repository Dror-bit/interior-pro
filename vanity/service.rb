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
    class Service
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
      def execute(commands,revision,transparent:false)
        raise 'Vanity is disabled' unless USE_VANITY
        raise 'Exit component editing first' if @model.active_path
        source=document
        candidate=Cabinetry.plan(source,commands,expected_revision:revision,validator:Domain.method(:validate))
        before=source['cabinets'].to_h { |c|[c['id'],c] }
        rebuilding=candidate['cabinets'].select do |c|
          previous=before[c['id']]
          !previous || previous.reject { |k,_|k=='position' }!=c.reject { |k,_|k=='position' }
        end
        rebuilding.select { |c|c['product_id']=='gallery' }.each do |c|
          a=@gallery.entry(c['asset_id'])
          raise ArgumentError,'Imported cabinets keep their original dimensions' unless a['dimensions'].zip(%w[width depth height]).all? { |n,k|(n-c[k]).abs<1e-6 }
        end
        return source if candidate==source
        prepare_assets(candidate.merge('cabinets'=>rebuilding)) unless transparent
        @busy=true
        @model.start_operation('Vanity: edit',true,false,transparent)
        begin
          @store.write(source,expected_revision:nil) unless @store.read(domain:'vanity',assembly_id:@assembly_id)
          @store.write(candidate,expected_revision:revision)
          old=source['cabinets'].to_h { |c|[c['id'],c] };now=candidate['cabinets'].to_h { |c|[c['id'],c] }
          (old.keys|now.keys).each do |id|
            next if old[id]==now[id]
            owned=groups.select { |g|g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id')==id }
            if old[id] && now[id] && old[id].reject { |k,_|k=='position' }==now[id].reject { |k,_|k=='position' } && owned.length==1
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
      # Materials persist in SketchUp's palette independently of cabinet Undo.
      # Prepare them before the document/geometry transaction, so deferred
      # material observers do not insert a Properties step after undoing a cabinet.
      def prepare_assets(doc)
        palette={'white'=>'#F5F5F0','ivory'=>'#E8E4D9','gray'=>'#969C9B','brass'=>'#B39456','black'=>'#242729'}
        assets=doc['cabinets'].select { |c|c['product_id']=='gallery' }.map { |c|c['asset_id'] }.uniq
        reference=finish_definition
        faces=reference ? reference.entities.grep(Sketchup::Face) : []
        needed=palette.any? do |key,color|
          face=faces.find { |f|f.get_attribute('InteriorPro::VanityAssets','finish')==key }
          !face || !face.material || !face.material.valid? || face.material.color.to_a!=Sketchup::Color.new(color).to_a
        end
        needed||=assets.any? { |id|!@definitions || !@definitions[id] || !@definitions[id].valid? }
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
          assets.each do |id|
            next if @definitions[id] && @definitions[id].valid?
            before=@model.materials.to_a;@definitions[id]=@gallery.definition(@model,id)
            if defined?(InteriorPro::MaterialIds)
              (@model.materials.to_a-before).each { |mat|InteriorPro::MaterialIds.ensure_id!(mat,@model) }
            end
          end
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
        return if @busy || !USE_VANITY
        reconcile_native
      end
      def reconcile_native
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
        mat.color=desired unless mat.color.to_a==desired.to_a
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
        mat=material(c['finish'],{'white'=>'#F5F5F0','ivory'=>'#E8E4D9','gray'=>'#969C9B'}.fetch(c['finish']))
        box=lambda { |name,x,y,z,bw,bd,bh,m=mat|geo.box(e,name,x,y,z,bw,bd,bh,m) }
        [0,w-t].each { |x|box.call('Side',x,-d+t,b,t,d-t,h-b) }
        if c['product_id']=='vanity'
          box.call('Bottom',t,-d+t,b,w-2*t,d-t,t)
          box.call('Back lower rail',t,-t,b+t,w-2*t,t,3)
          box.call('Back upper rail',t,-t,h-3,w-2*t,t,3)
          # Open top for later verified basin/cutout adapter. No fake sink geometry.
          c['basins'].times do |i|
            bay=w/c['basins'];fw=(bay-0.375)/2
            [0,1].each { |j|front(e,geo,c,mat,i*bay+0.125+j*(fw+0.125),b+0.0625,fw,h-b-0.125,d) }
          end
        else
          box.call('Makeup top',0,-d,h-t,w,d,t)
          if c['drawer']
            dz=h-t-5
            front(e,geo,c,mat,0.125,dz,w-0.25,4.875,d)
            box.call('Drawer bottom',1,-d+1.5,dz+0.5,w-2,d-2,0.5)
            [1,w-1.5].each { |x|box.call('Drawer side',x,-d+1.5,dz+1,0.5,d-2,3) }
            box.call('Drawer back',1.5,-1,dz+1,w-3,0.5,3)
          end
        end
        if c['legs']
          [1,w-2.5].each { |x|[-d+1.5,-3].each { |y|box.call('Leg',x,y,0,1.5,1.5,b) } }
        end
        g
      end
      def front(e,geo,c,mat,x,z,w,h,d)
        geo.front(e,x,z,w,h,d,c['style'],mat)
        return if c['handle']=='none'
        metal=material(c['handle'],c['handle']=='brass' ? '#B39456' : '#242729')
        geo.box(e,'Pull',x+w/2-2,-d-0.75,z+h/2-0.125,4,0.75,0.25,metal)
      end
    end
  end
end

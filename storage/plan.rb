require_relative 'session'
module InteriorPro
  module Storage
    remove_const(:USE_STORAGE_2D) if const_defined?(:USE_STORAGE_2D,false)
    USE_STORAGE_2D=true
    module Plan
      module_function
      def payload(model,level)
        rows=[]
        dict=model.attribute_dictionary(Cabinetry::ModelStore::DICTIONARY,false)
        (dict ? dict.keys : []).each do |key|
          domain,id=key.split(':',2)
          next unless Cabinetry.domains_for_tool('storage').include?(domain)
          next if domain=='wardrobe' && !Storage::USE_WARDROBE_PRODUCTS
          doc=Cabinetry::ModelStore.new(model).read(domain:domain,assembly_id:id)
          next unless doc.fetch('settings',{}).fetch('level',1).to_i==level.to_i
          doc['cabinets'].each do |c|
            p=c['position'];a=p['angle']*Math::PI/180;cs=Math.cos(a);sn=Math.sin(a)
            polygon=[[0,0],[c['width'],0],[c['width'],-c['depth']],[0,-c['depth']]].map { |x,y|[p['x']+x*cs-y*sn,p['y']+x*sn+y*cs] }
            row={'domain'=>domain,'assembly_id'=>id,'revision'=>doc['revision'],'id'=>c['id'],'polygon'=>polygon,'cabinet'=>c}
            if domain=='laundry' && Laundry::Appliances.appliance?(c)
              row['clearance']=Laundry::Domain.footprint(Laundry::Appliances.envelope(c))
            end
            rows<<row
          end
        end
        {'cabinets'=>rows,'armed'=>@armed}
      end
      def push(dialog)
        return unless Storage::USE_STORAGE_2D
        model=Sketchup.active_model
        level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level : 1
        # execute_script calls made while HtmlDialog is loading may be dropped.
        # The script is idempotent; retry at each host refresh, including ready.
        dialog.execute_script(File.read(File.join(__dir__,'plan.js')))
        dialog.execute_script("window.StoragePlan.load(#{JSON.generate(payload(model,level))})")
      rescue StandardError=>e
        dialog.execute_script('if(window.StoragePlan)window.StoragePlan.load({cabinets:[]})') rescue nil
        Storage.report_error(e.message)
      end
      def refresh
        dialog=InteriorPro::PlanEditor.instance_variable_get(:@dialog) if defined?(InteriorPro::PlanEditor)
        push(dialog) if dialog && dialog.visible?
      end
      def open
        raise 'Storage 2D is disabled' unless Storage::USE_STORAGE_2D
        raise 'Close the group editing context first' if Sketchup.active_model.active_path
        dialog=InteriorPro::PlanEditor.instance_variable_get(:@dialog)
        dialog && dialog.visible? ? dialog.bring_to_front : InteriorPro::PlanEditor.show
        refresh
      end
      def arm(cabinet,service,revision,new_record)
        level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level : 1
        raise 'Storage floor placement currently supports Level 1 only' unless level.to_i==1
        @armed={'domain'=>service.domain_name,'assembly_id'=>service.assembly_id,'revision'=>revision,'id'=>cabinet['id'],'cabinet'=>cabinet,'new_record'=>new_record}
        @armed_model=service.model
        open
      rescue StandardError
        @armed=nil;@armed_model=nil;raise
      end
      def apply(model,p)
        raise 'Close the group editing context first' if model.active_path
        service=Storage.service_for(model,p.fetch('domain'),p.fetch('assembly_id'))
        doc=service.document
        raise ArgumentError,'Design changed; refresh first' unless p['revision']==doc['revision']
        level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level : 1
        raise 'Design is on another level; refresh first' unless doc.fetch('settings',{}).fetch('level',1).to_i==level.to_i
        case p.fetch('action')
        when 'edit'
          group=service.groups.find { |g|g.get_attribute(Cabinetry::ModelStore::DICTIONARY,'cabinet_id')==p['id'] }
          raise 'Cabinet not found' unless group
          Storage.open(group);return false
        when 'remove'
          command={'type'=>'remove','id'=>p.fetch('id')}
        when 'move','place'
          x=Cabinetry.number!(p.fetch('x'));y=Cabinetry.number!(p.fetch('y'))
          if p['action']=='place'
            raise 'Placement expired; choose Place in 2D again' unless @armed && @armed_model.equal?(model) && %w[domain assembly_id revision id].all? { |k|p[k]==@armed[k] }
            c=Cabinetry.copy(@armed['cabinet']);c['position']=c['position'].merge('x'=>x,'y'=>y)
            command=@armed['new_record'] ? {'type'=>'add','cabinet'=>c} : {'type'=>'update','id'=>c['id'],'changes'=>{'position'=>c['position']}}
          else
            c=doc['cabinets'].find { |cab|cab['id']==p['id'] };raise 'Cabinet not found' unless c
            command={'type'=>'update','id'=>c['id'],'changes'=>{'position'=>c['position'].merge('x'=>x,'y'=>y)}}
          end
        else
          raise 'Unknown Storage 2D action'
        end
        result=service.execute([command],p['revision'])
        if p['action']=='place'
          @armed=nil;@armed_model=nil
        end
        result['revision']!=doc['revision']
      end
      def bind(dialog)
        return if dialog.instance_variable_get(:@storage_callbacks_bound)
        dialog.instance_variable_set(:@storage_callbacks_bound,true)
        bound_model=Sketchup.active_model
        dialog.add_action_callback('storage_plan') do |_,raw|
          begin
            raise 'Reopen the house plan in the active model' unless Sketchup.active_model.equal?(bound_model)
            p=JSON.parse(raw)
            if p['action']=='cancel'
              @armed=nil;@armed_model=nil
            else
              changed=apply(bound_model,p)
              dialog.execute_script("histModel('storage')") if changed
            end
            dialog.execute_script('window.StoragePlan.result("")')
          rescue StandardError=>e
            dialog.execute_script("window.StoragePlan.result(#{JSON.generate(e.message)})")
          ensure
            refresh;Storage.refresh
          end
        end
      end
      module EditorBridge
        def build_html
          html=super
          return html unless Storage::USE_STORAGE_2D
          marker='drawRooms();'
          raise 'Storage 2D canvas integration marker changed' unless html.scan(marker).length==1
          html.sub(marker,marker+' if(window.StoragePlan)window.StoragePlan.draw();')
        end
        def show
          result=super
          if Storage::USE_STORAGE_2D
            dialog=instance_variable_get(:@dialog)
            Plan.push(dialog)
          end
          result
        end
        def push_walls(dialog)
          result=super
          Plan.push(dialog) if Storage::USE_STORAGE_2D
          result
        end
      end
      # HtmlDialog snapshots callback names when its document is loaded.
      # Bind only the existing house editor, immediately after construction.
      module DialogFactory
        def new(*args)
          options=args.first
          dialog=super
          if Storage::USE_STORAGE_2D && options.is_a?(Hash) && options[:preferences_key]=='InteriorPro_PlanEditor'
            Plan.bind(dialog)
          end
          dialog
        end
      end
      def install
        return unless defined?(InteriorPro::PlanEditor)
        target=InteriorPro::PlanEditor.singleton_class
        target.prepend(EditorBridge) unless target.ancestors.include?(EditorBridge)
        factory=UI::HtmlDialog.singleton_class if defined?(UI::HtmlDialog)
        factory.prepend(DialogFactory) if factory && !factory.ancestors.include?(DialogFactory)
      end
    end
  end
end
InteriorPro::Storage::Plan.install

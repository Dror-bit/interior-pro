# House drawing adapter. Cabinet edits use the existing Kitchen engine.
# No plan_draft writes or replacement host keyboard/Undo handlers.
require_relative 'kitchen_document'
require_relative 'kitchen_spatial'
require 'digest'
require 'base64'
require_relative 'kitchen_appliance_surround'

module InteriorPro
  module KitchenPlan
    USE_KITCHEN_IN_EDITOR = true unless const_defined?(:USE_KITCHEN_IN_EDITOR, false)

    def self.payload(raw, level)
      return {'cabinets'=>[]} if raw.nil?
      doc=KitchenLab::Document.read(raw)
      settings=doc['settings'];pose=KitchenLab::Spatial.pose(settings)
      rows=pose['level'].to_i==level.to_i ? doc['cabinets'].map do |cabinet|
        points=KitchenLab::Spatial.polygon(cabinet,settings)
        raise 'Non-finite kitchen coordinates' unless points.flatten.all? { |n| n.is_a?(Numeric) && n.finite? }
        display=cabinet.dup
        if cabinet['appliance'] && defined?(KitchenLab::ApplianceCatalog)
          display['appliance_parts']=KitchenLab::ApplianceCatalog.parts(cabinet)
        end
        {'id'=>cabinet['id'],'polygon'=>points,'cabinet'=>display,
         'basis'=>[[0,0],[1,0],[0,-1]].map { |x,y| KitchenLab::Spatial.cabinet_point(cabinet,x,y,settings) },'level'=>pose['level'],
         'base_z'=>pose['z']+cabinet['z'],'height'=>cabinet['height']}
      end : []
      {'revision'=>doc['revision'],'cabinets'=>rows}
    end

    # Kitchen-only enrichment: keep the host's 2D opening list unchanged.
    def self.walls_payload
      entities=Sketchup.active_model.entities.select { |e| e.respond_to?(:transformation) }
      InteriorPro::PlanEditor.walls_payload.map do |wall|
        entity=entities.find { |e| e.get_attribute('InteriorPro','id').to_s==wall['id'] }
        next wall unless entity
        openings=InteriorPro::WallTool.read_door_openings(entity).map do |o|
          bottom=o.fetch(:floor_offset,0).to_f
          top=bottom+o[:height].to_f+o.fetch(:arch_rise,0).to_f
          zs=[bottom,top].map { |z| Geom::Point3d.new(0,0,z).transform(entity.transformation).z.to_f }
          [o[:t].round(3),o[:width].round(3),zs.min,zs.max,bottom>0 ? 'window' : 'door']
        end
        wall.merge('kitchen_openings'=>openings)
      end
    end

    def self.push(dlg)
      rows=USE_KITCHEN_IN_EDITOR ? payload(Sketchup.active_model.get_attribute('KitchenLab','document'),
        defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level : 1) : {'cabinets'=>[]}
      if USE_KITCHEN_IN_EDITOR
        host_walls=walls_payload
        rows['walls']=host_walls
        rows['wall_token']=Digest::SHA256.hexdigest(JSON.generate(host_walls))
        unless dlg.instance_variable_get(:@kitchen_scripts_loaded)
          scripts=%w[kitchen_plan.js kitchen_workspace.js].map { |name| File.read(File.join(__dir__,name)) }
          symbols=File.read(File.join(__dir__,'pantry_layout.js'))+File.read(File.join(__dir__,'cabinet_fronts.js'))+File.read(File.join(__dir__,'kitchen_canvas_symbols.js'))
          scripts << '(function(){'+symbols+'})();'
          %w[kitchen_sidebar.js kitchen_house_selection.js kitchen_house_placement.js kitchen_house_drag.js kitchen_house_insert.js kitchen_house_appliances.js kitchen_appliance_surround.js].each do |name|
            scripts << File.read(File.join(__dir__,name))
          end
          dlg.execute_script(scripts.join("\n"))
          dlg.instance_variable_set(:@kitchen_scripts_loaded,true)
        end
      end
      dlg.execute_script("if(window.KP)window.KP.load(#{JSON.generate(rows)});")
    rescue StandardError => error
      # Stale cabinets must disappear if loading fails; wall refresh survives.
      dlg.execute_script('if(window.KP)window.KP.load({cabinets:[]});') rescue nil
      puts "[KitchenPlan] #{error.message}"
    end

    # House drawing integration hooks; other Interior Pro workspaces stay unchanged.
    module EditorPreview
      def show
        @kitchen_disabled=!InteriorPro::KitchenPlan::USE_KITCHEN_IN_EDITOR
        unless @kitchen_disabled
          begin
            InteriorPro::KitchenPlan.bind_active_model!
          rescue StandardError=>error
            @kitchen_disabled=true
            puts "[KitchenPlan] Kitchen disabled for this window: #{error.message}"
          end
        end
        result=super
        return result if @kitchen_disabled
        dlg=instance_variable_get(:@dialog)
        InteriorPro::KitchenPlan.bind_catalog(dlg)
        InteriorPro::KitchenPlan.bind_drag(dlg)
        InteriorPro::KitchenPlan.bind_surround(dlg)
        dlg.add_action_callback('kitchen_edit_cabinet') do |_,id|
          begin
            InteriorPro::KitchenPlan.edit_cabinet(id.to_s)
          rescue StandardError=>error
            UI.messagebox(error.message)
          end
        end
        result
      end

      def build_html
        html=super
        return html if @kitchen_disabled || !InteriorPro::KitchenPlan::USE_KITCHEN_IN_EDITOR
        marker='drawRooms();'
        unless html.scan(marker).length==1
          @kitchen_disabled=true
          puts '[KitchenPlan] Kitchen disabled: expected one drawRooms() marker in the house editor.'
          return html
        end
        html.sub(marker,marker+' if(window.KP)window.KP.draw();')
      end

      def push_walls(dlg)
        result=super
        InteriorPro::KitchenPlan.push(dlg) unless @kitchen_disabled
        result
      end
    end

    def self.install_preview!
      raise 'Interior Pro drawing editor is not loaded' unless defined?(InteriorPro::PlanEditor)
      target=InteriorPro::PlanEditor.singleton_class
      target.prepend(EditorPreview) unless target.ancestors.include?(EditorPreview)
    end

    def self.edit_cabinet(id)
      raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
      KitchenLab.guard!
      raise 'Cabinet no longer exists' unless KitchenLab.document['cabinets'].any? { |c| c['id']==id }
      KitchenLab.instance_variable_set(:@hosted_cabinet_id,id)
      KitchenLab.show
      KitchenLab.publish
    end

    def self.open_catalog
      raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
      KitchenLab.guard!
      existing=KitchenLab.instance_variable_get(:@dialog)
      KitchenLab.instance_variable_set(:@hosted_catalog_ids,KitchenLab.document['cabinets'].map { |c| c['id'] })
      if existing && existing.visible?
        # Do not publish here: refreshing the form would overwrite its draft.
        existing.execute_script(File.read(File.join(__dir__,'kitchen_hosted_editor.js'))+File.read(File.join(__dir__,'kitchen_clean_notes.js')))
        existing.execute_script('window.openHostedCatalog();')
        existing.bring_to_front
        return
      end
      KitchenLab.instance_variable_set(:@hosted_cabinet_id,nil)
      KitchenLab.show
      KitchenLab.publish
    end

    def self.bind_catalog(dlg)
      dlg.add_action_callback('kitchen_surfaces') do |_,focus|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab::CountertopMaterials.show_settings(focus)
        rescue StandardError=>e
          dlg.execute_script("window.alert(#{JSON.generate(e.message)})")
        end
      end
      dlg.add_action_callback('kitchen_faucet_gallery') do |_,id|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab.guard!
          selected=KitchenLab.document['cabinets'].find { |c|c['id']==id.to_s }
          eligible=KitchenLab.document['cabinets'].select { |c|c['kind']=='sink' || c['kind']=='oven' || c.dig('appliance','category')=='cooktop' }
          unless eligible.any? { |c|c['id']==id.to_s }
            rows=eligible.each_with_index.map do |c,i|
              name=c.dig('appliance','model') || c.dig('sink','model') || (c['kind']=='sink' ? 'Sink' : 'Range / cooktop')
              {'id'=>c['id'],'label'=>"#{i+1}. #{name} · #{c['width']}\" · #{c['kind']=='sink' ? 'Faucet' : 'Pot filler'}"}
            end
            dlg.execute_script("window.KitchenHouseAppliances.accessoryTargets(#{JSON.generate(rows)});")
            next
          end
          KitchenLab.instance_variable_set(:@open_accessory_gallery,true)
          edit_cabinet(id.to_s)
        rescue StandardError=>error
          KitchenLab.instance_variable_set(:@open_accessory_gallery,nil)
          dlg.execute_script("window.KitchenHouseAppliances.fail(#{JSON.generate(error.message)});")
        end
      end
      dlg.add_action_callback('kitchen_project_handles') do |_,request|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab.guard!
          # Existing dialogs expose this bridge even before newly added callbacks reload.
          if %w[surfaces:countertop surfaces:backsplash].include?(request.to_s)
            KitchenLab::CountertopMaterials.show_settings(request.split(':').last)
            next
          end
          KitchenLab.instance_variable_set(:@hosted_cabinet_id,nil)
          KitchenLab.instance_variable_set(:@hosted_catalog_ids,nil)
          KitchenLab.instance_variable_set(:@hosted_project_handles,true)
          KitchenLab.show
          KitchenLab.publish
        rescue StandardError=>error
          dlg.execute_script("window.alert(#{JSON.generate(error.message)});")
        end
      end
      dlg.add_action_callback('kitchen_appliance_library') do |_,category|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          products=KitchenLab::ApplianceCatalog.products+KitchenLab::SinkCatalog.products
          products=products.reject { |p| products.any? { |q| q['id']=='thermador-custom-'+p['id'].sub(/^thermador-/,'') } }
          products=products.select { |p| p['category']==category.to_s }.sort_by { |p| [p['reference_image_path'] ? 0 : 1,p['brand'],p['model']] }
          cards=products.map do |p|
            card=p.slice('id','brand','category','model','name','dimensions','reference_image_path','sku','automatic_cutout_available','automatic_cutout')
            relative=p['image_path'].to_s
            file=File.expand_path(relative,__dir__)
            if file.start_with?(File.expand_path('assets/appliances',__dir__)+File::SEPARATOR) && File.file?(file)
              mime={'.png'=>'image/png','.jpg'=>'image/jpeg','.jpeg'=>'image/jpeg','.webp'=>'image/webp'}[File.extname(file).downcase]
              card['image']="data:#{mime};base64,#{Base64.strict_encode64(File.binread(file))}" if mime
            end
            card
          end
          dlg.execute_script("window.KitchenHouseAppliances.receive(#{JSON.generate(category.to_s)},#{JSON.generate(cards)});")
        rescue StandardError=>error
          dlg.execute_script("window.KitchenHouseAppliances.fail(#{JSON.generate(error.message)});")
        end
      end
      dlg.add_action_callback('kitchen_open_catalog') do |_,json|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab.guard!
          request=JSON.parse(json.to_s)
          allowed=%w[appliance_garage pullout_spice pullout_waste pullout_storage doors drawers sink wall glass_wall tall oven_tower micro_tower fridge_surround filler fridge oven dishwasher hood microwave corner_base corner_lazy corner_upper]
          product_id=request['product_id']
          raise 'Choose a cabinet from the library.' unless product_id || allowed.include?(request['kind'])
          payload={'kind'=>request['kind'],'wall'=>request.fetch('wall','A')}
          if product_id
            product=KitchenLab::SinkCatalog.include?(product_id) ? KitchenLab::SinkCatalog.find(product_id) : KitchenLab::ApplianceCatalog.find(product_id)
            payload['kind']=product['category']=='sink' ? 'sink' : KitchenLab::ApplianceCatalog::KINDS.fetch(product['category'])
            payload['product_id']=product_id
          end
          command_type=product_id ? 'create_catalog_appliance' : 'create_cabinet'
          without_cabinet=request.fetch('without_cabinet',false)
          hood_style=request.fetch('hood_style','shaker')
          raise 'Invalid cabinet option.' unless [true,false].include?(without_cabinet)
          with_surround=!without_cabinet && surround_supported?({'kind'=>payload['kind'],'appliance'=>product_id ? product : nil})
          source=KitchenLab.document
          level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level.to_i : 1
          raise 'Kitchen belongs to another floor.' unless KitchenLab::Spatial.pose(source['settings'])['level'].to_i==level
          current=walls_payload
          token=Digest::SHA256.hexdigest(JSON.generate(current))
          if request['action']=='prepare'
            if with_surround
              bundle=catalog_bundle_preview(source,payload,without_cabinet,level,hood_style)
              row=bundle['row']
            else
              candidate=catalog_preview(source,payload)
              row=self.payload(JSON.generate(KitchenLab::Document.create(source['settings'],[candidate])),level)['cabinets'].first
              bundle={'parts'=>nil}
            end
            push(dlg)
            dlg.execute_script("window.KitchenHouseInsert.begin(#{JSON.generate({'request_id'=>request['request_id'],'row'=>row,'parts'=>bundle['parts'],'without_cabinet'=>without_cabinet,'hood_style'=>hood_style,'kind'=>payload['kind'],'product_id'=>product_id,'wall'=>payload['wall'],'revision'=>source['revision'],'wall_token'=>token})});")
            dlg.execute_script('window.KitchenSidebar?.result(null);')
          elsif request['action']=='place'
            raise 'Kitchen changed. Select the cabinet again.' unless request['revision']==source['revision'] && request['wall_token']==token
            payload['overrides']={'x'=>0,'house_placement'=>request.fetch('placement')}
            payload['overrides']['width']=Float(request['width']) if request.key?('width') && !product_id
            if with_surround
              # The cursor places the enclosure's left edge; the appliance sits
              # one inch inside it (3/4 panel + 1/4 clearance on each side).
              placement=request.fetch('placement').dup
              angle=Float(placement.fetch('angle'))*Math::PI/180
              placement['x']=Float(placement.fetch('x'))+Math.cos(angle)
              placement['y']=Float(placement.fetch('y'))+Math.sin(angle)
              payload['overrides']['house_placement']=placement
              commands=catalog_commands(source,payload,without_cabinet,hood_style)
              plan=KitchenLab.command_engine.plan(source,commands,expected_revision:request['revision'])
              ids=commands.map { |c| c['payload']['id'] }
              plan['document']['cabinets'].select { |c| ids.include?(c['id']) }.each { |c| validate_house_placement!(c,source['settings'],current) }
            else
              candidate=catalog_preview(source,payload)
              validate_house_placement!(candidate,source['settings'],current)
              commands=[{'type'=>command_type,'payload'=>payload}]
            end
            KitchenLab.execute_commands({'expected_revision'=>request['revision'],'commands'=>commands},false)
            dlg.execute_script('window.KitchenHouseInsert.result(null);')
          else
            raise 'Select a cabinet, then click its position in the drawing.'
          end
        rescue StandardError=>error
          dlg.execute_script("window.KitchenHouseInsert?.result(#{JSON.generate(error.message)});")
          dlg.execute_script("window.KitchenSidebar?.result(#{JSON.generate(error.message)});")
        end
      end
    end

    # Run the same defaults/validation as creation, without writing to the model.
    def self.catalog_preview(source,payload)
      defaults={'x'=>0}
      defaults['house_placement']={'x'=>0,'y'=>0,'angle'=>0,'handedness'=>1} if %w[corner_base corner_lazy corner_upper].include?(payload['kind'])
      preview_payload=payload.merge('overrides'=>defaults.merge(payload.fetch('overrides',{})))
      empty=KitchenLab::Document.create(source['settings'],[])
      KitchenLab.command_engine.plan(empty,[{'type'=>payload['product_id'] ? 'create_catalog_appliance' : 'create_cabinet','payload'=>preview_payload}])['document']['cabinets'].first
    end

    def self.bind_drag(dlg)
      dlg.add_action_callback('kitchen_delete_cabinet') do |_,json|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab.guard!
          request=JSON.parse(json.to_s)
          source=KitchenLab.document
          level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level.to_i : 1
          raise 'Kitchen belongs to another floor.' unless KitchenLab::Spatial.pose(source['settings'])['level'].to_i==level
          raise 'Kitchen changed. Select the cabinet again.' unless request['revision']==source['revision']
          raise 'Cabinet no longer exists' unless source['cabinets'].any? { |c| c['id']==request['id'] }
          KitchenLab.execute_commands({'expected_revision'=>request['revision'],'commands'=>[{'type'=>'remove_cabinet','payload'=>{'id'=>request['id']}}]},false)
          push(dlg)
          dlg.execute_script('window.KitchenHouseDrag?.result(null);')
        rescue StandardError=>error
          push(dlg)
          dlg.execute_script("window.KitchenHouseDrag?.result(#{JSON.generate(error.message)});")
        end
      end
      dlg.add_action_callback('kitchen_move_cabinet') do |_,json|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab.guard!
          request=JSON.parse(json)
          current=walls_payload
          raise 'Walls changed. Try the move again.' unless request['wall_token']==Digest::SHA256.hexdigest(JSON.generate(current))
          source=KitchenLab.document
          level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level.to_i : 1
          raise 'Kitchen belongs to another floor.' unless KitchenLab::Spatial.pose(source['settings'])['level'].to_i==level
          raise 'Kitchen changed. Try the move again.' unless request['revision']==source['revision']
          old=source['cabinets'].find { |c| c['id']==request['id'] }
          raise 'Cabinet no longer exists' unless old
          next_cabinet=KitchenLab.validate(old.merge('house_placement'=>request.fetch('placement')),source['settings'])
          validate_house_placement!(next_cabinet,source['settings'],current)
          move_request={'expected_revision'=>request['revision'],'commands'=>[{'type'=>'update_cabinet','payload'=>{'id'=>old['id'],'changes'=>{'house_placement'=>next_cabinet['house_placement']}}}]}
          planned=KitchenLab.command_engine.plan(source,move_request['commands'],expected_revision:request['revision'])
          planned['document']['cabinets'].each do |member|
            validate_house_placement!(member,source['settings'],current) if planned['changed_ids'].include?(member['id'])
          end
          KitchenLab.execute_commands({'expected_revision'=>request['revision'],'commands'=>[{'type'=>'update_cabinet','payload'=>{'id'=>old['id'],'changes'=>{'house_placement'=>next_cabinet['house_placement']}}}]},false)
          dlg.execute_script('window.KitchenHouseDrag?.result(null);')
        rescue StandardError=>error
          push(dlg)
          dlg.execute_script("window.KitchenHouseDrag?.result(#{JSON.generate(error.message)});")
        end
      end
    end

    def self.validate_house_placement!(cabinet,settings,walls)
      polygon=KitchenLab::Spatial.polygon(cabinet,settings);p=cabinet.fetch('house_placement')
      if p['wall_id']
        wall=walls.find { |w| w['id']==p['wall_id'] }
        raise 'Host wall is unavailable on this floor.' unless wall && wall['corners']&.length==8 && wall.fetch('sag',0).abs<0.0625
        pts=wall['corners'].each_slice(2).to_a;a=pts[p['face']];b=pts[(p['face']+1)%4]
        dx=b[0]-a[0];dy=b[1]-a[1];length=Math.hypot(dx,dy)
        raise 'Cabinet does not fit this wall face.' unless length>=cabinet['width'] && p['along'].between?(cabinet['width']/2.0,length-cabinet['width']/2.0)
        back=KitchenLab::Spatial.cabinet_point(cabinet,cabinet['width']/2.0,0,settings)
        expected=[a[0]+dx*p['along']/length,a[1]+dy*p['along']/length]
        raise 'Invalid wall snap.' unless Math.hypot(back[0]-expected[0],back[1]-expected[1])<0.02

      end
      walls.each do |wall|
        next unless wall['corners']&.length==8
        other=wall['corners'].each_slice(2).to_a
        touching=other.each_index.any? do |i|
          a=other[i];b=other[(i+1)%4];dx=b[0]-a[0];dy=b[1]-a[1];len=Math.hypot(dx,dy)
          next false if len<0.001
          on_edge=polygon.select { |x,y| ((x-a[0])*dy-(y-a[1])*dx).abs/len<0.02 }
          next false if on_edge.length<2
          ts=on_edge.map { |x,y| ((x-a[0])*dx+(y-a[1])*dy)/len }
          [ts.max,len].min-[ts.min,0].max>0.01
        end
        if touching
        length_axis=Math.hypot(wall['ex']-wall['sx'],wall['ey']-wall['sy'])
        projections=polygon.map { |x,y| ((x-wall['sx'])*(wall['ex']-wall['sx'])+(y-wall['sy'])*(wall['ey']-wall['sy']))/length_axis }
        base_z=KitchenLab::Spatial.pose(settings)['z']+cabinet['z']
        openings=wall.fetch('kitchen_openings',wall['ops']||[])
        blocked=openings.find do |t,width,bottom,top|
          horizontal=[projections.max,t+width/2.0].min-[projections.min,t-width/2.0].max>0.01
          vertical=bottom.nil? || top.nil? || [base_z+cabinet['height'],top].min-[base_z,bottom].max>0.001
          horizontal && vertical
        end
        raise(blocked[4]=='window' ? 'Window is too low for this cabinet.' : 'Door opening must remain clear.') if blocked
        end
        overlap=[polygon,other].all? do |poly|
          poly.each_index.all? do |i|
            a=poly[i];b=poly[(i+1)%poly.length];dx=b[0]-a[0];dy=b[1]-a[1];len=Math.hypot(dx,dy)
            next true if len<0.000001
            axis=[-dy/len,dx/len];aa=polygon.map { |x,y| x*axis[0]+y*axis[1] };bb=other.map { |x,y| x*axis[0]+y*axis[1] }
            [aa.max,bb.max].min-[aa.min,bb.min].max>0.01
          end
        end
        raise 'Cabinet intersects a wall.' if overlap
      end
      true
    end

    module CabinetEditorBridge
      def show
        unless instance_variable_get(:@hosted_cabinet_id) || instance_variable_get(:@hosted_catalog_ids) || instance_variable_get(:@hosted_project_handles)
          chosen=CabinetPicker.selected_id
          if chosen
            instance_variable_set(:@hosted_cabinet_id,chosen)
          else
            return CabinetPicker.activate
          end
        end
        result=super
        dlg=instance_variable_get(:@dialog)
        dlg.add_action_callback('kitchen_accessory_opened') { |_,_| instance_variable_set(:@open_accessory_gallery,nil) }
        dlg.add_action_callback('hosted_close') do |_|
          instance_variable_set(:@hosted_cabinet_id,nil)
          dlg.close
        end
        dlg.set_on_closed do
          next unless instance_variable_get(:@dialog).equal?(dlg)
          instance_variable_set(:@dialog,nil)
          instance_variable_set(:@hosted_cabinet_id,nil)
          instance_variable_set(:@hosted_catalog_ids,nil)
          instance_variable_set(:@hosted_project_handles,nil)
          instance_variable_set(:@open_accessory_gallery,nil)
        end
        result
      end

      def publish(*args)
        result=super
        if instance_variable_get(:@hosted_project_handles)
          instance_variable_get(:@dialog)&.execute_script('window.KitchenHandleGallery?.openProject();')
          return result
        end
        catalog_ids=instance_variable_get(:@hosted_catalog_ids)
        if catalog_ids
          created=document['cabinets'].find { |c| !catalog_ids.include?(c['id']) }
          if created
            instance_variable_set(:@hosted_cabinet_id,created['id'])
            instance_variable_set(:@hosted_catalog_ids,nil)
          end
        end
        id=instance_variable_get(:@hosted_cabinet_id)
        dlg=instance_variable_get(:@dialog)
        if (id || catalog_ids) && dlg
          dlg.execute_script(File.read(File.join(__dir__,'kitchen_hosted_editor.js'))+File.read(File.join(__dir__,'kitchen_clean_notes.js')))
          dlg.execute_script(id ? "window.openHostedCabinet(#{JSON.generate(id)});" : 'window.openHostedCatalog();')
          if id && instance_variable_get(:@open_accessory_gallery)
            dlg.execute_script('if(window.KitchenAccessoryEditor){window.KitchenAccessoryEditor.open();if(document.getElementById("accessoryGallery")?.open)sketchup.kitchen_accessory_opened();}')
          end
        end
        result
      end

      def execute_commands(*args)
        plan=super
        host=InteriorPro::PlanEditor.instance_variable_get(:@dialog)
        if host && host.visible? && (!plan['changed_ids'].empty? || plan['settings_changed'])
          host.execute_script("histModel('kitchen');")
          InteriorPro::KitchenPlan.push(host)
        end
        plan
      end
    end

    def self.bind_active_model!
      model=Sketchup.active_model
      raise 'Close the current group before opening Kitchens.' unless model.active_path.nil?
      old=KitchenLab.instance_variable_get(:@model)
      unless old.equal?(model)
        dialog=KitchenLab.instance_variable_get(:@dialog)
        raise 'Close the cabinet editor before switching models.' if dialog && dialog.visible?
        observer=KitchenLab.instance_variable_get(:@document_observer)
        old.remove_observer(observer) if old && observer
        KitchenLab.instance_variable_set(:@document_observer,nil)
        KitchenLab.instance_variable_set(:@model,model)
        KitchenLab.observe_document!
      end
      KitchenLab.guard!
    end

    def self.install_editor!(toolbar: true)
      install_preview!
      target=KitchenLab.singleton_class
      target.prepend(CabinetEditorBridge) unless target.ancestors.include?(CabinetEditorBridge)
      return unless toolbar
      KitchenLab.guard!
      return if @toolbar
      command=UI::Command.new('Edit cabinet') do
        begin
          CabinetPicker.activate
        rescue StandardError=>error
          UI.messagebox(error.message)
        end
      end
      command.tooltip='Edit selected cabinet'
      command.small_icon=command.large_icon=File.join(__dir__,'kitchen_icon.svg')
      @toolbar=UI::Toolbar.new('Kitchen cabinet editor')
      @toolbar.add_item(command)
      @toolbar.show
    end
  end
end

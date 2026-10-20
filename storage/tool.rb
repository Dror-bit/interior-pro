require_relative 'session'
require_relative 'native_sync'
require_relative 'plan'
module InteriorPro
  module Storage
    remove_const(:USE_STORAGE_TOOL) if const_defined?(:USE_STORAGE_TOOL,false)
    # One combined entry; ConDoc was removed at the user's explicit request.
    USE_STORAGE_TOOL=true
    remove_const(:USE_STORAGE_TOOLBAR) if const_defined?(:USE_STORAGE_TOOLBAR,false)
    USE_STORAGE_TOOLBAR=true
    def self.install_toolbar(command,restore: true)
      return unless USE_STORAGE_TOOLBAR
      command.small_icon=command.large_icon=File.join(__dir__,'storage_icon.svg')
      unless @toolbar
        @toolbar=UI::Toolbar.new('Storage — Wardrobe / Laundry')
        @toolbar.add_item(command)
      end
      restore ? @toolbar.restore : @toolbar.show
    end
    class PlacementTool
      def initialize(service,cabinet,revision,new_record)
        @service=service;@cabinet=Cabinetry.copy(cabinet);@revision=revision;@new_record=new_record
        @point=Sketchup::InputPoint.new
      end
      def activate
        Sketchup.status_text='Storage: click the back-left corner on the floor. Esc cancels.'
      end
      def deactivate(view)
        Storage.placement_finished(self);view.invalidate
      end
      def onMouseMove(flags,x,y,view);@point.pick(view,x,y);view.invalidate;end
      def draw(view);@point.draw(view) if @point.valid?;end
      def onLButtonDown(flags,x,y,view)
        @point.pick(view,x,y);return unless @point.valid?
        raise 'Open Storage again in the active model' unless Sketchup.active_model.equal?(@service.model)
        p=@point.position
        @cabinet['position']=@cabinet['position'].merge('x'=>p.x.to_f,'y'=>p.y.to_f)
        command=@new_record ? {'type'=>'add','cabinet'=>@cabinet} : {'type'=>'update','id'=>@cabinet['id'],'changes'=>{'position'=>@cabinet['position']}}
        @service.execute([command],@revision)
        @service.model.select_tool(nil);Storage.refresh
      rescue StandardError=>e
        Storage.report_error(e.message)
      end
      def onCancel(reason,view);@service.model.select_tool(nil);end
    end

    def self.placement_finished(tool)
      @placement=nil if @placement.equal?(tool)
    end
    def self.cancel_placement
      @session.model.select_tool(nil) if @placement && @session
      @placement=nil
    end
    def self.report_error(message)
      @dialog.execute_script("showError(#{JSON.generate(message.to_s)})") if @dialog && @dialog.visible?
      puts "[Storage] #{message}" unless message.to_s.empty?
    end
    def self.refresh
      Plan.refresh if USE_STORAGE_2D
      return if @refresh_pending || !@dialog || !@dialog.visible? || !@session
      @refresh_pending=true
      UI.start_timer(0,false) do
        @refresh_pending=false
        if @dialog && @dialog.visible? && @session
            @dialog.execute_script("render(#{JSON.generate(@session.document)},#{JSON.generate(@selected_id)},#{JSON.generate(@session.editable?)},#{JSON.generate(product_catalog)})")
          @selected_id=nil
        end
      end
    end
    def self.product_catalog
      keys=['base'];keys<<'upper' if Laundry::USE_UPPER_PRODUCTS
      keys+=Laundry::Appliances::MODELS.keys if Laundry::USE_APPLIANCE_PRODUCTS
      keys.to_h do |key|
        template=Laundry::Domain.cabinet('template',key)
        info=Laundry::Appliances::MODELS[key]
        names={'washer'=>'Front-load washer','dryer'=>'Front-control electric dryer','washer_top'=>'Top-load washer','dryer_rear'=>'Matching electric dryer (front opening)',
          'stack'=>'Stacked front-load pair','pair_front'=>'Side-by-side front-load pair','pair_top'=>'Side-by-side top-load washer + dryer'}
        [key,{'template'=>template,'label'=>info ? "#{names.fetch(key)} · #{info['model']}" : (key=='upper' ? 'Upper cabinet' : 'Base cabinet'),'spec'=>info}]
      end
    end
    def self.action(raw)
      raise 'Open Storage again in the active model' unless @session && @session.model.equal?(Sketchup.active_model)
      p=JSON.parse(raw)
      if p['action']=='open2d'
        Plan.open;return
      end
      if p['action']=='switch'
        cancel_placement
        @session.switch(p.fetch('mode'),p['assembly']);@selected_id=nil;refresh;return
      end
      @session.check_request!(p) unless %w[undo redo].include?(p['action'])
      case p.fetch('action')
      when 'place','move','place2d','move2d'
        service=@session.service;doc=service.document
        new_record=%w[place place2d].include?(p['action'])
        if new_record
          id="s-#{SecureRandom.hex(8)}"
          c=(@session.domain=='laundry' ? @session.product_domain.cabinet(id,p.fetch('product','base')) : @session.product_domain.cabinet(id)).merge(p.fetch('values'))
          candidate=Cabinetry.copy(doc);candidate['cabinets']=[c]
          @session.product_domain.validate(Cabinetry.validate(candidate))
        else
          c=doc['cabinets'].find { |v|v['id']==p['id'] };raise 'Select a cabinet' unless c
        end
        cancel_placement
        if %w[place2d move2d].include?(p['action'])
          Plan.arm(c,service,doc['revision'],new_record)
        else
          @placement=PlacementTool.new(service,c,doc['revision'],new_record)
          service.model.select_tool(@placement)
        end
      when 'save','remove'
        command={'type'=>p['action']=='save' ? 'update' : 'remove','id'=>p.fetch('id')}
        command['changes']=p.fetch('values') if p['action']=='save'
        @session.service.execute([command],p['revision']);refresh
      when 'undo','redo'
        cancel_placement
        # Use the native API: menu actions can target a focused console/editor.
        p['action']=='undo' ? Sketchup.undo : Sketchup.redo
      else
        raise 'Unknown Storage action'
      end
      report_error('')
    rescue StandardError=>e
      report_error(e.message);refresh
    end
    def self.open(group=nil)
      return unless USE_STORAGE_TOOL
      model=Sketchup.active_model
      unless @session && @session.model.equal?(model)
        cancel_placement
        @dialog.close if @dialog
        @dialog=nil;@session=Session.new(model)
      end
      if group
        dict=Cabinetry::ModelStore::DICTIONARY
        domain=group.get_attribute(dict,'domain');assembly=group.get_attribute(dict,'assembly_id');id=group.get_attribute(dict,'cabinet_id')
        raise 'Invalid Storage selection' unless group.valid? && group.model.equal?(model) && group.get_attribute(dict,'role')=='cabinet'
        doc=Cabinetry::ModelStore.new(model).read(domain:domain,assembly_id:assembly)
        raise 'Storage cabinet has no source document' unless doc && doc['cabinets'].any? { |c|c['id']==id }
        cancel_placement;@session.switch(domain,assembly);@selected_id=id
      end
      install_observers
      @session.service.prepare_materials! if @session.editable? && !model.active_path
      unless @dialog
        @dialog=UI::HtmlDialog.new(dialog_title:'Storage — Wardrobe / Laundry',preferences_key:'InteriorProStorage',width:500,height:850,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_file(File.join(__dir__,'editor.html'))
        @dialog.add_action_callback('ready') { refresh }
        @dialog.add_action_callback('action') { |_,raw|action(raw) }
        owned_dialog=@dialog;owned_session=@session
        @dialog.set_on_closed do
          if @dialog.equal?(owned_dialog)
            cancel_placement if @session.equal?(owned_session)
            @dialog=nil;@refresh_pending=false
          end
        end
      end
      @dialog.visible? ? @dialog.bring_to_front : @dialog.show
      refresh
    rescue StandardError=>e
      report_error(e.message)
    end
  end
end

if InteriorPro::Storage::USE_STORAGE_TOOL
  InteriorPro::Storage.install_observers
  unless defined?($interior_pro_storage_command) && $interior_pro_storage_command
    $interior_pro_storage_command=UI::Command.new('Storage — Wardrobe / Laundry') { InteriorPro::Storage.open }
    $interior_pro_storage_command.tooltip='Wardrobe and laundry designs in one editor'
    UI.menu('Extensions').add_item($interior_pro_storage_command)
    UI.add_context_menu_handler do |menu|
      selected=Sketchup.active_model.selection.to_a
      g=selected.length==1 && selected.first
      if g.is_a?(Sketchup::Group) && g.get_attribute(InteriorPro::Cabinetry::ModelStore::DICTIONARY,'role')=='cabinet' && InteriorPro::Cabinetry.domains_for_tool('storage').include?(g.get_attribute(InteriorPro::Cabinetry::ModelStore::DICTIONARY,'domain'))
        menu.add_item('Edit Storage cabinet') { InteriorPro::Storage.open(g) }
      end
    end
  end
  InteriorPro::Storage.install_toolbar($interior_pro_storage_command)
end

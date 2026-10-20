require_relative 'service'
require 'securerandom'
module InteriorPro
  module Vanity
    remove_const(:USE_VANITY_MENU) if const_defined?(:USE_VANITY_MENU,false)
    USE_VANITY_MENU=true
    class Observer < Sketchup::ModelObserver
      def initialize(service=nil);@service=service;end
      def onTransactionCommit(model)
        return if @busy
        synchronize(model)
      end
      def synchronize(model)
        @busy=true
        if @service
          @service.synchronize_native
        else
          dict=model.attribute_dictionary(Cabinetry::ModelStore::DICTIONARY,false)
          (dict ? dict.keys.grep(/\Avanity:/) : []).each do |key|
            Service.new(model,key.split(':',2).last).synchronize_native
          end
        end
        Vanity.refresh
      ensure
        @busy=false
      end
      def onTransactionUndo(model);Vanity.refresh;end
      def onTransactionRedo(model);Vanity.refresh;end
    end
    class AppObserver < Sketchup::AppObserver
      def expectsStartupModelNotifications;true;end
      def onNewModel(model);Vanity.watch(model);end
      def onOpenModel(model);Vanity.watch(model,reset:true);end
    end
    def self.watch(model,reset:false)
      @watchers||={}
      model.remove_observer(@watchers.delete(model)) if reset && @watchers.key?(model)
      return if @watchers.key?(model)
      observer=Observer.new;model.add_observer(observer);@watchers[model]=observer
    end
    def self.install_observers
      return unless USE_VANITY
      watch(Sketchup.active_model)
      unless @app_observer
        @app_observer=AppObserver.new;Sketchup.add_observer(@app_observer)
      end
    end
    class Placement
      def initialize(service,cabinet,revision,new_record)
        @service=service;@cabinet=Cabinetry.copy(cabinet);@revision=revision;@new_record=new_record;@point=Sketchup::InputPoint.new
      end
      def activate;Sketchup.status_text='Vanity: click the back-left corner. Esc cancels.';end
      def onMouseMove(flags,x,y,view);@point.pick(view,x,y);view.invalidate;end
      def draw(view);@point.draw(view) if @point.valid?;end
      def onLButtonDown(flags,x,y,view)
        @point.pick(view,x,y);return unless @point.valid?
        p=@point.position;pos=@cabinet['position'].merge('x'=>p.x.to_f,'y'=>p.y.to_f)
        @cabinet['position']=pos
        cmd=@new_record ? {'type'=>'add','cabinet'=>@cabinet} : {'type'=>'update','id'=>@cabinet['id'],'changes'=>{'position'=>pos}}
        @service.execute([cmd],@revision);@service.model.select_tool(nil);Vanity.refresh
      rescue StandardError => e
        UI.messagebox(e.message)
      end
      def onCancel(reason,view);@service.model.select_tool(nil);end
    end
    def self.refresh
      return unless @dialog && @dialog.visible? && @service
      @dialog.execute_script("render(#{JSON.generate(@service.document)},#{JSON.generate(@service.gallery.entries)})")
    end
    def self.open
      raise 'Vanity is disabled' unless USE_VANITY
      if @dialog && @dialog.visible? && @service.model==Sketchup.active_model
        @dialog.bring_to_front;refresh;return
      end
      @dialog.close if @dialog
      @service=Service.new(Sketchup.active_model)
      @service.prepare_assets(@service.document)
      install_observers
      @dialog=UI::HtmlDialog.new(dialog_title:'Vanity',preferences_key:'InteriorProVanity',width:510,height:850,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__,'editor.html'))
      @dialog.add_action_callback('ready') { refresh }
      @dialog.add_action_callback('action') do |_,raw|
        begin
          raise 'Reopen Vanity in the active model' unless Sketchup.active_model==@service.model
          p=JSON.parse(raw);doc=@service.document;action=p.fetch('action')
          raise 'Design changed; refresh first' unless doc['revision']==p.fetch('revision')
          case action
          when 'place','gallery_place'
            product=action=='gallery_place' ? 'gallery' : p.fetch('product')
            raise 'Invalid product' unless %w[vanity makeup gallery].include?(product)
            c=Domain.cabinet("v-#{SecureRandom.hex(8)}",product).merge(p.fetch('values'))
            if product=='gallery'
              a=@service.gallery.entry(p.fetch('asset_id'));c['asset_id']=a['id'];c['basins']=0;c['drawer']=false
              %w[width depth height].zip(a['dimensions']).each { |k,n|c[k]=n }
              c['mount']='floor';c['legs']=false;c['position']['z']=0.0
            end
            # Validate product options before arming; the clicked placement is
            # collision-checked atomically against the full design by execute.
            test=Cabinetry.copy(doc);test['cabinets']=[c];Domain.validate(test)
            prepared=@service.prepare_assets(test)
            if prepared
              UI.start_timer(2,false) { @service.model.select_tool(Placement.new(@service,c,doc['revision'],true)) if Sketchup.active_model==@service.model }
            else
              @service.model.select_tool(Placement.new(@service,c,doc['revision'],true))
            end
          when 'save'
            @service.execute([{'type'=>'update','id'=>p.fetch('id'),'changes'=>p.fetch('values')}],doc['revision'])
          when 'move'
            c=doc['cabinets'].find { |v|v['id']==p['id'] };raise 'Select a cabinet' unless c
            @service.model.select_tool(Placement.new(@service,c,doc['revision'],false))
          when 'remove'
            @service.execute([{'type'=>'remove','id'=>p.fetch('id')}],doc['revision'])
          when 'capture'
            @service.gallery.capture(@service.model,@service.model.selection.to_a,p.fetch('name'))
          when 'undo';Sketchup.undo
          when 'redo';Sketchup.redo
          else;raise 'Unknown action'
          end
          refresh;@dialog.execute_script("showError('')")
        rescue StandardError => e
          @dialog.execute_script("showError(#{JSON.generate(e.message)})");refresh
        end
      end
      @dialog.show
    end
    # Explicit registration, coordinated separately from the shared loader.
    def self.register_menu!
      return if @command
      install_observers
      @command=UI::Command.new('Vanity') { open }
      @command.tooltip='Bathroom and makeup cabinets'
      UI.menu('Extensions').add_item(@command)
    end
  end
end

InteriorPro::Vanity.register_menu! if InteriorPro::Vanity::USE_VANITY && InteriorPro::Vanity::USE_VANITY_MENU

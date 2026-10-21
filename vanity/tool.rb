require_relative 'service'
require_relative 'plan_bridge'
require 'securerandom'
module InteriorPro
  module Vanity
    remove_const(:USE_VANITY_MENU) if const_defined?(:USE_VANITY_MENU,false)
    USE_VANITY_MENU=true
    remove_const(:USE_VANITY_TOOLBAR) if const_defined?(:USE_VANITY_TOOLBAR,false)
    USE_VANITY_TOOLBAR=false
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
        if defined?(InteriorPro::FixtureTool)
          @wall_picker=InteriorPro::FixtureTool.new({'kind'=>'vanity'})
          @wall_picker.send(:reset)
        end
      end
      def activate;Sketchup.status_text='Vanity: move to a wall or floor. Green = fits; click to place. R = rotate; Esc = cancel.';end
      def onMouseMove(flags,x,y,view)
        @point.pick(view,x,y);@preview=nil;@error=nil
        begin
          hit=@wall_picker && @wall_picker.face_point(view,x,y)
          if hit && hit[:wall] && hit[:side]
            fr=InteriorPro::TileWall.frame_for(hit[:wall],hit[:side])
            @preview=PlanBridge.on_wall(@cabinet,hit[:wall],hit[:side],fr,hit[:u])
          else
            p=@point.valid? ? @point.position : Geom.intersect_line_plane(view.pickray(x,y),[ORIGIN,Z_AXIS])
            if p
              @preview=Cabinetry.copy(@cabinet)
              @preview['position'].merge!('x'=>p.x.to_f,'y'=>p.y.to_f)
            end
          end
          if @preview
            command=@new_record ? {'type'=>'add','cabinet'=>@preview} : {'type'=>'update','id'=>@preview['id'],'changes'=>{'position'=>@preview['position']}}
            Cabinetry.plan(@service.document,[command],expected_revision:@revision,validator:Domain.method(:validate))
          end
        rescue StandardError=>e
          @error=e.message
          if !@preview && @point.valid?
            @preview=Cabinetry.copy(@cabinet);@preview['position'].merge!('x'=>@point.position.x.to_f,'y'=>@point.position.y.to_f)
          end
        end
        view.tooltip=@error || 'Click to place Vanity';view.invalidate
      end
      def ghost_points
        return [] unless @preview
        c=@preview;s=Surfaces.settings(c);top=c['height']+s['countertop_thickness']+s['backsplash_height']
        tr=@service.transform(c)
        [0,top].flat_map { |z|[[0,0,z],[c['width'],0,z],[c['width'],-c['depth']-0.5,z],[0,-c['depth']-0.5,z]].map { |p|Geom::Point3d.new(p).transform(tr) } }
      end
      def draw(view)
        pts=ghost_points;return if pts.empty?
        view.drawing_color=@error ? 'red' : 'green';view.line_width=2;view.line_stipple=''
        edges=[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
        view.draw(GL_LINES,edges.flat_map { |a,b|[pts[a],pts[b]] })
        @point.draw(view) if @point.valid?
      end
      def getExtents
        bb=Geom::BoundingBox.new;ghost_points.each { |p|bb.add(p) };bb
      end
      def onKeyDown(key,repeat,flags,view)
        return unless key==82 && repeat==1
        @cabinet['position']['angle']=(@cabinet['position']['angle']+90)%360
        @preview['position']['angle']=@cabinet['position']['angle'] if @preview
        view.invalidate
      end
      def onLButtonDown(flags,x,y,view)
        onMouseMove(flags,x,y,view);return unless @preview && !@error
        @cabinet=Cabinetry.copy(@preview);pos=@cabinet['position']
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
      if @pending_cabinet_id
        @dialog.execute_script("document.getElementById('list').value=#{JSON.generate(@pending_cabinet_id)};choose();")
        @pending_cabinet_id=nil
      end
    end
    def self.editable?(entity)
      return false unless USE_VANITY && entity.is_a?(Sketchup::Group) && entity.valid?
      dict=Cabinetry::ModelStore::DICTIONARY
      entity.get_attribute(dict,'domain')=='vanity' && entity.get_attribute(dict,'role')=='cabinet'
    end
    def self.edit_entity(entity)
      return false unless editable?(entity)
      dict=Cabinetry::ModelStore::DICTIONARY
      assembly=entity.get_attribute(dict,'assembly_id');id=entity.get_attribute(dict,'cabinet_id')
      service=Service.new(Sketchup.active_model,assembly)
      return false unless service.document['cabinets'].any? { |c|c['id']==id }
      Sketchup.active_model.select_tool(nil)
      open(cabinet_id:id,assembly_id:assembly)
      true
    end
    def self.open(cabinet_id:nil,assembly_id:'main',on_place:nil)
      raise 'Vanity is disabled' unless USE_VANITY
      @placement_handler=on_place
      @pending_cabinet_id=cabinet_id
      if @dialog && @dialog.visible? && @service.model==Sketchup.active_model && @service.assembly_id==assembly_id
        @dialog.bring_to_front;refresh;return
      end
      @dialog.close if @dialog
      @service=Service.new(Sketchup.active_model,assembly_id)
      install_observers
      @dialog=UI::HtmlDialog.new(dialog_title:'Interior Pro · Vanity',preferences_key:'InteriorProVanitySimple',width:1100,height:800,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
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
              c['front_columns']=[];c['countertop']=nil
              %w[width depth height].zip(a['dimensions']).each { |k,n|c[k]=n }
              c['mount']='floor';c['legs']=false;c['position']['z']=0.0
            end
            # Validate product options before arming; the clicked placement is
            # collision-checked atomically against the full design by execute.
            test=Cabinetry.copy(doc);test['cabinets']=[c];Domain.validate(test)
            if @placement_handler && action=='place'
              @placement_handler.call(Cabinetry.copy(c))
              @dialog.close
              next
            end
            prepared=@service.prepare_assets(test)
            if prepared
              UI.start_timer(2,false) { @service.model.select_tool(Placement.new(@service,c,doc['revision'],true)) if Sketchup.active_model==@service.model }
            else
              @service.model.select_tool(Placement.new(@service,c,doc['revision'],true))
            end
          when 'save'
            @service.execute([{'type'=>'update','id'=>p.fetch('id'),'changes'=>p.fetch('values')}],doc['revision'],refresh_geometry:true)
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
      unless @command
        install_observers
        @command=UI::Command.new('Vanity') { open }
        @command.tooltip='Vanity - Bathroom and makeup cabinets'
        @command.status_bar_text='Open Vanity to create or edit bathroom and makeup cabinets'
        UI.menu('Extensions').add_item(@command)
      end
      install_toolbar(restore: true) if USE_VANITY_TOOLBAR
      @toolbar.hide if !USE_VANITY_TOOLBAR && @toolbar
    end
    def self.install_toolbar(restore: false)
      return unless USE_VANITY && USE_VANITY_TOOLBAR && @command
      icon=File.join(__dir__,'vanity_icon.svg')
      @command.small_icon=icon
      @command.large_icon=icon
      unless @toolbar
        @toolbar=UI::Toolbar.new('Vanity')
        @toolbar.add_item(@command)
      end
      restore ? @toolbar.restore : @toolbar.show
    end
  end
end

InteriorPro::Vanity.register_menu! if InteriorPro::Vanity::USE_VANITY && InteriorPro::Vanity::USE_VANITY_MENU

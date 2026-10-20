require_relative 'service'
module InteriorPro
  module Laundry
    # Keep the pilot off until native Undo/Redo passes in a clean test instance.
    remove_const(:USE_LAUNDRY_PILOT) if const_defined?(:USE_LAUNDRY_PILOT,false)
    USE_LAUNDRY_PILOT=false
    class PlacementTool
      def initialize(service,cabinet,revision,new_record)
        @service=service;@cabinet=Cabinetry.copy(cabinet);@revision=revision;@new_record=new_record
        @point=Sketchup::InputPoint.new
      end
      def activate
        Sketchup.status_text='Laundry: click the back-left corner on the floor. Esc cancels.'
      end
      def onMouseMove(flags,x,y,view)
        @point.pick(view,x,y);view.invalidate
      end
      def draw(view)
        @point.draw(view) if @point.valid?
      end
      def onLButtonDown(flags,x,y,view)
        @point.pick(view,x,y);return unless @point.valid?
        p=@point.position
        @cabinet['position']=@cabinet['position'].merge('x'=>p.x.to_f,'y'=>p.y.to_f,'z'=>0.0)
        command=@new_record ? {'type'=>'add','cabinet'=>@cabinet} : {'type'=>'update','id'=>@cabinet['id'],'changes'=>{'position'=>@cabinet['position']}}
        @service.execute([command],@revision)
        @service.model.select_tool(nil);Laundry.refresh
      rescue StandardError => e
        UI.messagebox(e.message)
      end
      def onCancel(reason,view)
        @service.model.select_tool(nil)
      end
    end

    class UndoObserver < Sketchup::ModelObserver
      def onTransactionUndo(model);UI.start_timer(0,false) { Laundry.refresh };end
      def onTransactionRedo(model);UI.start_timer(0,false) { Laundry.refresh };end
    end

    def self.refresh
      return unless @dialog && @dialog.visible? && @service
      @dialog.execute_script("render(#{JSON.generate(@service.document)})")
    end

    def self.open
      if @dialog && @dialog.visible? && @service.model.equal?(Sketchup.active_model)
        @dialog.bring_to_front;refresh;return
      end
      @dialog.close if @dialog
      @service.model.remove_observer(@observer) if @service && @observer
      @service=Service.new(Sketchup.active_model)
      @observer=UndoObserver.new;@service.model.add_observer(@observer)
      @dialog=UI::HtmlDialog.new(dialog_title:'Laundry cabinets',preferences_key:'InteriorProLaundry',width:480,height:730,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__,'editor.html'))
      @dialog.add_action_callback('ready') { refresh }
      @dialog.add_action_callback('action') do |_,raw|
        begin
          raise 'Open Laundry again in the active model' unless @service.model.equal?(Sketchup.active_model)
          p=JSON.parse(raw);doc=@service.document
          raise 'Design changed; refresh first' unless doc['revision']==p.fetch('revision')
          case p.fetch('action')
          when 'place'
            c=Domain.cabinet("l-#{SecureRandom.hex(8)}").merge(p.fetch('values'))
            candidate=Cabinetry.copy(doc);candidate['cabinets']=[c];Domain.validate(Cabinetry.validate(candidate))
            @service.model.select_tool(PlacementTool.new(@service,c,doc['revision'],true))
          when 'move'
            c=doc['cabinets'].find { |v|v['id']==p['id'] };raise 'Select a cabinet' unless c
            @service.model.select_tool(PlacementTool.new(@service,c,doc['revision'],false))
          when 'save'
            @service.execute([{'type'=>'update','id'=>p.fetch('id'),'changes'=>p.fetch('values')}],p['revision']);refresh
          when 'remove'
            @service.execute([{'type'=>'remove','id'=>p.fetch('id')}],p['revision']);refresh
          when 'undo'
            Sketchup.send_action('editUndo:')
          when 'redo'
            Sketchup.send_action('editRedo:')
          else
            raise 'Unknown action'
          end
          @dialog.execute_script("showError('')")
        rescue StandardError => e
          @dialog.execute_script("showError(#{JSON.generate(e.message)})")
        end
      end
      @dialog.show
    end
  end
end

if InteriorPro::Laundry::USE_LAUNDRY_PILOT && !(defined?($interior_pro_laundry_command) && $interior_pro_laundry_command)
  $interior_pro_laundry_command=UI::Command.new('Laundry cabinets') { InteriorPro::Laundry.open }
  $interior_pro_laundry_command.tooltip='Place and edit laundry cabinets'
  UI.menu('Extensions').add_item($interior_pro_laundry_command)
end

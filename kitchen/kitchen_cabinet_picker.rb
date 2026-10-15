module InteriorPro
  module KitchenPlan
    module CabinetPicker
      def self.id_from_path(path)
        ids=KitchenLab.document.fetch('cabinets',[]).map { |c| c['id'] }
        path.reverse_each do |entity|
          next unless entity.respond_to?(:get_attribute)
          %w[id owner_id].each do |key|
            id=entity.get_attribute('KitchenLab',key)
            return id if ids.include?(id)
          end
        end
        nil
      end
      def self.selected_id
        model=Sketchup.active_model
        return nil unless model.selection.length==1
        id_from_path((model.active_path || [])+model.selection.to_a)
      end
      def self.activate
        KitchenPlan.bind_active_model!
        id=selected_id
        return KitchenPlan.edit_cabinet(id) if id
        Sketchup.active_model.select_tool(Tool.new)
      end
      class Tool
        def activate
          Sketchup.status_text='Choose a kitchen cabinet to edit. Esc to cancel.'
        end
        def onCancel(reason,view)
          Sketchup.active_model.select_tool(nil)
        end
        def onLButtonDown(flags,x,y,view)
          picker=view.pick_helper;picker.do_pick(x,y)
          id=nil
          picker.count.times do |i|
            id=CabinetPicker.id_from_path(picker.path_at(i));break if id
          end
          unless id
            Sketchup.status_text='Click a cabinet door, drawer or side panel.'
            return
          end
          Sketchup.active_model.select_tool(nil)
          KitchenPlan.edit_cabinet(id)
        rescue StandardError=>error
          UI.messagebox(error.message)
        end
      end
    end
  end
end

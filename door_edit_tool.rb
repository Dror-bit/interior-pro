# Interior Pro - Door Edit Tool

module InteriorPro
  class DoorEditTool

    def activate
      doors = Sketchup.active_model.selection.select { |e| InteriorPro::DoorManager.door_entity?(e) }
      if doors.any?
        InteriorPro::DoorLibraryDialog.show_for_edit(doors.first)
      else
        update_status_bar
      end
    end

    def deactivate(view)
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.count > 0 ? ph.path_at(0) : nil
      door = InteriorPro::DoorManager.find_door_in_path(path)
      InteriorPro::DoorLibraryDialog.show_for_edit(door) if door
    end

    def update_status_bar
      Sketchup.set_status_text('Click a door to edit its settings', SB_PROMPT)
    end

  end
end

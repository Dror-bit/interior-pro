# Interior Pro - Door Move Tool

module InteriorPro
  class DoorMoveTool

    def activate
      update_status_bar
    end

    def deactivate(view)
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.count > 0 ? ph.path_at(0) : nil
      door = InteriorPro::DoorManager.find_door_in_path(path)
      InteriorPro::DoorManager.show_move_dialog(door) if door
    end

    def update_status_bar
      Sketchup.set_status_text('Click a door to move it along the wall', SB_PROMPT)
    end

  end
end

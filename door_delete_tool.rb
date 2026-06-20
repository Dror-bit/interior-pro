# Interior Pro - Door Delete Tool

module InteriorPro
  class DoorDeleteTool

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
      return unless door

      if UI.messagebox('Delete this door and patch the wall opening?', MB_YESNO) == IDYES
        InteriorPro::DoorManager.delete_door(door)
      end
    end

    def update_status_bar
      Sketchup.set_status_text('Click a door to delete it', SB_PROMPT)
    end

  end
end

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
        if defined?(InteriorPro::MoldingManager)
          begin
            InteriorPro::MoldingManager.refresh!
          rescue StandardError => e
            puts "[DoorDeleteTool] molding refresh failed: #{e.message}"
          end
        end
        # The threshold has to go with the door (2026-08-15) - otherwise a
        # patch is left lying in a wall that no longer has an opening.
        if defined?(InteriorPro::FloorManager)
          begin
            InteriorPro::FloorManager.refresh_door_patches!
          rescue StandardError => e
            puts "[DoorDeleteTool] floor patch refresh failed: #{e.message}"
          end
        end
      end
    end

    def update_status_bar
      Sketchup.set_status_text('Click a door to delete it', SB_PROMPT)
    end

  end
end

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

    # Escape puts the tool down and gives him the select arrow back - line 1 of
    # the iron law in CLAUDE.md (2026-10-07). This tool has no step to cancel,
    # it only waits for a click, so before this Escape did nothing at all and
    # he stayed in it until he picked another tool.
    # reason 0 = Escape. (1 = the same tool picked again, 2 = an undo - stay.)
    def onCancel(reason, _view)
      Sketchup.active_model.select_tool(nil) if reason.to_i.zero?
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

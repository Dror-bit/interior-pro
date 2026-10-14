# Interior Pro - Wall Move Tool

module InteriorPro
  class WallMoveTool

    def activate
      update_status_bar
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
      entity = ph.best_picked

      if entity.is_a?(Sketchup::Group) && entity.get_attribute('InteriorPro', 'type') == 'wall'
        InteriorPro::UIDialogs.wall_move(entity)
      end
    end

    def update_status_bar
      Sketchup.set_status_text('Click a wall to move it', SB_PROMPT)
    end

  end
end

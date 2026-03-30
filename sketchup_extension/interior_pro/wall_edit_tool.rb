# Interior Pro - Wall Edit Tool

module InteriorPro
  class WallEditTool

    def activate
      update_status_bar
    end

    def deactivate(view)
      view.invalidate
    end

    def onLButtonDoubleClick(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      entity = ph.best_picked

      if entity.is_a?(Sketchup::Group) && entity.get_attribute('InteriorPro', 'type') == 'wall'
        InteriorPro::UIDialogs.wall_edit(entity)
      end
    end

    def update_status_bar
      Sketchup.set_status_text('Double-click a wall to edit it.', SB_PROMPT)
    end

  end
end

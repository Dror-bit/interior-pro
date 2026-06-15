# Interior Pro - Wall Move Tool

module InteriorPro
  class WallMoveTool

    def activate
      update_status_bar
    end

    def deactivate(view)
      view.invalidate
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

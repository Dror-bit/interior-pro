# Interior Pro - Wall Edit Tool

module InteriorPro
  class WallEditTool

    def activate
      walls = Sketchup.active_model.selection.select do |e|
        e.is_a?(Sketchup::Group) && e.get_attribute('InteriorPro', 'type') == 'wall'
      end
      if walls.any?
        if InteriorPro::UIDialogs.respond_to?(:wall_edit_multi)
          InteriorPro::UIDialogs.wall_edit_multi(walls)
        else
          puts "Would open multi-edit for #{walls.length} walls"
        end
      else
        update_status_bar
      end
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
      Sketchup.set_status_text('Double-click a wall to edit, or select walls first then activate this tool', SB_PROMPT)
    end

  end
end

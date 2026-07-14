# Interior Pro - Wall Edit Tool

module InteriorPro
  class WallEditTool

    def activate
      walls = Sketchup.active_model.selection.select do |e|
        e.is_a?(Sketchup::Group) && e.get_attribute('InteriorPro', 'type') == 'wall'
      end
      if walls.length == 1
        InteriorPro::UIDialogs.wall_edit(walls.first)
      elsif walls.length > 1
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

    # Single click on a wall opens the edit dialog (double-click kept for habit).
    def onLButtonDown(flags, x, y, view)
      open_edit_for_pick(view, x, y)
    end

    def onLButtonDoubleClick(flags, x, y, view)
      open_edit_for_pick(view, x, y)
    end

    def update_status_bar
      Sketchup.set_status_text('Click a wall to edit it, or select several walls first then activate this tool', SB_PROMPT)
    end

    private

    def open_edit_for_pick(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      entity = nil
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          next unless ent.get_attribute('InteriorPro', 'type') == 'wall'
          entity = ent
          break
        end
        break if entity
      end
      InteriorPro::UIDialogs.wall_edit(entity) if entity
    end

  end
end

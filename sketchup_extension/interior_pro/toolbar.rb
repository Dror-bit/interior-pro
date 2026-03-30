# Interior Pro - Toolbar and Menu

module InteriorPro
  module Toolbar
    def self.setup
      toolbar = UI::Toolbar.new('Interior Pro')

      # Wall Tool Button
      wall_cmd = UI::Command.new('Wall Tool') {
        Sketchup.active_model.select_tool(InteriorPro::WallTool.new)
      }
      wall_cmd.tooltip = 'Draw Walls'
      wall_cmd.status_bar_text = 'Click to start drawing walls'
      wall_cmd.small_icon = 'icons/wall_small.png'
      wall_cmd.large_icon = 'icons/wall_large.png'
      toolbar.add_item(wall_cmd)

      # Edit Wall Button
      edit_cmd = UI::Command.new('Edit Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallEditTool.new)
      }
      edit_cmd.tooltip = 'Edit Walls'
      edit_cmd.status_bar_text = 'Double-click a wall to edit it'
      edit_cmd.small_icon = 'icons/edit_small.png'
      edit_cmd.large_icon = 'icons/edit_large.png'
      toolbar.add_item(edit_cmd)

      toolbar.restore
    end
  end

  module Menu
    def self.setup
      menu = UI.menu('Extensions').add_submenu('Interior Pro')

      menu.add_item('Wall Tool') {
        Sketchup.active_model.select_tool(InteriorPro::WallTool.new)
      }

      menu.add_item('Edit Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallEditTool.new)
      }

      menu.add_separator

      menu.add_item('Wall Settings') {
        InteriorPro::UIDialogs.wall_settings_standalone
      }
    end
  end
end

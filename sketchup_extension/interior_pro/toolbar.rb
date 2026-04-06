# Interior Pro - Toolbar and Menu

module InteriorPro
  module Toolbar
    def self.setup
      toolbar = UI::Toolbar.new('Interior Pro')

      # Wall Tool Button
      wall_cmd = UI::Command.new('Wall Tool') {
        tool = InteriorPro::WallTool.new
        InteriorPro::WallLibraryDialog.show(tool)
      }
      wall_cmd.tooltip = 'Draw Walls - Opens Wall Library'
      wall_cmd.status_bar_text = 'Select wall type and start drawing'
      wall_cmd.small_icon = File.join(__dir__, 'icons', 'wall_tool_16.png')
      wall_cmd.large_icon = File.join(__dir__, 'icons', 'wall_tool_24.png')
      toolbar.add_item(wall_cmd)

      # Edit Wall Button
      edit_cmd = UI::Command.new('Edit Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallEditTool.new)
      }
      edit_cmd.tooltip = 'Edit Wall - Double-click a wall to edit'
      edit_cmd.status_bar_text = 'Double-click a wall to edit it'
      edit_cmd.small_icon = File.join(__dir__, 'icons', 'edit_wall_16.png')
      edit_cmd.large_icon = File.join(__dir__, 'icons', 'edit_wall_24.png')
      toolbar.add_item(edit_cmd)

      toolbar.restore
    end
  end

  module Menu
    def self.setup
      menu = UI.menu('Extensions').add_submenu('Interior Pro')

      menu.add_item('Wall Tool') {
        tool = InteriorPro::WallTool.new
        InteriorPro::WallLibraryDialog.show(tool)
      }

      menu.add_item('Edit Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallEditTool.new)
      }
    end
  end
end

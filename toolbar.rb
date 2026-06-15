# Interior Pro - Toolbar and Menu

require_relative 'ui_dialogs.rb'
require_relative 'wall_tool.rb'
require_relative 'wall_edit_tool.rb'
require_relative 'wall_move_tool.rb'
require_relative 'wall_merge_tool.rb'
require_relative 'wall_library_dialog.rb'
require_relative 'window_tool.rb'
require_relative 'window_library_dialog.rb'

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
      wall_cmd.small_icon = File.join(__dir__, 'icons', 'wall_tool.svg')
      wall_cmd.large_icon = File.join(__dir__, 'icons', 'wall_tool.svg')
      toolbar.add_item(wall_cmd)

      # Edit Wall Button
      edit_cmd = UI::Command.new('Edit Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallEditTool.new)
      }
      edit_cmd.tooltip = 'Edit Wall - Double-click a wall to edit'
      edit_cmd.status_bar_text = 'Double-click a wall to edit it'
      edit_cmd.small_icon = File.join(__dir__, 'icons', 'edit_wall.svg')
      edit_cmd.large_icon = File.join(__dir__, 'icons', 'edit_wall.svg')
      toolbar.add_item(edit_cmd)

      # Move Wall Button
      move_cmd = UI::Command.new('Move Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMoveTool.new)
      }
      move_cmd.tooltip = 'Move Wall'
      move_cmd.status_bar_text = 'Move a wall - connected walls will stretch'
      move_cmd.small_icon = File.join(__dir__, 'icons', 'move_wall.svg')
      move_cmd.large_icon = File.join(__dir__, 'icons', 'move_wall.svg')
      toolbar.add_item(move_cmd)

      # Merge Wall Button
      merge_cmd = UI::Command.new('Merge Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMergeTool.new)
      }
      merge_cmd.tooltip = 'Merge Wall'
      merge_cmd.status_bar_text = 'Connect a new wall to an existing wall'
      merge_cmd.small_icon = File.join(__dir__, 'icons', 'merge_wall.svg')
      merge_cmd.large_icon = File.join(__dir__, 'icons', 'merge_wall.svg')
      toolbar.add_item(merge_cmd)

      # Window Tool Button
      window_cmd = UI::Command.new('Window Tool') {
        tool = InteriorPro::WindowTool.new
        InteriorPro::WindowLibraryDialog.show(tool)
      }
      window_cmd.tooltip = 'Place Window - Opens Window Library'
      window_cmd.status_bar_text = 'Configure window and click on a wall to place it'
      window_cmd.small_icon = File.join(__dir__, 'icons', 'window_tool.svg')
      window_cmd.large_icon = File.join(__dir__, 'icons', 'window_tool.svg')
      toolbar.add_item(window_cmd)

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

      menu.add_item('Move Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMoveTool.new)
      }

      menu.add_item('Merge Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMergeTool.new)
      }

      menu.add_item('Window Tool') {
        tool = InteriorPro::WindowTool.new
        InteriorPro::WindowLibraryDialog.show(tool)
      }
    end
  end
end

# Interior Pro - Toolbar and Menu

require_relative 'ui_dialogs.rb'
require_relative 'wall_tool.rb'
require_relative 'wall_edit_tool.rb'
require_relative 'wall_move_tool.rb'
require_relative 'wall_merge_tool.rb'
require_relative 'wall_library_dialog.rb'
require_relative 'window_tool.rb'
require_relative 'window_library_dialog.rb'
require_relative 'door_tool.rb'
require_relative 'door_library_dialog.rb'
require_relative 'door_manager.rb'
require_relative 'door_edit_tool.rb'
require_relative 'door_move_tool.rb'
require_relative 'door_delete_tool.rb'

module InteriorPro
  module Toolbar
    LEGACY_TOOLBAR_NAME = 'Interior Pro' unless const_defined?(:LEGACY_TOOLBAR_NAME, false)
    CLEAN_TOOLBAR_NAME = 'Interior Pro Tools' unless const_defined?(:CLEAN_TOOLBAR_NAME, false)
    TOOLBAR_ITEM_COUNT = 9 unless const_defined?(:TOOLBAR_ITEM_COUNT, false)

    # SketchUp cannot remove toolbar items via the API — hide bloated legacy bar and use a clean one.
    def self.resolve_toolbar
      legacy = UI::Toolbar.new(LEGACY_TOOLBAR_NAME)
      if legacy.length > TOOLBAR_ITEM_COUNT
        legacy.hide
        return UI::Toolbar.new(CLEAN_TOOLBAR_NAME)
      end
      legacy
    end

    def self.bloated_toolbars?
      UI::Toolbar.new(LEGACY_TOOLBAR_NAME).length > TOOLBAR_ITEM_COUNT ||
        UI::Toolbar.new(CLEAN_TOOLBAR_NAME).length > TOOLBAR_ITEM_COUNT
    end

    def self.setup
      return if @setup_done
      @setup_done = true

      toolbar = resolve_toolbar
      return if toolbar.length >= TOOLBAR_ITEM_COUNT

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

      # Door Tool Button — activate tool first (viewport focus), then modeless settings panel.
      door_cmd = UI::Command.new('Door Tool') {
        model = Sketchup.active_model
        active = model.tools.active_tool
        tool = active.is_a?(InteriorPro::DoorTool) ? active : InteriorPro::DoorTool.new
        model.select_tool(tool)
        InteriorPro::DoorLibraryDialog.show(tool)
      }
      door_cmd.tooltip = 'Place Door - Opens Door Library'
      door_cmd.status_bar_text = 'Configure door and click on a wall to place it'
      door_cmd.small_icon = File.join(__dir__, 'icons', 'door_tool.svg')
      door_cmd.large_icon = File.join(__dir__, 'icons', 'door_tool.svg')
      toolbar.add_item(door_cmd)

      door_edit_cmd = UI::Command.new('Edit Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorEditTool.new)
      }
      door_edit_cmd.tooltip = 'Edit Door — click a door to change its settings'
      door_edit_cmd.status_bar_text = 'Click a door to edit'
      door_edit_cmd.small_icon = File.join(__dir__, 'icons', 'edit_door.svg')
      door_edit_cmd.large_icon = File.join(__dir__, 'icons', 'edit_door.svg')
      toolbar.add_item(door_edit_cmd)

      door_move_cmd = UI::Command.new('Move Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorMoveTool.new)
      }
      door_move_cmd.tooltip = 'Move Door — slide along the wall'
      door_move_cmd.status_bar_text = 'Click a door to move it left/right along the wall'
      door_move_cmd.small_icon = File.join(__dir__, 'icons', 'move_door.svg')
      door_move_cmd.large_icon = File.join(__dir__, 'icons', 'move_door.svg')
      toolbar.add_item(door_move_cmd)

      door_delete_cmd = UI::Command.new('Delete Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorDeleteTool.new)
      }
      door_delete_cmd.tooltip = 'Delete Door'
      door_delete_cmd.status_bar_text = 'Click a door to delete it'
      door_delete_cmd.small_icon = File.join(__dir__, 'icons', 'delete_door.svg')
      door_delete_cmd.large_icon = File.join(__dir__, 'icons', 'delete_door.svg')
      toolbar.add_item(door_delete_cmd)

      toolbar.restore
    end
  end

  module Menu
    def self.setup
      return if @setup_done
      @setup_done = true

      menu = @interior_pro_submenu ||= UI.menu('Extensions').add_submenu('Interior Pro')

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

      menu.add_item('Door Tool') {
        model = Sketchup.active_model
        active = model.tools.active_tool
        tool = active.is_a?(InteriorPro::DoorTool) ? active : InteriorPro::DoorTool.new
        model.select_tool(tool)
        InteriorPro::DoorLibraryDialog.show(tool)
      }

      menu.add_item('Edit Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorEditTool.new)
      }

      menu.add_item('Move Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorMoveTool.new)
      }

      menu.add_item('Delete Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorDeleteTool.new)
      }
    end
  end
end

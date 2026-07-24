# Interior Pro - Toolbar and Menu

require_relative 'ui_dialogs.rb'
require_relative 'wall_tool.rb'
require_relative 'wall_edit_tool.rb'
require_relative 'wall_move_tool.rb'
require_relative 'wall_stretch_tool.rb'
require_relative 'wall_merge_tool.rb'
require_relative 'wall_split_tool.rb'
require_relative 'wall_delete_tool.rb'
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

      setup_floors_toolbar

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

      # Stretch Wall Button
      stretch_cmd = UI::Command.new('Stretch Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallStretchTool.new)
      }
      stretch_cmd.tooltip = 'Stretch Wall - click near a wall end'
      stretch_cmd.status_bar_text = 'Click a wall near the end to stretch; move mouse, then click or type a length'
      stretch_cmd.small_icon = File.join(__dir__, 'icons', 'stretch_wall.svg')
      stretch_cmd.large_icon = File.join(__dir__, 'icons', 'stretch_wall.svg')
      toolbar.add_item(stretch_cmd)

      # Merge Wall Button
      merge_cmd = UI::Command.new('Merge Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMergeTool.new)
      }
      merge_cmd.tooltip = 'Merge Wall'
      merge_cmd.status_bar_text = 'Connect a new wall to an existing wall'
      merge_cmd.small_icon = File.join(__dir__, 'icons', 'merge_wall.svg')
      merge_cmd.large_icon = File.join(__dir__, 'icons', 'merge_wall.svg')
      toolbar.add_item(merge_cmd)

      # Split Wall (2026-07-18): click a wall at a point to split it in two.
      split_cmd = UI::Command.new('Split Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallSplitTool.new)
      }
      split_cmd.tooltip = 'Split Wall - click a wall at the split point'
      split_cmd.status_bar_text = 'Click a wall where you want to split it (snaps to touching walls)'
      split_cmd.small_icon = File.join(__dir__, 'icons', 'split_wall.svg')
      split_cmd.large_icon = File.join(__dir__, 'icons', 'split_wall.svg')
      toolbar.add_item(split_cmd)

      # Join Walls (2026-07-18): inverse of Split — two collinear walls -> one.
      join_cmd = UI::Command.new('Join Walls') {
        Sketchup.active_model.select_tool(InteriorPro::WallJoinTool.new)
      }
      join_cmd.tooltip = 'Join Walls - click two collinear touching walls'
      join_cmd.status_bar_text = 'Click two collinear touching walls to merge them into one'
      join_cmd.small_icon = File.join(__dir__, 'icons', 'join_wall.svg')
      join_cmd.large_icon = File.join(__dir__, 'icons', 'join_wall.svg')
      toolbar.add_item(join_cmd)

      # Delete Wall (2026-07-23): click a wall -> confirm -> delete it with
      # its doors/windows/molding and re-join the neighbour corners.
      wall_delete_cmd = UI::Command.new('Delete Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallDeleteTool.new)
      }
      wall_delete_cmd.tooltip = 'Delete Wall - click a wall to delete it'
      wall_delete_cmd.status_bar_text = 'Click a wall to delete it with its doors, windows and molding'
      wall_delete_cmd.small_icon = File.join(__dir__, 'icons', 'wall_delete.svg')
      wall_delete_cmd.large_icon = File.join(__dir__, 'icons', 'wall_delete.svg')
      toolbar.add_item(wall_delete_cmd)

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

      # Edit Window Button
      window_edit_cmd = UI::Command.new('Edit Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowEditTool.new)
      }
      window_edit_cmd.tooltip = 'Edit Window — click a window to change its settings'
      window_edit_cmd.status_bar_text = 'Click a window to edit its settings'
      window_edit_cmd.small_icon = File.join(__dir__, 'icons', 'window_edit.svg')
      window_edit_cmd.large_icon = File.join(__dir__, 'icons', 'window_edit.svg')
      toolbar.add_item(window_edit_cmd)

      # Move Window Button
      window_move_cmd = UI::Command.new('Move Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowMoveTool.new)
      }
      window_move_cmd.tooltip = 'Move Window — slide along the wall'
      window_move_cmd.status_bar_text = 'Click a window to move it along the wall'
      window_move_cmd.small_icon = File.join(__dir__, 'icons', 'window_move.svg')
      window_move_cmd.large_icon = File.join(__dir__, 'icons', 'window_move.svg')
      toolbar.add_item(window_move_cmd)

      # Delete Window Button
      window_delete_cmd = UI::Command.new('Delete Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowDeleteTool.new)
      }
      window_delete_cmd.tooltip = 'Delete Window'
      window_delete_cmd.status_bar_text = 'Click a window to delete it'
      window_delete_cmd.small_icon = File.join(__dir__, 'icons', 'window_delete.svg')
      window_delete_cmd.large_icon = File.join(__dir__, 'icons', 'window_delete.svg')
      toolbar.add_item(window_delete_cmd)

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

      # Molding (baseboard + crown) — whole-house apply/remove
      molding_cmd = UI::Command.new('Molding') {
        InteriorPro::MoldingDialog.show
      }
      molding_cmd.tooltip = 'Molding On/Off - baseboard + crown for the whole house'
      molding_cmd.status_bar_text = 'Apply or remove baseboard and crown molding on all walls'
      molding_cmd.small_icon = File.join(__dir__, 'icons', 'molding_tool.svg')
      molding_cmd.large_icon = File.join(__dir__, 'icons', 'molding_tool.svg')
      toolbar.add_item(molding_cmd)

      molding_toggle_cmd = UI::Command.new('Molding Toggle') {
        Sketchup.active_model.select_tool(InteriorPro::MoldingToggleTool.new)
      }
      molding_toggle_cmd.tooltip = 'Molding Toggle - click a wall to exclude/restore its molding'
      molding_toggle_cmd.status_bar_text = 'Click a wall to remove or restore its molding'
      molding_toggle_cmd.small_icon = File.join(__dir__, 'icons', 'molding_toggle.svg')
      molding_toggle_cmd.large_icon = File.join(__dir__, 'icons', 'molding_toggle.svg')
      toolbar.add_item(molding_toggle_cmd)

      # Manual molding refresh (2026-07-17): molding no longer follows new
      # walls automatically — the user refreshes with this button instead.
      molding_refresh_cmd = UI::Command.new('Refresh Molding') {
        has_molding = Sketchup.active_model.entities.grep(Sketchup::Group).any? do |g|
          %w[baseboard crown].include?(g.get_attribute('InteriorPro', 'type'))
        end
        if has_molding
          InteriorPro::MoldingManager.refresh!
        else
          UI.messagebox('No molding in the model yet - use the Molding button first')
        end
      }
      molding_refresh_cmd.tooltip = 'Refresh Molding - rebuild molding to match current walls'
      molding_refresh_cmd.status_bar_text = 'Rebuild all molding to match current walls, rooms and doors'
      molding_refresh_cmd.small_icon = File.join(__dir__, 'icons', 'molding_refresh.svg')
      molding_refresh_cmd.large_icon = File.join(__dir__, 'icons', 'molding_refresh.svg')
      toolbar.add_item(molding_refresh_cmd)

      toolbar.restore
    end

    # Separate toolbar for rooms/floors (per user request 2026-07-15).
    def self.setup_floors_toolbar
      tb = UI::Toolbar.new('Interior Pro Floors')
      return if tb.length >= 3

      rooms_cmd = UI::Command.new('Sync Rooms') {
        InteriorPro::RoomManager.sync_rooms!
      }
      rooms_cmd.tooltip = 'Detect Rooms - update room labels'
      rooms_cmd.status_bar_text = 'Detect closed wall loops and create/update room entities'
      rooms_cmd.small_icon = File.join(__dir__, 'icons', 'rooms_sync.svg')
      rooms_cmd.large_icon = File.join(__dir__, 'icons', 'rooms_sync.svg')
      tb.add_item(rooms_cmd)

      floors_cmd = UI::Command.new('Build Floors') {
        InteriorPro::FloorDialog.show
      }
      floors_cmd.tooltip = 'Floors - choose floor type per room'
      floors_cmd.status_bar_text = 'Open the floors dialog: floor type and thickness per room'
      floors_cmd.small_icon = File.join(__dir__, 'icons', 'floor_tool.svg')
      floors_cmd.large_icon = File.join(__dir__, 'icons', 'floor_tool.svg')
      tb.add_item(floors_cmd)

      # Foundation belt under exterior walls (2026-07-18).
      foundation_cmd = UI::Command.new('Foundation') {
        InteriorPro::FoundationManager.build_with_prompt!
      }
      foundation_cmd.tooltip = 'Foundation - stem wall belt under the exterior walls'
      foundation_cmd.status_bar_text = 'Build/update the foundation belt (asks for height); Remove via Extensions menu'
      foundation_cmd.small_icon = File.join(__dir__, 'icons', 'foundation_tool.svg')
      foundation_cmd.large_icon = File.join(__dir__, 'icons', 'foundation_tool.svg')
      tb.add_item(foundation_cmd)

      tb.restore
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
      menu.add_item('Stretch Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallStretchTool.new)
      }

      menu.add_item('Merge Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMergeTool.new)
      }

      menu.add_item('Split Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallSplitTool.new)
      }

      menu.add_item('Join Walls') {
        Sketchup.active_model.select_tool(InteriorPro::WallJoinTool.new)
      }

      menu.add_item('Delete Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallDeleteTool.new)
      }

      menu.add_item('Window Tool') {
        tool = InteriorPro::WindowTool.new
        InteriorPro::WindowLibraryDialog.show(tool)
      }
      menu.add_item('Edit Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowEditTool.new)
      }
      menu.add_item('Move Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowMoveTool.new)
      }
      menu.add_item('Delete Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowDeleteTool.new)
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

      menu.add_item('Molding: Apply to House') {
        InteriorPro::MoldingDialog.show
      }
      menu.add_item('Molding: Remove All') {
        InteriorPro::MoldingManager.remove_all!
      }
      menu.add_item('Molding: Toggle Wall') {
        Sketchup.active_model.select_tool(InteriorPro::MoldingToggleTool.new)
      }
      menu.add_item('Molding: Refresh') {
        InteriorPro::MoldingManager.refresh!
      }
      menu.add_item('Foundation: Build / Update') {
        InteriorPro::FoundationManager.build_with_prompt!
      }
      menu.add_item('Foundation: Remove') {
        InteriorPro::FoundationManager.remove_all!
      }
    end
  end
end

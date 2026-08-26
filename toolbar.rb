# Interior Pro - Toolbar and Menu

require_relative 'ui_dialogs.rb'
require_relative 'wall_tool.rb'
require_relative 'wall_edit_tool.rb'
require_relative 'wall_move_tool.rb'
require_relative 'wall_stretch_tool.rb'
require_relative 'wall_curve_tool.rb'
require_relative 'wall_arc_tool.rb'
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

    # Toolbar icon format: SketchUp reads SVG on Windows, PDF on macOS.
    # Falls back to .svg if the platform file is missing.
    ICON_EXT = (Sketchup.platform == :platform_osx ? '.pdf' : '.svg') unless const_defined?(:ICON_EXT, false)

    def self.icon_path(name)
      base = File.join(__dir__, 'icons', name)
      pref = base + ICON_EXT
      File.exist?(pref) ? pref : base + '.svg'
    end
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
      setup_roofs_toolbar
      setup_2d_toolbar
      setup_landscape_toolbar

      toolbar = resolve_toolbar
      return if toolbar.length >= TOOLBAR_ITEM_COUNT

      # Wall Tool Button
      wall_cmd = UI::Command.new('Wall Tool') {
        tool = InteriorPro::WallTool.new
        InteriorPro::WallLibraryDialog.show(tool)
      }
      wall_cmd.tooltip = 'Draw Walls - Opens Wall Library'
      wall_cmd.status_bar_text = 'Select wall type and start drawing'
      wall_cmd.small_icon = icon_path('wall_tool')
      wall_cmd.large_icon = icon_path('wall_tool')
      toolbar.add_item(wall_cmd)

      # Edit Wall Button
      edit_cmd = UI::Command.new('Edit Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallEditTool.new)
      }
      edit_cmd.tooltip = 'Edit Wall - Double-click a wall to edit'
      edit_cmd.status_bar_text = 'Double-click a wall to edit it'
      edit_cmd.small_icon = icon_path('edit_wall')
      edit_cmd.large_icon = icon_path('edit_wall')
      toolbar.add_item(edit_cmd)

      # Move Wall Button
      move_cmd = UI::Command.new('Move Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMoveTool.new)
      }
      move_cmd.tooltip = 'Move Wall'
      move_cmd.status_bar_text = 'Move a wall - connected walls will stretch'
      move_cmd.small_icon = icon_path('move_wall')
      move_cmd.large_icon = icon_path('move_wall')
      toolbar.add_item(move_cmd)

      # Stretch Wall Button
      stretch_cmd = UI::Command.new('Stretch Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallStretchTool.new)
      }
      stretch_cmd.tooltip = 'Stretch Wall - click near a wall end'
      stretch_cmd.status_bar_text = 'Click a wall near the end to stretch; move mouse, then click or type a length'
      stretch_cmd.small_icon = icon_path('stretch_wall')
      stretch_cmd.large_icon = icon_path('stretch_wall')
      toolbar.add_item(stretch_cmd)

      # Merge Wall Button
      merge_cmd = UI::Command.new('Merge Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallMergeTool.new)
      }
      merge_cmd.tooltip = 'Merge Wall'
      merge_cmd.status_bar_text = 'Connect a new wall to an existing wall'
      merge_cmd.small_icon = icon_path('merge_wall')
      merge_cmd.large_icon = icon_path('merge_wall')
      toolbar.add_item(merge_cmd)

      # Split Wall (2026-07-18): click a wall at a point to split it in two.
      split_cmd = UI::Command.new('Split Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallSplitTool.new)
      }
      split_cmd.tooltip = 'Split Wall - click a wall at the split point'
      split_cmd.status_bar_text = 'Click a wall where you want to split it (snaps to touching walls)'
      split_cmd.small_icon = icon_path('split_wall')
      split_cmd.large_icon = icon_path('split_wall')
      toolbar.add_item(split_cmd)

      # Join Walls (2026-07-18): inverse of Split — two collinear walls -> one.
      join_cmd = UI::Command.new('Join Walls') {
        Sketchup.active_model.select_tool(InteriorPro::WallJoinTool.new)
      }
      join_cmd.tooltip = 'Join Walls - click two collinear touching walls'
      join_cmd.status_bar_text = 'Click two collinear touching walls to merge them into one'
      join_cmd.small_icon = icon_path('join_wall')
      join_cmd.large_icon = icon_path('join_wall')
      toolbar.add_item(join_cmd)

      # Delete Wall (2026-07-23): click a wall -> confirm -> delete it with
      # its doors/windows/molding and re-join the neighbour corners.
      wall_delete_cmd = UI::Command.new('Delete Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallDeleteTool.new)
      }
      wall_delete_cmd.tooltip = 'Delete Wall - click a wall to delete it'
      wall_delete_cmd.status_bar_text = 'Click a wall to delete it with its doors, windows and molding'
      wall_delete_cmd.small_icon = icon_path('wall_delete')
      wall_delete_cmd.large_icon = icon_path('wall_delete')
      toolbar.add_item(wall_delete_cmd)

      # Window Tool Button
      window_cmd = UI::Command.new('Window Tool') {
        tool = InteriorPro::WindowTool.new
        InteriorPro::WindowLibraryDialog.show(tool)
      }
      window_cmd.tooltip = 'Place Window - Opens Window Library'
      window_cmd.status_bar_text = 'Configure window and click on a wall to place it'
      window_cmd.small_icon = icon_path('window_tool')
      window_cmd.large_icon = icon_path('window_tool')
      toolbar.add_item(window_cmd)

      # Edit Window Button
      window_edit_cmd = UI::Command.new('Edit Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowEditTool.new)
      }
      window_edit_cmd.tooltip = 'Edit Window — click a window to change its settings'
      window_edit_cmd.status_bar_text = 'Click a window to edit its settings'
      window_edit_cmd.small_icon = icon_path('window_edit')
      window_edit_cmd.large_icon = icon_path('window_edit')
      toolbar.add_item(window_edit_cmd)

      # Move Window Button
      window_move_cmd = UI::Command.new('Move Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowMoveTool.new)
      }
      window_move_cmd.tooltip = 'Move Window — slide along the wall'
      window_move_cmd.status_bar_text = 'Click a window to move it along the wall'
      window_move_cmd.small_icon = icon_path('window_move')
      window_move_cmd.large_icon = icon_path('window_move')
      toolbar.add_item(window_move_cmd)

      # Delete Window Button
      window_delete_cmd = UI::Command.new('Delete Window') {
        Sketchup.active_model.select_tool(InteriorPro::WindowDeleteTool.new)
      }
      window_delete_cmd.tooltip = 'Delete Window'
      window_delete_cmd.status_bar_text = 'Click a window to delete it'
      window_delete_cmd.small_icon = icon_path('window_delete')
      window_delete_cmd.large_icon = icon_path('window_delete')
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
      door_cmd.small_icon = icon_path('door_tool')
      door_cmd.large_icon = icon_path('door_tool')
      toolbar.add_item(door_cmd)

      door_edit_cmd = UI::Command.new('Edit Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorEditTool.new)
      }
      door_edit_cmd.tooltip = 'Edit Door — click a door to change its settings'
      door_edit_cmd.status_bar_text = 'Click a door to edit'
      door_edit_cmd.small_icon = icon_path('edit_door')
      door_edit_cmd.large_icon = icon_path('edit_door')
      toolbar.add_item(door_edit_cmd)

      door_move_cmd = UI::Command.new('Move Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorMoveTool.new)
      }
      door_move_cmd.tooltip = 'Move Door — slide along the wall'
      door_move_cmd.status_bar_text = 'Click a door to move it left/right along the wall'
      door_move_cmd.small_icon = icon_path('move_door')
      door_move_cmd.large_icon = icon_path('move_door')
      toolbar.add_item(door_move_cmd)

      door_delete_cmd = UI::Command.new('Delete Door') {
        Sketchup.active_model.select_tool(InteriorPro::DoorDeleteTool.new)
      }
      door_delete_cmd.tooltip = 'Delete Door'
      door_delete_cmd.status_bar_text = 'Click a door to delete it'
      door_delete_cmd.small_icon = icon_path('delete_door')
      door_delete_cmd.large_icon = icon_path('delete_door')
      toolbar.add_item(door_delete_cmd)

      # Molding (baseboard + crown) — whole-house apply/remove
      molding_cmd = UI::Command.new('Molding') {
        InteriorPro::MoldingDialog.show
      }
      molding_cmd.tooltip = 'Molding On/Off - baseboard + crown for the whole house'
      molding_cmd.status_bar_text = 'Apply or remove baseboard and crown molding on all walls'
      molding_cmd.small_icon = icon_path('molding_tool')
      molding_cmd.large_icon = icon_path('molding_tool')
      toolbar.add_item(molding_cmd)

      molding_toggle_cmd = UI::Command.new('Molding Toggle') {
        Sketchup.active_model.select_tool(InteriorPro::MoldingToggleTool.new)
      }
      molding_toggle_cmd.tooltip = 'Molding Toggle - click a wall to exclude/restore its molding'
      molding_toggle_cmd.status_bar_text = 'Click a wall to remove or restore its molding'
      molding_toggle_cmd.small_icon = icon_path('molding_toggle')
      molding_toggle_cmd.large_icon = icon_path('molding_toggle')
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
      molding_refresh_cmd.small_icon = icon_path('molding_refresh')
      molding_refresh_cmd.large_icon = icon_path('molding_refresh')
      toolbar.add_item(molding_refresh_cmd)

      toolbar.restore
    end

    # Separate toolbar for rooms/floors (per user request 2026-07-15).
    def self.setup_floors_toolbar
      tb = UI::Toolbar.new('Interior Pro Floors')
      return if tb.length >= 4

      rooms_cmd = UI::Command.new('Sync Rooms') {
        InteriorPro::RoomManager.sync_rooms!
      }
      rooms_cmd.tooltip = 'Detect Rooms - update room labels'
      rooms_cmd.status_bar_text = 'Detect closed wall loops and create/update room entities'
      rooms_cmd.small_icon = icon_path('rooms_sync')
      rooms_cmd.large_icon = icon_path('rooms_sync')
      tb.add_item(rooms_cmd)

      floors_cmd = UI::Command.new('Build Floors') {
        InteriorPro::FloorDialog.show
      }
      floors_cmd.tooltip = 'Floors - choose floor type per room'
      floors_cmd.status_bar_text = 'Open the floors dialog: floor type and thickness per room'
      floors_cmd.small_icon = icon_path('floor_tool')
      floors_cmd.large_icon = icon_path('floor_tool')
      tb.add_item(floors_cmd)

      # Foundation belt under exterior walls (2026-07-18).
      foundation_cmd = UI::Command.new('Foundation') {
        InteriorPro::FoundationManager.build_with_prompt!
      }
      foundation_cmd.tooltip = 'Foundation - stem wall belt under the exterior walls'
      foundation_cmd.status_bar_text = 'Build/update the foundation belt (asks for height); Remove via Extensions menu'
      foundation_cmd.small_icon = icon_path('foundation_tool')
      foundation_cmd.large_icon = icon_path('foundation_tool')
      tb.add_item(foundation_cmd)

      # Ceilings per room (2026-08-03): built only when asked, like floors.
      ceilings_cmd = UI::Command.new('Ceilings') {
        InteriorPro::CeilingManager.build_ceilings!
      }
      ceilings_cmd.tooltip = 'Ceilings - build a ceiling for every room'
      ceilings_cmd.status_bar_text = 'Build/update ceilings from the room boundaries; Remove via Extensions menu'
      ceilings_cmd.small_icon = icon_path('ceiling_tool')
      ceilings_cmd.large_icon = icon_path('ceiling_tool')
      tb.add_item(ceilings_cmd)

      tb.restore
    end

    # Separate toolbar for roofs (per user request 2026-08-04) — same
    # pattern as Floors: roofs live apart from walls/doors/windows.
    def self.setup_roofs_toolbar
      tb = UI::Toolbar.new('Interior Pro Roofs')
      return if tb.length >= 2

      roof_cmd = UI::Command.new('Roof') {
        InteriorPro::RoofDialog.show
      }
      roof_cmd.tooltip = 'Roof - style, pitch, eaves, fascia and colors'
      roof_cmd.status_bar_text = 'Open the roof settings and build/update the roof'
      roof_cmd.small_icon = icon_path('roof_tool')
      roof_cmd.large_icon = icon_path('roof_tool')
      tb.add_item(roof_cmd)

      # Edit Roof (2026-08-26): click a roof, get ITS OWN panel. The
      # guard above still holds - in a running session a populated bar is
      # skipped whole, and a fresh SketchUp start builds all three - so
      # the new button shows up on the next restart, never duplicated.
      redit_cmd = UI::Command.new('Edit Roof') {
        Sketchup.active_model.select_tool(InteriorPro::RoofEditTool.new)
      }
      redit_cmd.tooltip = 'Edit Roof - click a roof to edit it'
      redit_cmd.status_bar_text = 'Click a roof to open its settings and rebuild just it'
      redit_cmd.small_icon = icon_path('roof_edit')
      redit_cmd.large_icon = icon_path('roof_edit')
      tb.add_item(redit_cmd)

      # Per-wall gable ends (2026-08-05): click walls to choose WHERE the
      # gables go, like Revit's Defines Slope.
      gable_cmd = UI::Command.new('Gable Ends') {
        Sketchup.active_model.select_tool(InteriorPro::RoofGableTool.new)
      }
      gable_cmd.tooltip = 'Gable Ends - click a wall to toggle hip/gable'
      gable_cmd.status_bar_text = 'Click walls to toggle their roof end between hip and gable'
      gable_cmd.small_icon = icon_path('roof_gable')
      gable_cmd.large_icon = icon_path('roof_gable')
      tb.add_item(gable_cmd)

      # Dormer (2026-09-02): the panel first - sizes, gablet style and
      # pitch - and its Place button hands over to DormerTool, which
      # draws the whole dormer under the cursor and takes one click.
      # Same shape as the Wall button, which opens the library first.
      dormer_cmd = UI::Command.new('Dormer') {
        InteriorPro::DormerDialog.show
      }
      dormer_cmd.tooltip = 'Dormer - size it, then click a roof slope to place it'
      dormer_cmd.status_bar_text = 'Open the dormer panel and place a dormer on a roof'
      dormer_cmd.small_icon = icon_path('dormer_tool')
      dormer_cmd.large_icon = icon_path('dormer_tool')
      tb.add_item(dormer_cmd)

      # Shed roof (2026-08-26): a single-slope roof. Click the LOW wall -
      # the roof rises away from it and every other wall is cut vertical.
      # One click does the whole thing (the UI rule: a tool button runs
      # its tool), so there is no trip to the panel to pick the style.
      shed_cmd = UI::Command.new('Shed Roof') {
        Sketchup.active_model.select_tool(InteriorPro::RoofShedTool.new)
      }
      shed_cmd.tooltip = 'Shed Roof - click the LOW wall of a single-slope roof'
      shed_cmd.status_bar_text =
        'Click the low wall: the shed roof rises away from it. Click it again to clear.'
      shed_cmd.small_icon = icon_path('roof_shed')
      shed_cmd.large_icon = icon_path('roof_shed')
      tb.add_item(shed_cmd)

      # Downspouts (2026-08-29): they come up automatically, one per
      # corner, and this is how one comes off - and back on. Same story
      # as Edit Roof above: the length guard skips a populated bar whole,
      # so this shows up on the next SketchUp restart, never twice.
      dspout_cmd = UI::Command.new('Downspout') {
        Sketchup.active_model.select_tool(InteriorPro::DownspoutTool.new)
      }
      dspout_cmd.tooltip = 'Downspout - click one to remove it, click the roof to bring it back'
      dspout_cmd.status_bar_text =
        'Click a downspout to remove it for good; click the roof where one was to restore it'
      dspout_cmd.small_icon = icon_path('downspout')
      dspout_cmd.large_icon = icon_path('downspout')
      tb.add_item(dspout_cmd)

      tb.restore
    end

    # Separate 2D toolbar (2026-07-30): direct access to the 2D editor, so the
    # 2D-first workflow does not have to go through the Extensions menu.
    # Its own toolbar on purpose - the main bar's length guard
    # (TOOLBAR_ITEM_COUNT) would skip any item added there now.
    def self.setup_2d_toolbar
      tb = UI::Toolbar.new('Interior Pro 2D')
      # two buttons now: the 2D editor and the sheet window (2026-08-12).
      return if tb.length >= 2

      editor_cmd = UI::Command.new('2D Editor') {
        InteriorPro::PlanEditor.show
      }
      editor_cmd.tooltip = '2D Editor - draw the plan from above'
      editor_cmd.status_bar_text = 'Open the 2D editor: draw walls, doors and windows from above'
      editor_cmd.small_icon = icon_path('plan_2d')
      editor_cmd.large_icon = icon_path('plan_2d')
      tb.add_item(editor_cmd)

      # The sheet window: page, scale, layers, PDF (2026-08-12). A button,
      # not a menu item - the user asked for it where he can see it.
      sheet_cmd = UI::Command.new('Sheet') {
        InteriorPro::PlanSheetDialog.show
      }
      sheet_cmd.tooltip = 'Sheet - the page, the scale and the PDF'
      sheet_cmd.status_bar_text = 'Open the sheet window: page size, scale, layers, export PDF'
      sheet_cmd.small_icon = icon_path('sheet_pdf')
      sheet_cmd.large_icon = icon_path('sheet_pdf')
      tb.add_item(sheet_cmd)

      tb.restore
    end

    # ------------------------------------------------------- Landscape Pro
    #
    # Everything outside the house lives on its OWN bar (user, 2026-08-15):
    # fences, walls, patios, pools, lighting, planting. It is a separate
    # product wearing the same plugin, so nothing here may reach into the
    # wall / door / window / roof bars, and nothing there needs to know this
    # exists. One button today - the fence.
    def self.setup_landscape_toolbar
      tb = UI::Toolbar.new('Landscape Pro')
      # Bump this every time a button is added, or the new one silently never
      # appears: the toolbar survives a restart, so on the next launch it is
      # already non-empty and the guard returns before adding anything.
      return if tb.length >= 2

      # Named in full on purpose: the button and the menu item must land in the
      # SAME method, so there is only ever one fence flow to fix.
      fence_cmd = UI::Command.new('Fence') { InteriorPro::Toolbar.open_fence_library }
      fence_cmd.tooltip = 'Fence - pick a type, then click its two ends'
      fence_cmd.status_bar_text = 'Pick a fence type, then click where it starts and ends'
      icon = icon_path('fence_tool')
      # A missing icon file must not take the whole toolbar down with it.
      if File.exist?(icon)
        fence_cmd.small_icon = icon
        fence_cmd.large_icon = icon
      end
      tb.add_item(fence_cmd)

      # The garden wall (חומה) - a free-standing masonry site wall. Same
      # one-method rule as the fence: button and menu item both land in
      # open_garden_wall, so there is only ever one flow to fix.
      wall_cmd = UI::Command.new('Wall') { InteriorPro::Toolbar.open_garden_wall }
      wall_cmd.tooltip = 'Garden Wall - set thickness and height, then click its two ends'
      wall_cmd.status_bar_text = 'Garden wall: pick thickness, height and finish, then click where it starts and ends'
      wicon = icon_path('garden_wall_tool')
      if File.exist?(wicon)
        wall_cmd.small_icon = wicon
        wall_cmd.large_icon = wicon
      end
      tb.add_item(wall_cmd)

      tb.restore
    end

    # The garden wall. Ask for its settings, then hand him the mouse - the
    # same order as the Wall and Fence buttons: decide what you are drawing,
    # THEN draw it.
    def self.open_garden_wall
      unless defined?(InteriorPro::Landscape::GardenWallTool)
        UI.messagebox('The garden wall tool did not load. Run InteriorPro.reload!')
        return
      end
      tool = InteriorPro::Landscape::GardenWallTool.prompt!
      return unless tool
      Sketchup.active_model.select_tool(tool)
    rescue StandardError => e
      puts "[GardenWall] open: #{e.class}: #{e.message}"
      puts Array(e.backtrace).first(4).join("\n")
    end

    # The fence library window, the same order as the Wall button: pick what
    # you are drawing, THEN get the mouse (2026-08-16).
    #
    # The nine-field UI.inputbox that used to open here is still in
    # fence_tool.rb and is still the fallback, so a broken or missing library
    # window can never leave the fence tool unreachable.
    def self.open_fence_library
      # Since 2026-08-16 a fence is one of HIS models, dropped as a .skp into
      # landscape/reference, laid along a line. Pick which one, then draw.
      # The parametric library (FenceLibraryDialog) is still on disk and still
      # tested; it is only reached from the console now.
      if defined?(InteriorPro::Landscape::FenceRefTool)
        refs = InteriorPro::Landscape::FenceRefTool.references
        if refs.empty?
          UI.messagebox("No fences yet.\n\nDrop a .skp of a fence into:\n" +
                        InteriorPro::Landscape::FenceRefTool.reference_dir)
          return
        end
        names = refs.map { |r| r[:name] }
        pick = if names.length == 1
                 names.first
               else
                 res = UI.inputbox(['Fence'], [names.first], [names.join('|')],
                                   'Landscape Pro - Fence')
                 res ? res[0].to_s : nil
               end
        return unless pick
        ref = refs.find { |r| r[:name] == pick }
        return unless ref
        Sketchup.active_model.select_tool(InteriorPro::Landscape::FenceRefTool.new(ref[:path]))
      elsif defined?(InteriorPro::Landscape::FenceLibraryDialog)
        InteriorPro::Landscape::FenceLibraryDialog.show
      else
        tool = InteriorPro::Landscape::FenceTool.new
        Sketchup.active_model.select_tool(tool) if tool.prompt_settings!
      end
    rescue StandardError => e
      puts "[Fence] open: #{e.class}: #{e.message}"
      puts Array(e.backtrace).first(4).join("\n")
    end
  end

  module Menu
    def self.setup
      return if @setup_done
      @setup_done = true

      menu = @interior_pro_submenu ||= UI.menu('Extensions').add_submenu('Interior Pro')

      # Right-click on a selected wall: flip exterior/interior faces
      # (2026-08-06, fixes a flipped wall from the 2D->3D generator).
      UI.add_context_menu_handler do |cmenu|
        sel = Sketchup.active_model.selection
        sel_walls = sel.select do |e|
          e.respond_to?(:get_attribute) && e.get_attribute('InteriorPro', 'type') == 'wall'
        end
        unless sel_walls.empty?
          cmenu.add_separator
          # Flip works on ANY number of selected walls in one go (user
          # 2026-08-12) - selecting five and flipping them one at a time was
          # five right-clicks and five undo steps.
          flip_label = sel_walls.length > 1 ? "Interior Pro: Flip Wall Faces (#{sel_walls.length})" : 'Interior Pro: Flip Wall Faces'
          cmenu.add_item(flip_label) do
            InteriorPro::WallTool.flip_wall_faces_multi!(Sketchup.active_model.selection.to_a)
          end
          # Body-side move (2026-08-12): the drawn line stays, the thickness
          # changes sides. Fixes corners where two bodies sit on opposite
          # sides and can only meet with a shoulder.
          side_label = sel_walls.length > 1 ? "Interior Pro: Wall Body to Other Side (#{sel_walls.length})" : 'Interior Pro: Wall Body to Other Side'
          cmenu.add_item(side_label) do
            InteriorPro::WallTool.swap_wall_side_multi!(Sketchup.active_model.selection.to_a)
          end
          # Curved walls (2026-08-11): reach them straight from the wall.
          # Two ways in because they are two different hands, not two
          # controls for the same job - mouse, or keyboard. Both act on ONE
          # wall, so they only appear when exactly one is selected.
          if sel_walls.length == 1
            cmenu.add_item('Interior Pro: Curve Wall - drag the middle') do
              Sketchup.active_model.select_tool(InteriorPro::WallCurveTool.new)
            end
            cmenu.add_item('Interior Pro: Curve Wall - type the bow') do
              InteriorPro::WallCurveTool.prompt_wall_sag!(Sketchup.active_model.selection.first)
            end
          end
        end
      end

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

      # Curve Wall (2026-08-10): click a wall, drag its middle sideways.
      # Menu only for now - the toolbar still needs a matching icon.
      menu.add_item('Curve Wall') {
        Sketchup.active_model.select_tool(InteriorPro::WallCurveTool.new)
      }

      # Arc Wall (2026-08-11): draw a NEW curved wall in three clicks.
      # Goes through the wall library first, exactly like the Wall tool, so
      # it picks up thickness, height and materials the same way.
      menu.add_item('Arc Wall (3 clicks)') {
        tool = InteriorPro::WallArcTool.new
        InteriorPro::WallLibraryDialog.show(tool)
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
      menu.add_item('Ceilings: Build / Update') {
        InteriorPro::CeilingManager.build_ceilings!
      }
      menu.add_item('Ceilings: Remove') {
        InteriorPro::CeilingManager.remove_all!
      }
      menu.add_item('Level 2 Structure: Build / Update') {
        InteriorPro::LevelManager.build_level2_structure!
      }
      menu.add_item('Level 2 Structure: Remove') {
        InteriorPro::LevelManager.remove_level2_structure!
      }
      menu.add_item('Level: Work on Level 1') {
        InteriorPro::LevelManager.set_active_level!(1)
      }
      menu.add_item('Level: Work on Level 2') {
        InteriorPro::LevelManager.set_active_level!(2)
      }
      menu.add_item('Roof: Build / Update') {
        InteriorPro::RoofDialog.show
      }
      menu.add_item('Roof: Edit (click a roof)') {
        Sketchup.active_model.select_tool(InteriorPro::RoofEditTool.new)
      }
      menu.add_item('Roof: Gable Ends (click walls)') {
        Sketchup.active_model.select_tool(InteriorPro::RoofGableTool.new)
      }
      menu.add_item('Roof: Shed - single slope (click the low wall)') {
        Sketchup.active_model.select_tool(InteriorPro::RoofShedTool.new)
      }
      menu.add_item('Roof: Downspout (click one to remove)') {
        Sketchup.active_model.select_tool(InteriorPro::DownspoutTool.new)
      }
      menu.add_item('Roof: Remove') {
        InteriorPro::RoofManager.remove_all!
      }
      menu.add_item('2D Editor') {
        InteriorPro::PlanEditor.show
      }
      menu.add_item('2D Plan: Build / Refresh') {
        InteriorPro::PlanGenerator.build!
      }
      menu.add_item('2D Plan: Remove') {
        InteriorPro::PlanGenerator.remove_all!
      }
      # The sheet window (2026-08-12): see the page before it prints.
      menu.add_item('Sheet: Page + PDF') {
        InteriorPro::PlanSheetDialog.show
      }

      # Landscape Pro (2026-08-15): the outside of the house. Its own bar and
      # its own menu entry, so it can grow without crowding the wall tools.
      # One way in, shared with the toolbar button (2026-08-16) - the menu and
      # the button must never drift into two different fence flows.
      menu.add_item('Landscape: Fence') {
        InteriorPro::Toolbar.open_fence_library
      }

      menu.add_item('Landscape: Garden Wall') {
        InteriorPro::Toolbar.open_garden_wall
      }

      # NO backup menu items, deliberately (user, 2026-08-15): "take them
      # away, I don't want to complicate things". Backing up is not a feature
      # he should have to think about - it runs by itself (auto_backup.rb,
      # state_backup.rb). Recovery is rare enough to be done by hand:
      #
      #   InteriorPro::StateBackup.report
      #   InteriorPro::StateBackup.restore!('plan_draft')
      #   InteriorPro::PlanEditor.restore_underlay!
      #
      # Do not add buttons for these again without asking him.

      # One click instead of restarting SketchUp after a code change
      # (2026-08-12). New menu items still need a restart - SketchUp
      # cannot take a menu item away once it is there.
      menu.add_item('Reload Interior Pro') {
        InteriorPro.reload!
      }
    end
  end
end

# Interior Pro - Main Module

module InteriorPro
  PLUGIN_DIR = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)

  def self.plugin_files
    %w[
      wall_library.rb
      wall_library_dialog.rb
      wall_tool.rb
      ui_dialogs.rb
      wall_edit_tool.rb
      wall_move_tool.rb
      wall_merge_tool.rb
      window_library.rb
      window_library_dialog.rb
      window_tool.rb
      door_library.rb
      door_casing_profiles.rb
      door_library_dialog.rb
      door_tool.rb
      door_manager.rb
      door_edit_tool.rb
      door_move_tool.rb
      door_delete_tool.rb
      toolbar.rb
    ]
  end

  def self.load_files
    plugin_files.each { |f| load File.join(PLUGIN_DIR, f) }
  end

  def self.reload!
    load_files
    puts 'InteriorPro: classes reloaded (toolbar/menu preserved).'
    nil
  end
end

InteriorPro.load_files

module InteriorPro
  unless file_loaded?(__FILE__)
    InteriorPro::Toolbar.setup
    InteriorPro::Menu.setup
    file_loaded(__FILE__)
  end
end

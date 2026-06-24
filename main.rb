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
      solid_boolean/load.rb
      door_boolean.rb
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
    failed = []
    plugin_files.each do |f|
      path = File.join(PLUGIN_DIR, f)
      unless File.exist?(path)
        puts "[InteriorPro] missing file: #{f}"
        failed << f
        next
      end
      begin
        load path
      rescue StandardError => e
        puts "[InteriorPro] load failed: #{f} — #{e.class}: #{e.message}"
        puts e.backtrace.first(6).join("\n")
        failed << f
      end
    end
    if failed.any?
      puts "[InteriorPro] #{failed.length} file(s) failed: #{failed.join(', ')}"
    end
    failed
  end

  def self.ui_setup_complete?
    @ui_setup_complete == true
  end

  def self.setup_ui!
    return if @ui_setup_complete

    # Reserve immediately so a second load in the same tick cannot register twice.
    @ui_setup_complete = true

    begin
      InteriorPro::Toolbar.setup
    rescue StandardError => e
      puts "[InteriorPro] Toolbar.setup failed: #{e.message}"
      puts e.backtrace.first(8).join("\n")
      return
    end
    begin
      InteriorPro::Menu.setup
    rescue StandardError => e
      puts "[InteriorPro] Menu.setup failed: #{e.message}"
      puts e.backtrace.first(8).join("\n")
    end
  end

  # Hide duplicate legacy toolbar and show a clean 9-button bar (Ruby Console).
  def self.repair_ui!
    unless const_defined?(:Toolbar, false)
      load_files
    end

    legacy = UI::Toolbar.new(InteriorPro::Toolbar::LEGACY_TOOLBAR_NAME)
    if legacy.length > InteriorPro::Toolbar::TOOLBAR_ITEM_COUNT
      legacy.hide
      puts "InteriorPro: hid legacy toolbar (#{legacy.length} items)"
    end

    InteriorPro::Toolbar.remove_instance_variable(:@setup_done) if
      InteriorPro::Toolbar.instance_variable_defined?(:@setup_done)

    InteriorPro::Toolbar.setup
    toolbar = InteriorPro::Toolbar.resolve_toolbar
    toolbar.show
    puts "InteriorPro: active toolbar '#{toolbar.name}' — #{toolbar.length} tools"
    puts 'Uncheck "Interior Pro" under View > Toolbars if the old duplicate bar is still listed.'
    puts 'Restart SketchUp if Extensions menu lists Interior Pro twice.'
    nil
  end

  # Ruby Console recovery if toolbar/menu missing after a bad load.
  def self.fix_ui!
    unless const_defined?(:Toolbar, false)
      puts '[InteriorPro] Toolbar missing — loading plugin files...'
      begin
        load_files
      rescue StandardError => e
        puts "[InteriorPro] fix_ui! load_files failed: #{e.message}"
        puts e.backtrace.first(8).join("\n")
        return nil
      end
    end

    unless const_defined?(:Toolbar, false)
      puts '[InteriorPro] Toolbar still missing — run InteriorPro.diagnose_load!'
      return nil
    end

    if InteriorPro::Toolbar.bloated_toolbars?
      repair_ui!
      return nil
    end

    if @ui_setup_complete
      toolbar = InteriorPro::Toolbar.resolve_toolbar
      if toolbar.length > 0
        puts 'InteriorPro: UI already registered. Restart SketchUp if tools still appear twice.'
        return nil
      end
      # Toolbar empty but flag set — allow one retry.
      @ui_setup_complete = false
    end

    setup_ui!
    puts 'InteriorPro: UI setup attempted — check View > Toolbars > Interior Pro'
    nil
  end

  def self.diagnose_load!
    plugin_files.each do |f|
      path = File.join(PLUGIN_DIR, f)
      begin
        load path
        puts "OK  #{f}"
      rescue StandardError => e
        puts "FAIL #{f} — #{e.message}"
        puts e.backtrace.first(4).join("\n")
      end
    end
    nil
  end

  def self.reload!
    load_files
    puts 'InteriorPro: classes reloaded (toolbar/menu preserved).'
    nil
  end
end

begin
  failed = InteriorPro.load_files
  unless file_loaded?(__FILE__)
    InteriorPro.setup_ui!
    file_loaded(__FILE__)
  end
  if failed.any? && !InteriorPro.const_defined?(:Toolbar, false)
    puts '[InteriorPro] Run InteriorPro.diagnose_load! in Ruby Console for details.'
  end
rescue StandardError => e
  puts "[InteriorPro] startup failed: #{e.class}: #{e.message}"
  puts e.backtrace.first(10).join("\n")
end

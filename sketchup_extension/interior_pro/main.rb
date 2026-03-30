# Interior Pro - Main Module

require_relative 'wall_tool.rb'
require_relative 'wall_edit_tool.rb'
require_relative 'toolbar.rb'
require_relative 'ui_dialogs.rb'

module InteriorPro
  unless file_loaded?(__FILE__)
    # Initialize toolbar and menu
    InteriorPro::Toolbar.setup
    InteriorPro::Menu.setup
    file_loaded(__FILE__)
  end
end

# Interior Pro - Main Module

require_relative 'wall_library.rb'
require_relative 'wall_library_dialog.rb'
require_relative 'wall_tool.rb'
require_relative 'wall_edit_tool.rb'
require_relative 'toolbar.rb'

module InteriorPro
  unless file_loaded?(__FILE__)
    InteriorPro::Toolbar.setup
    InteriorPro::Menu.setup
    file_loaded(__FILE__)
  end
end

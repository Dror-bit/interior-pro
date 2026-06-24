# Interior Pro — Ruby Console recovery. Paste:
#   load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/recover.rb'

RECOVER_DIR = File.dirname(__FILE__)

module InteriorPro
  RECOVER_DIR = RECOVER_DIR unless const_defined?(:RECOVER_DIR, false)

  def self.reload_door_plugin_code!
    %w[door_observer.rb door_boolean.rb door_manager.rb].each do |fname|
      path = File.join(RECOVER_DIR, fname)
      load path if File.exist?(path)
    end
  end
end

InteriorPro.reload_door_plugin_code!
InteriorPro.stabilize_door_plugin! if InteriorPro.respond_to?(:stabilize_door_plugin!)

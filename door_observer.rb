# Interior Pro — door-wall sync utilities.
# AUTO-SYNC IS DISABLED. Use toolbar/menu "Sync Doors" (DoorManager.sync_all_doors_to_walls!).

module InteriorPro
  AUTO_DOOR_WALL_SYNC = false unless const_defined?(:AUTO_DOOR_WALL_SYNC, false)

  LEGACY_WALL_MOVE_OBSERVER_METHODS = %i[
    schedule_sync! run_sync_if_needed! walls_to_sync run_sync
  ].freeze unless const_defined?(:LEGACY_WALL_MOVE_OBSERVER_METHODS, false)

  def self.interior_pro_model_hook_modules
    Sketchup::Model.ancestors.select { |a|
      a.is_a?(Module) && a.name.to_s.start_with?('InteriorPro::')
    }
  end

  def self.strip_all_interior_pro_model_hooks!
    removed = []
    interior_pro_model_hook_modules.each do |mod|
      %i[commit_operation start_operation abort_operation].each do |meth|
        next unless mod.method_defined?(meth)

        mod.module_eval { remove_method(meth) }
        removed << "#{mod.name}##{meth}"
      end
    end
    removed.each { |name| puts "[InteriorPro] removed hook #{name}" }
    removed.length
  end

  # Backward-compatible alias
  def self.strip_broken_commit_hooks!
    strip_all_interior_pro_model_hooks!
  end

  def self.refresh_wall_move_observer_class!
    return unless const_defined?(:WallMoveObserver, false)

    LEGACY_WALL_MOVE_OBSERVER_METHODS.each do |name|
      next unless InteriorPro::WallMoveObserver.method_defined?(name)

      InteriorPro::WallMoveObserver.send(:remove_method, name)
      puts "[InteriorPro] removed legacy WallMoveObserver##{name}"
    end
  end

  def self.door_observer_code_stale?
    return false unless const_defined?(:WallMoveObserver, false)

    InteriorPro::WallMoveObserver.instance_methods(false).include?(:schedule_sync!)
  end

  def self.door_sync_hook_diagnose
    hooks = interior_pro_model_hook_modules.select { |mod|
      mod.method_defined?(:commit_operation) ||
        mod.method_defined?(:start_operation) ||
        mod.method_defined?(:abort_operation)
    }
    if hooks.empty?
      puts 'OK — no InteriorPro hooks on Sketchup::Model'
    else
      puts "InteriorPro model hooks: #{hooks.map(&:name).join(', ')}"
      hooks.each do |mod|
        %i[commit_operation start_operation abort_operation].each do |meth|
          next unless mod.method_defined?(meth)

          src = mod.instance_method(meth).source_location
          puts "  #{mod.name}##{meth} at #{src ? src.join(':') : 'unknown'}"
        end
      end
    end
    puts "auto door-wall sync: #{AUTO_DOOR_WALL_SYNC ? 'ON' : 'OFF (manual Sync Doors only)'}"
    puts "stale observer class: #{door_observer_code_stale?}"
    nil
  end

  def self.uninstall_auto_sync_observers!(model = nil)
    model ||= Sketchup.active_model
    return 0 unless model

    removed = 0
    list = model.instance_variable_get(:@observer_list)
    if list.respond_to?(:each)
      list.each do |obs|
        next unless obs
        name = obs.class.name.to_s
        next unless name.include?('WallMoveObserver') || name.include?('DoorObserver')

        model.remove_observer(obs)
        puts "[InteriorPro] removed observer #{name}"
        removed += 1
      end
    end
    @door_observer_models = {}
    removed
  end

  # Do not register observers — auto-sync disabled.
  def self.install_door_observer!(_model = nil)
    nil
  end

  def self.install_door_observer_app_observer!
    nil
  end

  def self.install_model_operation_track_hook!
    strip_all_interior_pro_model_hooks!
    nil
  end

  def self.install_model_commit_door_sync_hook!
    install_model_operation_track_hook!
  end

  def self.stabilize_door_plugin!
    strip_all_interior_pro_model_hooks!
    refresh_wall_move_observer_class!
    uninstall_auto_sync_observers!
    puts '[InteriorPro] door plugin stabilized (auto-sync OFF, hooks stripped)'
    door_sync_hook_diagnose
    nil
  end

  def self.repair_door_wall_sync!
    stabilize_door_plugin!
  end

  def self.emergency_fix_wall_preview!
    stabilize_door_plugin!
  end
end

InteriorPro.strip_all_interior_pro_model_hooks!
InteriorPro.refresh_wall_move_observer_class!

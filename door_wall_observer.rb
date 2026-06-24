# Stabilization bootstrap — strip legacy hooks only. No auto-sync observers.

module InteriorPro
  def self.legacy_door_wall_hooks_in_memory?
    Sketchup::Model.ancestors.any? { |a| a.name.to_s.match?(/DoorWall/i) }
  end

  def self.ensure_door_wall_sync_loaded!
    if respond_to?(:stabilize_door_plugin!)
      stabilize_door_plugin!
    elsif respond_to?(:strip_all_interior_pro_model_hooks!)
      strip_all_interior_pro_model_hooks!
      uninstall_auto_sync_observers! if respond_to?(:uninstall_auto_sync_observers!)
    end

    if legacy_door_wall_hooks_in_memory?
      puts '[InteriorPro] legacy DoorWall hooks still in memory — restart SketchUp once.'
    end
  end
end

InteriorPro.ensure_door_wall_sync_loaded!

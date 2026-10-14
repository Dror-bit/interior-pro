# Loads the house drawing integration without opening dialogs or modifying models.
module InteriorProKitchenStartup
  ROOT=File.dirname(__FILE__) unless const_defined?(:ROOT,false)
  def self.install!
    return true if @installed
    return false unless defined?(InteriorPro::PlanEditor)
    require File.join(ROOT,'kitchen_lab') unless defined?(KitchenLab)
    KitchenLab.send(:remove_const,:TARGET_PID) if KitchenLab.const_defined?(:TARGET_PID,false)
    KitchenLab.const_set(:TARGET_PID,Process.pid)
    require File.join(ROOT,'kitchen_plan')
    InteriorPro::KitchenPlan.install_editor!(toolbar: false)
    KitchenLab.install_toolbar(restore: true) if defined?(UI::Toolbar) && defined?(UI::Command)
    @installed=true
  end
  def self.start!
    return if @installed || @timer
    return if install!
    attempts=0
    @timer=UI.start_timer(1,true) do
      attempts+=1
      if install! || attempts>=120
        UI.stop_timer(@timer)
        @timer=nil
      end
    end
  end
end

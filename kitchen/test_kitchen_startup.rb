module Sketchup
  class ModelObserver; end
  class << self; attr_accessor :active_model; end
end
module InteriorPro; module PlanEditor; end; end
require_relative 'kitchen_bootstrap'
def check(value,message);raise message unless value;end
class ReviewModel
  attr_accessor :active_path
  attr_reader :observers
  def initialize;@observers=[];end
  def add_observer(o);@observers<<o;end
  def remove_observer(o);@observers.delete(o);end
  def set_attribute(*);raise 'Startup must not write to the model';end
end
a=ReviewModel.new;b=ReviewModel.new;Sketchup.active_model=a
InteriorProKitchenStartup.start!
check(KitchenLab.instance_variable_get(:@model).nil?,'Startup bound model too early')
check(KitchenLab::TARGET_PID==Process.pid,'Stale PID')
2.times { InteriorProKitchenStartup.start! }
check(InteriorPro::PlanEditor.singleton_class.ancestors.count(InteriorPro::KitchenPlan::EditorPreview)==1,'Duplicate hook')
2.times { InteriorPro::KitchenPlan.bind_active_model! }
check(a.observers.length==1,'Duplicate observer')
Sketchup.active_model=b
InteriorPro::KitchenPlan.bind_active_model!
check(a.observers.empty? && b.observers.length==1,'Observer not moved')
check(KitchenLab.instance_variable_get(:@model).equal?(b),'Old model retained')
Sketchup.active_model=a
dialog=Object.new;def dialog.visible?;true;end
KitchenLab.instance_variable_set(:@dialog,dialog)
begin
 InteriorPro::KitchenPlan.bind_active_model!
 raise 'Unsaved cabinet editor was ignored'
rescue RuntimeError=>e
 raise unless e.message=='Close the cabinet editor before switching models.'
end
check(KitchenLab.instance_variable_get(:@model).equal?(b),'Unsafe rebind')
KitchenLab.instance_variable_set(:@dialog,nil)
a.active_path=[1]
begin
 InteriorPro::KitchenPlan.bind_active_model!
 raise 'Active group was ignored'
rescue RuntimeError=>e
 raise unless e.message=='Close the current group before opening Kitchens.'
end
puts 'PASS: startup is read-only, current PID, idempotent hooks, model rebinding, observer cleanup and open-draft/context guards.'

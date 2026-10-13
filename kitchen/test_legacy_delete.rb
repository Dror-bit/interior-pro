module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
module KitchenLab
 class << self;attr_accessor :delete_request;end
 def self.execute_commands(request,*);self.delete_request=request;:shared_result;end
end
raise 'Wrong return' unless KitchenLab.remove('panel-id')==:shared_result
raise 'Legacy bypasses shared engine' unless KitchenLab.delete_request=={'commands'=>[{'type'=>'remove_cabinet','payload'=>{'id'=>'panel-id'}}]}
puts 'PASS: legacy remove callback uses the shared atomic bundle deletion engine'

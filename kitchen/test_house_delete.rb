module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
class DeleteDialog
 attr_reader :callbacks,:scripts
 def initialize;@callbacks={};@scripts=[];end
 def add_action_callback(name,&block);@callbacks[name]=block;end
 def execute_script(script);@scripts<<script;end
end
module KitchenLab
 class << self;attr_accessor :test_source,:test_request;end
 def self.guard!;end
 def self.document;test_source;end
 def self.execute_commands(request,*);self.test_request=request;end
end
KitchenLab.test_source=KitchenLab.command_engine.plan(KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[]),[{'type'=>'create_cabinet','payload'=>{'id'=>'one','kind'=>'doors'}}])['document']
InteriorPro::KitchenPlan.define_singleton_method(:push){|dialog|dialog.execute_script('REFRESH')}
dlg=DeleteDialog.new;InteriorPro::KitchenPlan.bind_drag(dlg)
call=dlg.callbacks.fetch('kitchen_delete_cabinet')
call.call(nil,JSON.generate({'id'=>'one','revision'=>KitchenLab.document['revision']}))
check(KitchenLab.test_request['commands']==[{'type'=>'remove_cabinet','payload'=>{'id'=>'one'}}],'Wrong removal command')
check(dlg.scripts[-2]=='REFRESH' && dlg.scripts[-1].include?('result(null)'),'Delete did not refresh before acknowledgement')
KitchenLab.test_request=nil
call.call(nil,JSON.generate({'id'=>'one','revision'=>-1}))
check(KitchenLab.test_request.nil?&&dlg.scripts.last.include?('Kitchen changed'),'Stale deletion accepted')
call.call(nil,JSON.generate({'id'=>'missing','revision'=>KitchenLab.document['revision']}))
check(KitchenLab.test_request.nil?&&dlg.scripts.last.include?('no longer exists'),'Missing cabinet accepted')
puts 'PASS: house Delete uses shared engine, revision guard and existing-cabinet validation.'

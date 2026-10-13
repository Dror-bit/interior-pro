module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
module KitchenLab
 def self.guard!;end
 def self.cabinets;[];end
end
model=Object.new
def model.get_attribute(_dict,key,*);@attrs.fetch(key,nil);end
model.instance_variable_set(:@attrs,{})
KitchenLab.instance_variable_set(:@model,model)
id=KitchenLab::HandleCatalog.products.find{|p|p['number']==18}['asset_id']
doc=KitchenLab.document
check(doc['settings']['global_door_handle_model']==id,'Door default missing')
check(doc['settings']['global_drawer_handle_model']==id,'Drawer default missing')
model.instance_variable_set(:@attrs,{'settings'=>JSON.generate({'shaker_width'=>2.25,'shaker_inset'=>0.25,'global_door_handle_model'=>''})})
check(KitchenLab.document['settings']['global_door_handle_model']=='','Overwrote saved standard handle')
model.instance_variable_set(:@attrs,{'document'=>JSON.generate(KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[]))})
check(!KitchenLab.document['settings'].key?('global_door_handle_model'),'Rewrote existing document')
puts 'PASS: #18 for new kitchens, saved choices and documents preserved'

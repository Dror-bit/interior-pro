module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
engine=KitchenLab.command_engine;settings={'shaker_width'=>2.25,'shaker_inset'=>0.25}
source=KitchenLab::Document.create(settings,[])
ids=KitchenLab::HandleCatalog.products.map{|p|p['asset_id']}
a,b=ids[0,2]
source=engine.plan(source,[{'type'=>'create_cabinet','payload'=>{'id'=>'local','kind'=>'doors','overrides'=>{'door_handle_model'=>b,'drawer_handle_model'=>b,'finish'=>'sage'}}},{'type'=>'create_cabinet','payload'=>{'id'=>'default','kind'=>'drawers','overrides'=>{'x'=>200}}}])['document']
payload={'global_door_handle_model'=>a,'global_drawer_handle_model'=>a,'apply_to_all'=>false}
result=engine.plan(source,[{'type'=>'set_project_handles','payload'=>payload}])['document']
check(result['cabinets'][0]['door_handle_model']==b,'Default overwrote individual choice')
check(result['settings']['global_door_handle_model']==a,'Default missing')
all=engine.plan(source,[{'type'=>'set_project_handles','payload'=>payload.merge('apply_to_all'=>true)}])['document']
check(all['cabinets'].all?{|c|c['door_handle_model'].nil?&&c['drawer_handle_model'].nil?},'Apply all retained local models')
check(all['cabinets'][0]['finish']=='sage','Handle update recolored cabinet')
check(all['revision']==source['revision']+1,'Not one undo revision')
created=engine.plan(all,[{'type'=>'create_cabinet','payload'=>{'id'=>'new','kind'=>'doors','overrides'=>{'x'=>400}}}])['document']['cabinets'].last
check(KitchenLab::HandleCatalog.selected(created,false,all['settings'])['asset_id']==a,'New cabinet did not inherit default')
check(KitchenLab::Document.read(JSON.generate(all))==all,'Saved defaults changed')
puts 'PASS: project defaults, existing local exceptions, replace all, unchanged finishes, new cabinet inheritance, persistence and atomic revision'

module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
id='thermador-columns-48-panelready'
s=KitchenLab.validate_settings({'global_finish'=>'sage'},{'shaker_width'=>2.25,'shaker_inset'=>0.25})
engine=KitchenLab::Engine.new(validator:->(d,o){KitchenLab.validate(d,o)},settings_validator:->(r,c){KitchenLab.validate_settings(r,c)})
source=KitchenLab::Document.create(s,[])
document=engine.plan(source,[{'type'=>'create_catalog_appliance','payload'=>{'id'=>'columns','product_id'=>id,'wall'=>'A'}}])['document']
d=document['cabinets'].find{|c|c['id']=='columns'}
p=d['appliance']['panel_ready'];panels=p['panels']
check(panels.map{|v|v['panel_id']}==%w[freezer_left_door refrigerator_right_door],'Expected two full-height doors')
check(panels.all?{|v|v['dimensions_in']['height']==79.875},'Unexpected drawer or split panel')
check(panels.map{|v|v['opening']['hinge_side']}==%w[left right],'Wrong hinges')
check(panels.all?{|v|v['handle_attachment']['length_axis_panel_local']==[0,0,1]},'Handles must be vertical')
parts=KitchenLab::PanelReady.parts(d)
check(parts.count{|v|v['name'].start_with?('Panel ')}==2,'Incorrect panel projection')
check(parts.count{|v|v['name'].start_with?('Handle ')}==2,'Missing independent handles')
options=KitchenLab::PanelReady.copy(d['panel_options'])
options['freezer_left_door'].merge!('finish'=>'charcoal','style'=>'shaker')
options['freezer_left_door']['handle']['overall_length']=18
updated=engine.plan(document,[{'type'=>'update_cabinet','payload'=>{'id'=>'columns','changes'=>{'panel_options'=>options}}}])['document']
u=updated['cabinets'].find{|c|c['id']=='columns'}
check(u['panel_options']['refrigerator_right_door']==d['panel_options']['refrigerator_right_door'],'Left panel change affected right door')
check(u['panel_options']['freezer_left_door']['handle']['snapshot']['L']==18,'Handle size not applied')
check(u['appliance']==d['appliance'],'Asset snapshot changed')
check(KitchenLab::Document.read(JSON.generate(updated))==updated,'Save/load lost independent panels')
%w[thermador-columns-42-24r-18f thermador-columns-48-24r-24f thermador-columns-48-30r-18f det3650ci-r-panelready dw2451-panelready].each{|old|check(KitchenLab::ApplianceCatalog.find(old),'Existing model lost')}
puts 'PASS: two full-height doors, opposing hinges, separate vertical handles, independent finish/style/size, save/load and existing products retained.'

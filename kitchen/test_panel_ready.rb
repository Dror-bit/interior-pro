module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
def reject;begin;yield;rescue StandardError;return;end;raise 'Expected rejection';end
s=KitchenLab.validate_settings({'global_finish'=>'sage'},{'shaker_width'=>2.25,'shaker_inset'=>0.25})
engine=KitchenLab::Engine.new(validator:->(d,o){KitchenLab.validate(d,o)},settings_validator:->(r,c){KitchenLab.validate_settings(r,c)})
source=KitchenLab::Document.create(s,[])
ids=%w[det3650ci-r-panelready dw2451-panelready]
ids.each do |id|
 plan=engine.plan(source,[{'type'=>'create_catalog_appliance','payload'=>{'id'=>'test-'+id,'product_id'=>id,'wall'=>'A'}}]);d=plan['document']['cabinets'].first
 check(d['width']==(id.start_with?('dw') ? 24 : 36),'Opening width changed')
 check(d['panel_options'].length==(id.start_with?('dw') ? 1 : 3),'Panels missing')
 d['panel_options'].each_value{|o|check(o['resolved_finish']=='sage'&&o['handle']['overall_length']==12,'Defaults missing')}
 p=d['appliance']['panel_ready'];first=p['panels'].first['panel_id'];options=KitchenLab::PanelReady.copy(d['panel_options'])
 options[first]['finish']='charcoal';options[first]['style']='shaker';options[first]['handle']={'source_asset_id'=>KitchenLab::HandleCatalog.products.find{|v|v['number']==18}['asset_id'],'overall_length'=>18}
 updated=engine.plan(plan['document'],[{'type'=>'update_cabinet','payload'=>{'id'=>d['id'],'changes'=>{'panel_options'=>options}}}])['document'];u=updated['cabinets'].first
 check(u['appliance']==d['appliance'],'Approved snapshot was mutated')
 check(u['panel_options'][first]['handle']['snapshot']['ctc']==17.25,'Overall length confused with screw spacing')
 check(KitchenLab::PanelReady.parts(u).count{|v|v['panel_id']==first&&v['name'].start_with?('Panel ')}==5,'Shaker missing')
 roundtrip=KitchenLab::Document.read(JSON.generate(updated));check(roundtrip==updated,'Saved panel configuration lost')
 opts=KitchenLab::PanelReady.copy(options);opts[first]['handle']['overall_length']=14
 reject{engine.plan(updated,[{'type'=>'update_cabinet','payload'=>{'id'=>d['id'],'changes'=>{'panel_options'=>opts}}}])}
 changed=engine.plan(updated,[{'type'=>'update_settings','payload'=>{'global_finish'=>'oak'}}])['document']['cabinets'].first
 check(changed['panel_options'][first]['resolved_finish']=='charcoal','Independent panel finish changed')
 changed['panel_options'].reject{|key,_|key==first}.each_value{|o|check(o['resolved_finish']=='oak','Kitchen finish not inherited')}
 check(KitchenLab::PanelReady.parts(changed).all?{|b|%w[width depth height].all?{|key|b[key]>0}},'Degenerate projection')
end
KitchenLab::HandleCatalog.products.select{|p|p['ctc']&&p['family']!='Cup Pull'}.each do |p|
 [12,18].each do |length|
  h=KitchenLab::PanelReady.handle_snapshot(p['asset_id'],length)
  check((h['actual_bounds_in'][0][1]-h['actual_bounds_in'][0][0]-length).abs<1e-6,'Incorrect custom pull bounds')
  check((h['mount_points_in'][1][0]-h['mount_points_in'][0][0]-h['ctc']).abs<1e-6,'Incorrect screw coordinates')
 end
end
check(KitchenLab::ApplianceCatalog.products.length==32,'Existing products removed')
puts 'PASS: panel-ready catalog, all panels, independent finish, kitchen inheritance, plain/Shaker projection, 12/18 inch pulls, screw centers, persistence and invalid sizes.'

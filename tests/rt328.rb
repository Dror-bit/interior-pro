require 'json'
root=File.expand_path('../kitchen',__dir__)
%w[kitchen_document kitchen_spatial kitchen_appearance kitchen_engine countertop_materials kitchen_backsplash].each{|f|load File.join(root,f+'.rb')}
check=->(value,message){raise message unless value}
settings={'kitchen_pose'=>{'x'=>0,'y'=>0,'z'=>0,'angle'=>0,'level'=>1},'backsplash'=>{'mode'=>'countertop','height'=>18},'countertop_thickness'=>1.5,'crown_height'=>6}
engine=KitchenLab::Engine.new(validator:->(d,s){d},settings_validator:->(raw,s){s.merge(raw)},ceiling_provider:->(d,s){90})
base={'id'=>'base','kind'=>'doors','wall'=>'A','x'=>0,'z'=>0,'width'=>36,'depth'=>24,'height'=>34.5,'style'=>'slab','finish'=>'ivory','handle'=>'brass'}
upper=base.merge('id'=>'upper','kind'=>'wall','z'=>54,'height'=>36,'depth'=>12)
doc=KitchenLab::Document.create(settings,[base,upper])
changed=engine.plan(doc,[{'type'=>'update_settings','payload'=>{'backsplash'=>{'mode'=>'tile','height'=>20}}}])['document']
u=changed['cabinets'].find{|c|c['id']=='upper'}
check.call(u['z']==56 && u['height']==34,'Upper did not clear backsplash and ceiling')
check.call(doc['cabinets'].last['z']==54,'Planner mutated original document')
same=engine.plan(changed,[{'type'=>'update_settings','payload'=>{'backsplash'=>{'mode'=>'tile','height'=>20}}}])['document']
check.call(same['cabinets']==changed['cabinets'],'Repeated save moved upper again')
thick=engine.plan(doc,[{'type'=>'update_settings','payload'=>{'countertop_thickness'=>2}}])['document']['cabinets'].last
check.call(thick['z']==54.5 && thick['height']==35.5,'Countertop thickness did not move upper')
other=upper.merge('id'=>'other','x'=>100)
no_base=engine.plan(KitchenLab::Document.create(settings,[base,other]),[{'type'=>'update_settings','payload'=>{'backsplash'=>{'mode'=>'tile','height'=>20}}}])['document']
check.call(no_base['cabinets'].last['z']==54,'Unrelated upper moved')
b=KitchenLab::Backsplash
[0,0.0625,0.125,0.1875,0.25,0.375].each{|gap|check.call(b.validate({'mode'=>'tile','grout'=>gap})['grout']==gap,'Grout option rejected')}
cfg=b.validate({'mode'=>'tile','grout'=>0});tiles=b.rectangles(36,36,cfg)
check.call((tiles.sum{|x,z,r,t|(r-x)*(t-z)}-648).abs<0.001,'Zero grout left gaps')
puts 'PASS: upper clearance, ceiling cap, idempotence, document isolation, unrelated uppers, countertop thickness, all tile grout widths and zero grout geometry.'
garage=engine.plan(KitchenLab::Document.create(settings,[]),[{'type'=>'create_cabinet','payload'=>{'kind'=>'appliance_garage'}}])['document']['cabinets'].first
check.call(garage['appliance_garage'] && garage['z']==36 && garage['height']==54,'Garage defaults')
sink=base.merge('id'=>'sink','kind'=>'sink','accessories'=>[{'usage'=>'main','anchor'=>[18,-2,36]},{'usage'=>'pot','anchor'=>[18,0,54]}])
fixture=KitchenLab::Document.create(settings.merge('backsplash'=>{'mode'=>'none'}),[sink,garage.merge('x'=>100)])
result=engine.plan(fixture,[{'type'=>'update_settings','payload'=>{'countertop_thickness'=>2}}])['document']
check.call(result['cabinets'][0]['accessories'].map{|a|a['anchor'][2]}==[36.5,54],'Deck faucet must follow thickness, wall faucet stays')
check.call(result['cabinets'][1]['z']==36.5 && result['cabinets'][1]['height']==53.5,'Garage keeps top height on thickness change')
check.call(fixture['cabinets'][0]['accessories'][0]['anchor'][2]==36,'Accessory source mutated')
puts 'PASS: appliance garage and thickness-following deck accessories, with wall fixture and source isolation.'
require_relative 'sketchup_stub'
require_relative 'electrical_library'
load File.expand_path('../elevation_tool.rb',__dir__)
et=InteriorPro::ElevationTool
out=[]
items=[{kind:'cabinet',a0:0,a1:36,z0:54,z1:90,w:36,name:'upper'},
 {kind:'kitchen_light',a0:1,a1:35,z0:54,z1:90,w:34,name:'LED',shelves:0}]
rows=et.kitchen_dims!(out,items,120,96,->(x){'R'},->(*args){},->(x){x/144.0},->(z){(z+12)/120.0})
lights=out.select{|d|d['g']=='electric'}
check.call(lights.length==2 && rows>=4,'Light length and contractor note need separate rows')
check.call(lights.all?{|d|d['u'].all?{|n|n.is_a?(Numeric)&&n.finite?}},'Light dimensions must have valid coordinates')
puts 'PASS: lighting annotations use electrical layer, separate instruction row and valid PDF coordinates.'

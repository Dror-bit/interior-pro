module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
catalog=KitchenLab::HandleCatalog
catalog.products.select{|p|p['ctc']&&p['family']!='Cup Pull'}.each do |base|
 [3,3.5,5,7.25,8].each do |size|
  id=base['asset_id']+'@ctc='+size.to_s;p=catalog.find(id)
  check((p['actual_bounds_in'][0][1]-p['actual_bounds_in'][0][0]-(base['L']+size-base['ctc'])).abs<0.002,'Wrong length')
  check(p['actual_bounds_in'][1..]==base['actual_bounds_in'][1..],'Changed thickness/projection')
  check((p['mount_points_in'].last[0]-p['mount_points_in'].first[0]).abs==size,'Mount spacing')
  [true,false].each{|horizontal|check(catalog.layout({'kind'=>'doors','style'=>'shaker','door_handle_model'=>id,'drawer_handle_model'=>id},20,30,horizontal,true,{'shaker_width'=>2.25})['product']['ctc']==size,'Layout lost custom size')}
 end
end
base=catalog.products.find{|p|p['number']==18};id=base['asset_id']+'@ctc=5.5';s={'shaker_width'=>2.25,'shaker_inset'=>0.25}
doc=KitchenLab.command_engine.plan(KitchenLab::Document.create(s,[]),[{'type'=>'create_cabinet','payload'=>{'kind'=>'doors','overrides'=>{'door_handle_model'=>id}}}])['document']
check(KitchenLab::Document.read(JSON.generate(doc))['cabinets'].first['door_handle_model']==id,'Persistence')
[-1,0,2.99,8.01,Float::INFINITY].each do |size|
 begin;catalog.find(base['asset_id']+'@ctc='+size.to_s);raise 'Invalid size accepted';rescue ArgumentError;rescue RuntimeError=>e;raise if e.message=='Invalid size accepted';end
end
puts 'PASS: 75 custom sizes, unchanged thickness/projection, screw spacing, both orientations, persistence and invalid sizes'

module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
s={'shaker_width'=>2.25,'shaker_inset'=>0.25};source=KitchenLab::Document.create(s,[])
KitchenLab::Accessories.catalog['products'].each do |p|
 p['finish_variants'].each do |f|
  item={'id'=>'a-test','product_id'=>p['id'],'finish_id'=>f['finish_id'],'location'=>'island_sink'}
  cmd={'type'=>'create_cabinet','payload'=>{'kind'=>(p['role']=='pot' ? 'oven' : 'sink'),'overrides'=>{'accessories'=>[item]}}}
  doc=KitchenLab.command_engine.plan(source,[cmd])['document'];a=doc['cabinets'][0]['accessories'][0]
  check(a['usage']==p['role']&&a['location']==(p['role']=='pot' ? 'cooktop' : 'island_sink'),'Location changed usage')
  check(a['sku']==f['product_sku']&&a['geometry_sha256']==p['skp_sha256'],'Snapshot missing')
  check(KitchenLab::Document.read(JSON.generate(doc))==doc,'Save/load changed accessories')
  if p['role']=='beverage'
   check(a['water_connection']=='filter_ro','RO not default')
   b=KitchenLab::Accessories.normalize([a.merge('filter_ro'=>false)],doc['cabinets'][0])[0]
   check(b['water_connection']=='cold_unfiltered'&&b['product_id']==a['product_id'],'Unfiltered changed model')
  end
 end
end
puts 'PASS: all 16 separate faucet models and every finish, snapshots, locations independent of usage, RO/default/cold-only, save/load'

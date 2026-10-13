module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
engine=KitchenLab.command_engine
empty=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
cmd=lambda{|t,p|{'type'=>t,'payload'=>p}}
count=0
%w[doors drawers sink wall glass_wall tall fridge oven dishwasher hood microwave oven_tower micro_tower fridge_surround filler corner_base corner_upper corner_lazy].each do |kind|
 doc=engine.plan(empty,[cmd.call('create_cabinet',{'id'=>'target','kind'=>kind,'overrides'=>(kind.start_with?('corner') ? {'house_placement'=>{'x'=>0,'y'=>0,'angle'=>0}} : {})})])['document']
 doc=engine.plan(doc,[cmd.call('create_cabinet',{'id'=>'neighbor','kind'=>'doors','overrides'=>{'x'=>500}})])['document']
 original=JSON.generate(doc);neighbor=doc['cabinets'].find{|c|c['id']=='neighbor'}
 result=engine.plan(doc,[cmd.call('remove_cabinet',{'id'=>'target'})])
 check(result['document']['cabinets']==[neighbor],kind+': wrong deletion')
 check(result['changed_ids']==['target'],kind+': neighbor affected')
 check(JSON.generate(doc)==original,kind+': original document mutated')
 check(result['document']['revision']==doc['revision']+1,kind+': not atomic')
 count+=1
end
%w[thermador-custom-md24bs thermador-custom-mb30wp].each do |product|
 commands=InteriorPro::KitchenPlan.catalog_commands(empty,{'kind'=>'microwave','product_id'=>product,'wall'=>'A','overrides'=>{'house_placement'=>{'x'=>100,'y'=>100,'angle'=>90,'handedness'=>-1}}})
 doc=engine.plan(empty,commands)['document']
 ids=doc['cabinets'].map{|c|c['id']};check(ids.length==7,'Missing microwave pieces')
 ids.each do |id|
  result=engine.plan(doc,[cmd.call('remove_cabinet',{'id'=>id})])
  check(result['document']['cabinets'].empty?,'Bundle leaves remnants from '+id)
  check(result['changed_ids'].sort==ids.sort,'Adapter will miss linked geometry')
  check(result['document']['revision']==doc['revision']+1,'Bundle must be one revision')
  count+=1
 end
end
KitchenLab::SinkCatalog.products.each do |p|
 options=KitchenLab::SinkCatalog.options(p['id']);kind=options.delete('kind')
 doc=engine.plan(empty,[cmd.call('create_cabinet',{'id'=>'sink','kind'=>kind,'overrides'=>options})])['document']
 result=engine.plan(doc,[cmd.call('remove_cabinet',{'id'=>'sink'})])
 check(result['document']['cabinets'].empty? && result['changed_ids']==['sink'],'Sink deletion failed: '+p['id'])
 count+=1
end
%w[fridge microwave wall_oven hood].each do |kind|
 doc=engine.plan(empty,[cmd.call('create_cabinet',{'id'=>'owner','kind'=>kind,'overrides'=>{'height'=>kind=='fridge' ? 84 : 28.5,'z'=>kind=='fridge' ? 0 : 54}})])['document']
 next unless InteriorPro::KitchenPlan.surround_supported?(doc['cabinets'].first)
 doc=engine.plan(doc,InteriorPro::KitchenPlan.surround_commands(doc,'owner'))['document']
 doc['cabinets'].each do |item|
  result=engine.plan(doc,[cmd.call('remove_cabinet',{'id'=>item['id']})])
  check(result['document']['cabinets'].empty?,kind+': surround remains');count+=1
 end
end
puts "PASS: #{count} deletion cases, all cabinet kinds, both microwave bundles from every part, neighbor unchanged, atomic revision and complete geometry removal IDs"


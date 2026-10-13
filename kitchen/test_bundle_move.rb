module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
engine=KitchenLab.command_engine;s={'shaker_width'=>2.25,'shaker_inset'=>0.25};empty=KitchenLab::Document.create(s,[]);count=0
%w[thermador-custom-md24bs thermador-custom-mb30wp].each do |product|
 [0,90,180].each do |angle|
  [-1,1].each do |handedness|
   commands=InteriorPro::KitchenPlan.catalog_commands(empty,{'kind'=>'microwave','product_id'=>product,'wall'=>'A','overrides'=>{'house_placement'=>{'x'=>100,'y'=>100,'angle'=>angle,'handedness'=>handedness}}})
   doc=engine.plan(empty,commands)['document']
   doc['cabinets'].each do |selected|
    p=selected['house_placement'];changes={'house_placement'=>p.merge('x'=>p['x']+100,'y'=>p['y']+80,'angle'=>p['angle']+90)}
    result=engine.plan(doc,[{'type'=>'update_cabinet','payload'=>{'id'=>selected['id'],'changes'=>changes}}]);next_doc=result['document']
    check(result['changed_ids'].sort==doc['cabinets'].map{|c|c['id']}.sort,'A part did not move')
    check(next_doc['revision']==doc['revision']+1,'Not one operation')
    centers=lambda{|d|d['cabinets'].map{|c|KitchenLab::Spatial.cabinet_point(c,c['width']/2,-c['depth']/2,s)}}
    before=centers.call(doc);after=centers.call(next_doc)
    before.each_index do |i|;before.each_index do |j|
     dist=lambda{|a,b|Math.hypot(a[0]-b[0],a[1]-b[1])}
     check((dist.call(before[i],before[j])-dist.call(after[i],after[j])).abs<1e-6,'Assembly stretched')
    end;end
    count+=1
   end
  end
 end
end
puts "PASS: #{count} bundle moves from every microwave part, rotations, mirrored placements, rigid distances, atomic revisions"
%w[fridge microwave wall_oven].each do |kind|
 doc=engine.plan(empty,[{'type'=>'create_cabinet','payload'=>{'id'=>'owner','kind'=>kind,'overrides'=>{'height'=>kind=='fridge' ? 84 : 28.5,'z'=>kind=='fridge' ? 0 : 54}}}])['document']
 doc=engine.plan(doc,InteriorPro::KitchenPlan.surround_commands(doc,'owner'))['document']
 doc['cabinets'].each do |part|
  result=engine.plan(doc,[{'type'=>'update_cabinet','payload'=>{'id'=>part['id'],'changes'=>{'x'=>part['x']+100,'z'=>part['z']+10}}}])
  check(result['changed_ids'].size==doc['cabinets'].size,kind+': partial movement')
 end
end
%w[doors drawers sink wall tall filler corner_base corner_upper corner_lazy].each do |kind|
 doc=engine.plan(empty,[{'type'=>'create_cabinet','payload'=>{'id'=>'single','kind'=>kind,'overrides'=>{'house_placement'=>{'x'=>0,'y'=>0,'angle'=>0}}}}])['document']
 result=engine.plan(doc,[{'type'=>'update_cabinet','payload'=>{'id'=>'single','changes'=>{'house_placement'=>{'x'=>80,'y'=>80,'angle'=>90}}}}])
 check(result['changed_ids']==['single'],kind+': single movement regressed')
end
puts 'PASS: refrigerator, wall oven and upper microwave surrounds from every part; standalone cabinets, sinks and corners'

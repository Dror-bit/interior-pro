module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def assert_replace(v,m);raise m unless v;end
engine=KitchenLab.command_engine
empty=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
source=engine.plan(empty,[{'type'=>'create_cabinet','payload'=>{'id'=>'original','kind'=>'doors','overrides'=>{'width'=>36,'house_placement'=>{'x'=>100,'y'=>100,'angle'=>90,'handedness'=>-1}}}}])['document']
old=source['cabinets'].first
%w[doors drawers wall glass_wall tall filler corner_base corner_upper corner_lazy].each do |kind|
  plan=engine.plan(source,[{'type'=>'replace_cabinet','payload'=>{'id'=>'original','kind'=>kind}}],expected_revision:source['revision'])
  c=plan['document']['cabinets'].first
  assert_replace(c['kind']==(kind=='glass_wall' ? 'wall' : kind),'Wrong replacement kind')
  %w[id width height depth x z rotation house_placement].each{|k|assert_replace(c[k]==old[k],"Lost #{k}")}
  assert_replace(source['cabinets'].first==old,'Mutated original document')
  assert_replace(KitchenLab::Document.read(JSON.generate(plan['document']))==plan['document'],'Save round trip changed replacement')
end
sink=engine.plan(empty,[{'type'=>'create_catalog_appliance','payload'=>{'id'=>'sink','product_id'=>'kohler-k-5285'}}])['document']
plan=engine.plan(sink,[{'type'=>'replace_cabinet','payload'=>{'id'=>'sink','kind'=>'drawers'}}])
c=plan['document']['cabinets'].first
assert_replace(!c['sink']&&!c['appliance']&&!c['accessories'],'Retained obsolete sink attachments')
assert_replace(plan['document']['revision']==sink['revision']+1,'Replacement is not one revision')
assert_replace(plan['changed_ids']==['sink'],'Changed unrelated IDs')
assert_replace(KitchenLab.front_rows(c).all?{|r|r['kind']=='drawer'},'Old front layout retained')
begin
  engine.plan(source,[{'type'=>'replace_cabinet','payload'=>{'id'=>'original','kind'=>'sink'}}])
  raise 'Prototype sink accepted'
rescue RuntimeError=>e
  raise unless e.message.include?('replacement list')
end
puts 'PASS: replacement types, stable placement/identity, clean attachments, drawer fronts, persistence, revision and legacy sink exclusion'

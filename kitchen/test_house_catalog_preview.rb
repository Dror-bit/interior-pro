module Sketchup;class ModelObserver;end;end
load File.join(__dir__,'kitchen_lab.rb')
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
source=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
original=JSON.generate(source)
%w[doors drawers sink wall glass_wall tall oven_tower micro_tower fridge_surround filler fridge oven dishwasher hood microwave corner_base corner_lazy corner_upper].each do |kind|
 payload={'kind'=>kind,'wall'=>'A'}
 preview=InteriorPro::KitchenPlan.catalog_preview(source,payload)
 check(JSON.generate(source)==original,'Preview mutated source')
 h={'x'=>45,'y'=>-70,'angle'=>90,'handedness'=>1}
 payload['overrides']={'x'=>0,'house_placement'=>h}
 expected=InteriorPro::KitchenPlan.catalog_preview(source,payload)
 plan=KitchenLab.command_engine.plan(source,[{'type'=>'create_cabinet','payload'=>payload}],expected_revision:0)
 actual=plan['document']['cabinets'].first
 check(actual.reject{|k,_|k=='id'}==expected.reject{|k,_|k=='id'},"Preview differs from create: #{kind}")
 check(preview.values_at('width','height','depth')==actual.values_at('width','height','depth'),'Dimensions changed')
 check(plan['document']['revision']==1,'Wrong revision')
 check(actual['house_placement']==h,'Position not retained')
end
puts 'PASS: all 18 catalog types share preview/create dimensions and data; preview is read-only; world placement persists.'

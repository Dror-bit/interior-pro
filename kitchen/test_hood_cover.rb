module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
s=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
engine=KitchenLab.command_engine
%w[thermador-custom-vcin36gws thermador-custom-vcin48gws].each do |id|
 %w[slab shaker].each do |style|
  [0,90,180,270].each do |angle|
   payload={'product_id'=>id,'kind'=>'hood','wall'=>'A','overrides'=>{'x'=>0,'house_placement'=>{'x'=>120,'y'=>150,'angle'=>angle,'handedness'=>-1}}}
   commands=InteriorPro::KitchenPlan.catalog_commands(s,payload,false,style)
   rows=engine.plan(s,commands)['document']['cabinets'];hood=rows.first;parts=rows.drop(1)
   check(parts.map{|p|p['surround_part']}.sort==%w[hood_front left right],'Unexpected doors/shelves')
   front=parts.find{|p|p['surround_part']=='hood_front'}
   check(front['style']==style&&front['handle']=='none','Wrong finish style or handles')
   check(front['height']==30&&front['z']==hood['z'],'Front does not cover full casing height')
   check(front['depth']==0.75,'Front panel not 3/4 inch')
   check(parts.all?{|p|p['z']==hood['z']},'Intake blocked by bottom shelf')
   check(parts.reject{|p|p==front}.all?{|p|p['depth']>=hood['depth']+1},'Side panels stop behind the front')
   check(!rows.combination(2).any?{|a,b|KitchenLab::Spatial.overlap?(a,b,s['settings'])},'Casing overlaps hood')
  end
 end
end
puts 'PASS: plain/Shaker continuous hood fronts, no doors/handles/shelves, open intake, rotated non-overlap.'

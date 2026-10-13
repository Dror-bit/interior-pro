module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
source=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
%w[thermador-custom-md24bs thermador-custom-mb30wp].each do |id|
  [0,90,180,-90].each do |angle|
    payload={'kind'=>'microwave','product_id'=>id,'wall'=>'A','overrides'=>{'x'=>0,'house_placement'=>{'x'=>100,'y'=>100,'angle'=>angle,'handedness'=>-1}}}
    commands=InteriorPro::KitchenPlan.catalog_commands(source,payload)
    result=KitchenLab.command_engine.plan(source,commands)
    all=result['document']['cabinets'];appliance=all.first
    check(all.size==7,'Expected appliance and six base parts')
    check(result['document']['revision']==1,'Bundle must be one revision')
    drawer=all.find{|c|c['surround_part']=='lower'}
    check(KitchenLab.front_rows(drawer).all?{|r|r['kind']=='drawer'},'Lower storage is not a drawer')
    check(drawer['front_overlay']==0.75,'Drawer must cover both outer sides')
    check(drawer['z']==4,'Missing toe space')
    check(drawer['depth']==24,'Base depth does not match adjacent cabinets')
    check(all.select{|c|%w[left right].include?(c['surround_part'])}.all?{|c|c['toe_height']==4 && c['toe_setback']==3 && c['depth']==24},'Missing notched sides')
    offset=KitchenLab::ApplianceAssets.offset(appliance)[1]
    body=appliance.dig('appliance','appearance','cabinet_depth')
    check((offset-body+24).abs<0.001,'Microwave body front not flush')
    check((appliance['z']+appliance['height']-33.5).abs<0.001,'Microwave is not beneath countertop')
    check(all.select{|c|%w[left right].include?(c['surround_part'])}.all?{|c|c['z']==0&&c['height']==34.5},'Wrong base height')
    check(InteriorPro::KitchenPlan.catalog_commands(source,payload,true).size==1,'Bare checkbox ignored')
    preview=InteriorPro::KitchenPlan.catalog_bundle_preview(source,payload,false,1)
    check(preview['parts'].size==7 && preview['row']['base_z']==0,'Incomplete placement preview')
    check(KitchenLab::ApplianceAssets.manifest(appliance['appliance'])['version']==2,'Prepared model missing')
  end
end
puts 'PASS: both prepared microwaves, lower drawers, toe space, base heights, four rotations/reflection, one operation and bare option'

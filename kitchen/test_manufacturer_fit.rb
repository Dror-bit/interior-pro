module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
def KitchenLab.settings;{'countertop_thickness'=>1.5};end
s={'shaker_width'=>2.25,'shaker_inset'=>0.25}
engine=KitchenLab.command_engine
KitchenLab::InstallationFit.profiles.each do |id,f|
 [0,37,90,180].each do |angle|
  [-1,1].each do |hand|
   source=KitchenLab::Document.create(s,[])
   payload={'product_id'=>id,'wall'=>'A','overrides'=>{'x'=>0,'z'=>id.start_with?('lg-w') ? 28 : 40,'house_placement'=>{'x'=>150,'y'=>200,'angle'=>angle,'handedness'=>hand}}}
   payload['overrides'].delete('z') if f['mode']=='over_range'
   cmds=InteriorPro::KitchenPlan.catalog_commands(source,payload,false)
   doc=engine.plan(source,cmds)['document'];d=doc['cabinets'].first;parts=doc['cabinets'].drop(1)
   check(d['manufacturer_fit']==1,'Fit snapshot missing')
   check(doc==KitchenLab::Document.read(JSON.generate(doc)),'Roundtrip changed')
   check(!doc['cabinets'].combination(2).any?{|a,b|KitchenLab::Spatial.overlap?(a,b,s)},'Intersecting parts '+id)
   left=parts.find{|p|p['surround_part']=='left'};right=parts.find{|p|p['surround_part']=='right'}
   check(left['depth']==f['cabinet_depth'],'Depth wrong')
   if f['mode']=='over_range'
    check(left['z']==d['z'] && left['height']+left['z']==90,'Sides not continuous')
    check(parts.none?{|p|p['surround_part']=='bottom'},'Bottom vent blocked')
   else
    check(parts.any?{|p|p['surround_part']=='plinth' && p['height']==4},'Toe kick missing')
    check(parts.find{|p|p['surround_part']=='lower'}['handle_position']=='top','Wrong lower handle')
   end
   if id=='lg-mser2090s'
    trim=KitchenLab::InstallationFit.parts(d).select{|p|p['name'].start_with?('MK2030NST')}
    check(trim.length==4 && trim.all?{|p|p['name'].start_with?('MK2030NST')},'Missing trim')
   end
   moved=engine.plan(doc,[{'type'=>'update_cabinet','payload'=>{'id'=>d['id'],'changes'=>{'house_placement'=>d['house_placement'].merge('x'=>d['house_placement']['x']+20)}}}])['document']
   check(moved['cabinets'].length==doc['cabinets'].length,'Move lost parts')
   deleted=engine.plan(moved,[{'type'=>'remove_cabinet','payload'=>{'id'=>d['id']}}])['document']
   check(deleted['cabinets'].empty?,'Delete left orphan')
  end
 end
 puts "PASS #{id}: gallery, rotated/reflected fit, toe, handles, trim, move, delete, persistence"
end
puts 'PASS manufacturer installation profiles'

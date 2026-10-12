module Sketchup;class ModelObserver;end;end
load File.join(__dir__,'kitchen_lab.rb')
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
def reject(m);begin;yield;rescue StandardError;return;end;raise m;end
s={'shaker_width'=>2.25,'shaker_inset'=>0.25}
engine=KitchenLab.command_engine
doc=engine.plan(KitchenLab::Document.create(s,[]),[{'type'=>'create_cabinet','payload'=>{'id'=>'base'}}])['document']
h={'x'=>100,'y'=>-50,'angle'=>90,'handedness'=>1,'wall_id'=>'east','face'=>3,'along'=>70}
command={'type'=>'update_cabinet','payload'=>{'id'=>'base','changes'=>{'house_placement'=>h}}}
result=engine.plan(doc,[command],expected_revision:1)
c=result['document']['cabinets'].first
check(c['house_placement']==h,'Attachment stripped by validation')
check(!doc['cabinets'].first.key?('house_placement'),'Input mutated')
a=KitchenLab::Spatial.cabinet_point(c,0,0,s);b=KitchenLab::Spatial.cabinet_point(c,36,-24,s)
check((a[0]-100).abs<1e-8 && (a[1]+50).abs<1e-8,'World origin')
check((b[0]-124).abs<1e-8 && (b[1]+14).abs<1e-8,'Rotated world basis')
wall={'id'=>'east','sx'=>100,'sy'=>-120,'ex'=>100,'ey'=>0,'corners'=>[100,-120,104,-120,104,0,100,0],'ops'=>[]}
c=c.merge('house_placement'=>{'x'=>100,'y'=>-70,'angle'=>-90,'handedness'=>1,'wall_id'=>'east','face'=>3,'along'=>88})
# Left-facing cabinet: back center is (100,-88), measured downward from face start (100,0).
check(InteriorPro::KitchenPlan.validate_house_placement!(c,s,[wall]),'Valid attachment rejected')
window=wall.merge('ops'=>[[32,40]],'kitchen_openings'=>[[32,40,36,84,'window']])
check(InteriorPro::KitchenPlan.validate_house_placement!(c,s,[window]),'Cabinet under window rejected')
check(InteriorPro::KitchenPlan.validate_house_placement!(c.merge('height'=>36),s,[window]),'Exact sill fit rejected')
begin
  InteriorPro::KitchenPlan.validate_house_placement!(c.merge('height'=>37),s,[window])
  raise 'Low window accepted'
rescue StandardError=>error
  check(error.message=='Window is too low for this cabinet.','Wrong low-window message')
end
reject('Door accepted'){InteriorPro::KitchenPlan.validate_house_placement!(c,s,[window.merge('kitchen_openings'=>[[32,40,0,84,'door']])])}
check(InteriorPro::KitchenPlan.validate_house_placement!(c.merge('z'=>84),s,[window]),'Cabinet above opening rejected')
reject('Wall penetration accepted'){InteriorPro::KitchenPlan.validate_house_placement!(c.merge('house_placement'=>h.reject{|k,_| %w[wall_id face along].include?(k)}),s,[wall])}
reject('NaN accepted'){KitchenLab.validate(c.merge('house_placement'=>h.merge('x'=>Float::NAN)),s)}
reject('Stale command accepted'){engine.plan(doc,[command],expected_revision:0)}
puts 'PASS: persistent house placement, real validation, source immutability, world rotation, wall penetration and stale-revision rejection.'
corner=KitchenLab.validate({'id'=>'corner-check','kind'=>'corner_base','wall'=>'A','x'=>0,'z'=>0,'width'=>36,'height'=>34.5,'depth'=>24,'house_placement'=>{'x'=>0,'y'=>0,'angle'=>0,'handedness'=>1,'wall_id'=>'north','face'=>0,'along'=>18}},s)
north={'id'=>'north','sx'=>0,'sy'=>0,'ex'=>200,'ey'=>0,'corners'=>[0,0,200,0,200,4,0,4],'ops'=>[]}
west={'id'=>'west','sx'=>0,'sy'=>-200,'ex'=>0,'ey'=>0,'corners'=>[-4,-200,0,-200,0,0,-4,0],'ops'=>[]}
check(InteriorPro::KitchenPlan.validate_house_placement!(corner,s,[north,west]),'Two-wall corner rejected')
reject('Second wall door ignored'){InteriorPro::KitchenPlan.validate_house_placement!(corner,s,[north,west.merge('kitchen_openings'=>[[182,30,0,84,'door']])])}
check(InteriorPro::KitchenPlan.validate_house_placement!(corner,s,[north,west.merge('kitchen_openings'=>[[182,30,36,84,'window']])]),'Second wall high window rejected')
puts 'PASS: two-wall corner commit validation, second-wall door blocking and window clearance.'

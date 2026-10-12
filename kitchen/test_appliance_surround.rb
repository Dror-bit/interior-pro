module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
def reject(message)
  begin;yield;rescue StandardError=>e;return if e.message.include?(message);raise;end
  raise 'Expected rejection: '+message
end
s={'shaker_width'=>2.25,'shaker_inset'=>0.25}
engine=KitchenLab.command_engine
[0,90,180,270,37].each do |angle|
 [-1,1].each do |hand|
  %w[fridge microwave wall_oven].each do |kind|
   source=engine.plan(KitchenLab::Document.create(s,[]),[{'type'=>'create_cabinet','payload'=>{'id'=>'appliance','kind'=>kind,'overrides'=>{'height'=>kind=='fridge' ? 84 : kind=='wall_oven' ? 28.5 : 18,'z'=>kind=='fridge' ? 0 : kind=='wall_oven' ? 28 : 54,'house_placement'=>{'x'=>200,'y'=>150,'angle'=>angle,'handedness'=>hand}}}}])['document']
   before=JSON.generate(source)
   commands=InteriorPro::KitchenPlan.surround_commands(source,'appliance')
   result=engine.plan(source,commands,expected_revision:source['revision'])['document']
   check(JSON.generate(source)==before,'Planner mutated original document')
   check(result['revision']==source['revision']+1,'Surround not a single revision')
   check(result['cabinets'].first==source['cabinets'].first,'Appliance changed')
   pieces=result['cabinets'].drop(1)
   check(pieces.length==(kind=='fridge' ? 3 : kind=='wall_oven' ? 5 : 4),'Wrong piece count')
   check(pieces.all? { |c| c['surround_for']=='appliance' },'Link lost in validation')
   check(!result['cabinets'].combination(2).any? { |a,b| KitchenLab::Spatial.overlap?(a,b,s) },'Surround intersects appliance')
   left=pieces.find { |c| c['surround_part']=='left' }
   expected=KitchenLab::Spatial.cabinet_point(source['cabinets'].first,-1,0,s)
   actual=KitchenLab::Spatial.cabinet_point(left,0,0,s)
   check(expected.zip(actual).all? { |a,b| (a-b).abs<0.00001 },'Wrong rotated side position')
   reject('already has'){InteriorPro::KitchenPlan.surround_commands(result,'appliance')}
   reject('Invalid side gap'){InteriorPro::KitchenPlan.surround_commands(source,'appliance',{'side_gap'=>-1})}
   if kind=='fridge'
    reject('8.25'){InteriorPro::KitchenPlan.surround_commands(source,'appliance',{'total_height'=>90})}
   else
    check(pieces.find { |c| c['surround_part']=='bottom' }['height']==0.75,'Microwave shelf thickness wrong')
   end
  end
 end
end
class SurroundDialog
 attr_reader :callbacks,:scripts
 def initialize;@callbacks={};@scripts=[];end
 def add_action_callback(name,&b);@callbacks[name]=b;end
 def execute_script(s);@scripts<<s;end
end
module KitchenLab
 class << self;attr_accessor :test_source,:test_request;end
 def self.guard!;end
 def self.document;test_source;end
 def self.execute_commands(request,*);self.test_request=request;end
end
KitchenLab.test_source=engine.plan(KitchenLab::Document.create(s,[]),[{'type'=>'create_cabinet','payload'=>{'id'=>'fridge','kind'=>'fridge','overrides'=>{'house_placement'=>{'x'=>0,'y'=>0,'angle'=>0}}}}])['document']
InteriorPro::KitchenPlan.define_singleton_method(:walls_payload){[]}
dlg=SurroundDialog.new;InteriorPro::KitchenPlan.bind_surround(dlg)
request={'id'=>'fridge','revision'=>KitchenLab.document['revision']}
dlg.callbacks['kitchen_add_surround'].call(nil,JSON.generate(request))
check(KitchenLab.test_request['commands'].length==3,'Creation was not one batch')
KitchenLab.test_request=nil
dlg.callbacks['kitchen_add_surround'].call(nil,JSON.generate(request.merge('revision'=>-1)))
check(KitchenLab.test_request.nil? && dlg.scripts.last.include?('Kitchen changed'),'Stale surround accepted')
InteriorPro::KitchenPlan.define_singleton_method(:validate_house_placement!){|*_|raise 'Window is too low for this cabinet.'}
dlg.callbacks['kitchen_add_surround'].call(nil,JSON.generate(request))
check(KitchenLab.test_request.nil? && dlg.scripts.last.include?('Window is too low'),'Blocked surround partially committed')
puts 'PASS: fridge/microwave surrounds, rotated/reflected alignment, non-overlap, atomic batch, stale/duplicate/window rejection.'

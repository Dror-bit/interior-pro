# Real production validation, stubbed only at the SketchUp class boundary.
module Sketchup;class ModelObserver;end;end
load File.join(__dir__,'kitchen_lab.rb')
def assert(value,message);raise message unless value;end
def rejects(message)
  begin;yield;rescue StandardError;return;end
  raise message
end
s={'shaker_width'=>2.25,'shaker_inset'=>0.25}
doc=KitchenLab::Document.create(s,[])
engine=KitchenLab.command_engine
def command(type,payload={});{'type'=>type,'payload'=>payload};end
result=engine.plan(doc,[command('create_base_cabinet',{'id'=>'base'})])
base=result['document']['cabinets'].first
assert(base['width']==36 && base['height']==34.5,'Base defaults')
assert(doc['cabinets'].empty? && doc['revision']==0,'Planning mutated input')
assert(result['document']['revision']==1,'Batch revision')
doc=result['document']
result=engine.plan(doc,[command('create_wall_cabinet',{'id'=>'wall'})])
upper=result['document']['cabinets'].last
assert(upper['x']==0 && upper['z']==54 && upper['depth']==12,'Upper free placement')
%w[drawers sink tall glass_wall fridge oven dishwasher hood microwave oven_tower micro_tower fridge_surround filler].each do |kind|
  r=engine.plan(KitchenLab::Document.create(s,[]),[command('create_cabinet',{'kind'=>kind,'id'=>kind.tr('_','-')})])
  assert(r['changed_ids'].length==1,"Catalog #{kind}")
end
rejects('Stale revision accepted') { engine.plan(doc,[command('remove_cabinet',{'id'=>'base'})],expected_revision:0) }
rejects('Duplicate ID accepted') { engine.plan(doc,[command('create_base_cabinet',{'id'=>'base'})]) }
rejects('Missing cabinet recreated') { engine.plan(doc,[command('update_cabinet',{'id'=>'gone','changes'=>{'width'=>30}})]) }
rejects('Invalid dimensions accepted') { engine.plan(doc,[command('change_width',{'id'=>'base','value'=>-1})]) }
rejects('Overlapping batch accepted') { engine.plan(doc,[command('create_base_cabinet',{'id'=>'other','overrides'=>{'x'=>0}})]) }
pair=engine.plan(doc,[command('create_base_cabinet',{'id'=>'other'})])['document']
swap=engine.plan(pair,[command('update_cabinet',{'id'=>'base','changes'=>{'x'=>36}}),command('update_cabinet',{'id'=>'other','changes'=>{'x'=>0}})])
assert(swap['changed_ids'].sort==%w[base other],'Atomic swap')
assert(swap['document']['revision']==pair['revision']+1,'One revision per batch')
same=engine.plan(doc,[command('change_width',{'id'=>'base','value'=>36})])
assert(same['changed_ids'].empty? && same['document']['revision']==doc['revision'],'No-op revision')
bad_batch=[command('remove_cabinet',{'id'=>'base'}),command('change_height',{'id'=>'gone','value'=>40})]
snapshot=JSON.generate(doc)
rejects('Invalid batch accepted') { engine.plan(doc,bad_batch) }
assert(JSON.generate(doc)==snapshot,'Failed batch mutated source')
styled=KitchenLab::Document.create(s.merge('global_finish'=>'sage','global_handle_type'=>'none'),[])
c=engine.plan(styled,[command('create_base_cabinet',{'overrides'=>{'width'=>30}})])['document']['cabinets'].first
assert(c['finish']=='sage' && c['handle']=='none' && c['width']==30,'Global creation defaults + overrides')
puts 'PASS: command planning, production validation, all catalog defaults, revisions, atomicity, collisions and overrides'

# Exercise the production transaction adapter against a fault-injecting model.
class FakeKitchenModel
  attr_reader :events
  def initialize;@events=[];end
  def start_operation(*);@events<<:start;@snapshot=Marshal.dump(KitchenLab.test_doc);end
  def commit_operation;@events<<:commit;end
  def abort_operation;@events<<:abort;KitchenLab.test_doc=Marshal.load(@snapshot);end
end
module KitchenLab
  class << self;attr_accessor :test_doc,:fail_build;end
  def self.guard!;end
  def self.document;test_doc;end
  def self.write_document!(data,options);self.test_doc=Document.create(options,data,test_doc['revision']+1);end
  def self.cabinets;[];end
  def self.build(d);raise 'Injected geometry failure' if fail_build;end
  def self.worktops!;end
  def self.publish(*);end
end
model=FakeKitchenModel.new
KitchenLab.instance_variable_set(:@model,model)
KitchenLab.test_doc=doc
request={'expected_revision'=>doc['revision'],'commands'=>[command('change_width',{'id'=>'base','value'=>30})]}
KitchenLab.execute_commands(request)
assert(model.events==[:start,:commit],'Adapter must use one operation')
saved=JSON.generate(KitchenLab.test_doc)
rejects('Adapter accepted stale request') { KitchenLab.execute_commands(request) }
assert(model.events==[:start,:commit],'Stale request opened transaction')
KitchenLab.fail_build=true
rejects('Build failure swallowed') { KitchenLab.execute_commands({'commands'=>[command('change_width',{'id'=>'base','value'=>24})]}) }
assert(model.events.last==:abort && JSON.generate(KitchenLab.test_doc)==saved,'Failed build did not roll back source')
puts 'PASS: adapter transaction ownership, stale request rejection and rollback on geometry failure (model double)'

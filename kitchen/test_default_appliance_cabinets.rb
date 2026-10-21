module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
source=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
engine=KitchenLab.command_engine
count=0
KitchenLab::ApplianceCatalog.products.each do |product|
 next unless %w[fridge microwave wall_oven hood].include?(product['category'])
 supported=InteriorPro::KitchenPlan.surround_supported?({'kind'=>product['category'],'appliance'=>product})
 [false,true].each do |without|
  payload={'product_id'=>product['id'],'kind'=>product['category'],'wall'=>'A','overrides'=>{'x'=>0,'house_placement'=>{'x'=>100,'y'=>200,'angle'=>90,'handedness'=>-1}}}
  commands=InteriorPro::KitchenPlan.catalog_commands(source,payload,without)
  plan=engine.plan(source,commands)
  check(plan['document']['revision']==source['revision']+1,'More than one revision')
  check((commands.length>1)==(supported&&!without),'Incorrect default/opt-out for '+product['id'])
  appliance=plan['document']['cabinets'].first
  check(appliance.dig('appliance','id')==product['id'],'Product identity changed')
  check(plan['document']['cabinets'].drop(1).all?{|c|c['surround_for']==appliance['id']},'Broken surround link')
  bundle=InteriorPro::KitchenPlan.catalog_bundle_preview(source,payload,without,1)
  if supported&&!without
   expected_width=product['installation_fit'] ? product['installation_fit']['opening_width']+1.5 : appliance['width']+2
   check((bundle['row']['cabinet']['width']-expected_width).abs<0.00001,'Preview omits side panels')
   check(bundle['parts'].length==commands.length,'Preview omits cabinet parts')
  else
   check(bundle['parts'].nil?,'Bare/chimney appliance received cabinet preview')
  end
  count+=1
 end
end
class DefaultDialog
 attr_reader :callbacks,:scripts
 def initialize;@callbacks={};@scripts=[];end
 def add_action_callback(n,&b);@callbacks[n]=b;end
 def execute_script(s);@scripts<<s;end
end
module KitchenLab
 class << self;attr_accessor :test_source,:test_request;end
 def self.guard!;end
 def self.document;test_source;end
 def self.execute_commands(r,*);self.test_request=r;end
end
KitchenLab.test_source=source
InteriorPro::KitchenPlan.define_singleton_method(:walls_payload){[]}
InteriorPro::KitchenPlan.define_singleton_method(:push){|_|}
dlg=DefaultDialog.new;InteriorPro::KitchenPlan.bind_catalog(dlg)
id=KitchenLab::ApplianceCatalog.products.find{|p|p['category']=='fridge'}['id']
request={'action'=>'place','product_id'=>id,'revision'=>source['revision'],'wall_token'=>Digest::SHA256.hexdigest('[]'),'placement'=>{'x'=>100,'y'=>200,'angle'=>90,'handedness'=>1}}
dlg.callbacks['kitchen_open_catalog'].call(nil,JSON.generate(request))
check(KitchenLab.test_request && KitchenLab.test_request['commands'].length==4,'Default placement was not one full batch')
position=KitchenLab.test_request['commands'].first['payload']['overrides']['house_placement']
check((position['x']-100).abs<0.00001&&(position['y']-201).abs<0.00001,'Appliance not inset inside rotated enclosure')
KitchenLab.test_request=nil
dlg.callbacks['kitchen_open_catalog'].call(nil,JSON.generate(request.merge('without_cabinet'=>true)))
check(KitchenLab.test_request['commands'].length==1,'Opt-out created surround')
KitchenLab.test_request=nil
InteriorPro::KitchenPlan.define_singleton_method(:validate_house_placement!) { |cab,*_|raise 'Surround blocked' if cab['surround_for'] }
dlg.callbacks['kitchen_open_catalog'].call(nil,JSON.generate(request))
check(KitchenLab.test_request.nil?&&dlg.scripts.last.include?('Surround blocked'),'Blocked surround left a bare appliance')
puts "PASS: #{count} product/option combinations, full previews, chimney exclusion, rotated inset and atomic placement/rejection."

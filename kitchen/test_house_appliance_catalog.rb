module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(value,message);raise message unless value;end
source=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
check(KitchenLab::ApplianceCatalog.products.all? { |p| p['manufacturer']=='Thermador' },'Retired brand is still offered')
retired={'schema_version'=>1,'id'=>'bosch-shp78cm5n','brand'=>'Bosch','manufacturer'=>'Bosch','model'=>'SHP78CM5N','name'=>'Saved dishwasher','category'=>'dishwasher','dimensions'=>{'width'=>24,'height'=>34.5,'depth'=>24},'asset'=>{'id'=>'bosch-shp78cm5n','version'=>1,'manifest_sha256'=>'retired'}}
check(KitchenLab::ApplianceAssets.manifest(retired).nil?,'Retired snapshot cannot open without removed files')
saved=KitchenLab.validate({'id'=>'saved-old','kind'=>'dishwasher','appliance'=>retired,'width'=>24,'height'=>34.5,'depth'=>24},source['settings'])
check(!KitchenLab::ApplianceCatalog.parts(saved).empty?,'Saved retired appliance has no fallback geometry')
pose={'x'=>45,'y'=>-70,'angle'=>90,'handedness'=>1}
KitchenLab::ApplianceCatalog.products.each do |product|
 payload={'product_id'=>product['id'],'wall'=>'A','overrides'=>{'x'=>0,'house_placement'=>pose}}
 preview=InteriorPro::KitchenPlan.catalog_preview(source,payload)
 actual=KitchenLab.command_engine.plan(source,[{'type'=>'create_catalog_appliance','payload'=>payload}])['document']['cabinets'].first
 check(preview.reject{|k,_|k=='id'}==actual.reject{|k,_|k=='id'},"Preview/create differ: #{product['id']}")
 check(actual['house_placement']==pose,'Placement lost')
 check(actual.dig('appliance','id')==product['id'],'Product lost')
end
%w[sgs305ts sgs365ts].each do |sku|
 c=InteriorPro::KitchenPlan.catalog_preview(source,{'product_id'=>'thermador-custom-'+sku})
 data=KitchenLab::ApplianceAssets.manifest(c['appliance'])
 offset=KitchenLab::ApplianceAssets.offset(c)
 check((offset[2]+data['mounting_deck_z']-c['height']-1.5).abs<0.0001,'Cooktop deck is not on countertop')
 check((offset[2]+data['origin'][2]*-1-c['height']-1.5).abs<0.0001,'SKP native deck differs')
end
class ApplianceDialog
 attr_reader :callbacks,:scripts
 def initialize;@callbacks={};@scripts=[];end
 def add_action_callback(name,&block);@callbacks[name]=block;end
 def execute_script(script);@scripts<<script;end
end
module KitchenLab
 class << self;attr_accessor :test_source,:test_commands;end
 def self.guard!;end
 def self.document;test_source;end
 def self.execute_commands(request,*);self.test_commands=request;end
end
KitchenLab.test_source=source
InteriorPro::KitchenPlan.define_singleton_method(:walls_payload){[]}
InteriorPro::KitchenPlan.define_singleton_method(:push){|_|}
dlg=ApplianceDialog.new;InteriorPro::KitchenPlan.bind_catalog(dlg)
dlg.callbacks['kitchen_appliance_library'].call(nil,'hood')
check(dlg.scripts.last.include?('thermador-custom-vcin48gws'),'New hood missing')
check(dlg.scripts.last.include?('data:image/png;base64,'),'Local thumbnails missing')
check(!dlg.scripts.last.include?('"id":"thermador-hpcn36ws"'),'Superseded generic hood visible')
request={'action'=>'prepare','request_id'=>3,'product_id'=>'thermador-custom-sgs305ts','wall'=>'A'}
dlg.callbacks['kitchen_open_catalog'].call(nil,JSON.generate(request))
begin_script=dlg.scripts.find{|s|s.start_with?('window.KitchenHouseInsert.begin(')}
check(begin_script && begin_script.include?('thermador-custom-sgs305ts'),'Preview missing product selection')
token=Digest::SHA256.hexdigest(JSON.generate([]))
request.merge!('action'=>'place','revision'=>source['revision'],'wall_token'=>token,'placement'=>pose)
dlg.callbacks['kitchen_open_catalog'].call(nil,JSON.generate(request))
check(KitchenLab.test_commands['commands'][0]['type']=='create_catalog_appliance','Generic creation replaced catalog selection')
check(KitchenLab.test_commands['commands'][0]['payload']['overrides']['house_placement']==pose,'Callback placement lost')
KitchenLab.test_commands=nil;request['revision']=-1
dlg.callbacks['kitchen_open_catalog'].call(nil,JSON.generate(request))
check(KitchenLab.test_commands.nil? && dlg.scripts.last.include?('Kitchen changed'),'Stale request created appliance')
puts 'PASS: all manufacturer previews match placement; native cooktop deck, local images, custom replacements and stale requests.'

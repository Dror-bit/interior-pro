module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(v,m);raise m unless v;end
source=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
engine=KitchenLab.command_engine
KitchenLab::SinkCatalog.products.each do |product|
  check(product['mount']=='undermount','Sink is not undermount')
  payload={'product_id'=>product['id'],'kind'=>'sink','wall'=>'A','overrides'=>{'x'=>0,'house_placement'=>{'x'=>100,'y'=>100,'angle'=>90,'handedness'=>-1}}}
  command={'type'=>'create_catalog_appliance','payload'=>payload}
  plan=engine.plan(source,[command]);cab=plan['document']['cabinets'].first
  check(cab.dig('sink','product_id')==product['id'],'Lost sink identity')
  check(cab['kind']=='sink' && !cab['appliance'],'Not a sink base')
  preview=InteriorPro::KitchenPlan.catalog_preview(source,payload)
  check(preview.reject{|k,_| k=='id'}==cab.reject{|k,_| k=='id'},'Preview differs from creation')
  check(plan['document']['revision']==source['revision']+1,'Not one operation')
  persisted=KitchenLab::Document.read(JSON.generate(plan['document']))['cabinets'].first
  check(persisted['sink']==cab['sink'],'Save/load lost product')
  changed=KitchenLab.validate(cab.merge('finish'=>'white'),source['settings'])
  check(changed['sink']==cab['sink'],'Cabinet edit lost product')
  bounds=KitchenLab::Sink.cutout(cab)
  if product['automatic_cutout_available']==false
    check(bounds.nil?,'Unverified sink generated a cutout')
    check(cab['width']>=product['minimum_cabinet_width'],'Minimum cabinet ignored')
    forged=Marshal.load(Marshal.dump(cab));forged['sink']['automatic_cutout_available']=true;forged['sink']['catalog_snapshot']['cutout']=[1,2,3,4]
    check(KitchenLab::Sink.cutout(forged).nil?,'Engine cutout prohibition bypassed')
    check(KitchenLab.validate(forged,source['settings'])['sink']['automatic_cutout_available']==false,'Cutout flag not enforced')
    check(Digest::SHA256.file(File.join(__dir__,product['skp_path'])).hexdigest==product['geometry_sha256'],'SKP changed')
  else
  check(bounds[0]>=0 && bounds[2]<=cab['width'] && bounds[3]<=0,'Cutout outside cabinet')
  check(KitchenLab::SinkCatalog.apron?(cab) ? bounds[1]<=-cab['depth']-1 : bounds[1]>-cab['depth']-1,'Incorrect countertop front opening')
  check((KitchenLab::SinkCatalog.front_height(cab)-(cab['height']-8.9375)).abs<0.001,'Apron doors overlap lowered sink') if KitchenLab::SinkCatalog.apron?(cab)
  rows=KitchenLab.front_rows(cab)
  check(rows.none?{|r|r['kind']=='drawer'},'Apron has false drawer') if KitchenLab::SinkCatalog.apron?(cab)
  if product['mesh_path']
  mesh=JSON.parse(File.read(File.join(__dir__,product['mesh_path'])))
  check(mesh['instances'].length>50 && mesh['definitions'].length>10,'Missing prepared mesh')
  else
    check(Digest::SHA256.file(File.join(__dir__,product['skp_path'])).hexdigest==product['geometry_sha256'],'Approved SKP changed')
    check(bounds[4]==0.5,'Template corner radius lost')
  end
  end
  check(File.size(File.join(__dir__,product['image_path']))>1000,'Missing thumbnail')
  begin
    engine.plan(source,[command.merge('payload'=>payload.merge('overrides'=>{'width'=>10}))])
    raise 'Allowed catalog dimensions override'
  rescue RuntimeError=>e
    raise unless e.message.include?('Only placement')
  end
end
class SinkDialog
  attr_reader :callbacks,:scripts
  def initialize;@callbacks={};@scripts=[];end
  def add_action_callback(name,&block);@callbacks[name]=block;end
  def execute_script(script);@scripts<<script;end
end
dialog=SinkDialog.new;InteriorPro::KitchenPlan.bind_catalog(dialog)
dialog.callbacks.fetch('kitchen_appliance_library').call(nil,'sink')
check(dialog.scripts.last.include?('receive("sink"'),'Library failed')
check(dialog.scripts.last.scan('data:image/png;base64,').length==5,'Library is missing images')
puts 'PASS: five approved sink models, verified K-5287 cutout and explicit K-33152 no-cutout, placement parity, persistence, apron fronts, assets and library'


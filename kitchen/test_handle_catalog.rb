module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
products=KitchenLab::HandleCatalog.products
check(products.size==24,'Missing approved handles')
check(products.map{|p|p['number']}==(1..24).to_a,'Unstable numbering')
s={'shaker_width'=>2.25,'shaker_inset'=>0.25}
products.each do |p|
  check(File.file?(File.join(__dir__,p['preview_path'])),'Missing image')
  check(Digest::SHA256.file(File.join(__dir__,p['skp_path'])).hexdigest==p['skp_sha256'],'Asset hash mismatch')
  [true,false].each do |horizontal|
    d={'kind'=>'doors','style'=>'shaker','handle_position'=>'auto',(horizontal ? 'drawer_handle_model' : 'door_handle_model')=>p['asset_id']}
    layout=KitchenLab::HandleCatalog.layout(d,18,28,horizontal,true,s)
    check(layout['vertical']==(!horizontal && p['vertical_allowed'] && !!p['ctc']),'Wrong orientation')
    check(layout['rect'].all?(&:finite?),'Invalid dimensions')
  end
end
p=products.find{|v|v['ctc']==8}
begin
 KitchenLab::HandleCatalog.layout({'drawer_handle_model'=>p['asset_id'],'style'=>'shaker','kind'=>'drawers'},6,5,true,true,s)
 raise 'Oversize accepted'
rescue RuntimeError=>e;raise unless e.message.include?('does not fit');end
source=KitchenLab::Document.create(s,[])
result=KitchenLab.command_engine.plan(source,[{'type'=>'create_cabinet','payload'=>{'kind'=>'doors','overrides'=>{'door_handle_model'=>products.first['asset_id']}}}])
check(result['document']['cabinets'].first['door_handle_model']==products.first['asset_id'],'Selection lost')
puts 'PASS: 24 numbered assets/images/hashes, door/drawer orientations, oversize rejection and saved cabinet selection'

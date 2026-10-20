root=ARGV.fetch(0,__dir__)
load File.join(root,'kitchen_handle_catalog.rb')
p=KitchenLab::HandleCatalog.products.find{|v|v['number']==19}
s={'global_door_handle_model'=>p['asset_id']}
d={'kind'=>'wall','style'=>'shaker','surround_part'=>'upper','handle_position'=>'auto'}
a=KitchenLab::HandleCatalog.layout(d,11.875,8.3676,false,true,s)
raise 'Short upper pull is not horizontal' if a['vertical']
raise 'Pull not centered' unless (a['center'][0]-11.875/2).abs<1e-6
raise 'Wrong pull selected' unless a['product']['asset_id']==p['asset_id']
raise 'Normal upper no longer vertical' unless KitchenLab::HandleCatalog.layout(d,11.875,15,false,true,s)['vertical']
[d.merge('handle_position'=>'bottom'),d.reject{|k,v|k=='surround_part'}].each do |manual|
 begin
  KitchenLab::HandleCatalog.layout(manual,11.875,8.3676,false,true,s)
 rescue RuntimeError=>e
  raise unless e.message.include?('does not fit')
  next
 end
 raise 'Changed manual or ordinary cabinet behavior'
end
puts 'PASS short appliance upper rotates same pull in Auto only; other doors/manual settings unchanged'

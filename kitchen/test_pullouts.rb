load File.join(__dir__,'kitchen_pullouts.rb')
p=KitchenLab::Pullouts
cab={'kind'=>'doors','width'=>18.0,'depth'=>24.0,'height'=>34.5}
p::TYPES.each{|type|cfg=p.validate({'type'=>type},cab);raise unless cfg['extension']==0 && cfg['type']==type}
raise unless p.validate(nil,cab).nil?
bad=[['waste',cab.merge('width'=>12)],['spice',cab.merge('depth'=>12)],['storage',cab.merge('kind'=>'sink')],['spice',cab.merge('appliance'=>{})]]
bad.each do |type,d|
  rejected=false;begin;p.validate({'type'=>type},d);rescue RuntimeError;rejected=true;end;raise 'Invalid cabinet accepted' unless rejected
end
[-1,22,Float::INFINITY].each do |distance|
  rejected=false;begin;p.validate({'type'=>'spice','extension'=>distance},cab);rescue RuntimeError;rejected=true;end;raise 'Invalid extension accepted' unless rejected
end
puts 'PASS pull-out types, size limits, incompatible cabinets and extension limits'
module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
engine=KitchenLab.command_engine
empty=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])
%w[spice waste storage].each do |type|
  doc=engine.plan(empty,[{'type'=>'create_cabinet','payload'=>{'kind'=>'pullout_'+type}}])['document']
  c=doc['cabinets'].first
  raise 'Wrong preset' unless c.dig('pullout','type')==type && c['width']==(type=='spice' ? 9 : 18)
  rows=KitchenLab.front_rows(c)
  raise 'Wrong fronts' unless rows.length==(type=='waste' ? 2 : 1) && rows.last['doors']==1
  raise 'Missing upper drawer' if type=='waste' && (rows.first['kind']!='drawer' || rows.first['height']!=5.875)
  raise 'Persistence changed data' unless KitchenLab::Document.read(JSON.generate(doc))==doc
  replaced=engine.plan(doc,[{'type'=>'replace_cabinet','payload'=>{'id'=>c['id'],'kind'=>(type=='spice' ? 'filler' : 'drawers')}}])['document']['cabinets'].first
  raise 'Pull-out survived replacement' if replaced['pullout']
  raise 'Placement changed' unless replaced.slice('id','x','z','width','depth')==c.slice('id','x','z','width','depth')
end
puts 'PASS preset creation, single fronts, persistence and replacement cleanup'

module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def check(v,m);raise m unless v;end
def reject(text);begin;yield;rescue StandardError=>e;raise unless e.message.include?(text);return;end;raise 'Expected rejection';end
KitchenLab::Accessories.catalog['products'].select{|p|p['role']=='pot'}.each do |p|
 item={'id'=>'pot','product_id'=>p['id']};c={'kind'=>'oven','width'=>36,'depth'=>26,'height'=>36,'wall'=>'A'}
 a=KitchenLab::Accessories.normalize([item],c).first
 check(a['anchor']==[18.0,0,54],'Range anchor incorrect');check(a['location']=='cooktop'&&a['water_connection']=='cold_only','Wrong role')
 cooktop=c.merge('kind'=>'doors','height'=>34.5,'appliance'=>{'category'=>'cooktop'})
 check(KitchenLab::Accessories.normalize([item],cooktop).first['anchor'][2]==54,'Cooktop height')
 reject('Select a range'){KitchenLab::Accessories.normalize([item],c.merge('kind'=>'sink'))}
 reject('requires a wall'){KitchenLab::Accessories.normalize([item],c.merge('wall'=>'I'))}
 reject('requires a wall'){KitchenLab::Accessories.normalize([item],c.merge('house_placement'=>{'x'=>0,'y'=>0,'angle'=>0}))}
 reject('above the cooking'){KitchenLab::Accessories.normalize([item.merge('anchor'=>[18,0,37])],c)}
 reject('back wall'){KitchenLab::Accessories.normalize([item.merge('anchor'=>[18,-5,54])],c)}
end
puts 'PASS: four pot fillers, wall mount, range/cooktop surface height, cold supply, rejection of sink/island/free-standing/below-surface positions'

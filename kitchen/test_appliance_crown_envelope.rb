require 'json'
load File.join(__dir__,'kitchen_crown.rb')
j=KitchenLab::CrownJoints
%w[fridge wall_oven microwave].each do |kind|
  device={'id'=>'device','kind'=>kind}
  left={'id'=>'left','kind'=>'filler','surround_for'=>'device','surround_part'=>'left','width'=>0.75,'depth'=>24,'z'=>0,'height'=>96,'house_placement'=>{'x'=>10,'y'=>20,'angle'=>180}}
  right=left.merge('id'=>'right','surround_part'=>'right')
  upper=left.merge('id'=>'upper','surround_part'=>'upper','kind'=>'wall','width'=>30,'height'=>15,'z'=>75,'finish'=>'oak')
  lower=upper.merge('id'=>'lower','surround_part'=>'lower','z'=>0,'height'=>28)
  data=[device,left,right,upper,lower]
  rows=j.carriers(data,{'crown_profile'=>'crown'})
  raise 'Duplicate/lower crown' unless rows.size==1
  crown=rows.first
  raise 'Wrong outside envelope' unless crown.values_at('id','width','height','depth','finish')==['device',31.5,90,24,'oak']
  raise 'Placement changed' unless crown['house_placement']==left['house_placement']
  flat=j.carriers(data,{'crown_profile'=>'flat'}).first
  raise 'Flat board overlaps side panels' unless flat['width']==upper['width'] && flat['crown_front_only'] && flat['z']==upper['z']
  raise 'Crown disabled ignored' unless j.carriers(data,{'crown_profile'=>'none'}).empty?
  raise 'Missing side discarded upper' unless j.carriers([device,upper],{'crown_profile'=>'flat'}).first['id']=='upper'
end
puts 'PASS refrigerator and wall-oven crown envelopes: outside panels, upper height, finish, placement, no lower/duplicate crown, disabled and incomplete surround'

module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
pantry=KitchenLab::Pantry
[34.5,40.0,60.0,84.0,96.0].each do |height|
 d={'kind'=>'tall','height'=>height,'width'=>36.0,'depth'=>24.0,'toe_height'=>4.0}
 original=d.dup
 p=pantry.defaults(d)
 rows=pantry.rows(d.merge('pantry'=>p))
 raise 'Defaults mutated cabinet dimensions' unless d==original
 raise 'Section below minimum' unless rows.select{|r|r['kind']=='doors' && r['zone']!='bottom'}.all?{|r|r['height']>=8}
 expected=height-4.0-0.5
 raise 'Sections do not fill available height' unless (p['bottom_height']+p['middle_height']+rows.first['height']-expected).abs<0.001
 raise 'Standard pantry defaults changed' if height>=84 && [p['bottom_height'],p['middle_height']]!=[28.0,30.0]
end
short={'kind'=>'tall','height'=>30.0,'width'=>36.0,'depth'=>24.0,'toe_height'=>4.0}
begin
 pantry.rows(short.merge('pantry'=>pantry.defaults(short)))
 raise 'Accepted an impossible short pantry'
rescue RuntimeError=>e
 raise unless e.message.include?('at least 8') || e.message.include?('14 inches')
end
pantry.send(:remove_const,:USE_FITTED_DEFAULTS);pantry.const_set(:USE_FITTED_DEFAULTS,false)
raise 'Kill switch failed' unless pantry.defaults(short)['bottom_height']==28.0 && pantry.defaults(short)['middle_height']==30.0
puts 'PASS fitted pantry defaults, short/standard/tall heights, preserved dimensions, invalid-height rejection and kill switch'

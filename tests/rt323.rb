require './sketchup_stub'
require './elevation_tool'
e=InteriorPro::ElevationTool
d={'kind'=>'doors','width'=>36,'depth'=>24}
raise 'Base footprint' unless e.kitchen_plan_outline(d)==[[0,0],[36,0],[36,-24],[0,-24]]
%w[doors drawers sink tall oven dishwasher filler pullout_spice pullout_waste].each{|k|raise k unless e.kitchen_plan_outline(d.merge('kind'=>k)).length==4}
%w[corner_base corner_lazy corner_upper].each{|k|raise k unless e.kitchen_plan_outline(d.merge('kind'=>k))==[[0,0],[36,0],[36,-24],[24,-24],[24,-36],[0,-36]]}
raise 'Hood footprint' unless e.kitchen_plan_outline(d.merge('kind'=>'hood')).length==4
raise 'Invalid dimensions' unless e.kitchen_plan_outline(d.merge('width'=>Float::NAN)).empty?
raise 'Zero depth' unless e.kitchen_plan_outline(d.merge('depth'=>0)).empty?
raise 'Unknown type' unless e.kitchen_plan_outline(d.merge('kind'=>'worktop')).empty?
raise 'Switch' unless e::USE_KITCHEN_CABINET_PLAN
puts 'PASS cabinet plan footprints: bases, uppers, corners, appliances and invalid dimensions'

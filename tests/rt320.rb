require './sketchup_stub'
require './elevation_tool'
et=InteriorPro::ElevationTool
raise 'Switch missing' unless et::USE_KITCHEN_UPPER_DASHES
base={'kind'=>'wall','width'=>30,'depth'=>12,'z'=>54}
raise 'Rectangle' unless et.kitchen_upper_outline(base)==[[0,0],[30,0],[30,-12],[0,-12]]
raise 'Corner L' unless et.kitchen_upper_outline(base.merge('kind'=>'corner_upper','width'=>24))==[[0,0],[24,0],[24,-12],[12,-12],[12,-24],[0,-24]]
%w[tall doors hood].each{|kind|raise kind unless et.kitchen_upper_outline(base.merge('kind'=>kind)).empty?}
raise 'Lower surround' unless et.kitchen_upper_outline(base.merge('surround_part'=>'lower')).empty?
raise 'Low wall' unless et.kitchen_upper_outline(base.merge('z'=>4)).empty?
raise 'Invalid size' unless et.kitchen_upper_outline(base.merge('width'=>0)).empty?
r=et.kitchen_dash_ranges(7.5)
raise 'Dashes have gaps and correct final endpoint' unless r==[[0.0,2.0],[3.0,5.0],[6.0,7.5]]
raise 'Zero edge' unless et.kitchen_dash_ranges(0.0).empty?
puts 'PASS kitchen upper outlines'

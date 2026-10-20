require 'json'
load File.join(__dir__,'kitchen_crown.rb')
part={'z'=>0};upper={'z'=>70,'height'=>20}
%w[crown house:CROWN-1].each do |profile|
  raise 'Decorative side panel protrudes' unless KitchenLab.appliance_panel_crown_height(part,upper,{'crown_profile'=>profile,'crown_height'=>6})==90
end
flat={'crown_profile'=>'flat','crown_height'=>6}
raise 'Flat side panel shortened' unless KitchenLab.appliance_panel_crown_height(part,upper,flat)==96
house=flat.merge('crown_profile'=>'house:FLAT','crown_shape'=>{'points'=>[[0,0],[1,0],[1,6],[0,6]]})
raise 'House flat not recognized' unless KitchenLab.appliance_panel_crown_height(part,upper,house)==96
raise 'Raised oven base ignored' unless KitchenLab.appliance_panel_crown_height({'z'=>10},upper,{'crown_profile'=>'crown'})==80
raise 'Inputs changed' unless upper=={'z'=>70,'height'=>20} && part=={'z'=>0}
puts 'PASS panel heights: decorative, straight, house straight, raised base, no input mutation'

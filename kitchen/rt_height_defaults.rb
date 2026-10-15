# Run inside the connected SketchUp model; no geometry is changed.
module KitchenHeightDefaultsCheck
  def self.run
    s=KitchenLab.settings.merge('global_handle_type'=>'none','global_door_handle_model'=>'','global_drawer_handle_model'=>'')
    empty=KitchenLab::Document.create(s,[])
    %w[wall glass_wall tall corner_upper].each do |kind|
      payload={'kind'=>kind,'id'=>'height-default-test','overrides'=>{'x'=>0,'handle'=>'none'}}
      payload['overrides']['house_placement']={'x'=>100,'y'=>100,'angle'=>0,'handedness'=>1} if kind=='corner_upper'
      c=KitchenLab.command_engine.plan(empty,[{'type'=>'create_cabinet','payload'=>payload}])['document']['cabinets'].first
      raise "Wrong default for #{kind}" unless c['height']+c['z']==90
    end
    c=KitchenLab.command_engine.plan(empty,[{'type'=>'create_wall_cabinet','payload'=>{'id'=>'custom-height-test','overrides'=>{'height'=>24,'z'=>60,'handle'=>'none'}}}])['document']['cabinets'].first
    raise 'Custom size lost' unless c['height']==24 && c['z']==60
    raise 'Wrong molding default' unless KitchenLab.crown_settings({}).values_at('crown_profile','crown_height')==['flat',6.0]
    puts 'PASS: wall, glass wall, corner upper and tall default to 90; custom heights retained; flat crown 6.'
  end
end
KitchenHeightDefaultsCheck.run

# Build real cabinet parts around an existing appliance in one engine operation.
module InteriorPro
  module KitchenPlan
    def self.surround_commands(source,id,options={})
      appliance=source['cabinets'].find { |c| c['id']==id }
      raise 'Select a refrigerator, microwave or wall oven.' unless appliance && %w[fridge microwave wall_oven].include?(appliance['kind'])
      raise 'This appliance already has a surround.' if source['cabinets'].any? { |c| c['surround_for']==id }
      number=lambda do |key,default,min,max|
        value=Float(options.fetch(key,default))
        raise "Invalid #{key.tr('_',' ')}." unless value.finite? && value.between?(min,max)
        value
      end
      gap=number.call('side_gap',0.25,0,6)
      top_gap=number.call('top_gap',1,0,12)
      depth=number.call('depth',appliance['kind']=='fridge' ? 24 : appliance['depth'],8,36)
      thickness=0.75;opening=appliance['width']+2*gap
      origin=KitchenLab::Spatial.cabinet_point(appliance,0,0,source['settings'])
      px=KitchenLab::Spatial.cabinet_point(appliance,1,0,source['settings'])
      py=KitchenLab::Spatial.cabinet_point(appliance,0,1,source['settings'])
      u=px.zip(origin).map { |a,b| a-b };v=py.zip(origin).map { |a,b| a-b }
      angle=Math.atan2(u[1],u[0])*180/Math::PI
      hand=u[0]*v[1]-u[1]*v[0]<0 ? -1 : 1
      part=lambda do |role,kind,x,z,width,height|
        position=KitchenLab::Spatial.cabinet_point(appliance,x,0,source['settings'])
        {'type'=>'create_cabinet','payload'=>{'id'=>'c-'+SecureRandom.hex(8),'kind'=>kind,'wall'=>appliance['wall'],
          'overrides'=>{'x'=>0,'z'=>z,'width'=>width,'height'=>height,'depth'=>depth,'toe_height'=>0,
          'surround_for'=>id,'surround_part'=>role,
          'house_placement'=>{'x'=>position[0],'y'=>position[1],'angle'=>angle,'handedness'=>hand}}}}
      end
      z=appliance['z'];height=appliance['height'];width=appliance['width']
      if appliance['kind']=='fridge'
        total=number.call('total_height',96,18,96)
        upper=total-height-top_gap
        raise 'Leave at least 8.25 inches above the refrigerator for the upper cabinet.' if upper<8.25
        [part.call('left','filler',-gap-thickness,z,thickness,total),
         part.call('right','filler',width+gap,z,thickness,total),
         part.call('upper','wall',-gap,z+height+top_gap,opening,upper)]
      elsif appliance['kind']=='wall_oven'
        total=number.call('total_height',96,18,96)
        upper=total-z-height-top_gap;lower=z-thickness
        raise 'Leave at least 8.25 inches above and below the wall oven for its cabinets.' if upper<8.25 || lower<8.25
        [part.call('left','filler',-gap-thickness,0,thickness,total),
         part.call('right','filler',width+gap,0,thickness,total),
         part.call('lower','wall',-gap,0,opening,lower),
         part.call('bottom','filler',-gap,z-thickness,opening,thickness),
         part.call('upper','wall',-gap,z+height+top_gap,opening,upper)]
      else
        raise 'Raise the microwave before adding its bottom shelf.' if z<thickness
        total=height+top_gap+2*thickness
        [part.call('left','filler',-gap-thickness,z-thickness,thickness,total),
         part.call('right','filler',width+gap,z-thickness,thickness,total),
         part.call('bottom','filler',-gap,z-thickness,opening,thickness),
         part.call('top','filler',-gap,z+height+top_gap,opening,thickness)]
      end
    end

    def self.bind_surround(dlg)
      dlg.add_action_callback('kitchen_add_surround') do |_,json|
        begin
          raise 'Kitchen integration is disabled' unless USE_KITCHEN_IN_EDITOR
          KitchenLab.guard!
          request=JSON.parse(json.to_s);source=KitchenLab.document
          level=defined?(InteriorPro::LevelManager) ? InteriorPro::LevelManager.active_level.to_i : 1
          raise 'Kitchen belongs to another floor.' unless KitchenLab::Spatial.pose(source['settings'])['level'].to_i==level
          raise 'Kitchen changed. Select the appliance again.' unless request['revision']==source['revision']
          commands=surround_commands(source,request['id'],request.fetch('options',{}))
          plan=KitchenLab.command_engine.plan(source,commands,expected_revision:request['revision'])
          ids=commands.map { |c| c['payload']['id'] };walls=walls_payload
          plan['document']['cabinets'].select { |c| ids.include?(c['id']) }.each { |c| validate_house_placement!(c,source['settings'],walls) }
          KitchenLab.execute_commands({'expected_revision'=>request['revision'],'commands'=>commands},false)
          dlg.execute_script('window.KitchenSurround?.result(null);')
        rescue StandardError=>error
          dlg.execute_script("window.KitchenSurround?.result(#{JSON.generate(error.message)});")
        end
      end
    end
  end
end

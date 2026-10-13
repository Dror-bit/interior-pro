# Domain command planner. No SketchUp, UI, model attributes or transactions.
require 'securerandom'
module KitchenLab
  class Engine
    def initialize(validator:, settings_validator: nil, reference_provider: nil, id_generator: -> { "c-#{SecureRandom.hex(8)}" })
      @validator=validator
      @settings_validator=settings_validator
      @reference_provider=reference_provider
      @id_generator=id_generator
    end

    def plan(source, commands, expected_revision: nil)
      before=Document.read(JSON.generate(source))
      raise 'Kitchen changed. Refresh before trying again.' if !expected_revision.nil? && expected_revision!=before['revision']
      raise 'Provide 1–100 commands' unless commands.is_a?(Array) && commands.length.between?(1,100)
      candidate=Document.read(JSON.generate(before))
      results=commands.map { |command| apply_command(candidate,command) }
      data=candidate['cabinets'];settings=candidate['settings']
      # Validate the final batch, so coordinated moves may use a currently occupied slot.
      data.each { |cabinet| @validator.call(cabinet,settings) }
      raise 'Cabinets overlap. Adjust the position or width.' if data.combination(2).any? { |a,b| Spatial.overlap?(a,b,settings) }
      old=before['cabinets'].to_h { |c| [c['id'],c] };now=data.to_h { |c| [c['id'],c] }
      changed=(old.keys|now.keys).select { |id| old[id]!=now[id] }
      settings_changed=before['settings']!=settings
      candidate['revision']+=1 unless changed.empty? && !settings_changed
      {'base_revision'=>before['revision'],'document'=>candidate,'changed_ids'=>changed,'settings_changed'=>settings_changed,'results'=>results}
    end

    private

    def elevated?(c);%w[wall wall_oven hood microwave].include?(c['kind']);end
    def wall(c);c.fetch('wall','A');end

    def create_data(doc,payload,forced_kind=nil)
      kind=forced_kind||payload.fetch('kind','doors')
      glass=kind=='glass_wall';kind='wall' if glass
      house_corner=%w[corner_base corner_lazy corner_upper].include?(kind) && payload.fetch('overrides',{}).is_a?(Hash) && payload['overrides']['house_placement']
      raise 'Use the corner tool for coordinated corner placement' if kind.start_with?('corner') && !house_corner
      s=doc['settings'];data=doc['cabinets'];area=payload.fetch('wall','A')
      c={'id'=>payload.fetch('id') { @id_generator.call },'kind'=>kind,'wall'=>area,
        'width'=>%w[drawers tall].include?(kind) ? 24 : 36,
        'height'=>kind=='wall' ? 30 : kind=='tall' ? 96 : 34.5,
        'depth'=>kind=='wall' ? 12 : 24,'z'=>kind=='wall' ? 54 : 0,
        'style'=>glass ? 'glass' : 'shaker','finish'=>'ivory','handle'=>'brass'}
      c.merge!('width'=>kind=='corner_upper' ? 24 : 36,'height'=>kind=='corner_upper' ? 30 : 34.5,'depth'=>kind=='corner_upper' ? 12 : 24,'z'=>kind=='corner_upper' ? 54 : 0,'x'=>0) if house_corner
      c['finish']=s['global_finish'] unless s.fetch('global_finish','').empty?
      c['handle']=s['global_handle_color'] unless s.fetch('global_handle_color','').empty?
      c['handle']='none' if s['global_handle_type']=='none'
      if kind=='filler'
        # Prefer the user's cabinet; otherwise match the nearest cabinet in this run.
        neighbors=data.select { |d| wall(d)==area && !%w[filler corner fridge oven wall_oven dishwasher hood microwave].include?(d['kind']) }
        reference=neighbors.find { |d| d['id']==payload['reference_id'] }
        unless reference
          placement=payload['overrides'].is_a?(Hash) ? payload['overrides'] : {}
          target_x=placement.fetch('x',neighbors.map { |d| d['x']+d['width'] }.push(0).max).to_f
          target_z=placement.fetch('z',0).to_f
          reference=neighbors.min_by { |d| [(d['z']-target_z).abs, [target_x-d['x']-d['width'],d['x']-target_x,0].max] }
        end
        c.merge!('width'=>3,'style'=>'slab','handle'=>'none')
        %w[height depth z].each { |key| c[key]=reference[key] } if reference
      end
      appliances={'fridge'=>[36,70,30,0],'oven'=>[30,36,26,0],'dishwasher'=>[24,34.5,24,0],
        'hood'=>[30,30,20,66],'microwave'=>[30,18,16,54]}
      c.merge!(%w[width height depth z].zip(appliances[kind]).to_h) if appliances.key?(kind)
      if %w[oven_tower micro_tower fridge_surround].include?(kind)
        c.merge!('width'=>kind=='fridge_surround' ? 39 : 30,'height'=>96,'depth'=>kind=='fridge_surround' ? 30 : 24)
      end
      overrides=payload.fetch('overrides',{})
      raise 'Invalid cabinet overrides' unless overrides.is_a?(Hash)
      raise 'ID and kind belong to the creation command' unless (overrides.keys & %w[id kind wall]).empty?
      c.merge!(overrides)
      c['sink']=Sink.defaults(c) if kind=='sink' && !overrides.key?('sink')
      c['appearance_overrides']=overrides.fetch('appearance_overrides',overrides.slice('finish','handle'))
      c=Appearance.resolve(c,s)
      if area=='I' && s['island_match_kitchen_style']==false && !Appearance.appliance?(c) && !overrides.key?('appearance_overrides')
        c['appearance_overrides']=c.slice('finish','handle')
      end
      related=data.select { |o| wall(o)==area && elevated?(o)==elevated?(c) }
      c['x']=related.map { |o| o['x']+o['width'] }.push(0).max unless overrides.key?('x')
      c=@validator.call(c,s)
      if payload.key?('fit_space_at') && overrides.key?('x')
        clicked=Float(payload['fit_space_at'])
        raise 'Choose a point along this run.' unless clicked.finite? && clicked.between?(0,1200)
        if data.any? { |o| Spatial.overlap?(c,o,s) }
          probe=c.merge('x'=>clicked,'width'=>0.01)
          raise 'That point is occupied. Click inside the empty gap.' if data.any? { |o| Spatial.overlap?(probe,o,s) }
          origin=Spatial.point(area,0,0,s);axis=Spatial.point(area,1,0,s).zip(origin).map { |v,o| v-o }
          boundaries=data.flat_map { |o| Spatial.polygon(o,s).map { |p| (p[0]-origin[0])*axis[0]+(p[1]-origin[1])*axis[1] } }
          positions=([0,clicked-c['width']/2]+boundaries.flat_map { |p| [p,p-c['width']] }).map { |p| p.round(6) }.uniq
          positions.select! { |p| p.between?(0,1200) && p<=clicked && p+c['width']>=clicked }
          x=positions.sort_by { |p| [(p-c['x']).abs,p] }.find { |p| data.none? { |o| Spatial.overlap?(c.merge('x'=>p),o,s) } }
          raise 'The cabinet is too wide for this gap. Choose a smaller width.' unless x
          c['x']=x
        end
      end
      unless overrides.key?('x')
        if elevated?(c)||area=='B'
          # Use actual footprints: an L corner occupies its full width on B,
          # not merely its carcass depth. Include transformed island/other runs.
          origin=Spatial.point(area,0,0,s);axis=Spatial.point(area,1,0,s).zip(origin).map { |v,o| v-o }
          boundaries=data.flat_map { |o| Spatial.polygon(o,s).map { |p| (p[0]-origin[0])*axis[0]+(p[1]-origin[1])*axis[1] } }
          positions=([c['x'],0]+boundaries).select { |px| px>=0 && px<=1200 }.map { |px| px.round(6) }.uniq.sort
          x=positions.find { |px| data.none? { |o| Spatial.overlap?(c.merge('x'=>px),o,s) } }
          raise 'No free space on this wall. Move a cabinet or change its height.' unless x
          c['x']=x
        end
        if %w[hood microwave].include?(kind)
          range=data.find { |o| o['kind']=='oven' && wall(o)==area }
          if range
            x=range['x']+(range['width']-c['width'])/2.0
            c['x']=x if x>=0 && data.none? { |o| Spatial.overlap?(c.merge('x'=>x),o,s) }
          end
        end
      end
      c
    end

    def gap_lane(data,reference)
      data.select { |c| wall(c)==wall(reference) && (c['z']-reference['z']).abs<0.001 && (c.fetch('offset_y',0)-reference.fetch('offset_y',0)).abs<0.001 }
    end

    def shift_gap_tail!(lane,start,amount)
      moving=lane.select { |c| c['x']>=start-0.001 }
      raise 'Close gap requires aligned cabinets. Move rotated cabinets individually.' if moving.any? { |c| c.fetch('rotation',0)%360!=0 || c['kind'].start_with?('corner') }
      moving.each { |c| c['x']=(c['x']-amount).round(6) }
    end

    def apply_command(doc,command)
      raise 'Invalid kitchen command' unless command.is_a?(Hash)
      name=command.fetch('type');payload=command.fetch('payload',{})
      raise 'Invalid command payload' unless payload.is_a?(Hash)
      data=doc['cabinets'];s=doc['settings'];id=payload['id']
      case name
      when 'set_island_dimension'
        basis=payload.fetch('basis');side=payload.fetch('side');distance=Float(payload.fetch('distance'))
        raise 'Distance must be 0–1200 inches' unless distance.finite? && distance.between?(0,1200)
        refs=basis=='wall' && @reference_provider ? @reference_provider.call : []
        measured=Dimensions.measure(data,s,basis,refs).find { |m| m['side']==side && m['target_id']==payload.fetch('target_id') }
        raise 'Measurement changed. Refresh the plan and select the dimension again.' unless measured
        expected=Float(payload.fetch('measured_distance'))
        raise 'Measurement changed. Refresh the plan.' unless expected.finite? && (expected-measured['distance']).abs<0.01
        nx,ny=Dimensions::DIRECTIONS.fetch(side);delta=measured['distance']-distance
        s['island_x']=s.fetch('island_x',48)+nx*delta;s['island_y']=s.fetch('island_y',84)-ny*delta
        raise 'Island position exceeds 1200 inches' unless %w[island_x island_y].all? { |k| s[k].abs<=1200 }
        check=Dimensions.measure(data,s,basis,refs).find { |m| m['side']==side && m['target_id']==measured['target_id'] }
        raise 'Another object blocks this dimension. Choose a smaller move.' unless check && (check['distance']-distance).abs<0.01
        if basis=='wall'
          walls=refs.select { |r| r['type']=='wall' && r['measurement_safe'] }
          raise 'Island would overlap a wall.' if data.select { |d| wall(d)=='I' }.any? { |d| walls.any? { |r| Dimensions.overlap?(Spatial.polygon(d,s),r['points']) } }
        end
      when 'set_island_clearance'
        area=payload.fetch('run');gap=Float(payload.fetch('distance'))
        raise 'Choose Run A or B' unless %w[A B].include?(area)
        raise 'Distance must be 0–1200 inches' unless gap.finite? && gap.between?(0,1200)
        island=data.select { |d| wall(d)=='I' };raise 'Create an island first' if island.empty?
        reference=data.select { |d| wall(d)==area && d['z']<island.map { |c| c['z']+c['height'] }.max && d['z']+d['height']>island.map { |c| c['z'] }.min }
        raise 'No cabinets on the selected run at island height' if reference.empty?
        local=s.merge('kitchen_pose'=>{'x'=>0,'y'=>0,'z'=>0,'angle'=>0,'level'=>1})
        ip=island.flat_map { |d| Spatial.polygon(d,local) };rp=reference.flat_map { |d| Spatial.polygon(d,local) }
        if area=='A'
          delta=rp.map(&:last).min-gap-ip.map(&:last).max
          s['island_y']=s.fetch('island_y',84)-delta
        else
          delta=rp.map(&:first).max+gap-ip.map(&:first).min
          s['island_x']=s.fetch('island_x',48)+delta
        end
        raise 'Island position exceeds 1200 inches' unless %w[island_x island_y].all? { |k| s.fetch(k,0).abs<=1200 }
      when 'create_island_cabinet'
        raise 'An island already exists. Add cabinets to it or move it.' if data.any? { |d| wall(d)=='I' }
        origin=payload.fetch('origin')
        raise 'Invalid island origin' unless origin.is_a?(Hash)
        coords=%w[x y angle].to_h { |key| [key,Float(origin.fetch(key,key=='angle' ? 0 : nil))] }
        raise 'Island position must be -1200–1200 inches' unless %w[x y].all? { |key| coords[key].finite? && coords[key].abs<=1200 }
        raise 'Invalid island angle' unless coords['angle'].finite? && coords['angle'].abs<=360
        s.merge!('island_x'=>coords['x'],'island_y'=>-coords['y'],'island_angle'=>coords['angle'])
        supplied=payload.fetch('overrides',{})
        raise 'Invalid cabinet overrides' unless supplied.is_a?(Hash)
        c=create_data(doc,payload.merge('wall'=>'I','overrides'=>supplied.merge('x'=>0)))
        id=c['id'];raise 'Cabinet ID already exists' if data.any? { |o| o['id']==id };data<<c
      when 'create_catalog_appliance'
        options=SinkCatalog.include?(payload.fetch('product_id')) ? SinkCatalog.options(payload['product_id']) : ApplianceCatalog.options(payload['product_id'])
        supplied=payload.fetch('overrides',{})
        raise 'Invalid appliance overrides' unless supplied.is_a?(Hash)
        permitted=%w[x z house_placement]
        permitted+=%w[installation_depth depth] if ApplianceCatalog.microwave_base?(options) && supplied.key?('installation_depth')
        raise 'Only placement may override a catalog appliance' unless (supplied.keys-permitted).empty?
        c=create_data(doc,payload.merge('kind'=>options['kind'],'overrides'=>options.reject { |k,_| k=='kind' }.merge(supplied)))
        id=c['id'];raise 'Cabinet ID already exists' if data.any? { |o| o['id']==id };data<<c
      when 'detach_catalog_appliance'
        index=data.index { |o| o['id']==id };raise 'Cabinet no longer exists' unless index
        raise 'Cooktop base requires a catalog selection' if ApplianceCatalog.cooktop?(data[index])
        data[index]=@validator.call(data[index].reject { |k,_| k=='appliance' },s)
      when 'create_cabinet','create_base_cabinet','create_wall_cabinet','create_tall_cabinet'
        forced={'create_base_cabinet'=>'doors','create_wall_cabinet'=>'wall','create_tall_cabinet'=>'tall'}[name]
        c=create_data(doc,payload,forced);id=c['id']
        raise 'Cabinet ID already exists' if data.any? { |o| o['id']==id }
        data<<c
      when 'flip_cabinet'
        cabinet=data.find { |c| c['id']==id };raise 'Cabinet no longer exists' unless cabinet
        axis=payload.fetch('axis');raise 'Choose left/right or front/back' unless %w[x y].include?(axis)
        cabinet['flip_'+axis]=!cabinet.fetch('flip_'+axis,false)
      when 'update_cabinet','change_width','change_height','change_depth'
        index=data.index { |o| o['id']==id };raise 'Cabinet no longer exists' unless index
        changes=name=='update_cabinet' ? payload.fetch('changes') : {name.delete_prefix('change_')=>payload.fetch('value')}
        raise 'Invalid cabinet changes' unless changes.is_a?(Hash)
        if data[index]['appliance'] && changes.key?('appliance') && changes['appliance']!=data[index]['appliance']
          raise 'Choose a catalog model to change the appliance selection'
        end
        raise 'Cabinet identity and type cannot be changed' unless (changes.keys & %w[id kind]).empty?
        data[index]=@validator.call(Appearance.edit(data[index],changes,s),s)
      when 'set_project_handles'
        raise 'Settings validation is unavailable' unless @settings_validator
        all=payload.fetch('apply_to_all',false)
        raise 'Invalid handle scope' unless [true,false].include?(all)
        updates=payload.slice('global_door_handle_model','global_drawer_handle_model')
        raise 'Choose both door and drawer handles' unless updates.length==2
        doc['settings']=@settings_validator.call(updates.merge('global_handle_type'=>'bar','global_handle_color'=>s.fetch('global_handle_color','').empty? ? 'brass' : s['global_handle_color']),s)
        doc['cabinets']=data.map do |c|
          if all && !Appearance.appliance?(c)
            c=c.merge('door_handle_model'=>nil,'drawer_handle_model'=>nil,'appearance_overrides'=>c.fetch('appearance_overrides',{}).reject { |k,_| k=='handle' })
          end
          Appearance.resolve(c,doc['settings'])
        end
      when 'update_settings'
        raise 'Settings validation is unavailable' unless @settings_validator
        doc['settings']=@settings_validator.call(payload,s)
        doc['cabinets']=data.map { |c| Appearance.resolve(c,doc['settings']) }
      when 'use_kitchen_style'
        raise 'Cabinet no longer exists' if id && data.none? { |c| c['id']==id }
        doc['cabinets']=data.map { |c| (!id || c['id']==id) && !Appearance.appliance?(c) ? Appearance.resolve(c.merge('appearance_overrides'=>{}),s) : c }
      when 'set_island_style_match'
        enabled=payload.fetch('enabled')
        raise 'Invalid island style choice' unless [true,false].include?(enabled)
        raise 'Place an island first.' unless data.any? { |c| wall(c)=='I' }
        s['island_match_kitchen_style']=enabled
        doc['cabinets']=data.map do |c|
          next c unless wall(c)=='I' && !Appearance.appliance?(c)
          Appearance.resolve(c.merge('appearance_overrides'=>enabled ? {} : c.slice('finish','handle')),s)
        end
      when 'set_island_dimension_directions'
        raise 'Place an island first.' unless data.any? { |c| wall(c)=='I' }
        raise 'Choose up or down.' unless %w[up down].include?(payload['vertical'])
        raise 'Choose left or right.' unless %w[left right].include?(payload['horizontal'])
        raise 'Invalid dimension visibility.' unless [true,false].include?(payload.fetch('visible',true))
        s['island_dimensions']=payload.slice('vertical','horizontal').merge('visible'=>payload.fetch('visible',true))
      when 'close_gap'
        left=data.find { |c| c['id']==payload['left_id'] };right=data.find { |c| c['id']==payload['right_id'] }
        raise 'Gap boundaries changed. Select the gap again.' unless left && right
        lane=gap_lane(data,left).sort_by { |c| c['x'] }
        index=lane.index(left)
        raise 'Gap boundaries changed. Select the gap again.' unless lane[index+1]==right
        raise 'Close gap requires an aligned left cabinet.' unless left.fetch('rotation',0)%360==0
        gap=right['x']-left['x']-left['width']
        raise 'There is no gap between these cabinets.' unless gap>0.001
        raise 'Gap size changed. Select it again.' if payload.key?('gap') && (Float(payload['gap'])-gap).abs>0.001
        shift_gap_tail!(lane,right['x'],gap)
      when 'remove_cabinet_and_close_gap'
        removed=data.find { |c| c['id']==id };raise 'Cabinet no longer exists' unless removed
        raise 'For corner or rotated cabinets use Delete and keep space.' if removed['kind'].start_with?('corner') || removed.fetch('rotation',0)%360!=0
        raise 'For appliance cabinets use Delete and keep space.' if removed['surround_for'] || data.any? { |c| c['surround_for']==id }
        lane=gap_lane(data,removed)
        shift_gap_tail!(lane.reject { |c| c['id']==id },removed['x']+removed['width'],removed['width'])
        data.reject! { |c| c['id']==id }
      when 'remove_cabinet'
        removed=data.find { |o| o['id']==id };raise 'Cabinet no longer exists' unless removed
        owner=removed['surround_for'] || id
        data.reject! { |o| o['id']==owner || o['surround_for']==owner }
      else
        raise "Unknown kitchen command: #{name}"
      end
      {'type'=>name,'id'=>id}
    end
  end
end

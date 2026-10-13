# Build real cabinet parts around an existing appliance in one engine operation.
module InteriorPro
  module KitchenPlan
    def self.surround_supported?(cabinet)
      return true if %w[fridge microwave wall_oven].include?(cabinet['kind'])
      return false unless cabinet['kind']=='hood'
      appliance=cabinet['appliance']||{}
      installation=appliance.dig('appearance','installation')
      installation||=KitchenLab::ApplianceCatalog.products.find { |p| p['id']==appliance['id'] }&.dig('appearance','installation')
      installation=='built_in'
    end

    def self.catalog_commands(source,payload,without_cabinet=false,hood_style='shaker')
      raise 'Invalid cabinet option.' unless [true,false].include?(without_cabinet)
      type=payload['product_id'] ? 'create_catalog_appliance' : 'create_cabinet'
      first={'type'=>type,'payload'=>payload.merge('id'=>'c-'+SecureRandom.hex(8))}
      empty=KitchenLab::Document.create(source['settings'],[])
      preview=KitchenLab.command_engine.plan(empty,[first])['document']
      appliance=preview['cabinets'].first
      return [first] if without_cabinet || !surround_supported?(appliance)
      parts=surround_commands(preview,appliance['id'],{'cover_style'=>hood_style})
      if parts.first && parts.first['type']=='update_cabinet'
        changes=parts.shift['payload']['changes']
        first['payload']=first['payload'].merge('overrides'=>first['payload'].fetch('overrides',{}).merge(changes))
      end
      [first,*parts]
    end

    def self.catalog_bundle_preview(source,payload,without_cabinet,level,hood_style='shaker')
      p=payload.merge('overrides'=>{'x'=>0,'house_placement'=>{'x'=>0,'y'=>0,'angle'=>0,'handedness'=>1}})
      commands=catalog_commands(source,p,without_cabinet,hood_style)
      doc=KitchenLab.command_engine.plan(KitchenLab::Document.create(source['settings'],[]),commands)['document']
      rows=self.payload(JSON.generate(doc),level)['cabinets']
      return {'row'=>rows.first,'parts'=>nil,'offset'=>0} if rows.length==1
      xs=rows.flat_map { |r| r['polygon'].map(&:first) };ys=rows.flat_map { |r| r['polygon'].map(&:last) }
      offset=-xs.min;bottom=rows.map { |r| r['base_z'] }.min;top=rows.map { |r| r['base_z']+r['height'] }.max
      parts=rows.map do |r|
        r.merge('polygon'=>r['polygon'].map { |x,y| [x+offset,y] },'basis'=>r['basis'].map { |x,y| [x+offset,y] })
      end
      width=xs.max-xs.min;depth=-ys.min
      row=rows.first.merge('polygon'=>[[0,0],[width,0],[width,-depth],[0,-depth]],'basis'=>[[0,0],[1,0],[0,-1]],'base_z'=>bottom,'height'=>top-bottom,
        'cabinet'=>rows.first['cabinet'].merge('width'=>width,'depth'=>depth,'height'=>top-bottom))
      {'row'=>row,'parts'=>parts,'offset'=>offset}
    end

    def self.surround_commands(source,id,options={})
      appliance=source['cabinets'].find { |c| c['id']==id }
      raise 'Select a refrigerator, microwave, wall oven or built-in hood.' unless appliance && surround_supported?(appliance)
      raise 'This appliance already has a surround.' if source['cabinets'].any? { |c| c['surround_for']==id }
      number=lambda do |key,default,min,max|
        value=Float(options.fetch(key,default))
        raise "Invalid #{key.tr('_',' ')}." unless value.finite? && value.between?(min,max)
        value
      end
      gap=number.call('side_gap',0.25,0,6)
      top_gap=number.call('top_gap',KitchenLab::ApplianceCatalog.microwave_base?(appliance) ? 0.25 : 1,0,12)
      depth=number.call('depth',(appliance['kind']=='fridge' || KitchenLab::ApplianceCatalog.microwave_base?(appliance)) ? 24 : appliance.dig('appliance','appearance','cabinet_depth') || appliance['depth'],8,36)
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
      if KitchenLab::ApplianceCatalog.microwave_base?(appliance)
        total=number.call('total_height',34.5,30,42)
        lower=z-thickness-4
        raise 'Microwave must leave room for a lower drawer and countertop.' if lower<8.25 || z+height+top_gap>total-thickness+0.001
        drawer=part.call('lower','wall',-gap,4,opening,lower)
        drawer['payload']['overrides'].merge!('front_layout'=>'drawers','drawer_heights'=>[lower-0.25],'front_overlay'=>0.75)
        plinth=part.call('plinth','filler',-gap,0,opening,4)
        plinth['payload']['overrides']['depth']=0.75
        point=KitchenLab::Spatial.cabinet_point(appliance,-gap,-depth+3.75,source['settings'])
        plinth['payload']['overrides']['house_placement'].merge!('x'=>point[0],'y'=>point[1])
        parts=[part.call('left','filler',-gap-thickness,0,thickness,total),
         part.call('right','filler',width+gap,0,thickness,total),drawer,plinth,
         part.call('bottom','filler',-gap,z-thickness,opening,thickness),
         part.call('top','filler',-gap,z+height+top_gap,opening,total-z-height-top_gap)]
        parts.first(2).each { |c| c['payload']['overrides'].merge!('toe_height'=>4,'toe_setback'=>3) }
        body=appliance.dig('appliance','appearance','cabinet_depth')
        if body
          raise 'Microwave cabinet must be at least 24 inches deep.' if depth<24
          parts.unshift({'type'=>'update_cabinet','payload'=>{'id'=>id,'changes'=>{'installation_depth'=>depth,'depth'=>appliance['appliance']['dimensions']['depth']+depth-body}}})
        end
        parts
      elsif appliance['kind']=='hood'
        total=number.call('total_height',96-z,height,96)
        style=options.fetch('cover_style','shaker')
        raise 'Choose a plain or Shaker hood cover.' unless %w[slab shaker].include?(style)
        # The casing is open underneath for extraction and above for the duct.
        # Its fixed front sits outside the insert, never across its intake.
        depth=[depth,appliance['depth']+1].max
        front=part.call('hood_front','filler',-gap,z,opening,total)
        front['payload']['overrides'].merge!('depth'=>0.75,'style'=>style,'handle'=>'none')
        front_point=KitchenLab::Spatial.cabinet_point(appliance,-gap,-depth+0.75,source['settings'])
        front['payload']['overrides']['house_placement'].merge!('x'=>front_point[0],'y'=>front_point[1])
        [part.call('left','filler',-gap-thickness,z,thickness,total),
         part.call('right','filler',width+gap,z,thickness,total),front]
      elsif appliance['kind']=='fridge'
        total=number.call('total_height',appliance['kind']=='hood' ? 96-z : 96,18,96)
        upper=total-height-top_gap
        raise 'Leave at least 8.25 inches above the appliance for the upper cabinet.' if upper<8.25
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


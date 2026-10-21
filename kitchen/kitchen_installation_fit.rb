# Manufacturer installation profiles, in inches. They are snapshotted on new
# selections; existing saved appliances are deliberately not silently migrated.
module KitchenLab
  module InstallationFit
    def self.profiles
      JSON.parse(File.read(File.join(__dir__,'appliance_installation_profiles.json')))
    end
    def self.profile(d)
      d.dig('appliance','installation_fit') if d['manufacturer_fit']==1
    end
    def self.validate(d)
      return unless d.key?('manufacturer_fit')
      f=profile(d)
      raise 'Invalid manufacturer installation' unless d['manufacturer_fit']==1 && f.is_a?(Hash) && f['version']==1 && f['product_id']==d.dig('appliance','id')
      %w[opening_width opening_height cabinet_depth fascia_y].each do |k|
        raise 'Invalid installation dimension' unless f[k].is_a?(Numeric) && f[k].finite? && f[k].abs<=120
      end
    end
    # Accessories and support framing use the SAME boxes for native geometry
    # and 2D projections. The delivered appliance SKP is never stretched/edited.
    def self.parts(d)
      f=profile(d);return [] unless f
      out=[];add=lambda do |name,x,y,z,w,dep,h,color|
        out<<{'name'=>name,'x'=>x,'y'=>y,'z'=>z,'width'=>w,'depth'=>dep,'height'=>h,'color'=>color} if [w,dep,h].all? { |v|v>0.0001 }
      end
      if (kit=f['trim_kit'])
        # A separate purchased trim accessory, not part of the native MSER SKP.
        w,h,dep=kit.values_at('width','height','depth');iw,ih=kit.values_at('inner_width','inner_height')
        x=(d['width']-w)/2;z=kit['bottom'];y=f['fascia_y']-0.02
        bx=(w-iw)/2;bz=(h-ih)/2
        add.call('MK2030NST trim / left',x,y,z,bx,dep,h,'#B9BEC2')
        add.call('MK2030NST trim / right',x+w-bx,y,z,bx,dep,h,'#B9BEC2')
        add.call('MK2030NST trim / bottom',x+bx,y,z,iw,dep,bz,'#B9BEC2')
        add.call('MK2030NST trim / top',x+bx,y,z+h-bz,iw,dep,bz,'#B9BEC2')
        ow=f['opening_width'];cx=(d['width']-kit['cutout_width'])/2
        edge=(d['width']-ow)/2;floor=z+1.25;roof=floor+kit['cutout_height']
        fy=f['fascia_y']+f['front_projection'];bottom=f['opening_bottom'];top=bottom+f['opening_height']
        color=KitchenLab::FINISHES[d['finish']] || '#EAE8DF'
        add.call('Trim niche / left',edge,fy,bottom,cx-edge,0.75,top-bottom,color)
        add.call('Trim niche / right',d['width']-cx,fy,bottom,cx-edge,0.75,top-bottom,color)
        add.call('Trim niche / lower',cx,fy,bottom,kit['cutout_width'],0.75,floor-bottom,color)
        add.call('Trim niche / upper',cx,fy,roof,kit['cutout_width'],0.75,top-roof,color)
        add.call('Trim duct support',cx,fy,floor-0.75,kit['cutout_width'],kit['cutout_depth'],0.75,color)
      elsif f['mode']!='over_range'
        ow=f['opening_width'];edge=(d['width']-ow)/2
        cleat=f['cleat'];cw=cleat ? cleat['width'] : (f['niche_width'] ? (ow-f['niche_width'])/2 : 0)
        if cw>0
          fy=f['fascia_y']+(cleat ? cleat['inset'] : f.fetch('front_projection',0))
          dd=cleat ? cleat['depth'] : 1
          zz=f.fetch('opening_bottom',0);hh=cleat ? cleat['height'] : f['opening_height']
          color=KitchenLab::FINISHES[d['finish']] || '#EAE8DF'
          add.call('Installation left cleat',edge,fy,zz,cw,dd,hh,color)
          add.call('Installation right cleat',edge+ow-cw,fy,zz,cw,dd,hh,color)
        end
      end
      out
    end
    def self.build(entities,d)
      parts(d).each do |p|
        mat=KitchenLab.material('Installation '+p['color'],p['color'])
        KitchenLab.box(entities,p['name'],p['x'],p['y'],p['z'],p['width'],p['depth'],p['height'],mat)
      end
    end
    def self.commands(source,appliance,options={})
      f=appliance.dig('appliance','installation_fit');return nil unless f
      id=appliance['id'];s=source['settings'];w=appliance['width'];h=appliance['height']
      z=appliance['z'];depth=f['cabinet_depth'];opening=f['opening_width']
      total=Float(options.fetch('total_height',90))
      raise 'Cabinet top must be between 80 and 96 inches.' unless total.finite? && total.between?(80,96)
      if options.key?('depth') && Float(options['depth'])<depth-0.001
        raise "This model requires a cabinet at least #{depth} inches deep."
      end
      # Source back line remains the cabinet back. Shift the device alone to
      # its measured fascia plane; bundle movement later preserves this offset.
      origin=Spatial.cabinet_point(appliance,0,0,s)
      px=Spatial.cabinet_point(appliance,1,0,s);py=Spatial.cabinet_point(appliance,0,1,s)
      u=px.zip(origin).map { |a,b|a-b };v=py.zip(origin).map { |a,b|a-b }
      angle=Math.atan2(u[1],u[0])*180/Math::PI;hand=u[0]*v[1]-u[1]*v[0]<0 ? -1 : 1
      pose=lambda do |x,y|
        p=Spatial.cabinet_point(appliance,x,y,s)
        {'x'=>p[0],'y'=>p[1],'angle'=>angle,'handedness'=>hand}
      end
      offset=f['mode']=='over_range' ? 0 : -depth-f['fascia_y']-f.fetch('front_projection',0)
      z=[z,f.fetch('minimum_bottom',0)].max
      changes={'manufacturer_fit'=>1,'house_placement'=>pose.call(0,offset),'flip_x'=>false,'flip_y'=>false,'z'=>z}
      commands=[{'type'=>'update_cabinet','payload'=>{'id'=>id,'changes'=>changes}}]
      part=lambda do |role,kind,x,zz,ww,hh,dd=depth,yy=0,extra={}|
        commands<<{'type'=>'create_cabinet','payload'=>{'id'=>'c-'+SecureRandom.hex(8),'kind'=>kind,'wall'=>appliance['wall'],
          'overrides'=>{'x'=>0,'z'=>zz,'width'=>ww,'height'=>hh,'depth'=>dd,'toe_height'=>0,'surround_for'=>id,'surround_part'=>role,'house_placement'=>pose.call(x,yy)}.merge(extra)}}
      end
      gap=(opening-w)/2;left=-gap
      if f['mode']=='over_range'
        upper_z=z+h
        raise 'Leave at least 8.25 inches for the upper cabinet.' if total-upper_z<8.25
        part.call('upper','wall',left,upper_z,opening,total-upper_z)
        %w[left right].each { |r|part.call(r,'filler',r=='left' ? left-0.75 : w+gap,z,0.75,total-z) }
      else
        bottom=z+f.fetch('opening_bottom',0);top=bottom+f['opening_height']
        lower_top=bottom-0.75
        raise 'Leave at least 8.25 inches for upper and lower storage.' if total-top<8.25 || lower_top-4<8.25
        part.call('left','filler',left-0.75,0,0.75,total,depth,0,{'toe_height'=>4,'toe_setback'=>3})
        part.call('right','filler',w+gap,0,0.75,total,depth,0,{'toe_height'=>4,'toe_setback'=>3})
        service=f.fetch('rear_service_depth',0)
        part.call('lower','wall',left,4,opening,lower_top-4,depth-service,-service,{'handle_position'=>'top'})
        part.call('plinth','filler',left,0,opening,4,0.75,-depth+3.75)
        part.call('bottom','filler',left,lower_top,opening,0.75)
        part.call('upper','wall',left,top,opening,total-top)
      end
      commands
    end
    def self.build_support(entities,d,mat)
      return false unless d['surround_part']=='bottom'
      owner=KitchenLab.document['cabinets'].find { |c|c['id']==d['surround_for'] }
      f=owner && profile(owner);return false unless f && f['rear_service_width']
      w=d['width'];dep=d['depth'];gap=f['rear_service_width'];back=f['rear_service_depth'];edge=(w-gap)/2
      KitchenLab.box(entities,'Ventilated support front',0,-dep,0,w,dep-back,d['height'],mat)
      [0,w-edge].each { |x|KitchenLab.box(entities,'Ventilated support side',x,-back,0,edge,back,d['height'],mat) }
      true
    end
  end
end

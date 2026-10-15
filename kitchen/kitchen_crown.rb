load File.join(__dir__,'kitchen_molding_profiles.rb')
# Kitchen-specific crown runs. Interior Pro files remain read-only.
module KitchenLab
  def self.crown_settings(raw={})
    s={'crown_profile'=>'none','crown_height'=>4.0,'crown_depth'=>3.0,'crown_color'=>'cabinet'}.merge(raw)
    raise 'Invalid house molding option' unless [nil,true,false].include?(s['crown_match_house'])
    MoldingProfiles.settings(s)
    s['crown_depth']=0.75 if s['crown_profile']=='flat'
    raise 'Invalid crown profile' unless %w[none flat crown].include?(s['crown_profile']) || s['crown_profile'].to_s.start_with?('house:')
    raise 'Invalid crown color' unless %w[cabinet white].include?(s['crown_color'])
    %w[crown_height crown_depth].each do |k|
      s[k]=Float(s[k]);raise 'Crown dimensions must be 0.5ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“12 inches' unless s[k].finite? && s[k].between?(k=='crown_depth' && s['crown_shape'] ? 0.01 : 0.5,12)
    end
    s
  end

  def self.crown_runs(data)
    runs=[]
    data.select { |d| %w[wall tall oven_tower micro_tower fridge_surround].include?(d['kind']) && d['surround_part']!='lower' }.sort_by { |d| [wall_of(d),d['z']+d['height'],d['depth'],d['x']] }.each do |d|
      r=runs.last
      if r && r[:wall]==wall_of(d) && (r[:right]-d['x']).abs<0.001 && (r[:top]-d['z']-d['height']).abs<0.001 && r[:depth]==d['depth'] && r[:finish]==d['finish']
        r[:right]=d['x']+d['width']
      else
        runs<<{left:d['x'],right:d['x']+d['width'],top:d['z']+d['height'],depth:d['depth'],finish:d['finish'],wall:wall_of(d)}
      end
    end
    runs
  end

  # A closed profile swept between two matching miter planes.
  def self.crown_piece(ents,name,profile,mat,&point)
    g=ents.add_group;g.name=name
    rings=[0,1].map { |end_index| profile.map { |d,z| point.call(end_index,d,z) } }
    g.entities.add_face(rings[0].reverse)
    g.entities.add_face(rings[1])
    profile.length.times do |i|
      j=(i+1)%profile.length
      g.entities.add_face(rings[0][i],rings[0][j],rings[1][j],rings[1][i])
    end
    raise 'Could not create solid crown' unless g.manifold?
    # Hide tessellation seams on curved surfaces; keep sharp profile and miter edges.
    g.entities.grep(Sketchup::Edge).each do |edge|
      next unless edge.faces.length==2
      angle=edge.faces[0].normal.angle_between(edge.faces[1].normal)
      angle=[angle,Math::PI-angle].min
      next unless angle<Math::PI/6
      edge.soft=true;edge.smooth=true
    end
    g.entities.grep(Sketchup::Face).each { |f| f.material=mat;f.back_material=mat }
    g.material=mat
    g
  end

  # Seat the outer lower edge on the carcass, rather than outside it.
  def self.seated_crown_shape(shape)
    bottom=shape.map(&:last).min
    edge=shape.select { |_,z| (z-bottom).abs<0.00001 }.map(&:first).max
    shape.map { |x,z| [x-edge,z-bottom] }
  end

  def self.crown_ceiling_for(d)
    return nil unless defined?(InteriorPro::CeilingManager)
    point=Geom::Point3d.new(d['width']/2.0,-d['depth']/2.0,0).transform(cabinet_transform(d))
    groups=@model.entities.grep(Sketchup::Group)
    room=groups.find do |g|
      next false unless g.get_attribute('InteriorPro','type')=='room'
      xy=g.get_attribute('InteriorPro','boundary_xy')
      next false unless xy && xy.length>=6
      poly=xy.each_slice(2).map { |x,y| Geom::Point3d.new(x.to_f,y.to_f,0) }
      Geom.point_in_polygon_2D(Geom::Point3d.new(point.x,point.y,0),poly,true)
    end
    return nil unless room
    id=room.get_attribute('InteriorPro','id')
    floor=InteriorPro::CeilingManager.room_floor_level(id)
    ceiling=groups.find { |g| g.get_attribute('InteriorPro','type')=='ceiling' && g.get_attribute('InteriorPro','room_id')==id }
    height=ceiling && ceiling.get_attribute('InteriorPro','ceiling_height_in')
    height=InteriorPro::CeilingManager.default_height_for_room(room,floor) unless height && height.to_f>0
    floor+height.to_f
  end

  def self.fit_cabinet_crowns!(height)
    doc=document;data=doc['cabinets'];changed=[]
    data.select { |d| d['kind']=='hood' }.each do |hood|
      parts=data.select { |d| d['surround_for']==hood['id'] }
      next unless %w[hood_front left right].all? { |role| parts.any? { |d| d['surround_part']==role } }
      ceiling=crown_ceiling_for(hood)
      next unless ceiling
      parts.each do |part|
        base=cabinet_transform(part).origin.z.to_f
        limit=ceiling-base-height
        raise 'Not enough space above the hood for this molding.' if limit<hood['height']-0.001
        next unless part['height']>limit+0.001
        part['height']=limit;changed<<part
      end
    end
    data.select { |d| %w[wall tall oven_tower micro_tower fridge_surround corner_upper].include?(d['kind']) && d['surround_part']!='lower' }.each do |d|
      ceiling=crown_ceiling_for(d)
      next unless ceiling
      limit=ceiling-cabinet_transform(d).origin.z.to_f-height
      next unless d['height']>limit+0.001
      # Appliance openings cannot be shortened without checking their fit.
      if %w[oven_tower micro_tower fridge_surround].include?(d['kind'])
        raise 'Cabinet and molding exceed the ceiling. Lower the appliance cabinet or choose a shorter molding.'
      end
      candidate=validate(d.merge('height'=>limit),doc['settings'])
      check_shaker(candidate,doc['settings'])
      data[data.index(d)]=candidate;changed<<candidate
    end
    return if changed.empty?
    write_document!(data,doc['settings'])
    changed.each do |d|
      cabinets.select { |g| g.get_attribute(DICT,'id')==d['id'] }.each(&:erase!)
      build(d)
    end
  end

  def self.crowns!
    @model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'kind')=='crown' }.each(&:erase!)
    s=crown_settings(settings);return if s['crown_profile']=='none'
    h=s['crown_height'];p=s['crown_depth']
    shape=s['crown_profile'].to_s.start_with?('house:') ? MoldingProfiles.shape(s) : s['crown_profile']=='flat' ? [[-p,0],[0,0],[0,h],[-p,h]] : [[0,0],[p*0.18,h*0.1],[p*0.55,h*0.82],[p*0.85,h*0.9],[p,h],[0,h]]
    shape=seated_crown_shape(shape)
    fit_cabinet_crowns!(h)
    data=state['cabinets']
    custom,regular=data,[]
    custom.select { |d| d['kind']=='corner_upper' }.each do |d|
      w=d['width'];arm=d['depth'];top=d['height']
      g=@model.entities.add_group;g.name='Kitchen / Corner crown';g.set_attribute(DICT,'kind','crown');g.set_attribute(DICT,'owner_id',d['id']);g.transformation=cabinet_transform(d)
      mat=s['crown_color']=='white' ? material('Crown white','#F5F3ED') : material(d['finish'],FINISHES.fetch(d['finish']))
      joints=[[w,0,1,0],[w,-arm,1,-1],[arm,-arm,1,-1],[arm,-w,1,-1],[0,-w,0,-1]]
      joints.each_cons(2).with_index do |ends,i|
        crown_piece(g.entities,"Corner crown #{i+1}",shape,mat) do |side,projection,z|
          x,y,nx,ny=ends[side];[x+nx*projection,y+ny*projection,top+z]
        end
      end
    end
    runs=crown_runs(regular)
    custom.each { |d| crown_runs([d.merge('x'=>0,'z'=>0)]).each { |r| runs<<r.merge(transform:cabinet_transform(d),owner_id:d['id']) } }
    # One continuous crown around the casing, owned by the hood assembly.
    custom.select { |d| d['kind']=='hood' }.each do |hood|
      parts=custom.select { |d| d['surround_for']==hood['id'] }
      front=parts.find { |d| d['surround_part']=='hood_front' }
      left=parts.find { |d| d['surround_part']=='left' }
      right=parts.find { |d| d['surround_part']=='right' }
      next unless front && left && right
      runs<<{left:0,right:front['width']+left['width']+right['width'],
        top:left['height'],depth:left['depth'],finish:front['finish'],
        transform:cabinet_transform(left),owner_id:hood['id']}
    end
    runs.each do |r|
      g=@model.entities.add_group;g.name='Kitchen / Crown';g.set_attribute(DICT,'kind','crown');g.set_attribute(DICT,'owner_id',r[:owner_id])
      g.transformation=r[:transform]||wall_transform(r[:wall])
      mat=s['crown_color']=='white' ? material('Crown white','#F5F3ED') : material(r[:finish],FINISHES.fetch(r[:finish]))
      l=r[:left];rr=r[:right];y=-r[:depth];top=r[:top]
      cover=lambda do |edge,left|
        next 0 if r[:transform]
        data.select { |c| wall_of(c)==r[:wall] && ((left ? c['x']+c['width'] : c['x'])-edge).abs<0.001 && c['z']<=top && c['z']+c['height']>=top-0.001 }.map { |c| c['depth'] }.max || 0
      end
      left_back=-[cover.call(l,true),r[:depth]].min
      right_back=-[cover.call(rr,false),r[:depth]].min
      left_return=left_back>y+0.001;right_return=right_back>y+0.001
      crown_piece(g.entities,'Crown front',shape,mat) { |side,d,z| [side==0 ? l-(left_return ? d : 0) : rr+(right_return ? d : 0),y-d,top+z] }
      crown_piece(g.entities,'Crown left return',shape,mat) { |side,d,z| [l-d,side==0 ? left_back : y-d,top+z] } if left_return
      crown_piece(g.entities,'Crown right return',shape,mat) { |side,d,z| [rr+d,side==0 ? y-d : right_back,top+z] } if right_return
    end
  end
end

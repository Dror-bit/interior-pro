module KitchenLab
  def self.wall_of(d);d.fetch('wall','A');end
  def self.wall_transform(wall)
    s=settings;p=Spatial.pose(s)
    o=Spatial.point(wall,0,0,s);x=Spatial.point(wall,1,0,s);y=Spatial.point(wall,0,1,s)
    Geom::Transformation.axes(Geom::Point3d.new(o[0],o[1],p['z']),Geom::Vector3d.new(x[0]-o[0],x[1]-o[1],0),Geom::Vector3d.new(y[0]-o[0],y[1]-o[1],0),Z_AXIS)
  end
  def self.cabinet_transform(d)
    if d['house_placement']
      o=Spatial.cabinet_point(d,0,0,settings);a=Spatial.cabinet_point(d,1,0,settings);b=Spatial.cabinet_point(d,0,1,settings)
      return Geom::Transformation.axes(Geom::Point3d.new(o[0],o[1],Spatial.pose(settings)['z']+d['z']),Geom::Vector3d.new(a[0]-o[0],a[1]-o[1],0),Geom::Vector3d.new(b[0]-o[0],b[1]-o[1],0),Z_AXIS)
    end
    c=Spatial.cabinet_pivot(d)+[0]
    mirror=Geom::Transformation.scaling(Geom::Point3d.new(d['width']/2.0,-d['depth']/2.0,0),d.fetch('flip_x',false) ? -1 : 1,d.fetch('flip_y',false) ? -1 : 1,1)
    wall_transform(wall_of(d))*Geom::Transformation.translation([d['x'],d.fetch('offset_y',0),d['z']])*Geom::Transformation.rotation(c,Z_AXIS,d.fetch('rotation',0)*Math::PI/180.0)*mirror
  end
  def self.footprint(d,s=settings)
    points=Spatial.polygon(d,s);xx=points.map(&:first);yy=points.map(&:last)
    [xx.min,xx.max,yy.min,yy.max]
  end
  def self.overlap?(a,b,s=settings)
    Spatial.overlap?(a,b,s)
  end
  def self.move_island(raw)
    guard!
    s=settings.merge('island_x'=>Float(raw.fetch('x')),'island_y'=>Float(raw.fetch('y')),'island_angle'=>Float(raw.fetch('angle',settings.fetch('island_angle',0))))
    raise 'Island position must be -1200–1200 inches' unless %w[island_x island_y].all? { |k| s[k].finite? && s[k].between?(-1200,1200) }
    raise 'Invalid island angle' unless s['island_angle'].finite? && s['island_angle'].between?(-360,360)
    data=state['cabinets'];raise 'Island overlaps another cabinet' if data.combination(2).any? { |a,b| overlap?(a,b,s) }
    @model.start_operation('Kitchen: move island',true)
    begin
      write_document!(data,s)
      cabinets.each do |g|
        d=JSON.parse(g.get_attribute(DICT,'data'));g.transformation=cabinet_transform(d) if wall_of(d)=='I'
      end
      worktops!;@model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    publish
  end
  def self.move_kitchen(raw)
    guard!
    p=%w[x y z angle].to_h { |k| [k,Float(raw.fetch(k))] }
    p['level']=Integer(raw.fetch('level'))
    raise 'Invalid kitchen position' unless %w[x y z].all? { |k| p[k].finite? && p[k].between?(-12000,12000) }
    raise 'Invalid kitchen angle' unless p['angle'].finite? && p['angle'].between?(-360,360)
    raise 'Invalid level' unless p['level'].between?(1,100)
    @model.start_operation('Kitchen: place in house',true)
    begin
      write_document!(state['cabinets'],settings.merge('kitchen_pose'=>p))
      cabinets.each do |g|
        d=JSON.parse(g.get_attribute(DICT,'data'));g.transformation=cabinet_transform(d)
      end
      worktops!;@model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    publish
  end
  def self.add_corner(kind='corner_base')
    guard!
    raise 'Invalid corner type' unless %w[corner corner_base corner_upper corner_lazy].include?(kind)
    all=state['cabinets'];upper=kind=='corner_upper'
    replaced=all.select { |d| any_corner?(d) && (d['kind']=='corner_upper')==upper }
    data=all-replaced
    size=upper ? 24 : kind=='corner' ? 27 : 36
    corner=validate({'id'=>replaced.first&.fetch('id')||"corner-#{SecureRandom.hex(4)}",'kind'=>kind,'width'=>size,'depth'=>upper ? 12 : kind=='corner' ? 27 : 24,'height'=>upper ? 30 : 34.5,'z'=>upper ? 54 : 0,'wall'=>'A','style'=>kind=='corner' ? 'slab' : 'shaker','handle'=>kind=='corner' ? 'none' : 'brass'})
    corner=global_appearance(corner.merge('appearance_overrides'=>{}))
    shifts=%w[A B].to_h do |wall|
      candidates=data.select { |d| !any_corner?(d) && wall_of(d)==wall && [d['z']+d['height'],corner['z']+corner['height']].min>[d['z'],corner['z']].max }
      [wall,[size-(candidates.map { |c| c['x'] }.min||size),0].max]
    end
    proposed=data.map do |d|
      delta=any_corner?(d) ? 0 : shifts.fetch(wall_of(d),0)
      d.merge('x'=>d['x']+delta)
    end+[corner]
    proposed.each { |d| validate(d) }
    raise 'Corner would overlap existing cabinets' if proposed.combination(2).any? { |a,b| overlap?(a,b) }
    @model.start_operation('Kitchen: add corner cabinet',true)
    begin
      write_document!(proposed)
      cabinets.select { |g| replaced.any? { |d| g.get_attribute(DICT,'id')==d['id'] } }.each(&:erase!)
      data.each do |d|
        nd=proposed.find { |c| c['id']==d['id'] };g=cabinets.find { |c| c.get_attribute(DICT,'id')==d['id'] }
        g ||= build(nd)
        g.transformation=cabinet_transform(nd);g.set_attribute(DICT,'data',JSON.generate(nd))
      end
      build(corner);worktops!;@model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    publish
  end
end

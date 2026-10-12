# Kitchen-specific crown runs. Interior Pro files remain read-only.
module KitchenLab
  def self.crown_settings(raw={})
    s={'crown_profile'=>'none','crown_height'=>4.0,'crown_depth'=>3.0,'crown_color'=>'cabinet'}.merge(raw)
    raise 'Invalid crown profile' unless %w[none flat crown].include?(s['crown_profile'])
    raise 'Invalid crown color' unless %w[cabinet white].include?(s['crown_color'])
    %w[crown_height crown_depth].each do |k|
      s[k]=Float(s[k]);raise 'Crown dimensions must be 0.5–12 inches' unless s[k].finite? && s[k].between?(0.5,12)
    end
    s
  end

  def self.crown_runs(data)
    runs=[]
    data.select { |d| %w[wall tall oven_tower micro_tower fridge_surround].include?(d['kind']) }.sort_by { |d| [wall_of(d),d['z']+d['height'],d['depth'],d['x']] }.each do |d|
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
    g.entities.grep(Sketchup::Face).each { |f| f.material=mat;f.back_material=mat }
    g.material=mat
    g
  end

  def self.crowns!
    @model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'kind')=='crown' }.each(&:erase!)
    s=crown_settings(settings);return if s['crown_profile']=='none'
    h=s['crown_height'];p=s['crown_depth']
    shape=s['crown_profile']=='flat' ? [[0,0],[p,0],[p,h],[0,h]] : [[0,0],[p*0.18,h*0.1],[p*0.55,h*0.82],[p*0.85,h*0.9],[p,h],[0,h]]
    data=state['cabinets']
    custom,regular=data.partition { |d| d['house_placement'] || d.fetch('rotation',0)!=0 || d.fetch('offset_y',0)!=0 || d['flip_x'] || d['flip_y'] }
    runs=crown_runs(regular)
    custom.each { |d| crown_runs([d.merge('x'=>0,'z'=>0)]).each { |r| runs<<r.merge(transform:cabinet_transform(d)) } }
    runs.each do |r|
      g=@model.entities.add_group;g.name='Kitchen / Crown';g.set_attribute(DICT,'kind','crown')
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

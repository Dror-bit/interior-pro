require 'digest'
load File.join(__dir__,'kitchen_molding_profiles.rb')
# Kitchen-specific crown runs. Interior Pro files remain read-only.
module KitchenLab
  remove_const(:USE_KITCHEN_MOLDING_JOIN) if const_defined?(:USE_KITCHEN_MOLDING_JOIN, false)
  USE_KITCHEN_MOLDING_JOIN = true
  remove_const(:USE_HOOD_MOLDING_OPTION) if const_defined?(:USE_HOOD_MOLDING_OPTION, false)
  USE_HOOD_MOLDING_OPTION = true
  def self.hood_molding?(hood)
    USE_HOOD_MOLDING_OPTION && hood['hood_molding']==true
  end
  def self.hood_crown_settings
    s=crown_settings(settings)
    s['crown_profile']=='none' ? crown_settings(s.merge('crown_profile'=>'flat','crown_height'=>6.0,'crown_depth'=>0.75,'crown_match_house'=>false)) : s
  end
  remove_const(:USE_KITCHEN_CEILING_FIT) if const_defined?(:USE_KITCHEN_CEILING_FIT, false)
  USE_KITCHEN_CEILING_FIT = true
  def self.crown_settings(raw={})
    s={'crown_profile'=>'flat','crown_height'=>6.0,'crown_depth'=>0.75,'crown_color'=>'cabinet'}.merge(raw)
    raise 'Invalid house molding option' unless [nil,true,false].include?(s['crown_match_house'])
    MoldingProfiles.settings(s)
    s['crown_depth']=0.75 if s['crown_profile']=='flat'
    raise 'Invalid crown profile' unless %w[none flat crown].include?(s['crown_profile']) || s['crown_profile'].to_s.start_with?('house:')
    raise 'Invalid crown color' unless %w[cabinet white].include?(s['crown_color'])
    %w[crown_height crown_depth].each do |k|
      s[k]=Float(s[k]);raise 'Crown dimensions must be 0.5–12 inches' unless s[k].finite? && s[k].between?(k=='crown_depth' && s['crown_shape'] ? 0.01 : 0.5,12)
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

  remove_const(:USE_APPLIANCE_PANEL_CROWN_FIT) if const_defined?(:USE_APPLIANCE_PANEL_CROWN_FIT,false)
  USE_APPLIANCE_PANEL_CROWN_FIT=true
  def self.appliance_panel_crown_height(part,upper,s)
    flat=s['crown_profile']=='flat'
    points=s.dig('crown_shape','points') if s['crown_profile'].to_s.start_with?('house:')
    if points && points.uniq.length==4
      flat=points.map(&:first).uniq.length==2 && points.map(&:last).uniq.length==2
    end
    upper['z']+upper['height']-part['z']+(flat ? s['crown_height'] : 0)
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
        limit=ceiling-base-(hood_molding?(hood) ? hood_crown_settings['crown_height'] : 0)
        raise 'Not enough space above the hood for this molding.' if limit<hood['height']-0.001
        next if (part['height']-limit).abs<0.001
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
    if USE_APPLIANCE_PANEL_CROWN_FIT
      s=crown_settings(doc['settings'])
      if s['crown_profile']!='none'
        data.select { |d|%w[fridge wall_oven].include?(d['kind']) }.each do |appliance|
          parts=data.select { |d|d['surround_for']==appliance['id'] }
          upper=parts.find { |d|d['surround_part']=='upper' };next unless upper
          parts.select { |d|%w[left right].include?(d['surround_part']) }.each do |part|
            target=appliance_panel_crown_height(part,upper,s)
            ceiling=crown_ceiling_for(part)
            target=[target,ceiling-cabinet_transform(part).origin.z.to_f].min if ceiling
            raise 'Not enough height for appliance side panel.' unless target>0
            next if (part['height']-target).abs<0.001
            part['height']=target;changed<<part
          end
        end
      end
    end
    return if changed.empty?
    write_document!(data,doc['settings'])
    changed.uniq { |d|d['id'] }.each do |d|
      cabinets.select { |g| g.get_attribute(DICT,'id')==d['id'] }.each(&:erase!)
      build(d)
    end
  end

  def self.crowns!
    s=crown_settings(settings)
    fit_cabinet_crowns!(s['crown_profile']=='none' ? 0 : s['crown_height']) if USE_KITCHEN_CEILING_FIT
    return CrownJoints.build!(s) if USE_KITCHEN_MOLDING_JOIN && defined?(InteriorPro::MoldingBuilder)
    @model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'kind')=='crown' }.each(&:erase!)
    cabinet_crowns=s['crown_profile']!='none'
    return unless cabinet_crowns || state['cabinets'].any? { |d| d['kind']=='hood' && hood_molding?(d) }
    s=hood_crown_settings unless cabinet_crowns
    h=s['crown_height'];p=s['crown_depth']
    shape=s['crown_profile'].to_s.start_with?('house:') ? MoldingProfiles.shape(s) : s['crown_profile']=='flat' ? [[-p,0],[0,0],[0,h],[-p,h]] : [[0,0],[p*0.18,h*0.1],[p*0.55,h*0.82],[p*0.85,h*0.9],[p,h],[0,h]]
    shape=seated_crown_shape(shape)
    data=state['cabinets']
    custom,regular=data,[]
    custom.select { |d| cabinet_crowns && d['kind']=='corner_upper' }.each do |d|
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
    (cabinet_crowns ? custom : []).each { |d| crown_runs([d.merge('x'=>0,'z'=>0)]).each { |r| runs<<r.merge(transform:cabinet_transform(d),owner_id:d['id']) } }
    # One continuous crown around the casing, owned by the hood assembly.
    custom.select { |d| d['kind']=='hood' && hood_molding?(d) }.each do |hood|
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

# Shared endpoints only: house corner/tee/room policies remain in MoldingManager.
module KitchenLab::CrownJoints
  extend self
  EPS=0.001 unless const_defined?(:EPS,false)
  def v(x,y,z=0); Geom::Vector3d.new(x,y,z); end
  def pt(x,y,z=0); Geom::Point3d.new(x,y,z); end
  def cross(a,b); a.x*b.y-a.y*b.x; end
  def line_hit(a,u,b,w)
    den=cross(u,w);return nil if den.abs<1e-8
    a.offset(u,u.length*cross(b-a,w)/den)
  end
  def poly(d)
    w=d['width'];h=d['depth'];t=KitchenLab.cabinet_transform(d)
    xy=d['kind']=='corner_upper' ? [[0,0],[w,0],[w,-h],[h,-h],[h,-w],[0,-w]] : [[0,0],[w,0],[w,-h],[0,-h]]
    xy.map { |x,y| p=pt(x,y).transform(t);pt(p.x,p.y) }
  end
  def inside?(p,poly); Geom.point_in_polygon_2D(p,poly,false); end
  def segment(a,b,n,shape,base,owner,mat,extra={})
    {a:a,b:b,n:n,shape:shape,base:base,owner:owner,mat:mat}.merge(extra)
  end
  def exposed_runs(r,obstacles)
    u=r[:b]-r[:a];len=u.length;return [] if len<EPS;u.normalize!
    cuts=[0.0,len]
    obstacles.each do |o|
      o[:poly].each_with_index do |a,i|
        b=o[:poly][(i+1)%o[:poly].length];w=b-a
        hit=line_hit(r[:a],u,a,w);next unless hit
        along=(hit-r[:a]).dot(u);fraction=(hit-a).dot(w)/w.length**2
        cuts<<[[along,0].max,len].min if along>-EPS && along<len+EPS && fraction>=-EPS && fraction<=1+EPS
      end
    end
    cuts.sort.uniq.each_cons(2).filter_map do |a,b|
      next if b-a<EPS
      mid=r[:a].offset(u,(a+b)/2).offset(r[:n],0.002)
      next if obstacles.any? { |o| inside?(mid,o[:poly]) }
      r.merge(a:r[:a].offset(u,a),b:r[:a].offset(u,b),cut_a:a>EPS,cut_b:b<len-EPS)
    end
  end
  def carriers(data,s)
    items=data.select { |d| s['crown_profile']!='none' && %w[wall tall oven_tower micro_tower fridge_surround corner_upper].include?(d['kind']) && d['surround_part']!='lower' }
    if USE_APPLIANCE_CROWN_ENVELOPE && s['crown_profile']!='none'
      data.select { |d|%w[fridge wall_oven].include?(d['kind']) }.each do |appliance|
        parts=data.select { |d|d['surround_for']==appliance['id'] }
        left=parts.find { |d|d['surround_part']=='left' };right=parts.find { |d|d['surround_part']=='right' };upper=parts.find { |d|d['surround_part']=='upper' }
        next unless left && right && upper
        # Crown follows the outside casing, including both side panels. Its
        # owner is the bundle, so its own panels cannot clip away the returns.
        items.reject! { |d|d['id']==upper['id'] }
        items<<left.merge('id'=>appliance['id'],'kind'=>'fridge_surround',
          'width'=>left['width']+upper['width']+right['width'],
          'height'=>upper['z']+upper['height']-left['z'],
          'depth'=>[left['depth'],upper['depth'],right['depth']].max,
          'finish'=>upper['finish'])
      end
    end
    data.select { |d| d['kind']=='hood' && KitchenLab.hood_molding?(d) }.each do |hood|
      parts=data.select { |d| d['surround_for']==hood['id'] };left=parts.find { |d| d['surround_part']=='left' };right=parts.find { |d| d['surround_part']=='right' };front=parts.find { |d| d['surround_part']=='hood_front' }
      next unless left && right && front
      items<<left.merge('id'=>hood['id'],'kind'=>'hood_crown','width'=>left['width']+front['width']+right['width'])
    end
    items
  end
  remove_const(:USE_APPLIANCE_CROWN_ENVELOPE) if const_defined?(:USE_APPLIANCE_CROWN_ENVELOPE,false)
  USE_APPLIANCE_CROWN_ENVELOPE=true
  def shape(s)
    h=s['crown_height'];d=s['crown_depth']
    raw=s['crown_profile'].start_with?('house:') ? KitchenLab::MoldingProfiles.shape(s) : s['crown_profile']=='flat' ? [[-d,0],[0,0],[0,h],[-d,h]] : [[0,0],[d*0.18,h*0.1],[d*0.55,h*0.82],[d*0.85,h*0.9],[d,h],[0,h]]
    KitchenLab.seated_crown_shape(raw)
  end
  def walls
    Sketchup.active_model.entities.grep(Sketchup::Group).select { |g|g.get_attribute('InteriorPro','type')=='wall' }
  end
  def wall_obstacles
    walls.filter_map do |wall|
      edges=InteriorPro::MoldingBuilder.wall_edges(wall);next unless edges
      lo=InteriorPro::MoldingBuilder.wall_base_z(wall).to_f
      {poly:[edges[:pos][0],edges[:pos][1],edges[:neg][1],edges[:neg][0]],lo:lo,hi:lo+wall.get_attribute('InteriorPro','height').to_f,wall:wall}
    end
  end
  def cabinet_obstacles(data)
    data.map do |d|
      lo=KitchenLab.cabinet_transform(d).origin.z.to_f
      {poly:poly(d),lo:lo,hi:lo+d['height'],owner:d['surround_for']||d['id']}
    end
  end
  def kitchen_runs(items,s,obstacles)
    items.flat_map do |d|
      ss=d['kind']=='hood_crown' ? KitchenLab.hood_crown_settings : s
      points=poly(d);center=pt(points.sum(&:x)/points.length,points.sum(&:y)/points.length)
      base=KitchenLab.cabinet_transform(d).origin.z.to_f+d['height']
      mat=s['crown_color']=='white' ? KitchenLab.material('Crown white','#F5F3ED') : KitchenLab.material(d['finish'],KitchenLab::FINISHES.fetch(d['finish']))
      # Back edges never receive a return. Mirrored transforms are supported.
      indexes=d['kind']=='corner_upper' ? [1,2,3,4] : [1,2,3]
      indexes.flat_map do |i|
        a=points[i];b=points[(i+1)%points.length];u=b-a;n=v(-u.y,u.x);n.normalize!
        # Local polygon has clockwise winding; reflection reverses it.
        area=points.each_with_index.sum { |p,j|q=points[(j+1)%points.length];p.x*q.y-q.x*p.y }
        n.reverse! if area>0
        r=segment(a,b,n,shape(ss),base,d['id'],mat)
        stops=obstacles.select { |o|o[:owner]!=d['id'] && o[:lo]<base+ss['crown_height']-EPS && o[:hi]>=base-EPS }
        # A tiny fitting gap at a side wall is not an exposed cabinet side.
        # Omit that return so the front meets the house run, rather than picking
        # a false outside corner with its own return inside the wall clearance.
        projection=[r[:shape].map(&:first).max,0].max
        blocked=stops.select { |o|o[:wall] }.any? do |o|
          [0.01,0.5,0.99].all? do |fraction|
            sample=a.offset(u,u.length*fraction)
            o[:poly].each_with_index.any? do |p,j|
              q=o[:poly][(j+1)%o[:poly].length];edge=q-p
              next false unless cross(u,edge).abs/(u.length*edge.length)<0.001
              hit=line_hit(sample,n,p,edge);next false unless hit
              distance=(hit-sample).dot(n);along=(hit-p).dot(edge)/edge.length**2
              distance>=-EPS && distance<projection+EPS && along>=-EPS && along<=1+EPS
            end
          end
        end
        next [] if blocked
        exposed_runs(r,stops)
      end
    end
  end
  # Join nearby, opposing returns when their profiles would collide. The
  # narrow gap becomes part of the crown envelope, not two inward-facing trims.
  # Cabinet bodies and their positions are never expanded or moved.
  def close_crown_gaps(items,s,obstacles)
    raw=[]
    items.each do |d|
      ss=d['kind']=='hood_crown' ? KitchenLab.hood_crown_settings : s
      pp=poly(d);base=KitchenLab.cabinet_transform(d).origin.z.to_f+d['height']
      area=pp.each_with_index.sum { |p,i|q=pp[(i+1)%pp.length];p.x*q.y-q.x*p.y }
      indexes=d['kind']=='corner_upper' ? [1,2,3,4] : [1,2,3]
      indexes.each do |i|
        a=pp[i];b=pp[(i+1)%pp.length];u=b-a;n=v(-u.y,u.x);n.normalize!;n.reverse! if area>0
        mat=s['crown_color']=='white' ? KitchenLab.material('Crown white','#F5F3ED') : KitchenLab.material(d['finish'],KitchenLab::FINISHES.fetch(d['finish']))
        raw<<segment(a,b,n,shape(ss),base,d['id'],mat,carrier:d,polygon:pp)
      end
    end
    bridges=[];connectors=[]
    raw.combination(2) do |r,o|
      next if r[:owner]==o[:owner] || (r[:base]-o[:base]).abs>0.02
      next unless r[:n].dot(o[:n]) < -0.999999
      next unless r[:shape].length==o[:shape].length && r[:shape].zip(o[:shape]).all? { |a,b|(a[0]-b[0]).abs<0.02 && (a[1]-b[1]).abs<0.02 }
      gap=(o[:a]-r[:a]).dot(r[:n])
      reach=[r[:shape].map(&:first).max,0].max+[o[:shape].map(&:first).max,0].max
      next unless gap>EPS && gap<reach-EPS
      u=r[:b]-r[:a];len=u.length.to_f;u.normalize!
      limits=[(o[:a]-r[:a]).dot(u),(o[:b]-r[:a]).dot(u)].sort
      lo=[0.0,limits[0]].max;hi=[len,limits[1]].min
      next unless hi-lo>EPS
      a=r[:a].offset(u,lo);b=r[:a].offset(u,hi);c=b.offset(r[:n],gap);d=a.offset(r[:n],gap)
      shape_height=r[:shape].map(&:last).max
      bridges<<{poly:[a,b,c,d],lo:r[:base]-EPS,hi:r[:base]+shape_height,owner:'gap-'+bridges.length.to_s}
      [[a,d,u.reverse],[c,b,u]].each do |start,finish,normal|
        # A bridge along the backs of both cabinets needs no back molding.
        next if on_crown_back?(start,r) && on_crown_back?(finish,o) || on_crown_back?(start,o) && on_crown_back?(finish,r)
        connector=segment(start,finish,normal,r[:shape],r[:base],r[:owner],r[:mat])
        stops=obstacles.select { |ob|ob[:lo]<r[:base]+shape_height-EPS && ob[:hi]>=r[:base]-EPS }
        connectors.concat(exposed_runs(connector,stops))
      end
    end
    [bridges,connectors]
  end
  def merge_straight_runs(source)
    runs=source.map(&:dup)
    loop do
      pair=nil
      runs.each_with_index do |a,i|
        ((i+1)...runs.length).each do |k|
          b=runs[k]
          next unless (a[:base]-b[:base]).abs<0.001 && a[:mat]==b[:mat] && a[:shape]==b[:shape] && a[:n].dot(b[:n])>0.999999
          next unless [a[:a].distance(b[:a]),a[:a].distance(b[:b]),a[:b].distance(b[:a]),a[:b].distance(b[:b])].map(&:to_f).min<0.001
          u=a[:b]-a[:a];u.normalize!
          next unless cross(u,b[:b]-b[:a]).abs<0.001
          points=[a[:a],a[:b],b[:a],b[:b]].sort_by { |p|(p-a[:a]).dot(u) }
          pair=[i,k,points.first,points.last];break
        end
        break if pair
      end
      break unless pair
      i,k,a,b=pair;runs[i][:a]=a;runs[i][:b]=b;runs.delete_at(k)
    end
    runs
  end

  def on_crown_back?(point,row)
    pp=row[:polygon];indexes=row[:carrier]['kind']=='corner_upper' ? [0,pp.length-1] : [0]
    indexes.any? do |i|
      a=pp[i];b=pp[(i+1)%pp.length];edge=b-a;length=edge.length.to_f
      next false if length<EPS
      along=(point-a).dot(edge)/(length*length)
      cross(point-a,edge).abs/length<0.01 && along>=-EPS && along<=1+EPS
    end
  end

  def house_runs(data,items)
    builder=InteriorPro::MoldingBuilder;manager=InteriorPro::MoldingManager
    groups=Sketchup.active_model.entities.grep(Sketchup::Group).select { |g|g.get_attribute('InteriorPro','type')=='crown' }
    plan=[]
    groups.each do |g|
      wall=walls.find { |w|w.get_attribute('InteriorPro','id')==g.get_attribute('InteriorPro','host_wall_id') };next unless wall
      side=g.get_attribute('InteriorPro','side').to_sym;edges=builder.wall_edges(wall);next unless edges && edges[side]
      geo=builder.edge_geometry(wall,edges[side]);next unless geo
      plan<<{wall:wall,side:side,edge:edges[side],geo:geo,shifts:{start:0,end:0},tee_gaps:[],group:g}
    end
    # Include excluded sides in the resolver just as the house builder does;
    # they still shape T junctions, but are never generated here.
    full=[];cent={};ws=manager.walls(Sketchup.active_model)
    manager.wall_components(ws).each { |component| c=manager.house_centroid(component);component.each { |w|cent[w]=c } }
    ws.each do |w|
      next if w.get_attribute('InteriorPro','no_molding')
      edges=builder.wall_edges(w);next unless edges
      manager.sides_for(w,cent[w]).each do |side|
        geo=builder.edge_geometry(w,edges[side]);next unless geo
        full<<{wall:w,side:side,edge:edges[side],geo:geo,shifts:{start:0,end:0},tee_gaps:[]}
      end
    end
    manager.resolve_miters!(full);manager.resolve_tees!(full);manager.resolve_flush_butts!(full)
    plan.each do |r|
      original=full.find { |o|o[:wall]==r[:wall] && o[:side]==r[:side] }
      r.merge!(shifts:original[:shifts],tee_gaps:original[:tee_gaps]) if original
    end
    result=[];affected=[]
    plan.each do |r|
      g=r[:group];w=r[:wall];geo=r[:geo];height=w.get_attribute('InteriorPro','height').to_f;ch=w.get_attribute('InteriorPro','ceiling_h').to_f;height=ch if ch>12 && ch<height
      profile=InteriorPro::MoldingLibrary.crown_profile_by_name(g.get_attribute('InteriorPro','profile'),height,g.get_attribute('InteriorPro','profile_h'))
      next unless profile
      low=profile.map(&:last).min;high=profile.map(&:last).max;bz=builder.wall_base_z(w).to_f
      candidates=items.select { |d| top=KitchenLab.cabinet_transform(d).origin.z.to_f+d['height'];(top-low-bz).abs<0.02 }
      next if candidates.empty?
      # Only house sides actually touched by a kitchen carrier participate.
      nearby=candidates.select do |d|
        pp=poly(d);ds=pp.map { |p|(p-geo[:p0]).dot(geo[:nd]) };ts=pp.map { |p|(p-geo[:p0]).dot(geo[:u]) }
        ds.min<0.6 && ds.max>0 && ts.max>0 && ts.min<geo[:len]
      end
      next if nearby.empty?
      affected<<r
      gaps=r[:tee_gaps].map { |x|x.merge(kind: :tee) }+builder.stop_gaps(w,geo,low,high)
      seated=KitchenLab.seated_crown_shape(profile)
      anchor=profile.select { |_,z|(z-low).abs<EPS }.map(&:first).max
      obstacles=cabinet_obstacles(data).select { |o|o[:hi]>=low+bz-EPS && o[:lo]<high+bz-EPS }
      builder.segments_ex(geo[:len],gaps).each do |seg|
        a=geo[:p0].offset(geo[:u],seg[:a]).offset(geo[:nd],anchor);b=geo[:p0].offset(geo[:u],seg[:b]).offset(geo[:nd],anchor)
        sa=seg[:start_kind]==:run ? r[:shifts][:start] : seg[:start_kind]==:stop ? 0 : 1
        sb=seg[:end_kind]==:run ? r[:shifts][:end] : seg[:end_kind]==:stop ? 0 : -1
        row=segment(a,b,geo[:nd],seated,low+bz,nil,g.material,house:r,original_a:a,original_b:b,sa:sa,sb:sb,anchor:anchor)
        result.concat(exposed_runs(row,obstacles))
      end
    end
    [result,affected]
  end
  def resolve!(runs)
    updates=[]
    runs.each do |r|
      [:a,:b].each do |key|
        candidates=[]
        runs.each do |o|
          next if o.equal?(r) || (o[:base]-r[:base]).abs>0.02 || o[:shape].length!=r[:shape].length
          next unless o[:shape].zip(r[:shape]).all? { |a,b|(a[0]-b[0]).abs<0.02 && (a[1]-b[1]).abs<0.02 }
          [:a,:b].each do |other|
            next if r[key].distance(o[other])>1.0
            u=r[:b]-r[:a];w=o[:b]-o[:a];hit=line_hit(r[key],u,o[other],w)
            next unless hit && hit.distance(r[key])<1.0 && hit.distance(o[other])<1.0
            den=1+r[:n].dot(o[:n]);next if den.abs<0.01
            offset=(r[:n]+o[:n]);offset.length=offset.length/den
            candidates<<[hit.distance(r[key]),hit,offset]
          end
        end
        best=candidates.min_by(&:first);next unless best
        updates<<[r,key,best[1],best[2]]
      end
    end
    updates.each { |r,key,point,offset|r[key]=point;r[(key.to_s+'_offset').to_sym]=offset }
  end
  def make_piece(parent,r,obstacles=[])
    u=r[:b]-r[:a];return if u.length<EPS;u.normalize!
    g=KitchenLab.crown_piece(parent,'Crown segment',r[:shape],r[:mat]) do |side,d,z|
      key=side==0 ? :a : :b;p=r[key];offset=r[(key.to_s+'_offset').to_sym]
      if offset
        p=p.offset(offset,d*offset.length)
      else
        p=p.offset(r[:n],d)
        if r[:house] && !r[side==0 ? :cut_a : :cut_b]
          p=p.offset(u,r[side==0 ? :sa : :sb]*(d+r[:anchor]))
        end
      end
      [p.x,p.y,r[:base]+z]
    end
    obstacles.each do |o|
      next if o[:owner]==r[:owner] && r[:owner]
      bb=g.bounds;xs=o[:poly].map(&:x);ys=o[:poly].map(&:y)
      next unless [bb.max.x,xs.max].min-[bb.min.x,xs.min].max>EPS && [bb.max.y,ys.max].min-[bb.min.y,ys.min].max>EPS && [bb.max.z,o[:hi]].min-[bb.min.z,o[:lo]].max>EPS
      next if separated_projections?(solid_projection({group:g,world:g.transformation}),obstacle_projection(o))
      cutter=parent.add_group
      begin
        face=cutter.entities.add_face(o[:poly].map { |p|pt(p.x,p.y,o[:lo]) })
        raise 'Invalid molding boundary' unless face
        face.reverse! if face.normal.z<0;face.pushpull(o[:hi]-o[:lo])
        # Each operand is a separate solid. Never pushpull joined trim geometry.
        clipped=cutter.subtract(g)
        raise 'Unable to trim molding at boundary' unless clipped && clipped.valid? && clipped.manifold?
        g=clipped;g.name='Crown segment';g.material=r[:mat]
        InteriorPro::MoldingBuilder.soften_facets!(g.entities)
      ensure
        cutter.erase! if cutter.valid?
      end
    end
    g
  end

  remove_const(:USE_CROWN_REUSE) if const_defined?(:USE_CROWN_REUSE,false)
  USE_CROWN_REUSE=true
  def run_points(r)
    u=r[:b]-r[:a];u.normalize!
    [:a,:b].flat_map do |key|
      r[:shape].map do |d,z|
        offset=r[(key.to_s+'_offset').to_sym]
        p=offset ? r[key].offset(offset,d*offset.length) : r[key].offset(r[:n],d)
        if !offset && r[:house] && !r[key==:a ? :cut_a : :cut_b]
          p=p.offset(u,r[key==:a ? :sa : :sb]*(d+r[:anchor]))
        end
        [p.x.to_f,p.y.to_f,r[:base]+z]
      end
    end
  end
  def near_bounds?(a,b)
    return false if a.empty? || b.empty?
    3.times.all? { |i| a.map{|p|p[i]}.max+0.02>=b.map{|p|p[i]}.min && b.map{|p|p[i]}.max+0.02>=a.map{|p|p[i]}.min }
  end
  def crown_signature(own,runs,obstacles)
    points=own.flat_map { |r|run_points(r) }
    nearby=runs.filter_map do |r|
      pp=run_points(r)
      [r[:owner],!!r[:house],pp,r[:mat]&.name] if near_bounds?(points,pp)
    end
    cutters=obstacles.filter_map do |o|
      pp=[o[:lo],o[:hi]].flat_map { |z|o[:poly].map { |p|[p.x.to_f,p.y.to_f,z] } }
      [o[:owner],pp] if near_bounds?(points,pp)
    end
    normalize=lambda { |x| x.is_a?(Array) ? x.map{|v|normalize.call(v)} : x.is_a?(Numeric) ? x.to_f.round(6) : x }
    own_keys=normalize.call(own.map{|r|[run_points(r),r[:mat]&.name]}).sort_by{|x|JSON.generate(x)}
    nearby=normalize.call(nearby).sort_by{|x|JSON.generate(x)}
    cutters=normalize.call(cutters).sort_by{|x|JSON.generate(x)}
    Digest::SHA256.hexdigest(JSON.generate([own_keys,nearby,cutters]))
  end

  def build!(s)
    return unless defined?(InteriorPro::MoldingBuilder)
    model=Sketchup.active_model
    data=KitchenLab.state['cabinets'];items=carriers(data,s)
    obstacles=wall_obstacles+cabinet_obstacles(data)
    bridges,connectors=close_crown_gaps(items,s,obstacles)
    runs=merge_straight_runs(kitchen_runs(items,s,obstacles+bridges)+connectors)
    house,affected=house_runs(data,items)
    # Reconstruct only house sides that no longer meet the kitchen. The run
    # resolver reads wall/profile data, not the currently generated faces.
    restore_house!(affected.map { |record|record[:group] })
    resolve!(runs+house)
    @last_runs=runs+house
    # Cache each owner's finished crown using its resolved shape and all nearby
    # cutters/trim partners. Distant appliances cannot change this geometry.
    grouped=runs.group_by { |r|r[:owner] }
    existing=model.entities.grep(Sketchup::Group).select { |g|g.get_attribute(KitchenLab::DICT,'kind')=='crown' }
    reused=0
    changed_owners=[]
    grouped.each do |owner,own_runs|
      signature=crown_signature(own_runs,runs+house,obstacles)
      old=existing.select { |g|g.valid? && g.get_attribute(KitchenLab::DICT,'owner_id')==owner }
      if USE_CROWN_REUSE && old.length==1 && old.first.get_attribute(KitchenLab::DICT,'geometry_signature')==signature
        reused+=1
        next
      end
      old.each(&:erase!)
      changed_owners<<owner
      g=model.entities.add_group;g.name='Kitchen / Crown'
      g.set_attribute(KitchenLab::DICT,'kind','crown');g.set_attribute(KitchenLab::DICT,'owner_id',owner)
      own_runs.each { |r|make_piece(g.entities,r,obstacles) }
      g.set_attribute(KitchenLab::DICT,'geometry_signature',signature)
    end
    existing.each { |g|g.erase! if g.valid? && !grouped.key?(g.get_attribute(KitchenLab::DICT,'owner_id')) }
    reused_house=0
    affected.each do |record|
      own_runs=house.select { |r|r[:house].equal?(record) }
      signature=crown_signature(own_runs,runs+house,[])
      source=JSON.generate({shifts:record[:shifts],tee_gaps:record[:tee_gaps]})
      if USE_CROWN_REUSE && record[:group].get_attribute(KitchenLab::DICT,'house_geometry_signature')==signature
        record[:group].set_attribute(KitchenLab::DICT,'house_join_source',source) unless record[:group].get_attribute(KitchenLab::DICT,'house_join_source')==source
        reused_house+=1
        next
      end
      old=record[:group];replacement=model.entities.add_group;replacement.name=old.name;replacement.material=old.material;replacement.layer=old.layer;replacement.hidden=old.hidden?
      changed_owners<<'house'
      old.attribute_dictionaries&.each { |dict| dict.each_pair { |key,value|replacement.set_attribute(dict.name,key,value) } }
      replacement.set_attribute(KitchenLab::DICT,'house_join_source',source)
      own_runs.each { |r|make_piece(replacement.entities,r) }
      replacement.set_attribute(KitchenLab::DICT,'house_geometry_signature',signature)
      old.erase!
    end
    trimmed=trim_overlaps!(changed_owners:changed_owners) if USE_CROWN_OVERLAP_TRIM
    @report={reused_owners:reused,reused_house_sides:reused_house,trimmed_overlaps:trimmed.to_i,kitchen_runs:runs.length,house_runs:house.length,house_sides:affected.length,jointed_ends:(runs+house).sum { |r|[:a_offset,:b_offset].count { |k|r[k] } }}
  end
  # Miter resolution handles matching endpoints. This second pass handles
  # profiles whose projecting solids meet away from those endpoints. One board
  # owns the intersection; the other terminates flush against it. Never fuse
  # touching boards or alter unrelated house-only joints.
  remove_const(:USE_CROWN_OVERLAP_TRIM) if const_defined?(:USE_CROWN_OVERLAP_TRIM,false)
  USE_CROWN_OVERLAP_TRIM=true
  remove_const(:USE_INCREMENTAL_CROWN_TRIM) if const_defined?(:USE_INCREMENTAL_CROWN_TRIM,false)
  USE_INCREMENTAL_CROWN_TRIM=true
  def crown_solids(entities,transform=Geom::Transformation.new,owner=nil,result=[])
    entities.grep(Sketchup::Group).each do |group|
      own=owner
      own='house' if group.get_attribute('InteriorPro','type')=='crown'
      own=group.get_attribute(KitchenLab::DICT,'owner_id')||'kitchen' if group.get_attribute(KitchenLab::DICT,'kind')=='crown'
      world=transform*group.transformation
      if own && group.manifold?
        result<<{group:group,owner:own,parent:transform,world:world}
      else
        crown_solids(group.entities,world,own,result)
      end
    end
    result
  end
  # A separating plane is a proof that two closed pieces do not share volume.
  # Works conservatively for concave profiles too: uncertain cases still use CSG.
  def projection_geometry(points,axes)
    {points:points,axes:axes}
  end
  def solid_projection(row)
    row[:projection] ||= begin
      t=row[:world];faces=row[:group].entities.grep(Sketchup::Face)
      points=faces.flat_map(&:vertices).uniq.map { |vertex|vertex.position.transform(t) }
      axes=faces.filter_map do |face|
        pts=face.outer_loop.vertices.map { |vertex|vertex.position.transform(t) }
        next if pts.length<3
        edge=pts[1]-pts[0]
        normal=pts.drop(2).map { |p|edge.cross(p-pts[0]) }.find { |n|n.length.to_f>1e-8 }
        normal&.normalize
      end
      axes=axes.uniq { |n|n.to_a.map { |x|(x*1e7).round } }
      projection_geometry(points,axes)
    end
  end
  def obstacle_projection(obstacle)
    obstacle[:projection] ||= begin
      pp=obstacle[:poly]
      points=[obstacle[:lo],obstacle[:hi]].flat_map { |z| pp.map { |p|pt(p.x,p.y,z) } }
      axes=[v(0,0,1)]+pp.each_with_index.filter_map do |p,i|
        q=pp[(i+1)%pp.length];n=v(q.y-p.y,p.x-q.x)
        n.normalize if n.length.to_f>1e-8
      end
      projection_geometry(points,axes)
    end
  end
  def separated_projections?(a,b)
    (a[:axes]+b[:axes]).any? do |n|
      ap=a[:points].map { |p|p.x*n.x+p.y*n.y+p.z*n.z }
      bp=b[:points].map { |p|p.x*n.x+p.y*n.y+p.z*n.z }
      next false if ap.empty? || bp.empty?
      [ap.max,bp.max].min-[ap.min,bp.min].max<=1e-6
    end
  end

  def solid_bounds(row)
    box=Geom::BoundingBox.new
    8.times { |i|box.add(row[:group].definition.bounds.corner(i).transform(row[:world])) }
    box
  end
  def boxes_overlap?(a,b)
    [a.max.x.to_f-b.min.x.to_f,b.max.x.to_f-a.min.x.to_f,
     a.max.y.to_f-b.min.y.to_f,b.max.y.to_f-a.min.y.to_f,
     a.max.z.to_f-b.min.z.to_f,b.max.z.to_f-a.min.z.to_f].min>EPS
  end
  def solid_copy(entities,row,into=Geom::Transformation.new)
    copy=entities.add_group
    copy.entities.add_instance(row[:group].definition,into.inverse*row[:world]).explode
    copy.material=row[:group].material
    copy
  end
  remove_const(:USE_SEPARATE_CROWN_SHELLS) if const_defined?(:USE_SEPARATE_CROWN_SHELLS,false)
  USE_SEPARATE_CROWN_SHELLS=true
  # Subtraction can leave two closed shells touching along one edge. SketchUp
  # merges that edge into four incident faces, so the combined group is not a
  # solid. Move the existing faces into separate groups; never patch a hole or
  # discard a face to make a failed boolean appear valid.
  def closed_crown_parts(group)
    return [] unless group && group.valid?
    return [group] if group.manifold?
    return [] unless USE_SEPARATE_CROWN_SHELLS
    unseen=group.entities.grep(Sketchup::Face).to_h { |face|[face,true] }
    components=[]
    until unseen.empty?
      queue=[unseen.keys.first];faces=[]
      until queue.empty?
        face=queue.pop
        next unless unseen.delete(face)
        faces<<face
        face.edges.each { |edge|queue.concat(edge.faces) if edge.faces.length==2 }
      end
      components<<faces
    end
    return [] if components.length<2
    parts=components.map { |faces|group.entities.add_group(faces+faces.flat_map(&:edges).uniq) }
    parts.all?(&:manifold?) ? parts : []
  end
  def trim_overlaps!(changed_owners: nil)
    changed_owners=nil unless USE_INCREMENTAL_CROWN_TRIM
    model=Sketchup.active_model
    rows=crown_solids(model.entities).sort_by { |r|[r[:owner]=='house' ? 0 : 1,r[:owner],r[:group].persistent_id] }
    trimmed=0
    scratch=model.entities.add_group
    begin
      rows.each_with_index do |winner,i|
        next unless winner[:group].valid?
        rows.drop(i+1).each do |target|
          next unless target[:group].valid?
          next if winner[:owner]=='house' && target[:owner]=='house'
          next if changed_owners && !changed_owners.include?(winner[:owner]) && !changed_owners.include?(target[:owner])
          next unless boxes_overlap?(solid_bounds(winner),solid_bounds(target))
          next if separated_projections?(solid_projection(winner),solid_projection(target))
          a=b=intersection=cutter=nil
          begin
            a=solid_copy(scratch.entities,winner)
            b=solid_copy(scratch.entities,target)
            target_volume=b.volume.to_f
            intersection=a.intersect(b)
            next unless intersection && intersection.valid? && intersection.volume.to_f>0.0001
            original=target[:group]
            # A completely covered piece contributes no surface to the envelope.
            if (intersection.volume.to_f-target_volume).abs<0.0001
              original.erase!;trimmed+=1;next
            end
            name=original.name;mat=original.material;layer=original.layer;hidden=original.hidden?
            cutter=solid_copy(original.parent.entities,winner,target[:parent])
            replacement=cutter.subtract(original)
            parts=closed_crown_parts(replacement)
            raise 'Unable to trim intersecting crown solids' if parts.empty?
            replacement.name=name;replacement.material=mat;replacement.layer=layer;replacement.hidden=hidden
            parent=parts.first.equal?(replacement) ? target[:parent] : target[:parent]*replacement.transformation
            updated=parts.map do |part|
              part.name=name;part.material=mat;part.layer=layer;part.hidden=hidden
              InteriorPro::MoldingBuilder.soften_facets!(part.entities)
              {group:part,owner:target[:owner],parent:parent,world:parent*part.transformation}
            end
            # Every new shell must still be tested against subsequent cutters.
            # Array#each visits appended rows, preserving later overlap checks.
            target.replace(updated.shift)
            rows.concat(updated)
            changed_owners<<target[:owner] if changed_owners
            trimmed+=1
          ensure
            [a,b,intersection,cutter].compact.each { |g|g.erase! if g.valid? }
          end
        end
      end
    ensure
      scratch.erase! if scratch.valid?
    end
    trimmed
  end

  def restore_house!(retained=[])
    builder=InteriorPro::MoldingBuilder
    Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
      next if retained.include?(g)
      raw=g.get_attribute(KitchenLab::DICT,'house_join_source');next unless raw
      wall=walls.find { |w|w.get_attribute('InteriorPro','id')==g.get_attribute('InteriorPro','host_wall_id') };next unless wall
      side=g.get_attribute('InteriorPro','side').to_sym;edge=builder.wall_edges(wall)&.fetch(side,nil);next unless edge
      source=JSON.parse(raw);shifts=source['shifts'].transform_keys(&:to_sym);gaps=source['tee_gaps'].map { |x|x.transform_keys(&:to_sym) }
      rebuilt=builder.build_crown_on_edge!(wall,edge,g.get_attribute('InteriorPro','profile'),side,shifts,g.get_attribute('InteriorPro','profile_h'),gaps)
      if rebuilt && rebuilt.valid?;rebuilt.material=g.material;rebuilt.layer=g.layer;rebuilt.hidden=g.hidden?;end
      g.erase!
    end
  end
  def refresh_from_house!
    return unless KitchenLab::USE_KITCHEN_MOLDING_JOIN && !@refreshing && Sketchup.active_model.get_attribute(KitchenLab::DICT,'document')
    return unless KitchenLab.instance_variable_get(:@model).equal?(Sketchup.active_model)
    @refreshing=true
    KitchenLab.unpack_units!;KitchenLab.crowns!;KitchenLab.pack_units!
  ensure
    @refreshing=false
  end
end

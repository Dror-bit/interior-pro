# encoding: utf-8
require 'json'
require 'securerandom'
load File.join(File.dirname(__FILE__),'kitchen_document.rb')
load File.join(File.dirname(__FILE__),'kitchen_appearance.rb')
load File.join(File.dirname(__FILE__),'kitchen_handle_catalog.rb')
load File.join(File.dirname(__FILE__),'kitchen_sink.rb')
load File.join(File.dirname(__FILE__),'kitchen_appliance_catalog.rb')
load File.join(File.dirname(__FILE__),'kitchen_appliance_assets.rb')
load File.join(File.dirname(__FILE__),'kitchen_engine.rb')
load File.join(File.dirname(__FILE__),'kitchen_commands.rb')
load File.join(File.dirname(__FILE__),'kitchen_store.rb')
load File.join(File.dirname(__FILE__),'kitchen_spatial.rb')
load File.join(File.dirname(__FILE__),'kitchen_dimensions.rb')
load File.join(File.dirname(__FILE__),'kitchen_house_context.rb')
load File.join(File.dirname(__FILE__),'builtin_cabinets.rb')
load File.join(File.dirname(__FILE__),'kitchen_crown.rb')
load File.join(File.dirname(__FILE__),'kitchen_layout.rb')
load File.join(File.dirname(__FILE__),'overhead_appliances.rb')
load File.join(File.dirname(__FILE__),'corner_cabinets.rb')

# Development module deliberately separate from InteriorPro.
module KitchenLab
  ROOT = File.dirname(__FILE__) unless const_defined?(:ROOT)
  DICT = 'KitchenLab' unless const_defined?(:DICT)
  TARGET_PID = Process.pid unless const_defined?(:TARGET_PID)
  DEFAULTS = {'width'=>36.0,'height'=>34.5,'depth'=>24.0,'x'=>0.0,'z'=>0.0,
    'kind'=>'doors','style'=>'shaker','finish'=>'ivory','handle'=>'brass'} unless const_defined?(:DEFAULTS)
  FINISHES = {'ivory'=>'#E8E4DA','sage'=>'#87978B','charcoal'=>'#3D4549','oak'=>'#BA9365'} unless const_defined?(:FINISHES)

  def self.guard!
    raise 'Wrong SketchUp window.' unless Process.pid == TARGET_PID
    raise 'Model changed. Reopen the kitchen tool in its original model.' unless @model && Sketchup.active_model.equal?(@model)
    raise 'Close the current group before editing the kitchen.' unless @model.active_path.nil?
  end

  def self.validate(raw,options=settings)
    raise 'Invalid cabinet data' unless raw.is_a?(Hash)
    d=DEFAULTS.merge('appliance_finish'=>'stainless','toe_height'=>4.0,'toe_setback'=>3.0,'handle_position'=>'auto','handle_offset'=>1.0,'handle_side'=>2.0).merge(raw)
    d=Appearance.resolve(d,options) if d.key?('appearance_overrides')
    d['wall']=d.fetch('wall','A');raise 'Invalid wall' unless %w[A B I].include?(d['wall'])
    if d['house_placement']
      p=d['house_placement'];raise 'Invalid house placement' unless p.is_a?(Hash)
      p=p.slice('x','y','angle','handedness','wall_id','face','along')
      %w[x y angle].each { |k| p[k]=Float(p.fetch(k));raise 'Invalid house position' unless p[k].finite? && p[k].abs<=12000 }
      p['handedness']=Integer(p.fetch('handedness',1));raise 'Invalid house axes' unless [-1,1].include?(p['handedness'])
      if p['wall_id']
        raise 'Invalid host wall' unless p['wall_id'].is_a?(String) && p['wall_id'].length.between?(1,128)
        p['face']=Integer(p.fetch('face'));p['along']=Float(p.fetch('along'))
        raise 'Invalid wall attachment' unless p['face'].between?(0,3) && p['along'].finite? && p['along']>=0
      end
      d['house_placement']=p
    end
    %w[flip_x flip_y].each { |key| raise 'Invalid flip value' if d.key?(key) && ![true,false].include?(d[key]) }
    raise 'Corner cabinets follow their wall junction' if d['kind'].to_s.start_with?('corner') && (d['flip_x'] || d['flip_y'])
    raise 'Invalid rotation corner' if d.key?('rotation_pivot') && !%w[center back_left back_right front_left front_right].include?(d['rotation_pivot'])
    %w[rotation offset_y].each do |key|
      next unless d.key?(key)
      d[key]=Float(d[key]);limit=key=='rotation' ? 360 : 1200
      raise "Invalid #{key}" unless d[key].finite? && d[key].abs<=limit
    end
    raise 'Corner orientation follows its two runs' if d['kind'].to_s.start_with?('corner') && (d.fetch('rotation',0)!=0 || d.fetch('offset_y',0)!=0 || d['flip_x'] || d['flip_y'])
    surround=d.key?('surround_for') || d.key?('surround_part')
    if surround
      raise 'Invalid appliance surround' unless d['surround_for'].to_s.match?(/\A[a-zA-Z0-9-]{1,64}\z/) &&
        ((d['kind']=='filler' && %w[left right top bottom hood_front plinth].include?(d['surround_part'])) || (d['kind']=='wall' && %w[upper lower].include?(d['surround_part'])))
    end
    panel=surround && d['kind']=='filler'
    hood_front=panel && d['surround_part']=='hood_front'
    thin_panel=hood_front || (panel && d['surround_part']=='plinth')
    raise 'Choose a plain or Shaker hood cover.' if hood_front && !%w[slab shaker].include?(d['style'])
    {'width'=>[d['kind']=='filler' ? 0.5 : (d['kind']=='doors' && d['pullout'].is_a?(Hash) && d['pullout']['type']=='spice' ? 9 : 12),60],'height'=>[panel ? 0.5 : surround ? 8.25 : 12,96],'depth'=>[thin_panel ? 0.75 : 8,thin_panel ? 0.75 : 36],'x'=>[0,1200],'z'=>[0,120]}.each do |k,range|
      d[k]=Float(d[k]);raise "Invalid #{k}" unless d[k].finite? && d[k].between?(*range)
    end
    raise 'Invalid item type' unless %w[doors drawers sink wall tall fridge oven wall_oven dishwasher oven_tower micro_tower fridge_surround filler corner hood microwave corner_base corner_upper corner_lazy].include?(d['kind'])
    if open_corner?(d)
      raise 'Corner stays at the junction of walls A and B' unless d['wall']=='A' && d['x']==0
      raise 'Corner width must exceed cabinet depth by at least 9 inches' unless d['width']-d['depth']>=9
      d['front_layout']='single'
    end
    if %w[filler corner].include?(d['kind'])
      d['style']='slab' unless hood_front;d['handle']='none'
    end
    raise 'Closed corner stays at the junction of Wall A and Wall B' if d['kind']=='corner' && (d['wall']!='A'||d['x']!=0||d['z']!=0)
    raise 'Invalid appliance finish' unless %w[stainless black white].include?(d['appliance_finish'])
    raise 'Invalid front style' unless %w[shaker slab glass].include?(d['style'])
    raise 'Invalid finish' unless FINISHES.key?(d['finish'])
    raise 'Invalid handle' unless %w[brass black none].include?(d['handle'])
    raise 'Base cabinet must be at least 18 inches high' if !panel && !%w[wall hood microwave].include?(d['kind']) && d['height']<18
    raise 'Invalid cabinet ID' unless d['id'].to_s.match?(/\A[a-zA-Z0-9-]{1,64}\z/)
    if d.key?('pullout')
      d['pullout']=Pullouts.validate(d['pullout'],d)
      d['front_layout']='single' if d['pullout']
    end
    unless %w[fridge oven wall_oven dishwasher hood microwave].include?(d['kind'])
      d['toe_height']=(panel && !%w[left right].include?(d['surround_part'])) || %w[wall fridge_surround corner_upper].include?(d['kind']) ? 0.0 : Float(d['toe_height'])
      d['toe_setback']=Float(d['toe_setback'])
      d['toe_setback']=0 if thin_panel
      raise 'Toe kick height must be 0Ã¢â‚¬â€œ12 inches and leave at least 8 inches for fronts' unless d['toe_height'].finite? && d['toe_height'].between?(0,12) && (panel || d['height']-d['toe_height']>=8.25)
      raise 'Toe kick setback must fit inside the cabinet depth' unless d['toe_setback'].finite? && d['toe_setback'].between?(0,d['depth']-0.6)
      if builtin?(d)
        builtin_defaults(d).each { |key,value| d[key]=Float(d.fetch(key,value)) }
      end
      front_rows(d)
      raise 'Invalid handle position' unless %w[auto top center bottom].include?(d['handle_position'])
      %w[handle_offset handle_side].each { |key| d[key]=Float(d[key]);raise 'Invalid handle distance' unless d[key].finite? && d[key].between?(0.25,48) }
      if d['handle']!='none'
        front_rows(d).each_with_index do |row,i|
          next if row['kind']=='appliance' || (d['kind']=='sink' && row['kind']=='drawer')
          n=row['kind']=='drawer' ? 1 : row['doors']
          handle_layout(d.merge('_upper_front'=>builtin?(d) && i==0),(d['width']-0.125*(n+1))/n,row['height'],row['kind']=='drawer',true,options)
        end
      end
    end
    d['sink']=Sink.spec(d) if d.key?('sink')
    if d.key?('front_overlay')
      d['front_overlay']=Float(d['front_overlay'])
      raise 'Invalid drawer overlay' unless d['surround_for'] && d['surround_part']=='lower' && d['front_layout']=='drawers' && d['front_overlay']==0.75
    end
    %w[door_handle_model drawer_handle_model].each { |key|HandleCatalog.validate_id(d[key]) }
    ApplianceCatalog.validate(d)
    PanelReady.validate!(d,options)
    if d.key?('backsplash')
      d['backsplash']=Backsplash.validate(d['backsplash'])
      raise 'Backsplash requires a base cabinet' if d['backsplash']['mode']!='none' && !Backsplash.eligible?(d)
    end
    d.slice('pullout','backsplash','panel_options','door_handle_model','drawer_handle_model','front_overlay','installation_depth','id','wall',*DEFAULTS.keys,'flip_x','flip_y','rotation','offset_y','rotation_pivot','house_placement','appliance_finish','front_layout','drawer_heights','toe_height','toe_setback','handle_position','handle_offset','handle_side','appliance_width','appliance_height','appliance_bottom','microwave_height','appearance_overrides','sink','appliance','surround_for','surround_part')
  end

  # Row heights are visible front sizes, ordered from top to bottom.
  def self.front_rows(d)
    return Pullouts.front_rows(d) if d['pullout']
    return [{'kind'=>'doors','doors'=>1,'height'=>d['height']}] if d['surround_part']=='hood_front'
    return [{'kind'=>'doors','doors'=>1,'height'=>d['height']-d.fetch('toe_height',4)-0.25}] if open_corner?(d)
    return [{'kind'=>'doors','doors'=>2,'height'=>SinkCatalog.front_height(d)-d.fetch('toe_height',4)-0.25}] if SinkCatalog.apron?(d)
    return [] if %w[filler corner].include?(d['kind'])
    return builtin_rows(d) if builtin?(d)
    available=d['height']-(d['kind']=='wall' ? 0 : d.fetch('toe_height',4))-0.25
    layout=d['front_layout'] || (d['kind']=='drawers' ? 'drawers' : d['kind']=='sink' ? (d['width']<24 ? 'combo_single' : 'combo_double') : (d['width']<24 ? 'single' : 'double'))
    raise 'Invalid front layout' unless %w[single double drawers combo_single combo_double].include?(layout)
    return [{'kind'=>'doors','height'=>available,'doors'=>layout=='single' ? 1 : 2}] if %w[single double].include?(layout)
    heights=d['drawer_heights']
    heights=layout=='drawers' ? [0.24,0.36,0.40].map { |r| (available-0.25)*r } : [5.875] if heights.nil?
    raise 'Choose 1 to 6 drawers' unless heights.is_a?(Array) && heights.length.between?(1,6)
    raise 'Combined layout uses one top drawer' if layout!='drawers' && heights.length!=1
    heights=heights.map { |v| Float(v) }
    raise 'Each drawer front must be at least 3 inches high' unless heights.all? { |v| v.finite? && v>=3 }
    rows=heights.map { |v| {'kind'=>'drawer','height'=>v} }
    if layout=='drawers'
      raise 'Drawer heights must fill the available front height' unless (heights.sum+0.125*(heights.length-1)-available).abs<0.005
    else
      remaining=available-heights[0]-0.125
      raise 'Leave at least 8 inches for the doors' unless remaining>=8
      rows<<{'kind'=>'doors','height'=>remaining,'doors'=>layout=='combo_single' ? 1 : 2}
    end
    rows
  end

  def self.cabinets
    @model.entities.grep(Sketchup::Group).select { |g| g.valid? && g.get_attribute(DICT,'kind')=='cabinet' }
  end

  def self.state
    guard!
    Document.state(document)
  end

  def self.settings
    document['settings']
  end

  def self.check_shaker(d,s=settings)
    return if !%w[shaker glass].include?(d['style']) || %w[fridge oven wall_oven dishwasher hood microwave].include?(d['kind'])
    front_rows(d).each do |row|
      next if row['kind']=='appliance'
      count=row['kind']=='drawer' ? 1 : row['doors']
      width=open_corner?(d) ? d['width']-d['depth']-0.25 : (d['width']-0.125*(count+1))/count
      raise "Shaker frame too wide for #{d['kind']} at X=#{d['x']}. Reduce frame width or enlarge the front." if [width,row['height']].min<2*s['shaker_width']+0.25
    end
  end

  def self.validate_settings(raw,current=settings)
    raise 'Invalid kitchen settings' unless raw.is_a?(Hash)
    allowed=%w[backsplash island_countertop_material countertop_material global_door_handle_model global_drawer_handle_model shaker_width shaker_inset crown_match_house crown_profile crown_height crown_depth crown_color global_finish global_handle_type global_handle_color]
    raise 'Use placement commands for kitchen position' unless (raw.keys-allowed).empty?
    %w[global_door_handle_model global_drawer_handle_model].each { |key|HandleCatalog.validate_id(raw[key]) }
    CountertopMaterials.validate(raw['countertop_material']) if raw.key?('countertop_material')
    CountertopMaterials.validate(raw['island_countertop_material']) if raw.key?('island_countertop_material')
    raw=raw.merge('backsplash'=>Backsplash.validate(raw['backsplash'])) if raw.key?('backsplash')
    s=crown_settings(current.merge(raw))
    %w[shaker_width shaker_inset].each { |key| s[key]=Float(raw.fetch(key,current.fetch(key))) }
    raise 'Frame width must be 0.25Ã¢â‚¬â€œ6 inches' unless s['shaker_width'].finite? && s['shaker_width'].between?(0.25,6)
    raise 'Panel inset must be 0Ã¢â‚¬â€œ0.625 inches' unless s['shaker_inset'].finite? && s['shaker_inset'].between?(0,0.625)
    raise 'Invalid global cabinet color' unless ['',*FINISHES.keys].include?(s.fetch('global_finish',''))
    raise 'Invalid global handle type' unless ['','bar','none'].include?(s.fetch('global_handle_type',''))
    raise 'Invalid global handle color' unless ['','brass','black'].include?(s.fetch('global_handle_color',''))
    s
  end

  def self.update_settings(raw)
    execute_commands({'commands'=>[{'type'=>'update_settings','payload'=>raw}]})
  end

  def self.global_appearance(d,s=settings)
    Appearance.resolve(d,s)
  end
  def self.material(key,color)
    if key=='Worktop' && settings['countertop_material']
      return CountertopMaterials.resolve(@model,settings['countertop_material'])
    end
    m=@model.materials["KitchenLab / #{key}"] || @model.materials.add("KitchenLab / #{key}")
    m.color=color;m
  end

  def self.box(ents,name,x,y,z,w,d,h,mat)
    raise "Invalid geometry: #{name}" unless [w,d,h].all? { |v| v>0.001 }
    g=ents.add_group;g.name=name
    f=g.entities.add_face([x,y,z],[x+w,y,z],[x+w,y+d,z],[x,y+d,z])
    f.reverse! if f.normal.z<0;f.pushpull(h)
    g.material=mat
    g.entities.grep(Sketchup::Face).each { |face| face.material=mat;face.back_material=mat }
    g
  end

  def self.handle_layout(d,w,h,horizontal,left,options=settings)
    catalog_layout=HandleCatalog.layout(d,w,h,horizontal,left,options)
    return catalog_layout['rect'] if catalog_layout
    pos=d.fetch('handle_position','auto')
    auto=pos=='auto'
    pos=horizontal || d['kind']=='tall' ? 'center' : (d['kind']=='wall' || d['_upper_front'] ? 'bottom' : 'top') if auto
    rail=%w[shaker glass].include?(d['style']) ? options['shaker_width'] : 2.0
    offset=auto ? rail : d.fetch('handle_offset',rail)
    edge=auto ? rail/2 : d.fetch('handle_side',rail/2)
    length=horizontal ? [5.0,w-4].min : [5.0,h-2].min
    if horizontal
      hx=(w-length)/2;hz=pos=='top' ? h-offset-0.16 : pos=='bottom' ? offset-0.16 : (h-0.32)/2
      hw=length;hh=0.32
    else
      hx=(left ? w-edge : edge)-0.16;hz=pos=='top' ? h-offset-length+0.5 : pos=='bottom' ? offset-0.5 : (h-length)/2
      hw=0.32;hh=length
    end
    raise 'Handle falls outside the front. Reduce the edge distances.' if hx<0 || hz<0 || hx+hw>w || hz+hh>h
    [hx,hz,hw,hh]
  end

  def self.front(ents,name,x,z,w,h,d,finish,metal,horizontal=false)
    y=-d['depth'];t=0.75
    if %w[shaker glass].include?(d['style'])
      s=settings;r=s['shaker_width'];inset=s['shaker_inset']
      raise 'Shaker frame too wide for this front' if [w,h].min<2*r+0.25
      if d['style']=='glass' && !horizontal
        glazing=material('Clear glass','#AFDAE2');glazing.alpha=0.35
        box(ents,"#{name} / glass",x+r,y+0.25,z+r,w-2*r,0.125,h-2*r,glazing)
      else
        box(ents,"#{name} / panel",x+r,y+inset,z+r,w-2*r,t-inset,h-2*r,finish)
      end
      box(ents,"#{name} / left",x,y,z,r,t,h,finish)
      box(ents,"#{name} / right",x+w-r,y,z,r,t,h,finish)
      box(ents,"#{name} / top",x+r,y,z+h-r,w-2*r,t,r,finish)
      box(ents,"#{name} / bottom",x+r,y,z,w-2*r,t,r,finish)
    else
      box(ents,name,x,y,z,w,t,h,finish)
    end
    return if d['handle']=='none'
    return if HandleCatalog.build(ents,name,x,y,z,w,h,d,horizontal,name.include?('left'),settings)
    dx,dz,hw,hh=handle_layout(d,w,h,horizontal,name.include?('left'))
    hx=x+dx;hz=z+dz
    box(ents,"#{name} / pull",hx,y-1.2,hz,hw,0.32,hh,metal)
    if horizontal
      [hx+0.3,hx+hw-0.6].each { |px| box(ents,'Pull mount',px,y-0.9,hz+0.03,0.3,0.9,0.26,metal) }
    else
      [hz+0.35,hz+hh-0.65].each { |pz| box(ents,'Pull mount',hx+0.03,y-0.9,pz,0.26,0.9,0.3,metal) }
    end
  end

  def self.cabinet_side(ents,name,x,dep,h,toe,setback,finish)
    return box(ents,name,x,-dep+0.75,0,0.75,dep-0.75,h,finish) if toe<=0 || setback<=0.75
    g=ents.add_group;g.name=name
    face=g.entities.add_face([x,-dep+0.75,toe],[x,-dep+0.75,h],
      [x,0,h],[x,0,0],[x,-dep+setback,0],[x,-dep+setback,toe])
    face.reverse! if face.normal.x<0
    face.pushpull(0.75)
    g.material=finish
    g.entities.grep(Sketchup::Face).each { |f| f.material=finish;f.back_material=finish }
    g
  end

  def self.build(d)
    g=@model.entities.add_group;g.name="Kitchen / #{d['kind']} / #{d['width']} in"
    g.set_attribute(DICT,'kind','cabinet');g.set_attribute(DICT,'id',d['id']);g.set_attribute(DICT,'data',JSON.generate(d))
    g.set_attribute(DICT,'schema_version',1)
    if open_corner?(d)
      build_corner_cabinet(g.entities,d);g.transformation=cabinet_transform(d);return g
    end
    if %w[fridge oven wall_oven dishwasher hood microwave].include?(d['kind'])
      build_appliance(g.entities,d)
      g.transformation=cabinet_transform(d)
      return g
    end
    if %w[filler corner].include?(d['kind'])
      mat=material(d['finish'],FINISHES[d['finish']]);toe=d.fetch('toe_height',4)
      if d['surround_for']
        if d['surround_part']=='hood_front' || (%w[left right].include?(d['surround_part']) && document['cabinets'].any? { |c| c['id']==d['surround_for'] && c['kind']=='hood' })
          g.name='Kitchen / Hood cover'
          HoodMiters.build(g.entities,d,mat)
        elsif %w[left right].include?(d['surround_part']) && toe>0
          panel=g.entities.add_group;panel.name='Surround side'
          dep=d['depth'];h=d['height'];setback=d['toe_setback']
          face=panel.entities.add_face([0,-dep+0.75,toe],[0,-dep+0.75,h],[0,0,h],[0,0,0],[0,-dep+setback,0],[0,-dep+setback,toe])
          face.reverse! if face.normal.x<0
          face.pushpull(d['width']);panel.material=mat
          panel.entities.grep(Sketchup::Face).each { |f| f.material=mat;f.back_material=mat }
        else
          box(g.entities,'Surround panel',0,-d['depth'],0,d['width'],d['depth'],d['height'],mat)
        end
        g.transformation=cabinet_transform(d);return g
      end
      box(g.entities,'Closing panel',0,-d['depth'],toe,d['width'],0.75,d['height']-toe,mat)
      box(g.entities,'Plinth',0,-d['depth']+d.fetch('toe_setback',3),0,d['width'],0.6,toe,mat) if toe>0
      if d['kind']=='corner'
        box(g.entities,'Corner side',0,-d['depth']+0.75,0,0.75,d['depth']-0.75,d['height'],mat)
        box(g.entities,'Corner top',0,-d['depth'],d['height']-0.75,d['width'],d['depth'],0.75,mat)
      end
      g.transformation=cabinet_transform(d);return g
    end
    w=d['width'];h=d['height'];dep=d['depth'];toe=%w[wall fridge_surround].include?(d['kind']) ? 0.0 : d.fetch('toe_height',4.0)
    finish=material(d['finish'],FINISHES[d['finish']]);dark=material('Recess','#30332F')
    stone=material('Worktop','#F2F0E9');metal=material(d['handle'],d['handle']=='brass' ? '#B39456' : '#242729')
    e=g.entities
    # Exterior envelope only: no shelves, drawer boxes or manufacturing parts.
    setback=d.fetch('toe_setback',3.0)
    front_h=SinkCatalog.front_height(d)
    cabinet_side(e,'Left side',0,dep,front_h,toe,setback,finish)
    cabinet_side(e,'Right side',w-0.75,dep,front_h,toe,setback,finish)
    if SinkCatalog.apron?(d)
      back_depth=dep-3
      box(e,'Left rear support',0,-back_depth,front_h,0.75,back_depth,h-front_h,finish)
      box(e,'Right rear support',w-0.75,-back_depth,front_h,0.75,back_depth,h-front_h,finish)
    end
    box(e,'Back',0.75,-0.5,0,w-1.5,0.5,h,finish)
    box(e,'Bottom panel',0.75,-dep+0.75,toe,w-1.5,dep-1.25,0.75,finish)
    box(e,'Shadow behind fronts',0.75,-dep+0.78,toe,w-1.5,0.15,front_h-toe,dark) unless d['style']=='glass' || d['pullout']
    box(e,'Toe kick',0,-dep+d.fetch('toe_setback',3.0),0,w,0.6,toe,finish) if toe>0
    if d['pullout']
      Pullouts.build!(e,d,finish,metal);g.transformation=cabinet_transform(d);return g
    end
    gap=0.125;cursor=front_h-gap
    front_rows(d).each_with_index do |row,i|
      fd=d.merge('_upper_front'=>builtin?(d) && i==0)
      fh=row['height'];cursor-=fh
      if row['kind']=='appliance'
        builtin_front(e,row,cursor,d,finish)
      elsif row['kind']=='drawer'
        name=d['kind']=='sink' ? 'False drawer' : "Drawer #{i+1}"
        front(e,name,gap-d.fetch('front_overlay',0),cursor,w-2*gap+2*d.fetch('front_overlay',0),fh,d['kind']=='sink' ? fd.merge('handle'=>'none') : fd,finish,metal,true)
      elsif row['doors']==1
        front(e,'Door left',gap,cursor,w-2*gap,fh,fd,finish,metal)
      else
        dw=(w-3*gap)/2
        front(e,'Door left',gap,cursor,dw,fh,fd,finish,metal)
        front(e,'Door right',2*gap+dw,cursor,dw,fh,fd,finish,metal)
      end
      cursor-=gap
    end
    box(e,'Top panel',0,-dep+0.75,h-0.75,w,dep-0.75,0.75,finish) if %w[wall tall oven_tower micro_tower fridge_surround].include?(d['kind'])
    build_sink(e,d)
    build_catalog_appliance(e,d) if ApplianceCatalog.cooktop?(d)
    g.transformation=cabinet_transform(d)
    g
  end

  def self.build_appliance(e,d)
    return build_catalog_appliance(e,d) if d['appliance']
    return build_overhead(e,d) if %w[hood microwave].include?(d['kind'])
    w=d['width'];h=d['height'];dep=d['depth'];y=-dep
    color={'stainless'=>'#B8C0C4','black'=>'#303538','white'=>'#ECEDE9'}[d['appliance_finish'] || 'stainless']
    shell=material("Appliance #{d['appliance_finish'] || 'stainless'}",color)
    glass=material('Appliance glass','#18262D');trim=material('Appliance handle','#DCE1E2')
    box(e,'Appliance body',0,y+0.8,0,w,dep-0.8,h,shell)
    box(e,'Recessed plinth',0,y+0.6,0,w,0.2,2,glass)
    if d['kind']=='fridge'
      split=h*0.30;gap=0.125
      box(e,'Freezer drawer',gap,y,2,w-2*gap,0.75,split-2-gap,shell)
      dw=(w-3*gap)/2
      [gap,2*gap+dw].each { |x| box(e,'Refrigerator door',x,y,split+gap,dw,0.75,h-split-2*gap,shell) }
      [w/2-1.4,w/2+1.1].each { |x| box(e,'Refrigerator pull',x,y-0.8,split+3,0.3,0.35,[12,h*0.22].min,trim) }
      box(e,'Freezer pull',w*0.2,y-0.8,split-2,w*0.6,0.35,0.3,trim)
    elsif %w[oven wall_oven].include?(d['kind'])
      box(e,'Oven door',0.125,y,2,w-0.25,0.75,h-6,glass)
      box(e,'Oven window',w*0.13,y-0.03,h*0.23,w*0.74,0.04,h*0.43,material('Oven window','#344850'))
      box(e,'Oven controls',0,y,h-4,w,0.75,3.8,shell)
      box(e,'Oven pull',w*0.12,y-0.8,h-6,w*0.76,0.35,0.35,trim)
      4.times { |i| box(e,'Control',w*(0.2+i*0.2)-0.4,y-0.25,h-2.5,0.8,0.3,0.8,glass) }
      box(e,'Cooktop',0,y+0.8,h-0.15,w,dep-0.8,0.15,glass)
      [w*0.27,w*0.73].product([-dep*0.28,-dep*0.72]).each do |cx,cy|
        radius=[w*0.13,dep*0.13].min
        face=e.add_face(e.add_circle([cx,cy,h+0.01],[0,0,1],radius,24))
        face.material=trim;face.back_material=trim
      end
    else
      box(e,'Dishwasher door',0.125,y,2,w-0.25,0.75,h-2.125,shell)
      box(e,'Dishwasher controls',0.25,y-0.03,h-3,w-0.5,0.04,2.5,glass)
      box(e,'Dishwasher pull',w*0.18,y-0.8,h-4.5,w*0.64,0.35,0.35,trim)
      box(e,'Display',w*0.65,y-0.08,h-2.25,w*0.18,0.04,0.6,trim)
    end
  end

  def self.build_catalog_appliance(e,d)
    return if ApplianceAssets.build(e,d)
    ApplianceCatalog.parts(d).each do |p|
      mat=material("Catalog #{p['color']}",p['color'])
      if p['shape']=='cylinder'
        g=e.add_group;g.name=p['name']
        face=g.entities.add_face(g.entities.add_circle([p['x']+p['width']/2,p['y']+p['depth']/2,p['z']],[0,0,1],p['width']/2,24))
        face.reverse! if face.normal.z<0;face.pushpull(p['height']);g.material=mat
        g.entities.grep(Sketchup::Face).each { |f| f.material=mat;f.back_material=mat }
      else
        box(e,p['name'],p['x'],p['y'],p['z'],p['width'],p['depth'],p['height'],mat)
      end
    end
  end

  def self.worktops!
    unpack_units!
    @model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'kind')=='worktop' }.each(&:erase!)
    bases=state['cabinets'].reject { |d| d['surround_for']||open_corner?(d)||%w[wall tall fridge oven wall_oven oven_tower micro_tower fridge_surround hood microwave].include?(d['kind']) }.sort_by { |d| [wall_of(d),d['x']] }
    runs=[]
    separate,bases=bases,[]
    separate.each do |d|
      holes=[]
      if Sink.active?(d)
        hole=Sink.cutout(d);holes<<hole if hole
      end
      holes<<ApplianceCatalog.cooktop_bounds(d,true) if ApplianceCatalog.cooktop?(d)
      mat=CountertopMaterials.for_cabinet(d)
      g=holes.empty? ? box(@model.entities,'Kitchen / Worktop',0,-d['depth']-1,d['height'],d['width'],d['depth']+1,1.5,mat) : slab_with_holes(@model.entities,'Kitchen / Worktop',[0,-d['depth']-1,d['width'],0],d['height'],1.5,holes,mat)
      g.transformation=cabinet_transform(d);g.set_attribute(DICT,'kind','worktop');g.set_attribute(DICT,'owner_id',d['id']);Backsplash.build!(g,d)
    end
    bases.each do |d|
      r=runs.last
      if r && r[:wall]==wall_of(d) && (r[:end]-d['x']).abs<0.001 && (r[:z]-d['z']-d['height']).abs<0.001 && (r[:depth]-d['depth']).abs<0.001 && r[:corner]==(d['kind']=='corner')
        r[:end]=d['x']+d['width']
      else
        runs<<{start:d['x'],end:d['x']+d['width'],z:d['z']+d['height'],depth:d['depth'],wall:wall_of(d),corner:d['kind']=='corner'}
      end
    end
    runs.each do |r|
      d={'wall'=>r[:wall]}
      overhang=r[:corner] ? 0 : 1
      holes=bases.select { |d| Sink.active?(d) && wall_of(d)==r[:wall] && d['x']>=r[:start] && d['x']+d['width']<=r[:end] && (d['z']+d['height']-r[:z]).abs<0.001 }.map do |d|
        hole=Sink.cutout(d);next unless hole
        x,y,right,back=hole;[d['x']+x,y,d['x']+right,back]
      end
      holes.compact!
      holes+=bases.select { |d| ApplianceCatalog.cooktop?(d) && wall_of(d)==r[:wall] && d['x']>=r[:start] && d['x']+d['width']<=r[:end] && (d['z']+d['height']-r[:z]).abs<0.001 }.map do |d|
        x,y,right,back=ApplianceCatalog.cooktop_bounds(d,true);[d['x']+x,y,d['x']+right,back]
      end
      mat=CountertopMaterials.for_cabinet(d)
      g=holes.empty? ? box(@model.entities,'Kitchen / Worktop',r[:start],-r[:depth]-overhang,r[:z],r[:end]-r[:start],r[:depth]+overhang,1.5,mat) : slab_with_holes(@model.entities,'Kitchen / Worktop',[r[:start],-r[:depth]-overhang,r[:end],0],r[:z],1.5,holes,mat)
      g.transformation=wall_transform(r[:wall])
      g.set_attribute(DICT,'kind','worktop')
    end
    state['cabinets'].select { |d| %w[corner_base corner_lazy].include?(d['kind']) }.each do |d|
      top=d['height']
      g=corner_panel(@model.entities,'Kitchen / Corner worktop',d['width'],d['depth']+1,top,1.5,CountertopMaterials.for_cabinet(d));g.transformation=cabinet_transform(d);g.set_attribute(DICT,'kind','worktop');g.set_attribute(DICT,'owner_id',d['id']);Backsplash.build!(g,d)
    end
    # A base microwave bundle carries a worktop across its two side panels.
    state['cabinets'].select { |d| ApplianceCatalog.microwave_base?(d) }.each do |d|
      sides=state['cabinets'].select { |p| p['surround_for']==d['id'] && %w[left right].include?(p['surround_part']) }
      next unless sides.length==2
      left=sides.find { |p| p['surround_part']=='left' };right=sides.find { |p| p['surround_part']=='right' }
      lp=Spatial.cabinet_point(left,0,0,settings);rp=Spatial.cabinet_point(right,right['width'],0,settings)
      width=Math.sqrt((rp[0]-lp[0])**2+(rp[1]-lp[1])**2)
      slab=box(@model.entities,'Kitchen / Worktop',0,-left['depth']-1,left['height'],width,left['depth']+1,1.5,CountertopMaterials.for_cabinet(d))
      slab.transformation=cabinet_transform(left);slab.set_attribute(DICT,'kind','worktop');slab.set_attribute(DICT,'owner_id',d['id']);Backsplash.build!(slab,left.merge('width'=>width),d)
    end
    ContinuousSurfaces.build!
    crowns!
    pack_units!
  end

  def self.apply(raw,notify=true)
    guard!;d=validate(raw)
    check_shaker(d)
    state['cabinets'].each do |o|
      next if o['id']==d['id']
      overlap_x=[d['x']+d['width'],o['x']+o['width']].min-[d['x'],o['x']].max
      overlap_z=[d['z']+d['height'],o['z']+o['height']].min-[d['z'],o['z']].max
      raise 'Cabinets overlap. Adjust the position or width.' if overlap?(d,o)
    end
    @model.start_operation('Kitchen: edit cabinet',true)
    begin
      write_document!(state['cabinets'].reject { |c| c['id']==d['id'] }+[d])
      cabinets.select { |g| g.get_attribute(DICT,'id')==d['id'] }.each(&:erase!)
      build(d);worktops!;@model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    publish if notify
    d
  end

  def self.place(raw)
    guard!
    changes=raw.fetch('positions')
    raise 'Invalid placement' unless changes.is_a?(Array) && changes.length>0
    before=state['cabinets'];by_id=before.to_h { |d| [d['id'],d] }
    raise 'Duplicate placement IDs' unless changes.map { |p| p['id'] }.uniq.length==changes.length
    updates=changes.map do |p|
      old=by_id.fetch(p['id']) { raise 'Cabinet no longer exists' }
      d=old.merge('x'=>Float(p.fetch('x')),'z'=>Float(p.fetch('z')))
      raise 'Corner stays at the wall junction' if any_corner?(old) && (d['x']!=old['x']||d['z']!=old['z'])
      raise 'Invalid placement coordinates' unless d['x'].finite? && d['z'].finite? && d['x'].between?(0,1200) && d['z'].between?(0,120)
      d
    end
    proposed=by_id.merge(updates.to_h { |d| [d['id'],d] }).values
    proposed.combination(2).each do |a,b|
      dx=[a['x']+a['width'],b['x']+b['width']].min-[a['x'],b['x']].max
      dz=[a['z']+a['height'],b['z']+b['height']].min-[a['z'],b['z']].max
      raise 'Cabinets overlap' if overlap?(a,b)
    end
    @model.start_operation('Kitchen: place cabinets',true)
    begin
      write_document!(proposed)
      updates.each do |d|
        old=by_id[d['id']];g=cabinets.find { |c| c.get_attribute(DICT,'id')==d['id'] }
        g ||= build(d)
        g.transformation=cabinet_transform(d)
        g.set_attribute(DICT,'data',JSON.generate(d))
      end
      worktops!;@model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    publish
  end

  def self.move(raw)
    guard!
    old=state['cabinets'].find { |c| c['id']==raw['id'] }
    raise 'Cabinet no longer exists' unless old
    data=validate(old.merge('x'=>raw['x'],'z'=>raw.fetch('z',old['z'])))
    state['cabinets'].each do |other|
      next if other['id']==data['id']
      dx=[data['x']+data['width'],other['x']+other['width']].min-[data['x'],other['x']].max
      dz=[data['z']+data['height'],other['z']+other['height']].min-[data['z'],other['z']].max
      raise 'Cabinets overlap.' if overlap?(data,other)
    end
    group=cabinets.find { |g| g.get_attribute(DICT,'id')==data['id'] }
    @model.start_operation('Kitchen: move cabinet',true)
    begin
      write_document!(state['cabinets'].map { |c| c['id']==data['id'] ? data : c })
      group ||= build(data)
      group.transformation=cabinet_transform(data)
      group.set_attribute(DICT,'data',JSON.generate(data))
      worktops!
      @model.commit_operation
    rescue StandardError
      @model.abort_operation
      raise
    end
    publish
  end

  def self.publish(error=nil,dialog=@dialog,command_results=nil)
    payload=state.merge('error'=>error,'house_context'=>house_context,'command_results'=>command_results,'appliance_catalog'=>ApplianceCatalog.products)
    payload['molding_catalog']=MoldingProfiles.catalog
    payload['house_molding']=MoldingProfiles.house_selection
    payload['cabinets']=payload['cabinets'].map { |d| d['appliance'] ? d.merge('appliance_parts'=>ApplianceCatalog.parts(d)) : d }
    if dialog && dialog.equal?(@dialog) && dialog.visible?
      dialog.execute_script("window.receiveKitchen(#{JSON.generate(payload)})")
    end
  end

  def self.view(mode)
    guard!
    groups=@model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'kind') }
    return if groups.empty?
    b=Geom::BoundingBox.new;groups.each { |g| b.add(g.bounds) };center=b.center
    eye=case mode
    when 'front' then center+Geom::Vector3d.new(0,-200,0)
    when 'top' then center+Geom::Vector3d.new(0,0,200)
    else center+Geom::Vector3d.new(150,-220,145)
    end
    up=mode=='top' ? [0,1,0] : [0,0,1]
    @model.active_view.camera=Sketchup::Camera.new(eye,center,up,false)
    @model.active_view.zoom(groups)
    @model.active_view.invalidate
  end

  def self.install_toolbar(restore: false)
    unless @toolbar
      @open_command=UI::Command.new('Kitchens') do
        begin
          InteriorPro::KitchenPlan.bind_active_model!
          show
        rescue StandardError=>e
          UI.messagebox(e.message)
        end
      end
      @open_command.tooltip='Kitchens'
      @open_command.status_bar_text='Open the kitchen planner'
      @open_command.small_icon=File.join(ROOT,'kitchen_icon.svg')
      @open_command.large_icon=File.join(ROOT,'kitchen_icon.svg')
      @toolbar=UI::Toolbar.new('Kitchens')
      @toolbar.add_item(@open_command)
    end
    restore ? @toolbar.restore : @toolbar.show
  end

  def self.show
    raise 'Wrong SketchUp process' unless Process.pid==TARGET_PID
    @model ||= Sketchup.active_model;guard!
    ensure_document!;observe_document!
    install_toolbar
    if @dialog && @dialog.visible?
      @dialog.bring_to_front;return
    end
    @dialog=UI::HtmlDialog.new(dialog_title:'Kitchens',preferences_key:'KitchenLab.Prototype',
      width:1120,height:760,min_width:900,min_height:650,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
    opened_dialog=@dialog
    @dialog.add_action_callback('backsplash_materials') { |_,id,json| begin;CountertopMaterials.show(id,JSON.parse(json));rescue StandardError=>e;publish(e.message);end }
    @dialog.add_action_callback('countertop_materials') { |_,scope| begin;CountertopMaterials.show(nil,nil,scope=='island' ? 'island' : 'kitchen');rescue StandardError=>e;publish(e.message);end }
    @dialog.add_action_callback('ready') { publish(nil,opened_dialog) }
    @dialog.add_action_callback('command') do |_,json|
      begin;execute_commands(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('apply') do |_,json|
      begin;apply(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('corner') do |_,kind|
      begin;add_corner(kind.to_s.empty? ? 'corner_base' : kind);rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('island') do |_,json|
      begin;move_island(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('pose') do |_,json|
      begin;move_kitchen(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('settings') do |_,json|
      begin;update_settings(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('move') do |_,json|
      begin;move(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('place') do |_,json|
      begin;place(JSON.parse(json));rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('remove') do |_,id|
      begin;remove(id);rescue StandardError=>e;publish(e.message);end
    end
    @dialog.add_action_callback('view') { |_,mode| begin;view(mode);rescue StandardError=>e;publish(e.message);end }
    @dialog.add_action_callback('refresh') { publish }
    @dialog.add_action_callback('undo') do |_|
      begin
        guard!
        Sketchup.send_action('editUndo:')
        UI.start_timer(0.2,false) { publish if @model.equal?(Sketchup.active_model) }
      rescue StandardError=>e
        publish(e.message)
      end
    end
    @dialog.add_action_callback('fit_height') { |_,h| @dialog.set_size(1120,[[h.to_i+46,700].max,900].min) }
    opened_dialog=@dialog
    @dialog.set_on_closed { @dialog=nil if @dialog.equal?(opened_dialog) }
    @dialog.set_file(File.join(ROOT,'kitchen.html'));@dialog.show
  end
end


load File.join(__dir__,'kitchen_accessories.rb')

load File.join(__dir__,'kitchen_continuous_surfaces.rb')
load File.join(__dir__,'kitchen_units.rb')

load File.join(__dir__,'countertop_materials.rb')

load File.join(__dir__,'kitchen_backsplash.rb')

load File.join(__dir__,'kitchen_pullouts.rb')

load File.join(__dir__,'kitchen_hood_miters.rb')

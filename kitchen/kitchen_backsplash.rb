require 'digest'
module KitchenLab
  module Backsplash
    BASE_KINDS=%w[doors drawers sink dishwasher filler corner corner_base corner_lazy].freeze unless const_defined?(:BASE_KINDS,false)
    def self.eligible?(d)
      d['wall']!='I' && !d['surround_for'] && ((BASE_KINDS+['oven']).include?(d['kind']) || (defined?(ApplianceCatalog) && ApplianceCatalog.microwave_base?(d)))
    end
    def self.product_dimensions(card)
      return nil unless card.is_a?(Hash)
      width=Float(card['tile_w_inches']) rescue nil
      height=Float(card['tile_l_inches']) rescue nil
      return nil unless [width,height].all?{|n|n && n.finite? && n.between?(1,120)}
      {'tile_width'=>width,'tile_height'=>height}
    end
    def self.with_material(raw,value)
      raw.merge('mode'=>'tile','material'=>value).merge(product_dimensions(value['card']) || {})
    end
    def self.validate(raw)
      return {'mode'=>'none'} if raw.nil?
      raise 'Invalid backsplash options' unless raw.is_a?(Hash)
      mode=raw.fetch('mode','none');raise 'Choose no backsplash, countertop or tile' unless %w[none countertop tile].include?(mode)
      return {'mode'=>'none'} if mode=='none'
      out={'mode'=>mode}
      {'height'=>[18,1,60],'thickness'=>[mode=='tile' ? 0.375 : 0.75,0.125,2],
       'tile_width'=>[6,1,120],'tile_height'=>[3,1,120],'grout'=>[0.125,0,0.5]}.each do |key,(default,min,max)|
        n=Float(raw.fetch(key,default));raise "Invalid backsplash #{key}" unless n.finite? && n.between?(min,max);out[key]=n
      end
      out['material']=CountertopMaterials.validate(raw['material']) if raw['material']
      out
    end
    # Rectangle subtraction retains the area around doors/windows and cabinets.
    def self.subtract(rect, hole)
      x,z,r,t=rect;a,b,c,d=hole
      a=[x,a].max;b=[z,b].max;c=[r,c].min;d=[t,d].min
      return [rect] if c<=a || d<=b
      [[x,z,a,t],[c,z,r,t],[a,z,c,b],[a,d,c,t]].select{|p|p[2]-p[0]>0.001 && p[3]-p[1]>0.001}
    end
    def self.rectangles(width,bottom,config,holes=[])
      rects=[[0.0,bottom,width,bottom+config['height']]]
      holes.each{|hole|rects=rects.flat_map{|r|subtract(r,hole)}}
      return rects if config['mode']=='countertop'
      tw=config['tile_width'];th=config['tile_height'];gap=config['grout']
      raise 'Tile layout is too dense; increase tile size' if (width/(tw+gap)).ceil*(config['height']/(th+gap)).ceil>3000
      tiles=[];z=bottom-config.fetch('_phase_z',0.0)
      while z<bottom+config['height']-0.001
        x=-config.fetch('_phase_x',0.0)
        while x<width-0.001
          tile=[x,z,[x+tw,width].min,[z+th,bottom+config['height']].min]
          rects.each do |r|
            clipped=[[r[0],tile[0]].max,[r[1],tile[1]].max,[r[2],tile[2]].min,[r[3],tile[3]].min]
            tiles<<clipped if clipped[2]-clipped[0]>0.001 && clipped[3]-clipped[1]>0.001
          end
          x+=tw+gap
        end
        z+=th+gap
      end
      tiles
    end
    # Like TileWall: each logical tile samples one tile from the product photo.
    # Inspect only the declared grid boundaries; do not mistake arbitrary veins for grout.
    def self.photo_region(card)
      @photo_regions ||= {}
      cache=Digest::SHA256.hexdigest(JSON.generate(card))
      return @photo_regions[cache] if @photo_regions.key?(cache)
      nx=[[card.fetch('image_tiles_x',1).to_i,1].max,16].min
      ny=[[card.fetch('image_tiles_y',1).to_i,1].max,16].min
      rotated=false
      if nx!=ny && nx*ny>1 && File.file?(card['texture_file'].to_s)
        rep=Sketchup::ImageRep.new;rep.load_file(card['texture_file'])
        bytes=rep.data;channels=rep.bits_per_pixel/8;stride=rep.width*channels+rep.row_padding
        intensity=lambda do |x,y|
          offset=y*stride+x*channels
          3.times.sum{|i|bytes.getbyte(offset+i)} / 3.0
        end
        score=lambda do |count,vertical|
          next 0.0 if count<2
          extent=vertical ? rep.width : rep.height
          cross=vertical ? rep.height : rep.width
          (1...count).map do |k|
            center=extent*k/count;radius=[(extent.to_f/count*0.015).ceil,2].max
            ((center-radius)..(center+radius)).map do |at|
              next 0.0 if at-radius<0 || at+radius>=extent
              contrasts=48.times.map do |i|
                across=((i+0.5)*cross/48).to_i
                sample=lambda{|q|vertical ? intensity.call(q,across) : intensity.call(across,q)}
                (sample.call(at)-(sample.call(at-radius)+sample.call(at+radius))/2).abs
              end
              contrasts.count{|v|v>5}>=40 ? contrasts.sum/48 : 0.0
            end.max
          end.min || 0.0
        end
        normal=score.call(nx,true)+score.call(ny,false)
        swapped=score.call(ny,true)+score.call(nx,false)
        if swapped>8 && swapped>normal*2
          nx,ny=ny,nx;rotated=true
        end
      end
      # Exclude the photographed joint and antialiasing at the cell boundary.
      inset=nx*ny>1 ? 0.015 : 0.0
      @photo_regions[cache]=[nx,ny,rotated,inset]
    end
    def self.map_tile_photo!(group,config)
      return unless config['material'] && group.material && group.material.texture
      cell=JSON.parse(group.get_attribute(KitchenLab::DICT,'tile_cell'))
      ux,uy,vx,vy,plane,col,row=cell
      tw=config['tile_width'];th=config['tile_height'];gap=config['grout']
      nx,ny,rotated,inset=photo_region(config['material']['card'])
      group.entities.grep(Sketchup::Face).each do |face|
        normal=face.normal.transform(group.transformation)
        next unless (normal.x*vx+normal.y*vy).abs>0.99
        mapping=face.vertices.first(3).flat_map do |vertex|
          pt=vertex.position;world=pt.transform(group.transformation)
          a=(world.x*ux+world.y*uy-col*(tw+gap))/tw
          b=(world.z-36.0-row*(th+gap))/th
          a,b=b,1-a if rotated
          [pt,Geom::Point3d.new((inset+a*(1-2*inset))/nx,(inset+b*(1-2*inset))/ny,0)]
        end
        face.position_material(group.material,mapping,true)
        face.position_material(group.material,mapping,false)
      end
    end
    remove_const(:USE_LOCAL_OPENING_SIGNATURE) if const_defined?(:USE_LOCAL_OPENING_SIGNATURE,false)
    USE_LOCAL_OPENING_SIGNATURE=true
    LOCAL_SIGNATURE_VERSION='kitchen-local-v1:' unless const_defined?(:LOCAL_SIGNATURE_VERSION,false)
    # World-space influence volumes, one per cabinet (inches). Include returns,
    # crown projection and the full configured backsplash height, on this floor.
    def self.opening_regions(model)
      raw=model.get_attribute(KitchenLab::DICT,'document')
      return [] unless raw
      doc=JSON.parse(raw);s=doc.fetch('settings');floor=Spatial.pose(s)['z']
      doc.fetch('cabinets').map do |d|
        points=Spatial.polygon(d,s);z=floor+d['z']
        extra=[12.0,s.fetch('backsplash',{}).to_h.fetch('height',18).to_f+2].max
        [points.map(&:first).min-12,points.map(&:last).min-12,z-12,
         points.map(&:first).max+12,points.map(&:last).max+12,z+d['height']+extra]
      end
    rescue StandardError
      nil # Unknown placement must conservatively retain the legacy dependency set.
    end
    def self.near_opening_regions?(min,max,regions)
      regions.nil? || regions.any?{|r|3.times.all?{|i|max[i]>=r[i] && min[i]<=r[i+3]}}
    end
    def self.relevant_wall_openings(wall,regions)
      return wall.get_attribute('InteriorPro','door_openings') unless defined?(InteriorPro::WallTool)
      tool=InteriorPro::WallTool
      sx,sy,ex,ey=%w[start_x start_y end_x end_y].map{|k|wall.get_attribute('InteriorPro',k).to_f}
      va,ha=wall.get_attribute('InteriorPro','anchor','bottom-center').split('-')
      offsets=tool.anchor_side_offsets(wall.get_attribute('InteriorPro','thickness').to_f,ha)
      floor=tool.native_floor_z(va,wall.get_attribute('InteriorPro','height').to_f)
      tool.read_door_openings(wall).select do |o|
        pocket=tool.opening_pocket(sx,sy,ex,ey,wall.get_attribute('InteriorPro','arc_sag').to_f,o[:t],o[:width])
        next true unless pocket
        ux,uy=pocket[:dir];z=floor+o.fetch(:floor_offset,0)
        points=[pocket[:p0],pocket[:p1]].product(offsets,[z,z+o[:height]+o.fetch(:arch_rise,0).to_f]).map do |p,y,h|
          Geom::Point3d.new(p[0]-uy*y,p[1]+ux*y,h).transform(wall.transformation).to_a
        end
        near_opening_regions?(3.times.map{|i|points.map{|p|p[i]}.min},3.times.map{|i|points.map{|p|p[i]}.max},regions)
      end
    rescue StandardError
      wall.get_attribute('InteriorPro','door_openings')
    end
    def self.opening_signature(model,local:USE_LOCAL_OPENING_SIGNATURE)
      regions=local ? opening_regions(model) : nil
      rows=model.entities.select{|e|e.respond_to?(:transformation) && %w[wall window door].include?(e.get_attribute('InteriorPro','type')) && near_opening_regions?(e.bounds.min.to_a,e.bounds.max.to_a,regions)}.map do |e|
        attrs=e.attribute_dictionary('InteriorPro')
        keys=%w[type id host_wall_id start_x start_y end_x end_y height thickness anchor arc_sag door_openings width_in height_in sill_height_in header_height_in position_along_wall_in]
        values=keys.map{|k|attrs && attrs[k]}
        values[keys.index('door_openings')]=relevant_wall_openings(e,regions) if local && e.get_attribute('InteriorPro','type')=='wall'
        [e.persistent_id,values,e.transformation.to_a,e.bounds.min.to_a,e.bounds.max.to_a]
      end.sort_by(&:first)
      (local ? LOCAL_SIGNATURE_VERSION : '')+Digest::SHA256.hexdigest(JSON.generate(rows))
    end
    # Seed old documents without writing model attributes or creating an Undo
    # entry. Otherwise the first unrelated edit after upgrading would rebuild.
    def self.prime_opening_signature!(model)
      return unless USE_LOCAL_OPENING_SIGNATURE
      saved=model.get_attribute(KitchenLab::DICT,'backsplash_opening_signature')
      return unless saved && !saved.start_with?(LOCAL_SIGNATURE_VERSION) && saved==opening_signature(model,local:false)
      @opening_baselines ||= {}
      @opening_baselines[model]=[saved,opening_signature(model)]
    end
    def self.openings_changed?(model)
      saved=model.get_attribute(KitchenLab::DICT,'backsplash_opening_signature')
      if USE_LOCAL_OPENING_SIGNATURE && saved && !saved.start_with?(LOCAL_SIGNATURE_VERSION)
        prime_opening_signature!(model) unless @opening_baselines && @opening_baselines[model]&.first==saved
        baseline=@opening_baselines && @opening_baselines[model]
        return baseline.last!=opening_signature(model) if baseline && baseline.first==saved
      end
      saved!=opening_signature(model)
    end
    prime_opening_signature!(Sketchup.active_model) if defined?(Sketchup) && Sketchup.respond_to?(:active_model)
    # Opening data is authoritative even when the rendered window is recessed.
    def self.opening_holes(model,inv,thick)
      walls=model.entities.select{|e|e.respond_to?(:transformation) && e.get_attribute('InteriorPro','type')=='wall'}
      walls.flat_map do |wall|
        sx=wall.get_attribute('InteriorPro','start_x').to_f;sy=wall.get_attribute('InteriorPro','start_y').to_f
        ex=wall.get_attribute('InteriorPro','end_x').to_f;ey=wall.get_attribute('InteriorPro','end_y').to_f
        len=Math.hypot(ex-sx,ey-sy);next [] if len<0.001
        ux=(ex-sx)/len;uy=(ey-sy)/len
        va,ha=wall.get_attribute('InteriorPro','anchor','bottom-center').split('-')
        offsets=InteriorPro::WallTool.anchor_side_offsets(wall.get_attribute('InteriorPro','thickness').to_f,ha)
        floor=InteriorPro::WallTool.native_floor_z(va,wall.get_attribute('InteriorPro','height').to_f)
        tr=inv*wall.transformation
        InteriorPro::WallTool.read_door_openings(wall).filter_map do |o|
          x1=o[:t]-o[:width]/2.0;x2=o[:t]+o[:width]/2.0
          z1=floor+o.fetch(:floor_offset,0);z2=z1+o[:height]+o.fetch(:arch_rise,0).to_f
          pts=[x1,x2].product(offsets,[z1,z2]).map{|x,y,z|Geom::Point3d.new(sx+ux*x-uy*y,sy+uy*x+ux*y,z).transform(tr)}
          next if pts.map(&:y).min>0.5 || pts.map(&:y).max < -thick-0.5
          [pts.map(&:x).min,pts.map(&:z).min,pts.map(&:x).max,pts.map(&:z).max]
        end
      end
    end
    def self.hood_bottom(d)
      inv=KitchenLab.cabinet_transform(d).inverse
      KitchenLab.state['cabinets'].select{|h|h['kind']=='hood'}.filter_map do |h|
        tr=inv*KitchenLab.cabinet_transform(h)
        a=Geom::Point3d.new(0,0,0).transform(tr);b=Geom::Point3d.new(h['width'],0,0).transform(tr)
        next unless a.y.abs<2 && b.y.abs<2
        overlap=[d['width'],[a.x,b.x].max].min-[0,[a.x,b.x].min].max
        next unless overlap>[d['width'],h['width']].min*0.5 && a.z>d['height']
        a.z.to_f
      end.min
    end
    def self.build_ranges!
      return if validate(KitchenLab.settings['backsplash'])['mode']=='none'
      model=KitchenLab.instance_variable_get(:@model)
      KitchenLab.state['cabinets'].select{|d|d['kind']=='oven' && !d['surround_for']}.each do |d|
        holder=model.entities.add_group;holder.transformation=KitchenLab.cabinet_transform(d)
        holder.set_attribute(KitchenLab::DICT,'kind','worktop');holder.set_attribute(KitchenLab::DICT,'owner_id',d['id'])
        build!(holder,d,d,bottom_override:d['height'],top_override:hood_bottom(d))
      end
    end
    def self.build!(top,d,source=d,bottom_override:nil,top_override:nil)
      config=validate(KitchenLab.settings['backsplash']);return if config['mode']=='none' || !eligible?(source)
      thick=config['thickness'];bottom=bottom_override || d['height']+KitchenLab.settings.fetch('countertop_thickness',1.5)
      top_override ||= hood_bottom(d) if ApplianceCatalog.cooktop?(d)
      config=config.merge('height'=>top_override-bottom) if top_override && top_override>bottom
      model=KitchenLab.instance_variable_get(:@model)
      mat=config['mode']=='tile' ? (config['material'] ? CountertopMaterials.resolve(model,config['material']) : KitchenLab.material('Backsplash tile','#F5F3ED')) : CountertopMaterials.for_cabinet(source)
      strips=[{width:d['width'],transform:Geom::Transformation.new}]
      if %w[corner corner_base corner_lazy].include?(d['kind'])
        strips<<{width:d['width']-thick,transform:Geom::Transformation.axes([0,-thick,0],Geom::Vector3d.new(0,-1,0),Geom::Vector3d.new(-1,0,0),Z_AXIS)}
      end
      obstacles=model.entities.select{|e|e.respond_to?(:bounds) && %w[window door].include?(e.get_attribute('InteriorPro','type')) && !e.get_attribute('InteriorPro','host_wall_id')}
      strips.each do |strip|
        # Canonical world tangent: corner returns and mirrored cabinets may
        # traverse the same wall in opposite directions. Reverse the local strip
        # before clipping/grid construction, retaining its wall-facing Y axis.
        transform=top.transformation*strip[:transform]
        tangent=transform.xaxis
        if tangent.x < -1e-8 || (tangent.x.abs<=1e-8 && tangent.y < 0)
          strip=strip.merge(transform:strip[:transform]*Geom::Transformation.translation([strip[:width],0,0])*Geom::Transformation.scaling(-1,1,1))
          transform=top.transformation*strip[:transform]
        end
        inv=transform.inverse
        # Shared world-space lattice: adjoining cabinets never restart the tile grid.
        ux=transform.xaxis;uy=transform.yaxis;o=transform.origin
        gx=o.x*ux.x+o.y*ux.y;plane=o.x*uy.x+o.y*uy.y
        pitch_x=config['tile_width']+config['grout'];pitch_z=config['tile_height']+config['grout']
        grid=config.merge('_phase_x'=>gx%pitch_x,'_phase_z'=>(o.z+bottom-36.0)%pitch_z)

        holes=obstacles.filter_map do |e|
          bounds=e.bounds;pts=8.times.map{|i|bounds.corner(i).transform(inv)}
          next if pts.map(&:y).min>0.5 || pts.map(&:y).max < -thick-0.5
          [pts.map(&:x).min,pts.map(&:z).min,pts.map(&:x).max,pts.map(&:z).max]
        end
        holes.concat(opening_holes(model,inv,thick)) if defined?(InteriorPro::WallTool)
        # Upper cabinets clip the backsplash rather than being buried in it.
        KitchenLab.state['cabinets'].select{|c|c['id']!=source['id'] && %w[wall tall corner_upper fridge_surround].include?(c['kind'])}.each do |c|
          ct=inv*KitchenLab.cabinet_transform(c)
          pts=[0,c['width']].product([0,-c['depth']],[0,c['height']]).map{|p|Geom::Point3d.new(p).transform(ct)}
          next if pts.map(&:y).min>0.5 || pts.map(&:y).max < -thick-0.5
          holes<<[pts.map(&:x).min,pts.map(&:z).min,pts.map(&:x).max,pts.map(&:z).max]
        end
        group=top.entities.add_group;group.name='Kitchen / Backsplash';group.transformation=strip[:transform]
        group.set_attribute(KitchenLab::DICT,'kind','backsplash');group.set_attribute(KitchenLab::DICT,'owner_id',source['id'])
        # A thin grout backing closes the joints without covering openings.
        if config['mode']=='tile'
          grout=KitchenLab.material('Backsplash grout','#C9C6BF')
          rectangles(strip[:width],bottom,config.merge('mode'=>'countertop'),holes).each do |x,z,r,t|
            grout_depth=[thick-(defined?(InteriorPro::TileWall::GROUT_BACK) ? InteriorPro::TileWall::GROUT_BACK : 0.005),0.02].max
            KitchenLab.box(group.entities,'Grout',x,-grout_depth,z,r-x,grout_depth,t-z,grout)
          end
        end
        rectangles(strip[:width],bottom,grid,holes).each do |x,z,r,t|
          piece=KitchenLab.box(group.entities,config['mode']=='tile' ? 'Tile' : 'Slab',x,-thick,z,r-x,thick,t-z,mat)
          if config['mode']=='tile'
            col=((gx+(x+r)/2.0)/pitch_x).floor;row=((o.z+(z+t)/2.0-36.0)/pitch_z).floor
            key=[ux.x,ux.y,uy.x,uy.y].map{|v|v.abs<1e-8 ? 0.0 : v.round(6)}+[plane.round(5),col,row]
            piece.set_attribute(KitchenLab::DICT,'tile_cell',JSON.generate(key))
          end

        end
      end
    end
  end
end

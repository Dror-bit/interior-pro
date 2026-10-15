module KitchenLab
  module Backsplash
    BASE_KINDS=%w[doors drawers sink dishwasher filler corner corner_base corner_lazy].freeze unless const_defined?(:BASE_KINDS,false)
    def self.eligible?(d)
      !d['surround_for'] && ((BASE_KINDS+['oven']).include?(d['kind']) || (defined?(ApplianceCatalog) && ApplianceCatalog.microwave_base?(d)))
    end
    def self.validate(raw)
      return {'mode'=>'none'} if raw.nil?
      raise 'Invalid backsplash options' unless raw.is_a?(Hash)
      mode=raw.fetch('mode','none');raise 'Choose no backsplash, countertop or tile' unless %w[none countertop tile].include?(mode)
      return {'mode'=>'none'} if mode=='none'
      out={'mode'=>mode}
      {'height'=>[18,1,60],'thickness'=>[mode=='tile' ? 0.375 : 0.75,0.125,2],
       'tile_width'=>[6,1,48],'tile_height'=>[3,1,48],'grout'=>[0.125,0.03125,0.5]}.each do |key,(default,min,max)|
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
      thick=config['thickness'];bottom=bottom_override || d['height']+1.5
      top_override ||= hood_bottom(d) if ApplianceCatalog.cooktop?(d)
      config=config.merge('height'=>top_override-bottom) if top_override && top_override>bottom
      model=KitchenLab.instance_variable_get(:@model)
      mat=config['mode']=='tile' ? (config['material'] ? CountertopMaterials.resolve(model,config['material']) : KitchenLab.material('Backsplash tile','#F5F3ED')) : CountertopMaterials.for_cabinet(source)
      strips=[{width:d['width'],transform:Geom::Transformation.new}]
      if %w[corner corner_base corner_lazy].include?(d['kind'])
        strips<<{width:d['width']-thick,transform:Geom::Transformation.axes([0,-thick,0],Geom::Vector3d.new(0,-1,0),Geom::Vector3d.new(-1,0,0),Z_AXIS)}
      end
      obstacles=model.entities.select{|e|e.respond_to?(:bounds) && %w[window door].include?(e.get_attribute('InteriorPro','type'))}
      strips.each do |strip|
        transform=top.transformation*strip[:transform];inv=transform.inverse
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
            grout_depth=thick-[1.0/32.0,thick/4.0].min
            KitchenLab.box(group.entities,'Grout',x,-grout_depth,z,r-x,grout_depth,t-z,grout)
          end
        end
        rectangles(strip[:width],bottom,grid,holes).each do |x,z,r,t|
          piece=KitchenLab.box(group.entities,config['mode']=='tile' ? 'Tile' : 'Slab',x,-thick,z,r-x,thick,t-z,mat)
          if config['mode']=='tile'
            col=((gx+(x+r)/2.0)/pitch_x).floor;row=((o.z+(z+t)/2.0-36.0)/pitch_z).floor
            key=[ux.x.round(6),ux.y.round(6),uy.x.round(6),uy.y.round(6),plane.round(5),col,row]
            piece.set_attribute(KitchenLab::DICT,'tile_cell',JSON.generate(key))
          end

        end
      end
    end
  end
end

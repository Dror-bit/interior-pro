module KitchenLab
  module Backsplash
    BASE_KINDS=%w[doors drawers sink dishwasher filler corner corner_base corner_lazy].freeze unless const_defined?(:BASE_KINDS,false)
    def self.eligible?(d)
      !d['surround_for'] && (BASE_KINDS.include?(d['kind']) || (defined?(ApplianceCatalog) && ApplianceCatalog.microwave_base?(d)))
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
      tiles=[];z=bottom
      while z<bottom+config['height']-0.001
        x=0.0
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
    def self.build!(top,d,source=d)
      config=validate(source['backsplash']);return if config['mode']=='none' || !eligible?(source)
      thick=config['thickness'];bottom=d['height']+1.5
      model=KitchenLab.instance_variable_get(:@model)
      mat=config['mode']=='tile' ? (config['material'] ? CountertopMaterials.resolve(model,config['material']) : KitchenLab.material('Backsplash tile','#F5F3ED')) : KitchenLab.material('Worktop','#F2F0E9')
      strips=[{width:d['width'],transform:Geom::Transformation.new}]
      if %w[corner corner_base corner_lazy].include?(d['kind'])
        strips<<{width:d['width']-thick,transform:Geom::Transformation.axes([0,-thick,0],Geom::Vector3d.new(0,-1,0),Geom::Vector3d.new(-1,0,0),Z_AXIS)}
      end
      obstacles=model.entities.select{|e|e.respond_to?(:bounds) && %w[window door].include?(e.get_attribute('InteriorPro','type'))}
      strips.each do |strip|
        transform=top.transformation*strip[:transform];inv=transform.inverse
        holes=obstacles.filter_map do |e|
          bounds=e.bounds;pts=8.times.map{|i|bounds.corner(i).transform(inv)}
          next if pts.map(&:y).min>0.5 || pts.map(&:y).max < -thick-0.5
          [pts.map(&:x).min,pts.map(&:z).min,pts.map(&:x).max,pts.map(&:z).max]
        end
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
            KitchenLab.box(group.entities,'Grout',x,-0.0625,z,r-x,0.0625,t-z,grout)
          end
        end
        rectangles(strip[:width],bottom,config,holes).each do |x,z,r,t|
          KitchenLab.box(group.entities,config['mode']=='tile' ? 'Tile' : 'Slab',x,-thick,z,r-x,thick,t-z,mat)
        end
      end
    end
  end
end

load File.join(__dir__,'kitchen_sink_catalog.rb')
# Generic top-mount sink and faucet exterior. All dimensions are inches.
module KitchenLab
  module Sink
    def self.defaults(d)
      {'type'=>'single','width'=>[30,d['width']-4].min,'depth'=>[18,d['depth']-6].min,
        'bowl_depth'=>8.0,'offset_x'=>0.0,'front_setback'=>2.0,'finish'=>'stainless',
        'faucet'=>'arched','faucet_finish'=>'chrome','faucet_height'=>12.0}
    end
    def self.spec(d)
      raw=d['sink'];return nil if raw.nil?
      raise 'Sink settings require a sink base' unless d['kind']=='sink' && raw.is_a?(Hash)
      s=defaults(d).merge(raw)
      s['mount']='undermount' if raw['product_id']
      product=raw['product_id'] && SinkCatalog.record(d)
      if product && %w[kohler-k-5287 kohler-k-33152].include?(raw['product_id'])
        raise 'Wrong sink snapshot' unless product['id']==raw['product_id']
        s['catalog_snapshot']=JSON.parse(JSON.generate(product)).merge('automatic_cutout_available'=>false,'cutout'=>nil,'cutout_status'=>'awaiting_verified_manufacturer_template')
        s['automatic_cutout_available']=false
        minimum=raw['product_id']=='kohler-k-5287' ? 18 : 21
        raise "Sink requires a cabinet at least #{minimum} inches wide" if d['width']<minimum
      end
      s.merge!(product['spec'].slice('type','width','depth','bowl_depth','finish','drain_centres')) if product
      s.merge!('front_setback'=>-1,'offset_x'=>0) if product && product['model']=='K-6489'
      raise 'Invalid sink type' unless %w[none single double].include?(s['type'])
      return {'type'=>'none'} if s['type']=='none'
      ranges={'width'=>[12,48],'depth'=>[10,28],'bowl_depth'=>[4,12],'offset_x'=>[-24,24],'front_setback'=>[product && product['model']=='K-6489' ? -1 : 1.25,12],'faucet_height'=>[6,20]}
      ranges.each { |k,r| s[k]=Float(s[k]);raise "Invalid sink #{k}" unless s[k].finite? && s[k].between?(*r) }
      raise 'Invalid sink finish' unless %w[stainless white black].include?(s['finish'])
      raise 'Invalid faucet type' unless %w[none arched].include?(s['faucet'])
      raise 'Invalid faucet finish' unless %w[chrome brass black].include?(s['faucet_finish'])
      x=(d['width']-s['width'])/2.0+s['offset_x']
      raise 'Sink must fit between cabinet sides with 1 inch clearance' unless x>=(product && product['model']=='K-6489' ? 0.125 : 1) && x+s['width']<=d['width']-(product && product['model']=='K-6489' ? 0.125 : 1)
      rear_clearance=product && product['model']=='K-3838-1' ? 0.5 : 3
      raise 'Sink does not fit the cabinet depth' unless s['front_setback']+s['depth']<=d['depth']-rear_clearance
      raise 'Double sink needs at least 24 inches width' if s['type']=='double' && s['width']<24
      raise 'Sink bowl reaches the cabinet bottom' if d['height']+(product ? 0 : 1.5)-s['bowl_depth']<=d.fetch('toe_height',4)+1
      s.slice('automatic_cutout_available','catalog_snapshot','type',*ranges.keys,'finish','faucet','faucet_finish','product_id','drain_centres','mount')
    end
    def self.cutout(d)
      return nil if %w[kohler-k-5287 kohler-k-33152].include?(d.dig('sink','product_id')) || d.dig('sink','automatic_cutout_available')==false
      x,y,r,b=bounds(d);s=spec(d)
      return [x+0.5,y+0.5,r-0.5,b-0.5] unless s['product_id']
      l,f,right,back=SinkCatalog.find(s['product_id'])['cutout']
      [x+l,b+f,x+right,b+back]
    end
    def self.active?(d);d['kind']=='sink' && d['sink'].is_a?(Hash) && d['sink']['type']!='none';end
    def self.bounds(d)
      s=spec(d);x=(d['width']-s['width'])/2.0+s['offset_x'];y=-d['depth']+s['front_setback']
      [x,y,x+s['width'],y+s['depth']]
    end
  end

  # One solid slab with real through-holes; caller supplies local coordinates.
  def self.slab_with_holes(entities,name,bounds,z,thickness,holes,mat)
    g=entities.add_group;g.name=name
    loop_points=->(b) { [[b[0],b[1],z],[b[2],b[1],z],[b[2],b[3],z],[b[0],b[3],z]] }
    # Notches that reach the front edge are part of the outside contour.
    notches,inner=holes.partition { |h| h[1]<=bounds[1]+0.00001 }
    points=[[bounds[0],bounds[1],z]]
    notches.sort_by(&:first).each do |h|
      points.concat([[h[0],bounds[1],z],[h[0],h[3],z],[h[2],h[3],z],[h[2],bounds[1],z]])
    end
    points.concat([[bounds[2],bounds[1],z],[bounds[2],bounds[3],z],[bounds[0],bounds[3],z]])
    face=g.entities.add_face(points)
    inner.each { |hole| g.entities.add_face(loop_points.call(hole)).erase! }
    face=g.entities.grep(Sketchup::Face).max_by(&:area)
    raise 'Could not create countertop opening' unless face
    face.reverse! if face.normal.z<0
    face.pushpull(thickness)
    g.material=mat;g.entities.grep(Sketchup::Face).each { |f| f.material=mat;f.back_material=mat }
    g
  end

  def self.build_sink(entities,d)
    return unless Sink.active?(d)
    s=Sink.spec(d);x,y,right,back=Sink.bounds(d);w=right-x;dep=back-y;top=d['height']+1.5
    if s['product_id']
      SinkCatalog.build(entities,d)
    else
    metal=material('Sink '+s['finish'],{'stainless'=>'#ADB8BD','white'=>'#F4F3ED','black'=>'#292E30'}[s['finish']])
    g=entities.add_group;g.name='Sink / '+s['type'];e=g.entities
    slab_with_holes(e,'Sink rim',[x,y,right,back],top,0.12,[[x+0.5,y+0.5,right-0.5,back-0.5]],metal)
    bottom=top-s['bowl_depth'];t=0.12
    box(e,'Bowl floor',x+0.5,y+0.5,bottom,w-1,dep-1,t,metal)
    box(e,'Bowl left',x+0.5,y+0.5,bottom,t,dep-1,s['bowl_depth'],metal)
    box(e,'Bowl right',right-0.5-t,y+0.5,bottom,t,dep-1,s['bowl_depth'],metal)
    box(e,'Bowl front',x+0.5+t,y+0.5,bottom,w-1-2*t,t,s['bowl_depth'],metal)
    box(e,'Bowl back',x+0.5+t,back-0.5-t,bottom,w-1-2*t,t,s['bowl_depth'],metal)
    box(e,'Bowl divider',x+w/2-0.125,y+0.5,bottom,0.25,dep-1,s['bowl_depth']-0.3,metal) if s['type']=='double'
    drains=s['type']=='double' ? [x+w/4,x+w*3/4] : [x+w/2]
    drains.each do |cx|
      drain=e.add_group;drain.name='Drain';f=drain.entities.add_face(drain.entities.add_circle([cx,y+dep/2,bottom+t+0.01],[0,0,1],0.65,24));f.material=material('Sink drain','#343B40');f.back_material=f.material
    end
    end
    return if s['faucet']=='none'
    faucet=entities.add_group;faucet.name='Faucet / arched';f=faucet.entities
    chrome=material('Faucet '+s['faucet_finish'],{'chrome'=>'#C9D2D6','brass'=>'#B39456','black'=>'#242729'}[s['faucet_finish']])
    cx=x+w/2;fy=back+(s['product_id']=='kohler-k-3838-1' ? -2.4375 : 1.5);radius=2.5;h=s['faucet_height']
    path=[[cx,fy,top],[cx,fy,top+h-radius]]
    1.upto(16) { |i| a=i*Math::PI/16;path<<[cx,fy-radius+radius*Math.cos(a),top+h-radius+radius*Math.sin(a)] }
    path<<[cx,fy-2*radius,top+h-radius-1]
    path.each_cons(2).with_index do |(a,b),i|
      piece=f.add_group;piece.name="Faucet tube #{i}";v=Geom::Vector3d.new(b.zip(a).map { |bv,av| bv-av })
      face=piece.entities.add_face(piece.entities.add_circle(a,v,0.32,16));face.reverse! if face.normal.dot(v)<0;face.pushpull(v.length);piece.material=chrome
    end
    box(f,'Faucet lever',cx+0.5,fy-0.15,top+1,1.5,0.3,0.3,chrome)
  end
end



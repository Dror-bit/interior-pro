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
      raise 'Invalid sink type' unless %w[none single double].include?(s['type'])
      return {'type'=>'none'} if s['type']=='none'
      ranges={'width'=>[12,48],'depth'=>[10,28],'bowl_depth'=>[4,12],'offset_x'=>[-24,24],'front_setback'=>[1.25,12],'faucet_height'=>[6,20]}
      ranges.each { |k,r| s[k]=Float(s[k]);raise "Invalid sink #{k}" unless s[k].finite? && s[k].between?(*r) }
      raise 'Invalid sink finish' unless %w[stainless white black].include?(s['finish'])
      raise 'Invalid faucet type' unless %w[none arched].include?(s['faucet'])
      raise 'Invalid faucet finish' unless %w[chrome brass black].include?(s['faucet_finish'])
      x=(d['width']-s['width'])/2.0+s['offset_x']
      raise 'Sink must fit between cabinet sides with 1 inch clearance' unless x>=1 && x+s['width']<=d['width']-1
      raise 'Leave 3 inches behind the sink for the faucet' unless s['front_setback']+s['depth']<=d['depth']-3
      raise 'Double sink needs at least 24 inches width' if s['type']=='double' && s['width']<24
      raise 'Sink bowl reaches the cabinet bottom' if d['height']+1.5-s['bowl_depth']<=d.fetch('toe_height',4)+1
      s.slice('type',*ranges.keys,'finish','faucet','faucet_finish')
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
    face=g.entities.add_face(loop_points.call(bounds))
    holes.each { |hole| g.entities.add_face(loop_points.call(hole)).erase! }
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
    return if s['faucet']=='none'
    faucet=entities.add_group;faucet.name='Faucet / arched';f=faucet.entities
    chrome=material('Faucet '+s['faucet_finish'],{'chrome'=>'#C9D2D6','brass'=>'#B39456','black'=>'#242729'}[s['faucet_finish']])
    cx=x+w/2;fy=back+1.5;radius=2.5;h=s['faucet_height']
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

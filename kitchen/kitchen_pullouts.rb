module KitchenLab
  module Pullouts
    TYPES=%w[spice waste storage].freeze unless const_defined?(:TYPES,false)
    def self.validate(raw,d)
      return nil if raw.nil? || (raw.is_a?(Hash) && raw['type']=='none')
      raise 'Choose spice, waste or storage pull-out' unless raw.is_a?(Hash) && TYPES.include?(raw['type'])
      raise 'Pull-outs require a plain base cabinet without a sink or appliance' unless d['kind']=='doors' && !d['surround_for'] && !d['sink'] && !d['appliance']
      raise 'Pull-outs require at least 18 inches depth and 24 inches height' unless d['depth']>=18 && d['height']>=24
      raise 'Waste pull-out requires at least 15 inches width' if raw['type']=='waste' && d['width']<15
      extension=Float(raw.fetch('extension',0));raise 'Pull-out extension must fit the cabinet depth' unless extension.finite? && extension.between?(0,d['depth']-3)
      bins=Integer(raw.fetch('bins',2));raise 'Choose one or two bins' unless [1,2].include?(bins)
      {'type'=>raw['type'],'extension'=>extension,'bins'=>bins}
    end
    def self.front_rows(d)
      available=d['height']-d.fetch('toe_height',4)-0.25
      return [{'kind'=>'drawer','height'=>5.875},{'kind'=>'doors','doors'=>1,'height'=>available-6.0}] if d.dig('pullout','type')=='waste'
      [{'kind'=>'doors','doors'=>1,'height'=>available}]
    end
    def self.tray(entities,name,x,y,z,w,depth,rim,mat)
      t=0.25
      KitchenLab.box(entities,name+' base',x,y,z,w,depth,t,mat)
      KitchenLab.box(entities,name+' left',x,y,z+t,t,depth,rim,mat)
      KitchenLab.box(entities,name+' right',x+w-t,y,z+t,t,depth,rim,mat)
      KitchenLab.box(entities,name+' front',x+t,y,z+t,w-2*t,t,rim,mat)
      KitchenLab.box(entities,name+' back',x+t,y+depth-t,z+t,w-2*t,t,rim,mat)
    end
    def self.build!(entities,d,finish,metal)
      cfg=validate(d['pullout'],d);return unless cfg
      w=d['width'];dep=d['depth'];toe=d.fetch('toe_height',4);h=d['height']
      rails=KitchenLab.material('Pull-out slides','#A3AAAD')
      [0.8,w-1.1].each{|x|KitchenLab.box(entities,'Pull-out fixed slide',x,-dep+1.5,toe+1.0,0.3,dep-2.5,0.6,rails)}
      moving=entities.add_group;moving.name='Pull-out / '+cfg['type'];moving.set_attribute(KitchenLab::DICT,'pullout_type',cfg['type'])
      moving.transformation=Geom::Transformation.translation([0,-cfg['extension'],0]);e=moving.entities
      KitchenLab.front(e,'Pull-out front',0.125,toe+0.125,w-0.25,front_rows(d).last['height'],d.merge('handle_position'=>'top','_handle_model_key'=>'door_handle_model'),finish,metal,true)
      x=1.25;y=-dep+1.25;tw=w-2.5;td=dep-2.25;bottom=toe+1.75
      interior=KitchenLab.material('Pull-out interior','#D3B994')
      if cfg['type']=='waste'
        drawer_bottom=h-6.0
        drawer=entities.add_group;drawer.name='Trash upper drawer';de=drawer.entities
        KitchenLab.front(de,'Trash upper drawer',0.125,drawer_bottom,w-0.25,5.875,d.merge('handle_position'=>'center'),finish,metal,true)
        tray(de,'Upper drawer box',x,y,drawer_bottom+0.5,tw,td,3.0,interior)
        tray(e,'Bin carrier',x,y,bottom,tw,td,1,interior)
        count=cfg['bins'];bd=(td-0.75*(count+1))/count;bw=tw-1.5;bh=[drawer_bottom-bottom-1.0,20].min
        plastic=KitchenLab.material('Pull-out bins','#4E5557')
        count.times{|i|tray(e,"Waste bin #{i+1}",x+0.75,y+0.75+i*(bd+0.75),bottom+0.3,bw,bd,bh,plastic)}
      else
        count=cfg['type']=='spice' ? 3 : 2
        gap=(h-bottom-5)/(count-1)
        count.times{|i|tray(e,"#{cfg['type']} tray #{i+1}",x,y,bottom+i*gap,tw,td,cfg['type']=='spice' ? 2 : 3,interior)}
        [x,x+tw-0.35].each{|xx|KitchenLab.box(e,'Carrier upright',xx,-1.4,bottom,0.35,0.35,h-bottom-2,rails)}
      end
      moving
    end
  end
end

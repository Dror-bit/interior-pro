require_relative '../cabinetry/core'
module InteriorPro
  module Vanity
    module Domain
      module_function
      def cabinet(id, product='vanity')
        {'id'=>id,'product_id'=>product,'width'=>36.0,'depth'=>21.0,'height'=>30.0,
         'position'=>{'x'=>0.0,'y'=>0.0,'z'=>0.0,'angle'=>0.0},'sections'=>[],
         'mount'=>'floor','legs'=>false,'support_height'=>4.0,'style'=>'shaker',
         'finish'=>'white','handle'=>'brass','basins'=>product=='vanity' ? 1 : 0,
         'drawer'=>false,'sink_id'=>'none','faucet_id'=>'none'}
      end
      def body_bottom(c)
        c['mount']=='floor' && c['legs'] ? c['support_height'] : 0.0
      end
      def validate(source)
        d=Cabinetry.validate(source)
        raise ArgumentError,'Wrong domain' unless d['domain']=='vanity'
        d['cabinets'].each do |c|
          raise ArgumentError,'Unknown product' unless %w[vanity makeup gallery].include?(c['product_id'])
          {'width'=>[12,120],'depth'=>[12,30],'height'=>[8,42]}.each do |key,range|
            n=c[key];raise ArgumentError,"Invalid #{key}" unless n.between?(*range) && (c['product_id']=='gallery' || (n*8-(n*8).round).abs<1e-6)
          end
          {'mount'=>%w[floor floating],'style'=>%w[shaker slab],
           'finish'=>%w[white ivory gray],'handle'=>%w[none brass black]}.each do |k,values|
            raise ArgumentError,"Invalid #{k}" unless values.include?(c[k])
          end
          %w[legs drawer].each { |k|raise ArgumentError,"Invalid #{k}" unless [true,false].include?(c[k]) }
          Cabinetry.number!(c['support_height'],positive:true)
          raise ArgumentError,'Leg height must be 2–10 inches' unless c['support_height'].between?(2,10)
          raise ArgumentError,'Floating cabinets cannot have floor legs' if c['mount']=='floating' && c['legs']
          raise ArgumentError,'Floor cabinets must start at floor level' if c['mount']=='floor' && c['position']['z']!=0
          raise ArgumentError,'Floating cabinets need a positive mounting height' if c['mount']=='floating' && c['position']['z']<=0
          raise ArgumentError,'Custom sections not supported yet' unless c['sections'].empty?
          raise ArgumentError,'Invalid basin count' unless c['basins'].is_a?(Integer) && (c['product_id']=='vanity' ? [1,2] : [0]).include?(c['basins'])
          raise ArgumentError,'Makeup drawer only' if c['drawer'] && c['product_id']!='makeup'
          raise ArgumentError,'Insufficient body height' if c['height']-body_bottom(c)<8
          if c['product_id']=='vanity'
            raise ArgumentError,'Two basins require at least 48 inches' if c['basins']==2 && c['width']<48
            # Layout allowance only. Actual installation requires a verified adapter.
            raise ArgumentError,'No verified bathroom sink/faucet adapter installed' unless c['sink_id']=='none' && c['faucet_id']=='none'
          end
          Cabinetry.identifier!(c['asset_id']) if c['product_id']=='gallery'
        end
        raise ArgumentError,'Vanity cabinets overlap' if d['cabinets'].combination(2).any? { |a,b|overlap?(a,b) }
        true
      end
      def footprint(c)
        p=c['position'];r=p['angle']*Math::PI/180;co=Math.cos(r);si=Math.sin(r)
        [[0,0],[c['width'],0],[c['width'],-c['depth']],[0,-c['depth']]].map { |x,y|[p['x']+x*co-y*si,p['y']+x*si+y*co] }
      end
      def overlap?(a,b)
        return false if [a['position']['z']+a['height'],b['position']['z']+b['height']].min-[a['position']['z'],b['position']['z']].max<=0.001
        aa=footprint(a);bb=footprint(b)
        [aa,bb].all? do |poly|
          poly.each_with_index.all? do |p,i|
            q=poly[(i+1)%4];dx=q[0]-p[0];dy=q[1]-p[1];length=Math.hypot(dx,dy)
            x=aa.map { |v|(-dy*v[0]+dx*v[1])/length };y=bb.map { |v|(-dy*v[0]+dx*v[1])/length }
            [x.max,y.max].min-[x.min,y.min].max>0.001
          end
        end
      end
    end
  end
end

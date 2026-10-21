require_relative '../cabinetry/core'
require_relative 'surfaces'
require_relative 'faucets'
require_relative 'accessories'
module InteriorPro
  module Vanity
    module Domain
      module_function
      def handle_left?(col,index)
        side=(col['door_handle_sides']||[])[index]||'auto'
        side=='left' || (side=='auto' && index.odd?)
      end
      def front_columns(c)
        c['front_columns'].is_a?(Array) && !c['front_columns'].empty? ? c['front_columns'] :
          Array.new(c['basins']) { {'kind'=>'doors','count'=>2} }
      end
      def cabinet(id, product='vanity')
        {'id'=>id,'product_id'=>product,'width'=>36.0,'depth'=>21.0,'height'=>30.0,
         'position'=>{'x'=>0.0,'y'=>0.0,'z'=>0.0,'angle'=>0.0},'sections'=>[],
         'mount'=>'floor','legs'=>false,'support_height'=>4.0,'style'=>'shaker',
         'finish'=>'white','handle'=>'brass','basins'=>product=='vanity' ? 1 : 0,
         'drawer'=>false,'sink_id'=>'none','faucet_id'=>'none'}.tap do |c|
          c['surfaces']=Surfaces.new_defaults if product=='vanity'
        end
      end
      # Legacy documents without widths retain their original equal division.
      def column_layout(c)
        cols=front_columns(c);x=0.0
        cols.map do |col|
          width=col.fetch('width',c['width']/cols.length.to_f)
          row={'x'=>x,'width'=>width};x+=width;row
        end
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
           'finish'=>%w[white ivory gray white_oak],'handle'=>%w[none brass black keaton warwick globe hunter]}.each do |k,values|
            raise ArgumentError,"Invalid #{k}" unless values.include?(c[k])
          end
          %w[legs drawer].each { |k|raise ArgumentError,"Invalid #{k}" unless [true,false].include?(c[k]) }
          raise ArgumentError,'סוג רגליים לא תקין' unless %w[square round plinth].include?(c.fetch('leg_style','square'))
          Cabinetry.number!(c['support_height'],positive:true)
          raise ArgumentError,'Leg height must be 2–10 inches' unless c['support_height'].between?(2,10)
          raise ArgumentError,'Floating cabinets cannot have floor legs' if c['mount']=='floating' && c['legs']
          raise ArgumentError,'Floor cabinets must start at floor level' if c['mount']=='floor' && c['position']['z']!=0
          raise ArgumentError,'Floating cabinets need a positive mounting height' if c['mount']=='floating' && c['position']['z']<=0
          raise ArgumentError,'Custom sections not supported yet' unless c['sections'].empty?
          raise ArgumentError,'Only a white countertop is available' unless [nil,'white'].include?(c['countertop'])
          if c.key?('front_columns')
            cols=c['front_columns']
            raise ArgumentError,'Invalid front layout' unless cols.is_a?(Array) && cols.length<=6
            raise ArgumentError,'Front layout is for bathroom cabinets' if c['product_id']!='vanity' && !cols.empty?
            if cols.any? { |col|col.is_a?(Hash) && col.key?('width') }
              cols.each do |col|
                width=col.is_a?(Hash) && col['width']
                Cabinetry.number!(width,positive:true)
                raise ArgumentError,'רוחב חלק צריך להיות 4–120 אינץ׳, בכפולות של שמינית' unless width.between?(4,120) && (width*8-(width*8).round).abs<1e-6
              end
              raise ArgumentError,'הרוחב הכולל חייב להיות סכום רוחבי החלקים' unless (cols.sum { |col|col['width'] }-c['width']).abs<1e-6
            end
            cols.each do |col|
              raise ArgumentError,'Invalid front column' unless col.is_a?(Hash) && %w[doors doors_drawer drawers makeup].include?(col['kind']) && col['count'].is_a?(Integer) && (col['kind']=='makeup' ? col['count'].between?(0,1) : col['count'].between?(1,4))
              if %w[doors doors_drawer].include?(col['kind']) && col.key?('door_handle_sides')
                sides=col['door_handle_sides']
                raise ArgumentError,'צד ידית לא תקין' unless sides.is_a?(Array) && sides.length==col['count'] && sides.all? { |s|%w[auto left right].include?(s) }
              end
              if col['kind']=='makeup'
                raise ArgumentError,'אזור המייק־אפ צריך רוחב של 24 אינץ׳ לפחות' unless col.fetch('width',c['width']/cols.length.to_f)>=24
                raise ArgumentError,'אין מספיק מקום לישיבה מתחת למייק־אפ' unless c['height']+c['position']['z']-(col['count']==1 ? 5.25 : 0)>=24
                next
              end
              fw=col.fetch('width',c['width']/cols.length.to_f)/(%w[doors doors_drawer].include?(col['kind']) ? col['count'] : 1)-0.25
              fh=(c['height']-body_bottom(c)-(col['kind']=='doors_drawer' ? 5 : 0))/(col['kind']=='drawers' ? col['count'] : 1)-0.125
              minimum=c['style']=='shaker' ? 4.25 : 1.0
              raise ArgumentError,'החלוקה צפופה מדי למידות הארון ולחזית שנבחרה' unless [fw,fh].min>minimum
              raise ArgumentError,'אזור המגירות צר מדי' if col['kind']=='drawers' && fw<=3
              raise ArgumentError,'הידית ארוכה מדי לחזית; בחר Globe או שנה חלוקה' if %w[keaton warwick].include?(c['handle']) && (col['kind']=='drawers' ? fw : fh)<4.75
            end
            raise ArgumentError,'נדרש אזור ארון לצד המייק־אפ' if c['product_id']=='vanity' && !cols.empty? && cols.all? { |col|col['kind']=='makeup' }
          end
          raise ArgumentError,'Invalid basin count' unless c['basins'].is_a?(Integer) && (c['product_id']=='vanity' ? [1,2] : [0]).include?(c['basins'])
          raise ArgumentError,'Makeup drawer only' if c['drawer'] && c['product_id']!='makeup'
          raise ArgumentError,'Insufficient body height' if c['height']-body_bottom(c)<8
          Accessories.validate(c)
          Surfaces.validate(c)
          if c['product_id']=='vanity'
            raise ArgumentError,'Two basins require at least 48 inches' if c['basins']==2 && c['width']<48
            raise ArgumentError,'Unknown sink adapter' unless c['sink_id']=='none'
            Faucets.validate(c)
          end
          Cabinetry.identifier!(c['asset_id']) if c['product_id']=='gallery'
        end
        raise ArgumentError,'Vanity cabinets overlap' if d['cabinets'].combination(2).any? { |a,b|overlap?(a,b) }
        true
      end
      def footprint(c)
        p=c['position'];r=p['angle']*Math::PI/180;co=Math.cos(r);si=Math.sin(r)
        depth=c['depth']+(c.key?('surfaces') || (c['product_id']=='vanity' && c['countertop']=='white') ? 0.5 : 0)
        [[0,0],[c['width'],0],[c['width'],-depth],[0,-depth]].map { |x,y|[p['x']+x*co-y*si,p['y']+x*si+y*co] }
      end
      def overlap?(a,b)
        return false if [a,b].map { |c|c['position']['z']+c['height']+(c.key?('surfaces') ? Surfaces.settings(c)['countertop_thickness']+Surfaces.settings(c)['backsplash_height'] : c['product_id']=='vanity' && c['countertop']=='white' ? 0.75 : 0) }.min-[a['position']['z'],b['position']['z']].max<=0.001
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

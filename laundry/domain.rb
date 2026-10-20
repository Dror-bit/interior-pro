require_relative '../cabinetry/core'
require_relative 'appliances'
module InteriorPro
  module Laundry
    remove_const(:USE_UPPER_PRODUCTS) if const_defined?(:USE_UPPER_PRODUCTS,false)
    USE_UPPER_PRODUCTS=true
    module Domain
      module_function
      def cabinet(id,product='base')
        if Appliances::MODELS.key?(product)
          raise ArgumentError,'Appliance products are disabled' unless Laundry::USE_APPLIANCE_PRODUCTS
          spec=Appliances::MODELS.fetch(product)
          return {'id'=>id,'product_id'=>product,'model_id'=>spec['model'],'width'=>spec['width'],'height'=>spec['height'],'depth'=>spec['depth'],
            'position'=>{'x'=>0.0,'y'=>0.0,'z'=>0.0,'angle'=>0.0},'sections'=>[],
            'front'=>'appliance','style'=>'slab','finish'=>'white','handle'=>'none'}
        end
        if product=='upper'
          raise ArgumentError,'Upper cabinets are disabled' unless Laundry::USE_UPPER_PRODUCTS
          return cabinet(id).merge('product_id'=>'upper','height'=>30.0,'depth'=>12.0,'shelves'=>2,
            'position'=>{'x'=>0.0,'y'=>0.0,'z'=>66.0,'angle'=>0.0})
        end
        raise ArgumentError,'Unsupported laundry product' unless product=='base'
        {'id'=>id,'product_id'=>'base','width'=>30.0,'height'=>34.5,'depth'=>24.0,
         'position'=>{'x'=>0.0,'y'=>0.0,'z'=>0.0,'angle'=>0.0},'sections'=>[],
         'front'=>'double','style'=>'shaker','finish'=>'ivory','handle'=>'brass'}
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
            q=poly[(i+1)%poly.length];dx=q[0]-p[0];dy=q[1]-p[1];len=Math.hypot(dx,dy)
            x=aa.map { |v|(-dy*v[0]+dx*v[1])/len };y=bb.map { |v|(-dy*v[0]+dx*v[1])/len }
            [x.max,y.max].min-[x.min,y.min].max>0.001
          end
        end
      end
      def validate(doc)
        raise ArgumentError,'Wrong design domain' unless doc['domain']=='laundry'
        doc['cabinets'].each do |c|
          if Appliances.appliance?(c)
            Appliances.validate(c)
            next
          end
          upper=c['product_id']=='upper'
          raise ArgumentError,'Unsupported laundry product' unless c['product_id']=='base' || (upper && Laundry::USE_UPPER_PRODUCTS)
          raise ArgumentError,'Width must be 12–48 inches' unless c['width'].between?(12,48)
          limits=upper ? [12,48,10,24] : [24,42,12,30]
          raise ArgumentError,"Height must be #{limits[0]}–#{limits[1]} inches" unless c['height'].between?(*limits.first(2))
          raise ArgumentError,"Depth must be #{limits[2]}–#{limits[3]} inches" unless c['depth'].between?(*limits.last(2))
          %w[width height depth].each { |k|raise ArgumentError,'Use 1/8-inch increments' if (c[k]*8-(c[k]*8).round).abs>1e-6 }
          {'front'=>%w[single double drawers],'style'=>%w[shaker slab],
           'finish'=>%w[ivory white gray],'handle'=>%w[brass black none]}.each do |key,values|
            raise ArgumentError,"Invalid #{key}" unless values.include?(c[key])
          end
          if upper
            z=c['position']['z']
            raise ArgumentError,'Upper cabinet bottom must be 12–108 inches, in eighths' unless z.between?(12,108) && (z*8-(z*8).round).abs<1e-6
            raise ArgumentError,'Upper cabinets use single or double doors' unless %w[single double].include?(c['front'])
            raise ArgumentError,'Upper cabinet needs 0–6 shelves' unless c['shelves'].is_a?(Integer) && c['shelves'].between?(0,6)
            raise ArgumentError,'Too many shelves for the cabinet height' if (c['height']-1.5)/(c['shelves']+1)<3
          else
            raise ArgumentError,'Base cabinets sit on the floor' unless c['position']['z']==0
          end
          raise ArgumentError,'Custom sections are not enabled for this base product' unless c['sections'].empty?
        end
        raise ArgumentError,'Laundry cabinets overlap' if doc['cabinets'].combination(2).any? { |a,b|overlap?(a,b) }
        Appliances.validate_fit!(doc['cabinets'])
        true
      end
    end
  end
end

require_relative '../cabinetry/core'
require_relative '../laundry/domain'
module InteriorPro
  module Storage
    module WardrobeDomain
      module_function
      def usable_height(height);height-5.5;end # 4-inch toe + two 3/4-inch boards
      def cabinet(id)
        heights=Cabinetry.divide(usable_height(84.0),4)
        {'id'=>id,'product_id'=>'wardrobe','width'=>30.0,'height'=>84.0,'depth'=>24.0,
         'position'=>{'x'=>0.0,'y'=>0.0,'z'=>0.0,'angle'=>0.0},
         'sections'=>heights.each_with_index.map { |h,i|{'id'=>"section-#{i+1}",'kind'=>'shelf','height'=>h} },
         'front'=>'open','style'=>'slab','finish'=>'ivory','handle'=>'black'}
      end
      def validate(doc)
        raise ArgumentError,'Wrong design domain' unless doc['domain']=='wardrobe'
        doc['cabinets'].each do |c|
          raise ArgumentError,'Unsupported wardrobe product' unless c['product_id']=='wardrobe'
          {'width'=>[12,48],'height'=>[48,108],'depth'=>[12,30]}.each do |key,(lo,hi)|
            raise ArgumentError,"#{key.capitalize} must be #{lo}–#{hi} inches" unless c[key].between?(lo,hi)
            raise ArgumentError,'Use 1/8-inch dimensions' unless (c[key]*8-(c[key]*8).round).abs<1e-6
          end
          {'front'=>%w[open single double],'style'=>%w[shaker slab],'finish'=>%w[ivory white gray],'handle'=>%w[brass black none]}.each do |key,values|
            raise ArgumentError,"Invalid #{key}" unless values.include?(c[key])
          end
          raise ArgumentError,'Wardrobes sit on the floor' unless c['position']['z']==0
          sections=c['sections']
          raise ArgumentError,'Provide 1–16 sections, ordered bottom to top' unless sections.length.between?(1,16)
          sections.each do |s|
            raise ArgumentError,'Unsupported wardrobe section' unless %w[shelf hanging drawer open].include?(s['kind'])
            minimum={'shelf'=>5,'open'=>5,'drawer'=>5,'hanging'=>24}.fetch(s['kind'])
            raise ArgumentError,"#{s['kind'].capitalize} section needs at least #{minimum} inches" if s['height']<minimum
            raise ArgumentError,'Use 1/8-inch section heights' unless (s['height']*8-(s['height']*8).round).abs<1e-6
            raise ArgumentError,'Hanging sections need at least 20 inches depth' if s['kind']=='hanging' && c['depth']<20
          end
          raise ArgumentError,"Section heights must total #{usable_height(c['height'])} inches (inside the cabinet)" if (sections.sum { |s|s['height'] }-usable_height(c['height'])).abs>1e-6
        end
        raise ArgumentError,'Wardrobe cabinets overlap' if doc['cabinets'].combination(2).any? { |a,b|Laundry::Domain.overlap?(a,b) }
        true
      end
    end
  end
end

module InteriorPro
  module Laundry
    remove_const(:USE_APPLIANCE_PRODUCTS) if const_defined?(:USE_APPLIANCE_PRODUCTS,false)
    USE_APPLIANCE_PRODUCTS=true
    module Appliances
      remove_const(:MODELS) if const_defined?(:MODELS,false)
      MODELS={
        'washer'=>{'model'=>'LG WM4000HWA','width'=>27.0,'height'=>39.0,'depth'=>30.25,
          'side'=>1.0,'rear'=>4.0,'front'=>24.75,'top'=>0.25,
          'source'=>'https://www.lg.com/us/business/download/resources/CT00021979/WM4000H_A_LG_Pro_Builder_Spec_Sheet%5B20250528_051619%5D.pdf'},
        'dryer'=>{'model'=>'LG DLEX4000W','width'=>27.0,'height'=>39.0,'depth'=>30.125,
          'side'=>1.0,'rear'=>5.0,'front'=>21.25,'top'=>18.0,'overhead_depth'=>14.0,
          'source'=>'https://www.lg.com/us/business/download/resources/CT00021979/DLEX4000_%20DLGX4001_%20LG%20Pro_Builder_Spec_Sheet%5B20250528_060503%5D.pdf'},
        'washer_top'=>{'model'=>'LG WT7400CW','width'=>27.0,'height'=>44.5,'depth'=>28.375,
          'side'=>1.0,'rear'=>4.0,'front'=>0.0,'top'=>13.5,'lid_open_height'=>57.25,
          'source'=>'https://www.lg.com/us/business/download/resources/CT00021979/WT7400C_%20LG%20Builder%20Spec%20Sheet%5B20220726_041839%5D.pdf'},
        'dryer_rear'=>{'model'=>'LG DLE7400WE','width'=>27.0,'height'=>44.25,'depth'=>29.5,
          'side'=>1.0,'rear'=>5.0,'front'=>20.75,'top'=>18.0,'overhead_depth'=>14.0,
          'source'=>'https://www.lg.com/us/business/download/resources/CT00021979/DLE7400_E%20DLG7401_E%20LG%20Builder%20Spec%20Sheet%5B20220414_112739%5D.pdf'},
        'stack'=>{'model'=>'LG WM4000HWA + DLEX4000W / KSTK4','width'=>27.0,'height'=>78.0,'depth'=>30.25,
          'side'=>1.0,'rear'=>5.5,'front'=>24.75,'top'=>6.0,
          'source'=>'https://www.lg.com/us/business/download/resources/CT00021979/DLEX4000_%20DLGX4001_%20LG%20Pro_Builder_Spec_Sheet%5B20250528_060503%5D.pdf'}
      }
      # Pair extents are derived from fixed catalog dimensions plus the shared
      # one-inch side gap, not a stretched appliance or a manufacturer SKU.
      {'pair_front'=>['washer','dryer'],'pair_top'=>['washer_top','dryer_rear']}.each do |key,parts|
        a,b=parts.map{|part|MODELS.fetch(part)}
        MODELS[key]={'model'=>"#{a['model']} + #{b['model']} / side by side",'width'=>a['width']+1+b['width'],
          'height'=>[a['height'],b['height']].max,'depth'=>[a['depth'],b['depth']].max,
          'side'=>1.0,'rear'=>[a['rear'],b['rear']].max,'front'=>[a['front'],b['front']].max,
          'top'=>[a['top'],b['top']].max,'overhead_depth'=>14.0,'parts'=>parts,'source'=>a['source']}
      end
      MODELS.each_value(&:freeze);MODELS.freeze
      module_function
      def appliance?(c);MODELS.key?(c['product_id']);end
      def model(c);MODELS.fetch(c['product_id']);end
      def validate(c)
        raise ArgumentError,'Appliance products are disabled' unless Laundry::USE_APPLIANCE_PRODUCTS
        spec=model(c)
        raise ArgumentError,'Appliance model mismatch' unless c['model_id']==spec['model']
        raise ArgumentError,'LG appliance dimensions are fixed; choose a different catalog model instead of scaling' unless %w[width height depth].all?{|k|c[k]==spec[k]}
        raise ArgumentError,'Use the verified stacked product for stacking; individual products sit on the floor' unless c['position']['z']==0
        raise ArgumentError,'Appliance finish must be white' unless c['finish']=='white'
        raise ArgumentError,'Invalid appliance configuration' unless c['front']=='appliance' && c['style']=='slab' && c['handle']=='none' && c['sections'].empty?
      end
      # Conservative open-front, rear-vented planning envelope. Adjacent units
      # share their side gap; envelopes are compared against bodies, not each other.
      def envelope(c)
        spec=model(c);p=c['position'];a=p['angle']*Math::PI/180;dx=-spec['side'];dy=spec['rear']
        c.merge('width'=>c['width']+2*spec['side'],'depth'=>c['depth']+spec['rear']+spec['front'],
          'height'=>c['height']+spec['top'],
          'position'=>p.merge('x'=>p['x']+dx*Math.cos(a)-dy*Math.sin(a),'y'=>p['y']+dx*Math.sin(a)+dy*Math.cos(a)))
      end
      def validate_fit!(cabinets)
        cabinets.select{|c|appliance?(c)}.each do |c|
          spec=model(c)
          cabinets.each do |other|
            next if other.equal?(c)
            if Domain.overlap?(envelope(c),other)
              raise ArgumentError,"#{spec['model']}: keep side, rear, door-opening and overhead planning clearances free"
            end
            # Above the dryer, the manufacturer's recessed-installation drawing
            # limits an overhead cabinet to 14 inches deep.
            angle=(other['position']['angle']-c['position']['angle'])*Math::PI/180
            projected_depth=other['width']*Math.sin(angle).abs+other['depth']*Math.cos(angle).abs
            if spec['overhead_depth'] && other['product_id']=='upper' && other['position']['z']>=c['height'] && Domain.overlap?(c.merge('height'=>200.0),other) && projected_depth>spec['overhead_depth']+1e-6
              raise ArgumentError,"Cabinet above #{spec['model']} must be no deeper than 14 inches in this installation profile"
            end
          end
        end
      end
    end
  end
end

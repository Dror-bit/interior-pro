# Public, inch-based manufacturer catalog. Saved selections are snapshots, so
# a later catalog refresh cannot silently change the user's kitchen.
module KitchenLab
  module ApplianceCatalog
    KINDS={'fridge'=>'fridge','range'=>'oven','rangetop'=>'oven','wall_oven'=>'wall_oven','dishwasher'=>'dishwasher','hood'=>'hood','microwave'=>'microwave','cooktop'=>'doors'}.freeze unless const_defined?(:KINDS,false)
    def self.products
      JSON.parse(File.read(File.join(__dir__,'appliance_catalog.json')))['products'].select { |p| p['dimensions'] && p['verified_at'] }
    end
    def self.find(id)
      products.find { |p| p['id']==id } || raise('Appliance model is not in the verified US catalog')
    end
    def self.snapshot(id)
      a=find(id).slice('id','brand','manufacturer','category','model','name','dimensions','depth_basis','cutout','appearance','product_url','spec_url','verified_at','panel_ready','automatic_cutout','source_asset_id','geometry_sha256').merge('schema_version'=>1)
      asset=ApplianceAssets.selection(id);a['asset']=asset if asset;a
    end
    def self.microwave_base?(d)
      a=d['appliance']||{}
      d['kind']=='microwave' && (a.dig('appearance','door')=='drawer' || a.dig('appearance','installation')=='under_counter')
    end
    def self.options(id)
      a=snapshot(id);dim=a['dimensions'];category=a['category']
      d={'kind'=>KINDS.fetch(category),'appliance'=>a,'appliance_finish'=>a.fetch('appearance',{}).fetch('finish','stainless')}.merge(dim)
      d['z']=case category;when 'wall_oven';28;when 'hood';66;when 'microwave';a.dig('appearance','installation')=='over_range' ? 54 : 36;else;0;end
      d['z']=34.5-d['height']-1 if microwave_base?(d)
      d['z']=36-d['height'] if category=='rangetop'
      if category=='cooktop'
        d.merge!('width'=>((dim['width']+2)/3.0).ceil*3.0,'height'=>34.5,'depth'=>[24,dim['depth']+3].max,'z'=>0)
      end
      d
    end
    def self.validate(d)
      return unless d['appliance']
      a=d['appliance'];raise 'Invalid appliance selection' unless a.is_a?(Hash) && a['schema_version']==1 && KINDS.key?(a['category'])
      %w[id brand manufacturer model name].each { |k| raise "Missing appliance #{k}" unless a[k].is_a?(String) && !a[k].empty? && a[k].length<=240 }
      dim=a['dimensions'];raise 'Missing appliance dimensions' unless dim.is_a?(Hash)
      ApplianceAssets.manifest(a) if a['asset']
      %w[width height depth].each { |k| raise "Invalid appliance #{k}" unless dim[k].is_a?(Numeric) && dim[k].finite? && dim[k]>0 && dim[k]<=120 }
      raise 'Appliance category does not match cabinet type' unless d['kind']==KINDS[a['category']]
      if d.key?('installation_depth')
        installation=Float(d['installation_depth'])
        raise 'Invalid microwave cabinet depth' unless microwave_base?(d) && installation.finite? && installation.between?(24,36)
        d['installation_depth']=installation
      end
      if a['category']=='cooktop'
        raise 'Cooktop must fit the base with 1 inch at either side' unless dim['width']<=d['width']-2
        raise 'Cooktop must fit the countertop depth' unless dim['depth']<=d['depth']-2
        return if a['automatic_cutout']==false
        raise 'Cooktop requires a recorded countertop cutout' unless a['cutout'].is_a?(Hash)
        %w[width depth].each { |k| raise 'Invalid cooktop cutout' unless a['cutout'][k].is_a?(Numeric) && a['cutout'][k]>0 && a['cutout'][k]<dim[k] }
      else
        raise 'Catalog appliance dimensions are fixed. Choose another model or detach from catalog.' unless %w[width height depth].all? { |k| expected=dim[k];expected+=d['installation_depth']-a.dig('appearance','cabinet_depth').to_f if k=='depth' && d['installation_depth'];(d[k]-expected).abs<0.0001 }
      end
    end
    def self.automatic_cooktop_cutout?(d);cooktop?(d) && d.dig('appliance','automatic_cutout')!=false;end
    def self.cooktop?(d);d.dig('appliance','category')=='cooktop';end
    # One set of local-inch boxes drives both native geometry and SVG projections.
    def self.parts(d)
      return [] unless d['appliance']
      baked=ApplianceAssets.parts(d);return baked if baked
      a=d['appliance'];w,h,dep=a['dimensions'].values_at('width','height','depth');y=-dep+0.8
      finish={'stainless'=>'#B8C0C4','black'=>'#303538','white'=>'#ECEDE9'}[d['appliance_finish']] || '#B8C0C4'
      out=[];add=lambda { |name,x,yy,z,ww,dd,hh,color| out<<{'name'=>name,'x'=>x,'y'=>yy,'z'=>z,'width'=>ww,'depth'=>dd,'height'=>hh,'color'=>color} if [ww,dd,hh].all? { |v| v>0 } }
      glass='#18262D';trim='#DCE1E2'
      zones=lambda do |x,yy,z,ww,dd|
        count=a.dig('appearance','burners') || 4
        positions=[[0.23,0.3],[0.77,0.3],[0.23,0.72],[0.77,0.72]]
        positions<<[0.5,0.5] if count==5
        positions=[[0.18,0.3],[0.5,0.3],[0.82,0.3],[0.18,0.72],[0.5,0.72],[0.82,0.72]] if count==6
        positions.each_with_index do |(px,py),index|
          radius=[ww*(count==6 ? 0.075 : 0.1),dd*0.14].min
          add.call("Cooking zone #{index+1}",x+ww*px-radius,yy+dd*py-radius,z,2*radius,2*radius,0.06,trim)
          out.last['shape']='cylinder'
        end
      end
      if cooktop?(d)
        x,y,right,back=cooktop_bounds(d);z=d['height']+1.5
        cx,cy,cr,cb=cooktop_bounds(d,true)
        add.call('Cooktop body',cx+0.0625,cy+0.0625,z-h,cr-cx-0.125,cb-cy-0.125,h,glass)
        add.call('Cooktop surface',x,y,z,w,dep,0.08,a.dig('appearance','cooktop')=='gas' ? finish : glass)
        zones.call(x,y,z+0.08,w,dep)
        return out
      end
      if a['category']=='hood'
        canopy=[h,5].min
        add.call('Hood canopy',0,-dep,0,w,dep,canopy,finish)
        add.call('Hood upper housing',w*0.27,-dep*0.7,canopy,w*0.46,dep*0.7,h-canopy,finish)
        return out
      end
      add.call('Appliance body',0,y+0.75,0,w,dep-1.55,h,finish)
      case a['category']
      when 'wall_oven','range','microwave'
        add.call('Front frame',0,y,0,w,0.75,h,finish)
        add.call('Door glass',w*0.08,y-0.01,h*0.08,w*0.84,0.03,h*0.68,glass)
        add.call('Control display',w*0.36,y-0.03,h*0.86,w*0.28,0.04,h*0.045,glass)
        add.call('Door handle',w*0.12,y-0.8,h*0.73,w*0.76,0.35,0.35,trim)
        if a.dig('appearance','controls')=='knobs'
          count=a['category']=='range' ? a.dig('appearance','burners') || 4 : 2
          count.times { |i| f=a['category']=='range' ? (i+1).to_f/(count+1) : [0.16,0.84][i];add.call("Control knob #{i+1}",w*f-0.55,y-0.4,h*0.85,1.1,0.4,1.1,a.dig('appearance','knob_color')=='red' ? '#AE242A' : trim) }
        end
        if a['category']=='range'
          add.call('Range cooktop',0,-dep,h-0.15,w,dep,0.09,glass)
          zones.call(0,-dep,h-0.06,w,dep)
        end
      when 'fridge'
        split=h*0.3;gap=0.125;grille=a.dig('appearance','grille') || 0;top=h-grille
        configuration=a.dig('appearance','configuration') || 'french_3door'
        if configuration=='side_by_side'
          split=0
          [gap,w*0.4+gap].each_with_index { |x,i| add.call("Refrigerator door #{i+1}",x,y,2,(i==0 ? w*0.4 : w*0.6)-2*gap,0.75,top-2,finish) }
        else
          if configuration=='french_4door'
            [gap,w/2+gap/2].each_with_index { |x,i| add.call("Freezer door #{i+1}",x,y,2,w/2-1.5*gap,0.75,split-2-gap,finish) }
          else
            add.call('Freezer drawer',gap,y,2,w-2*gap,0.75,split-2-gap,finish)
          end
          if configuration=='bottom_freezer_single'
            add.call('Refrigerator door',gap,y,split,w-2*gap,0.75,top-split-gap,finish)
          else
            [gap,w/2+gap/2].each_with_index { |x,i| add.call("Refrigerator door #{i+1}",x,y,split,w/2-1.5*gap,0.75,top-split-gap,finish) }
          end
        end
        if grille>0
          add.call('Refrigerator grille',0,y,top,w,0.75,grille,finish)
          6.times { |i| add.call("Grille slot #{i+1}",0.5,y-0.02,top+1+i*(grille-2)/6,w-1,0.03,0.2,glass) }
        end
        if a.dig('appearance','handles')!='pocket'
          handles=configuration=='bottom_freezer_single' ? [w*0.08] : configuration=='side_by_side' ? [w*0.4-1.4,w*0.4+1.1] : [w/2-1.4,w/2+1.1]
          handles.each_with_index { |x,i| add.call("Refrigerator handle #{i+1}",x,y-0.8,split+6,0.3,0.35,12,trim) }
          add.call('Freezer pull',w*0.2,y-0.8,split-2,w*0.6,0.35,0.3,trim) unless %w[side_by_side french_4door].include?(configuration)
        end
        add.call('Dispenser',w*0.15,y-0.03,h*0.52,w*0.2,0.04,h*0.14,glass) if a.dig('appearance','dispenser')
        add.call('InstaView glass',w*0.55,y-0.03,split+3,w*0.37,0.04,top-split-6,glass) if a.dig('appearance','instaview')
      when 'dishwasher'
        if a.dig('appearance','drawers')==2
          [2,h/2+0.0625].each_with_index do |z,i|
            add.call("DishDrawer #{i+1}",0,y,z,w,0.75,h/2-2,finish)
            add.call("DishDrawer handle #{i+1}",w*0.18,y-0.8,z+h/2-4,w*0.64,0.35,0.35,trim)
          end
        else
          add.call('Dishwasher front',0,y,2,w,0.75,h-2,finish)
          add.call('Dishwasher handle',w*0.18,y-0.8,h-4,w*0.64,0.35,0.35,trim) unless a.dig('appearance','handles')=='none'
        end
      when 'hood'
        add.call('Hood canopy',0,y,0,w,dep,[h,8].min,finish)
      end
      out
    end
    def self.cooktop_bounds(d,cutout=false)
      a=d['appliance'];dim=cutout ? a['cutout'] : a['dimensions']
      x=(d['width']-dim['width'])/2.0;y=-d['depth']+(d['depth']-dim['depth'])/2.0
      if cutout && dim.key?('front_offset')
        body=a['dimensions'];y=-d['depth']+(d['depth']-body['depth'])/2.0+dim['front_offset']
      end
      [x,y,x+dim['width'],y+dim['depth']]
    end
  end
end

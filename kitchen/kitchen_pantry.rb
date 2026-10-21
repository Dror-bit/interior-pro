# encoding: utf-8
module KitchenLab
  module Pantry
    USE_FITTED_DEFAULTS = true unless const_defined?(:USE_FITTED_DEFAULTS, false)
    def self.defaults(d)
      p = {'version'=>1,'drawer_height_basis'=>'section','top'=>'double','middle'=>'double','bottom'=>'combo_double','bottom_height'=>28.0,'middle_height'=>30.0,'drawers'=>3}
      if USE_FITTED_DEFAULTS
        # Replacing a shorter cabinet preserves its height. Fit NEW default
        # sections to that space; never rewrite explicit/saved pantry settings.
        usable = d.fetch('height',84.0).to_f - d.fetch('toe_height',4.0).to_f - 0.5
        p['bottom_height'] = [[usable-16.0,14.0].max,28.0].min
        p['middle_height'] = [[usable-p['bottom_height']-8.0,8.0].max,30.0].min
      end
      p
    end
    def self.rows(d)
      p=d['pantry'];return nil unless d['kind']=='tall' && p
      raise 'Invalid pantry settings' unless p.is_a?(Hash) && p['version']==1
      raise 'Invalid upper section' unless %w[single double lift].include?(p['top'])
      raise 'Invalid middle section' unless %w[single double microwave wall_oven].include?(p['middle'])
      raise 'Invalid lower section' unless %w[combo_single combo_double drawers].include?(p['bottom'])
      %w[top middle bottom].each { |zone| raise 'Choose left or right door hinges' unless %w[left right].include?(p.fetch(zone+'_hinge','left')) }
      lower=Float(p['bottom_height']);middle=Float(p['middle_height'])
      upper=d['height']-d.fetch('toe_height',4)-0.5-lower-middle
      raise 'Each pantry section must be at least 8 inches high' unless [lower,middle,upper].all? { |v| v.finite? && v>=8 }
      out=[{'kind'=>'doors','doors'=>p['top']=='double' ? 2 : 1,'height'=>upper,'zone'=>'top','hinge'=>p.fetch('top_hinge','left'),'opening'=>p['top']=='lift' ? 'lift' : 'swing'}]
      if %w[microwave wall_oven].include?(p['middle'])
        a=p['appliance'];raise 'Choose a compatible appliance for the middle section' unless a && fits?(a,d,middle,p['middle'])
        out<<{'kind'=>'appliance','height'=>middle,'width'=>a['dimensions']['width'],'device'=>a['category'],'pantry_appliance'=>a,'zone'=>'middle'}
      else
        out<<{'kind'=>'doors','doors'=>p['middle']=='double' ? 2 : 1,'height'=>middle,'zone'=>'middle','hinge'=>p.fetch('middle_hinge','left')}
      end
      if p['bottom']=='drawers'
        n=Integer(p['drawers']);raise 'Choose 1 to 5 lower drawers' unless n.between?(1,5)
        allocated=p['drawer_height_basis']=='section'
        units=(lower*8).round
        equal=Array.new(n) { |i| (units/n+(i<units%n ? 1 : 0))/8.0 }
        heights=p['drawer_heights'] || (allocated ? equal : Array.new(n,(lower-0.125*(n-1))/n))
        raise 'Provide one height for each lower drawer' unless heights.is_a?(Array) && heights.length==n
        heights=heights.map { |v| Float(v) }
        raise 'Lower drawers must be at least 3 inches high' unless heights.all? { |v| v.finite? && v>=3 }
        if allocated
          raise 'Use 1/8 inch increments for drawer heights' unless heights.all? { |v| (v*8-(v*8).round).abs<0.0001 }
          raise 'Drawer heights must add up to the bottom section height' unless (heights.sum-lower).abs<0.005
        else
          raise 'Drawer heights plus reveals must fill the bottom section' unless (heights.sum+0.125*(n-1)-lower).abs<0.005
        end
        heights.each_with_index do |height,i|
          visible=height-(allocated && i<n-1 ? 0.125 : 0)
          raise 'Drawer front must be at least 3 inches high' if visible<3
          row={'kind'=>'drawer','height'=>visible,'zone'=>'bottom'}
          row['allocated_height']=height if allocated
          out<<row
        end
      else
        raise 'Lower section needs 14 inches for a drawer and doors' if lower<14
        out<<{'kind'=>'drawer','height'=>5.875,'zone'=>'bottom'}
        out<<{'kind'=>'doors','doors'=>p['bottom']=='combo_double' ? 2 : 1,'height'=>lower-6,'zone'=>'bottom','hinge'=>p.fetch('bottom_hinge','left')}
      end
      out
    end
    def self.fits?(a,d,height,category)
      return false unless a.is_a?(Hash) && a['category']==category && %w[microwave wall_oven].include?(category)
      return false if a.dig('appearance','door')=='drawer' || %w[over_range under_counter].include?(a.dig('appearance','installation'))
      dim=a['dimensions'];cut=a['cutout']
      return false unless [dim,cut].all? { |v| v.is_a?(Hash) && %w[width height depth].all? { |k| v[k].is_a?(Numeric) && v[k].finite? && v[k]>0 } }
      cut['width']<=d['width']-1.5+0.0001 && cut['depth']<=d['depth']-0.5+0.0001 && cut['height']<=height && dim['width']<=d['width']-0.25+0.0001 && dim['height']<=height
    end
    def self.device_data(a)
      a['dimensions'].merge('appliance'=>a,'kind'=>a['category'],'appliance_finish'=>a.dig('appearance','finish') || 'stainless')
    end
    def self.validate!(d)
      return unless d['pantry']
      raise 'Three sections require a pantry cabinet' unless d['kind']=='tall'
      rows(d)
      a=d['pantry']['appliance']
      ApplianceCatalog.validate(device_data(a)) if a && %w[microwave wall_oven].include?(d['pantry']['middle'])
    end
    def self.choices
      ApplianceCatalog.products.filter_map do |p|
        next unless %w[microwave wall_oven].include?(p['category']) && p['cutout']
        a=ApplianceCatalog.snapshot(p['id'])
        next unless fits?(a,{'width'=>60,'depth'=>36},90,a['category'])
        {'snapshot'=>a,'parts'=>ApplianceCatalog.parts(device_data(a)),'product'=>p}
      end
    end
    def self.front_data(d,row)
      return d unless row['opening']=='lift'
      d.merge('handle_position'=>'bottom','_handle_model_key'=>'door_handle_model')
    end
    def self.build_device(e,row,z,d,finish)
      a=row['pantry_appliance'];dim=a['dimensions'];cut=a['cutout']
      x=(d['width']-dim['width'])/2.0
      bottom=z+(row['height']-dim['height'])/2.0
      group=e.add_group;group.name="Pantry #{a['model']}"
      group.set_attribute('KitchenLab','owner_id',d['id'])
      group.set_attribute('KitchenLab','appliance_snapshot',JSON.generate(a))
      KitchenLab.build_catalog_appliance(group.entities,device_data(a))
      group.transformation=Geom::Transformation.translation([x,-d['depth']+cut['depth'],bottom])
      # Frame the manufacturer opening; never stretch the approved appliance.
      opening_x=(d['width']-cut['width'])/2.0
      opening_z=bottom+(dim['height']-cut['height'])/2.0
      KitchenLab.box(e,'Pantry appliance left filler',0.75,-d['depth'],z,opening_x-0.75,0.75,row['height'],finish) if opening_x>0.75
      KitchenLab.box(e,'Pantry appliance right filler',d['width']-opening_x,-d['depth'],z,opening_x-0.75,0.75,row['height'],finish) if opening_x>0.75
      [[z,opening_z-z],[opening_z+cut['height'],z+row['height']-opening_z-cut['height']]].each do |zz,hh|
        KitchenLab.box(e,'Pantry appliance horizontal filler',opening_x,-d['depth'],zz,cut['width'],0.75,hh,finish) if hh>0.001
      end
      KitchenLab.box(e,'Pantry appliance support',0.75,-d['depth']+0.75,bottom-0.75,d['width']-1.5,d['depth']-1.25,0.75,finish)
    end
  end
end

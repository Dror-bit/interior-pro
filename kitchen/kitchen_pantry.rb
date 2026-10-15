# encoding: utf-8
module KitchenLab
  module Pantry
    def self.defaults(d)
      {'version'=>1,'top'=>'double','middle'=>'double','bottom'=>'combo_double','bottom_height'=>28.0,'middle_height'=>30.0,'drawers'=>3}
    end
    def self.rows(d)
      p=d['pantry'];return nil unless d['kind']=='tall' && p
      raise 'Invalid pantry settings' unless p.is_a?(Hash) && p['version']==1
      raise 'Invalid upper section' unless %w[single double lift].include?(p['top'])
      raise 'Invalid middle section' unless %w[single double microwave wall_oven].include?(p['middle'])
      raise 'Invalid lower section' unless %w[combo_single combo_double drawers].include?(p['bottom'])
      lower=Float(p['bottom_height']);middle=Float(p['middle_height'])
      upper=d['height']-d.fetch('toe_height',4)-0.5-lower-middle
      raise 'Each pantry section must be at least 8 inches high' unless [lower,middle,upper].all? { |v| v.finite? && v>=8 }
      out=[{'kind'=>'doors','doors'=>p['top']=='double' ? 2 : 1,'height'=>upper,'zone'=>'top','opening'=>p['top']=='lift' ? 'lift' : 'swing'}]
      if %w[microwave wall_oven].include?(p['middle'])
        a=p['appliance'];raise 'Choose a compatible appliance for the middle section' unless a && fits?(a,d,middle,p['middle'])
        out<<{'kind'=>'appliance','height'=>middle,'width'=>a['dimensions']['width'],'device'=>a['category'],'pantry_appliance'=>a,'zone'=>'middle'}
      else
        out<<{'kind'=>'doors','doors'=>p['middle']=='double' ? 2 : 1,'height'=>middle,'zone'=>'middle'}
      end
      if p['bottom']=='drawers'
        n=Integer(p['drawers']);raise 'Choose 1 to 5 lower drawers' unless n.between?(1,5)
        heights=p['drawer_heights'] || Array.new(n,(lower-0.125*(n-1))/n)
        raise 'Provide one height for each lower drawer' unless heights.is_a?(Array) && heights.length==n
        heights=heights.map { |v| Float(v) }
        raise 'Lower drawers must be at least 3 inches high' unless heights.all? { |v| v.finite? && v>=3 }
        raise 'Drawer heights plus reveals must fill the bottom section' unless (heights.sum+0.125*(n-1)-lower).abs<0.005
        heights.each { |height| out<<{'kind'=>'drawer','height'=>height,'zone'=>'bottom'} }
      else
        raise 'Lower section needs 14 inches for a drawer and doors' if lower<14
        out<<{'kind'=>'drawer','height'=>5.875,'zone'=>'bottom'}
        out<<{'kind'=>'doors','doors'=>p['bottom']=='combo_double' ? 2 : 1,'height'=>lower-6,'zone'=>'bottom'}
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

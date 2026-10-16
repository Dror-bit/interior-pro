require 'json'
require 'digest'
module KitchenLab
  module Accessories
    def self.catalog;@catalog ||= JSON.parse(File.read(File.join(__dir__,'accessory_catalog.json')));end
    def self.normalize(items,d)
      raise 'Invalid accessory list' unless items.is_a?(Array) && items.length<=12
      seen=[]
      items.map do |raw|
        a=JSON.parse(JSON.generate(raw));id=a['id']
        raise 'Invalid accessory ID' unless id.is_a?(String)&&id.match?(/\A[a-zA-Z0-9-]{1,64}\z/)&&!seen.include?(id)
        seen<<id
        p=a['snapshot'] || catalog['products'].find{|v|v['id']==a['product_id']}
        raise 'Unknown faucet model' unless p && %w[main prep beverage pot].include?(p['role']) && p['id']==a['product_id']
        raise 'Place a deck faucet on a sink cabinet' unless p['role']=='pot' || d['kind']=='sink'
        p=JSON.parse(JSON.generate(p));palette=a['finish_palette'] || catalog['finish_palette']
        finish=a['finish_id']||p['default_finish'];variant=p['finish_variants'].find{|v|v['finish_id']==finish}
        raise 'Finish is unavailable for this faucet' unless variant
        cooking=d['kind']=='oven' || d.dig('appliance','category')=='cooktop'
        if p['role']=='pot'
          raise 'Select a range or cooktop for the pot filler.' unless cooking
          raise 'Pot filler requires a wall behind the cooking area.' if d['wall']=='I' || (d['house_placement'] && !d['house_placement']['wall_id'])
        end
        location=p['role']=='pot' ? 'cooktop' : a.fetch('location','main_sink')
        raise 'Invalid sink placement' unless %w[main_sink island_sink secondary_sink cooktop].include?(location) && (p['role']=='pot' || location!='cooktop')
        surface=d['height']+(d.dig('appliance','category')=='cooktop' ? KitchenLab.settings.fetch('countertop_thickness',1.5) : 0)
        anchor=a.fetch('anchor',[d['width']/2.0,p['mount']=='wall' ? 0 : -1.5,p['mount']=='wall' ? surface+18 : d['height']+KitchenLab.settings.fetch('countertop_thickness',1.5)])
        raise 'Invalid faucet anchor' unless anchor.is_a?(Array)&&anchor.size==3&&anchor.all?{|v|v.is_a?(Numeric)&&v.finite?}
        raise 'Faucet anchor outside cabinet' unless anchor[0].between?(0,d['width'])&&anchor[1].between?(-d['depth'],0)&&anchor[2].between?(0,120)
        angle=a.fetch('angle',0);raise 'Invalid faucet angle' unless angle.is_a?(Numeric)&&angle.finite?&&angle.between?(-360,360)
        if p['role']=='pot'
          raise 'Pot filler wall connection must stay at the back wall.' unless anchor[1].abs<0.001 && angle.abs<0.001
          raise 'Pot filler must be above the cooking surface.' unless anchor[2]+p['measured_mesh_bounds_in'][0][2]>surface
        end
        ro=a.fetch('filter_ro',true);raise 'Invalid filter selection' unless [true,false].include?(ro)
        connection=p['role']=='beverage' ? (ro ? 'filter_ro' : 'cold_unfiltered') : p['role']=='pot' ? 'cold_only' : 'hot_and_cold'
        {'id'=>id,'product_id'=>p['id'],'sku'=>variant['product_sku'],'handle_sku'=>variant['handle_sku'],'snapshot'=>p,'finish_palette'=>palette,
         'finish_id'=>finish,'material_mapping'=>variant.slice('body_material','accent_material'),'geometry_revision'=>p['geometry_revision'],'geometry_sha256'=>p['skp_sha256'],
         'usage'=>p['role'],'water_connection'=>connection,'filter_ro'=>p['role']=='beverage' ? ro : false,'location'=>location,'anchor'=>anchor,'angle'=>angle}
      end
    end
    def self.color_material(model,code,palette,accent=false)
      info=palette.fetch(code);rgb=accent ? info.fetch('accent_rgb',info['rgb']) : info['rgb'];name='Kitchen faucet '+code+(accent ? ' accent' : ' body')+' '+Digest::SHA256.hexdigest(JSON.generate(rgb))[0,12]
      material=model.materials[name]||model.materials.add(name);material.color=Sketchup::Color.new(*rgb);material
    end
    def self.definition(model,a)
      p=a['snapshot'];relative=p['skp_path'];raise 'Invalid faucet path' unless relative.match?(%r{\Aassets/accessories/[A-Za-z0-9-]+\.skp\z})
      path=File.join(__dir__,relative);raise 'Saved faucet geometry changed' unless Digest::SHA256.file(path).hexdigest==a['geometry_sha256']
      key=Digest::SHA256.hexdigest(JSON.generate([a['geometry_sha256'],a['finish_id'],a['material_mapping'],a['finish_palette']]))
      cached=model.definitions.find{|v|v.get_attribute('KitchenAccessory','variant')==key};return cached if cached
      source=model.definitions.find{|v|v.get_attribute('KitchenAccessory','source')==a['geometry_sha256']}
      unless source;source=model.definitions.load(path);source.set_attribute('KitchenAccessory','source',a['geometry_sha256']);end
      holder=model.entities.add_group;instance=holder.entities.add_instance(source,Geom::Transformation.new);instance.make_unique;definition=instance.definition
      roles=p['finish_material_roles']||{};mapping=a['material_mapping'];palette=a['finish_palette'];memo={}
      recolor=lambda do |entities,fixed|
        entities.each do |e|
          fixed_here=fixed || Array(roles['fixed_black_instances']).any?{|name|e.respond_to?(:name)&&e.name.include?(name)}
          if e.respond_to?(:material) && e.material && !fixed_here
            name=e.material.display_name
            role=%w[fixed accent body].find{|r|Array(roles[r]).any?{|v|name.include?(v)}}
            if %w[accent body].include?(role)
              code=mapping[role+'_material']||a['finish_id'];mat=color_material(model,code,palette,role=='accent')
              e.material=mat;e.back_material=mat if e.is_a?(Sketchup::Face)
            end
          end
          if e.is_a?(Sketchup::ComponentInstance)
            unless fixed_here
              old=e.definition
              if memo[old];e.definition=memo[old]
              else;e.make_unique;memo[old]=e.definition;recolor.call(e.definition.entities,false);end
            end
          elsif e.is_a?(Sketchup::Group)
            e.make_unique unless fixed_here;recolor.call(e.entities,fixed_here)
          end
        end
      end
      recolor.call(definition.entities,false);definition.set_attribute('KitchenAccessory','variant',key);holder.erase!;definition
    end
    def self.build(entities,d)
      Array(d['accessories']).each do |a|
        definition=definition(entities.model,a)
        transform=Geom::Transformation.translation(a['anchor'])*Geom::Transformation.rotation([0,0,0],[0,0,1],a['angle']*Math::PI/180)
        instance=entities.add_instance(definition,transform);instance.name=a['sku']+' / '+a['usage'];instance.set_attribute('KitchenAccessory','snapshot',JSON.generate(a))
      end
    end
  end
  module AccessoryHooks
    def validate(raw,options=settings)
      d=super
      if raw.key?('accessories')
        d['accessories']=Accessories.normalize(raw['accessories'],d)
        d['sink']=d['sink'].merge('faucet'=>'none') if d['sink'] && !d['accessories'].empty?
      end
      d
    end
    def build(d)
      group=super;Accessories.build(group.entities,d) unless Array(d['accessories']).empty?;group
    end
  end
  singleton_class.prepend(AccessoryHooks) unless singleton_class.ancestors.include?(AccessoryHooks)
end

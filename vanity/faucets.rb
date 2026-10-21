require 'json'
module InteriorPro
  module Vanity
    remove_const(:USE_FAUCET_GALLERY) if const_defined?(:USE_FAUCET_GALLERY,false)
    USE_FAUCET_GALLERY=true
    module Faucets
      module_function
      def catalog
        @catalog ||= JSON.parse(File.read(File.join(__dir__,'faucets','catalog.json'))).to_h { |a|[a['id'],a] }
      end
      def colors
        {'matte_black'=>'#25272A','brushed_nickel'=>'#B8B6AF','satin_brass'=>'#C4A568'}
      end
      def choices(c)
        return [] unless c['product_id']=='vanity'
        c['basin_faucets'] || Array.new(c['basins']) { {'id'=>c.fetch('faucet_id','none'),'finish'=>Surfaces.settings(c)['faucet_finish']} }
      end
      def for_basin(c,i)
        a=choices(c).fetch(i)
        c.merge('basin_faucets'=>nil,'faucet_id'=>a['id'],'surfaces'=>Surfaces.settings(c).merge('faucet_finish'=>a['finish']))
      end
      def selected(c)
        USE_FAUCET_GALLERY && c['product_id']=='vanity' && choices(c).any? { |a|a['id']!='none' }
      end
      def mounting_y(c)
        s=Surfaces.settings(c);a=catalog.fetch(c['faucet_id'])
        # Place the base between the actual opening and backsplash; front points -Y.
        rear=s['backsplash_height']>0 ? -s['countertop_thickness'] : 0
        rear-a['bounds'][1][1]-0.25
      end
      def validate(c)
        list=choices(c)
        raise ArgumentError,'בחר ברז לכל כיור' unless list.is_a?(Array) && list.length==c['basins']
        list.each_with_index do |a,i|
          raise ArgumentError,'גימור ברז לא תקין' unless a.is_a?(Hash) && %w[matte_black brushed_nickel satin_brass chrome brass black].include?(a['finish'])
          validate_one(for_basin(c,i),Surfaces.centers(c)[i])
        end
      end
      def validate_one(c,center)
        id=c.fetch('faucet_id','none')
        raise ArgumentError,'ברז לא מוכר' unless id=='none' || catalog.key?(id)
        return unless selected(c)
        raise ArgumentError,'נדרש קאונטרטופ להצבת ברז' unless c.key?('surfaces')
        s=Surfaces.settings(c);a=catalog.fetch(id);y=mounting_y(c)
        # Entire base (not the overhanging spout) needs solid counter behind basin.
        base=a['bounds'][1][1]
        raise ArgumentError,'אין מספיק מקום לברז מאחורי הכיור; הגדל עומק ארון או הקטן כיור/באקספלש' if y-base < -c['depth']/2+s['sink_depth']/2+0.15
        raise ArgumentError,'פיית הברז אינה מעל הכיור; התאם עומק ארון או כיור' unless (y-a['reach']).between?(-c['depth']/2-s['sink_depth']/2+0.25,-c['depth']/2+s['sink_depth']/2-0.25)
        [center].each do |x|
          raise ArgumentError,'הברז רחב מדי לארון' if x+a['bounds'][0][0]<0.25 || x+a['bounds'][1][0]>c['width']-0.25
        end
      end
      def revision(id)
        %w[196.1000 196.2000 240.2000 559LF-MPU 3536-MPU-DST].include?(id) ? 3 : 2
      end
      def find(model,id)
        model.definitions.find { |d|d.get_attribute('InteriorPro::VanityAssets','faucet')==id && d.get_attribute('InteriorPro::VanityAssets','faucet_revision')==revision(id) }
      end
      def definition(model,id,dark)
        found=find(model,id);return found if found
        catalog.fetch(id)
        before=model.materials.to_a
        definition=model.definitions.load(File.join(__dir__,'faucets',id+'.skp'))
        if defined?(InteriorPro::MaterialIds)
          (model.materials.to_a-before).each { |mat|InteriorPro::MaterialIds.ensure_id!(mat,model) }
        end
        definition.set_attribute('InteriorPro::VanityAssets','faucet',id)
        definition.set_attribute('InteriorPro::VanityAssets','faucet_revision',revision(id))
        definition
      end
      def build(entities,c,model,material)
        return unless USE_FAUCET_GALLERY
        Surfaces.centers(c).each_with_index do |x,i|
          one=for_basin(c,i);id=one['faucet_id'];next if id=='none'
          s=Surfaces.settings(one)
          instance=entities.add_instance(definition(model,id,material.call('black')),Geom::Transformation.translation([x,mounting_y(one),c['height']+s['countertop_thickness']]))
          instance.name="Vanity faucet / #{catalog.fetch(id)['label']}"
          instance.material=material.call(s['faucet_finish'])
          instance.set_attribute('InteriorPro::VanityAssets','faucet_finish',s['faucet_finish'])
        end
      end
    end
  end
end

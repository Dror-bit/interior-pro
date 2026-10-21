require 'json'
module InteriorPro
  module Vanity
    remove_const(:USE_ICERA_MUSE) if const_defined?(:USE_ICERA_MUSE,false)
    USE_ICERA_MUSE=true
    module MuseSink
      module_function
      def asset
        @asset ||= JSON.parse(File.read(File.join(__dir__,'sinks','icera_muse.json')))
      end
      def selected(s)
        USE_ICERA_MUSE && s['sink_shape']=='icera_muse'
      end
      def defaults
        {'sink_shape'=>'icera_muse','sink_width'=>18.125,'sink_depth'=>12.25,'sink_height'=>7.875,'sink_color'=>'white'}
      end
      def find(model)
        model.definitions.find { |d|d.get_attribute('InteriorPro::VanityAssets','sink')=='icera_muse_v1' }
      end
      def definition(model)
        found=find(model);return found if found
        before=model.materials.to_a
        definition=model.definitions.load(File.join(__dir__,'sinks','icera_muse.skp'))
        definition.set_attribute('InteriorPro::VanityAssets','sink','icera_muse_v1')
        if defined?(InteriorPro::MaterialIds)
          (model.materials.to_a-before).each { |mat|InteriorPro::MaterialIds.ensure_id!(mat,model) }
        end
        definition
      end
      def opening
        asset.fetch('opening_points')
      end
      # Intersect a ray with the actual asset polygon. Countertop and basin share
      # the exact same edge, including extra vertices needed at countertop corners.
      def outline(angle)
        dx=Math.cos(angle);dy=Math.sin(angle)
        opening.each_with_index do |a,i|
          b=opening[(i+1)%opening.length];ex=b[0]-a[0];ey=b[1]-a[1]
          den=dx*ey-dy*ex;next if den.abs<1e-12
          t=(a[0]*ey-a[1]*ex)/den;u=(a[0]*dy-a[1]*dx)/den
          return [dx*t,dy*t] if t>=0 && u>=-1e-9 && u<=1+1e-9
        end
        raise 'Muse opening ray did not intersect'
      end
      def build(entities,cx,cy,h,ceramic)
        instance=entities.add_instance(definition(entities.model),Geom::Transformation.translation([cx,cy,h]))
        instance.name='ICERA Muse Medium / L-2410.01'
        instance.material=ceramic
        instance
      end
    end
  end
end

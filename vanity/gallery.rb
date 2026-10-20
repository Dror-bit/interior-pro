require 'fileutils'
require 'securerandom'
require 'json'
module InteriorPro
  module Vanity
    class Gallery
      def initialize(root=File.join(__dir__,'gallery'))
        @root=root
      end
      def entries
        Dir.glob(File.join(@root,'*.json')).sort.map { |p|JSON.parse(File.read(p)) }
      end
      def entry(id)
        Cabinetry.identifier!(id)
        entries.find { |e|e['id']==id } || (raise ArgumentError,'Gallery item missing')
      end
      def definition(model,id)
        entry(id)
        model.definitions.load(File.join(@root,"#{id}.skp")) || (raise 'Cannot load gallery cabinet')
      end
      # A local-axis snapshot, never explode, transform or restamp the source.
      # Imported assets are fixed geometry; parametric edits apply to generated products.
      def capture(model,selection,name)
        raise ArgumentError,'Select one group or component' unless selection.length==1
        source=selection.first
        raise ArgumentError,'Select one group or component' unless source.is_a?(Sketchup::Group) || source.is_a?(Sketchup::ComponentInstance)
        raise ArgumentError,'Enter a name' unless name.is_a?(String) && name.strip.length.between?(1,80)
        b=source.definition.bounds
        dims=[b.width.to_f,b.depth.to_f,b.height.to_f]
        raise ArgumentError,'Empty cabinet geometry' unless dims.all? { |v|v>0.001 }
        raise ArgumentError,'Use an unscaled source; rotation is supported' unless [source.transformation.xaxis,source.transformation.yaxis,source.transformation.zaxis].all? { |v|(v.length-1).abs<1e-6 }
        FileUtils.mkdir_p(@root);id="cab-#{SecureRandom.hex(8)}"
        path=File.join(@root,"#{id}.skp")
        begin
          raise 'Cabinet export failed' unless source.definition.save_as(path)
          info={'id'=>id,'name'=>name.strip,'dimensions'=>dims,'min'=>b.min.to_a.map(&:to_f),
                'max'=>b.max.to_a.map(&:to_f),'units'=>'inches','parametric'=>false}
          File.write(File.join(@root,"#{id}.json"),JSON.pretty_generate(info))
          info
        rescue Exception
          File.delete(path) if File.exist?(path)
          raise
        end
      end
    end
  end
end

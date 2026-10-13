require 'json'
require 'digest'
module KitchenLab
  module SinkCatalog
    @products=nil
    def self.products
      @products ||= JSON.parse(File.read(File.join(__dir__,'sink_catalog.json')))
    end
    def self.include?(id); products.any? { |p| p['id']==id }; end
    def self.find(id); products.find { |p| p['id']==id } || raise('Unknown sink model'); end
    def self.options(id)
      p=find(id)
      {'kind'=>'sink','width'=>p['cabinet_width'],'depth'=>p['cabinet_depth'],
       'sink'=>p['spec'].merge('product_id'=>id).merge(p['skp_path'] ? {'catalog_snapshot'=>JSON.parse(JSON.generate(p)),'automatic_cutout_available'=>false} : {})}
    end
    def self.record(d)
      snapshot=d.dig('sink','catalog_snapshot')
      snapshot || find(d['sink']['product_id'])
    end
    def self.apron?(d); d.dig('sink','product_id')=='kohler-k-6489'; end
    def self.front_height(d); apron?(d) ? d['height']-8.8125-0.125 : d['height']; end
    def self.build(entities,d)
      p=record(d)
      if p['skp_path']
        raise 'Invalid sink asset path' unless p['skp_path'].match?(%r{\Aassets/appliances/prep-sinks/K-(5287|33152)\.skp\z})
        path=File.join(__dir__,p['skp_path'])
        raise 'Saved sink geometry changed' unless Digest::SHA256.file(path).hexdigest==p['geometry_sha256']
        model=entities.model
        definition=model.definitions.find{|v|v.get_attribute('KitchenSink','sha256')==p['geometry_sha256']}
        unless definition
          definition=model.definitions.load(path);definition.set_attribute('KitchenSink','sha256',p['geometry_sha256'])
        end
        x,_,_,back=Sink.bounds(d)
        instance=entities.add_instance(definition,Geom::Transformation.translation([x,back,d['height']]))
        instance.name='Kohler '+p['model'];return instance
      end
      path=File.join(__dir__,p.fetch('mesh_path'))
      data=JSON.parse(File.read(path));model=entities.model
      key='Kitchen sink '+p['model']+' v1'
      definition=model.definitions[key]
      unless definition
        definition=model.definitions.add(key)
        mats=data.fetch('materials').to_h do |name,info|
          mat=KitchenLab.material('Kohler '+name,info['rgb']);[name,mat]
        end
        parts=data.fetch('definitions').each_with_index.map do |part,index|
          sub=model.definitions.add(key+' part '+index.to_s)
          mesh=Geom::PolygonMesh.new
          ids=part['vertices'].map { |v| mesh.add_point(v.map { |n| n*1000.0 }) }
          part['faces'].each { |face| mesh.add_polygon(face.map { |i| ids.fetch(i) }) }
          mat=mats.fetch(part['material']);sub.entities.fill_from_mesh(mesh,true,0,mat,mat)
          raise 'Empty sink mesh' if sub.entities.grep(Sketchup::Face).empty?
          sub.entities.grep(Sketchup::Edge).each do |edge|
            if edge.faces.size==2 && edge.faces[0].normal.dot(edge.faces[1].normal)>Math.cos(35*Math::PI/180)
              edge.soft=true;edge.smooth=true
            end
          end
          sub
        end
        data.fetch('instances').each do |item|
          instance=definition.entities.add_instance(parts.fetch(item['definition']),Geom::Transformation.translation(item['origin'])*Geom::Transformation.scaling(0.001))
          instance.name=item['name']
        end
      end
      x,_,_,back=Sink.bounds(d)
      # Undermount rim sits against the underside of the 1.5 inch countertop.
      top=d['height']
      instance=entities.add_instance(definition,Geom::Transformation.translation([x,back,top]));instance.name='Kohler '+p['model']
      instance
    end
  end
end

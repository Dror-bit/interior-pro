require 'digest'
module KitchenLab
  module ApplianceAssets
    ROOT=File.join(__dir__,'assets','appliances','blender') unless const_defined?(:ROOT,false)
    def self.base(id)
      raise 'Invalid Blender asset ID' unless id.is_a?(String) && id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      File.join(ROOT,id)
    end
    def self.selection(id)
      file=base(id)+'.asset.json'
      begin;raw=File.read(file);rescue Errno::ENOENT;return nil;end
      a=JSON.parse(raw);return nil unless [1,2].include?(a['version']) && a['parts'] && (a['version']==2 ? a['skp_sha256'] : a['obj_sha256'])
      {'id'=>id,'version'=>a['version'],'manifest_sha256'=>Digest::SHA256.file(file).hexdigest}
    end
    def self.manifest(a)
      asset=a['asset'];return nil unless asset
      raise 'Unsupported Blender asset version' unless [1,2].include?(asset['version']) && asset['id']==a['id']
      file=base(asset['id'])+'.asset.json'
      raise 'Saved Blender asset changed or missing' unless Digest::SHA256.file(file).hexdigest==asset['manifest_sha256']
      data=JSON.parse(File.read(file));prefix=base(asset['id'])
      raise 'Blender dimensions differ from selection' unless data['dimensions']==a['dimensions']
      raise 'Asset schema changed' unless data['version']==asset['version']
      files=data['version']==2 ? {'.skp'=>'skp_sha256'} : {'.obj'=>'obj_sha256','.materials.json'=>'materials_sha256'}
      files.each do |ext,key|
        raise 'Blender asset content changed' unless Digest::SHA256.file(prefix+ext).hexdigest==data[key]
      end
      data
    end
    def self.offset(d)
      return [0,0,0] unless d.dig('appliance','category')=='cooktop'
      dim=d['appliance']['dimensions'];x,y,=ApplianceCatalog.cooktop_bounds(d)
      deck=manifest(d['appliance'])&.fetch('mounting_deck_z',nil)
      [x,y+dim['depth'],d['height']+1.5-(deck || dim['height'])]
    end
    def self.parts(d)
      data=manifest(d['appliance']);return nil unless data
      ox,oy,oz=offset(d)
      data['parts'].map { |p| p.merge('x'=>p['x']+ox,'y'=>p['y']+oy,'z'=>p['z']+oz) }
    end
    def self.build(entities,d)
      data=manifest(d['appliance']);return false unless data
      if data['version']==2
        model=entities.model
        definition=model.definitions.find { |v| v.get_attribute('KitchenLabAsset','sha256')==data['skp_sha256'] }
        unless definition
          definition=model.definitions.load(base(d['appliance']['id'])+'.skp')
          definition.set_attribute('KitchenLabAsset','sha256',data['skp_sha256'])
        end
        origin=data.fetch('origin');offset=offset(d)
        transform=Geom::Transformation.translation(3.times.map { |i| offset[i]-origin[i] })
        instance=entities.add_instance(definition,transform)
        instance.name=d['appliance']['model']
        instance.set_attribute('KitchenLab','blender_asset',d['appliance']['id'])
        return true
      end
      # Each Blender object remains a separate closed mesh. Fill PolygonMesh in
      # one call per part to preserve small bevel triangles and avoid face merging.
      vertices=[];objects=[];current=nil
      File.foreach(base(d['appliance']['id'])+'.obj') do |line|
        f=line.split;next if f.empty?
        case f.first
        when 'o';current={'name'=>f.drop(1).join(' ').tr('_',' '),'faces'=>[]};objects<<current
        when 'v';vertices<<f.drop(1).map(&:to_f)
        when 'usemtl';current['material']=f[1]
        when 'f';current['faces']<<f.drop(1).map { |v| Integer(v)-1 }
        end
      end
      colors=JSON.parse(File.read(base(d['appliance']['id'])+'.materials.json'))
      ox,oy,oz=offset(d)
      objects.each do |obj|
        mesh=Geom::PolygonMesh.new;indices={}
        obj['faces'].each do |face|
          points=face.map do |index|
            indices[index] ||= begin
              # SketchUp drops tiny bevel faces at ordinary inch scale. Build
              # enlarged, then scale the closed group back to exact dimensions.
              x,y,z=vertices.fetch(index);mesh.add_point([(x+ox)*1000,(y+oy)*1000,(z+oz)*1000])
            end
          end
          mesh.add_polygon(points)
        end
        # Linear Blender colors -> sRGB SketchUp colors.
        rgb=colors.fetch(obj['material']).map { |v| ((v<=0.0031308 ? v*12.92 : 1.055*v**(1.0/2.4)-0.055)*255).round.clamp(0,255) }
        mat=KitchenLab.material("Blender #{obj['material']}",Sketchup::Color.new(*rgb))
        group=entities.add_group;group.name=obj['name'];group.material=mat
        group.entities.fill_from_mesh(mesh,true,Geom::PolygonMesh::AUTO_SOFTEN|Geom::PolygonMesh::SMOOTH_SOFT_EDGES,mat,mat)
        group.transform!(Geom::Transformation.scaling(0.001))
        group.set_attribute('KitchenLab','blender_asset',d['appliance']['id'])
      end
      true
    end
  end
end

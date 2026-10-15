require 'json'
require 'digest'
module KitchenLab
  module HandleCatalog
    def self.products
      @products ||= JSON.parse(File.read(File.join(__dir__,'handle_catalog.json')))
    end
    def self.find(id)
      original=products.find { |p|p['asset_id']==id };return original if original
      base,size=id.to_s.split('@ctc=',2)
      product=products.find { |p|p['asset_id']==base }
      raise 'Handle is not in the approved catalog' unless product && size && product['ctc'] && product['family']!='Cup Pull'
      ctc=Float(size)
      raise 'Cabinet pull size must be 3–8 inches' unless ctc.finite? && ctc.between?(3,8)
      p=JSON.parse(JSON.generate(product));delta=ctc-p['ctc'];p['source_asset_id']=base;p['asset_id']=id;p['custom_size']=true
      p['source_ctc']=p['ctc'];p['ctc']=ctc;p['L']+=delta
      p['actual_bounds_in'][0][0]-=delta/2;p['actual_bounds_in'][0][1]+=delta/2
      p['mount_points_in'].each { |point|point[0]=point[0]<0 ? -ctc/2 : ctc/2 }
      p
    end
    def self.validate_id(id)
      raise 'Invalid handle selection' unless id.nil? || id.is_a?(String)
      find(id) if id && !id.empty?
    end
    def self.selected(d,horizontal,s)
      key=d['_handle_model_key'] || (horizontal ? 'drawer_handle_model' : 'door_handle_model')
      id=d[key].nil? ? s['global_'+key] : d[key]
      id && !id.empty? ? find(id) : nil
    end
    def self.layout(d,w,h,horizontal,left,s)
      p=selected(d,horizontal,s);return nil unless p
      vertical=!horizontal && p['vertical_allowed'] && p['ctc']
      bounds=p['actual_bounds_in'];xmin,xmax=bounds[0];zmin,zmax=bounds[1]
      xmin,xmax,zmin,zmax=-zmax,-zmin,xmin,xmax if vertical
      pos=d.fetch('handle_position','auto');auto=pos=='auto'
      pos=horizontal || d['kind']=='tall' ? 'center' : (%w[wall corner_upper].include?(d['kind']) || d['_upper_front'] ? 'bottom' : 'top') if auto
      rail=%w[shaker glass].include?(d['style']) ? s.fetch('shaker_width',2.25) : 2.0
      offset=auto ? rail : d.fetch('handle_offset',rail);edge=auto ? rail/2 : d.fetch('handle_side',rail/2)
      cx=horizontal ? w/2 : (left ? w-edge : edge)
      half=vertical ? p['ctc']/2.0 : 0
      cz=pos=='top' ? h-offset-half : pos=='bottom' ? offset+half : h/2
      cx=[[cx,0.125-xmin].max,w-0.125-xmax].min if auto
      rect=[cx+xmin,cz+zmin,xmax-xmin,zmax-zmin]
      raise "Handle ##{p['number']} does not fit this front. Choose a smaller size or adjust placement." if rect[0]<0 || rect[1]<0 || rect[0]+rect[2]>w || rect[1]+rect[3]>h
      {'product'=>p,'vertical'=>!!vertical,'center'=>[cx,cz],'rect'=>rect}
    end
    def self.build(entities,name,x,y,z,w,h,d,horizontal,left,s)
      placement=layout(d,w,h,horizontal,left,s);return false unless placement
      p=placement['product'];file=File.join(__dir__,p['skp_path'])
      raise 'Handle asset changed' unless Digest::SHA256.file(file).hexdigest==p['skp_sha256']
      model=entities.model
      definition=model.definitions.find { |v|v.get_attribute('KitchenHandle','asset_id')==p['asset_id'] && v.get_attribute('KitchenHandle','sha256')==p['skp_sha256'] }
      unless definition
        source=model.definitions.load(file)
        if p['custom_size']
          definition=model.definitions.add("Kitchen custom handle #{p['asset_id']}")
          instance=definition.entities.add_instance(source,Geom::Transformation.new)
          instance.explode
          vertices=definition.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
          # The end regions translate rigidly; only the middle grip changes length.
          limit=p['source_ctc']/2.0-0.6;delta=p['ctc']-p['source_ctc']
          vectors=vertices.map do |vertex|
            x=vertex.position.x.to_f
            weight=[[x/limit,-1.0].max,1.0].min
            Geom::Vector3d.new(delta*weight/2.0,0,0)
          end
          definition.entities.transform_by_vectors(vertices,vectors)
        else
          definition=source
        end
        finish=model.materials['EMTEK_US15_Satin_Nickel']
        if finish
          definition.entities.grep(Sketchup::Face).each { |face|face.material=finish;face.back_material=finish }
        end
        definition.set_attribute('KitchenHandle','asset_id',p['asset_id'])
        definition.set_attribute('KitchenHandle','sha256',p['skp_sha256'])
      end
      cx,cz=placement['center'];origin=[x+cx,y,z+cz]
      axes=placement['vertical'] ? [[0,0,1],[-1,0,0],[0,-1,0]] : [[1,0,0],[0,0,1],[0,-1,0]]
      transform=Geom::Transformation.axes(origin,*axes)
      instance=entities.add_instance(definition,transform);instance.name="#{name} / #{p['family']} ##{p['number']}"
      instance.set_attribute('KitchenHandle','asset_id',p['asset_id'])
      instance.set_attribute('KitchenHandle','mount_points',p['mount_points_in'].map{|point|Geom::Point3d.new(point).transform(transform).to_a})
      true
    end
  end
end

require 'json'
require 'digest'
module KitchenLab
  module HandleCatalog
    def self.products
      @products ||= JSON.parse(File.read(File.join(__dir__,'handle_catalog.json')))
    end
    def self.find(id)
      products.find { |p|p['asset_id']==id } || raise('Handle is not in the approved catalog')
    end
    def self.validate_id(id)
      raise 'Invalid handle selection' unless id.nil? || id.is_a?(String)
      find(id) if id && !id.empty?
    end
    def self.selected(d,horizontal,s)
      key=horizontal ? 'drawer_handle_model' : 'door_handle_model'
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
        definition=model.definitions.load(file)
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

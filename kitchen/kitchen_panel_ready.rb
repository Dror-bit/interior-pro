require 'json'
require 'digest'
module KitchenLab
  module PanelReady
    def self.appliance?(d);d.dig('appliance','panel_ready').is_a?(Hash);end
    def self.copy(v);JSON.parse(JSON.generate(v));end
    def self.asset_file(relative)
      raise 'Invalid panel-ready asset path' unless relative.is_a?(String) && relative.match?(%r{\Aassets/appliances/panel-ready/[a-z0-9-]+\.skp\z})
      File.join(__dir__,relative)
    end
    def self.handle_snapshot(id,length)
      p=copy(HandleCatalog.find(id))
      raise 'Choose a straight pull for the appliance' unless p['ctc'] && p['family']!='Cup Pull' && !p['custom_size']
      raise 'Choose a 12 or 18 inch appliance pull' unless [12,18].include?(length)
      bounds=p['actual_bounds_in'];delta=length-(bounds[0][1]-bounds[0][0])
      p['source_asset_id']=p['asset_id'];p['asset_id']+="@overall=#{length}"
      p['source_ctc']=p['ctc'];p['source_overall_length']=p['L'];p['L']=length;p['ctc']+=delta
      p['actual_bounds_in'][0]=[bounds[0][0]-delta/2,bounds[0][1]+delta/2]
      p['mount_points_in'].each { |point|point[0]+=point[0]<0 ? -delta/2 : delta/2 }
      p['mount_points_mm']=p['mount_points_in'].map{|v|v.map{|n|n*25.4}}
      p['source_native_validation']=p.delete('native_validation');p['geometry_approved_by_user']=false
      p['size_delta']=delta;p['custom_appliance_pull']=true;p['geometry_revision']=1
      p['source_geometry']='Custom appliance pull derived from cabinet pull; not a manufacturer appliance SKU'
      p
    end
    def self.resolve(d,s)
      return d unless appliance?(d)
      d=d.dup;metadata=d['appliance']['panel_ready'];raw=d.fetch('panel_options',{})
      raise 'Invalid panel options' unless raw.is_a?(Hash) && (raw.keys-metadata['panels'].map{|p|p['panel_id']}).empty?
      inherited=s['global_finish'].to_s;inherited=d.fetch('finish','ivory') if inherited.empty?
      d['panel_options']=metadata['panels'].to_h do |panel|
        o=copy(raw.fetch(panel['panel_id'],{}));raise 'Invalid panel settings' unless o.is_a?(Hash)
        finish=o['finish'];raise 'Invalid panel finish' unless finish.nil? || %w[ivory sage charcoal oak].include?(finish)
        style=o.fetch('style','slab');raise 'Choose a plain or Shaker panel' unless %w[slab shaker].include?(style)
        h=o.fetch('handle') do
          candidate=HandleCatalog.products.find{|p|p['asset_id']==s['global_door_handle_model'] && p['ctc'] && p['family']!='Cup Pull'}
          candidate||=HandleCatalog.products.find{|p|p['number']==18}
          {'source_asset_id'=>candidate['asset_id'],'overall_length'=>12}
        end
        if h
          raise 'Invalid appliance handle' unless h.is_a?(Hash) && [12,18].include?(h['overall_length'])
          snap=h['snapshot']
          snap=handle_snapshot(h['source_asset_id'],h['overall_length']) unless snap && snap['source_asset_id']==h['source_asset_id'] && snap['L']==h['overall_length']
          raise 'Invalid saved appliance handle' unless snap['custom_appliance_pull'] && snap['geometry_revision']==1 && snap['mount_points_in'].length==2
          h={'source_asset_id'=>h['source_asset_id'],'overall_length'=>h['overall_length'],'snapshot'=>snap}
        end
        [panel['panel_id'],{'style'=>style,'finish'=>finish,'resolved_finish'=>finish||inherited,'handle'=>h}]
      end
      d
    end
    def self.validate!(d,s)
      unless appliance?(d)
        raise 'Custom appliance panels require a Panel Ready model' if d.key?('panel_options')
        return
      end
      p=d['appliance']['panel_ready']
      raise 'Panel Ready is only supported for refrigerators and dishwashers' unless %w[fridge dishwasher].include?(d['kind'])
      raise 'Panel-ready geometry changed' unless Digest::SHA256.file(asset_file(p['skp_path'])).hexdigest==p['skp_sha256']
      raise 'Unsupported panel-ready geometry revision' unless p['geometry_revision']==1
      d['panel_options']=resolve(d,s)['panel_options']
    end
    def self.panel_boxes(panel,style)
      w,h,t=panel['dimensions_in'].values_at('width','height','thickness');x,y,z=panel['origin_asset_in']
      return [[x,y,z,w,t,h]] if style=='slab'
      rail=2.25;inset=0.25
      [[x,y,z,rail,t,h],[x+w-rail,y,z,rail,t,h],
       [x+rail,y,z,w-2*rail,t,rail],[x+rail,y,z+h-rail,w-2*rail,t,rail],
       [x+rail,y+inset,z+rail,w-2*rail,t-inset,h-2*rail]]
    end
    def self.handle_axes(panel)
      length=panel['handle_attachment']['length_axis_panel_local']
      [length,length==[0,0,1] ? [-1,0,0] : [0,0,1],[0,-1,0]]
    end
    def self.handle_box(panel,h)
      p=h['snapshot'];axes=handle_axes(panel);center=panel['handle_attachment']['center_asset_in']
      points=p['actual_bounds_in'][0].product(p['actual_bounds_in'][1],p['actual_bounds_in'][2]).map do |point|
        3.times.map{|i|center[i]+3.times.sum{|j|point[j]*axes[j][i]}}
      end
      lo=3.times.map{|i|points.map{|v|v[i]}.min};hi=3.times.map{|i|points.map{|v|v[i]}.max}
      [*lo,*3.times.map{|i|hi[i]-lo[i]}]
    end
    def self.parts(d)
      p=d['appliance']['panel_ready'];parts=[]
      add=lambda do |name,box,color,id=nil|
        x,y,z,w,dep,h=box;parts<<{'name'=>name,'x'=>x,'y'=>y,'z'=>z,'width'=>w,'depth'=>dep,'height'=>h,'color'=>color,'panel_id'=>id}
      end
      lo,hi=p['body_bounds_asset_in'];add.call('Appliance body',[*lo,*3.times.map{|i|hi[i]-lo[i]}],'#53595b')
      p['panels'].each do |panel|
        id=panel['panel_id'];o=d.fetch('panel_options').fetch(id);color=KitchenLab::FINISHES.fetch(o['resolved_finish'])
        panel_boxes(panel,o['style']).each{|box|add.call('Panel '+id,box,color,id)}
        add.call('Handle '+id,handle_box(panel,o['handle']),'#b9b8b5',id) if o['handle']
      end
      parts
    end
    def self.handle_definition(model,p)
      relative=p['skp_path']
      raise 'Invalid handle path' unless relative.match?(%r{\Aassets/handles/[a-zA-Z0-9-]+/handle\.skp\z})
      file=File.join(__dir__,relative);raise 'Appliance handle geometry changed' unless Digest::SHA256.file(file).hexdigest==p['skp_sha256']
      key=Digest::SHA256.hexdigest(JSON.generate(p))
      cached=model.definitions.find{|v|v.get_attribute('KitchenApplianceHandle','key')==key};return cached if cached
      source=model.definitions.load(file)
      definition=model.definitions.add('Custom appliance pull '+p['family']+' '+p['L'].to_s)
      instance=definition.entities.add_instance(source,Geom::Transformation.new);instance.explode
      vertices=definition.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      limit=p['source_ctc']/2.0-0.6;delta=p['size_delta']
      vectors=vertices.map{|v|Geom::Vector3d.new(delta*[[v.position.x.to_f/limit,-1.0].max,1.0].min/2,0,0)}
      definition.entities.transform_by_vectors(vertices,vectors)
      definition.set_attribute('KitchenApplianceHandle','key',key)
      definition.set_attribute('KitchenApplianceHandle','snapshot',JSON.generate(p));definition
    end
    def self.build(entities,d)
      p=d['appliance']['panel_ready'];model=entities.model
      source=model.definitions.find{|v|v.get_attribute('KitchenPanelReadySource','sha256')==p['skp_sha256']}
      unless source
        source=model.definitions.load(asset_file(p['skp_path']))
        source.set_attribute('KitchenPanelReadySource','sha256',p['skp_sha256'])
      end
      assembly=entities.add_instance(source,Geom::Transformation.new);assembly.make_unique
      assembly.definition.delete_attribute('KitchenPanelReadySource')
      assembly.name=d['appliance']['model']+' / Panel Ready'
      assembly.set_attribute('KitchenPanelReady','snapshot',JSON.generate(p))
      p['panels'].each do |panel|
        id=panel['panel_id'];options=d.fetch('panel_options').fetch(id)
        part=assembly.definition.entities.grep(Sketchup::ComponentInstance).find{|v|v.get_attribute('PanelReady','panel_id')==id || v.name==panel['component_name'] || v.definition.name==panel['component_name']}
        raise 'Panel missing from approved model: '+id unless part
        finish=KitchenLab.material(options['resolved_finish'],KitchenLab::FINISHES.fetch(options['resolved_finish']))
        part.material=finish
        if options['style']=='shaker'
          part.make_unique;part.definition.entities.clear!
          origin=panel['origin_asset_in']
          panel_boxes(panel,'shaker').each_with_index do |box,i|
            x,y,z,w,depth,h=box;KitchenLab.box(part.definition.entities,"Shaker #{i+1}",x-origin[0],y-origin[1],z-origin[2],w,depth,h,finish)
          end
        end
        part.set_attribute('PanelReady','panel_id',id);part.set_attribute('PanelReady','options',JSON.generate(options))
        next unless options['handle']
        hp=options['handle']['snapshot'];transform=Geom::Transformation.axes(panel['handle_attachment']['center_asset_in'],*handle_axes(panel))
        handle=assembly.definition.entities.add_instance(handle_definition(model,hp),transform)
        handle.name="Custom #{hp['family']} #{hp['L']} in / #{id}"
        handle.set_attribute('KitchenApplianceHandle','panel_id',id)
        handle.set_attribute('KitchenApplianceHandle','snapshot',JSON.generate(hp))
        handle.set_attribute('KitchenApplianceHandle','mount_points',hp['mount_points_in'].map{|v|Geom::Point3d.new(v).transform(transform).to_a})
      end
      true
    end
  end
end

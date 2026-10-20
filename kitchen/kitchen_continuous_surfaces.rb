module KitchenLab
  module ContinuousSurfaces
    remove_const(:USE_ISOLATED_SURFACE_REUSE) if const_defined?(:USE_ISOLATED_SURFACE_REUSE,false)
    USE_ISOLATED_SURFACE_REUSE=true
    # Prove that a change cannot affect existing surfaces. Uncertain cases use
    # the original complete rebuild, including all surface producers and hoods.
    def self.isolated_changes?(previous,current,surfaces,&bounds)
      return false unless previous && previous['settings']==current['settings'] && !surfaces.empty?
      before=previous['cabinets'].to_h { |d|[d['id'],d] }
      after=current['cabinets'].to_h { |d|[d['id'],d] }
      changed=(before.keys|after.keys).select { |id|before[id]!=after[id] }
      changed.all? do |id|
        next false if surfaces.any? { |s|s[:owners].include?(id) }
        [before[id],after[id]].compact.all? do |d|
          parent=before[d['surround_for']] || after[d['surround_for']]
          next false unless %w[wall tall fridge fridge_surround corner_upper].include?(d['kind']) || (d['kind']=='filler' && parent && parent['kind']=='fridge')
          next false if parent && parent['kind']!='fridge'
          box=bounds.call(d)
          # Include the backsplash clipping tolerance and slab overhang.
          surfaces.none? { |s|3.times.all? { |i|box[1][i]+2>=s[:box][0][i] && s[:box][1][i]+2>=box[0][i] } }
        end
      end
    end
    def self.reusable?(previous)
      return false unless USE_ISOLATED_SURFACE_REUSE && previous
      model=KitchenLab.instance_variable_get(:@model)
      return false unless model.get_attribute(KitchenLab::DICT,'backsplash_opening_signature')==Backsplash.opening_signature(model)
      surfaces=[]
      collect=lambda do |g,transform,owners|
        world=transform*g.transformation
        faces=g.entities.grep(Sketchup::Face)
        unless faces.empty?
          points=faces.flat_map(&:vertices).uniq.map { |v|v.position.transform(world).to_a.map(&:to_f) }
          surfaces<<{owners:owners,box:[3.times.map { |i|points.map { |p|p[i] }.min },3.times.map { |i|points.map { |p|p[i] }.max }]}
        end
        g.entities.grep(Sketchup::Group).each { |child|collect.call(child,world,owners) }
      end
      model.entities.grep(Sketchup::Group).select { |g|g.get_attribute(KitchenLab::DICT,'kind')=='worktop' }.each do |g|
        owners=g.get_attribute(KitchenLab::DICT,'owners',[]) + [g.get_attribute(KitchenLab::DICT,'owner_id')].compact
        collect.call(g,Geom::Transformation.new,owners)
      end
      isolated_changes?(previous,KitchenLab.document,surfaces) do |d|
        t=KitchenLab.cabinet_transform(d)
        points=[0,d['width']].product([0,-d['depth']],[0,d['height']]).map { |p|Geom::Point3d.new(p).transform(t).to_a.map(&:to_f) }
        [3.times.map { |i|points.map { |p|p[i] }.min },3.times.map { |i|points.map { |p|p[i] }.max }]
      end
    end
    EPS=0.001 unless const_defined?(:EPS,false)
    def self.touch?(a,b)
      aa=a.bounds;bb=b.bounds
      overlaps=3.times.map{|i| [aa.max[i],bb.max[i]].min-[aa.min[i],bb.min[i]].max}
      overlaps.all?{|v|v>=-EPS} && overlaps.count{|v|v>EPS}>=2
    end
    def self.stamp(g,role,owners,assembly)
      g.name=role=='countertop' ? 'Kitchen / Continuous countertop' : 'Kitchen / Continuous backsplash'
      g.set_attribute(KitchenLab::DICT,'kind','worktop')
      g.delete_attribute(KitchenLab::DICT,'owner_id')
      g.set_attribute(KitchenLab::DICT,'surface_role',role)
      g.set_attribute(KitchenLab::DICT,'owners',owners.uniq.sort)
      g.set_attribute(KitchenLab::DICT,'assembly',assembly)
    end
    def self.build!
      model=KitchenLab.instance_variable_get(:@model);roots=model.entities
      data=KitchenLab.state['cabinets'].to_h{|d|[d['id'],d]}
      tops=roots.grep(Sketchup::Group).select{|g|g.get_attribute(KitchenLab::DICT,'kind')=='worktop'}
      pieces=[]
      tops.each do |top|
        id=top.get_attribute(KitchenLab::DICT,'owner_id');d=data[id];next unless d
        assembly=d['wall']=='I' ? 'island' : 'kitchen'
        top.entities.grep(Sketchup::Group).select{|g|g.get_attribute(KitchenLab::DICT,'kind')=='backsplash'}.each do |bs|
          bs.entities.grep(Sketchup::Group).each do |slab|
            g=roots.add_group
            g.entities.add_instance(slab.definition,top.transformation*bs.transformation*slab.transformation).explode
            g.material=slab.material || bs.material || top.material
            stamp(g,'backsplash',[id],assembly);g.set_attribute(KitchenLab::DICT,'surface_finish',slab.name);g.set_attribute(KitchenLab::DICT,'tile_cell',slab.get_attribute(KitchenLab::DICT,'tile_cell'));pieces<<g
          end
          bs.erase!
        end
        if top.entities.grep(Sketchup::Face).empty?
          top.erase!
        else
          stamp(top,'countertop',[id],assembly);pieces<<top
        end
      end
      pieces.each{|g|raise "Surface is not solid: #{g.name}" unless g.manifold?}
      buckets=pieces.group_by{|g|[g.get_attribute(KitchenLab::DICT,'surface_role'),g.get_attribute(KitchenLab::DICT,'assembly'),g.material && g.material.name,g.get_attribute(KitchenLab::DICT,'surface_finish'),g.get_attribute(KitchenLab::DICT,'tile_cell')]}
      buckets.each do |(role,assembly,_,finish,cell),groups|
        next if finish=='Tile' && !cell
        loop do
          pair=groups.combination(2).find{|a,b|touch?(a,b)}
          break unless pair
          a,b=pair;owners=a.get_attribute(KitchenLab::DICT,'owners')+b.get_attribute(KitchenLab::DICT,'owners');mat=a.material
          merged=a.union(b)
          raise 'Unable to join kitchen surfaces; change was cancelled.' unless merged && merged.manifold?
          merged.material=mat;stamp(merged,role,owners,assembly)
          merged.set_attribute(KitchenLab::DICT,'surface_finish',finish)
          merged.set_attribute(KitchenLab::DICT,'tile_cell',cell)
          groups=groups.reject{|g|g==a || g==b}+[merged]
        end
      end
      config=Backsplash.validate(KitchenLab.settings['backsplash'])
      roots.grep(Sketchup::Group).each do |g|
        Backsplash.map_tile_photo!(g,config) if g.get_attribute(KitchenLab::DICT,'surface_finish')=='Tile' && g.get_attribute(KitchenLab::DICT,'tile_cell')
      end
      # A kitchen backsplash is one selectable object, including disconnected wall runs.
      # Preserve real gaps/windows in its geometry; the island remains independent.
      backs=roots.grep(Sketchup::Group).select{|g|g.get_attribute(KitchenLab::DICT,'surface_role')=='backsplash'}
      backs.group_by{|g|g.get_attribute(KitchenLab::DICT,'assembly')}.each do |assembly,groups|
        next if groups.length==1
        owners=groups.flat_map{|g|g.get_attribute(KitchenLab::DICT,'owners')}
        parent=roots.add_group(groups);stamp(parent,'backsplash',owners,assembly)
      end
    end
  end
end

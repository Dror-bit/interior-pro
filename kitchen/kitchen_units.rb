require 'json'
module KitchenLab
  def self.unit_groups
    @model.entities.grep(Sketchup::Group).select { |g|g.get_attribute(DICT,'kind')=='kitchen_unit' }
  end
  def self.unpack_units!
    return unless @model.respond_to?(:entities)
    unit_groups.each(&:explode)
  end
  def self.pack_units!
    data=state['cabinets'];by_id=data.to_h { |d|[d['id'],d] }
    owner=lambda { |id|by_id[id] && (by_id[id]['surround_for'] || id) }
    members=@model.entities.grep(Sketchup::Group).select { |g|%w[cabinet worktop crown].include?(g.get_attribute(DICT,'kind')) }.group_by do |g|
      owner.call(g.get_attribute(DICT,'kind')=='cabinet' ? g.get_attribute(DICT,'id') : g.get_attribute(DICT,'owner_id'))
    end
    members.each do |id,groups|
      next unless id
      unit=@model.entities.add_group(groups);unit.name='Kitchen / '+(by_id[id].dig('appliance','model') || by_id[id]['kind'])
      unit.set_attribute(DICT,'kind','kitchen_unit');unit.set_attribute(DICT,'id',id)
      unit.set_attribute(DICT,'unit_transform',unit.transformation.to_a)
      unit.set_attribute(DICT,'members',data.select{|d|owner.call(d['id'])==id}.map{|d|d['id']})
    end
    @model.set_attribute(DICT,'unit_owners',JSON.generate(unit_groups.map{|g|g.get_attribute(DICT,'id')}))
    refresh_kitchen_baseboards!
  end
  remove_const(:USE_KITCHEN_BASEBOARD_SYNC) if const_defined?(:USE_KITCHEN_BASEBOARD_SYNC,false)
  USE_KITCHEN_BASEBOARD_SYNC=true
  # Runs inside the cabinet transaction. Never start an extra Undo operation or
  # rebuild house crowns. Preserve per-side profiles, material and visibility.
  def self.refresh_kitchen_baseboards!
    return unless USE_KITCHEN_BASEBOARD_SYNC && defined?(InteriorPro::MoldingManager)
    builder=InteriorPro::MoldingBuilder;manager=InteriorPro::MoldingManager
    groups=@model.entities.grep(Sketchup::Group).select { |g|g.get_attribute('InteriorPro','type')=='baseboard' }
    pending=JSON.parse(@model.get_attribute(DICT,'empty_baseboard_runs','[]'))
    return if groups.empty? && pending.empty?
    ws=manager.walls(@model);cent={};plan=[]
    manager.wall_components(ws).each { |component|c=manager.house_centroid(component);component.each { |w|cent[w]=c } }
    ws.each do |w|
      next if w.get_attribute('InteriorPro','no_molding')
      edges=builder.wall_edges(w);next unless edges
      manager.sides_for(w,cent[w]).each do |side|
        geo=builder.edge_geometry(w,edges[side]);next unless geo
        plan<<{wall:w,side:side,edge:edges[side],geo:geo,shifts:{start:0,end:0},tee_gaps:[]}
      end
    end
    manager.resolve_miters!(plan);manager.resolve_tees!(plan);manager.resolve_flush_butts!(plan)
    records=groups.map { |g|{'wall'=>g.get_attribute('InteriorPro','host_wall_id'),'side'=>g.get_attribute('InteriorPro','side'),'profile'=>g.get_attribute('InteriorPro','profile'),'height'=>g.get_attribute('InteriorPro','profile_h'),'group'=>g} }
    keys=records.map { |r|[r['wall'],r['side']] }
    records+=pending.reject { |r|keys.include?([r['wall'],r['side']]) }
    empty=[];updated=0
    records.each do |record|
      row=plan.find { |r|r[:wall].get_attribute('InteriorPro','id')==record['wall'] && r[:side].to_s==record['side'] };next unless row
      wall=row[:wall];side=row[:side]
      next if wall.get_attribute('InteriorPro',"no_molding_#{side}")
      next if manager::USE_ROOM_MOLDING && manager.side_in_off_room?(wall,row[:geo],manager.rooms_off(@model))
      profile=InteriorPro::MoldingLibrary.baseboard_profile_by_name(record['profile'],record['height']);next unless profile
      gaps=builder.baseboard_stop_gaps(wall,row[:geo],0,profile.map(&:last).max)
      signature=JSON.generate([gaps,row[:shifts],row[:tee_gaps]])
      old=record['group']
      next if old && old.get_attribute(DICT,'baseboard_cut_signature')==signature
      replacement=builder.build_baseboard_on_edge!(wall,row[:edge],record['profile'],side,row[:shifts],record['height'],row[:tee_gaps])
      if replacement && replacement.valid?
        if old
          replacement.material=old.material;replacement.layer=old.layer;replacement.hidden=old.hidden?
        end
        replacement.set_attribute(DICT,'baseboard_cut_signature',signature)
      else
        empty<<record.reject { |k,_|k=='group' }
      end
      old.erase! if old && old.valid?
      updated+=1
    end
    serialized=JSON.generate(empty)
    @model.set_attribute(DICT,'empty_baseboard_runs',serialized) unless @model.get_attribute(DICT,'empty_baseboard_runs','[]')==serialized
    @last_baseboard_updates=updated
  end
  module UnitCabinets
    def cabinets
      roots=super
      return roots unless @model.respond_to?(:entities)
      roots+unit_groups.flat_map { |u|u.entities.grep(Sketchup::Group).select{|g|g.get_attribute(DICT,'kind')=='cabinet'} }
    end
  end
  singleton_class.prepend(UnitCabinets) unless singleton_class.ancestors.include?(UnitCabinets)

  def self.unit_pose(d,transform,options)
    x=transform.xaxis;y=transform.yaxis;z=transform.zaxis
    raise 'Kitchen units support Move and rotation about the vertical axis; edit dimensions in the cabinet editor.' unless x.z.abs<0.00001 && y.z.abs<0.00001 && (z.z-1).abs<0.00001 && (x.length-1).abs<0.00001 && (y.length-1).abs<0.00001 && x.dot(y).abs<0.00001
    origin=transform.origin;angle=Math.atan2(x.y,x.x)*180.0/Math::PI
    d.merge('house_placement'=>{'x'=>origin.x.to_f,'y'=>origin.y.to_f,'angle'=>angle,'handedness'=>x.cross(y).z>0 ? 1 : -1},'z'=>origin.z.to_f-Spatial.pose(options)['z'],'flip_x'=>false,'flip_y'=>false)
  end
  remove_const(:USE_ISOLATED_KITCHEN_SYNC) if const_defined?(:USE_ISOLATED_KITCHEN_SYNC,false)
  USE_ISOLATED_KITCHEN_SYNC=true
  def self.sync_unit_moves!(model)
    return if @unit_syncing || !model.equal?(@model) || !model.active_path.nil?
    raw=model.get_attribute(DICT,'document');return unless raw
    doc=Document.read(raw);units=unit_groups
    saved=JSON.parse(model.get_attribute(DICT,'unit_owners','[]'))
    removed=saved-units.map{|g|g.get_attribute(DICT,'id')}
    changed=units.select { |u|prev=u.get_attribute(DICT,'unit_transform');prev && u.transformation.to_a.zip(prev).any?{|a,b|(a-b).abs>0.000001} }
    openings_changed=defined?(Backsplash) && Backsplash.openings_changed?(model)
    return if changed.empty? && removed.empty? && !openings_changed
    data=doc['cabinets'].reject{|d|removed.include?(d['surround_for']||d['id'])}
    changed.each do |u|
      delta=u.transformation*Geom::Transformation.new(u.get_attribute(DICT,'unit_transform')).inverse
      ids=u.get_attribute(DICT,'members',[])
      data=data.map{|d|ids.include?(d['id']) ? unit_pose(d,delta*cabinet_transform(d),doc['settings']) : d}
    end
    @unit_syncing=true
    # A failed transparent operation also aborts the user's preceding edit.
    # Keep observer-driven kitchen rebuilding in its own undo transaction.
    model.start_operation('Kitchen: sync placement and openings',true,false,!USE_ISOLATED_KITCHEN_SYNC)
    begin
      write_document!(data,doc['settings'])
      changed.each{|u|u.set_attribute(DICT,'unit_transform',u.transformation.to_a)}
      model.set_attribute(DICT,'unit_owners',JSON.generate(units.map{|u|u.get_attribute(DICT,'id')}))
      cabinets.each do |g|
        d=data.find{|c|c['id']==g.get_attribute(DICT,'id')};g.set_attribute(DICT,'data',JSON.generate(d)) if d
      end
      worktops!(previous: doc)
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    ensure
      @unit_syncing=false
    end
    publish
    host=defined?(InteriorPro::PlanEditor) && InteriorPro::PlanEditor.instance_variable_get(:@dialog)
    InteriorPro::KitchenPlan.push(host) if host && host.visible?
  rescue StandardError=>e
    puts '[Kitchen units] '+e.message
  end
  class DocumentUndoObserver
    def onTransactionCommit(model);KitchenLab.sync_unit_moves!(model);end
  end
  unless @unit_context_menu
    if defined?(UI) && UI.respond_to?(:add_context_menu_handler)
      UI.add_context_menu_handler do |menu|
        selected=Sketchup.active_model.selection.to_a
        unit=selected.length==1 && selected.first
        if unit && %w[kitchen_unit cabinet].include?(unit.get_attribute(DICT,'kind'))
          menu.add_item('Edit kitchen cabinet') do
            InteriorPro::KitchenPlan.bind_active_model!
            InteriorPro::KitchenPlan.edit_cabinet(unit.get_attribute(DICT,'id'))
          end
        end
      end
      @unit_context_menu=true
    end
  end
end
module KitchenLab
  def self.bind_saved_units(model)
    return unless model.equal?(Sketchup.active_model) && model.get_attribute(DICT,'unit_owners') && model.active_path.nil?
    Backsplash.prime_opening_signature!(model) if defined?(Backsplash)
    InteriorPro::KitchenPlan.bind_active_model! if defined?(InteriorPro::KitchenPlan)
  rescue StandardError=>e
    puts '[Kitchen units] '+e.message
  end
  if defined?(Sketchup::AppObserver)
    class UnitAppObserver < Sketchup::AppObserver
      def expectsStartupModelNotifications;true;end
      def onOpenModel(model);KitchenLab.bind_saved_units(model);end
      def onNewModel(model);KitchenLab.bind_saved_units(model);end
    end
    unless @unit_app_observer
      @unit_app_observer=UnitAppObserver.new
      Sketchup.add_observer(@unit_app_observer)
      UI.start_timer(0,false){KitchenLab.bind_saved_units(Sketchup.active_model)}
    end
  end
end

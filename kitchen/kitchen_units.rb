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
  def self.sync_unit_moves!(model)
    return if @unit_syncing || !model.equal?(@model) || !model.active_path.nil?
    raw=model.get_attribute(DICT,'document');return unless raw
    doc=Document.read(raw);units=unit_groups
    saved=JSON.parse(model.get_attribute(DICT,'unit_owners','[]'))
    removed=saved-units.map{|g|g.get_attribute(DICT,'id')}
    changed=units.select { |u|prev=u.get_attribute(DICT,'unit_transform');prev && u.transformation.to_a.zip(prev).any?{|a,b|(a-b).abs>0.000001} }
    openings_changed=defined?(Backsplash) && model.get_attribute(DICT,'backsplash_opening_signature')!=Backsplash.opening_signature(model)
    return if changed.empty? && removed.empty? && !openings_changed
    data=doc['cabinets'].reject{|d|removed.include?(d['surround_for']||d['id'])}
    changed.each do |u|
      delta=u.transformation*Geom::Transformation.new(u.get_attribute(DICT,'unit_transform')).inverse
      ids=u.get_attribute(DICT,'members',[])
      data=data.map{|d|ids.include?(d['id']) ? unit_pose(d,delta*cabinet_transform(d),doc['settings']) : d}
    end
    @unit_syncing=true
    model.start_operation('Kitchen: sync placement and openings',true,false,true)
    begin
      write_document!(data,doc['settings'])
      changed.each{|u|u.set_attribute(DICT,'unit_transform',u.transformation.to_a)}
      model.set_attribute(DICT,'unit_owners',JSON.generate(units.map{|u|u.get_attribute(DICT,'id')}))
      cabinets.each do |g|
        d=data.find{|c|c['id']==g.get_attribute(DICT,'id')};g.set_attribute(DICT,'data',JSON.generate(d)) if d
      end
      worktops!
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

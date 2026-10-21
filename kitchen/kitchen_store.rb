# Standalone SketchUp storage adapter. A future Interior Pro adapter can use
# the same Document without importing its generated SketchUp geometry.
module KitchenLab
  remove_const(:USE_OPERATION_DOCUMENT_MEMO) if const_defined?(:USE_OPERATION_DOCUMENT_MEMO,false)
  USE_OPERATION_DOCUMENT_MEMO=true
  def self.with_document_snapshot
    return yield unless USE_OPERATION_DOCUMENT_MEMO
    outer=@document_snapshot_depth.to_i==0
    @document_snapshot_depth=@document_snapshot_depth.to_i+1
    yield
  ensure
    if USE_OPERATION_DOCUMENT_MEMO
      @document_snapshot_depth=@document_snapshot_depth.to_i-1
      @document_snapshot=nil if outer
    end
  end
  def self.document
    return read_document_uncached unless USE_OPERATION_DOCUMENT_MEMO && @document_snapshot_depth.to_i>0
    guard!
    raw=@model.get_attribute(DICT,'document')
    memo=@document_snapshot
    return memo[2] if memo && memo[0].equal?(@model) && memo[1]==raw
    value=read_document_uncached
    @document_snapshot=[@model,raw,value]
    value
  end
  def self.read_document_uncached
    guard!
    raw=@model.get_attribute(DICT,'document')
    return Document.read(raw) unless raw.nil?
    existing=cabinets.map { |g| JSON.parse(g.get_attribute(DICT,'data')) }
    saved_settings=@model.get_attribute(DICT,'settings')
    initial={'shaker_width'=>2.25,'shaker_inset'=>0.25,'crown_profile'=>'flat','crown_height'=>6.0,'crown_depth'=>0.75,'crown_color'=>'cabinet','crown_match_house'=>false}
    if saved_settings.nil? && existing.empty?
      default_handle=HandleCatalog.products.find { |p|p['number']==18 }.fetch('asset_id')
      initial.merge!('global_door_handle_model'=>default_handle,'global_drawer_handle_model'=>default_handle)
    end
    Document.create(saved_settings ? JSON.parse(saved_settings) : initial,existing)
  end

  # Caller owns the Undo operation. Never reconstruct saved data from geometry
  # once a document exists, even when a generated group has been deleted.
  def self.write_document!(data, options=settings)
    previous=document
    candidate=Document.create(options,data,previous['revision']+1)
    old=@model.get_attribute(DICT,'document')
    if old
      history=JSON.parse(@model.get_attribute(DICT,'document_history','[]'))
      history.unshift(old)
      history=history.first(6)
      history.pop while history.length>1 && JSON.generate(history).bytesize>3_000_000
      @model.set_attribute(DICT,'document_history',JSON.generate(history))
    else
      @model.set_attribute(DICT,'legacy_snapshot',JSON.generate(previous))
    end
    @model.set_attribute(DICT,'document',JSON.generate(candidate))
    # Compatibility mirror for older diagnostics; never read as authority.
    @model.set_attribute(DICT,'settings',JSON.generate(options))
    candidate
  end

  def self.ensure_document!
    guard!
    return document unless @model.get_attribute(DICT,'document').nil?
    initial=document
    @model.start_operation('Kitchen: preserve design document',true)
    begin
      write_document!(initial['cabinets'],initial['settings'])
      @model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    document
  end

  def self.remove(id)
    execute_commands({'commands'=>[{'type'=>'remove_cabinet','payload'=>{'id'=>id}}]})
  end

  # Geometry-only entry point: caller owns the operation; source data survives
  # deleting/rebuilding every generated cabinet, counter and crown.
  def self.generate_geometry!
    guard!
    raise 'Preserve the kitchen document before generating geometry' if @model.get_attribute(DICT,'document').nil?
    unpack_units!
    data=state['cabinets']
    data.each { |d| validate(d);check_shaker(d) }
    raise 'Cabinets overlap' if data.combination(2).any? { |a,b| overlap?(a,b) }
    @model.entities.grep(Sketchup::Group).select { |g| %w[cabinet worktop crown].include?(g.get_attribute(DICT,'kind')) }.each(&:erase!)
    data.each { |d| build(d) }
    worktops!
  end

  def self.rebuild_3d!
    guard!
    @model.start_operation('Kitchen: rebuild 3D',true)
    begin
      # Also preserves legacy source before removing any generated groups.
      initial=state
      write_document!(initial['cabinets'],initial['settings']) if @model.get_attribute(DICT,'document').nil?
      generate_geometry!
      @model.commit_operation
    rescue StandardError
      @model.abort_operation;raise
    end
    publish
  end

  class DocumentUndoObserver < Sketchup::ModelObserver
    def onTransactionUndo(model);refresh(model);end
    def onTransactionRedo(model);refresh(model);end
    def refresh(model)
      UI.start_timer(0.1,false) do
        begin
          if model.equal?(KitchenLab.instance_variable_get(:@model))
            KitchenLab.publish
            host=defined?(InteriorPro::PlanEditor) && InteriorPro::PlanEditor.instance_variable_get(:@dialog)
            InteriorPro::KitchenPlan.push(host) if host && host.visible?
          end
        rescue StandardError => e
          puts "[Kitchen] refresh: #{e.message}"
        end
      end
    end
  end

  def self.observe_document!
    @model.remove_observer(@document_observer) if @document_observer
    @document_observer=DocumentUndoObserver.new
    @model.add_observer(@document_observer)
  end
end

module KitchenLab
  module OperationDocumentSnapshot
    %i[crowns! worktops! sync_unit_moves! pack_units! refresh_kitchen_baseboards! execute_commands generate_geometry!].each do |name|
      define_method(name) do |*args,**kwargs,&block|
        with_document_snapshot { kwargs.empty? ? super(*args,&block) : super(*args,**kwargs,&block) }
      end
    end
  end
  singleton_class.prepend(OperationDocumentSnapshot) unless singleton_class.ancestors.include?(OperationDocumentSnapshot)
end

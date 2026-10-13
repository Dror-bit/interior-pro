# Standalone SketchUp storage adapter. A future Interior Pro adapter can use
# the same Document without importing its generated SketchUp geometry.
module KitchenLab
  def self.document
    guard!
    raw=@model.get_attribute(DICT,'document')
    return Document.read(raw) unless raw.nil?
    Document.create(JSON.parse(@model.get_attribute(DICT,'settings','{"shaker_width":2.25,"shaker_inset":0.25}')),
      cabinets.map { |g| JSON.parse(g.get_attribute(DICT,'data')) })
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
          KitchenLab.publish if model.equal?(KitchenLab.instance_variable_get(:@model))
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

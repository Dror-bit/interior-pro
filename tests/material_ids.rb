# encoding: utf-8
# Interior Pro - A PERMANENT ID ON A MATERIAL (2026-09-18)
#
# WHY. A SketchUp material is identified by its NAME, and a name moves:
# the user renames it, SketchUp appends "#1" on a clash, an imported
# component brings its own. Measured on his model the same day
# (vray_api_report.txt): 106 materials, not one of them carrying a single
# attribute dictionary - so today there is no handle at all.
#
# Three things wait on this one (VRAY_POC_PLAN.md):
#   1. V-Ray: "give THIS material roughness 0.35" has to point at a
#      material that cannot turn into a different one overnight;
#   2. Tile: every tile run remembers its own texture, direction, scale;
#   3. the business software: a material card to match against later.
#
# WHAT IT IS. One hidden attribute, written once and never changed:
#   dictionary "InteriorPro_Material", key "id", value "IP_MAT_0001".
# The name is then free to be anything. Nothing here reads a name, ever.
#
# Kill switch: InteriorPro::MaterialIds::USE_MATERIAL_IDS = false - then
# nothing is stamped and nothing is read; the plugin is exactly the one
# it was before this file.
module InteriorPro
  module MaterialIds
    USE_MATERIAL_IDS = true unless const_defined?(:USE_MATERIAL_IDS, false)

    DICT = 'InteriorPro_Material'.freeze
    KEY  = 'id'.freeze
    # the running number lives on the MODEL, so two materials in one
    # model never take the same id
    COUNTER_DICT = 'InteriorPro'.freeze
    COUNTER_KEY  = 'next_material_id'.freeze
    PREFIX = 'IP_MAT_'.freeze

    # The id already on this material, or nil. Reads only - a material
    # that has never been stamped is left exactly as it is.
    def self.id_of(mat)
      return nil unless USE_MATERIAL_IDS
      return nil if mat.nil?
      v = mat.get_attribute(DICT, KEY)
      v.nil? || v.to_s.empty? ? nil : v.to_s
    rescue StandardError
      nil
    end

    # PURE. The text of the n-th id. Kept apart so a test can pin the
    # shape without a model.
    def self.format_id(n)
      format('%s%04d', PREFIX, n.to_i)
    end

    # PURE. Is this an id we wrote?
    def self.id?(s)
      !!(s.to_s =~ /\A#{PREFIX}\d{4,}\z/)
    end

    # The next free number on this model, and it moves the counter on.
    # Never reuses a number, even after a material is deleted: an id that
    # came back on a different material would be worse than none.
    def self.next_number!(model)
      n = model.get_attribute(COUNTER_DICT, COUNTER_KEY).to_i
      n = 1 if n < 1
      model.set_attribute(COUNTER_DICT, COUNTER_KEY, n + 1)
      n
    end

    # Give this material an id if it has none, and hand it back. A
    # material that already has one keeps it - this is the whole point.
    def self.ensure_id!(mat, model = nil)
      return nil unless USE_MATERIAL_IDS
      return nil if mat.nil?
      have = id_of(mat)
      return have if have
      model ||= Sketchup.active_model
      new_id = format_id(next_number!(model))
      mat.set_attribute(DICT, KEY, new_id)
      new_id
    rescue StandardError => e
      puts "[MaterialIds] ensure_id!: #{e.message}"
      nil
    end

    # The material carrying this id, or nil. This is the ONLY way the
    # rest of the plugin should look a material up.
    def self.find(id, model = nil)
      return nil unless USE_MATERIAL_IDS
      return nil if id.nil? || id.to_s.empty?
      model ||= Sketchup.active_model
      model.materials.each { |m| return m if id_of(m) == id.to_s }
      nil
    rescue StandardError
      nil
    end

    # Stamp every material in the model that has no id yet. Returns
    # [how many were stamped, how many already had one]. Safe to run
    # again and again - it only ever fills in blanks.
    def self.stamp_all!(model = nil)
      return [0, 0] unless USE_MATERIAL_IDS
      model ||= Sketchup.active_model
      made = 0
      had = 0
      model.materials.each do |m|
        if id_of(m)
          had += 1
        else
          made += 1 if ensure_id!(m, model)
        end
      end
      [made, had]
    rescue StandardError => e
      puts "[MaterialIds] stamp_all!: #{e.message}"
      [0, 0]
    end

    # Every id in the model, and whether any two materials share one.
    # A duplicate should be impossible; this is how we find out that it
    # happened rather than hearing about it from a wrong render.
    def self.audit(model = nil)
      model ||= Sketchup.active_model
      seen = {}
      dup = []
      none = []
      model.materials.each do |m|
        i = id_of(m)
        if i.nil?
          none << m.display_name
        elsif seen.key?(i)
          dup << [i, seen[i], m.display_name]
        else
          seen[i] = m.display_name
        end
      end
      { count: seen.length, without_id: none, duplicates: dup,
        next_number: model.get_attribute(COUNTER_DICT, COUNTER_KEY).to_i }
    rescue StandardError => e
      puts "[MaterialIds] audit: #{e.message}"
      { count: 0, without_id: [], duplicates: [], next_number: 0 }
    end
  end
end

# ---------------------------------------------------------------------
# A NEW MATERIAL IS STAMPED THE MOMENT IT IS BORN (2026-09-18)
#
# The plugin creates materials in 17 different places (walls, doors,
# windows, roofs, floors, ceilings, moldings, skylights...). Editing all
# 17 would mean touching seven files that work. SketchUp offers ONE
# choke point instead - it tells us when a material is added - so this
# is one hook in one file and no working code is touched at all.
#
# THE WRITE IS NOT DONE INSIDE THE CALLBACK. Changing the model from
# inside an observer is how SketchUp gets pushed over; the new material
# is put on a list and stamped a moment later, outside the callback.
# (Same reasoning as the crash note in CLAUDE.md: a crash leaves no
# backtrace, so we do not go near the known ways of causing one.)
#
# Kill switch: the same USE_MATERIAL_IDS. With it off the watcher is
# never attached and nothing is queued.
module InteriorPro
  module MaterialIds
    @pending = []
    @draining = false

    # PURE-ish: put a material on the list. No model change here.
    def self.note_new(mat)
      return 0 unless USE_MATERIAL_IDS
      return 0 if mat.nil?
      @pending << mat unless @pending.include?(mat)
      @pending.length
    end

    def self.pending_count
      @pending.length
    end

    def self.clear_pending!
      @pending = []
      0
    end

    # Stamp everything on the list and empty it. Returns how many got a
    # NEW id. A material that was deleted between being noted and being
    # stamped is dropped quietly.
    def self.drain!(model = nil)
      return 0 unless USE_MATERIAL_IDS
      list = @pending
      @pending = []
      model ||= (Sketchup.active_model rescue nil)
      return 0 if model.nil?
      made = 0
      list.each do |m|
        next if m.nil?
        next if m.respond_to?(:valid?) && !m.valid?
        next if id_of(m)
        made += 1 if ensure_id!(m, model)
      end
      made
    rescue StandardError => e
      puts "[MaterialIds] drain!: #{e.message}"
      0
    end

    # The hook itself. It only notes and asks to be called back later.
    if defined?(Sketchup::MaterialsObserver)
      class Watcher < Sketchup::MaterialsObserver
        def onMaterialAdd(_materials, material)
          return unless InteriorPro::MaterialIds::USE_MATERIAL_IDS
          InteriorPro::MaterialIds.note_new(material)
          InteriorPro::MaterialIds.ask_to_drain
        rescue StandardError => e
          puts "[MaterialIds] onMaterialAdd: #{e.message}"
        end
      end
    end

    # One timer at a time, however many materials arrive at once - a
    # whole roof build adds a handful in one go and they all ride the
    # same drain.
    def self.ask_to_drain
      return if @draining
      return unless defined?(UI) && UI.respond_to?(:start_timer)
      @draining = true
      UI.start_timer(0, false) do
        @draining = false
        drain!
      end
    rescue StandardError => e
      @draining = false
      puts "[MaterialIds] ask_to_drain: #{e.message}"
    end

    # Attach to a model, once. Attaching twice would stamp twice, which
    # is harmless (the second finds an id already there) but noisy.
    def self.watch!(model = nil)
      return false unless USE_MATERIAL_IDS
      return false unless defined?(Watcher)
      model ||= Sketchup.active_model
      return false if model.nil?
      @watched ||= {}
      # NOT model.guid: it changes when the model is saved, and then we
      # thought we had never attached and attached a SECOND observer
      # (2026-09-18 - watching? flipped to false right after a save).
      # The Model object itself lives as long as the model is open.
      key = model.object_id
      return false if @watched[key]
      model.materials.add_observer(Watcher.new)
      @watched[key] = true
      true
    rescue StandardError => e
      puts "[MaterialIds] watch!: #{e.message}"
      false
    end

    def self.watching?(model = nil)
      model ||= (Sketchup.active_model rescue nil)
      return false if model.nil?
      !!(@watched && @watched[model.object_id])
    end
  end
end

# A model that is OPENED later needs the same watcher.
if defined?(Sketchup::AppObserver) && !defined?(InteriorPro::MaterialIds::AppWatch)
  module InteriorPro
    module MaterialIds
      class AppWatch < Sketchup::AppObserver
        def onOpenModel(model)
          InteriorPro::MaterialIds.watch!(model)
        rescue StandardError
          nil
        end

        def onNewModel(model)
          InteriorPro::MaterialIds.watch!(model)
        rescue StandardError
          nil
        end
      end
    end
  end
  begin
    unless InteriorPro::MaterialIds.instance_variable_get(:@app_watched)
      Sketchup.add_observer(InteriorPro::MaterialIds::AppWatch.new)
      InteriorPro::MaterialIds.instance_variable_set(:@app_watched, true)
    end
  rescue StandardError => e
    puts "[MaterialIds] app observer: #{e.message}"
  end
end

begin
  InteriorPro::MaterialIds.watch!
rescue StandardError
  nil
end

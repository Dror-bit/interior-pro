# Interior Pro - Door Handle Library
# Scans assets handle folders (.skp files) and loads them as Components
# on demand (one definition per model, reused across doors).

module InteriorPro
  module DoorHandles

    HANDLE_DIRS = {
      'interior' => 'INTERIOR DOOR HANDLES',
      'closet'   => 'CLOSET DOOR HANDLES',
      'front'    => 'FRONT DOOR HANDLES'
    }.freeze unless const_defined?(:HANDLE_DIRS, false)

    def self.assets_dir(kind = 'interior')
      File.join(InteriorPro::PLUGIN_DIR, 'assets',
                HANDLE_DIRS[kind.to_s] || HANDLE_DIRS['interior'])
    end

    # Handle names (file base names, no extension), sorted. [] if folder missing.
    def self.handle_names(kind = 'interior')
      dir = assets_dir(kind)
      return [] unless Dir.exist?(dir)
      Dir.glob(File.join(dir, '*.skp')).map { |f| File.basename(f, '.skp') }.sort
    end

    # Load (or reuse) the ComponentDefinition for a handle. nil on failure.
    def self.definition_for(model, name, kind = 'interior')
      return nil if name.to_s.strip.empty? || name.to_s == 'none'
      def_name = "InteriorPro_Handle_#{kind}_#{name}"
      existing = model.definitions[def_name]
      return existing if existing && existing.valid?

      path = File.join(assets_dir(kind), "#{name}.skp")
      unless File.exist?(path)
        puts "[DoorHandles] file not found: #{path}"
        return nil
      end
      d = model.definitions.load(path, allow_newer: true)
      d.name = def_name if d && d.valid?
      d
    rescue StandardError => e
      puts "[DoorHandles] load failed for #{name}: #{e.message}"
      nil
    end

    # Bounding box report for orientation/size debugging.
    def self.report(kind = 'interior')
      model = Sketchup.active_model
      handle_names(kind).each do |name|
        d = definition_for(model, name, kind)
        if d
          b = d.bounds
          puts format('%-20s w=%.2f d=%.2f h=%.2f (in)', name,
                      b.width.to_f, b.height.to_f, b.depth.to_f)
        else
          puts "#{name}: FAILED"
        end
      end
      nil
    end

  end
end

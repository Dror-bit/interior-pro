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

    # Per-file calibration: shifts the anchor so the ROSE/PIVOT lands exactly
    # on the requested point. dx = along door width (+ = lever direction),
    # dz = up. Calibrated visually 2026-07-05 (debug_handles.rb scene).
    # rx = rotation (deg) around the horizontal X axis for files modeled
    # lying flat (facing up/down) instead of facing the door.
    HANDLE_FIT = {
      '2'         => { dx: 1.8125,  dz: -1.7875 },
      '3'         => { dx: 0.25,    dz: -1.5875, both: true },
      '4'         => { dx: 0.75,    dz: -1.15,   both: true },
      '5'         => { dx: 1.7375,  dz: -1.275, dy: -3.6875, yflip: true },
      'Door knob' => { dx: 0.0,     dz: 0.0, rx: 90 },
      '6'         => { dx: -0.8125, dz: 0.0 },
      'M - 7'     => { dx: 2.0625,  dz: 0.0, rx: 90 },
      'M-8'       => { dx: 2.25,    dz: 0.0, dy: -3.25, yflip: true }
    }.freeze

    def self.fit_offset(name)
      HANDLE_FIT[name.to_s] || { dx: 0.0, dz: 0.0 }
    end

    # true when the .skp already contains both sides of the handle.
    def self.both_sides?(name)
      !!fit_offset(name)[:both]
    end

    # Complete "fit" transform for a handle definition: optional lay-flat
    # rotation, front-back mirror, anchor on the pivot, base pressed to the
    # door plane. Shared by DoorTool and the calibration scene.
    def self.fit_transform(hdef, name)
      off = fit_offset(name)
      rx = (off[:rx] || 0).to_f
      r = if rx.zero?
            Geom::Transformation.new
          else
            Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0),
                                          Geom::Vector3d.new(1, 0, 0),
                                          rx.degrees)
          end
      rb = Geom::BoundingBox.new
      8.times { |i| rb.add(hdef.bounds.corner(i).transform(r)) }
      if off[:yflip]
        # Front-back mirror around the component's OWN center (bounds stay
        # identical, so dx/dy/dz calibration is unaffected).
        cy = (rb.min.y + rb.max.y) / 2.0
        r = Geom::Transformation.translation(Geom::Vector3d.new(0, 2 * cy, 0)) *
            Geom::Transformation.scaling(1, -1, 1) * r
      end
      ax = (rb.min.x < -0.1 && rb.max.x > 0.1) ? 0.0 : (rb.min.x + rb.max.x) / 2.0
      az = (rb.min.z < -0.1 && rb.max.z > 0.1) ? 0.0 : (rb.min.z + rb.max.z) / 2.0
      dx = (off[:dx] || 0).to_f
      dz = (off[:dz] || 0).to_f
      dy = (off[:dy] || 0).to_f  # depth: + pushes the handle OUT of the door
      if off[:both]
        # File contains BOTH sides of the handle: center it on the plane
        # (the door leaf sits in the gap between the two plates).
        cy = (rb.min.y + rb.max.y) / 2.0
        return Geom::Transformation.translation(
                 Geom::Vector3d.new(-ax + dx, cy + dy, -az + dz)
               ) * Geom::Transformation.scaling(1, -1, 1) * r
      end
      if off[:flip]
        # File modeled with its base at MIN Y: no mirror, press min Y to door.
        Geom::Transformation.translation(
          Geom::Vector3d.new(-ax + dx, -rb.min.y + dy, -az + dz)
        ) * r
      else
        Geom::Transformation.translation(
          Geom::Vector3d.new(-ax + dx, rb.max.y + dy, -az + dz)
        ) * Geom::Transformation.scaling(1, -1, 1) * r
      end
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

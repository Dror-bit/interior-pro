# Interior Pro - Molding Library
# Baseboard + crown profiles (dimensions from the Metrie catalog).

module InteriorPro
  module MoldingLibrary

    # --- User-modeled profiles (.skp with a single flat face, X=depth,
    # Z=up, back on the blue axis, bottom at origin) --------------------
    PROFILE_DIR = 'MOLDING PROFILES' unless const_defined?(:PROFILE_DIR, false)

    def self.profiles_dir
      File.join(InteriorPro::PLUGIN_DIR, 'assets', PROFILE_DIR)
    end

    def self.skp_names(prefix)
      return [] unless Dir.exist?(profiles_dir)
      Dir.glob(File.join(profiles_dir, "#{prefix}-*.skp"))
         .map { |f| File.basename(f, '.skp') }.sort
    end

    # Face outline from the .skp -> [[d, z], ...], normalized to x>=0, z>=0.
    # Supports a single flat face OR a 3D extruded body: the cross-section
    # is a pair of twin faces (opposite normals, equal area, same vertex
    # count); the pair with the most vertices is the curvy profile outline.
    def self.skp_profile_points(name)
      @skp_cache ||= {}
      return @skp_cache[name] if @skp_cache[name]
      path = File.join(profiles_dir, "#{name}.skp")
      return nil unless File.exist?(path)
      d = Sketchup.active_model.definitions.load(path, allow_newer: true)
      return nil unless d && d.valid?
      face, tr = pick_profile_face(d.entities)
      unless face
        puts "[MoldingLibrary] #{name}.skp has no face"
        return nil
      end
      pts3 = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
      # Auto-detect the profile plane: the two axes with the largest extents.
      # The larger of them is treated as height, the smaller as depth.
      ranges = {
        x: pts3.map(&:x).max - pts3.map(&:x).min,
        y: pts3.map(&:y).max - pts3.map(&:y).min,
        z: pts3.map(&:z).max - pts3.map(&:z).min
      }
      axes = ranges.sort_by { |_, v| -v }.first(2).map(&:first)
      h_axis = axes.max_by { |a| ranges[a] }
      d_axis = (axes - [h_axis]).first
      get = lambda { |p, a| a == :x ? p.x.to_f : (a == :y ? p.y.to_f : p.z.to_f) }
      pts = pts3.map { |p| [get.call(p, d_axis), get.call(p, h_axis)] }
      minx = pts.map(&:first).min
      minz = pts.map(&:last).min
      pts = pts.map { |x, z| [x - minx, z - minz] }
      @skp_cache[name] = orient_back_to_wall(pts)
    rescue StandardError => e
      puts "[MoldingLibrary] failed to read #{name}.skp: #{e.message}"
      nil
    end

    def self.clear_profile_cache!
      @skp_cache = {}
    end

    # Ensure the flat back of the profile faces the wall (d=0): the depth
    # extreme (d=0 vs d=max) with the longer total vertical straight run
    # is the back. If the back sits at d=max, mirror the profile.
    def self.orient_back_to_wall(pts)
      dmax = pts.map(&:first).max
      return pts if dmax <= 0.001
      tol = dmax * 0.02
      vrun = lambda do |dv|
        total = 0.0
        pts.each_with_index do |(x1, z1), i|
          x2, z2 = pts[(i + 1) % pts.length]
          total += (z2 - z1).abs if (x1 - dv).abs < tol && (x2 - dv).abs < tol
        end
        total
      end
      vrun.call(0.0) >= vrun.call(dmax) ? pts : pts.map { |x, z| [dmax - x, z] }
    end

    # Collect all faces recursively (nested groups/components included),
    # each with its accumulated transformation.
    def self.collect_faces(ents, tr = Geom::Transformation.new, out = [])
      ents.each do |e|
        case e
        when Sketchup::Face
          out << [e, tr]
        when Sketchup::Group
          collect_faces(e.entities, tr * e.transformation, out)
        when Sketchup::ComponentInstance
          collect_faces(e.definition.entities, tr * e.transformation, out)
        end
      end
      out
    end

    # Returns [face, transformation] of the profile cross-section.
    # Single face -> that face. 3D body -> one of the twin end-cap faces:
    # opposite normals, ~equal area, same vertex count; among candidate
    # pairs prefer the one with the most vertices (the profile outline).
    def self.pick_profile_face(ents)
      faces = collect_faces(ents)
      return nil if faces.empty?
      return faces.first if faces.length == 1
      best = nil
      faces.combination(2) do |(f1, t1), (f2, t2)|
        v1 = f1.outer_loop.vertices.length
        next unless v1 == f2.outer_loop.vertices.length
        next if best && v1 <= best[2]
        a1 = f1.area
        a2 = f2.area
        next if (a1 - a2).abs > [a1, a2].max * 0.01
        n1 = f1.normal.transform(t1).normalize
        n2 = f2.normal.transform(t2).normalize
        next unless n1.dot(n2) < -0.999
        best = [f1, t1, v1]
      end
      return [best[0], best[1]] if best
      # Fallback: the smallest face is most likely an end cap.
      f, t = faces.min_by { |fc, _| fc.area }
      [f, t]
    end

    # Names for the UI: user .skp files first, built-ins as fallback.
    # The flat (square) built-in is always offered, after the .skp profiles.
    def self.baseboard_names
      names = skp_names('BASE')
      names.any? ? names + [FLAT_BASE_NAME] : BASEBOARDS.keys
    end

    def self.crown_names
      names = skp_names('CROWN')
      names.any? ? names : CROWNS.keys
    end

    # Scale a profile proportionally so its height becomes `height` (in).
    # nil / <=0 height = keep the original size.
    def self.scale_profile(pts, height)
      return pts unless height && height.to_f > 0.01
      zmax = pts.map { |_, z| z }.max
      return pts if zmax <= 0.01
      s = height.to_f / zmax
      pts.map { |d, z| [d * s, z * s] }
    end

    def self.scaled_spec(spec, height)
      return spec unless height && height.to_f > 0.01
      s = height.to_f / spec[:h].to_f
      spec.merge(t: spec[:t].to_f * s, h: height.to_f)
    end

    # Profile polygon for a baseboard by name (.skp or built-in).
    # height (in, optional): proportional scale of the whole profile.
    def self.baseboard_profile_by_name(name, height = nil)
      pts = skp_profile_points(name)
      return scale_profile(pts, height) if pts
      spec = BASEBOARDS[name]
      spec ? baseboard_profile(scaled_spec(spec, height)) : nil
    end

    # Crown polygon hung from the ceiling (wall_h) by name.
    def self.crown_profile_by_name(name, wall_h, height = nil)
      pts = skp_profile_points(name)
      if pts
        pts = scale_profile(pts, height)
        zmax = pts.map { |_, z| z }.max
        return nil if zmax <= 0.01
        return pts.map { |d, z| [d, wall_h - zmax + z] }
      end
      spec = CROWNS[name]
      spec ? crown_profile(scaled_spec(spec, height), wall_h) : nil
    end

    # t = thickness (in), h = height (in)
    # points (optional): profile as [depth_frac, height_frac] pairs (0..1),
    # flat back at d=0. Overrides the default shape.
    FLAT_BASE_NAME = 'Flat' unless const_defined?(:FLAT_BASE_NAME, false)

    BASEBOARDS = {
      # Square flat baseboard - 3.5" x 0.5" rectangle.
      'Flat' => {
        t: 0.5, h: 3.5,
        points: [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]
      },
      # Metrie 1556324 — flat lower body, ogee step, upper band, beveled top.
      'Base 5-3/16"' => {
        t: 0.5625, h: 5.1875,
        points: [
          [0.0, 0.0], [1.0, 0.0],
          [1.0, 0.56],                                   # flat lower body
          [0.99, 0.58],
          [0.90, 0.598], [0.74, 0.608], [0.58, 0.622],   # deep cove in
          [0.50, 0.64], [0.49, 0.66],
          [0.55, 0.685], [0.66, 0.70], [0.73, 0.715],    # bead back out
          [0.74, 0.73],
          [0.58, 0.905],                                 # long back-leaning plane
          [0.50, 0.92], [0.42, 0.935],                   # small cove
          [0.44, 0.95],
          [0.30, 0.99], [0.28, 1.0],                     # eased top edge
          [0.0, 1.0]
        ]
      },
      'Base 4-1/8"' => { t: 0.5625, h: 4.125 }
    }.freeze unless const_defined?(:BASEBOARDS, false)

    CROWNS = {
      'Crown 5-1/4"'  => { t: 0.5625, h: 5.25 },
      'Crown 6-5/16"' => { t: 1.1875, h: 6.3125 }
    }.freeze unless const_defined?(:CROWNS, false)

    # Crown cross-section as [depth-from-wall, height] pairs, hung from the
    # ceiling (wall_h) at a ~45 deg spring angle.
    def self.crown_profile(spec, wall_h)
      w = spec[:h].to_f          # catalog face width
      proj = w * 0.71            # ceiling projection
      drop = w * 0.71            # wall drop
      t = spec[:t].to_f
      top = wall_h
      bot = wall_h - drop
      [
        [0.0, bot], [t, bot + drop * 0.10], [proj * 0.55, top - drop * 0.18],
        [proj * 0.85, top - drop * 0.10], [proj, top], [0.0, top]
      ]
    end

    # Baseboard cross-section as [depth-from-wall, height] pairs.
    # Flat back at d=0, flat bottom, eased colonial top.
    def self.baseboard_profile(spec)
      t = spec[:t].to_f
      h = spec[:h].to_f
      if spec[:points]
        return spec[:points].map { |df, zf| [df * t, zf * h] }
      end
      [
        [0.0, 0.0], [t, 0.0], [t, h * 0.72],
        [t * 0.85, h * 0.80], [t * 0.55, h * 0.86],
        [t * 0.55, h * 0.94], [t * 0.30, h], [0.0, h]
      ]
    end

  end
end

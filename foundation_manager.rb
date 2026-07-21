# Interior Pro - Foundation Manager
# Perimeter stem wall ("foundation belt") under the EXTERIOR walls: follows
# each exterior wall's mitered footprint (corners_xy) from z=0 DOWNWARD by a
# user-set height. Raised foundation = ~18"; slab look = 1-2".
# Interior walls never get foundation. Per-wall override via the wall's
# 'foundation_h' attribute (stage 2: per-area levels, e.g. garage at
# driveway level).
module InteriorPro
  module FoundationManager
    DEFAULT_HEIGHT = 18.0 unless const_defined?(:DEFAULT_HEIGHT, false)

    def self.exterior_walls
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
          (g.get_attribute('InteriorPro', 'wall_category') || 'exterior') == 'exterior'
      end
    end

    def self.foundations
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'foundation'
      end
    end

    def self.material(model)
      m = model.materials['InteriorPro_Foundation']
      return m if m
      m = model.materials.add('InteriorPro_Foundation')
      m.color = Sketchup::Color.new(150, 148, 145)
      m
    end

    # One foundation block under one exterior wall, following its mitered
    # corners (world space), from z=0 down by `height`.
    def self.build_for_wall!(wall, height)
      flat = wall.get_attribute('InteriorPro', 'corners_xy')
      return nil unless flat && flat.length == 8
      model = Sketchup.active_model
      xform = wall.transformation
      # Keep the transformed z: a wall lowered via base_z (garage unit,
      # 2026-07-18) carries its translation in the group transformation, so
      # the belt top starts at the wall's actual bottom.
      pts = flat.each_slice(2).map do |x, y|
        Geom::Point3d.new(x.to_f, y.to_f, 0).transform(xform)
      end
      uniq = pts.uniq { |p| [p.x.round(4), p.y.round(4)] }
      return nil if uniq.length < 3

      grp = model.entities.add_group
      grp.name = 'InteriorPro_Foundation'
      InteriorPro.assign_tag(grp, 'IP/Foundation')
      face = begin
        grp.entities.add_face(uniq)
      rescue StandardError
        nil
      end
      unless face
        grp.erase! if grp.valid?
        puts "[Foundation] add_face failed for wall #{wall.get_attribute('InteriorPro', 'id')}"
        return nil
      end
      # Extrude DOWNWARD so the top stays flush with the wall bottom (z=0).
      face.pushpull(face.normal.z > 0 ? -height : height)
      mat = material(model)
      grp.entities.grep(Sketchup::Face).each do |f|
        f.material = mat
        f.back_material = nil
      end

      grp.set_attribute('InteriorPro', 'type', 'foundation')
      grp.set_attribute('InteriorPro', 'host_wall_id', wall.get_attribute('InteriorPro', 'id'))
      grp.set_attribute('InteriorPro', 'height_in', height.to_f)
      grp.set_attribute('InteriorPro', 'id', format('fnd-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      grp
    rescue StandardError => e
      puts "[Foundation] build_for_wall!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end

    # Build (or rebuild) the whole belt. Per-wall 'foundation_h' attribute
    # overrides the global height when set (> 0).
    def self.build_all!(height = nil)
      model = Sketchup.active_model
      h_global = height.to_f
      h_global = DEFAULT_HEIGHT if h_global <= 0.05
      ws = exterior_walls
      if ws.empty?
        UI.messagebox('No exterior walls found')
        return 0
      end
      model.start_operation('InteriorPro Foundation', true)
      foundations.each { |f| f.erase! if f.valid? }
      n = 0
      ws.each do |w|
        h = w.get_attribute('InteriorPro', 'foundation_h')
        h = (h && h.to_f > 0.05) ? h.to_f : h_global
        n += 1 if build_for_wall!(w, h)
      end
      model.set_attribute('InteriorPro', 'foundation_height', h_global)
      model.commit_operation
      puts "[Foundation] built #{n}/#{ws.length} (height=#{h_global}\")"
      n
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Foundation] build_all! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    def self.remove_all!
      model = Sketchup.active_model
      fs = foundations
      return 0 if fs.empty?
      model.start_operation('InteriorPro Remove Foundation', true)
      fs.each { |f| f.erase! if f.valid? }
      model.commit_operation
      puts "[Foundation] removed #{fs.length} block(s)"
      fs.length
    end

    # Toolbar entry: ask height (remembers the last one), then build.
    def self.build_with_prompt!
      last = Sketchup.active_model.get_attribute('InteriorPro', 'foundation_height') || DEFAULT_HEIGHT
      res = UI.inputbox(['Foundation height (inches)'], [last.to_f], 'Interior Pro - Foundation')
      return unless res
      build_all!(res[0].to_f)
    end

    # Rebuild with the stored height — no-op when there is no foundation.
    def self.refresh!
      return 0 if foundations.empty?
      build_all!(Sketchup.active_model.get_attribute('InteriorPro', 'foundation_height'))
    end
  end
end

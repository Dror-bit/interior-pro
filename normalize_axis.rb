# normalize_axis.rb - put the rotation INSIDE the walls (2026-08-14)
#
# What went wrong
# ---------------
# straighten_axis.rb turned the building back onto the axes by turning each
# group's TRANSFORMATION. On screen that was right - and it quietly broke a
# rule the rest of the plugin leans on everywhere. floor_manager.rb says it
# out loud on line 498:
#
#   "assumes wall transformations are Z-translation only (true for top-level
#    walls + set_wall_base!), so local XY == world XY"
#
# A wall keeps start_x/start_y/end_x/end_y/corners_xy as LOCAL numbers, and
# most callers read them as if they were world numbers, because until now they
# always were. After my rotation the wall SAT in a new place while its numbers
# still described the old one - so the floors he built next came out at the
# old crooked angle. His walls were fine. Everything built FROM them was not.
#
# What this does
# --------------
# Nothing moves. For every group it takes whatever rotation is sitting in the
# transformation, applies it to the geometry inside and to the stored numbers,
# and leaves the transformation as a plain Z-translation again. World position
# before == world position after, to the thousandth of an inch - and it checks
# that itself rather than claiming it.
#
# After this, rebuild the floors. They will read straight numbers.
#
# Ruby Console:
#   load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/normalize_axis.rb'

module InteriorPro
  module NormalizeAxis
    ROT_TOL = 1.0e-9    # a transformation flatter than this is already clean
    CHECK_TOL = 0.001   # inches - how far anything may have moved. It may not.

    XY_KEYS = %w[start_x start_y end_x end_y].freeze

    def self.report_path
      File.join(File.dirname(__FILE__), 'normalize_report.txt')
    end

    # Is this transformation already nothing but a slide along Z?
    def self.z_only?(t)
      a = t.to_a
      (a[0] - 1.0).abs < ROT_TOL && a[1].abs < ROT_TOL &&
        a[4].abs < ROT_TOL && (a[5] - 1.0).abs < ROT_TOL &&
        a[12].abs < ROT_TOL && a[13].abs < ROT_TOL
    end

    # Every world point of a group, so "did anything move" is a measurement.
    def self.fingerprint(g)
      t = g.transformation
      pts = []
      ents = g.respond_to?(:definition) ? g.definition.entities : g.entities
      ents.grep(Sketchup::Edge).first(40).each do |e|
        pts << e.start.position.transform(t)
        pts << e.end.position.transform(t)
      end
      pts
    end

    def self.run
      model = Sketchup.active_model
      out = []
      out << '== put the rotation inside the groups =='
      out << "run #{Time.now}"
      out << ''

      subjects = model.active_entities.select do |e|
        (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid?
      end

      if subjects.empty?
        out << 'nothing at the top level.'
        File.write(report_path, out.join("\n"))
        UI.messagebox('nothing to do')
        return
      end

      tilted = subjects.reject { |g| z_only?(g.transformation) }
      out << format('%d objects at the top level, %d carrying a rotation.',
                    subjects.length, tilted.length)

      if tilted.empty?
        out << ''
        out << 'every transformation is already a plain Z-slide.'
        out << 'local XY == world XY everywhere. Nothing needed changing.'
        File.write(report_path, out.join("\n"))
        UI.messagebox('already clean - nothing changed')
        return
      end

      before = {}
      tilted.each { |g| before[g.entityID] = fingerprint(g) }

      model.start_operation('Bake rotation into walls', true)
      moved = 0
      attrs_done = 0
      begin
        tilted.each do |g|
          t  = g.transformation
          z0 = t.origin.z
          t_final = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z0))
          x = t_final.inverse * t          # the part that must move inside

          ents = g.respond_to?(:definition) ? g.definition.entities : g.entities
          ents.transform_entities(x, ents.to_a)
          g.transformation = t_final
          moved += 1

          # The stored numbers are local, and everything reads them as world.
          # Move them by the very same X, so the two agree again.
          next unless g.get_attribute('InteriorPro', 'type') == 'wall'

          sx = g.get_attribute('InteriorPro', 'start_x')
          sy = g.get_attribute('InteriorPro', 'start_y')
          ex = g.get_attribute('InteriorPro', 'end_x')
          ey = g.get_attribute('InteriorPro', 'end_y')
          if sx && sy && ex && ey
            s2 = Geom::Point3d.new(sx.to_f, sy.to_f, 0).transform(x)
            e2 = Geom::Point3d.new(ex.to_f, ey.to_f, 0).transform(x)
            g.set_attribute('InteriorPro', 'start_x', s2.x.to_f)
            g.set_attribute('InteriorPro', 'start_y', s2.y.to_f)
            g.set_attribute('InteriorPro', 'end_x',   e2.x.to_f)
            g.set_attribute('InteriorPro', 'end_y',   e2.y.to_f)
          end

          flat = g.get_attribute('InteriorPro', 'corners_xy')
          if flat.is_a?(Array) && flat.length == 8
            moved_flat = []
            flat.each_slice(2) do |px, py|
              p2 = Geom::Point3d.new(px.to_f, py.to_f, 0).transform(x)
              moved_flat << p2.x.to_f << p2.y.to_f
            end
            g.set_attribute('InteriorPro', 'corners_xy', moved_flat)
          end
          attrs_done += 1
        end
        model.commit_operation
      rescue => e
        model.abort_operation
        out << ''
        out << "FAILED: #{e.class}: #{e.message}"
        out << e.backtrace.first(5).join("\n")
        File.write(report_path, out.join("\n"))
        UI.messagebox('failed - see normalize_report.txt')
        return
      end

      out << format('%d objects re-based, %d walls had their numbers moved with them.',
                    moved, attrs_done)
      out << ''

      # ---- did anything actually move? It must not have. ----
      worst = 0.0
      tilted.each do |g|
        next unless g.valid?
        was = before[g.entityID] || []
        now = fingerprint(g)
        next if was.length != now.length
        was.each_with_index do |p, i|
          d = p.distance(now[i]).to_f
          worst = d if d > worst
        end
      end
      out << format('largest thing that moved: %.6f"', worst)
      out << if worst <= CHECK_TOL
               'nothing moved. The walls sit exactly where they sat.'
             else
               'SOMETHING MOVED - this is wrong. Ctrl+Z and tell him.'
             end

      # ---- and are the numbers telling the truth now? ----
      out << ''
      out << 'wall numbers vs where the wall really is:'
      gap = 0.0
      walls = model.active_entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
      end
      walls.each_with_index do |w, i|
        sx = w.get_attribute('InteriorPro', 'start_x')
        sy = w.get_attribute('InteriorPro', 'start_y')
        next unless sx && sy
        local = Geom::Point3d.new(sx.to_f, sy.to_f, 0)
        world = local.transform(w.transformation)
        d = Math.sqrt((world.x - local.x)**2 + (world.y - local.y)**2)
        gap = d if d > gap
        next if d <= CHECK_TOL
        id = (w.get_attribute('InteriorPro', 'id') || "##{i}").to_s[0, 13]
        out << format('  %-14s still %.4f" apart', id, d)
      end
      out << format('worst gap between a wall and its own numbers: %.6f"', gap)
      out << if gap <= CHECK_TOL
               'local XY == world XY again. Floors and roofs will read straight.'
             else
               'still out of step - do not build floors yet.'
             end

      leftover = model.active_entities.select do |e|
        (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
          e.valid? && !z_only?(e.transformation)
      end
      out << ''
      out << if leftover.empty?
               'no rotated transformations left at the top level.'
             else
               "#{leftover.length} object(s) still carry a rotation."
             end

      out << ''
      out << 'NEXT: the floors built while the numbers were stale are still at the'
      out << 'old angle. Delete them and build them again - they will read straight'
      out << 'numbers now.'

      File.write(report_path, out.join("\n"))
      UI.messagebox('done - normalize_report.txt written. Ctrl+Z undoes it.')
    rescue => e
      File.write(report_path, "CRASHED: #{e.class}: #{e.message}\n" +
                              e.backtrace.first(6).join("\n"))
      UI.messagebox('crashed - see normalize_report.txt')
    end
  end
end

InteriorPro::NormalizeAxis.run

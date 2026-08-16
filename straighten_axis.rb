# straighten_axis.rb - put the building back on the axes (2026-08-14)
#
# axis_report.txt measured his plan: four EXTERIOR walls making a perfect
# rectangle - every corner 90.0000 - and the whole rectangle sitting 0.2334
# degrees off the red/green axes. Two inches of drift over forty-one feet.
#
# So the shape is not broken and must not be re-cut. The whole thing is just
# turned, and turning it back is one rotation of everything at the top level -
# exactly what select-all + the Rotate tool does, only with the angle measured
# instead of eyeballed.
#
# The tilt is taken from the EXTERIOR walls, weighted by length, because they
# are the ones that agree with each other. Anything that disagrees with them
# is listed at the end - rotating cannot fix a wall that is crooked RELATIVE
# to the others, and pretending otherwise would hide it.
#
# One start_operation, so a single Ctrl+Z puts it all back.
#
# Ruby Console:
#   load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/straighten_axis.rb'

module InteriorPro
  module StraightenAxis
    TOL = 0.0005   # degrees - below this it is already straight

    def self.report_path
      File.join(File.dirname(__FILE__), 'straighten_report.txt')
    end

    # Signed distance from the nearest quarter turn, folded into -45..45.
    def self.off_axis(deg)
      o = deg % 90.0
      o -= 90.0 if o > 45.0
      o
    end

    def self.wall_line(w)
      t  = w.transformation
      sx = w.get_attribute('InteriorPro', 'start_x').to_f
      sy = w.get_attribute('InteriorPro', 'start_y').to_f
      ex = w.get_attribute('InteriorPro', 'end_x').to_f
      ey = w.get_attribute('InteriorPro', 'end_y').to_f
      s  = Geom::Point3d.new(sx, sy, 0).transform(t)
      e  = Geom::Point3d.new(ex, ey, 0).transform(t)
      dx = e.x - s.x
      dy = e.y - s.y
      len = Math.sqrt(dx * dx + dy * dy)
      return nil if len < 0.5
      [s, e, len, Math.atan2(dy, dx) * 180.0 / Math::PI]
    end

    def self.run
      model = Sketchup.active_model
      out   = []
      out << "== straighten the building onto the axes =="
      out << "run #{Time.now}"
      out << ""

      walls = (model.active_entities.grep(Sketchup::Group) +
               model.active_entities.grep(Sketchup::ComponentInstance)).select do |g|
        g.get_attribute('InteriorPro', 'type') == 'wall'
      end

      if walls.empty?
        out << "no walls in the active context - nothing to straighten."
        File.write(report_path, out.join("\n"))
        UI.messagebox('no walls found')
        return
      end

      ext = walls.select do |w|
        (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s == 'exterior'
      end
      ext = walls if ext.empty?

      # Length-weighted tilt of the exterior walls. A long wall states its
      # direction far more precisely than a short one, so it should count for
      # more; a plain average lets a 2ft stub argue with a 41ft wall.
      wsum = 0.0
      lsum = 0.0
      ext.each do |w|
        line = wall_line(w)
        next unless line
        wsum += off_axis(line[3]) * line[2]
        lsum += line[2]
      end

      if lsum <= 0
        out << "the exterior walls have no usable length."
        File.write(report_path, out.join("\n"))
        UI.messagebox('nothing measurable')
        return
      end

      tilt = wsum / lsum
      out << format("exterior walls measured: %d", ext.length)
      out << format("tilt found: %.4f degrees", tilt)

      if tilt.abs < TOL
        out << "already on the axes - nothing was changed."
        File.write(report_path, out.join("\n"))
        UI.messagebox('already straight - nothing changed')
        return
      end

      # Turn about the corner of the longest exterior wall, so the building
      # keeps a fixed point he can recognise instead of drifting somewhere new.
      anchor_wall = ext.max_by { |w| (wall_line(w) || [nil, nil, 0])[2] }
      pivot = (wall_line(anchor_wall) || [Geom::Point3d.new(0, 0, 0)])[0]
      pivot = Geom::Point3d.new(pivot.x, pivot.y, 0)

      subjects = model.active_entities.select do |e|
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end

      out << format("turning %d objects by %+.4f degrees", subjects.length, -tilt)
      out << format("about (%.2f, %.2f)", pivot.x, pivot.y)

      rot = Geom::Transformation.rotation(pivot, Geom::Vector3d.new(0, 0, 1),
                                          -tilt * Math::PI / 180.0)

      model.start_operation('Straighten to axes', true)
      begin
        subjects.each { |e| e.transformation = rot * e.transformation }
        model.commit_operation
      rescue => e
        model.abort_operation
        out << ""
        out << "FAILED: #{e.class}: #{e.message}"
        out << e.backtrace.first(5).join("\n")
        File.write(report_path, out.join("\n"))
        UI.messagebox("failed - see straighten_report.txt")
        return
      end

      # Measure again AFTER the rotation. Claiming it worked is not the same
      # as checking, and this file has been wrong before.
      out << ""
      out << "after the turn:"
      out << format("%-14s %-9s %-10s %-8s %s", 'id', 'length', 'off-axis', 'cat', 'note')
      out << "-" * 74
      worst_ext = 0.0
      odd = []
      walls.each_with_index do |w, i|
        line = wall_line(w)
        next unless line
        off = off_axis(line[3])
        cat = (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
        id  = (w.get_attribute('InteriorPro', 'id') || "##{i}").to_s[0, 13]
        note = if off.abs < TOL
                 'on the axis'
               else
                 format('%.3f" adrift over its length',
                        line[2] * Math.tan(off.abs * Math::PI / 180.0))
               end
        worst_ext = off.abs if cat == 'exterior' && off.abs > worst_ext
        odd << [id, off, cat] if off.abs >= TOL
        out << format("%-14s %-9s %-10s %-8s %s",
                      id, format('%.2f"', line[2]), format('%+.4f', off), cat[0, 7], note)
      end

      out << ""
      out << format("worst EXTERIOR wall is now %.4f degrees off.", worst_ext)
      if odd.empty?
        out << "every wall is on an axis. Done."
      else
        out << ""
        out << "STILL NOT ON AN AXIS - and a rotation cannot fix these, because"
        out << "they are crooked relative to the exterior walls, not with them:"
        odd.each { |o| out << format("  %-14s %+.4f  (%s)", o[0], o[1], o[2]) }
        out << "each of these has to be turned on its own, one at a time."
      end

      File.write(report_path, out.join("\n"))
      UI.messagebox("done - straighten_report.txt written. Ctrl+Z undoes it.")
    rescue => e
      File.write(report_path, "CRASHED: #{e.class}: #{e.message}\n" +
                              e.backtrace.first(6).join("\n"))
      UI.messagebox("crashed - see straighten_report.txt")
    end
  end
end

InteriorPro::StraightenAxis.run

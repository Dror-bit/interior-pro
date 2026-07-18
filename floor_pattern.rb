# Interior Pro - Floor Pattern (stage 1: Tile + Straight planks)
# Revit-style split (2026-07-18): the RENDER texture and the DOCUMENTATION
# pattern are independent. This module builds the documentation layer —
# real-scale layout LINES (tile grid / plank runs) on top of each floor,
# clipped to the room boundary, in their own group on tag IP/FloorPatterns
# (turn the tag off for clean modeling, on for contractor plans).
#
# Floor attributes read (stored on the floor group):
#   pattern         - 'None' / 'Tile' / 'Straight'  (Herringbone/Chevron: stage 2)
#   unit_w          - tile width / plank width (inches)
#   unit_l          - tile length / plank length (inches)
#   pattern_ox/oy   - origin offset along the pattern axes (inches)
#   pattern_angle   - rotation in degrees (0 = along red axis)
#   pattern_center  - true: grid centered on the room so edge cuts balance
#                     (half tile top / half bottom), like Revit align-center.
module InteriorPro
  module FloorPattern
    PATTERNS = ['None', 'Tile', 'Straight'].freeze unless const_defined?(:PATTERNS, false)
    LINE_Z = 0.05 unless const_defined?(:LINE_Z, false) # above floor top (z=0)

    def self.patterns_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'floor_pattern'
      end
    end

    def self.remove_for_floor!(floor_id)
      patterns_in_model.each do |g|
        g.erase! if g.valid? && g.get_attribute('InteriorPro', 'floor_id') == floor_id
      end
    end

    # Rebuild patterns for all floors; remove orphan pattern groups.
    def self.refresh_all!
      floors = InteriorPro::FloorManager.floors_in_model
      floor_ids = floors.map { |f| f.get_attribute('InteriorPro', 'id') }
      patterns_in_model.each do |g|
        g.erase! if g.valid? && !floor_ids.include?(g.get_attribute('InteriorPro', 'floor_id'))
      end
      n = 0
      floors.each { |f| n += 1 if build_for_floor!(f) }
      puts "[FloorPattern] #{n} pattern(s)" if n > 0
      n
    rescue StandardError => e
      puts "[FloorPattern] refresh_all! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    def self.build_for_floor!(floor)
      fid = floor.get_attribute('InteriorPro', 'id')
      remove_for_floor!(fid)
      pattern = (floor.get_attribute('InteriorPro', 'pattern') || 'None').to_s
      return false if pattern == 'None' || pattern.empty?
      unless PATTERNS.include?(pattern)
        puts "[FloorPattern] pattern '#{pattern}' not supported yet"
        return false
      end

      room = InteriorPro::RoomManager.rooms_in_model.find do |r|
        r.get_attribute('InteriorPro', 'id') == floor.get_attribute('InteriorPro', 'room_id')
      end
      return false unless room
      flat = room.get_attribute('InteriorPro', 'boundary_xy')
      return false unless flat && flat.length >= 6
      poly = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0) }

      w = floor.get_attribute('InteriorPro', 'unit_w').to_f
      l = floor.get_attribute('InteriorPro', 'unit_l').to_f
      w = 12.0 if w <= 0.25
      l = (pattern == 'Straight' ? 48.0 : w) if l <= 0.25
      ox = floor.get_attribute('InteriorPro', 'pattern_ox').to_f
      oy = floor.get_attribute('InteriorPro', 'pattern_oy').to_f
      ang = floor.get_attribute('InteriorPro', 'pattern_angle').to_f * Math::PI / 180.0
      centered = floor.get_attribute('InteriorPro', 'pattern_center') ? true : false

      u_axis = Geom::Vector3d.new(Math.cos(ang), Math.sin(ang), 0)
      v_axis = Geom::Vector3d.new(-Math.sin(ang), Math.cos(ang), 0)
      pu = ->(p) { p.x * u_axis.x + p.y * u_axis.y }
      pv = ->(p) { p.x * v_axis.x + p.y * v_axis.y }
      us = poly.map { |p| pu.call(p) }
      vs = poly.map { |p| pv.call(p) }
      u_min = us.min
      u_max = us.max
      v_min = vs.min
      v_max = vs.max

      cen = InteriorPro::RoomManager.centroid(poly)
      # Grid origin per axis: centered -> a cell midline passes through the
      # room centroid (edge cuts balance); else anchored at the room's
      # bounding box corner. User offsets shift on top of either.
      u0 = (centered ? pu.call(cen) - l / 2.0 : u_min) + ox
      v0 = (centered ? pv.call(cen) - w / 2.0 : v_min) + oy
      u_start = u0 - ((u0 - u_min) / l).ceil * l
      v_start = v0 - ((v0 - v_min) / w).ceil * w

      model = Sketchup.active_model
      grp = model.entities.add_group
      grp.name = 'InteriorPro_FloorPattern'
      InteriorPro.assign_tag(grp, 'IP/FloorPatterns')
      ge = grp.entities

      # Lines along u (the plank/tile rows), spaced w apart along v.
      vv = v_start
      rows = []
      while vv <= v_max + 0.001
        rows << vv
        draw_clipped_line!(ge, v_axis, vv, u_axis, poly) if vv > v_min + 0.001 && vv < v_max - 0.001
        vv += w
      end

      # Cross joints along v, spaced l apart along u.
      if pattern == 'Tile'
        uu = u_start
        while uu <= u_max + 0.001
          draw_clipped_line!(ge, u_axis, uu, v_axis, poly) if uu > u_min + 0.001 && uu < u_max - 0.001
          uu += l
        end
      elsif pattern == 'Straight'
        # Running-bond stagger: odd rows shift by half a plank length.
        rows.each_with_index do |row_v, ri|
          band = [row_v, row_v + w]
          next if band[0] >= v_max || band[1] <= v_min
          uu = u_start + (ri.odd? ? l / 2.0 : 0.0) - l
          while uu <= u_max + 0.001
            draw_clipped_segment!(ge, u_axis, uu, v_axis, poly, band) if uu > u_min + 0.001 && uu < u_max - 0.001
            uu += l
          end
        end
      end

      if grp.valid? && ge.length.zero?
        grp.erase!
        return false
      end
      grp.set_attribute('InteriorPro', 'type', 'floor_pattern')
      grp.set_attribute('InteriorPro', 'floor_id', fid)
      grp.set_attribute('InteriorPro', 'room_id', floor.get_attribute('InteriorPro', 'room_id'))
      true
    rescue StandardError => e
      puts "[FloorPattern] build_for_floor!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    # Infinite line at offset `off` along `off_axis`, running along `dir`;
    # clipped to the polygon (even-odd), drawn as edges at LINE_Z.
    # Returns the inside intervals as [t0, t1] pairs along `dir`.
    def self.line_poly_intervals(off_axis, off, dir, poly)
      base_x = off_axis.x * off
      base_y = off_axis.y * off
      ts = []
      n = poly.length
      n.times do |i|
        p = poly[i]
        q = poly[(i + 1) % n]
        ex = q.x - p.x
        ey = q.y - p.y
        denom = dir.x * ey - dir.y * ex
        next if denom.abs < 1e-9
        rx = p.x - base_x
        ry = p.y - base_y
        t = (rx * ey - ry * ex) / denom
        s = (rx * dir.y - ry * dir.x) / denom
        ts << t if s >= 0.0 && s < 1.0
      end
      ts.sort.each_slice(2).select { |pair| pair.length == 2 && pair[1] - pair[0] > 0.1 }
    end

    def self.draw_clipped_line!(ge, off_axis, off, dir, poly)
      base_x = off_axis.x * off
      base_y = off_axis.y * off
      line_poly_intervals(off_axis, off, dir, poly).each do |t0, t1|
        ge.add_edges(
          Geom::Point3d.new(base_x + dir.x * t0, base_y + dir.y * t0, LINE_Z),
          Geom::Point3d.new(base_x + dir.x * t1, base_y + dir.y * t1, LINE_Z)
        )
      end
    end

    # Like draw_clipped_line!, but only within [band0, band1] along the line.
    def self.draw_clipped_segment!(ge, off_axis, off, dir, poly, band)
      base_x = off_axis.x * off
      base_y = off_axis.y * off
      line_poly_intervals(off_axis, off, dir, poly).each do |t0, t1|
        a = [t0, band[0]].max
        b = [t1, band[1]].min
        next if b - a < 0.1
        ge.add_edges(
          Geom::Point3d.new(base_x + dir.x * a, base_y + dir.y * a, LINE_Z),
          Geom::Point3d.new(base_x + dir.x * b, base_y + dir.y * b, LINE_Z)
        )
      end
    end
  end
end

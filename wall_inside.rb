# encoding: utf-8
# Interior Pro - a wall that ends up INSIDE the house turns interior, and back
# (2026-10-20).
#
# His words (2026-10-19): "את הקיר שהיה קיר חוץ ועכשיו הוא בתוך הבית המערכת
# צריכה להפוך אוטומטית לקיר פנים — וכך גם הפוך." And his picture (2026-10-20
# 13:46): when a room is added on the outside of the house, only the stretch of
# the old outside wall that now has a room on BOTH sides turns interior (blue);
# the rest stays exterior and makes a real corner with the new outside walls
# (green).
#
# How: runs inside RoomManager.sync_rooms!, right after the rooms are found.
#   * an EXTERIOR wall with a room on both sides along a stretch of it: the
#     wall is cut where that stretch starts/ends (at the end of the new wall
#     that meets it), and the inside piece turns interior;
#   * a wall this code turned interior ('auto_interior') that no longer has a
#     room on both sides turns exterior again.
# The corners are re-joined (wall_tool.rb tee_at_existing_corner!: the
# exterior piece miters with the new outside wall, the interior piece stops at
# its face). Nothing is moved or resized: same thickness, same line.
# Never cuts through a door/window, and leaves alone a wall that carries tile
# or a niche (that wall is reported, not touched).
#
# Kill switch: InteriorPro::WallInside::USE_AUTO_INTERIOR = false
module InteriorPro
  module WallInside
    USE_AUTO_INTERIOR = true unless const_defined?(:USE_AUTO_INTERIOR, false)
    PROBE = 1.5 unless const_defined?(:PROBE, false)     # how far past the face we look for a room
    STEP = 2.0 unless const_defined?(:STEP, false)       # inches between samples along the wall

    module_function

    def a(g, k)
      g.get_attribute('InteriorPro', k)
    end

    def cat(g)
      (a(g, 'wall_category') || 'exterior').to_s
    end

    def trace(msg)
      puts "[WallInside] #{msg}"
      InteriorPro::WallTool.new.send(:wall_trace, "INSIDE #{msg}") if defined?(InteriorPro::WallTool)
    rescue StandardError
      nil
    end

    # Drawn line in world, flattened: [s, e, unit, len]
    def line_of(w)
      t = w.transformation
      s = Geom::Point3d.new(a(w, 'start_x').to_f, a(w, 'start_y').to_f, 0).transform(t)
      e = Geom::Point3d.new(a(w, 'end_x').to_f, a(w, 'end_y').to_f, 0).transform(t)
      s = Geom::Point3d.new(s.x, s.y, 0)
      e = Geom::Point3d.new(e.x, e.y, 0)
      v = e - s
      len = v.length
      return nil if len < 1.0
      v.normalize!
      [s, e, v, len]
    end

    def inside?(poly, x, y)
      inside = false
      j = poly.length - 1
      poly.each_with_index do |pi, i|
        pj = poly[j]
        if ((pi.y > y) != (pj.y > y)) &&
           (x < (pj.x - pi.x) * (y - pi.y) / ((pj.y - pi.y).nonzero? || 1e-12) + pi.x)
          inside = !inside
        end
        j = i
      end
      inside
    end

    # Stretches [u0, u1] (from the drawn start) where BOTH sides have a room.
    def both_sides(w, polys)
      ln = line_of(w)
      return [] unless ln
      s, _e, v, len = ln
      th = a(w, 'thickness').to_f
      cl = InteriorPro::RoomManager.centerline(w)
      return [] unless cl
      c0 = cl[:s]
      n = Geom::Vector3d.new(-v.y, v.x, 0)
      off = th / 2.0 + PROBE
      # the centreline's offset from the drawn line, so the probes sit just past each FACE
      d0 = (c0 - s)
      shift = d0.x * n.x + d0.y * n.y
      out = []
      cur = nil
      u = STEP / 2.0
      while u < len
        bx = s.x + v.x * u + n.x * shift
        by = s.y + v.y * u + n.y * shift
        l = polys.any? { |p| inside?(p, bx + n.x * off, by + n.y * off) }
        r = polys.any? { |p| inside?(p, bx - n.x * off, by - n.y * off) }
        if l && r
          cur ||= [u - STEP / 2.0, u]
          cur[1] = u + STEP / 2.0
        elsif cur
          out << cur
          cur = nil
        end
        u += STEP
      end
      out << cur if cur
      out.map { |x, y| [[x, 0.0].max, [y, len].min] }
    end

    # Where along w another wall's end touches it (u from w's drawn start).
    def touch_points(w, walls)
      ln = line_of(w)
      return [] unless ln
      s, _e, v, len = ln
      th = a(w, 'thickness').to_f
      out = []
      walls.each do |o|
        next if o == w
        ol = line_of(o)
        next unless ol
        lim = th + a(o, 'thickness').to_f + 0.5
        [ol[0], ol[1]].each do |p|
          d = p - s
          u = d.x * v.x + d.y * v.y
          next if u < 0.5 || u > len - 0.5
          perp = (d.x * v.y - d.y * v.x).abs
          out << u if perp <= lim
        end
      end
      out
    end

    def snap(u, len, touches, th)
      tol = 2.0 * th + 2.0
      return 0.0 if u <= tol
      return len if u >= len - tol
      best = touches.min_by { |t| (t - u).abs }
      best && (best - u).abs <= tol ? best : nil
    end

    def blocked?(w, u)
      InteriorPro::WallTool.read_door_openings(w).any? { |o| (o[:t] - u).abs < o[:width] / 2.0 + 1.0 }
    end

    def has_tile?(w, model)
      id = a(w, 'id').to_s
      return true if Array(a(w, 'niches')).any? && a(w, 'niches').to_s != '[]'
      model.entities.to_a.any? do |e|
        e.valid? && e.respond_to?(:get_attribute) && %w[tile_wall].include?(a(e, 'type').to_s) &&
          (a(e, 'wall_id').to_s == id || a(e, 'host_wall_id').to_s == id)
      end
    end

    # Electrical / plumbing hang on a wall by id + u. After a split, move each
    # one onto the piece it is on now.
    def rehome!(old_id, pieces, model)
      model.entities.to_a.each do |e|
        next unless e.valid? && e.respond_to?(:get_attribute)
        next unless %w[electrical fixture].include?(a(e, 'type').to_s)
        next unless a(e, 'host_wall_id').to_s == old_id
        c = e.bounds.center
        best = pieces.min_by do |pc|
          ln = line_of(pc)
          next 1e9 unless ln
          d = Geom::Point3d.new(c.x, c.y, 0) - ln[0]
          u = d.x * ln[2].x + d.y * ln[2].y
          u < 0 ? -u : (u > ln[3] ? u - ln[3] : 0.0)
        end
        next unless best
        e.set_attribute('InteriorPro', 'host_wall_id', a(best, 'id').to_s)
        begin
          fr = InteriorPro::TileWall.frame_for(best, a(e, 'side').to_s)
          if fr && defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:box_in_frame)
            u0, u1, = InteriorPro::ElectricalLibrary.box_in_frame(e, e.transformation, fr)
            e.set_attribute('InteriorPro', 'u_in', (u0.to_f + u1.to_f) / 2.0) if u0 && u1
          end
        rescue StandardError => ex
          trace("u of #{a(e, 'type')} not updated: #{ex.message}")
        end
      end
    end

    # Turn a wall interior/exterior and re-cut its corners and its neighbours'.
    def convert!(w, to, model)
      model.start_operation(to == 'interior' ? 'Wall Turns Interior' : 'Wall Turns Exterior', true)
      w.set_attribute('InteriorPro', 'wall_category', to)
      if to == 'interior'
        w.set_attribute('InteriorPro', 'auto_interior', true)
        w.set_attribute('InteriorPro', 'side_a_color', '#ffffff') unless a(w, 'side_a_color')
        w.set_attribute('InteriorPro', 'side_b_color', '#ffffff') unless a(w, 'side_b_color')
      else
        w.delete_attribute('InteriorPro', 'auto_interior')
      end
      wt = InteriorPro::WallTool.new
      ln = line_of(w)
      ends = ln ? [ln[0], ln[1]] : []
      wt.square_corner!(w, :start)
      wt.square_corner!(w, :end)
      wt.join_corners(w, model, allow_centerline_fallback: true)
      # the walls at its two ends see a different neighbour now
      model.entities.grep(Sketchup::Group).each do |o|
        next if o == w || !o.valid? || a(o, 'type') != 'wall'
        next unless (a(o, 'level') || 1).to_i == (a(w, 'level') || 1).to_i
        ol = line_of(o)
        next unless ol
        next unless ends.any? { |p| p.distance(ol[0]) < 0.01 || p.distance(ol[1]) < 0.01 }
        wt.join_corners(o, model, allow_centerline_fallback: true)
      end
      model.commit_operation
      trace("#{a(w, 'id').to_s[0, 8]} -> #{to}")
    rescue StandardError => e
      model.abort_operation rescue nil
      trace("convert failed: #{e.message} #{e.backtrace.first(3).inspect}")
    end

    # Called from RoomManager.sync_rooms! with the rooms just found.
    # Returns true when it changed a wall (the caller finds the rooms again).
    def update!(detected, model = Sketchup.active_model)
      return false unless USE_AUTO_INTERIOR
      return false if @busy
      @busy = true
      changed = false
      detected.group_by { |r| (r[:level] || 1).to_i }.each do |lv, rooms|
        polys = rooms.map { |r| r[:boundary] }.compact
        walls = InteriorPro::RoomManager.wall_list(lv).reject { |w| InteriorPro::WallTool.curved_wall?(w) }
        walls.each do |w|
          next unless w.valid?
          ln = line_of(w)
          next unless ln
          len = ln[3]
          th = a(w, 'thickness').to_f
          spans = both_sides(w, polys).select { |x, y| y - x >= 2.0 * th }
          if cat(w) == 'interior'
            next unless a(w, 'auto_interior')
            cover = spans.sum { |x, y| y - x }
            if cover < len * 0.5
              convert!(w, 'exterior', model)
              changed = true
            end
            next
          end
          next if spans.empty?
          x, y = spans.max_by { |p, q| q - p }
          touches = touch_points(w, walls)
          u0 = snap(x, len, touches, th)
          u1 = snap(y, len, touches, th)
          unless u0 && u1 && u1 - u0 >= 2.0 * th
            trace("#{a(w, 'id').to_s[0, 8]}: rooms on both sides #{x.round(1)}..#{y.round(1)} but no wall end to cut at - left as is")
            next
          end
          if u0 <= 0.0 && u1 >= len
            convert!(w, 'interior', model)
            changed = true
            next
          end
          if has_tile?(w, model)
            trace("#{a(w, 'id').to_s[0, 8]}: has tile or a niche - not cut, left exterior")
            next
          end
          cuts = [u0, u1].reject { |u| u <= 0.0 || u >= len }
          if cuts.any? { |u| blocked?(w, u) }
            trace("#{a(w, 'id').to_s[0, 8]}: the cut would go through a door/window - left as is")
            next
          end
          old_id = a(w, 'id').to_s
          trace("#{old_id[0, 8]}: rooms on both sides #{u0.round(1)}..#{u1.round(1)} of #{len.round(1)} - cutting")
          pieces = []
          rest = w
          off = 0.0
          cuts.sort.each do |u|
            r = InteriorPro::WallSplitTool.split_wall!(rest, u - off, sync: false, quiet: true)
            break unless r
            pieces << r[0]
            rest = r[1]
            off = u
          end
          pieces << rest if rest&.valid?
          next if pieces.size < 2
          rehome!(old_id, pieces, model)
          inner = pieces.find do |pc|
            pl = line_of(pc)
            next false unless pl
            mid = Geom::Point3d.new((pl[0].x + pl[1].x) / 2.0, (pl[0].y + pl[1].y) / 2.0, 0)
            d = mid - ln[0]
            um = d.x * ln[2].x + d.y * ln[2].y
            um > u0 && um < u1
          end
          convert!(inner, 'interior', model) if inner
          changed = true
        end
      end
      changed
    rescue StandardError => e
      trace("update! failed: #{e.class}: #{e.message} #{e.backtrace.first(4).inspect}")
      changed
    ensure
      @busy = false
    end
  end
end

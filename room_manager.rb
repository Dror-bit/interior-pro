# room_manager.rb — Stage A: detect closed wall loops and report rooms.
# No geometry is created yet — detection + console report only.
# Boundary is computed at the INTERIOR wall faces (net), per CONTRACT_2D.md 4.4.
module InteriorPro
  module RoomManager
    CORNER_TOL = 1.5 unless const_defined?(:CORNER_TOL, false) # inches

    def self.wall_list
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
      end
    end

    # World-space centerline of a wall (flattened to z=0), derived from the
    # drawn endpoints + anchor, same offset convention as build_wall_group.
    def self.centerline(w)
      t  = w.transformation
      sx = w.get_attribute('InteriorPro', 'start_x')
      sy = w.get_attribute('InteriorPro', 'start_y')
      ex = w.get_attribute('InteriorPro', 'end_x')
      ey = w.get_attribute('InteriorPro', 'end_y')
      return nil if sx.nil? || ex.nil?

      s = Geom::Point3d.new(sx.to_f, sy.to_f, 0).transform(t)
      e = Geom::Point3d.new(ex.to_f, ey.to_f, 0).transform(t)
      s = Geom::Point3d.new(s.x, s.y, 0)
      e = Geom::Point3d.new(e.x, e.y, 0)

      th = w.get_attribute('InteriorPro', 'thickness').to_f
      anchor = (w.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      h = anchor == 'center' ? 'center' : (anchor.split('-')[1] || 'center')

      dx = e.x - s.x
      dy = e.y - s.y
      len = Math.sqrt(dx * dx + dy * dy)
      return nil if len < 0.1

      nx = -dy / len * th / 2.0
      ny =  dx / len * th / 2.0
      case h
      when 'left'
        v = Geom::Vector3d.new(nx, ny, 0)
        s += v; e += v
      when 'right'
        v = Geom::Vector3d.new(-nx, -ny, 0)
        s += v; e += v
      end
      { s: s, e: e, th: th, w: w }
    rescue StandardError => ex2
      puts "[Rooms] centerline failed: #{ex2.message}"
      nil
    end

    # Corner tolerance is thickness-dependent: at a 90-degree corner the two
    # centerline endpoints diverge by sqrt((tA/2)^2 + (tB/2)^2) even when the
    # drawn endpoints coincide. tol = 0.75*(tA+tB)/2 + 0.5 covers that.
    def self.node_id(nodes, pt, th)
      nodes.each_with_index do |n, i|
        tol = 0.75 * (n[:th] + th) / 2.0 + 0.5
        tol = CORNER_TOL if tol < CORNER_TOL
        return i if n[:pt].distance(pt) < tol
      end
      nodes << { pt: Geom::Point3d.new(pt.x, pt.y, 0), th: th }
      nodes.length - 1
    end

    def self.build_graph(segs)
      segs = split_at_tees(segs)
      raw = []
      edges = []
      segs.each do |sg|
        a = node_id(raw, sg[:s], sg[:th])
        b = node_id(raw, sg[:e], sg[:th])
        next if a == b
        edges << { a: a, b: b, th: sg[:th], wall: sg[:w] }
      end
      merge_dangling_nodes!(raw, edges)
      [raw.map { |n| n[:pt] }, edges]
    end

    # Butt-at-corner fix (2026-07-17): an interior wall butting an exterior
    # wall's FACE near a corner leaves its centerline endpoint up to about
    # th_exterior away from the corner node — beyond node_id's tolerance —
    # so the node dangles (degree 1), the loop never closes and the room is
    # not detected. Merge each dangling node into its nearest node when the
    # distance fits a larger, butt-aware tolerance. Only degree-1 nodes are
    # touched; healthy corners are never re-clustered.
    def self.merge_dangling_nodes!(raw, edges)
      loop do
        deg = Hash.new(0)
        edges.each do |e|
          deg[e[:a]] += 1
          deg[e[:b]] += 1
        end
        merged = false
        raw.each_index do |i|
          next unless deg[i] == 1
          best = nil
          best_d = 1_000_000.0
          raw.each_index do |j|
            next if j == i
            next if deg[j].zero? # already merged away
            d = raw[i][:pt].distance(raw[j][:pt])
            if d < best_d
              best_d = d
              best = j
            end
          end
          next unless best
          tol = (raw[i][:th] + raw[best][:th]) * 0.75 + 0.5
          next if best_d > tol
          edges.each do |e|
            e[:a] = best if e[:a] == i
            e[:b] = best if e[:b] == i
          end
          edges.reject! { |e| e[:a] == e[:b] }
          merged = true
          break
        end
        break unless merged
      end
    end

    # Butt/T model (2026-07-16): a wall whose endpoint touches the MIDDLE of
    # another wall (end-on-face) shares no graph node with it, so loops
    # through the touched wall never close (additions/closets were not
    # detected as rooms). Split the touched wall's segment at each such
    # contact point so the T-junction becomes a real node.
    def self.split_at_tees(segs)
      cuts = {}
      segs.each do |sg|
        [sg[:s], sg[:e]].each do |p|
          segs.each_with_index do |o, j|
            next if o.equal?(sg)
            dx = o[:e].x - o[:s].x
            dy = o[:e].y - o[:s].y
            len = Math.sqrt(dx * dx + dy * dy)
            next if len < 1.0
            ux = dx / len
            uy = dy / len
            t = (p.x - o[:s].x) * ux + (p.y - o[:s].y) * uy
            end_tol = 0.75 * (sg[:th] + o[:th]) / 2.0 + 0.5
            next if t < end_tol || t > len - end_tol # near an end = corner
            offx = p.x - (o[:s].x + ux * t)
            offy = p.y - (o[:s].y + uy * t)
            off = Math.sqrt(offx * offx + offy * offy)
            next if off > (o[:th] + sg[:th]) / 2.0 + 1.0
            (cuts[j] ||= []) << t
          end
        end
      end
      out = []
      segs.each_with_index do |sg, j|
        ts = (cuts[j] || []).sort
        if ts.empty?
          out << sg
          next
        end
        dx = sg[:e].x - sg[:s].x
        dy = sg[:e].y - sg[:s].y
        len = Math.sqrt(dx * dx + dy * dy)
        ux = dx / len
        uy = dy / len
        dts = []
        ts.each { |t| dts << t if dts.empty? || t - dts.last > 1.0 }
        stops = [0.0] + dts + [len]
        stops.each_cons(2) do |t0, t1|
          a = Geom::Point3d.new(sg[:s].x + ux * t0, sg[:s].y + uy * t0, 0)
          b = Geom::Point3d.new(sg[:s].x + ux * t1, sg[:s].y + uy * t1, 0)
          out << { s: a, e: b, th: sg[:th], w: sg[:w] }
        end
      end
      out
    end

    # Planar face traversal: at each node continue with the neighbor that is
    # the first clockwise from the reversed incoming edge. Interior faces come
    # out counterclockwise (positive signed area); the outer face is negative.
    def self.trace_faces(nodes, edges)
      adj = Hash.new { |h, k| h[k] = [] }
      edges.each_with_index do |e, i|
        ang = Math.atan2(nodes[e[:b]].y - nodes[e[:a]].y, nodes[e[:b]].x - nodes[e[:a]].x)
        rev = ang > 0 ? ang - Math::PI : ang + Math::PI
        adj[e[:a]] << { ang: ang, to: e[:b], edge: i }
        adj[e[:b]] << { ang: rev, to: e[:a], edge: i }
      end
      adj.each_value { |l| l.sort_by! { |h| h[:ang] } }

      used  = {}
      faces = []
      edges.each_index do |i|
        e = edges[i]
        [[e[:a], e[:b]], [e[:b], e[:a]]].each do |u, v|
          next if used[[u, v]]
          face_nodes = []
          face_edges = []
          cu = u
          cv = v
          guard = 0
          ok = true
          loop do
            used[[cu, cv]] = true
            face_nodes << cu
            step = adj[cu].find { |h| h[:to] == cv }
            face_edges << step[:edge] if step
            back = Math.atan2(nodes[cu].y - nodes[cv].y, nodes[cu].x - nodes[cv].x)
            list = adj[cv]
            nxt = list.reverse.find { |h| h[:ang] < back - 1e-9 } || list.last
            cu = cv
            cv = nxt[:to]
            guard += 1
            (ok = false; break) if guard > 500
            break if cu == u && cv == v
          end
          faces << { node_ids: face_nodes, edge_ids: face_edges } if ok && face_nodes.length >= 3
        end
      end
      faces
    end

    def self.signed_area(pts)
      a = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        a += (p.x * q.y - q.x * p.y)
      end
      a / 2.0
    end

    # Offset every loop edge toward the interior by half its wall thickness
    # and intersect consecutive offset lines -> boundary at interior faces.
    # Uses the TRUE wall centerlines (not the clustered node positions, which
    # can be off by up to the corner tolerance and skew the polygon).
    # Loop must be counterclockwise (interior on the left of each edge).
    def self.inner_boundary(poly, loop_edges)
      n = poly.length
      lines = []
      n.times do |i|
        p = poly[i]
        q = poly[(i + 1) % n]
        ref = Geom::Vector3d.new(q.x - p.x, q.y - p.y, 0)
        return nil if ref.length < 0.01

        edge = loop_edges[i]
        th = edge ? edge[:th] : 0.0
        seg = edge ? centerline(edge[:wall]) : nil
        if seg
          s = seg[:s]
          e = seg[:e]
          d = Geom::Vector3d.new(e.x - s.x, e.y - s.y, 0)
          d.reverse! if d % ref < 0 # align with traversal direction
          base = s
        else
          d = ref
          base = p
        end
        len = d.length
        off = Geom::Vector3d.new(-d.y / len * th / 2.0, d.x / len * th / 2.0, 0) # left = interior
        lines << [base + off, d]
      end
      inner = []
      n.times do |i|
        prev = lines[(i - 1) % n]
        cur  = lines[i]
        pt = Geom.intersect_line_line(prev, cur)
        pt ||= cur[0] # collinear neighbors: fall back to the offset point
        inner << Geom::Point3d.new(pt.x, pt.y, 0)
      end
      inner
    end

    def self.detect_rooms!(verbose: true)
      segs = wall_list.map { |w| centerline(w) }.compact
      if segs.empty?
        puts '[Rooms] no walls found'
        return []
      end
      nodes, edges = build_graph(segs)
      faces = trace_faces(nodes, edges)

      rooms = []
      skipped_neg = 0
      faces.each do |f|
        poly = f[:node_ids].map { |i| nodes[i] }
        sa = signed_area(poly)
        next if sa.abs < 144.0 # ignore < 1 sqft slivers
        if sa < 0
          skipped_neg += 1
          next
        end
        edata = f[:edge_ids].map { |i| edges[i] }
        inner = inner_boundary(poly, edata)
        next unless inner
        rooms << {
          boundary: inner,
          net_area_sqft: signed_area(inner).abs / 144.0,
          wall_ids: edata.compact.map { |e| e[:wall].get_attribute('InteriorPro', 'id') }
        }
      end

      if verbose
        puts "[Rooms] walls=#{segs.length} nodes=#{nodes.length} edges=#{edges.length} " \
             "faces=#{faces.length} (outer/neg skipped=#{skipped_neg})"
        puts "[Rooms] #{rooms.length} room(s) detected:"
        rooms.each_with_index do |r, i|
          pts = r[:boundary].map { |p| "(#{p.x.to_f.round(1)},#{p.y.to_f.round(1)})" }.join(' ')
          puts "  room#{i + 1}: net #{r[:net_area_sqft].round(2)} sqft, #{r[:wall_ids].length} walls"
          puts "    boundary: #{pts}"
        end
      end
      rooms
    end

    # ---------- Stage B: room entities in the model ----------

    MATCH_TOL = 36.0 unless const_defined?(:MATCH_TOL, false) # inches, centroid matching

    def self.rooms_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'room'
      end
    end

    def self.centroid(pts)
      a = 0.0
      cx = 0.0
      cy = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        cross = p.x.to_f * q.y.to_f - q.x.to_f * p.y.to_f
        a += cross
        cx += (p.x.to_f + q.x.to_f) * cross
        cy += (p.y.to_f + q.y.to_f) * cross
      end
      a /= 2.0
      return Geom::Point3d.new(pts.first.x, pts.first.y, 0) if a.abs < 1e-6
      Geom::Point3d.new(cx / (6.0 * a), cy / (6.0 * a), 0)
    end

    def self.next_default_number
      nums = rooms_in_model.map do |g|
        n = g.get_attribute('InteriorPro', 'number')
        n ? n.to_i : 0
      end
      (nums.max || 0) + 1
    end

    def self.build_label!(grp, name, area_sqft)
      grp.entities.clear!
      txt = "#{name}\n#{area_sqft.round(1)} sq ft"
      grp.entities.add_3d_text(txt, TextAlignCenter, 'Arial', false, false, 8.0, 0.0, 0.0, true, 0.0)
      b = grp.definition.bounds
      shift = Geom::Vector3d.new(-b.center.x, -b.center.y, 0)
      grp.entities.transform_entities(Geom::Transformation.translation(shift), grp.entities.to_a)
    rescue StandardError => e
      puts "[Rooms] build_label failed: #{e.message}"
    end

    def self.write_room_attrs!(grp, r, id:, name:, number:)
      flat = r[:boundary].flat_map { |p| [p.x.to_f, p.y.to_f] }
      grp.set_attribute('InteriorPro', 'type', 'room')
      grp.set_attribute('InteriorPro', 'id', id)
      grp.set_attribute('InteriorPro', 'name', name)
      grp.set_attribute('InteriorPro', 'number', number)
      grp.set_attribute('InteriorPro', 'boundary_xy', flat)
      grp.set_attribute('InteriorPro', 'bounding_wall_ids', r[:wall_ids].compact)
      grp.set_attribute('InteriorPro', 'area_sqft', r[:net_area_sqft].to_f)
      grp.set_attribute('InteriorPro', 'level', 1)
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
    end

    def self.create_room!(r)
      model = Sketchup.active_model
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Room'
      InteriorPro.assign_tag(grp, 'IP/Rooms')
      number = next_default_number
      name = "Room #{number}"
      id = format('room-%s-%04d', Time.now.to_i.to_s(36), rand(10_000))
      write_room_attrs!(grp, r, id: id, name: name, number: number)
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      build_label!(grp, name, r[:net_area_sqft])
      c = centroid(r[:boundary])
      grp.transformation = Geom::Transformation.new(Geom::Point3d.new(c.x, c.y, 0.25))
      grp
    end

    def self.update_room!(grp, r)
      id     = grp.get_attribute('InteriorPro', 'id')
      name   = grp.get_attribute('InteriorPro', 'name') || 'Room'
      number = grp.get_attribute('InteriorPro', 'number') || 0
      write_room_attrs!(grp, r, id: id, name: name, number: number)
      build_label!(grp, name, r[:net_area_sqft])
      c = centroid(r[:boundary])
      grp.transformation = Geom::Transformation.new(Geom::Point3d.new(c.x, c.y, 0.25))
      grp
    end

    # Re-detect and reconcile: existing rooms keep id/name (matched by
    # centroid), new loops get new rooms, stale rooms are erased.
    def self.sync_rooms!
      model = Sketchup.active_model
      detected = detect_rooms!(verbose: false)
      existing = rooms_in_model
      model.start_operation('InteriorPro Sync Rooms', true)
      used = []
      detected.each do |r|
        c = centroid(r[:boundary])
        match = existing.find do |g|
          next false if used.include?(g)
          g.transformation.origin.distance(Geom::Point3d.new(c.x, c.y, g.transformation.origin.z)) < MATCH_TOL
        end
        if match
          used << match
          update_room!(match, r)
        else
          create_room!(r)
        end
      end
      (existing - used).each { |g| g.erase! if g.valid? }
      renumber_rooms!
      model.commit_operation
      begin
        InteriorPro::FloorManager.refresh! if defined?(InteriorPro::FloorManager)
      rescue StandardError => e
        puts "[Floors] refresh after room sync: #{e.message}"
      end
      puts "[Rooms] sync: #{detected.length} room(s) in model"
      detected.length
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Rooms] sync_rooms! failed: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
      nil
    end

    # Keep numbering compact (1..N) after every sync (2026-07-18, user
    # request): numbers used to keep climbing because next_default_number
    # only ever increments. Custom names (e.g. 'Kitchen') are preserved —
    # only default 'Room <n>' names are renamed to the new number.
    def self.renumber_rooms!
      n = 0
      rooms_in_model.sort_by { |g| g.get_attribute('InteriorPro', 'number').to_i }.each do |g|
        n += 1
        old_num = g.get_attribute('InteriorPro', 'number').to_i
        name = g.get_attribute('InteriorPro', 'name').to_s
        g.set_attribute('InteriorPro', 'number', n)
        next unless name =~ /\ARoom \d+\z/
        next if old_num == n && name == "Room #{n}"
        g.set_attribute('InteriorPro', 'name', "Room #{n}")
        build_label!(g, "Room #{n}", g.get_attribute('InteriorPro', 'area_sqft').to_f)
      end
    rescue StandardError => e
      puts "[Rooms] renumber_rooms! failed: #{e.message}"
    end

    # Console rename helper (stage C will add a dialog):
    #   InteriorPro::RoomManager.rename_room!('Room 1', 'Kitchen')
    def self.rename_room!(current_name, new_name)
      grp = rooms_in_model.find { |g| g.get_attribute('InteriorPro', 'name') == current_name }
      unless grp
        puts "[Rooms] room '#{current_name}' not found"
        return false
      end
      grp.set_attribute('InteriorPro', 'name', new_name.to_s)
      build_label!(grp, new_name.to_s, grp.get_attribute('InteriorPro', 'area_sqft').to_f)
      puts "[Rooms] renamed '#{current_name}' -> '#{new_name}'"
      true
    end
  end
end

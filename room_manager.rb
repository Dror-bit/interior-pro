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
      raw = []
      edges = []
      segs.each do |sg|
        a = node_id(raw, sg[:s], sg[:th])
        b = node_id(raw, sg[:e], sg[:th])
        next if a == b
        edges << { a: a, b: b, th: sg[:th], wall: sg[:w] }
      end
      [raw.map { |n| n[:pt] }, edges]
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
    # Loop must be counterclockwise (interior on the left of each edge).
    def self.inner_boundary(poly, loop_edges)
      n = poly.length
      lines = []
      n.times do |i|
        p = poly[i]
        q = poly[(i + 1) % n]
        th = loop_edges[i] ? loop_edges[i][:th] : 0.0
        dx = q.x - p.x
        dy = q.y - p.y
        len = Math.sqrt(dx * dx + dy * dy)
        return nil if len < 0.01
        off = Geom::Vector3d.new(-dy / len * th / 2.0, dx / len * th / 2.0, 0) # left = interior
        lines << [p + off, Geom::Vector3d.new(dx, dy, 0)]
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
  end
end

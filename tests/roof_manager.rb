# roof_manager.rb — parametric roof over the top level (2026-08-04, v3).
# Modeled on Revit's "roof by footprint": the footprint polygon is the TRUE
# outline of the top level's exterior walls (outer faces + overhang), and the
# roof surface is computed with a straight skeleton — every footprint edge
# carries a sloped plane, and hips/ridges/valleys fall out of where the
# planes meet. Styles: 'hip' (every edge slopes) and 'flat'. Per-edge gables
# (Revit's Defines Slope) are the next phase.
#
# v3 additions (user spec 2026-08-04): settings saved on the MODEL and
# edited from RoofDialog — style, pitch, overhang (0 = no eaves), fascia
# board, metal drip edge, roof color + fascia color.
module InteriorPro
  module RoofManager
    DEFAULT_PITCH     = 4.0  unless const_defined?(:DEFAULT_PITCH, false)     # rise per 12" run
    DEFAULT_OVERHANG  = 12.0 unless const_defined?(:DEFAULT_OVERHANG, false)  # inches, all sides
    # The roof is a pure SURFACE with zero thickness (user 2026-08-05:
    # "just a surface — the material on it will carry the thickness").
    DEFAULT_FASCIA_DEPTH = 8.0 unless const_defined?(:DEFAULT_FASCIA_DEPTH, false)
    FASCIA_THICK = 0.75 unless const_defined?(:FASCIA_THICK, false)
    DRIP_THICK   = 0.1  unless const_defined?(:DRIP_THICK, false)
    DRIP_DEPTH   = 2.0  unless const_defined?(:DRIP_DEPTH, false)
    DEFAULT_ROOF_COLOR   = '#584e4a' unless const_defined?(:DEFAULT_ROOF_COLOR, false)
    DEFAULT_FASCIA_COLOR = '#ffffff' unless const_defined?(:DEFAULT_FASCIA_COLOR, false)

    EPS = 1e-9 unless const_defined?(:EPS, false)
    NODE_TOL = 0.05 unless const_defined?(:NODE_TOL, false) # skeleton graph merge, inches

    # ---------- lookup ----------

    def self.roofs
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'roof'
      end
    end

    # Highest level that actually has walls.
    def self.top_level
      lvls = InteriorPro::LevelManager.all_walls.map do |w|
        (w.get_attribute('InteriorPro', 'level') || 1).to_i
      end
      lvls.empty? ? 1 : lvls.max
    end

    # The walls the roof sits on: exterior walls of the top level
    # (all of its walls if none is marked exterior).
    def self.top_walls
      ws = InteriorPro::LevelManager.walls_of_level(top_level)
      ext = ws.select do |w|
        (w.get_attribute('InteriorPro', 'wall_category') || 'exterior') == 'exterior'
      end
      ext.empty? ? ws : ext
    end

    # Where the roof underside starts: the highest wall top (base_z + height).
    def self.eave_z(walls)
      walls.map do |w|
        w.get_attribute('InteriorPro', 'base_z').to_f +
          w.get_attribute('InteriorPro', 'height').to_f
      end.max
    end

    # ---------- settings (saved on the model, edited by RoofDialog) ------

    def self.settings
      m = Sketchup.active_model
      g = lambda do |k, d|
        v = m.get_attribute('InteriorPro', k)
        v.nil? ? d : v
      end
      {
        style: g.call('roof_style', 'hip').to_s,
        pitch: g.call('roof_pitch', DEFAULT_PITCH).to_f,
        overhang: g.call('roof_overhang', DEFAULT_OVERHANG).to_f,
        fascia: g.call('roof_fascia', true) == true,
        fascia_depth: g.call('roof_fascia_depth', DEFAULT_FASCIA_DEPTH).to_f,
        drip: g.call('roof_drip', true) == true,
        roof_color: g.call('roof_color', DEFAULT_ROOF_COLOR).to_s,
        fascia_color: g.call('roof_fascia_color', DEFAULT_FASCIA_COLOR).to_s
      }
    end

    def self.save_settings!(s)
      m = Sketchup.active_model
      m.set_attribute('InteriorPro', 'roof_style', s[:style])
      m.set_attribute('InteriorPro', 'roof_pitch', s[:pitch])
      m.set_attribute('InteriorPro', 'roof_overhang', s[:overhang])
      m.set_attribute('InteriorPro', 'roof_fascia', s[:fascia])
      m.set_attribute('InteriorPro', 'roof_fascia_depth', s[:fascia_depth])
      m.set_attribute('InteriorPro', 'roof_drip', s[:drip])
      m.set_attribute('InteriorPro', 'roof_color', s[:roof_color])
      m.set_attribute('InteriorPro', 'roof_fascia_color', s[:fascia_color])
      s
    end

    # ---------- materials ----------

    def self.hex_to_color(hex)
      h = hex.to_s.gsub('#', '')
      return Sketchup::Color.new(120, 120, 120) unless h =~ /\A[0-9a-fA-F]{6}\z/
      Sketchup::Color.new(h[0, 2].to_i(16), h[2, 2].to_i(16), h[4, 2].to_i(16))
    end

    def self.color_material(model, hex)
      name = "InteriorPro_Roof_#{hex.to_s.gsub('#', '').downcase}"
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = hex_to_color(hex)
      m
    end

    # ---------- footprint: true outline + overhang ----------

    # Closed CCW loop of the walls' centerlines (RoomManager machinery),
    # offset OUTWARD to the exterior faces plus the overhang.
    # Returns { pts: [[x, y], ...], wall_ids: [id per edge] } or nil —
    # edge i runs pts[i] -> pts[i+1] and belongs to wall_ids[i].
    def self.eave_polygon(walls, overhang)
      rm = InteriorPro::RoomManager
      segs = walls.map { |w| rm.centerline(w) }.compact
      return nil if segs.length < 3
      nodes, edges = rm.build_graph(segs)
      faces = rm.trace_faces(nodes, edges)
      best = nil
      best_area = 144.0
      faces.each do |f|
        poly = f[:node_ids].map { |i| nodes[i] }
        sa = rm.signed_area(poly)
        next if sa <= best_area
        best = f
        best_area = sa
      end
      return nil unless best
      poly  = best[:node_ids].map { |i| nodes[i] }
      edata = best[:edge_ids].map { |i| edges[i] }
      out = outer_offset(poly, edata, overhang)
      return nil unless out
      pts = out.map { |p| [p[0].x.to_f, p[0].y.to_f] }
      ids = out.map { |p| p[1] }
      if polygon_area(pts) < 0 # skeleton wants CCW
        pts.reverse!
        ids = ids.reverse.rotate(1) # keep edge i -> wall alignment
      end
      { pts: pts, wall_ids: ids }
    end

    # Mirror of RoomManager.inner_boundary, offset to the OTHER side:
    # each loop edge moves outward by half its wall thickness + overhang.
    # Returns [[point, wall_id_of_the_edge_starting_here], ...].
    def self.outer_offset(poly, loop_edges, overhang)
      rm = InteriorPro::RoomManager
      n = poly.length
      lines = []
      n.times do |i|
        p = poly[i]
        q = poly[(i + 1) % n]
        ref = Geom::Vector3d.new(q.x - p.x, q.y - p.y, 0)
        return nil if ref.length < 0.01

        edge = loop_edges[i]
        th = edge ? edge[:th].to_f : 0.0
        seg = edge && edge[:wall] ? rm.centerline(edge[:wall]) : nil
        if seg
          s = seg[:s]
          e = seg[:e]
          d = Geom::Vector3d.new(e.x - s.x, e.y - s.y, 0)
          d.reverse! if d % ref < 0
          base = s
        else
          d = ref
          base = p
        end
        len = d.length
        k = th / 2.0 + overhang.to_f
        off = Geom::Vector3d.new(d.y / len * k, -d.x / len * k, 0) # right = exterior
        lines << [base + off, d]
      end
      out = []
      n.times do |i|
        prev = lines[(i - 1) % n]
        cur  = lines[i]
        pt = Geom.intersect_line_line(prev, cur)
        pt ||= cur[0]
        edge = loop_edges[i]
        wid = edge && edge[:wall] ? edge[:wall].get_attribute('InteriorPro', 'id') : nil
        out << [Geom::Point3d.new(pt.x, pt.y, 0), wid]
      end
      dedup = []
      out.each { |p| dedup << p if dedup.empty? || dedup.last[0].distance(p[0]) > 0.01 }
      dedup.pop if dedup.length > 1 && dedup.first[0].distance(dedup.last[0]) < 0.01
      dedup.length < 3 ? nil : dedup
    end

    # ---------- tiny 2D vector helpers ([x, y] arrays) ----------

    def self.vsub(a, b); [a[0] - b[0], a[1] - b[1]]; end
    def self.vadd(a, b); [a[0] + b[0], a[1] + b[1]]; end
    def self.vmul(a, k); [a[0] * k, a[1] * k]; end
    def self.vdot(a, b); a[0] * b[0] + a[1] * b[1]; end
    def self.vcross(a, b); a[0] * b[1] - a[1] * b[0]; end
    def self.vlen(a); Math.sqrt(vdot(a, a)); end

    def self.vnorm(a)
      l = vlen(a)
      l < 1e-12 ? [0.0, 0.0] : [a[0] / l, a[1] / l]
    end

    def self.polygon_area(pts)
      a = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        a += p[0] * q[1] - q[0] * p[1]
      end
      a / 2.0
    end

    # Offset a CCW polygon OUTWARD by k (straight miter at the corners).
    def self.offset_polygon(pts, k)
      n = pts.length
      lines = Array.new(n) do |i|
        d = vnorm(vsub(pts[(i + 1) % n], pts[i]))
        [vadd(pts[i], vmul([d[1], -d[0]], k)), d] # right = outward for CCW
      end
      out = []
      n.times do |i|
        p1, d1 = lines[(i - 1) % n]
        p2, d2 = lines[i]
        den = vcross(d1, d2)
        out << if den.abs < 1e-9
                 p2
               else
                 t = vcross(vsub(p2, p1), d2) / den
                 vadd(p1, vmul(d1, t))
               end
      end
      out
    end

    # ---------- straight skeleton (Felkel/Obdrzalek wavefront) ----------
    # Input: simple CCW polygon [[x,y],...] + optional per-edge speeds
    # (1.0 = normal sloped edge, 0.0 = gable edge whose line never moves).
    # Output: skeleton arcs [[[x,y],[x,y]], ...] or nil on failure.
    # Each vertex moves at the velocity b that solves b.n_left = s_left and
    # b.n_right = s_right, keeping it at offset s_e * t from each edge line.
    def self.straight_skeleton(pts, speeds = nil)
      n = pts.length
      return nil if n < 3
      edges = Array.new(n) do |i|
        p = pts[i]
        q = pts[(i + 1) % n]
        d = vnorm(vsub(q, p))
        { p: p, d: d, n: [-d[1], d[0]], s: speeds ? speeds[i].to_f : 1.0 }
      end

      make_vertex = lambda do |pt, t0, el, er|
        dl = edges[el][:d]
        dr = edges[er][:d]
        nl = edges[el][:n]
        nr = edges[er][:n]
        sl = edges[el][:s]
        sr = edges[er][:s]
        det = vcross(nl, nr)
        vel = if det.abs < 1e-9
                # collinear SAME-direction edges slide with their line;
                # ANTIPARALLEL (facing) edges are a degenerate ridge vertex
                # and must stay put (handled as a corridor annihilation).
                ((sl - sr).abs < 1e-9 && vdot(nl, nr) > 0.0) ? vmul(nl, sl) : [0.0, 0.0]
              else
                [(sl * nr[1] - sr * nl[1]) / det,
                 (nl[0] * sr - nr[0] * sl) / det]
              end
        { pt: pt, t0: t0, el: el, er: er, vel: vel,
          reflex: vcross(dl, dr) < -1e-9, alive: true, prev: nil, next: nil }
      end

      verts = Array.new(n) { |i| make_vertex.call(pts[i], 0.0, (i - 1) % n, i) }
      n.times do |i|
        verts[i][:next] = verts[(i + 1) % n]
        verts[i][:prev] = verts[(i - 1) % n]
      end

      # Tear junctions (2026-08-05, gable ending mid-wall): two COLLINEAR
      # edges with different speeds share a vertex no velocity satisfies.
      # Insert a zero-length VERTICAL virtual edge (speed 0) there: one
      # vertex stays put on the standing line, its twin climbs straight
      # inward along the tear — exactly where the mother gable ends and the
      # attached wing's slope takes over.
      n.times do |i|
        el = (i - 1) % n
        er = i
        next if (edges[el][:s] - edges[er][:s]).abs < 1e-9
        next unless vcross(edges[el][:d], edges[er][:d]).abs < 1e-9 &&
                    vdot(edges[el][:d], edges[er][:d]) > 0
        dirv = edges[el][:n]
        dirv = vmul(dirv, -1.0) if edges[er][:s] < edges[el][:s]
        edges << { p: pts[i], d: dirv, n: [-dirv[1], dirv[0]], s: 0.0 }
        virt = edges.length - 1
        vi = verts[i]
        va = make_vertex.call(pts[i], 0.0, el, virt)
        vb = make_vertex.call(pts[i], 0.0, virt, er)
        va[:prev] = vi[:prev]
        va[:next] = vb
        vb[:prev] = va
        vb[:next] = vi[:next]
        vi[:prev][:next] = va
        vi[:next][:prev] = vb
        vi[:alive] = false
        verts << va << vb
      end

      pos = lambda { |v, t| vadd(v[:pt], vmul(v[:vel], t - v[:t0])) }
      arcs = []
      emit = lambda do |a, b|
        arcs << [a, b] if vlen(vsub(a, b)) > NODE_TOL
      end

      # registry of every vertex ever created (for LAV walks)
      all_verts = verts.dup

      alive_cycles = lambda do
        visited = {}
        cycles = []
        all_verts.each do |v|
          next unless v[:alive]
          next if visited[v.object_id]
          cyc = []
          c = v
          guard = 0
          loop do
            visited[c.object_id] = true
            cyc << c
            c = c[:next]
            guard += 1
            break if c.equal?(v) || guard > 2000
          end
          cycles << cyc if guard <= 2000
        end
        cycles
      end

      close_small = lambda do |cyc|
        return false unless cyc.length <= 2
        if cyc.length == 2
          emit.call(cyc[0][:pt], cyc[1][:pt])
        end
        cyc.each { |v| v[:alive] = false }
        true
      end

      guard = 0
      loop do
        guard += 1
        return nil if guard > 400
        cycles = alive_cycles.call
        cycles = cycles.reject { |c| close_small.call(c) }
        break if cycles.empty?

        best = nil
        cycles.each do |cyc|
          # edge events between adjacent vertices
          cyc.each do |v|
            w = v[:next]
            e = v[:er]
            d = edges[e][:d]
            a0 = vdot(w[:pt], d) - w[:t0] * vdot(w[:vel], d) -
                 vdot(v[:pt], d) + v[:t0] * vdot(v[:vel], d)
            k = vdot(w[:vel], d) - vdot(v[:vel], d)
            next if k.abs < 1e-12
            t = -a0 / k
            tmin = [v[:t0], w[:t0]].max - 1e-9
            next if t < tmin
            next if k > 0 # the gap must be closing, not opening
            cand = { t: t, kind: :edge, v: v, w: w, i: pos.call(v, t), cyc: cyc }
            best = cand if best.nil? || t < best[:t] - 1e-9
          end
          # split events for reflex vertices
          cyc.each do |v|
            next unless v[:reflex]
            edges.each_index do |ei|
              next if ei == v[:el] || ei == v[:er]
              ne = edges[ei][:n]
              c = vdot(ne, v[:vel])
              den = edges[ei][:s] - c # opposite edge offsets at its own speed
              next if den.abs < 1e-9
              a = vdot(ne, vsub(v[:pt], edges[ei][:p]))
              t = (a - c * v[:t0]) / den
              next if t < v[:t0] + 1e-6
              bpt = pos.call(v, t)
              # the opposite edge's wavefront must actually contain B
              holder = cyc.find do |y|
                next false unless y[:alive] && y[:er] == ei && !y.equal?(v) && !y[:next].equal?(v)
                z = y[:next]
                de = edges[ei][:d]
                vdot(vsub(bpt, pos.call(y, t)), de) >= -0.01 &&
                  vdot(vsub(pos.call(z, t), bpt), de) >= -0.01
              end
              next unless holder
              cand = { t: t, kind: :split, v: v, i: bpt, e: ei, y: holder, cyc: cyc }
              best = cand if best.nil? || t < best[:t] - 1e-9
            end
          end
        end
        break if best.nil?

        if best[:kind] == :edge
          v = best[:v]
          w = best[:w]
          i = best[:i]
          cyc = best[:cyc]
          if cyc.length == 3
            cyc.each do |x|
              emit.call(x[:pt], i)
              x[:alive] = false
            end
          else
            emit.call(v[:pt], i)
            emit.call(w[:pt], i)
            u = make_vertex.call(i, best[:t], v[:el], w[:er])
            all_verts << u
            u[:prev] = v[:prev]
            u[:next] = w[:next]
            v[:prev][:next] = u
            w[:next][:prev] = u
            v[:alive] = false
            w[:alive] = false
            # Corridor annihilation (2026-08-05, the holes bug): if u's two
            # edges FACE each other (a wing collapsing into the body), the
            # zero-width corridor between the two touching fronts dies
            # along its midline right now, over the interval where they
            # overlap. That reaches the NEARER neighbour; if the far front
            # continues, a merged vertex carries on there — which can chain
            # into another facing pair, so keep resolving in a loop.
            cur = u
            ann_guard = 0
            loop do
              ann_guard += 1
              break if ann_guard > 60
              break unless cur[:alive]
              nl = edges[cur[:el]][:n]
              nr = edges[cur[:er]][:n]
              break unless vcross(nl, nr).abs < 1e-9 && vdot(nl, nr) < 0.0
              p = cur[:prev]
              q = cur[:next]
              if p.equal?(q)
                pp = pos.call(p, best[:t])
                emit.call(cur[:pt], pp)
                emit.call(p[:pt], pp)
                cur[:alive] = false
                p[:alive] = false
                break
              end
              pp = pos.call(p, best[:t])
              qq = pos.call(q, best[:t])
              dp = vlen(vsub(pp, cur[:pt]))
              dq = vlen(vsub(qq, cur[:pt]))
              if vlen(vsub(pp, qq)) < NODE_TOL * 10
                # both neighbours arrive together: 3-way merge
                emit.call(cur[:pt], pp)
                emit.call(p[:pt], pp)
                emit.call(q[:pt], pp)
                cur[:alive] = false
                p[:alive] = false
                q[:alive] = false
                break if p[:prev].equal?(q) # the whole LAV died here
                m2 = make_vertex.call(pp, best[:t], p[:el], q[:er])
                all_verts << m2
                m2[:prev] = p[:prev]
                m2[:next] = q[:next]
                p[:prev][:next] = m2
                q[:next][:prev] = m2
                cur = m2
                next
              end
              # one-sided: the corridor ends at the nearer neighbour and
              # the far front survives past it
              near_q = dq < dp
              tgt = near_q ? q : p
              tpos = near_q ? qq : pp
              axis = edges[cur[:el]][:d]
              dirv = vnorm(vsub(tpos, cur[:pt]))
              break if vcross(axis, dirv).abs > 0.05 # not along the corridor
              emit.call(cur[:pt], tpos)
              emit.call(tgt[:pt], tpos)
              cur[:alive] = false
              tgt[:alive] = false
              el2   = near_q ? cur[:el] : tgt[:el]
              er2   = near_q ? tgt[:er] : cur[:er]
              prev2 = near_q ? cur[:prev] : tgt[:prev]
              next2 = near_q ? tgt[:next] : cur[:next]
              w2 = make_vertex.call(tpos, best[:t], el2, er2)
              all_verts << w2
              w2[:prev] = prev2
              w2[:next] = next2
              prev2[:next] = w2
              next2[:prev] = w2
              cur = w2
            end
          end
        else # split
          v = best[:v]
          b = best[:i]
          y = best[:y]
          z = y[:next]
          emit.call(v[:pt], b)
          v1 = make_vertex.call(b, best[:t], v[:el], best[:e])
          v2 = make_vertex.call(b, best[:t], best[:e], v[:er])
          all_verts << v1
          all_verts << v2
          # LAV 1: v.prev -> v1 -> z ...
          v1[:prev] = v[:prev]
          v1[:next] = z
          v[:prev][:next] = v1
          z[:prev] = v1
          # LAV 2: y -> v2 -> v.next ...
          v2[:prev] = y
          v2[:next] = v[:next]
          y[:next] = v2
          v[:next][:prev] = v2
          v[:alive] = false
        end
      end
      arcs
    end

    # ---------- cells: polygon edges + arcs -> one face per eave edge ----

    # Returns [{ pts: [[x,y],...], eave: edge_index }, ...] or nil.
    # speeds: per-polygon-edge; a cell's eave must be a SLOPED edge (gable
    # arcs run along the gable edge itself, so polygon edges are split at
    # every node that lands on them and overlapping arcs dedupe away).
    def self.roof_cells(poly, arcs, speeds = nil)
      rm = InteriorPro::RoomManager
      npts = []
      node_of = lambda do |p|
        npts.each_with_index do |q, i|
          return i if vlen(vsub(q, p)) < NODE_TOL
        end
        npts << [p[0], p[1]]
        npts.length - 1
      end
      n = poly.length
      # every segment: polygon edges first (their eave tag wins on
      # overlaps), then the skeleton arcs
      segs = []
      n.times { |i| segs << [poly[i], poly[(i + 1) % n], i] }
      arcs.each { |a, b| segs << [a, b, nil] }
      segs.each do |a, b, _|
        node_of.call(a)
        node_of.call(b)
      end

      graph = []
      seen = {}
      add_edge = lambda do |a, b, tag|
        key = [a, b].sort
        return if a == b || seen[key]
        seen[key] = true
        graph << { a: a, b: b, eave: tag }
      end
      # EVERY segment is split at every node that sits on it — valley
      # arcs can legitimately run THROUGH an earlier skeleton node
      # (2026-08-05, the vanished-cell bug).
      segs.each do |a, b, tag|
        d = vnorm(vsub(b, a))
        len = vlen(vsub(b, a))
        next if len < NODE_TOL
        stops = []
        npts.each_with_index do |p, id|
          t = vdot(vsub(p, a), d)
          next if t < -NODE_TOL || t > len + NODE_TOL
          perp = vcross(d, vsub(p, a)).abs
          stops << [t, id] if perp < NODE_TOL
        end
        stops.sort_by!(&:first)
        stops.each_cons(2) { |(_, u), (_, v)| add_edge.call(u, v, tag) }
      end

      points = npts.map { |p| Geom::Point3d.new(p[0], p[1], 0) }
      faces = rm.trace_faces(points, graph)
      cells = []
      faces.each do |f|
        pts = f[:node_ids].map { |i| npts[i] }
        next if polygon_area(pts) < 1.0
        eave = f[:edge_ids].map { |i| graph[i][:eave] }.compact
                .find { |t| speeds.nil? || speeds[t].to_f > 0.5 }
        next if eave.nil? # the outer face / gable-only borders
        cells << { pts: pts, eave: eave }
      end
      cells.empty? ? nil : cells
    end

    # ---------- build / remove ----------

    # Build (or rebuild) the roof from the saved settings; keyword args
    # override AND update the saved settings. Console examples:
    #   InteriorPro::RoofManager.build_roof!(pitch: 6, overhang: 18)
    #   InteriorPro::RoofManager.build_roof!(style: 'flat')
    def self.build_roof!(style: nil, pitch: nil, overhang: nil,
                         fascia: nil, fascia_depth: nil, drip: nil,
                         roof_color: nil, fascia_color: nil)
      model = Sketchup.active_model
      s = settings
      s[:style] = style.to_s if style
      s[:pitch] = pitch.to_f if pitch
      s[:overhang] = overhang.to_f unless overhang.nil?
      s[:fascia] = (fascia == true) unless fascia.nil?
      s[:fascia_depth] = fascia_depth.to_f if fascia_depth && fascia_depth.to_f > 0.01
      s[:drip] = (drip == true) unless drip.nil?
      s[:roof_color] = roof_color.to_s if roof_color
      s[:fascia_color] = fascia_color.to_s if fascia_color
      slope = s[:pitch] / 12.0

      walls = top_walls
      ep = walls.length >= 3 ? eave_polygon(walls, s[:overhang]) : nil
      if ep.nil?
        UI.messagebox('No closed loop of exterior walls to roof yet')
        return nil
      end
      poly = ep[:pts]
      wall_ids = ep[:wall_ids]
      cells = nil
      speeds = nil
      gables = []
      framed = nil
      unless s[:style] == 'flat'
        # Gable ends: walls the user marked with the Gable Ends tool win;
        # with no marks, the Gable style falls back to the two short ends.
        marked = gable_wall_ids
        clicks_by_id = {}
        gable_click_points.each_with_index do |pt, k|
          next if marked[k].nil? || pt[0].to_f > 1.0e8 # sentinel = no point
          clicks_by_id[marked[k]] = pt
        end
        # ignore marks whose wall no longer exists in this roof loop
        # (2026-08-05: a stale id after wall split/join blocked Gable style)
        loop_ids = wall_ids.compact
        dead = marked.reject { |id2| loop_ids.include?(id2) }
        puts "[Roof] ignoring #{dead.length} stale/off-loop gable mark(s)" unless dead.empty?
        marked -= dead
        gables = (0...poly.length).select { |i| wall_ids[i] && marked.include?(wall_ids[i]) }
        want_gable = !gables.empty? || s[:style] == 'gable'
        # Over-framing first (2026-08-05, the user's mock): a marked wall
        # gables its WHOLE wing, volumes intersect on valleys. The strip-
        # gable skeleton stays as fallback for non-rectilinear plans.
        framed = framed_plan(poly, wall_ids, marked, s[:style]) if want_gable
        if framed
          gables = framed[:edges]
        else
          puts '[Roof] plan not decomposable - strip-gable fallback' if want_gable
          gables = pick_gable_edges(poly) if gables.empty? && s[:style] == 'gable'
          unless gables.empty?
            # A marked wall that runs past its own roof section (a wing
            # attaches along it) gets its gable only on ONE span: the strip
            # UNDER the user's click, or the deepest strip when no click was
            # saved (user 2026-08-05: the gable goes where I clicked).
            clicks_by_edge = {}
            gables.each do |i|
              c = wall_ids[i] && clicks_by_id[wall_ids[i]]
              clicks_by_edge[i] = c if c
            end
            poly, wall_ids, gables = split_gable_edges(poly, wall_ids, gables, clicks_by_edge)
            speeds = Array.new(poly.length, 1.0)
            gables.each { |i| speeds[i] = 0.0 }
          end
          arcs = straight_skeleton(poly, speeds)
          if arcs.nil?
            puts '[Roof] straight skeleton failed for this footprint'
            return nil
          end
          cells = roof_cells(poly, arcs, speeds)
          if cells.nil?
            puts '[Roof] could not form roof faces from the skeleton'
            return nil
          end
        end
      end

      save_settings!(s)
      z0 = eave_z(walls)
      lvl = top_level

      model.start_operation('InteriorPro Roof', true)
      roofs.each { |r| r.erase! if r.valid? } # rebuild replaces, never stacks
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Roof'
      InteriorPro.assign_tag(grp, 'IP/Roofs')
      roof_mat = color_material(model, s[:roof_color])
      trim_mat = color_material(model, s[:fascia_color]) # fascia + drip + underside
      gable_flags = Array.new(poly.length, false)
      gables.each { |i| gable_flags[i] = true }
      zmap = nil
      if s[:style] == 'flat'
        ridge = build_flat_geometry!(grp, poly, z0, roof_mat, trim_mat)
        band_top = z0
      elsif framed
        ridge, zmap = build_framed_geometry!(grp, framed, z0, slope, s[:overhang],
                                             roof_mat, trim_mat)
        band_top = z0 - slope * s[:overhang]
      else
        ridge, zmap = build_hip_geometry!(grp, poly, cells, z0, slope, s[:overhang],
                                          roof_mat, trim_mat)
        band_top = z0 - slope * s[:overhang] # the surface at the eave edge
      end
      if ridge.nil?
        grp.erase! if grp.valid?
        model.abort_operation
        puts '[Roof] roof geometry failed'
        return nil
      end

      # Fascia + drip edge tuck UNDER the roof edge (user 2026-08-05: the
      # roof sits on them and ends at its own outer arris). Fascia outer
      # face is flush with the slab edge; the drip sticks 0.1" past it to
      # cover the seam. Both hang from the slab underside line.
      # gable ends stay OPEN - no white triangle fill (user 2026-08-05B:
      # the wall itself will rise to the roof shape later).
      # build_gable_wall_face! is kept unused for a quick revert.
      if s[:fascia]
        build_band!(grp, poly, -FASCIA_THICK, 0.0, band_top, band_top - s[:fascia_depth], gable_flags)
        # rake boards: fascia climbing the sloped edges of every gable end
        if zmap
          gables.each { |i| build_rake_board!(grp, poly, i, zmap, s[:fascia_depth]) }
        end
      end
      if s[:drip]
        build_band!(grp, poly, 0.0, DRIP_THICK, band_top, band_top - DRIP_DEPTH, gable_flags)
      end
      grp.entities.grep(Sketchup::Face).each do |f|
        next if f.material
        f.material = trim_mat
        f.back_material = trim_mat
      end

      grp.set_attribute('InteriorPro', 'type', 'roof')
      grp.set_attribute('InteriorPro', 'id',
                        format('roof-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'roof_style', s[:style])
      grp.set_attribute('InteriorPro', 'level', lvl)
      grp.set_attribute('InteriorPro', 'pitch', s[:pitch])
      grp.set_attribute('InteriorPro', 'overhang_in', s[:overhang])
      grp.set_attribute('InteriorPro', 'thickness_in', 0.0)
      grp.set_attribute('InteriorPro', 'fascia', s[:fascia])
      grp.set_attribute('InteriorPro', 'drip_edge', s[:drip])
      grp.set_attribute('InteriorPro', 'gable_edges', gables) unless gables.empty?
      grp.set_attribute('InteriorPro', 'eave_z', z0)
      grp.set_attribute('InteriorPro', 'ridge_z', ridge)
      grp.set_attribute('InteriorPro', 'footprint_xy', poly.flatten)
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      model.commit_operation
      puts format('[Roof] %s over level %d: eave %.1f", ridge %.1f" (pitch %s:12, overhang %.0f", fascia %s, drip %s)',
                  s[:style], lvl, z0, ridge, s[:pitch], s[:overhang],
                  s[:fascia] ? 'on' : 'off', s[:drip] ? 'on' : 'off')
      grp
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Roof] build_roof! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end

    def self.paint!(f, mat)
      f.material = mat
      f.back_material = mat
      f
    end

    # A roof surface face: roof color on the TOP side, trim (white) on the
    # underside. add_face may come out facing down — flip it first.
    def self.paint_surface!(f, top_mat, under_mat)
      f.reverse! if f.respond_to?(:reverse!) && f.normal.z < 0
      f.material = top_mat
      f.back_material = under_mat
      f
    end

    # ONE sloped surface face per cell — zero thickness. Roof color on
    # top, trim (white) underneath.
    #
    # Heel rule (2026-08-05, "the roof must not cut into the ceiling"):
    # the surface is shifted by delta = -slope*overhang, so it meets the
    # wall top exactly at the wall's OUTER face and only rises from there
    # inward — inside the house it is always at or above the ceiling
    # plane. The dip below z0 remains only out in the overhang.
    # Returns the ridge (max) z, or nil.
    def self.build_hip_geometry!(grp, poly, cells, z0, slope, overhang,
                                 roof_mat, under_mat)
      n = poly.length
      delta = -slope * overhang.to_f
      lines = Array.new(n) do |i|
        p = poly[i]
        d = vnorm(vsub(poly[(i + 1) % n], poly[i]))
        { p: p, n: [-d[1], d[0]] }
      end
      lift = lambda do |pt, ei|
        d = vdot(lines[ei][:n], vsub(pt, lines[ei][:p]))
        d = 0.0 if d < 0.0
        z0 + delta + slope * d
      end
      ridge = z0
      # node [x,y] (rounded) -> HIGHEST surface z there. A strip-junction
      # node (a gable on part of a long wall) legitimately carries TWO
      # heights; the gable faces and rake boards follow the high profile
      # (2026-08-05: keeping only the last-written z made the strip-gable
      # chain degenerate to 2 eave points, so no triangle was built).
      zmap = {}
      # xy segment -> the 3D z-profile every cell puts on it, to close
      # vertical tears between roof sections that meet at different heights
      edge_zs = Hash.new { |h, k| h[k] = [] }
      cells.each do |cell|
        top = cell[:pts].map do |p|
          z = lift.call(p, cell[:eave])
          ridge = z if z > ridge
          key = [p[0].round(4), p[1].round(4)]
          zmap[key] = z if zmap[key].nil? || z > zmap[key]
          Geom::Point3d.new(p[0], p[1], z)
        end
        top.each_index do |i2|
          pa = top[i2]
          pb = top[(i2 + 1) % top.length]
          ka = [pa.x.round(4), pa.y.round(4)]
          kb = [pb.x.round(4), pb.y.round(4)]
          next if ka == kb
          if (ka <=> kb) <= 0
            edge_zs[[ka, kb]] << [pa.z, pb.z]
          else
            edge_zs[[kb, ka]] << [pb.z, pa.z]
          end
        end
        paint_surface!(grp.entities.add_face(top), roof_mat, under_mat)
      end
      # Vertical tear faces (2026-08-05): where a gable strip meets the
      # rest of its wall, two roof sections share an xy segment at
      # DIFFERENT heights. Without a closing face the roof shows white
      # triangular holes and "floating" edges. Painted trim white by the
      # catch-all pass in build_roof!.
      edge_zs.each do |(ka, kb), profiles|
        next if profiles.length < 2
        profiles.combination(2).each do |(za1, zb1), (za2, zb2)|
          next if (za1 - za2).abs < 0.01 && (zb1 - zb2).abs < 0.01
          pts = []
          [[ka, za1], [kb, zb1], [kb, zb2], [ka, za2]].each do |(k, z)|
            pt = Geom::Point3d.new(k[0], k[1], z)
            dup = pts.any? do |q|
              (q.x - pt.x).abs < 0.001 && (q.y - pt.y).abs < 0.001 &&
                (q.z - pt.z).abs < 0.001
            end
            pts << pt unless dup
          end
          grp.entities.add_face(pts) if pts.length >= 3
        end
      end
      [ridge, zmap]
    rescue StandardError => e
      puts "[Roof] build_hip_geometry!: #{e.message}"
      nil
    end

    # Flat roof: a single surface on the wall tops. Roof color on top,
    # trim (white) underneath. Returns the top z.
    def self.build_flat_geometry!(grp, poly, z0, roof_mat, under_mat)
      top = poly.map { |p| Geom::Point3d.new(p[0], p[1], z0) }
      paint_surface!(grp.entities.add_face(top), roof_mat, under_mat)
      z0
    rescue StandardError => e
      puts "[Roof] build_flat_geometry!: #{e.message}"
      nil
    end

    # ---------- gable-end marking (the Gable Ends click tool) ----------

    def self.gable_wall_ids
      Sketchup.active_model.get_attribute('InteriorPro', 'roof_gable_wall_ids') || []
    end

    # Every wall id that actually exists in the model right now.
    def self.live_wall_ids
      InteriorPro::LevelManager.all_walls.map do |w|
        w.get_attribute('InteriorPro', 'id')
      end.compact
    end

    # Click positions saved with the marks (aligned with gable_wall_ids).
    # [1e9, 1e9] = an old mark with no click point.
    def self.gable_click_points
      flat = Sketchup.active_model.get_attribute('InteriorPro', 'roof_gable_click_xy') || []
      flat.each_slice(2).to_a
    end

    # Toggle a wall's roof end between hip and gable; saved by wall id on
    # the model, so it survives every rebuild. The CLICK POINT is saved
    # too — on a long wall the gable applies to the roof section under the
    # click (user 2026-08-05: no guessing). Rebuilds the roof if one
    # exists. Called by RoofGableTool.
    def self.toggle_gable_wall!(wall, click = nil)
      return false unless wall && wall.valid? &&
                          wall.get_attribute('InteriorPro', 'type') == 'wall'
      id = wall.get_attribute('InteriorPro', 'id')
      return false if id.nil?
      ids = gable_wall_ids.dup
      pts = gable_click_points
      pts = pts.first(ids.length) + Array.new([ids.length - pts.length, 0].max, [1e9, 1e9])
      # Self-heal (2026-08-05): a split/join/delete gives the wall a NEW id
      # ('...A' -> '...AJ'), so stored marks can point at walls that no
      # longer exist. Dead marks did nothing AND blocked the Gable style.
      live = live_wall_ids
      stale = ids.reject { |i2| live.include?(i2) }
      unless stale.empty?
        stale.each do |s2|
          k = ids.index(s2)
          ids.delete_at(k)
          pts.delete_at(k)
        end
        puts "[Roof] dropped #{stale.length} stale gable mark(s)"
      end
      idx = ids.index(id)
      if idx
        ids.delete_at(idx)
        pts.delete_at(idx)
        on = false
      else
        ids.push(id)
        pts.push(click ? [click[0].to_f, click[1].to_f] : [1e9, 1e9])
        on = true
      end
      m = Sketchup.active_model
      m.set_attribute('InteriorPro', 'roof_gable_wall_ids', ids)
      m.set_attribute('InteriorPro', 'roof_gable_click_xy', pts.flatten)
      puts "[Roof] wall #{id}: #{on ? 'GABLE end' : 'hip end'} (#{ids.length} marked)"
      build_roof! unless roofs.empty?
      true
    end

    # The gable triangle: a vertical face closing the gable end, from the
    # eave-corner height up along the roof profile (eave - ridge - eave).
    # Painted trim white by the catch-all trim pass.
    def self.build_gable_wall_face!(grp, poly, i, zmap)
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      chain = []
      zmap.each do |(x, y), z|
        p = [x, y]
        t = vdot(vsub(p, a), d)
        next if t < -NODE_TOL || t > len + NODE_TOL
        next if vcross(d, vsub(p, a)).abs > NODE_TOL
        chain << [t, p, z]
      end
      chain.sort_by!(&:first)
      return if chain.length < 2
      pts = chain.map { |_, p, z| Geom::Point3d.new(p[0], p[1], z) }
      # Close the profile down to the eave line. On a full-wall gable the
      # two chain ends already sit at eave height and these are dropped as
      # duplicates; on a STRIP gable (2026-08-05) the junction end hangs
      # high and needs the vertical drop edge to close the triangle.
      base = chain.map { |c| c[2] }.min
      [[b, base], [a, base]].each do |(q, z)|
        pt = Geom::Point3d.new(q[0], q[1], z)
        dup = pts.any? do |p|
          (p.x - pt.x).abs < 0.01 && (p.y - pt.y).abs < 0.01 &&
            (p.z - pt.z).abs < 0.01
        end
        pts << pt unless dup
      end
      return if pts.length < 3
      grp.entities.add_face(pts)
    rescue StandardError => e
      puts "[Roof] build_gable_wall_face!: #{e.message}"
    end

    # Rake board: the fascia climbing the two sloped edges of a gable end.
    # One mitered-ish box per profile segment, FASCIA_THICK outward.
    def self.build_rake_board!(grp, poly, i, zmap, depth)
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      out = [d[1] * FASCIA_THICK, -d[0] * FASCIA_THICK] # outward for CCW
      chain = []
      zmap.each do |(x, y), z|
        p = [x, y]
        t = vdot(vsub(p, a), d)
        next if t < -NODE_TOL || t > len + NODE_TOL
        next if vcross(d, vsub(p, a)).abs > NODE_TOL
        chain << [t, p, z]
      end
      chain.sort_by!(&:first)
      return if chain.length < 2
      chain.each_cons(2) do |(_, p1, z1), (_, p2, z2)|
        inner = [
          Geom::Point3d.new(p1[0], p1[1], z1),
          Geom::Point3d.new(p2[0], p2[1], z2),
          Geom::Point3d.new(p2[0], p2[1], z2 - depth),
          Geom::Point3d.new(p1[0], p1[1], z1 - depth)
        ]
        outer = inner.map { |p| Geom::Point3d.new(p.x + out[0], p.y + out[1], p.z) }
        grp.entities.add_face(inner)
        grp.entities.add_face(outer)
        4.times do |k|
          j = (k + 1) % 4
          grp.entities.add_face([inner[k], inner[j], outer[j], outer[k]])
        end
      end
    rescue StandardError => e
      puts "[Roof] build_rake_board!: #{e.message}"
    end

    # ---------- gable only on the mother span of a long wall ----------

    # Distance from origin along dirv to the nearest polygon boundary
    # crossing (ignoring edge skip_i). Rectilinear ray-cast.
    def self.ray_depth(poly, skip_i, origin, dirv)
      n = poly.length
      best = 1.0e12
      n.times do |j|
        next if j == skip_i
        p = poly[j]
        q = poly[(j + 1) % n]
        e = vsub(q, p)
        den = vcross(dirv, e)
        next if den.abs < 1e-9
        sdist = vcross(vsub(p, origin), e) / den
        u = vcross(vsub(p, origin), dirv) / den
        next if sdist < 1.0 || u < -1e-6 || u > 1.0 + 1e-6
        best = sdist if sdist < best
      end
      best
    end

    # Depth strips of edge i: cut positions from the other corners
    # projected onto the edge, plus the plan depth behind each strip.
    # Returns [[t0, t1, depth], ...] sorted along the edge.
    def self.gable_strips(poly, i)
      n = poly.length
      a = poly[i]
      b = poly[(i + 1) % n]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      nrm = [-d[1], d[0]] # inward for CCW
      cuts = [0.0, len]
      poly.each_with_index do |p, j|
        next if j == i || j == (i + 1) % n
        t = vdot(vsub(p, a), d)
        cuts << t if t > 1.0 && t < len - 1.0
      end
      cuts = cuts.sort.each_with_object([]) { |t, acc| acc << t if acc.empty? || t - acc.last > 1.0 }
      ivs = []
      cuts.each_cons(2) do |t0, t1|
        mid = vadd(a, vmul(d, (t0 + t1) / 2.0))
        ivs << [t0, t1, ray_depth(poly, i, mid, nrm)]
      end
      ivs
    end

    # Grow from strip k over the neighbours of (nearly) the same depth.
    def self.expand_strips(ivs, k)
      ref = ivs[k][2]
      lo = k
      lo -= 1 while lo > 0 && (ivs[lo - 1][2] - ref).abs < 1.0
      hi = k
      hi += 1 while hi < ivs.length - 1 && (ivs[hi + 1][2] - ref).abs < 1.0
      [ivs[lo][0], ivs[hi][1]]
    end

    # No click point (old marks / tests): the DEEPEST strip is the mother.
    def self.gable_subinterval(poly, i)
      ivs = gable_strips(poly, i)
      return nil if ivs.empty?
      dmax = ivs.map { |iv| iv[2] }.max
      expand_strips(ivs, ivs.index { |iv| (iv[2] - dmax).abs < 0.01 })
    end

    # With a click point: the gable goes to the strip UNDER the click.
    def self.gable_subinterval_at(poly, i, click)
      ivs = gable_strips(poly, i)
      return nil if ivs.empty?
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      tc = vdot(vsub([click[0].to_f, click[1].to_f], a), d)
      k = ivs.index { |iv| tc >= iv[0] - 0.5 && tc <= iv[1] + 0.5 }
      k ||= tc < ivs.first[0] ? 0 : ivs.length - 1
      expand_strips(ivs, k)
    end

    # Split every marked gable edge at its gable-span limits: the polygon
    # gains collinear vertices there, only that sub-edge stays gable.
    # clicks: edge index -> [x, y] click point (nil = no point saved).
    # Returns the new [poly, wall_ids, gable_indices].
    def self.split_gable_edges(poly, wall_ids, gables, clicks = {})
      n = poly.length
      new_pts = []
      new_ids = []
      flags = []
      n.times do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        d = vnorm(vsub(b, a))
        len = vlen(vsub(b, a))
        g = gables.include?(i)
        sub = nil
        if g
          c = clicks[i]
          sub = c ? gable_subinterval_at(poly, i, c) : gable_subinterval(poly, i)
        end
        if !g || sub.nil? || (sub[0] < 1.0 && sub[1] > len - 1.0)
          new_pts << a
          new_ids << wall_ids[i]
          flags << g
          next
        end
        stops = [0.0]
        stops << sub[0] if sub[0] > 1.0
        stops << sub[1] if sub[1] < len - 1.0
        stops << len
        stops.each_cons(2) do |t0, t1|
          new_pts << vadd(a, vmul(d, t0))
          new_ids << wall_ids[i]
          flags << (t0 >= sub[0] - 0.5 && t1 <= sub[1] + 0.5)
        end
      end
      [new_pts, new_ids, flags.each_index.select { |k2| flags[k2] }]
    end

    # ---------- gable over-framing (2026-08-05, the user's mock) ----------
    # "This is how you actually build a roof": every marked wall gets the
    # FULL gable volume of its own wing — ridge perpendicular to the wall,
    # triangle over the whole wall — and the volumes run into each other
    # like stick framing: the wing ridge dives into the parent roof by half
    # the wing width, so the planes meet on real 45-degree valleys.
    # Replaces the strip-gable skeleton path on rectilinear plans; the old
    # strip path remains as a fallback for tangled footprints.

    RECT_TOL = 0.05 unless const_defined?(:RECT_TOL, false)

    def self.rectilinear?(poly)
      n = poly.length
      poly.each_index.all? do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        (a[0] - b[0]).abs < RECT_TOL || (a[1] - b[1]).abs < RECT_TOL
      end
    end

    # Slabs between consecutive vertex lines along one axis; every
    # connected interval inside a slab is a rectangle. Stacked rects with
    # the same cross-span are merged back afterwards.
    def self.slab_rects(poly, axis)
      n = poly.length
      cuts = []
      poly.each { |p| c = axis == :y ? p[1] : p[0]; cuts << c unless cuts.any? { |x| (x - c).abs < RECT_TOL } }
      cuts.sort!
      rects = []
      cuts.each_cons(2) do |c0, c1|
        mid = (c0 + c1) / 2.0
        us = []
        n.times do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          if axis == :y
            next if (a[1] - b[1]).abs < RECT_TOL
            lo, hi = [a[1], b[1]].minmax
            us << a[0] if mid > lo && mid < hi
          else
            next if (a[0] - b[0]).abs < RECT_TOL
            lo, hi = [a[0], b[0]].minmax
            us << a[1] if mid > lo && mid < hi
          end
        end
        return nil if us.empty? || us.length.odd?
        us.sort!
        us.each_slice(2) do |u0, u1|
          rects << (axis == :y ? [u0, c0, u1, c1] : [c0, u0, c1, u1])
        end
      end
      merge_rects!(rects, axis)
    end

    def self.merge_rects!(rects, axis)
      loop do
        pair = nil
        rects.each_with_index do |r, i|
          rects.each_with_index do |q, j|
            next if i >= j
            if axis == :y
              same = (r[0] - q[0]).abs < RECT_TOL && (r[2] - q[2]).abs < RECT_TOL
              touch = (r[3] - q[1]).abs < RECT_TOL || (q[3] - r[1]).abs < RECT_TOL
            else
              same = (r[1] - q[1]).abs < RECT_TOL && (r[3] - q[3]).abs < RECT_TOL
              touch = (r[2] - q[0]).abs < RECT_TOL || (q[2] - r[0]).abs < RECT_TOL
            end
            pair = [i, j] if same && touch
            break if pair
          end
          break if pair
        end
        break unless pair
        i, j = pair
        r = rects[i]
        q = rects[j]
        nr = [[r[0], q[0]].min, [r[1], q[1]].min, [r[2], q[2]].max, [r[3], q[3]].max]
        rects.delete_at(j)
        rects.delete_at(i)
        rects << nr
      end
      rects
    end

    # Maximal-rectangle decomposition on the vertex grid (2026-08-05, the
    # user's third house): slab cuts on ONE axis lose when wings hang on
    # BOTH axes. Here: split the plan by every wall line into grid cells,
    # then repeatedly take the biggest all-inside uncovered rectangle —
    # the intuitive main body falls out first, wings after it.
    def self.grid_rects(poly)
      xs = []
      ys = []
      poly.each do |p|
        xs << p[0] unless xs.any? { |v| (v - p[0]).abs < RECT_TOL }
        ys << p[1] unless ys.any? { |v| (v - p[1]).abs < RECT_TOL }
      end
      xs.sort!
      ys.sort!
      nx = xs.length - 1
      ny = ys.length - 1
      return nil if nx < 1 || ny < 1 || nx * ny > 400
      inside = Array.new(nx) do |i|
        Array.new(ny) do |j|
          point_in_poly?(poly, (xs[i] + xs[i + 1]) / 2.0, (ys[j] + ys[j + 1]) / 2.0)
        end
      end
      covered = Array.new(nx) { Array.new(ny, false) }
      rects = []
      loop do
        best = nil
        (0...nx).each do |i0|
          (i0...nx).each do |i1|
            (0...ny).each do |j0|
              (j0...ny).each do |j1|
                good = true
                (i0..i1).each do |i|
                  (j0..j1).each { |j| good &&= inside[i][j] && !covered[i][j] }
                  break unless good
                end
                next unless good
                area = (xs[i1 + 1] - xs[i0]) * (ys[j1 + 1] - ys[j0])
                best = [area, i0, i1, j0, j1] if best.nil? || area > best[0]
              end
            end
          end
        end
        break if best.nil?
        _, i0, i1, j0, j1 = best
        (i0..i1).each { |i| (j0..j1).each { |j| covered[i][j] = true } }
        rects << [xs[i0], ys[j0], xs[i1 + 1], ys[j1 + 1]]
        return nil if rects.length > 8
      end
      (0...nx).each do |i|
        (0...ny).each { |j| return nil if inside[i][j] && !covered[i][j] }
      end
      rects.empty? ? nil : rects
    end

    def self.point_in_poly?(poly, x, y)
      n = poly.length
      c = false
      j = n - 1
      n.times do |i|
        yi = poly[i][1]
        yj = poly[j][1]
        if (yi > y) != (yj > y)
          xx = poly[i][0] + (y - yi) / (yj - yi) * (poly[j][0] - poly[i][0])
          c = !c if x < xx
        end
        j = i
      end
      c
    end

    # The side of wing rect w that touches parent rect p, or nil.
    def self.mouth_side(w, p)
      xov = [w[2], p[2]].min - [w[0], p[0]].max
      yov = [w[3], p[3]].min - [w[1], p[1]].max
      return :n if (w[3] - p[1]).abs < RECT_TOL && xov > 1.0
      return :s if (p[3] - w[1]).abs < RECT_TOL && xov > 1.0
      return :e if (w[2] - p[0]).abs < RECT_TOL && yov > 1.0
      return :w if (p[2] - w[0]).abs < RECT_TOL && yov > 1.0
      nil
    end

    # Is this rect side (a full end wall) marked gable? True when a marked
    # wall's polygon edge lies on the side's line and overlaps its span.
    def self.side_gabled?(rect, side, poly, wall_ids, marked)
      x0, y0, x1, y1 = rect
      vert = side == :w || side == :e
      line_c = { s: y0, n: y1, w: x0, e: x1 }[side]
      span = vert ? [y0, y1] : [x0, x1]
      n = poly.length
      poly.each_index.any? do |i|
        next false unless wall_ids[i] && marked.include?(wall_ids[i])
        a = poly[i]
        b = poly[(i + 1) % n]
        if vert
          next false unless (a[0] - b[0]).abs < RECT_TOL && (a[0] - line_c).abs < RECT_TOL
          lo, hi = [a[1], b[1]].minmax
        else
          next false unless (a[1] - b[1]).abs < RECT_TOL && (a[1] - line_c).abs < RECT_TOL
          lo, hi = [a[0], b[0]].minmax
        end
        [hi, span[1]].min - [lo, span[0]].max > 1.0
      end
    end

    OPP_SIDE = { n: :s, s: :n, e: :w, w: :e }.freeze unless const_defined?(:OPP_SIDE, false)

    # Choose the best rect decomposition and resolve which ends are
    # gabled. Returns { main:, g:, wings: [{rect:, mouth:, gabled:}],
    # edges: [poly edge indices on gabled ends] } or nil (fallback).
    def self.framed_plan(poly, wall_ids, marked, style)
      return nil unless rectilinear?(poly)
      rects = grid_rects(poly)
      return nil unless rects
      assemble_framed_plan(rects, poly, wall_ids, marked, style)
    end

    def self.assemble_framed_plan(rects, poly, wall_ids, marked, style)
      return nil if rects.empty? || rects.length > 8
      main_i = rects.each_index.max_by { |i| (rects[i][2] - rects[i][0]) * (rects[i][3] - rects[i][1]) }
      main = rects[main_i]
      # attach every other rect to the tree: parent = main or an already
      # attached wing (2026-08-05: chained wings are legal — a leg hanging
      # off another wing gables against ITS parent's plane the same way)
      known = [main_i]
      pending = (0...rects.length).to_a - [main_i]
      wings = []
      until pending.empty?
        pick = nil
        pending.each do |i|
          known.each do |k|
            m = mouth_side(rects[i], rects[k])
            next unless m
            pick = [i, m]
            break
          end
          break if pick
        end
        return nil unless pick # detached piece: fall back to the skeleton
        i, m = pick
        gab = side_gabled?(rects[i], OPP_SIDE[m], poly, wall_ids, marked)
        wings << { rect: rects[i], mouth: m, gabled: gab }
        known << i
        pending.delete(i)
      end
      g = {}
      [:n, :s, :e, :w].each { |sd| g[sd] = side_gabled?(main, sd, poly, wall_ids, marked) }
      if style == 'gable'
        # Gable style (2026-08-05, the user's mock: "make the WHOLE roof
        # gable"): every wing end gets its triangle automatically, and the
        # main gets its two short-end triangles — no clicks needed. Marks
        # add on top; Hip style gables marked walls only.
        wings.each { |w| w[:gabled] = true }
        unless g.values.any?
          if (main[2] - main[0]) >= (main[3] - main[1])
            g[:e] = g[:w] = true
          else
            g[:n] = g[:s] = true
          end
        end
      end
      return nil unless g.values.any? || wings.any? { |w| w[:gabled] }
      # ridge sanity: a lone gable + hip end must still leave a ridge
      if g[:e] || g[:w]
        half = (main[3] - main[1]) / 2.0
        xw = g[:w] ? main[0] : main[0] + half
        xe = g[:e] ? main[2] : main[2] - half
        return nil if xe - xw < -0.5
      elsif g[:n] || g[:s]
        half = (main[2] - main[0]) / 2.0
        ys = g[:s] ? main[1] : main[1] + half
        yn = g[:n] ? main[3] : main[3] - half
        return nil if yn - ys < -0.5
      end
      score = g.values.count(true) + wings.count { |w| w[:gabled] }
      plan = { main: main, g: g, wings: wings, score: score, nrects: rects.length }
      plan[:edges] = framed_gable_edges(poly, plan)
      plan
    end

    def self.framed_end_line(rect, side)
      x0, y0, x1, y1 = rect
      case side
      when :s then [false, y0, x0, x1]
      when :n then [false, y1, x0, x1]
      when :w then [true, x0, y0, y1]
      when :e then [true, x1, y0, y1]
      end
    end

    # Polygon edges that lie on a gabled end wall (for fascia skip + rakes).
    def self.framed_gable_edges(poly, plan)
      ends = []
      plan[:g].each { |sd, on| ends << framed_end_line(plan[:main], sd) if on }
      plan[:wings].each do |w|
        ends << framed_end_line(w[:rect], OPP_SIDE[w[:mouth]]) if w[:gabled]
      end
      n = poly.length
      (0...n).select do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        ends.any? do |(vert, c, s0, s1)|
          if vert
            (a[0] - b[0]).abs < RECT_TOL && (a[0] - c).abs < RECT_TOL &&
              [[a[1], b[1]].max, s1].min - [[a[1], b[1]].min, s0].max > 1.0
          else
            (a[1] - b[1]).abs < RECT_TOL && (a[1] - c).abs < RECT_TOL &&
              [[a[0], b[0]].max, s1].min - [[a[0], b[0]].min, s0].max > 1.0
          end
        end
      end
    end

    # sloped face: lift the plan points, track ridge + zmap, paint
    def self.framed_face!(st, pts2, lift)
      pts = pts2.map { |p| Geom::Point3d.new(p[0], p[1], lift.call(p)) }
      pts.each do |p|
        key = [p.x.round(4), p.y.round(4)]
        st[:zmap][key] = p.z if st[:zmap][key].nil? || p.z > st[:zmap][key]
        st[:ridge] = p.z if p.z > st[:ridge]
      end
      paint_surface!(st[:grp].entities.add_face(pts), st[:roof_mat], st[:under_mat])
    end

    # gable end profile: records the heights (zmap/ridge) that the rake
    # boards and bands need. NO white triangle face any more (user
    # 2026-08-05B: the wall itself will rise to the roof shape later).
    def self.framed_tri!(st, pts3)
      pts3.each do |(x, y, z)|
        key = [x.round(4), y.round(4)]
        st[:zmap][key] = z if st[:zmap][key].nil? || z > st[:zmap][key]
        st[:ridge] = z if z > st[:ridge]
      end
    end

    # Main rectangle: plain prism — gable triangle on gabled ends, hip
    # plane on the others.
    def self.build_main_rect!(st, rect, g)
      x0, y0, x1, y1 = rect
      z0d = st[:z0] + st[:delta]
      sl = st[:slope]
      axis = if g[:e] || g[:w]
               :x
             elsif g[:n] || g[:s]
               :y
             else
               (x1 - x0) >= (y1 - y0) ? :x : :y
             end
      if axis == :x
        yr = (y0 + y1) / 2.0
        zr = z0d + sl * (yr - y0)
        xw = g[:w] ? x0 : x0 + (yr - y0)
        xe = g[:e] ? x1 : x1 - (yr - y0)
        framed_face!(st, [[x0, y0], [x1, y0], [xe, yr], [xw, yr]], ->(p) { z0d + sl * (p[1] - y0) })
        framed_face!(st, [[x1, y1], [x0, y1], [xw, yr], [xe, yr]], ->(p) { z0d + sl * (y1 - p[1]) })
        if g[:w]
          framed_tri!(st, [[x0, y0, z0d], [x0, y1, z0d], [x0, yr, zr]])
        else
          framed_face!(st, [[x0, y1], [x0, y0], [xw, yr]], ->(p) { z0d + sl * (p[0] - x0) })
        end
        if g[:e]
          framed_tri!(st, [[x1, y1, z0d], [x1, y0, z0d], [x1, yr, zr]])
        else
          framed_face!(st, [[x1, y0], [x1, y1], [xe, yr]], ->(p) { z0d + sl * (x1 - p[0]) })
        end
      else
        xr = (x0 + x1) / 2.0
        zr = z0d + sl * (xr - x0)
        ys = g[:s] ? y0 : y0 + (xr - x0)
        yn = g[:n] ? y1 : y1 - (xr - x0)
        framed_face!(st, [[x0, y1], [x0, y0], [xr, ys], [xr, yn]], ->(p) { z0d + sl * (p[0] - x0) })
        framed_face!(st, [[x1, y0], [x1, y1], [xr, yn], [xr, ys]], ->(p) { z0d + sl * (x1 - p[0]) })
        if g[:s]
          framed_tri!(st, [[x0, y0, z0d], [x1, y0, z0d], [xr, y0, zr]])
        else
          framed_face!(st, [[x0, y0], [x1, y0], [xr, ys]], ->(p) { z0d + sl * (p[1] - y0) })
        end
        if g[:n]
          framed_tri!(st, [[x1, y1, z0d], [x0, y1, z0d], [xr, y1, zr]])
        else
          framed_face!(st, [[x1, y1], [x0, y1], [xr, yn]], ->(p) { z0d + sl * (y1 - p[1]) })
        end
      end
    end

    # A wing: ridge perpendicular to its mouth, gable (or hip) at the
    # outer end. The ridge dives PAST the mouth into the parent by half
    # the wing width, so the wing planes meet the parent plane exactly on
    # 45-degree valleys (same pitch everywhere).
    def self.build_wing_rect!(st, rect, mouth, gabled)
      x0, y0, x1, y1 = rect
      z0d = st[:z0] + st[:delta]
      sl = st[:slope]
      if mouth == :n || mouth == :s
        xr = (x0 + x1) / 2.0
        half = (x1 - x0) / 2.0
        zr = z0d + sl * half
        if mouth == :n # wing extends down: mouth y1, outer end y0
          pen = y1 + half
          out_r = gabled ? y0 : y0 + half
          framed_face!(st, [[x0, y1], [x0, y0], [xr, out_r], [xr, pen]], ->(p) { z0d + sl * (p[0] - x0) })
          framed_face!(st, [[x1, y0], [x1, y1], [xr, pen], [xr, out_r]], ->(p) { z0d + sl * (x1 - p[0]) })
          if gabled
            framed_tri!(st, [[x0, y0, z0d], [x1, y0, z0d], [xr, y0, zr]])
          else
            framed_face!(st, [[x0, y0], [x1, y0], [xr, out_r]], ->(p) { z0d + sl * (p[1] - y0) })
          end
        else # :s -> wing extends up: mouth y0, outer end y1
          pen = y0 - half
          out_r = gabled ? y1 : y1 - half
          framed_face!(st, [[x0, y1], [x0, y0], [xr, pen], [xr, out_r]], ->(p) { z0d + sl * (p[0] - x0) })
          framed_face!(st, [[x1, y0], [x1, y1], [xr, out_r], [xr, pen]], ->(p) { z0d + sl * (x1 - p[0]) })
          if gabled
            framed_tri!(st, [[x1, y1, z0d], [x0, y1, z0d], [xr, y1, zr]])
          else
            framed_face!(st, [[x1, y1], [x0, y1], [xr, out_r]], ->(p) { z0d + sl * (y1 - p[1]) })
          end
        end
      else
        yr = (y0 + y1) / 2.0
        half = (y1 - y0) / 2.0
        zr = z0d + sl * half
        if mouth == :e # wing extends left: mouth x1, outer end x0
          pen = x1 + half
          out_r = gabled ? x0 : x0 + half
          framed_face!(st, [[x0, y0], [x1, y0], [pen, yr], [out_r, yr]], ->(p) { z0d + sl * (p[1] - y0) })
          framed_face!(st, [[x1, y1], [x0, y1], [out_r, yr], [pen, yr]], ->(p) { z0d + sl * (y1 - p[1]) })
          if gabled
            framed_tri!(st, [[x0, y0, z0d], [x0, y1, z0d], [x0, yr, zr]])
          else
            framed_face!(st, [[x0, y1], [x0, y0], [out_r, yr]], ->(p) { z0d + sl * (p[0] - x0) })
          end
        else # :w -> wing extends right: mouth x0, outer end x1
          pen = x0 - half
          out_r = gabled ? x1 : x1 - half
          framed_face!(st, [[x0, y0], [x1, y0], [out_r, yr], [pen, yr]], ->(p) { z0d + sl * (p[1] - y0) })
          framed_face!(st, [[x1, y1], [x0, y1], [pen, yr], [out_r, yr]], ->(p) { z0d + sl * (y1 - p[1]) })
          if gabled
            framed_tri!(st, [[x1, y1, z0d], [x1, y0, z0d], [x1, yr, zr]])
          else
            framed_face!(st, [[x1, y0], [x1, y1], [out_r, yr]], ->(p) { z0d + sl * (x1 - p[0]) })
          end
        end
      end
    end

    # Build the whole framed roof. Returns [ridge, zmap] or nil.
    def self.build_framed_geometry!(grp, plan, z0, slope, overhang,
                                    roof_mat, under_mat)
      st = { grp: grp, z0: z0, delta: -slope * overhang.to_f, slope: slope,
             roof_mat: roof_mat, under_mat: under_mat, ridge: z0, zmap: {} }
      build_main_rect!(st, plan[:main], plan[:g])
      plan[:wings].each { |w| build_wing_rect!(st, w[:rect], w[:mouth], w[:gabled]) }
      [st[:ridge], st[:zmap]]
    rescue StandardError => e
      puts "[Roof] build_framed_geometry!: #{e.message}"
      nil
    end

    # Gable style: the two shortest non-adjacent edges become the gables.
    def self.pick_gable_edges(poly)
      n = poly.length
      lens = Array.new(n) { |i| vlen(vsub(poly[(i + 1) % n], poly[i])) }
      order = (0...n).sort_by { |i| lens[i] }
      first = order[0]
      second = order[1..].find { |j| j != (first + 1) % n && j != (first - 1) % n }
      [first, second].compact
    end

    # A rectangular band (fascia board / drip edge) around the eave
    # perimeter: between the outward offsets k_in and k_out of the polygon,
    # from z_top down to z_bot. One mitered box per edge, 6 faces each.
    def self.build_band!(grp, poly, k_in, k_out, z_top, z_bot, skip_flags = nil)
      inner = k_in.abs < 1e-9 ? poly : offset_polygon(poly, k_in)
      outer = offset_polygon(poly, k_out)
      return if inner.nil? || outer.nil?
      n = poly.length
      n.times do |i|
        next if skip_flags && skip_flags[i] # no fascia/drip on gable rakes
        j = (i + 1) % n
        quad = [inner[i], inner[j], outer[j], outer[i]]
        add_prism!(grp.entities, quad, z_top, z_bot)
      end
    rescue StandardError => e
      puts "[Roof] build_band!: #{e.message}"
    end

    def self.add_prism!(ents, quad, z_top, z_bot)
      top = quad.map { |p| Geom::Point3d.new(p[0], p[1], z_top) }
      bot = quad.map { |p| Geom::Point3d.new(p[0], p[1], z_bot) }
      ents.add_face(top)
      ents.add_face(bot)
      4.times do |i|
        j = (i + 1) % 4
        ents.add_face([top[i], top[j], bot[j], bot[i]])
      end
    end

    def self.remove_all!
      model = Sketchup.active_model
      rs = roofs
      return 0 if rs.empty?
      model.start_operation('InteriorPro Remove Roof', true)
      rs.each { |r| r.erase! if r.valid? }
      model.commit_operation
      puts "[Roof] removed #{rs.length} roof(s)"
      rs.length
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Roof] remove_all! failed: #{e.message}"
      0
    end
  end
end

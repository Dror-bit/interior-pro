# Interior Pro - Molding (Stage B)
# MoldingBuilder  - geometry: baseboard/crown along a wall face edge.
# MoldingManager  - whole-house apply/remove with per-wall exclusions.
# MoldingTool     - click one wall face -> baseboard (calibration/testing).
# MoldingToggleTool - click a wall to exclude/include its molding.

module InteriorPro
  module MoldingBuilder
    module_function

    # The two long face edges of a wall from its stored (mitered) corners.
    # Corner order in the attribute is NOT guaranteed (merge/move can change
    # it), so classify each corner by side of the wall axis and sort along it.
    # Returns { pos: [p0, p1, q0], neg: [p0, p1, q0] } or nil.
    def wall_edges(wall)
      flat = wall.get_attribute('InteriorPro', 'corners_xy')
      return nil unless flat && flat.length == 8
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      len = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if len < 0.001
      ux = (ex - sx) / len
      uy = (ey - sy) / len
      nx = -uy
      ny = ux

      corners = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x, y, 0) }
      mid_x = corners.sum(&:x) / 4.0
      mid_y = corners.sum(&:y) / 4.0
      pos_c = []
      neg_c = []
      corners.each do |c|
        s = (c.x - mid_x) * nx + (c.y - mid_y) * ny
        (s >= 0 ? pos_c : neg_c) << c
      end
      return nil unless pos_c.length == 2 && neg_c.length == 2

      along = ->(c) { (c.x - sx) * ux + (c.y - sy) * uy }
      pos_c.sort_by!(&along)
      neg_c.sort_by!(&along)
      { pos: [pos_c[0], pos_c[1], neg_c[0]], neg: [neg_c[0], neg_c[1], pos_c[0]] }
    end

    def remove_for_wall!(wall)
      model = Sketchup.active_model
      wid = wall.get_attribute('InteriorPro', 'id')
      model.entities.grep(Sketchup::Group).each do |g|
        t = g.get_attribute('InteriorPro', 'type')
        next unless %w[baseboard crown].include?(t)
        g.erase! if g.valid? && g.get_attribute('InteriorPro', 'host_wall_id') == wid
      end
    end

    # sides: array of :pos / :neg. crown_name nil = baseboard only.
    def build_for_wall!(wall, sides:, base_name: nil, crown_name: nil)
      edges = wall_edges(wall)
      return false unless edges
      remove_for_wall!(wall)
      sides.each do |s|
        edge = edges[s]
        next unless edge
        build_baseboard_on_edge!(wall, edge, base_name, s) if base_name
        build_crown_on_edge!(wall, edge, crown_name, s) if crown_name
      end
      true
    end

    # shifts: { start: -1/0/1, end: -1/0/1 } — 45deg miter shear per end
    # (+1 extends with depth, -1 cuts back with depth, 0 square).
    def build_baseboard_on_edge!(wall, edge, profile_name, side, shifts = { start: 0, end: 0 }, height = nil, tee_gaps = [])
      prof = MoldingLibrary.baseboard_profile_by_name(profile_name, height)
      return unless prof
      geo = edge_geometry(wall, edge)
      return unless geo
      openings = InteriorPro::WallTool.read_door_openings(wall)
      # Windows do NOT cut the baseboard (2026-08-03): an opening interrupts
      # it only when it actually reaches it — bottom (floor_offset) below the
      # baseboard top. Doors sit at 0; windows start high above it.
      base_top = begin
        prof.map { |p| p[1].to_f }.max
      rescue StandardError
        12.0
      end
      openings = openings.select { |o| o[:floor_offset].to_f < base_top }
      gaps = openings.map do |o|
        c = o[:t] + geo[:offset0]
        { a: c - o[:width] / 2.0, b: c + o[:width] / 2.0, kind: :door }
      end
      gaps += door_bbox_gaps(wall, geo).map do |g|
        { a: g[:t] - g[:width] / 2.0, b: g[:t] + g[:width] / 2.0, kind: :door }
      end
      gaps += tee_gaps.map { |g| { a: g[:a], b: g[:b], kind: :tee } }
      segs = segments_ex(geo[:len], gaps)
      make_molding_group(wall, 'baseboard', profile_name, side, height) do |ge|
        segs.each do |s|
          sa = s[:start_kind] == :run ? shifts[:start] : (s[:start_kind] == :tee ? 1 : 0)
          sb = s[:end_kind] == :run ? shifts[:end] : (s[:end_kind] == :tee ? -1 : 0)
          extrude_profile!(ge, geo, prof, s[:a], s[:b], sa, sb)
        end
      end
    end

    def build_crown_on_edge!(wall, edge, profile_name, side, shifts = { start: 0, end: 0 }, height = nil, tee_gaps = [])
      wall_h = wall.get_attribute('InteriorPro', 'height').to_f
      # Two-story wall (level-2 structure, 2026-08-03): the crown stops at
      # the CEILING ('ceiling_h' = original height), not at the raised top.
      ch = wall.get_attribute('InteriorPro', 'ceiling_h').to_f
      wall_h = ch if ch > 12.0 && ch < wall_h
      return if wall_h < 12.0
      prof = MoldingLibrary.crown_profile_by_name(profile_name, wall_h, height)
      return unless prof
      geo = edge_geometry(wall, edge)
      return unless geo
      gaps = tee_gaps.map { |g| { a: g[:a], b: g[:b], kind: :tee } }
      segs = segments_ex(geo[:len], gaps)
      make_molding_group(wall, 'crown', profile_name, side, height) do |ge|
        segs.each do |s|
          sa = s[:start_kind] == :run ? shifts[:start] : 1
          sb = s[:end_kind] == :run ? shifts[:end] : -1
          extrude_profile!(ge, geo, prof, s[:a], s[:b], sa, sb)
        end
      end
    end

    # --- helpers -----------------------------------------------------

    def edge_geometry(wall, edge)
      p0, p1, q0 = edge
      len = p0.distance(p1)
      return nil if len < 1.0
      u = Geom::Vector3d.new((p1.x - p0.x) / len, (p1.y - p0.y) / len, 0)
      # Outward direction: exactly perpendicular to the face (miters can make
      # p0-q0 skewed, so only use it for the sign).
      perp = Geom::Vector3d.new(-u.y, u.x, 0)
      sign = (p0.x - q0.x) * perp.x + (p0.y - q0.y) * perp.y >= 0 ? 1 : -1
      nd = Geom::Vector3d.new(perp.x * sign, perp.y * sign, 0)
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      offset0 = Geom::Vector3d.new(sx - p0.x, sy - p0.y, 0).dot(u)
      { p0: p0, u: u, nd: nd, len: len, offset0: offset0 }
    end

    def extrude_profile!(ge, geo, prof, a, b, sa = 0, sb = 0)
      return if b - a < 0.5
      p0 = geo[:p0]
      u = geo[:u]
      nd = geo[:nd]

      if sa.zero? && sb.zero?
        pts = prof.map do |d, z|
          Geom::Point3d.new(p0.x + u.x * a + nd.x * d,
                            p0.y + u.y * a + nd.y * d, z)
        end
        face = ge.add_face(pts)
        return unless face
        dist = b - a
        face.pushpull(face.normal.dot(u) > 0 ? dist : -dist)
        return
      end

      # Mitered end(s): build the prism manually with sheared caps.
      max_d = prof.map(&:first).max
      return if (b - a) < max_d * 2 + 0.5
      mk = lambda do |x, d, z|
        Geom::Point3d.new(p0.x + u.x * x + nd.x * d,
                          p0.y + u.y * x + nd.y * d, z)
      end
      cap_a = prof.map { |d, z| mk.call(a + sa * d, d, z) }
      cap_b = prof.map { |d, z| mk.call(b + sb * d, d, z) }
      n = prof.length
      n.times do |i|
        j = (i + 1) % n
        begin
          ge.add_face(cap_a[i], cap_a[j], cap_b[j], cap_b[i])
        rescue StandardError
          begin
            f1 = ge.add_face(cap_a[i], cap_a[j], cap_b[j])
            f2 = ge.add_face(cap_a[i], cap_b[j], cap_b[i])
            if f1 && f2
              shared = (f1.edges & f2.edges).first
              if shared
                shared.soft = true
                shared.smooth = true
              end
            end
          rescue StandardError
            nil
          end
        end
      end
      begin; ge.add_face(cap_a); rescue StandardError; end
      begin; ge.add_face(cap_b); rescue StandardError; end
    end

    def make_molding_group(wall, type, profile_name, side, height = nil)
      model = Sketchup.active_model
      # Always build at the model top level (world coords) — building inside
      # an open group/component context misplaces the molding and hides it
      # from the clear/remove scans.
      grp = model.entities.add_group
      grp.name = type.capitalize
      InteriorPro.assign_tag(grp, 'IP/Moldings')
      grp.set_attribute('InteriorPro', 'type', type)
      grp.set_attribute('InteriorPro', 'host_wall_id', wall.get_attribute('InteriorPro', 'id'))
      grp.set_attribute('InteriorPro', 'profile', profile_name)
      grp.set_attribute('InteriorPro', 'side', side.to_s)
      grp.set_attribute('InteriorPro', 'profile_h', height.to_f) if height && height.to_f > 0.01
      yield grp.entities
      if grp.valid? && grp.entities.length.zero?
        grp.erase!
      elsif grp.valid?
        soften_facets!(grp.entities)
        grp.material = molding_material(model, wall)
        # base_z awareness (2026-07-23): a dropped wall (garage) carries a Z
        # translation in its group transformation. corners_xy is local (flat
        # z=0), so the molding is built at the HOUSE floor (baseboard z~=0,
        # crown z~=wall_h). Shift the whole run down to the wall's real base
        # so it sits on the garage floor / at the dropped wall top.
        bz = wall_base_z(wall)
        if bz.abs > 0.001 && grp.valid?
          grp.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, bz)))
        end
      end
      grp
    end

    # Vertical base of a wall: the 'base_z' attribute (set by set_wall_base!),
    # falling back to the group transformation's Z origin. 0 for normal walls.
    def wall_base_z(wall)
      bz = wall.get_attribute('InteriorPro', 'base_z')
      return bz.to_f unless bz.nil?
      wall.transformation.origin.z
    rescue StandardError
      0.0
    end

    # Facet angle threshold for hiding curve-facet lines (radians).
    FACET_ANGLE = 25.0 * Math::PI / 180.0 unless const_defined?(:FACET_ANGLE, false)

    # Hide the longitudinal facet lines of curved profiles: soften edges
    # between two nearly-parallel faces. Corners and sharp profile breaks
    # (angle > threshold) stay visible.
    def soften_facets!(ents)
      ents.grep(Sketchup::Edge).each do |e|
        fs = e.faces
        next unless fs.length == 2
        next if fs[0].normal.angle_between(fs[1].normal) > FACET_ANGLE
        e.soft = true
        e.smooth = true
      end
    end

    # Exact along-wall span of each hosted door (including its casing),
    # from the door group's bounding box projected onto the face edge.
    def door_bbox_gaps(wall, geo)
      wid = wall.get_attribute('InteriorPro', 'id')
      p0 = geo[:p0]
      u = geo[:u]
      out = []
      Sketchup.active_model.entities.each do |g|
        next unless g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)
        next unless g.get_attribute('InteriorPro', 'host_wall_id') == wid
        next unless g.get_attribute('InteriorPro', 'type') == 'door'
        bb = g.bounds
        ts = (0..7).map do |i|
          c = bb.corner(i)
          (c.x - p0.x) * u.x + (c.y - p0.y) * u.y
        end
        t0 = ts.min
        t1 = ts.max
        out << { t: (t0 + t1) / 2.0, width: t1 - t0 } if t1 - t0 > 1.0
      end
      out
    end

    # Like segments, but each gap is {a:, b:, kind: :door/:tee} and each
    # returned segment records what bounds it at each end
    # (:run = wall end, :door = door opening, :tee = T-junction wall).
    def segments_ex(len, gaps)
      list = gaps.map { |g| { a: [g[:a], 0.0].max, b: [g[:b], len].min, kind: g[:kind] } }
                 .select { |g| g[:b] > g[:a] }
                 .sort_by { |g| g[:a] }
      segs = []
      cur = 0.0
      cur_kind = :run
      list.each do |g|
        segs << { a: cur, b: g[:a], start_kind: cur_kind, end_kind: g[:kind] } if g[:a] > cur
        if g[:b] > cur
          cur = g[:b]
          cur_kind = g[:kind]
        end
      end
      segs << { a: cur, b: len, start_kind: cur_kind, end_kind: :run } if len > cur
      segs
    end

    def segments(len, openings)
      gaps = openings.map { |o| [o[:t] - o[:width] / 2.0, o[:t] + o[:width] / 2.0] }
                     .map { |a, b| [[a, 0.0].max, [b, len].min] }
                     .select { |a, b| b > a }
                     .sort_by(&:first)
      segs = []
      cur = 0.0
      gaps.each do |a, b|
        segs << [cur, a] if a > cur
        cur = b if b > cur
      end
      segs << [cur, len] if len > cur
      segs
    end

    # Molding color mode: 'white' (default) or 'wall' (each wall's interior
    # color). Stored on the model so refresh! and reopening keep the choice.
    def color_mode(model)
      model.get_attribute('InteriorPro', 'molding_color_mode') == 'wall' ? 'wall' : 'white'
    end

    def molding_material(model, wall = nil)
      if wall && color_mode(model) == 'wall'
        hex = wall.get_attribute('InteriorPro', 'interior_material').to_s
        if hex.start_with?('#') && hex.length == 7
          name = "InteriorPro_Molding_#{hex.delete('#')}"
          m = model.materials[name]
          return m if m
          m = model.materials.add(name)
          m.color = Sketchup::Color.new(hex)
          return m
        end
      end
      m = model.materials['InteriorPro_Molding']
      return m if m
      m = model.materials.add('InteriorPro_Molding')
      m.color = Sketchup::Color.new(245, 245, 240)
      m
    end
  end

  module MoldingManager
    module_function

    def walls(model = Sketchup.active_model)
      model.entities.grep(Sketchup::Group).select do |g|
        g.get_attribute('InteriorPro', 'type') == 'wall'
      end
    end

    # Interior walls: both sides. Exterior walls: molding only on faces that
    # bound a detected room — probe point 2" in front of the face midpoint
    # tested against the room boundary polygons (boundary_xy, world coords).
    # Keeps exterior-space faces (entry alcove etc.) molding-free and picks
    # the correct room-facing side. Fallback when the model has no rooms:
    # the old house-centroid heuristic.
    def sides_for(wall, centroid)
      return %i[pos neg] if wall.get_attribute('InteriorPro', 'wall_category') == 'interior'
      edges = MoldingBuilder.wall_edges(wall)
      return [] unless edges
      # Per-level rooms (2026-08-04): a wall consults only the rooms of its
      # OWN level. No rooms on that level yet -> centroid heuristic below.
      rooms = room_polys(wall_lvl(wall))
      if rooms.any?
        sides = []
        %i[pos neg].each do |s|
          geo = MoldingBuilder.edge_geometry(wall, edges[s])
          next unless geo
          probe = geo[:p0].offset(geo[:u], geo[:len] / 2.0).offset(geo[:nd], 2.0)
          sides << s if rooms.any? { |poly| Geom.point_in_polygon_2D(probe, poly, true) }
        end
        return sides
      end
      p0, p1, = edges[:pos]
      mid = Geom::Point3d.new((p0.x + p1.x) / 2.0, (p0.y + p1.y) / 2.0, 0)
      nd = MoldingBuilder.edge_geometry(wall, edges[:pos])[:nd]
      to_c = Geom::Vector3d.new(centroid.x - mid.x, centroid.y - mid.y, 0)
      to_c.dot(nd) >= 0 ? [:pos] : [:neg]
    end

    # Boundary polygons (world coords, interior faces) of the room entities
    # of ONE level (per-level rooms, 2026-08-04).
    def room_polys(level = 1)
      Sketchup.active_model.entities.grep(Sketchup::Group).map do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'room'
        next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == level.to_i
        flat = g.get_attribute('InteriorPro', 'boundary_xy')
        next unless flat && flat.length >= 6
        flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0) }
      end.compact
    end

    def house_centroid(ws)
      xs = 0.0
      ys = 0.0
      ws.each do |w|
        sx = w.get_attribute('InteriorPro', 'start_x').to_f
        sy = w.get_attribute('InteriorPro', 'start_y').to_f
        ex = w.get_attribute('InteriorPro', 'end_x').to_f
        ey = w.get_attribute('InteriorPro', 'end_y').to_f
        xs += (sx + ex) / 2.0
        ys += (sy + ey) / 2.0
      end
      n = [ws.length, 1].max
      Geom::Point3d.new(xs / n, ys / n, 0)
    end

    def last_profiles
      @last_profiles ||= { base: nil, crown: nil }
    end

    # Group walls into connected structures (endpoints touching, tol 1"),
    # so each building gets its own centroid (two separate structures in
    # one model used to flip the interior side).
    def wall_components(ws)
      pts = {}
      ws.each do |w|
        sx = w.get_attribute('InteriorPro', 'start_x').to_f
        sy = w.get_attribute('InteriorPro', 'start_y').to_f
        ex = w.get_attribute('InteriorPro', 'end_x').to_f
        ey = w.get_attribute('InteriorPro', 'end_y').to_f
        pts[w] = [[sx, sy], [ex, ey]]
      end
      remaining = ws.dup
      comps = []
      until remaining.empty?
        comp = [remaining.shift]
        queue = comp.dup
        until queue.empty?
          cur = queue.shift
          remaining.reject! do |o|
            touch = pts[cur].any? do |a|
              pts[o].any? { |b| (a[0] - b[0])**2 + (a[1] - b[1])**2 < 1.0 }
            end
            if touch
              comp << o
              queue << o
            end
            touch
          end
        end
        comps << comp
      end
      comps
    end

    # transparent: true folds this rebuild into the PREVIOUS undo step - used
    # when the refresh runs as the tail of another gesture (placing a door),
    # so one Ctrl+Z undoes the door AND the molding re-cut together
    # (user 2026-08-12: "Ctrl+Z doesn't return my last action, or only one").
    def apply_all!(base_name: nil, crown_name: nil, base_h: nil, crown_h: nil,
                   color_mode: nil, transparent: false)
      model = Sketchup.active_model
      model.set_attribute('InteriorPro', 'molding_color_mode', color_mode) if color_mode
      last_profiles[:base] = base_name
      last_profiles[:crown] = crown_name
      last_profiles[:base_h] = base_h
      last_profiles[:crown_h] = crown_h
      ws = walls(model)
      if ws.empty?
        puts '[Molding] no walls found'
        return
      end
      # Per-structure centroid (separate buildings get separate centers).
      cent = {}
      wall_components(ws).each do |comp|
        cc = house_centroid(comp)
        comp.each { |w| cent[w] = cc }
      end

      # Collect all molding runs first, then resolve 45deg miters at shared
      # corners between runs.
      plan = []
      ws.each do |w|
        next if w.get_attribute('InteriorPro', 'no_molding')
        edges = MoldingBuilder.wall_edges(w)
        next unless edges
        # Per-side exclusion (2026-07-23): the garage-facing side of an
        # interior wall sits on concrete and wants no baseboard. An excluded
        # side STAYS in the plan (build: false) so it still cuts crossing
        # walls' molding at T-junctions — e.g. the garage separating wall
        # must still interrupt the house back-wall crown — but is not built.
        sides_for(w, cent[w]).each do |s|
          geo = MoldingBuilder.edge_geometry(w, edges[s])
          next unless geo
          excluded = w.get_attribute("InteriorPro", "no_molding_#{s}") ? true : false
          plan << { wall: w, side: s, edge: edges[s], geo: geo,
                    shifts: { start: 0, end: 0 }, tee_gaps: [], build: !excluded }
        end
      end
      resolve_miters!(plan)
      resolve_tees!(plan)
      resolve_flush_butts!(plan)

      model.start_operation('Molding: Apply All', true, false, transparent)
      # Clear ALL existing molding first (incl. walls excluded since the
      # last apply), then rebuild only the planned runs.
      model.entities.grep(Sketchup::Group).each do |g|
        t = g.get_attribute('InteriorPro', 'type')
        g.erase! if %w[baseboard crown].include?(t) && g.valid?
      end
      count = 0
      built = 0
      plan.group_by { |r| r[:wall] }.each do |w, runs|
        wall_built = false
        runs.each do |r|
          next if r[:build] == false # excluded side: shapes the plan, not built
          wall_built = true
          if base_name
            MoldingBuilder.build_baseboard_on_edge!(w, r[:edge], base_name,
                                                    r[:side], r[:shifts], base_h,
                                                    r[:tee_gaps] || [])
          end
          if crown_name
            MoldingBuilder.build_crown_on_edge!(w, r[:edge], crown_name,
                                                r[:side], r[:shifts], crown_h,
                                                r[:tee_gaps] || [])
          end
          built += 1
        end
        count += 1 if wall_built
      end
      model.commit_operation
      puts "[Molding] applied to #{count}/#{ws.length} walls, #{built} runs (base=#{base_name.inspect} crown=#{crown_name.inspect})"
    rescue StandardError => e
      begin; model.abort_operation; rescue StandardError; end
      puts "[Molding] apply error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end

    # For every pair of runs whose face-edge endpoints meet, set the miter
    # shear: inside corner cuts back with depth, outside corner extends.
    MITER_TOL = 1.0 unless const_defined?(:MITER_TOL, false)

    def wall_cat(w)
      (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
    end

    # Levels (2026-08-03): walls of different levels share the same x/y and
    # all the resolver maths is flat (z=0) - so miters/tees/butts must pair
    # runs WITHIN one level only, exactly like find_neighbor_at does.
    def wall_lvl(w)
      (w.get_attribute('InteriorPro', 'level') || 1).to_i
    end

    def resolve_miters!(plan)
      ends = lambda do |r|
        g = r[:geo]
        [g[:p0], g[:p0].offset(g[:u], g[:len])]
      end
      plan.each do |r|
        r0, r1 = ends.call(r)
        plan.each do |o|
          next if o.equal?(r)
          # Cross-category contact is a butt joint (interior wall trimmed to
          # the exterior wall's face, 2026-07-16) — handled by resolve_tees!,
          # never a miter corner.
          next if wall_cat(r[:wall]) != wall_cat(o[:wall])
          next if wall_lvl(r[:wall]) != wall_lvl(o[:wall])
          o0, o1 = ends.call(o)
          og = o[:geo]
          # direction pointing AWAY from the shared corner along the neighbor
          if r1.distance(o0) < MITER_TOL
            r[:shifts][:end] = end_shift(og[:u], r[:geo][:nd])
          elsif r1.distance(o1) < MITER_TOL
            r[:shifts][:end] = end_shift(og[:u].reverse, r[:geo][:nd])
          end
          if r0.distance(o1) < MITER_TOL
            r[:shifts][:start] = -end_shift(og[:u].reverse, r[:geo][:nd])
          elsif r0.distance(o0) < MITER_TOL
            r[:shifts][:start] = -end_shift(og[:u], r[:geo][:nd])
          end
        end
      end
    end

    # T-junctions: a run whose end touches the MIDDLE of another run's edge.
    # The stub run gets an inside-corner shear at that end; the crossing run
    # gets a gap between the stub wall's two side runs (mitered on both edges).
    def resolve_tees!(plan)
      bounds = Hash.new { |h, k| h[k] = [] }
      plan.each do |stub|
        g = stub[:geo]
        [[g[:p0], :start], [g[:p0].offset(g[:u], g[:len]), :end]].each do |pt, which|
          plan.each do |r|
            next if r.equal?(stub) || r[:wall] == stub[:wall]
            next if wall_lvl(r[:wall]) != wall_lvl(stub[:wall])
            rg = r[:geo]
            v = Geom::Vector3d.new(pt.x - rg[:p0].x, pt.y - rg[:p0].y, 0)
            t = v.dot(rg[:u])
            # Same category: only a true mid-run touch is a T (ends stay
            # miter corners). Cross category (butt joint): a butt landing
            # near the crossing run's end is still a T — allow the full
            # span; the gap is clamped to [0, len] by segments_ex and a
            # leftover sliver < 0.5" is dropped by extrude_profile!.
            if wall_cat(stub[:wall]) == wall_cat(r[:wall])
              next if t < MITER_TOL || t > rg[:len] - MITER_TOL
            else
              # Butt model: only an INTERIOR wall can be a stub against an
              # exterior run. The reverse touch (an exterior run's endpoint
              # on an interior run) is just the other side of the same butt
              # contact — registering it would overwrite the corner miter
              # shears with bogus stub shears.
              next unless wall_cat(stub[:wall]) == 'interior'
              next if t < -MITER_TOL || t > rg[:len] + MITER_TOL
            end
            off = Math.sqrt([(v.length**2) - t**2, 0.0].max)
            next if off > MITER_TOL
            stub[:shifts][which] = which == :end ? -1 : 1
            bounds[r] << { t: t, wall: stub[:wall] }
          end
        end
      end
      bounds.each do |r, list|
        list.group_by { |b| b[:wall] }.each_value do |bs|
          next unless bs.length == 2
          a, b = bs.map { |x| x[:t] }.minmax
          next if b - a < 0.5 || b - a > 24.0
          r[:tee_gaps] << { a: a, b: b }
        end
      end
    end

    # Flush butt at an exterior corner: an interior wall butting exactly at
    # the END of an exterior wall leaves two COLLINEAR runs (the interior
    # wall's face run continuing the exterior wall's face run) meeting
    # end-to-end. Join them with a straight square seam instead of the
    # crossing 45deg shears the miter/tee passes produce.
    def resolve_flush_butts!(plan)
      ipts = lambda do |r|
        g = r[:geo]
        { start: g[:p0], end: g[:p0].offset(g[:u], g[:len]) }
      end
      plan.each do |ri|
        next unless wall_cat(ri[:wall]) == 'interior'
        plan.each do |ro|
          next unless wall_cat(ro[:wall]) == 'exterior'
          next if wall_lvl(ri[:wall]) != wall_lvl(ro[:wall])
          ui = ri[:geo][:u]
          uo = ro[:geo][:u]
          next if (ui.x * uo.y - ui.y * uo.x).abs > 0.02 # not parallel
          ipts.call(ri).each do |wi, pi|
            ipts.call(ro).each do |wo, po|
              next if pi.distance(po) > MITER_TOL
              ri[:shifts][wi] = 0
              ro[:shifts][wo] = 0
            end
          end
        end
      end
    end

    def end_shift(u_away, nd)
      k = u_away.dot(nd)
      return -1 if k > 0.5   # inside corner
      return 1 if k < -0.5   # outside corner
      0                      # straight continuation
    end

    # Rebuild all molding with the profiles currently in the model.
    # Called after door place/move/delete so molding stays cut correctly.
    def refresh!(transparent: false)
      model = Sketchup.active_model
      base = nil
      crown = nil
      base_h = nil
      crown_h = nil
      model.entities.grep(Sketchup::Group).each do |g|
        case g.get_attribute('InteriorPro', 'type')
        when 'baseboard'
          base ||= g.get_attribute('InteriorPro', 'profile')
          base_h ||= g.get_attribute('InteriorPro', 'profile_h')
        when 'crown'
          crown ||= g.get_attribute('InteriorPro', 'profile')
          crown_h ||= g.get_attribute('InteriorPro', 'profile_h')
        end
        break if base && crown
      end
      return unless base || crown
      apply_all!(base_name: base, crown_name: crown, base_h: base_h, crown_h: crown_h,
                 transparent: transparent)
    end

    # Apply molding ONLY to the currently selected walls; all other walls
    # are marked no_molding (the toggle tool keeps working afterwards).
    def apply_to_selection!(base_name: nil, crown_name: nil, base_h: nil, crown_h: nil, color_mode: nil)
      model = Sketchup.active_model
      sel = model.selection.to_a.select do |g|
        (g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)) &&
          g.get_attribute('InteriorPro', 'type') == 'wall'
      end
      if sel.empty?
        UI.messagebox('Select one or more walls first, then Apply to Selected')
        return
      end
      # Union: walls that already have molding keep it; the selected walls
      # join; only walls with no molding and not selected are excluded.
      has_molding = {}
      model.entities.grep(Sketchup::Group).each do |g|
        next unless %w[baseboard crown].include?(g.get_attribute('InteriorPro', 'type'))
        has_molding[g.get_attribute('InteriorPro', 'host_wall_id')] = true
      end
      walls(model).each do |w|
        if sel.include?(w)
          w.set_attribute('InteriorPro', 'no_molding', false)
        elsif !has_molding[w.get_attribute('InteriorPro', 'id')]
          w.set_attribute('InteriorPro', 'no_molding', true)
        end
      end
      apply_all!(base_name: base_name, crown_name: crown_name,
                 base_h: base_h, crown_h: crown_h, color_mode: color_mode)
    end

    # Clear no_molding on all walls (used by the dialog's Apply to House).
    def include_all_walls!
      walls(Sketchup.active_model).each do |w|
        w.set_attribute('InteriorPro', 'no_molding', false)
      end
    end

    def remove_all!
      model = Sketchup.active_model
      model.start_operation('Molding: Remove All', true)
      n = 0
      model.entities.grep(Sketchup::Group).each do |g|
        t = g.get_attribute('InteriorPro', 'type')
        next unless %w[baseboard crown].include?(t)
        g.erase! if g.valid?
        n += 1
      end
      model.commit_operation
      puts "[Molding] removed #{n} molding groups"
    end

    # Prompt with dropdowns, then apply to the whole house.
    def apply_with_prompt!
      base_opts = ['(none)'] + MoldingLibrary.baseboard_names
      crown_opts = ['(none)'] + MoldingLibrary.crown_names
      res = UI.inputbox(
        ['Baseboard', 'Crown'],
        [MoldingLibrary.baseboard_names.first, MoldingLibrary.crown_names.first],
        [base_opts.join('|'), crown_opts.join('|')],
        'Interior Pro - Molding'
      )
      return unless res
      base = res[0] == '(none)' ? nil : res[0]
      crown = res[1] == '(none)' ? nil : res[1]
      apply_all!(base_name: base, crown_name: crown)
    end
  end

  # Click one wall face -> baseboard on that face (testing/calibration).
  class MoldingTool
    def initialize(profile_name = nil)
      @profile_name = profile_name || MoldingLibrary.baseboard_names.first
    end

    def activate
      Sketchup.status_text = "Baseboard (#{@profile_name}): click a wall face"
    end

    def onLButtonDown(_flags, x, y, view)
      wall = pick_wall(view, x, y)
      return UI.messagebox('Click on an Interior Pro wall') unless wall
      click_pt = view.inputpoint(x, y).position
      edges = MoldingBuilder.wall_edges(wall)
      return unless edges
      d_pos = click_pt.distance(click_pt.project_to_line([edges[:pos][0], edges[:pos][1]]))
      d_neg = click_pt.distance(click_pt.project_to_line([edges[:neg][0], edges[:neg][1]]))
      side = d_pos <= d_neg ? :pos : :neg
      model = Sketchup.active_model
      model.start_operation('Baseboard', true)
      MoldingBuilder.build_baseboard_on_edge!(wall, edges[side], @profile_name, side)
      model.commit_operation
      puts "[MoldingTool] baseboard side=#{side} wall=#{wall.get_attribute('InteriorPro', 'id')}"
      view.invalidate
    rescue StandardError => e
      puts "[MoldingTool] error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end

    private

    def pick_wall(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end
      nil
    end
  end

  # Click a wall FACE (or its molding) -> toggle molding off/on for THAT
  # SIDE only (2026-07-23). Removing the garage-facing baseboard on an
  # interior wall: click that face; click again to restore. Two clicks (one
  # per side) exclude the whole wall.
  class MoldingToggleTool
    def activate
      Sketchup.status_text = 'Molding toggle: click a wall face (or its molding) to remove/restore that side'
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      wall = nil
      clicked_side = nil
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
          t = ent.get_attribute('InteriorPro', 'type')
          if t == 'wall'
            wall = ent
          elsif %w[baseboard crown].include?(t)
            wid = ent.get_attribute('InteriorPro', 'host_wall_id')
            wall = MoldingManager.walls.find { |w| w.get_attribute('InteriorPro', 'id') == wid }
            s = ent.get_attribute('InteriorPro', 'side')
            clicked_side = s.to_sym if s
          end
          break if wall
        end
        break if wall
      end
      return UI.messagebox('Click a wall face or its molding') unless wall

      # Clicked the bare wall body: pick the side whose face edge is nearest
      # the click point (XY only — flat, so dropped garage walls work too).
      if clicked_side.nil?
        edges = MoldingBuilder.wall_edges(wall)
        if edges
          cp = view.inputpoint(x, y).position
          cp = Geom::Point3d.new(cp.x, cp.y, 0)
          d_pos = cp.distance(cp.project_to_line([edges[:pos][0], edges[:pos][1]]))
          d_neg = cp.distance(cp.project_to_line([edges[:neg][0], edges[:neg][1]]))
          clicked_side = d_pos <= d_neg ? :pos : :neg
        else
          clicked_side = :pos
        end
      end

      key = "no_molding_#{clicked_side}"
      now_excluded = !wall.get_attribute('InteriorPro', key)
      wall.set_attribute('InteriorPro', key, now_excluded)
      # Restoring a side also clears any whole-wall exclusion, so a wall
      # hidden by the old whole-wall toggle can be brought back per side.
      wall.set_attribute('InteriorPro', 'no_molding', false) unless now_excluded
      rebuild_molding!
      puts "[Molding] side #{clicked_side} #{now_excluded ? 'excluded' : 'restored'} " \
           "on wall #{wall.get_attribute('InteriorPro', 'id')}"
      view.invalidate
    rescue StandardError => e
      puts "[MoldingToggle] error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end

    private

    # Rebuild with the last dialog choice (None respected); after restart
    # fall back to detecting the profiles from the model.
    def rebuild_molding!
      lp = MoldingManager.last_profiles
      if lp[:base] || lp[:crown]
        MoldingManager.apply_all!(base_name: lp[:base], crown_name: lp[:crown],
                                  base_h: lp[:base_h], crown_h: lp[:crown_h])
      else
        MoldingManager.refresh!
      end
    end
  end
end

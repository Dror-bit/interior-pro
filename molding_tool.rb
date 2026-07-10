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
    def build_baseboard_on_edge!(wall, edge, profile_name, side, shifts = { start: 0, end: 0 })
      spec = MoldingLibrary::BASEBOARDS[profile_name]
      return unless spec
      prof = MoldingLibrary.baseboard_profile(spec)
      geo = edge_geometry(wall, edge)
      return unless geo
      openings = InteriorPro::WallTool.read_door_openings(wall)
      gaps = openings.map { |o| { t: o[:t] + geo[:offset0], width: o[:width] } }
      gaps += door_bbox_gaps(wall, geo)
      segs = segments(geo[:len], gaps)
      make_molding_group(wall, 'baseboard', profile_name, side) do |ge|
        segs.each do |a, b|
          sa = a.abs < 0.01 ? shifts[:start] : 0
          sb = (b - geo[:len]).abs < 0.01 ? shifts[:end] : 0
          extrude_profile!(ge, geo, prof, a, b, sa, sb)
        end
      end
    end

    def build_crown_on_edge!(wall, edge, profile_name, side, shifts = { start: 0, end: 0 })
      spec = MoldingLibrary::CROWNS[profile_name]
      return unless spec
      wall_h = wall.get_attribute('InteriorPro', 'height').to_f
      return if wall_h < 12.0
      prof = MoldingLibrary.crown_profile(spec, wall_h)
      geo = edge_geometry(wall, edge)
      return unless geo
      make_molding_group(wall, 'crown', profile_name, side) do |ge|
        extrude_profile!(ge, geo, prof, 0.0, geo[:len], shifts[:start], shifts[:end])
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

    def make_molding_group(wall, type, profile_name, side)
      model = Sketchup.active_model
      grp = model.active_entities.add_group
      grp.name = type.capitalize
      grp.set_attribute('InteriorPro', 'type', type)
      grp.set_attribute('InteriorPro', 'host_wall_id', wall.get_attribute('InteriorPro', 'id'))
      grp.set_attribute('InteriorPro', 'profile', profile_name)
      grp.set_attribute('InteriorPro', 'side', side.to_s)
      yield grp.entities
      if grp.valid? && grp.entities.length.zero?
        grp.erase!
      elsif grp.valid?
        grp.material = molding_material(model)
      end
      grp
    end

    # Exact along-wall span of each hosted door (including its casing),
    # from the door group's bounding box projected onto the face edge.
    def door_bbox_gaps(wall, geo)
      wid = wall.get_attribute('InteriorPro', 'id')
      p0 = geo[:p0]
      u = geo[:u]
      out = []
      Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
        next unless g.get_attribute('InteriorPro', 'host_wall_id') == wid
        next unless g.get_attribute('InteriorPro', 'door_id')
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

    def molding_material(model)
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

    # Interior walls: both sides. Exterior walls: only the side facing
    # the centroid of the house.
    def sides_for(wall, centroid)
      return %i[pos neg] if wall.get_attribute('InteriorPro', 'wall_category') == 'interior'
      edges = MoldingBuilder.wall_edges(wall)
      return [] unless edges
      p0, p1, = edges[:pos]
      mid = Geom::Point3d.new((p0.x + p1.x) / 2.0, (p0.y + p1.y) / 2.0, 0)
      nd = MoldingBuilder.edge_geometry(wall, edges[:pos])[:nd]
      to_c = Geom::Vector3d.new(centroid.x - mid.x, centroid.y - mid.y, 0)
      to_c.dot(nd) >= 0 ? [:pos] : [:neg]
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

    def apply_all!(base_name: nil, crown_name: nil)
      model = Sketchup.active_model
      last_profiles[:base] = base_name
      last_profiles[:crown] = crown_name
      ws = walls(model)
      if ws.empty?
        puts '[Molding] no walls found'
        return
      end
      c = house_centroid(ws)

      # Collect all molding runs first, then resolve 45deg miters at shared
      # corners between runs.
      plan = []
      ws.each do |w|
        next if w.get_attribute('InteriorPro', 'no_molding')
        edges = MoldingBuilder.wall_edges(w)
        next unless edges
        sides_for(w, c).each do |s|
          geo = MoldingBuilder.edge_geometry(w, edges[s])
          next unless geo
          plan << { wall: w, side: s, edge: edges[s], geo: geo,
                    shifts: { start: 0, end: 0 } }
        end
      end
      resolve_miters!(plan)

      model.start_operation('Molding: Apply All', true)
      count = 0
      plan.group_by { |r| r[:wall] }.each do |w, runs|
        MoldingBuilder.remove_for_wall!(w)
        runs.each do |r|
          if base_name
            MoldingBuilder.build_baseboard_on_edge!(w, r[:edge], base_name,
                                                    r[:side], r[:shifts])
          end
          if crown_name
            MoldingBuilder.build_crown_on_edge!(w, r[:edge], crown_name,
                                                r[:side], r[:shifts])
          end
        end
        count += 1
      end
      model.commit_operation
      puts "[Molding] applied to #{count}/#{ws.length} walls, #{plan.length} runs (base=#{base_name.inspect} crown=#{crown_name.inspect})"
    rescue StandardError => e
      begin; model.abort_operation; rescue StandardError; end
      puts "[Molding] apply error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end

    # For every pair of runs whose face-edge endpoints meet, set the miter
    # shear: inside corner cuts back with depth, outside corner extends.
    MITER_TOL = 1.0 unless const_defined?(:MITER_TOL, false)

    def resolve_miters!(plan)
      ends = lambda do |r|
        g = r[:geo]
        [g[:p0], g[:p0].offset(g[:u], g[:len])]
      end
      plan.each do |r|
        r0, r1 = ends.call(r)
        plan.each do |o|
          next if o.equal?(r)
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

    def end_shift(u_away, nd)
      k = u_away.dot(nd)
      return -1 if k > 0.5   # inside corner
      return 1 if k < -0.5   # outside corner
      0                      # straight continuation
    end

    # Rebuild all molding with the profiles currently in the model.
    # Called after door place/move/delete so molding stays cut correctly.
    def refresh!
      model = Sketchup.active_model
      base = nil
      crown = nil
      model.entities.grep(Sketchup::Group).each do |g|
        case g.get_attribute('InteriorPro', 'type')
        when 'baseboard' then base ||= g.get_attribute('InteriorPro', 'profile')
        when 'crown'     then crown ||= g.get_attribute('InteriorPro', 'profile')
        end
        break if base && crown
      end
      return unless base || crown
      apply_all!(base_name: base, crown_name: crown)
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
      base_opts = ['(none)'] + MoldingLibrary::BASEBOARDS.keys
      crown_opts = ['(none)'] + MoldingLibrary::CROWNS.keys
      res = UI.inputbox(
        ['Baseboard', 'Crown'],
        [MoldingLibrary::BASEBOARDS.keys.first, MoldingLibrary::CROWNS.keys.first],
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
      @profile_name = profile_name || MoldingLibrary::BASEBOARDS.keys.first
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

  # Click a wall (or its molding) -> toggle molding off/on for that wall.
  class MoldingToggleTool
    def activate
      Sketchup.status_text = 'Molding toggle: click a wall to remove/restore its molding'
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      wall = nil
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
          end
          break if wall
        end
        break if wall
      end
      return UI.messagebox('Click a wall or its molding') unless wall

      model = Sketchup.active_model
      lp = MoldingManager.last_profiles
      base = lp[:base] || MoldingLibrary::BASEBOARDS.keys.first
      crown = lp[:crown] || MoldingLibrary::CROWNS.keys.first
      if wall.get_attribute('InteriorPro', 'no_molding')
        wall.set_attribute('InteriorPro', 'no_molding', false)
        MoldingManager.apply_all!(base_name: base, crown_name: crown)
        puts '[Molding] wall restored'
      else
        wall.set_attribute('InteriorPro', 'no_molding', true)
        model.start_operation('Molding: Exclude Wall', true)
        MoldingBuilder.remove_for_wall!(wall)
        model.commit_operation
        puts '[Molding] wall excluded'
      end
      view.invalidate
    rescue StandardError => e
      puts "[MoldingToggle] error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end
end

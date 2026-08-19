# Interior Pro - Wall Split Tool (2026-07-18)
# Click a wall at a point -> the wall is split into TWO walls at that point
# (projected onto the drawn line). Attributes are copied (ids get A/B
# suffixes), door/window openings and their bodies are redistributed to the
# correct half, corners re-join, rooms re-sync. The split position snaps to
# a touching wall's contact point when one is nearby (the garage-boundary
# case). Splitting THROUGH an opening is refused.
# The split core is a class method so the future room-level automation
# ("drop walls with floor") can reuse it directly.

module InteriorPro
  class WallSplitTool
    SNAP_TOL = 16.0 unless const_defined?(:SNAP_TOL, false) # inches, snap to touching wall

    def activate
      @preview = nil
      Sketchup.set_status_text('Hover a wall — the cut line follows; click to split (green = snapped)', SB_PROMPT)
    end

    def deactivate(view)
      @preview = nil
      view.invalidate
    end

    # Live ghost: track the wall under the cursor and the (snapped) split
    # position; draw() renders the cutting plane outline.
    def onMouseMove(_flags, x, y, view)
      wall = pick_wall(view, x, y)
      unless wall
        if @preview
          @preview = nil
          view.invalidate
        end
        return
      end
      pos = position_on_wall(wall, view, x, y)
      unless pos
        @preview = nil
        view.invalidate
        return
      end
      snapped = self.class.snap_to_touching(wall, pos)
      @preview = { wall: wall, pos: snapped[:pos], snapped: snapped[:snapped] }
      Sketchup.set_status_text(
        format('Split at %.1f"%s — click to cut', snapped[:pos], snapped[:snapped] ? ' (SNAPPED)' : ''),
        SB_PROMPT
      )
      view.invalidate
    end

    def draw(view)
      return unless @preview
      pts = self.class.cut_plane_points(@preview[:wall], @preview[:pos])
      return unless pts
      view.drawing_color = @preview[:snapped] ? Sketchup::Color.new(0, 190, 60) : Sketchup::Color.new(230, 40, 40)
      view.line_width = 3
      view.line_stipple = '-'
      view.draw(GL_LINE_LOOP, pts)
      view.line_stipple = ''
    end

    def getExtents
      bb = Geom::BoundingBox.new
      if @preview
        pts = self.class.cut_plane_points(@preview[:wall], @preview[:pos])
        pts&.each { |p| bb.add(p) }
      end
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      wall = pick_wall(view, x, y)
      return UI.messagebox('Click an Interior Pro wall') unless wall
      pos = @preview && @preview[:wall] == wall ? @preview[:pos] : position_on_wall(wall, view, x, y)
      return unless pos
      result = self.class.split_wall!(wall, pos)
      if result
        @preview = nil
        view.invalidate
      end
    rescue StandardError => e
      puts "[WallSplitTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    private

    def pick_wall(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end
      nil
    end

    def position_on_wall(wall, view, x, y)
      click = view.inputpoint(x, y).position
      drawn = self.class.drawn_line_world(wall)
      return nil unless drawn
      unit = drawn[1] - drawn[0]
      len = unit.length
      return nil if len < 2.0
      unit.normalize!
      flat = Geom::Point3d.new(click.x, click.y, 0)
      pos = (flat - Geom::Point3d.new(drawn[0].x, drawn[0].y, 0)).dot(Geom::Vector3d.new(unit.x, unit.y, 0))
      pos.clamp(0.0, len)
    end

    # ---------- class-level core (reusable by automation) ----------

    # Outline of the cutting plane (across the wall thickness, full height)
    # for the live ghost preview.
    def self.cut_plane_points(wall, pos)
      return nil unless wall&.valid?
      drawn = drawn_line_world(wall)
      return nil unless drawn
      u = drawn[1] - drawn[0]
      len = u.length
      return nil if len < 0.001
      u.normalize!
      n = Geom::Vector3d.new(-u.y, u.x, 0)
      t = wall.get_attribute('InteriorPro', 'thickness').to_f
      h = wall.get_attribute('InteriorPro', 'height').to_f
      anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      ha = anchor == 'center' ? 'center' : (anchor.split('-')[1] || 'center')
      cl_off = case ha
               when 'left' then t / 2.0
               when 'right' then -t / 2.0
               else 0.0
               end
      bx = drawn[0].x + u.x * pos + n.x * cl_off
      by = drawn[0].y + u.y * pos + n.y * cl_off
      half = t / 2.0 + 2.0
      z0 = drawn[0].z
      z1 = z0 + h
      [
        Geom::Point3d.new(bx + n.x * half, by + n.y * half, z0),
        Geom::Point3d.new(bx - n.x * half, by - n.y * half, z0),
        Geom::Point3d.new(bx - n.x * half, by - n.y * half, z1),
        Geom::Point3d.new(bx + n.x * half, by + n.y * half, z1)
      ]
    end

    def self.drawn_line_world(wall)
      sx = wall.get_attribute('InteriorPro', 'start_x')
      sy = wall.get_attribute('InteriorPro', 'start_y')
      ex = wall.get_attribute('InteriorPro', 'end_x')
      ey = wall.get_attribute('InteriorPro', 'end_y')
      return nil unless sx && sy && ex && ey
      t = wall.transformation
      [Geom::Point3d.new(sx.to_f, sy.to_f, 0).transform(t),
       Geom::Point3d.new(ex.to_f, ey.to_f, 0).transform(t)]
    end

    # Snap a split position to the nearest touching wall's projection on this
    # wall (a wall whose drawn ENDPOINT lies close to this wall's line).
    def self.snap_to_touching(wall, pos)
      drawn = drawn_line_world(wall)
      return { pos: pos, snapped: false } unless drawn
      s2 = Geom::Point3d.new(drawn[0].x, drawn[0].y, 0)
      e2 = Geom::Point3d.new(drawn[1].x, drawn[1].y, 0)
      u = e2 - s2
      len = u.length
      return { pos: pos, snapped: false } if len < 0.001
      u.normalize!
      my_t = wall.get_attribute('InteriorPro', 'thickness').to_f
      best = nil
      best_d = SNAP_TOL
      Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
        next if g == wall
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        dl = drawn_line_world(g)
        next unless dl
        g_t = g.get_attribute('InteriorPro', 'thickness').to_f
        perp_tol = (my_t + g_t) / 2.0 + 1.0
        dl.each do |p|
          p2 = Geom::Point3d.new(p.x, p.y, 0)
          t = (p2 - s2).dot(u)
          next if t < 1.0 || t > len - 1.0
          off = p2.distance(s2.offset(u, t))
          next if off > perp_tol
          d = (t - pos).abs
          if d < best_d
            best_d = d
            best = t
          end
        end
      end
      best ? { pos: best, snapped: true } : { pos: pos, snapped: false }
    end

    # Split `wall` into A (start..pos) and B (pos..end). Returns [a, b] or nil.
    def self.split_wall!(wall, pos)
      drawn = drawn_line_world(wall)
      return nil unless drawn
      wall_vec = drawn[1] - drawn[0]
      wall_len = wall_vec.length
      return nil if wall_len < 2.0
      if pos < 1.0 || pos > wall_len - 1.0
        UI.messagebox('Split point is at the wall end — nothing to split.')
        return nil
      end
      unit = wall_vec.clone
      unit.normalize!

      # Refuse to cut through a door/window opening.
      openings = InteriorPro::WallTool.read_door_openings(wall)
      blocking = openings.find { |o| (o[:t] - pos).abs < o[:width] / 2.0 + 1.0 }
      if blocking
        UI.messagebox('Split point crosses a door/window opening — move it aside first.')
        return nil
      end

      ad = wall.attribute_dictionary('InteriorPro').to_h
      original_id = ad['id'].to_s
      base_z = ad['base_z'].to_f
      attrs = {
        thickness:         ad['thickness'],
        height:            ad['height'],
        anchor:            ad['anchor'],
        wall_type:         ad['wall_type'],
        exterior_material: ad['exterior_material'],
        interior_material: ad['interior_material'],
        side_a_color:      ad['side_a_color'],
        side_b_color:      ad['side_b_color'],
        wall_category:     ad['wall_category'] || 'exterior'
      }
      contact = Geom::Point3d.new(drawn[0].x + unit.x * pos, drawn[0].y + unit.y * pos, 0)
      s_flat = Geom::Point3d.new(drawn[0].x, drawn[0].y, 0)
      e_flat = Geom::Point3d.new(drawn[1].x, drawn[1].y, 0)

      # Openings per side (t measured from the wall start along the drawn line).
      ops_a = openings.select { |o| o[:t] < pos }
      ops_b = openings.select { |o| o[:t] >= pos }.map { |o| o.merge(t: o[:t] - pos) }

      model = Sketchup.active_model
      model.start_operation('Split Wall', true)
      begin
        wt = InteriorPro::WallTool.new
        wt.wall_category = attrs[:wall_category]
        wt.side_a_color = ad['side_a_color'] if ad['side_a_color']
        wt.side_b_color = ad['side_b_color'] if ad['side_b_color']

        group_a = wt.build_wall_group(s_flat, contact, attrs, model)
        group_b = wt.build_wall_group(contact, e_flat, attrs, model)
        raise 'build_wall_group failed' unless group_a && group_b

        group_a.set_attribute('InteriorPro', 'id', original_id + 'A')
        group_b.set_attribute('InteriorPro', 'id', original_id + 'B')
        group_a.set_attribute('InteriorPro', 'mark', ad['mark']) if ad['mark']
        group_b.set_attribute('InteriorPro', 'mark', ad['mark']) if ad['mark']

        InteriorPro::WallTool.persist_door_openings!(group_a, ops_a) unless ops_a.empty?
        InteriorPro::WallTool.persist_door_openings!(group_b, ops_b) unless ops_b.empty?

        # Re-home hosted door/window bodies to the correct half.
        model.entities.to_a.each do |b|
          next unless b.is_a?(Sketchup::Group) || b.is_a?(Sketchup::ComponentInstance)
          next unless b.valid?
          tp = b.get_attribute('InteriorPro', 'type')
          next unless tp == 'door' || tp == 'window'
          next unless b.get_attribute('InteriorPro', 'host_wall_id') == original_id
          bt = b.get_attribute('InteriorPro', 'position_along_wall_in')
          bt = bt.nil? ? (Geom::Point3d.new(b.bounds.center.x, b.bounds.center.y, 0) - s_flat).dot(Geom::Vector3d.new(unit.x, unit.y, 0)) : bt.to_f
          if bt < pos
            b.set_attribute('InteriorPro', 'host_wall_id', original_id + 'A')
          else
            b.set_attribute('InteriorPro', 'host_wall_id', original_id + 'B')
            b.set_attribute('InteriorPro', 'position_along_wall_in', bt - pos) unless b.get_attribute('InteriorPro', 'position_along_wall_in').nil?
          end
        end

        wall.erase!

        # Cut the openings into the new bodies, then re-join corners.
        [group_a, group_b].each do |g|
          if InteriorPro::WallTool.read_door_openings(g).any?
            InteriorPro::WallTool.rebuild_wall_native_geometry!(g)
          end
        end
        [group_a, group_b].each do |g|
          wt.join_corners(g, model, allow_centerline_fallback: true)
        end

        # Restore the original base height on both halves.
        if base_z.abs > 0.001
          [group_a, group_b].each do |g|
            g.set_attribute('InteriorPro', 'base_z', 0.0)
            InteriorPro::WallTool.set_wall_base!(g, base_z)
          end
        end

        model.commit_operation
        begin
          InteriorPro::RoomManager.sync_rooms! if defined?(InteriorPro::RoomManager)
        rescue StandardError => e
          puts "[Rooms] sync after split: #{e.message}"
        end
        puts "[WallSplitTool] split #{original_id} at #{pos.round(2)}\" -> A(#{ops_a.length} openings) + B(#{ops_b.length} openings)"
        [group_a, group_b]
      rescue StandardError => e
        model.abort_operation rescue nil
        UI.messagebox("Split failed: #{e.message}")
        nil
      end
    end
  end

  # Join Walls (2026-07-18) — the inverse of Split: click two collinear,
  # touching walls -> ONE wall. The FIRST wall's settings win. Openings and
  # their bodies re-home to the joined wall; corners re-join; rooms sync.
  class WallJoinTool
    def activate
      @first = nil
      Sketchup.set_status_text('Join Walls: click the FIRST wall (its settings win)', SB_PROMPT)
    end

    def deactivate(view)
      view.invalidate
    end

    def onCancel(_reason, _view)
      @first = nil
      Sketchup.set_status_text('Join Walls: click the FIRST wall (its settings win)', SB_PROMPT)
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      wall = nil
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          if ent.get_attribute('InteriorPro', 'type') == 'wall'
            wall = ent
            break
          end
        end
        break if wall
      end
      return UI.messagebox('Click an Interior Pro wall') unless wall

      if @first.nil? || !@first.valid?
        @first = wall
        Sketchup.set_status_text('Now click the SECOND wall (collinear, touching)', SB_PROMPT)
        return
      end
      return if wall == @first

      self.class.join_walls!(@first, wall)
      @first = nil
      Sketchup.set_status_text('Join Walls: click the FIRST wall (its settings win)', SB_PROMPT)
      view.invalidate
    rescue StandardError => e
      puts "[WallJoinTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    def self.join_walls!(wa, wb)
      da = InteriorPro::WallSplitTool.drawn_line_world(wa)
      db = InteriorPro::WallSplitTool.drawn_line_world(wb)
      return UI.messagebox('Wall attributes missing') unless da && db
      ua = da[1] - da[0]
      la = ua.length
      ub = db[1] - db[0]
      lb = ub.length
      return UI.messagebox('Wall too short') if la < 1.0 || lb < 1.0
      ua.normalize!
      ub.normalize!
      if (ua.x * ub.y - ua.y * ub.x).abs > 0.02
        return UI.messagebox('Walls are not collinear — cannot join.')
      end
      va = Geom::Vector3d.new(-ua.y, ua.x, 0)
      off = ((Geom::Point3d.new(db[0].x, db[0].y, 0) - Geom::Point3d.new(da[0].x, da[0].y, 0)).dot(va)).abs
      return UI.messagebox('Walls are not on the same line (check anchors) — cannot join.') if off > 1.0
      bza = wa.get_attribute('InteriorPro', 'base_z').to_f
      bzb = wb.get_attribute('InteriorPro', 'base_z').to_f
      return UI.messagebox('Walls have different base heights — align them first.') if (bza - bzb).abs > 0.01

      pts = [da[0], da[1], db[0], db[1]].map { |p| Geom::Point3d.new(p.x, p.y, 0) }
      axis = Geom::Vector3d.new(ua.x, ua.y, 0)
      ts = pts.map { |p| (p - pts[0]).dot(axis) }
      if (ts.max - ts.min) > la + lb + 1.5
        return UI.messagebox('Walls do not touch — close the gap first.')
      end
      new_s = pts[ts.index(ts.min)]
      new_e = pts[ts.index(ts.max)]
      new_u = new_e - new_s
      new_u.normalize!
      new_axis = Geom::Vector3d.new(new_u.x, new_u.y, 0)

      collect = lambda do |w, d|
        un = d[1] - d[0]
        un.normalize!
        InteriorPro::WallTool.read_door_openings(w).map do |o|
          wp = Geom::Point3d.new(d[0].x + un.x * o[:t], d[0].y + un.y * o[:t], 0)
          o.merge(t: (wp - new_s).dot(new_axis))
        end
      end
      ops = collect.call(wa, da) + collect.call(wb, db)

      ad = wa.attribute_dictionary('InteriorPro').to_h
      ida = ad['id'].to_s
      idb = wb.get_attribute('InteriorPro', 'id').to_s
      attrs = {
        thickness:         ad['thickness'],
        height:            ad['height'],
        anchor:            ad['anchor'],
        wall_type:         ad['wall_type'],
        exterior_material: ad['exterior_material'],
        interior_material: ad['interior_material'],
        side_a_color:      ad['side_a_color'],
        side_b_color:      ad['side_b_color'],
        wall_category:     ad['wall_category'] || 'exterior'
      }

      model = Sketchup.active_model
      model.start_operation('Join Walls', true)
      begin
        wt = InteriorPro::WallTool.new
        wt.wall_category = attrs[:wall_category]
        wt.side_a_color = ad['side_a_color'] if ad['side_a_color']
        wt.side_b_color = ad['side_b_color'] if ad['side_b_color']
        g = wt.build_wall_group(new_s, new_e, attrs, model)
        raise 'build_wall_group failed' unless g
        new_id = ida + 'J'
        g.set_attribute('InteriorPro', 'id', new_id)
        g.set_attribute('InteriorPro', 'mark', ad['mark']) if ad['mark']
        InteriorPro::WallTool.persist_door_openings!(g, ops) unless ops.empty?

        model.entities.to_a.each do |b|
          next unless b.is_a?(Sketchup::Group) || b.is_a?(Sketchup::ComponentInstance)
          next unless b.valid?
          hid = b.get_attribute('InteriorPro', 'host_wall_id')
          next unless hid == ida || hid == idb
          tp = b.get_attribute('InteriorPro', 'type')
          next unless tp == 'door' || tp == 'window'
          b.set_attribute('InteriorPro', 'host_wall_id', new_id)
          pos_attr = b.get_attribute('InteriorPro', 'position_along_wall_in')
          next if pos_attr.nil?
          src_d = hid == ida ? da : db
          src_u = src_d[1] - src_d[0]
          src_u.normalize!
          wp = Geom::Point3d.new(src_d[0].x + src_u.x * pos_attr.to_f,
                                 src_d[0].y + src_u.y * pos_attr.to_f, 0)
          b.set_attribute('InteriorPro', 'position_along_wall_in', (wp - new_s).dot(new_axis))
        end

        wa.erase!
        wb.erase!
        InteriorPro::WallTool.rebuild_wall_native_geometry!(g) if InteriorPro::WallTool.read_door_openings(g).any?
        wt.join_corners(g, model, allow_centerline_fallback: true)
        if bza.abs > 0.001
          g.set_attribute('InteriorPro', 'base_z', 0.0)
          InteriorPro::WallTool.set_wall_base!(g, bza)
        end
        model.commit_operation
        begin
          InteriorPro::RoomManager.sync_rooms! if defined?(InteriorPro::RoomManager)
        rescue StandardError => e
          puts "[Rooms] sync after join: #{e.message}"
        end
        puts "[WallJoin] #{ida} + #{idb} -> #{new_id} (#{ops.length} openings)"
        g
      rescue StandardError => e
        model.abort_operation rescue nil
        UI.messagebox("Join failed: #{e.message}")
        nil
      end
    end
  end
end

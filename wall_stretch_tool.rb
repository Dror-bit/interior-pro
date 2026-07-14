# Interior Pro - Wall Stretch Tool
# Click a wall near the end you want to stretch, move the mouse to preview
# (gray ghost along the wall axis), then click to confirm or type a length
# (VCB, supports feet/inches like 12'6") and press Enter.

module InteriorPro
  class WallStretchTool

    def activate
      reset_state
      update_status
    end

    def deactivate(view)
      view.invalidate
    end

    def enableVCB?
      true
    end

    def onCancel(_reason, view)
      reset_state
      update_status
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      if @wall.nil?
        pick_wall_and_end(view, x, y)
        view.invalidate
      else
        commit!(view)
      end
    end

    def onMouseMove(_flags, x, y, view)
      return unless @wall
      p = view.inputpoint(x, y).position
      flat = Geom::Point3d.new(p.x, p.y, 0)
      v = Geom::Vector3d.new(flat.x - @fixed.x, flat.y - @fixed.y, 0)
      t = v.dot(@u)
      @preview_len = [t, 1.0].max
      Sketchup.vcb_label = 'Length'
      Sketchup.vcb_value = Sketchup.format_length(@preview_len)
      view.invalidate
    end

    # Typed value = ADDITION to the current wall length (negative shortens).
    def onUserText(text, view)
      return unless @wall
      delta = parse_length(text)
      if delta.nil?
        UI.messagebox("Invalid value: #{text.inspect}\nExamples: 24 or 2' or -12 (negative shortens)")
        return
      end
      new_len = @orig_len.to_f + delta
      if new_len < 1.0
        UI.messagebox('Resulting wall length must be at least 1"')
        return
      end
      @preview_len = new_len
      commit!(view)
    end

    # Forgiving length parser: Hebrew geresh/gershayim, comma decimal,
    # plain numbers = inches.
    def parse_length(text)
      s = text.to_s.strip
      s = s.tr('׳', "'").tr('״', '"').tr(',', '.')
      begin
        return s.to_l.to_f
      rescue StandardError
        nil
      end
    end

    def draw(view)
      return unless @wall && @preview_len && @orig_len
      return if (@preview_len - @orig_len).abs < 0.01
      # Ghost ONLY the changed piece: between the original end and the new end.
      t_lo = [@orig_len, @preview_len].min
      t_hi = [@orig_len, @preview_len].max
      p_lo = Geom::Point3d.new(@fixed.x + @u.x * t_lo, @fixed.y + @u.y * t_lo, 0)
      p_hi = Geom::Point3d.new(@fixed.x + @u.x * t_hi, @fixed.y + @u.y * t_hi, 0)
      # Anchor offsets are defined along the wall's canonical direction
      # (start -> end) — keep that order regardless of which end moves.
      a, b = @which == :end ? [p_lo, p_hi] : [p_hi, p_lo]
      pts_bot = footprint_corners(a, b)
      return unless pts_bot
      view.drawing_color = Sketchup::Color.new(120, 120, 120)
      view.line_stipple = '-'
      view.line_width = 2
      view.draw(GL_LINE_LOOP, pts_bot)
      h = @height.to_f
      if h > 0.1
        pts_top = pts_bot.map { |p| Geom::Point3d.new(p.x, p.y, h) }
        view.draw(GL_LINE_LOOP, pts_top)
        pts_bot.each_with_index { |p, i| view.draw(GL_LINES, [p, pts_top[i]]) }
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      if @wall && @wall.valid?
        bb.add(@wall.bounds)
        if @fixed && @preview_len
          bb.add(Geom::Point3d.new(@fixed.x + @u.x * @preview_len,
                                   @fixed.y + @u.y * @preview_len, 0))
        end
      end
      bb
    end

    private

    def reset_state
      @wall = nil
      @which = nil
      @fixed = nil
      @u = nil
      @preview_len = nil
      @height = 0
      @thickness = 0
      @h_anchor = 'center'
    end

    def update_status
      if @wall
        Sketchup.set_status_text(
          "Stretch Wall: move the mouse and click to confirm, or type an ADDED length (e.g. 24 or 2', negative shortens) and press Enter. Esc = cancel.",
          SB_PROMPT
        )
      else
        Sketchup.set_status_text(
          'Stretch Wall: click a wall NEAR THE END you want to stretch. Esc = exit.',
          SB_PROMPT
        )
      end
    end

    def pick_wall_and_end(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      wall = nil
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          next unless ent.get_attribute('InteriorPro', 'type') == 'wall'
          wall = ent
          break
        end
        break if wall
      end
      return UI.messagebox('Click an Interior Pro wall') unless wall

      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      len = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return UI.messagebox('Wall is too short') if len < 1.0

      p = view.inputpoint(x, y).position
      flat = Geom::Point3d.new(p.x, p.y, 0)
      d_start = flat.distance(Geom::Point3d.new(sx, sy, 0))
      d_end   = flat.distance(Geom::Point3d.new(ex, ey, 0))

      @wall = wall
      @which = d_end <= d_start ? :end : :start
      if @which == :end
        @fixed = Geom::Point3d.new(sx, sy, 0)
        @u = Geom::Vector3d.new((ex - sx) / len, (ey - sy) / len, 0)
      else
        @fixed = Geom::Point3d.new(ex, ey, 0)
        @u = Geom::Vector3d.new((sx - ex) / len, (sy - ey) / len, 0)
      end
      @preview_len = len
      @orig_len = len
      @height = wall.get_attribute('InteriorPro', 'height').to_f
      @thickness = wall.get_attribute('InteriorPro', 'thickness').to_f
      anchor = wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      @h_anchor = anchor.split('-')[1] || 'center'
      update_status
    end

    # Footprint rectangle of the preview — EXACTLY like
    # WallTool#perpendicular_corners_xy (left perpendicular n = (-dy, dx)).
    def footprint_corners(a, b)
      u = Geom::Vector3d.new(b.x - a.x, b.y - a.y, 0)
      return nil if u.length < 0.001
      u.normalize!
      n = Geom::Vector3d.new(-u.y, u.x, 0)
      t = @thickness.to_f
      case @h_anchor
      when 'left'  then pos = t;       neg = 0.0
      when 'right' then pos = 0.0;     neg = -t
      else              pos = t / 2.0; neg = -t / 2.0
      end
      [
        Geom::Point3d.new(a.x + n.x * pos, a.y + n.y * pos, 0),
        Geom::Point3d.new(b.x + n.x * pos, b.y + n.y * pos, 0),
        Geom::Point3d.new(b.x + n.x * neg, b.y + n.y * neg, 0),
        Geom::Point3d.new(a.x + n.x * neg, a.y + n.y * neg, 0)
      ]
    end

    def commit!(view)
      wall = @wall
      len_new = @preview_len.to_f
      which = @which
      model = Sketchup.active_model

      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      len_old = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      delta = len_new - len_old

      # Openings must stay inside the new wall.
      openings = InteriorPro::WallTool.read_door_openings(wall)
      shift = which == :start ? delta : 0.0
      bad = openings.any? do |o|
        t0 = o[:t].to_f + shift - o[:width].to_f / 2.0
        t1 = o[:t].to_f + shift + o[:width].to_f / 2.0
        t0 < 0.5 || t1 > len_new - 0.5
      end
      if bad
        puts "[WallStretch] blocked: which=#{which} len_old=#{len_old.round(2)} len_new=#{len_new.round(2)} shift=#{shift.round(2)}"
        openings.each { |o| puts "[WallStretch]   opening t=#{o[:t].to_f.round(2)} width=#{o[:width].to_f.round(2)}" }
        UI.messagebox('New length would cut into a door/window opening. Cancelled.')
        return
      end

      model.start_operation('Stretch Wall', true)
      begin
        if which == :end
          group_set_end(wall, @fixed.x + @u.x * len_new, @fixed.y + @u.y * len_new)
        else
          wall.set_attribute('InteriorPro', 'start_x', @fixed.x + @u.x * len_new)
          wall.set_attribute('InteriorPro', 'start_y', @fixed.y + @u.y * len_new)
          # Openings are measured from the start point — keep them in place.
          if delta.abs > 0.001 && openings.any?
            moved = openings.map { |o| o.merge(t: o[:t].to_f + delta) }
            InteriorPro::WallTool.persist_door_openings!(wall, moved)
            shift_hosted_positions!(wall, delta)
          end
        end

        wt = InteriorPro::WallTool.new
        data = wt.wall_data(wall)
        if data
          corners = wt.compute_perpendicular_corners_from_data(data)
          if corners
            wt.save_corners_attr(wall, corners)
            wt.rebuild_wall_geometry(wall, corners, data)
          end
          wt.join_corners(wall, model, allow_centerline_fallback: true)
        end
        model.commit_operation
      rescue StandardError => e
        model.abort_operation rescue nil
        puts "[WallStretch] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        UI.messagebox("Stretch failed: #{e.message}")
        reset_state
        update_status
        return
      end

      begin
        InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
      rescue StandardError => e
        puts "[Molding] refresh after wall stretch: #{e.message}"
      end

      reset_state
      update_status
      view.invalidate
    end

    def group_set_end(wall, x, y)
      wall.set_attribute('InteriorPro', 'end_x', x)
      wall.set_attribute('InteriorPro', 'end_y', y)
    end

    # Hosted doors/windows keep a position_along_wall_in attribute measured
    # from the wall start — shift it when the start point moves.
    def shift_hosted_positions!(wall, delta)
      wid = wall.get_attribute('InteriorPro', 'id')
      Sketchup.active_model.entities.each do |g|
        next unless g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)
        next unless g.get_attribute('InteriorPro', 'host_wall_id') == wid
        t = g.get_attribute('InteriorPro', 'position_along_wall_in')
        next unless t
        g.set_attribute('InteriorPro', 'position_along_wall_in', t.to_f + delta)
      end
    end

  end
end

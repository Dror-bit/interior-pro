# Interior Pro - Wall Curve Tool (2026-08-10)
#
# Click a wall, then move the mouse sideways: the wall's middle follows the
# cursor and bows. Click again to keep it, or type a number (VCB, accepts
# 12 / 1'6" / 12.5) and press Enter. Type 0 to straighten it again.
#
# All it ever does to the model is call WallTool.set_wall_sag!, which is the
# single entry point for curved walls. The preview here is drawn with GL
# lines only - nothing is built until the second click.

module InteriorPro
  class WallCurveTool

    GHOST = [120, 120, 120].freeze unless const_defined?(:GHOST, false)
    BAD   = [200, 40, 40].freeze   unless const_defined?(:BAD, false)

    # Type the bow instead of dragging it. Reached by right-clicking a wall.
    # Pre-filled with the wall's current bow, so it is also how you read what
    # a wall is set to, and 0 straightens it.
    def self.prompt_wall_sag!(wall)
      return false unless wall&.valid?
      return false unless wall.get_attribute('InteriorPro', 'type') == 'wall'

      unless InteriorPro::WallTool.read_door_openings(wall).empty?
        UI.messagebox("This wall has doors or windows in it.\nBending those is the next step.")
        return false
      end

      current = InteriorPro::WallTool.wall_sag(wall)
      answer = UI.inputbox(
        ['Bow (inches). + = one side, - = the other, 0 = straight'],
        [format('%g', current)],
        'Interior Pro - Curve Wall'
      )
      return false unless answer

      sag = parse_length(answer[0])
      if sag.nil?
        UI.messagebox("Invalid value: #{answer[0].inspect}\nExamples: 12   1'6\"   -8   0")
        return false
      end
      InteriorPro::WallTool.set_wall_sag!(wall, sag)
    end

    # ---- PURE helpers (no model, no view) - tested by tests/rt21.rb -------

    # Forgiving length reader: Hebrew geresh/gershayim, comma decimal, a bare
    # number means inches. Returns nil if it cannot be read.
    def self.parse_length(text)
      s = text.to_s.strip
      return nil if s.empty?
      s = s.tr('׳', "'").tr('״', '"').tr(',', '.')
      neg = s.start_with?('-')
      s = s[1..-1].to_s.strip if neg
      return nil if s.empty?
      begin
        v = s.to_l.to_f
      rescue StandardError
        return nil
      end
      neg ? -v : v
    end

    # How far sideways the cursor is from the wall's straight line, signed.
    # Positive = LEFT of start -> end, the same convention arc_math uses, so
    # this number can go straight into set_wall_sag!. nil for a zero-length
    # wall. This IS the drag: the number the user is pulling.
    def self.sag_from_point(sx, sy, ex, ey, px, py)
      chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if chord < 1e-9
      ((ex - sx) * (py - sy) - (ey - sy) * (px - sx)) / chord
    end

    # The 4-corner ghost of a still-straight wall. Deliberately the same
    # offsets the real builder uses, so the ghost never lies about where the
    # wall will land.
    def self.straight_corners(sx, sy, ex, ey, thickness, h_anchor)
      chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if chord < 1e-9
      nx = -(ey - sy) / chord
      ny =  (ex - sx) / chord
      pos, neg = InteriorPro::WallTool.anchor_side_offsets(thickness, h_anchor)
      [[sx + nx * pos, sy + ny * pos], [ex + nx * pos, ey + ny * pos],
       [ex + nx * neg, ey + ny * neg], [sx + nx * neg, sy + ny * neg]]
    end

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
        pick_wall(view, x, y)
      else
        commit!(view)
      end
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      return unless @wall
      p = view.inputpoint(x, y).position
      @sag = self.class.sag_from_point(@sx, @sy, @ex, @ey, p.x, p.y) || 0.0
      refresh_preview
      Sketchup.vcb_label = 'Bow'
      Sketchup.vcb_value = Sketchup.format_length(@sag.abs)
      view.invalidate
    end

    # Typed value = how far to bow, in the direction the mouse is currently
    # on. A typed 0 straightens the wall.
    def onUserText(text, view)
      return unless @wall
      v = parse_length(text)
      if v.nil?
        UI.messagebox("Invalid value: #{text.inspect}\nExamples: 12  or  1'6\"  or  0 to straighten")
        return
      end
      side = @sag.to_f >= 0 ? 1.0 : -1.0
      @sag = v.abs * side
      refresh_preview
      commit!(view)
    end

    def parse_length(text)
      self.class.parse_length(text)
    end

    def draw(view)
      return unless @wall && @preview
      view.drawing_color = Sketchup::Color.new(*(@preview_ok ? GHOST : BAD))
      view.line_stipple = '-'
      view.line_width = 2
      bot = @preview.map { |c| Geom::Point3d.new(c[0], c[1], @z) }
      view.draw(GL_LINE_LOOP, bot)
      h = @height.to_f
      return unless h > 0.1
      top = bot.map { |p| Geom::Point3d.new(p.x, p.y, p.z + h) }
      view.draw(GL_LINE_LOOP, top)
      # Only a few uprights - one per corner would be a picket fence.
      step = [(bot.length / 8.0).ceil, 1].max
      bot.each_with_index { |p, i| view.draw(GL_LINES, [p, top[i]]) if (i % step).zero? }
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@wall.bounds) if @wall&.valid?
      @preview&.each { |c| bb.add(Geom::Point3d.new(c[0], c[1], @z)) }
      bb
    end

    private

    def reset_state
      @wall = nil
      @sag = 0.0
      @preview = nil
      @preview_ok = true
      @chord = 1.0
      @height = 0.0
      @thickness = 0.0
      @h_anchor = 'center'
      @z = 0.0
    end

    def update_status
      Sketchup.set_status_text(
        if @wall
          'Curve Wall: move the mouse sideways to bow the wall, then click. Or type a bow (0 = straight) and press Enter. Esc = cancel.'
        else
          'Curve Wall: click the wall you want to bow. Esc = exit.'
        end,
        SB_PROMPT
      )
    end

    def pick_wall(view, x, y)
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

      unless InteriorPro::WallTool.read_door_openings(wall).empty?
        return UI.messagebox("This wall has doors or windows in it.\nBending those is the next step - pick a wall without openings.")
      end

      @sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      @sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      @ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      @ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      @chord = Math.sqrt((@ex - @sx)**2 + (@ey - @sy)**2)
      return UI.messagebox('Wall is too short') if @chord < 1.0

      @wall = wall
      @thickness = wall.get_attribute('InteriorPro', 'thickness').to_f
      @height = wall.get_attribute('InteriorPro', 'height').to_f
      anchor = wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      @h_anchor = anchor.to_s.split('-')[1] || 'center'
      @z = wall.bounds.min.z
      @sag = InteriorPro::WallTool.wall_sag(wall)
      refresh_preview
      update_status
    end

    # Rebuild the ghost outline for the current bow. A bow too tight for this
    # wall's thickness has no outline - the ghost goes red and the click is
    # refused, so the model never sees an impossible curve.
    def refresh_preview
      if @sag.abs < InteriorPro::WallTool::MIN_ARC_SAG
        @preview = straight_corners
        @preview_ok = true
        return
      end
      fp = InteriorPro::WallTool.curved_footprint_xy(@sx, @sy, @ex, @ey,
                                                     @thickness, @h_anchor, @sag)
      if fp
        @preview = fp
        @preview_ok = true
      else
        @preview_ok = false   # keep the last good outline, just colour it red
      end
    end

    def straight_corners
      self.class.straight_corners(@sx, @sy, @ex, @ey, @thickness, @h_anchor)
    end

    def commit!(view)
      unless @preview_ok
        UI.messagebox("That bow is too tight for a #{@thickness}\" wall.\nPull it back a bit.")
        return
      end
      wall = @wall
      sag = @sag.to_f
      reset_state
      update_status
      InteriorPro::WallTool.set_wall_sag!(wall, sag)
      begin
        InteriorPro::RoomManager.sync_rooms! if defined?(InteriorPro::RoomManager)
      rescue StandardError => e
        puts "[Rooms] sync after wall curve: #{e.message}"
      end
      view.invalidate
    end

  end
end

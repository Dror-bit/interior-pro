# Interior Pro - Wall Arc Tool (3 clicks) - 2026-08-11
#
#   click 1 = where the wall starts
#   click 2 = where the wall ends
#   click 3 = how far it bows
#
# Same idea as the Arc tool in the 2D editor, so the two behave alike.
#
# It is a WallTool underneath, so it inherits every wall setting, the wall
# library dialog, the snapping, and the whole create path. All it changes is
# how the three clicks are collected: it fills in start, end and arc_sag, then
# lets the ordinary create_wall do the work. That way a curved wall is born
# exactly like a straight one - same attributes, same materials, same level,
# same corner joining.

require_relative 'wall_tool.rb'

module InteriorPro
  class WallArcTool < WallTool

    GHOST = [120, 120, 120].freeze unless const_defined?(:GHOST, false)
    BAD   = [200, 40, 40].freeze   unless const_defined?(:BAD, false)

    def activate
      @ip = Sketchup::InputPoint.new
      reset_arc
      update_arc_status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def enableVCB?
      true
    end

    def onCancel(_reason, view)
      reset_arc
      update_arc_status
      view.invalidate
    end

    def onKeyDown(key, _repeat, _flags, view)
      return unless key == 27
      reset_arc
      update_arc_status
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      pt = flat_point(view, x, y)
      if @p1.nil?
        snapped = snap_start_to_wall_centerline(pt)
        @p1 = Geom::Point3d.new(snapped.x, snapped.y, 0)
      elsif @p2.nil?
        snapped = snap_start_to_wall_centerline(pt)
        p2 = Geom::Point3d.new(snapped.x, snapped.y, 0)
        return if p2.distance(@p1) < 1.0
        @p2 = p2
        @bow = 0.0
      else
        build_the_wall(view)
      end
      update_arc_status
      view.invalidate
    end

    # A double-click would otherwise fall through to WallTool's finish.
    def onLButtonDoubleClick(_flags, _x, _y, _view); end

    def onMouseMove(_flags, x, y, view)
      @cursor = flat_point(view, x, y)
      if @p1 && @p2
        @bow = InteriorPro::WallCurveTool.sag_from_point(@p1.x, @p1.y, @p2.x, @p2.y,
                                                         @cursor.x, @cursor.y) || 0.0
        refresh_ghost
        Sketchup.vcb_label = 'Bow'
        Sketchup.vcb_value = Sketchup.format_length(@bow.abs)
      elsif @p1
        Sketchup.vcb_label = 'Length'
        Sketchup.vcb_value = Sketchup.format_length(@cursor.distance(@p1))
      end
      view.invalidate
    end

    # Typed number: the wall length while placing the second point, the bow
    # while placing the third. 0 bow = a plain straight wall.
    def onUserText(text, view)
      v = InteriorPro::WallCurveTool.parse_length(text)
      return UI.messagebox("Invalid value: #{text.inspect}") if v.nil?

      if @p1 && @p2
        @bow = v.abs * (@bow.to_f >= 0 ? 1.0 : -1.0)
        refresh_ghost
        build_the_wall(view)
      elsif @p1 && @cursor
        dir = @cursor - @p1
        return if dir.length < 1e-6
        dir.normalize!
        return if v.abs < 1.0
        @p2 = @p1.offset(dir, v.abs)
        @bow = 0.0
      end
      update_arc_status
      view.invalidate
    end

    def draw(view)
      view.line_width = 2
      if @p1 && @p2.nil? && @cursor
        view.drawing_color = Sketchup::Color.new(*GHOST)
        view.line_stipple = '-'
        view.draw(GL_LINES, [@p1, @cursor])
      elsif @ghost
        view.drawing_color = Sketchup::Color.new(*(@ghost_ok ? GHOST : BAD))
        view.line_stipple = '-'
        bot = @ghost.map { |c| Geom::Point3d.new(c[0], c[1], 0) }
        view.draw(GL_LINE_LOOP, bot)
        h = @height.to_f
        if h > 0.1
          top = bot.map { |p| Geom::Point3d.new(p.x, p.y, h) }
          view.draw(GL_LINE_LOOP, top)
          step = [(bot.length / 8.0).ceil, 1].max
          bot.each_with_index { |p, i| view.draw(GL_LINES, [p, top[i]]) if (i % step).zero? }
        end
      end
      draw_dot(view, @p1)
      draw_dot(view, @p2)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@p1) if @p1
      bb.add(@p2) if @p2
      bb.add(@cursor) if @cursor
      @ghost&.each { |c| bb.add(Geom::Point3d.new(c[0], c[1], 0)) }
      bb
    end

    private

    def reset_arc
      @p1 = nil
      @p2 = nil
      @bow = 0.0
      @cursor = nil
      @ghost = nil
      @ghost_ok = true
      @arc_sag = 0.0
      @start_point = nil
      @end_point = nil
      @drawing = false
    end

    def update_arc_status
      msg = if @p1.nil?
              'Arc Wall (1/3): click where the wall starts. Esc = cancel.'
            elsif @p2.nil?
              'Arc Wall (2/3): click where the wall ends, or type a length.'
            else
              'Arc Wall (3/3): move the mouse to bow it, then click. Or type the bow. 0 = straight.'
            end
      Sketchup.set_status_text(msg, SB_PROMPT)
    end

    def flat_point(view, x, y)
      p = view.inputpoint(x, y).position
      Geom::Point3d.new(p.x, p.y, 0)
    end

    def draw_dot(view, pt)
      return unless pt
      view.drawing_color = Sketchup::Color.new(40, 90, 200)
      view.line_stipple = ''
      view.draw_points([pt], 8, 2, Sketchup::Color.new(40, 90, 200))
    rescue StandardError
      nil
    end

    def refresh_ghost
      return unless @p1 && @p2
      h_anchor = (@anchor || 'bottom-center').to_s.split('-')[1] || 'center'
      if @bow.abs < InteriorPro::WallTool::MIN_ARC_SAG
        @ghost = InteriorPro::WallCurveTool.straight_corners(@p1.x, @p1.y, @p2.x, @p2.y,
                                                             @thickness, h_anchor)
        @ghost_ok = true
        return
      end
      fp = InteriorPro::WallTool.curved_footprint_xy(@p1.x, @p1.y, @p2.x, @p2.y,
                                                     @thickness, h_anchor, @bow)
      if fp
        @ghost = fp
        @ghost_ok = true
      else
        @ghost_ok = false   # keep the last good ghost, just colour it red
      end
    end

    def build_the_wall(view)
      unless @ghost_ok
        UI.messagebox("That bow is too tight for a #{@thickness}\" wall.\nPull it back a bit.")
        return
      end
      @start_point = Geom::Point3d.new(@p1.x, @p1.y, active_base)
      @end_point   = Geom::Point3d.new(@p2.x, @p2.y, active_base)
      @arc_sag     = @bow.to_f
      begin
        create_wall
      rescue StandardError => e
        puts "[WallArcTool] create failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        UI.messagebox("Could not build the arc wall: #{e.message}")
      end
      reset_arc
      view.invalidate
    end

  end
end

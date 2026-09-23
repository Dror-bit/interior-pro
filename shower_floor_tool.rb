# encoding: utf-8
# Interior Pro - THE SHOWER FLOOR TOOL (2026-09-22, step 1)
#
# HIS FLOW (2026-09-22): click corner, corner, corner... and close the
# loop on the first corner - the same way a line is drawn. Two clicks
# would only ever give a rectangle, and his showers have five sides.
#
# THE POINT LAW (CLAUDE.md): the move and the click go through the SAME
# method (floor_point), the ring shows where it locked, and a locked
# point gives the LENGTH while the direction comes from the axis. Green =
# a corner or the end of a line, cyan = a middle, magenta = on an edge.
#
# Esc takes the last corner back (and leaves when there is none). Enter
# closes the loop. A typed number is the length of the segment being
# drawn, along the direction it is locked to.
module InteriorPro
  class ShowerFloorTool
    SNAP_PX = 10 unless const_defined?(:SNAP_PX, false)
    GREEN   = [0, 170, 60].freeze   unless const_defined?(:GREEN, false)
    CYAN    = [0, 160, 190].freeze  unless const_defined?(:CYAN, false)
    MAGENTA = [190, 0, 160].freeze  unless const_defined?(:MAGENTA, false)
    LINE    = [30, 110, 200].freeze unless const_defined?(:LINE, false)

    # cfg: the window's numbers (ShowerFloorDialog). Nil = open the window
    # first; the mouse does nothing until it is answered (2026-09-22).
    def initialize(cfg = nil)
      @cfg = cfg
    end

    def activate
      if @cfg.nil?
        InteriorPro::ShowerFloorDialog.show(nil, button: 'Draw') do |cfg|
          @cfg = cfg
          status
        end
      end
      @pts = []
      @plane_z = nil
      @hover = nil
      @floor_tops = nil
      @ip = Sketchup::InputPoint.new
      status
    end

    def deactivate(view)
      view.invalidate
    end

    def enableVCB?
      true
    end

    def status
      what = @cfg && @cfg['kind'] == 'curb' ? 'raised, with a curb' : 'flat'
      msg = if @cfg.nil?
              'Shower floor: choose the floor in the window first, then click the corners.'
            elsif @pts.empty?
              "Shower floor (#{what}): click the first corner on the floor."
            else
              "Shower floor: #{@pts.length} corner(s). Click the next one, " \
              'click the first corner (or Enter) to close, Esc takes one back.'
            end
      Sketchup.set_status_text(msg, SB_PROMPT)
    end

    # ---- the one point method ------------------------------------------

    def floor_point(view, x, y)
      @ip ||= Sketchup::InputPoint.new
      begin
        @ip.pick(view, x, y)
      rescue StandardError
        @ip = view.inputpoint(x, y)
      end
      pos = @ip.position
      return nil unless pos
      kind = point_kind(@ip)
      # ONLY THE BOTTOM CORNERS (2026-09-22, his words: "רק על הפינות
      # התחתונות של הטייל"). Measured in the trace: a click locked on a
      # corner 96" up the wall. A point that is not on the floor is thrown
      # away and the mouse ray is laid on the floor instead.
      ref = @plane_z || floor_top_below(pos.z)
      if ref && (pos.z - ref).abs > LOW_TOL
        on = Geom.intersect_line_plane(view.pickray(x, y), [Geom::Point3d.new(0, 0, ref), Geom::Vector3d.new(0, 0, 1)])
        return nil unless on
        pos = on
        kind = nil
      end
      # The FIRST corner sets the plane; every corner after it lives on
      # that same floor, whatever the mouse is hovering over.
      z = @plane_z || ref || pos.z
      px = pos.x.to_f
      py = pos.y.to_f
      last = @pts.last
      if last
        px, py = InteriorPro::ShowerFloor.ortho_point(last[0], last[1], px, py)
      end
      { x: px, y: py, z: z, kind: kind, raw: pos }
    end

    # How far from the floor a corner may be and still count (tile and
    # grout sit 0.03-0.05 over the slab; a wall top is 96 up).
    LOW_TOL = 1.0 unless const_defined?(:LOW_TOL, false)

    # The finished floor top nearest under this height - read once from
    # the floors and tile layouts in the model.
    def floor_top_below(z)
      @floor_tops ||= begin
        Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && %w[floor floor_pattern shower_floor shower_pattern].include?(g.get_attribute('InteriorPro', 'type').to_s)
        end.flat_map do |g|
          g.entities.grep(Sketchup::Face).select { |f| f.valid? && f.normal.z.abs > 0.9 }
           .map { |f| f.vertices.first.position.z.to_f }
        end.uniq
      end
      below = @floor_tops.select { |t| t <= z.to_f + LOW_TOL }
      below.empty? ? nil : below.max
    rescue StandardError
      nil
    end

    def point_kind(ip)
      return :corner if ip.respond_to?(:vertex) && ip.vertex
      dof = ip.respond_to?(:degrees_of_freedom) ? ip.degrees_of_freedom : 3
      return :corner if dof <= 0
      return :edge if dof == 1
      nil
    rescue StandardError
      nil
    end

    # ---- mouse and keys -------------------------------------------------

    def onMouseMove(_flags, x, y, view)
      @hover = floor_point(view, x, y)
      if @hover && @pts.any?
        d = Math.hypot(@hover[:x] - @pts.last[0], @hover[:y] - @pts.last[1])
        view.tooltip = Sketchup.format_length(d)
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      if @cfg.nil?
        status
        return
      end
      p = floor_point(view, x, y)
      trace_click(x, y, p)
      if p.nil?
        Sketchup.set_status_text('Shower floor: click on the floor.', SB_PROMPT)
        return
      end
      if InteriorPro::ShowerFloor.closes?(@pts, p[:x], p[:y])
        finish(view)
        return
      end
      @plane_z ||= p[:z]
      @pts << [p[:x], p[:y]]
      status
      view.invalidate
    end

    # MEASURE, DO NOT GUESS (2026-09-22): every click writes one line to
    # shower_tool_trace.txt next to the code - the raw inference point, what
    # it locked on (and whose group that is), the corner before it, and the
    # corner the tool kept. Read it instead of asking him to paste anything.
    TRACE_CLICKS = true unless const_defined?(:TRACE_CLICKS, false)
    def trace_click(x, y, p)
      return unless TRACE_CLICKS
      ip = @ip
      pos = ip && ip.position
      r4 = lambda { |v| v.to_f.round(4) }
      on = begin
        e = ip.vertex || ip.edge || ip.face
        par = e && e.parent
        grp = par.respond_to?(:instances) ? par.instances.first : nil
        typ = grp ? grp.get_attribute('InteriorPro', 'type') : nil
        "#{e ? e.class.name.split('::').last : 'nothing'} in #{typ || (grp ? grp.name : 'model')}"
      rescue StandardError => ex
        "? #{ex.message}"
      end
      last = @pts.last
      line = "#{Time.now.strftime('%H:%M:%S')} click #{x},#{y} " \
             "dof #{(ip.degrees_of_freedom rescue '?')} on #{on} " \
             "raw #{pos ? [r4.call(pos.x), r4.call(pos.y), r4.call(pos.z)].inspect : 'nil'} | " \
             "prev #{last ? [r4.call(last[0]), r4.call(last[1])].inspect : 'none'} | " \
             "kept #{p ? [r4.call(p[:x]), r4.call(p[:y])].inspect + " kind #{p[:kind].inspect}" : 'NIL'} " \
             "| corners #{@pts.length}"
      File.open(File.join(__dir__, 'shower_tool_trace.txt'), 'a:UTF-8') { |f| f.puts line }
    rescue StandardError => e
      puts "[ShowerFloor] trace failed: #{e.message}"
    end

    def onReturn(view)
      finish(view)
    end

    def onCancel(_reason, view)
      if @pts.any?
        @pts.pop
        status
        view.invalidate
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    # A typed number is the length of the segment being drawn.
    def onUserText(text, view)
      return if @pts.empty? || @hover.nil?
      len = begin
        text.to_l.to_f
      rescue StandardError
        nil
      end
      if len.nil? || len <= 0.0
        Sketchup.set_status_text('Shower floor: type a length, like  36  or  3\'', SB_PROMPT)
        return
      end
      lx, ly = @pts.last
      dx = @hover[:x] - lx
      dy = @hover[:y] - ly
      d = Math.hypot(dx, dy)
      if d < 1.0e-6
        Sketchup.set_status_text('Shower floor: point the way first, then type the length.', SB_PROMPT)
        return
      end
      @pts << [lx + dx / d * len, ly + dy / d * len]
      status
      view.invalidate
    end

    def finish(view)
      if @pts.length < 3
        Sketchup.set_status_text('Shower floor: it needs at least three corners.', SB_PROMPT)
        return
      end
      model = Sketchup.active_model
      model.start_operation('InteriorPro Shower Floor', true)
      grp = InteriorPro::ShowerFloor.build!(@pts, @plane_z || 0.0, settings: @cfg)
      if grp == :no_floor
        model.abort_operation
        UI.messagebox("There is no room floor where you drew.\n\n" \
                      "Build the floor for this room first (Build Floors), " \
                      "then close the shape again - your corners are still here.")
        Sketchup.set_status_text('Shower floor: no room floor here - build the floor for this room first.', SB_PROMPT)
        view.invalidate
        return
      end
      if grp
        model.commit_operation
        a = InteriorPro::ShowerFloor.area_sqft(@pts)
        Sketchup.set_status_text(format('Shower floor: %.1f sq ft. Click the first corner of the next one.', a), SB_PROMPT)
      else
        model.abort_operation
        UI.messagebox('No shower floor was built - see the Ruby Console for the reason.')
      end
      @pts = []
      @plane_z = nil
      @hover = nil
      view.invalidate
    end

    # ---- what he sees ---------------------------------------------------

    def draw(view)
      pts3 = @pts.map { |x, y| Geom::Point3d.new(x, y, @plane_z || 0.0) }
      if pts3.length > 1
        view.drawing_color = Sketchup::Color.new(*LINE)
        view.line_stipple = ''
        view.line_width = 3
        view.draw(GL_LINE_STRIP, pts3)
      end
      if @hover && pts3.any?
        live = Geom::Point3d.new(@hover[:x], @hover[:y], @plane_z || @hover[:z])
        view.drawing_color = Sketchup::Color.new(*LINE)
        view.line_width = 2
        view.line_stipple = '-'
        view.draw(GL_LINE_STRIP, [pts3.last, live])
        if pts3.length >= 2
          view.line_stipple = '.'
          view.draw(GL_LINE_STRIP, [live, pts3.first])
        end
      end
      # The first corner is where the loop closes - show it.
      if pts3.any?
        view.drawing_color = Sketchup::Color.new(*GREEN)
        view.line_stipple = ''
        view.line_width = 2
        view.draw2d(GL_LINE_LOOP, ring2d(view, pts3.first, 7))
      end
      draw_ring(view, @hover) if @hover
      begin
        @ip.draw(view) if @ip && @ip.valid? && @ip.display?
      rescue StandardError
        nil
      end
    end

    def ring2d(view, pt3, r)
      c = view.screen_coords(pt3)
      (0..11).map do |i|
        a = i * Math::PI / 6.0
        Geom::Point3d.new(c.x + r * Math.cos(a), c.y + r * Math.sin(a), 0)
      end
    end

    # WHERE IT LOCKED, IN THE COLOURS EVERY TOOL USES (CLAUDE.md).
    def draw_ring(view, hov)
      return if hov.nil? || hov[:kind].nil?
      col = case hov[:kind]
            when :corner then GREEN
            when :mid then CYAN
            else MAGENTA
            end
      pt = Geom::Point3d.new(hov[:x], hov[:y], @plane_z || hov[:z])
      view.drawing_color = Sketchup::Color.new(*col)
      view.line_stipple = ''
      view.line_width = 2
      view.draw2d(GL_LINE_LOOP, ring2d(view, pt, 9))
    end

    def getExtents
      bb = Geom::BoundingBox.new
      z = @plane_z || 0.0
      @pts.each { |x, y| bb.add(Geom::Point3d.new(x, y, z)) }
      bb.add(Geom::Point3d.new(@hover[:x], @hover[:y], z)) if @hover
      bb
    end
  end
end

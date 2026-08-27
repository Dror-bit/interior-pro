# Interior Pro - Dormer Tool (2026-09-02, step 3 of the dormer)
#
# The GHOST SQUARE the user asked for: hover a roof slope and the whole
# dormer is drawn where it would land - both roof planes, the front wall
# and the hole it will cut - then one click builds it.
#
# It owns NO building logic and no maths. Every point it draws comes from
# DormerManager.preview, which reads the SAME frame() the build reads, so
# the ghost cannot drift from the thing that gets built.
module InteriorPro
  class DormerTool
    def activate
      @loops = nil
      @roof = nil
      @pt = nil
      Sketchup.set_status_text('Click a roof slope to place the dormer ' \
                               '(Esc to cancel)', SB_PROMPT)
    end

    def deactivate(view)
      @loops = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      roof, pt = pick_roof(view, x, y)
      @roof = roof
      @pt = pt
      @loops = if roof && pt
                 InteriorPro::DormerManager.preview(
                   roof, pt.x, pt.y,
                   InteriorPro::DormerManager.spec_from_settings
                 )
               end
      # WHY THERE IS NO GHOST, in the status bar. The maths says no for
      # good reasons - too tall for this roof, too short for a window -
      # and a silent cursor just looks broken.
      msg = if @loops
              'Click to place the dormer (Esc to cancel)'
            elsif roof
              why = InteriorPro::DormerManager.last_reason
              why ? "Dormer: #{why}" : 'A dormer does not fit here'
            else
              'Hover a roof slope to place the dormer (Esc to cancel)'
            end
      Sketchup.set_status_text(msg, SB_PROMPT)
      view.invalidate
    end

    # The two roof planes and the front wall in orange, the hole in blue,
    # so he can see what the roof loses before he commits to it.
    def draw(view)
      return if @loops.nil? || @loops.empty?
      view.line_stipple = ''
      @loops.each_with_index do |loop, i|
        next if loop.nil? || loop.length < 2
        if i == @loops.length - 1 && @loops.length > 3
          view.drawing_color = Sketchup::Color.new(40, 140, 230)
          view.line_width = 2
          view.line_stipple = '-'
        else
          view.drawing_color = Sketchup::Color.new(230, 112, 0)
          view.line_width = 3
        end
        view.draw(GL_LINE_LOOP, loop)
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      @loops&.each { |l| l&.each { |p| bb.add(p) } }
      bb.add(@roof.bounds) if @roof.respond_to?(:valid?) && @roof.valid?
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      roof, pt = pick_roof(view, x, y)
      return UI.messagebox('Click an Interior Pro roof') if roof.nil? || pt.nil?
      spec = InteriorPro::DormerManager.spec_from_settings
      if InteriorPro::DormerManager.preview(roof, pt.x, pt.y, spec).nil?
        return UI.messagebox('A dormer this size does not fit here - ' \
                             'try further down the slope, or change the sizes.')
      end
      model = Sketchup.active_model
      model.start_operation('Dormer', true)
      g = InteriorPro::DormerManager.place_on_roof!(roof, pt.x, pt.y, spec)
      model.commit_operation
      if g.nil?
        UI.messagebox('The dormer could not be built here - see the Ruby Console.')
      else
        puts "[Dormer] placed at (#{pt.x.round(1)}, #{pt.y.round(1)})"
      end
      view.invalidate
    rescue StandardError => e
      puts "[DormerTool] #{e.class}: #{e.message}"
      puts e.backtrace.first(5) if e.backtrace
    end

    def onKeyDown(key, _repeat, _flags, _view)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    def getInstructions
      'Hover a roof slope to see the dormer, click to place it.'
    end

    private

    # The roof group under the cursor AND the point on it - the same
    # pick, so the ghost and the build cannot disagree about where.
    #
    # THE POINT COMES FROM AN InputPoint (2026-09-02). PickHelper finds
    # the GROUP reliably but has no supported way to hand back the 3D
    # point it hit, and the first version leaned on one that does not
    # exist everywhere - so the tool found the roof, got nil for the
    # point, and quietly did nothing. View#inputpoint always lands
    # somewhere under the cursor; pickray on the roof's own plane is the
    # fallback when it does not.
    def pick_roof(view, x, y)
      roof = pick_roof_group(view, x, y)
      return [nil, nil] if roof.nil?
      [roof, pick_point(view, x, y, roof)]
    end

    def pick_roof_group(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'roof'
        end
      end
      nil
    end

    def pick_point(view, x, y, roof)
      ip = view.inputpoint(x, y)
      return ip.position if ip && ip.valid? && ip.position
      ray = view.pickray(x, y)
      face = roof.entities.grep(Sketchup::Face)
                 .select { |f| f.normal.z > 0.2 }.max_by(&:area)
      return nil if ray.nil? || face.nil?
      Geom.intersect_line_plane(ray, face.plane)
    rescue StandardError
      nil
    end
  end
end

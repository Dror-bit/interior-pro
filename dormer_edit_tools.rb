# Interior Pro - Dormer Edit / Move / Delete (2026-09-02)
#
# Three tools, one pick. Each one hovers a dormer, shows it in a colour,
# and acts on the click - the same shape RoofEditTool has, so nothing
# here is a new idea to learn.
#
# NONE OF THEM BUILDS ANYTHING. Every one goes through
# DormerManager.remove_dormer! / replace_dormer!, which read the dormer's
# own saved numbers back into the spec that made it. That is what keeps
# an edited dormer identical to a freshly placed one, and what lets the
# hole in the roof be closed exactly where it was cut.
module InteriorPro
  # What all three share: find the dormer under the cursor and draw it.
  module DormerPick
    def pick_dormer(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'dormer'
        end
      end
      nil
    end

    def outline(view, g, color)
      return unless g&.valid?
      bb = g.bounds
      lo = bb.min
      hi = bb.max
      corners = [[lo.x, lo.y], [hi.x, lo.y], [hi.x, hi.y], [lo.x, hi.y]]
      view.drawing_color = color
      view.line_width = 3
      view.line_stipple = ''
      [lo.z, hi.z].each do |z|
        view.draw(GL_LINE_LOOP, corners.map { |cx, cy| Geom::Point3d.new(cx, cy, z) })
      end
      corners.each do |cx, cy|
        view.draw(GL_LINES, [Geom::Point3d.new(cx, cy, lo.z),
                             Geom::Point3d.new(cx, cy, hi.z)])
      end
    end

    def hover_extents(g)
      bb = Geom::BoundingBox.new
      bb.add(g.bounds) if g&.valid?
      bb
    end
  end

  # ---------------- DELETE -------------------------------------------
  # Erases the dormer AND closes the hole it cut, in one operation - so
  # one Ctrl+Z puts both back.
  class DormerDeleteTool
    include DormerPick

    def activate
      @hover = nil
      Sketchup.set_status_text('Click a dormer to delete it (Esc to cancel)', SB_PROMPT)
    end

    def deactivate(view)
      @hover = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      g = pick_dormer(view, x, y)
      return if g == @hover
      @hover = g
      view.invalidate
    end

    def draw(view)
      outline(view, @hover, Sketchup::Color.new(220, 60, 60))
    end

    def getExtents
      hover_extents(@hover)
    end

    def onLButtonDown(_flags, x, y, view)
      g = pick_dormer(view, x, y)
      return UI.messagebox('Click a dormer') if g.nil?
      model = Sketchup.active_model
      model.start_operation('Delete Dormer', true)
      okd = InteriorPro::DormerManager.remove_dormer!(g)
      model.commit_operation
      UI.messagebox('That dormer could not be deleted - see the Ruby Console.') unless okd
      @hover = nil
      view.invalidate
    end

    def onKeyDown(key, _r, _f, _v)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    def getInstructions
      'Click a dormer to delete it. The hole in the roof closes with it.'
    end
  end

  # ---------------- EDIT ---------------------------------------------
  # Opens the panel ON that dormer: its own numbers fill the controls and
  # Place rebuilds THAT one where it stands.
  class DormerEditTool
    include DormerPick

    def activate
      @hover = nil
      Sketchup.set_status_text('Click a dormer to edit it (Esc to cancel)', SB_PROMPT)
    end

    def deactivate(view)
      @hover = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      g = pick_dormer(view, x, y)
      return if g == @hover
      @hover = g
      view.invalidate
    end

    def draw(view)
      outline(view, @hover, Sketchup::Color.new(40, 140, 230))
    end

    def getExtents
      hover_extents(@hover)
    end

    def onLButtonDown(_flags, x, y, view)
      g = pick_dormer(view, x, y)
      return UI.messagebox('Click a dormer') if g.nil?
      InteriorPro::DormerDialog.show(g)
      view.invalidate
    end

    def onKeyDown(key, _r, _f, _v)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    def getInstructions
      'Click a dormer to open its own panel.'
    end
  end

  # ---------------- MOVE ---------------------------------------------
  # Click the dormer, then walk it over the roof and click again. The
  # ghost is the SAME ghost the placing tool draws, from the same spec,
  # so what lands is what was picked up - only somewhere else.
  class DormerMoveTool
    include DormerPick

    def activate
      @picked = nil
      @spec = nil
      @loops = nil
      say('Click the dormer you want to move (Esc to cancel)')
    end

    def deactivate(view)
      @picked = nil
      @loops = nil
      view.invalidate
    end

    def say(msg)
      Sketchup.set_status_text(msg, SB_PROMPT)
    end

    def onMouseMove(_flags, x, y, view)
      if @picked.nil?
        g = pick_dormer(view, x, y)
        return if g == @hover
        @hover = g
        view.invalidate
        return
      end
      roof, pt = pick_roof(view, x, y)
      @roof = roof
      @pt = pt
      @loops = if roof && pt
                 InteriorPro::DormerManager.preview(roof, pt.x, pt.y,
                                                    @spec.merge(follow_click: true))
               end
      say(if @loops
            'Click to drop it here (Esc to cancel)'
          elsif roof
            why = InteriorPro::DormerManager.last_reason
            why ? "Dormer: #{why}" : 'It does not fit here'
          else
            'Move the mouse over a roof slope'
          end)
      view.invalidate
    end

    def draw(view)
      if @picked.nil?
        outline(view, @hover, Sketchup::Color.new(230, 160, 0))
        return
      end
      return if @loops.nil?
      view.line_stipple = ''
      view.drawing_color = Sketchup::Color.new(230, 112, 0)
      view.line_width = 3
      @loops.each { |l| view.draw(GL_LINE_LOOP, l) if l && l.length > 2 }
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@hover.bounds) if @hover&.valid?
      @loops&.each { |l| l&.each { |p| bb.add(p) } }
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      if @picked.nil?
        g = pick_dormer(view, x, y)
        return UI.messagebox('Click a dormer') if g.nil?
        spec = InteriorPro::DormerManager.dormer_spec(g)
        return UI.messagebox('That dormer has no saved sizes - rebuild it first.') if spec.nil?
        @picked = g
        @spec = spec
        say('Now click where it should go')
        view.invalidate
        return
      end
      roof, pt = pick_roof(view, x, y)
      return UI.messagebox('Click a roof slope') if roof.nil? || pt.nil?
      s = @spec.merge(follow_click: true)
      if InteriorPro::DormerManager.preview(roof, pt.x, pt.y, s).nil?
        why = InteriorPro::DormerManager.last_reason
        return UI.messagebox(why ? "This dormer #{why}" : 'It does not fit there.')
      end
      model = Sketchup.active_model
      model.start_operation('Move Dormer', true)
      InteriorPro::DormerManager.remove_dormer!(@picked)
      g = InteriorPro::DormerManager.place_on_roof!(roof, pt.x, pt.y, s)
      model.commit_operation
      UI.messagebox('It could not be rebuilt there - see the Ruby Console.') if g.nil?
      @picked = nil
      @loops = nil
      say('Click the dormer you want to move (Esc to cancel)')
      view.invalidate
    end

    def onKeyDown(key, _r, _f, view)
      return unless key == 27
      if @picked
        @picked = nil
        @loops = nil
        say('Click the dormer you want to move (Esc to cancel)')
        view.invalidate if view
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    def getInstructions
      'Click a dormer, then click where it should go.'
    end

    private

    def pick_roof(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      roof = nil
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          roof = ent if ent.get_attribute('InteriorPro', 'type') == 'roof'
        end
        break if roof
      end
      return [nil, nil] if roof.nil?
      ip = view.inputpoint(x, y)
      pt = ip && ip.valid? ? ip.position : nil
      [roof, pt]
    end
  end
end

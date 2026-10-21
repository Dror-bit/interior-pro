# encoding: utf-8
# Interior Pro - EDIT A FIXTURE (2026-09-25, his ask: "עריכה").
#
# Hover a shower head / toilet, it is outlined in blue; click, and the
# SAME window it was placed with opens with its own numbers - kind,
# product, height - plus how far its middle is from the nearer corner.
# Apply rebuilds it in place in ONE undo step (FixtureLibrary.update!).
# No delete tool: select it and press Delete (his call, 2026-09-25).
module InteriorPro
  class FixtureEditTool
    BLUE = [40, 110, 200].freeze unless const_defined?(:BLUE, false)

    def activate
      @hit = nil
      selection=Sketchup.active_model.selection.to_a
      if selection.length==1 && vanity?(selection.first)
        return if InteriorPro::Vanity.edit_entity(selection.first)
      end
      Sketchup.set_status_text('Edit Plumbing: click a fixture or Vanity to edit it. Esc = done.', SB_PROMPT)
    end

    def deactivate(view)
      view.invalidate
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onMouseMove(_flags, x, y, view)
      @hit = pick(view, x, y)
      view.tooltip = @hit ? 'Click to edit this' : ''
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      hit = pick(view, x, y)
      if hit.nil?
        Sketchup.set_status_text('Edit Plumbing: click a fixture or Vanity.', SB_PROMPT)
        return
      end
      if vanity?(hit)
        InteriorPro::Vanity.edit_entity(hit)
        @hit=nil;view.invalidate
        return
      end
      prefill = InteriorPro::FixtureLibrary.settings_of(hit)
      puts "[Fixture] edit opens with #{prefill.inspect}"
      InteriorPro::FixtureDialog.show(prefill, button: 'Apply') do |cfg|
        made = InteriorPro::FixtureLibrary.update!(hit, cfg)
        UI.messagebox('Nothing was changed - see the Ruby Console for the reason.') if made.nil?
        Sketchup.active_model.active_view.invalidate
      end
      @hit = nil
      view.invalidate
    end

    # The fixture under the mouse: the first instance on the pick path
    # that carries type 'fixture'.
    def pick(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each { |e| return e if vanity?(e) || InteriorPro::FixtureLibrary.fixture?(e) }
      end
      nil
    rescue StandardError => e
      puts "[Fixture] edit pick failed: #{e.message}"
      nil
    end
    def vanity?(entity)
      defined?(InteriorPro::Vanity) && InteriorPro::Vanity.respond_to?(:editable?) && InteriorPro::Vanity.editable?(entity)
    end

    def draw(view)
      return unless @hit&.valid?
      b = @hit.bounds
      c = (0..7).map { |i| b.corner(i) }
      view.drawing_color = Sketchup::Color.new(*BLUE)
      view.line_width = 3
      view.line_stipple = ''
      [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]].each do |a, z|
        view.draw(GL_LINES, [c[a], c[z]])
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@hit.bounds) if @hit&.valid?
      bb
    end
  end
end

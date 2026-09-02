# Interior Pro - Skylight Tool (2026-09-14)
#
# Hover a roof slope, see the rectangle it would cut, click to place it.
# It owns NO maths: the ghost is the same plan_rect the build cuts, so the
# two cannot drift apart. Shaped exactly like DormerTool.
module InteriorPro
  class SkylightTool
    def initialize(spec = {})
      @spec = spec || {}
    end

    def activate
      @loop = nil
      @roof = nil
      @pt = nil
      Sketchup.set_status_text('Click a roof slope to place the skylight ' \
                               '(Esc to cancel)', SB_PROMPT)
    end

    def deactivate(view)
      @loop = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      @roof, @pt = pick_roof(view, x, y)
      @loop = ghost(@roof, @pt)
      msg = if @loop
              'Click to place the skylight (Esc to cancel)'
            elsif @roof
              why = InteriorPro::SkylightManager.last_reason
              why ? "Skylight: #{why}" : 'A skylight does not fit here'
            else
              'Hover a roof slope to place the skylight (Esc to cancel)'
            end
      Sketchup.set_status_text(msg, SB_PROMPT)
      view.invalidate
    end

    def draw(view)
      return if @loop.nil? || @loop.length < 2
      view.line_stipple = ''
      view.drawing_color = Sketchup::Color.new(40, 140, 230)
      view.line_width = 3
      view.draw(GL_LINE_LOOP, @loop)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      @loop&.each { |p| bb.add(p) }
      bb.add(@roof.bounds) if @roof.respond_to?(:valid?) && @roof.valid?
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      roof, pt = pick_roof(view, x, y)
      return UI.messagebox('Click an Interior Pro roof') if roof.nil? || pt.nil?
      if ghost(roof, pt).nil?
        why = InteriorPro::SkylightManager.last_reason
        return UI.messagebox(why ? "The skylight #{why}" :
                             'A skylight does not fit here - try further in.')
      end
      model = Sketchup.active_model
      model.start_operation('Skylight', true)
      g = InteriorPro::SkylightManager.place_on_roof!(roof, pt.x, pt.y, @spec)
      model.commit_operation
      UI.messagebox('The skylight could not be built here - see the Ruby ' \
                    'Console.') if g.nil?
      view.invalidate
    rescue StandardError => e
      puts "[SkylightTool] #{e.class}: #{e.message}"
      puts e.backtrace.first(5) if e.backtrace
    end

    def onKeyDown(key, _repeat, _flags, _view)
      Sketchup.active_model.select_tool(nil) if key == 27
    end

    def getInstructions
      'Hover a roof slope to see the skylight, click to place it.'
    end

    private

    # The blue rectangle, on the roof's own plane.
    def ghost(roof, pt)
      return nil if roof.nil? || pt.nil?
      sm = InteriorPro::SkylightManager
      fr = InteriorPro::DormerManager.roof_frame(roof, pt.x, pt.y)
      return nil if fr.nil?
      w = @spec[:width].to_f  > 0.0 ? @spec[:width].to_f  : sm.default_width
      h = @spec[:height].to_f > 0.0 ? @spec[:height].to_f : sm.default_height
      plan = sm.plan_rect(fr[:s_click], w, h)
      return nil if plan.nil?
      at = InteriorPro::DormerManager.at_lambda(fr)
      return nil unless sm.corners_on_face?(fr[:face], at, plan)
      z_at = InteriorPro::DormerManager.plane_z_lambda(fr[:face])
      return nil if z_at.nil?
      plan.map do |s, wv|
        q = at.call(s, wv, 0.0)
        Geom::Point3d.new(q.x, q.y, z_at.call(q.x, q.y))
      end
    rescue StandardError
      nil
    end

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

# ---------------------------------------------------------------------
# Edit / Move / Delete (2026-09-14). Same click-to-pick shape as the
# dormer's three tools, one type further in. Each tool owns no maths:
# Edit opens the panel ON the skylight, Move and Delete call the manager.
module InteriorPro
  module SkylightPick
    def pick_skylight(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'skylight'
        end
      end
      nil
    end

    def onKeyDown(key, _repeat, _flags, _view)
      Sketchup.active_model.select_tool(nil) if key == 27
    end
  end

  class SkylightEditTool
    include SkylightPick

    def activate
      Sketchup.set_status_text('Click a skylight to edit it (Esc to cancel)', SB_PROMPT)
    end

    def onLButtonDown(_flags, x, y, view)
      g = pick_skylight(view, x, y)
      return UI.messagebox('Click a skylight') if g.nil?
      InteriorPro::SkylightDialog.show(g)
      Sketchup.active_model.select_tool(nil)
      view.invalidate
    rescue StandardError => e
      puts "[SkylightEditTool] #{e.class}: #{e.message}"
    end

    def getInstructions
      'Click a skylight to open its panel.'
    end
  end

  class SkylightDeleteTool
    include SkylightPick

    def activate
      Sketchup.set_status_text('Click a skylight to delete it (Esc to cancel)', SB_PROMPT)
    end

    def onLButtonDown(_flags, x, y, view)
      g = pick_skylight(view, x, y)
      return UI.messagebox('Click a skylight') if g.nil?
      model = Sketchup.active_model
      model.start_operation('Delete Skylight', true)
      ok = InteriorPro::SkylightManager.remove!(g)
      model.commit_operation
      UI.messagebox('The skylight could not be removed - see the Ruby Console.') unless ok
      view.invalidate
    rescue StandardError => e
      puts "[SkylightDeleteTool] #{e.class}: #{e.message}"
    end

    def getInstructions
      'Click a skylight to delete it and close its hole.'
    end
  end

  # Click the skylight, then click where it goes. Between the two clicks
  # the SkylightTool's own ghost is drawn, with the picked skylight's
  # numbers, so what he sees is what will be built.
  class SkylightMoveTool < SkylightTool
    include SkylightPick

    def initialize
      super({})
      @target = nil
    end

    def activate
      super
      @target = nil
      Sketchup.set_status_text('Click the skylight to move (Esc to cancel)', SB_PROMPT)
    end

    def onMouseMove(flags, x, y, view)
      return super if @target
      view.invalidate
    end

    def draw(view)
      super if @target
    end

    def onLButtonDown(_flags, x, y, view)
      if @target.nil?
        g = pick_skylight(view, x, y)
        return UI.messagebox('Click a skylight') if g.nil?
        @target = g
        @spec = InteriorPro::SkylightManager.spec_of(g)
        Sketchup.set_status_text('Now click where it goes (Esc to cancel)', SB_PROMPT)
        return
      end
      roof, pt = pick_roof(view, x, y)
      return UI.messagebox('Click a roof slope') if roof.nil? || pt.nil?
      if ghost(roof, pt).nil?
        why = InteriorPro::SkylightManager.last_reason
        return UI.messagebox(why ? "The skylight #{why}" : 'It does not fit there.')
      end
      model = Sketchup.active_model
      model.start_operation('Move Skylight', true)
      g = InteriorPro::SkylightManager.move!(@target, pt.x, pt.y)
      model.commit_operation
      UI.messagebox('The skylight could not be moved - see the Ruby Console.') if g.nil?
      @target = nil
      Sketchup.active_model.select_tool(nil)
      view.invalidate
    rescue StandardError => e
      puts "[SkylightMoveTool] #{e.class}: #{e.message}"
      puts e.backtrace.first(5) if e.backtrace
    end

    def getInstructions
      'Click a skylight, then click where it goes.'
    end
  end
end

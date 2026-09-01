# Interior Pro - Roof Ends Tool (2026-08-05, menu added 2026-09-11)
# Click a wall and a small menu opens for THAT edge: Hip, Gable or Dutch
# gable. The choice is saved by wall id on the model (survives rebuilds)
# and the roof rebuilds itself right away. Same wall-picking pattern as
# WallDeleteTool.
module InteriorPro
  class RoofGableTool
    # ORANGE hip, BLUE gable, GREEN Dutch gable - the highlight has to
    # show which of the three a wall is before it is clicked.
    COLORS = { hip: Sketchup::Color.new(230, 120, 20),
               gable: Sketchup::Color.new(40, 140, 230),
               dutch: Sketchup::Color.new(60, 180, 90) }.freeze
    NAMES = { hip: 'Hip', gable: 'Gable', dutch: 'Dutch gable' }.freeze

    def activate
      @preview_wall = nil
      Sketchup.set_status_text('Click a wall to choose its roof end: hip, gable or Dutch gable', SB_PROMPT)
    end

    def deactivate(view)
      @preview_wall = nil
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      w = pick_wall(view, x, y)
      if w != @preview_wall
        @preview_wall = w
        view.invalidate
      end
    end

    def draw(view)
      return unless @preview_wall&.valid?
      flat = @preview_wall.get_attribute('InteriorPro', 'corners_xy')
      return unless flat && flat.length == 8
      t = @preview_wall.transformation
      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0).transform(t) }
      wid = @preview_wall.get_attribute('InteriorPro', 'id')
      view.drawing_color = COLORS[InteriorPro::RoofManager.roof_end_of(wid)]
      view.line_width = 3
      view.line_stipple = ''
      view.draw(GL_LINE_LOOP, pts)
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@preview_wall.bounds) if @preview_wall&.valid?
      bb
    end

    def onLButtonDown(_flags, x, y, view)
      wall = pick_wall(view, x, y)
      return UI.messagebox('Click an Interior Pro wall') unless wall
      # the click position decides WHICH roof section of a long wall gables
      # - read BEFORE the menu opens, while the pick is still fresh.
      ip = view.inputpoint(x, y)
      p3 = ip.position
      wid = wall.get_attribute('InteriorPro', 'id')
      cur = InteriorPro::RoofManager.roof_end_of(wid)
      # A MENU FOR THAT EDGE (2026-09-11, the user: "צריך להיפתח תפריט
      # לאותה הצלע ואז לבחור איזה סוג של גימור של גג"). It opens showing
      # what this end IS, so the menu doubles as the answer to "what did
      # I set here?" - and Cancel leaves it exactly as it was.
      res = UI.inputbox(['Roof end'], [NAMES[cur]], [NAMES.values.join('|')],
                        'Interior Pro - Roof End')
      return unless res
      kind = NAMES.key(res[0]) || :hip
      InteriorPro::RoofManager.set_roof_end!(wall, kind, [p3.x.to_f, p3.y.to_f])
      view.invalidate
    rescue StandardError => e
      puts "[RoofGableTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    def onKeyDown(key, _repeat, _flags, view)
      Sketchup.active_model.select_tool(nil) if key == 27
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
  end
end

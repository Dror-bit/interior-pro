# Interior Pro - Wall Delete Tool (2026-07-23)
# Click a wall -> confirm -> delete the wall together with its hosted doors,
# windows and molding. Neighbour walls that shared an endpoint have their
# corner reset to a square end and are re-joined against the remaining walls
# (so the stale miter that pointed at the deleted wall is removed). Rooms
# re-sync (floors follow). Molding is refreshed only if present.

module InteriorPro
  class WallDeleteTool
    def activate
      @preview_wall = nil
      Sketchup.set_status_text('Click a wall to delete it (with its doors, windows and molding)', SB_PROMPT)
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
      pts = footprint_points(@preview_wall)
      return unless pts
      view.drawing_color = Sketchup::Color.new(230, 40, 40)
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
      return unless UI.messagebox('Delete this wall with its doors, windows and molding?',
                                  MB_YESNO) == IDYES
      self.class.delete_wall!(wall)
      @preview_wall = nil
      view.invalidate
    rescue StandardError => e
      puts "[WallDeleteTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    # Walls whose DRAWN end sits on one of this wall's drawn ends.
    #
    # Pulled out of delete_wall! so it can be tested on its own (tests/rt75.rb)
    # - deleting a wall for real needs half the plugin awake, and the thing
    # worth pinning is only this: WHICH walls get their corner reset.
    #
    # Level guard (2026-08-19): the caller resets every wall on this list to a
    # SQUARE end and rebuilds it. The user builds floor 2 by copying floor 1,
    # so an upstairs wall's ends usually sit exactly over a downstairs wall's
    # ends - and without this line, deleting upstairs wiped a perfectly good
    # mitered corner downstairs, leaving the white square cap he reported on
    # 2026-08-17. By the 'level' attribute, not by z, so a dropped garage
    # keeps its neighbours. Same rule as WallTool.find_neighbor_at.
    def self.neighbor_walls(wall, model = Sketchup.active_model)
      out = []
      return out unless wall&.valid?
      my = InteriorPro::WallSplitTool.drawn_line_world(wall)
      return out unless my
      my_t = wall.get_attribute('InteriorPro', 'thickness').to_f
      my_level = (wall.get_attribute('InteriorPro', 'level') || 1).to_i
      my_ends = [Geom::Point3d.new(my[0].x, my[0].y, 0),
                 Geom::Point3d.new(my[1].x, my[1].y, 0)]
      model.entities.grep(Sketchup::Group).each do |g|
        next if g == wall || !g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'wall'
        next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == my_level
        dl = InteriorPro::WallSplitTool.drawn_line_world(g)
        next unless dl
        g_ends = [Geom::Point3d.new(dl[0].x, dl[0].y, 0),
                  Geom::Point3d.new(dl[1].x, dl[1].y, 0)]
        tol = (my_t + g.get_attribute('InteriorPro', 'thickness').to_f) / 2.0 + 1.0
        out << g if my_ends.any? { |e| g_ends.any? { |p| e.distance(p) < tol } }
      end
      out
    end

    # ---- core (class method so other code can call it) ----
    def self.delete_wall!(wall)
      model = Sketchup.active_model
      return false unless wall&.valid? && wall.get_attribute('InteriorPro', 'type') == 'wall'
      wid = wall.get_attribute('InteriorPro', 'id')

      # Neighbours (endpoint-sharing walls) captured BEFORE deletion.
      neighbors = neighbor_walls(wall, model)

      model.start_operation('Delete Wall', true)
      begin
        # Erase hosted door/window bodies and this wall's molding runs.
        model.entities.to_a.each do |e|
          next unless e.valid?
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          t = e.get_attribute('InteriorPro', 'type')
          if e.get_attribute('InteriorPro', 'host_wall_id') == wid &&
             %w[door window baseboard crown].include?(t)
            e.erase!
          end
        end
        wall.erase!

        # Reset each neighbour to a square end, then re-join against the
        # walls that remain (drops the stale miter aimed at the deleted wall).
        wt = InteriorPro::WallTool.new
        neighbors.each do |g|
          next unless g.valid?
          data = wt.wall_data(g)
          next unless data
          corners = wt.compute_perpendicular_corners_from_data(data)
          next unless corners
          wt.save_corners_attr(g, corners)
          wt.rebuild_wall_geometry(g, corners, data)
        end
        neighbors.each do |g|
          next unless g.valid?
          wt.join_corners(g, model, allow_centerline_fallback: true)
        end
        model.commit_operation
      rescue StandardError => e
        model.abort_operation rescue nil
        UI.messagebox("Delete failed: #{e.message}")
        puts "[WallDelete] #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        return false
      end

      # Rooms (and floors, via the room sync hook). Molding only if present.
      begin
        InteriorPro::RoomManager.sync_rooms! if defined?(InteriorPro::RoomManager)
      rescue StandardError => e
        puts "[WallDelete] room sync: #{e.message}"
      end
      begin
        if defined?(InteriorPro::MoldingManager) &&
           model.entities.grep(Sketchup::Group).any? { |g|
             %w[baseboard crown].include?(g.get_attribute('InteriorPro', 'type'))
           }
          InteriorPro::MoldingManager.refresh!
        end
      rescue StandardError => e
        puts "[WallDelete] molding refresh: #{e.message}"
      end
      puts "[WallDelete] deleted wall #{wid}; #{neighbors.length} neighbour(s) re-joined"
      true
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

    def footprint_points(wall)
      flat = wall.get_attribute('InteriorPro', 'corners_xy')
      return nil unless flat && flat.length == 8
      t = wall.transformation
      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0).transform(t) }
      pts + [pts.first]
    end
  end
end

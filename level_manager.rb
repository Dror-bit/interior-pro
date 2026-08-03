# level_manager.rb — building levels (2026-08-03, user decisions).
# Level 1 starts at 0. Level 2 base = wall height + floor structure, where
# the structure is 2x10 joists (9.25") + subfloor (0.75") -> 106" default.
# All numbers live on the MODEL and are changeable from the console.
#
# "Build Level 2 Structure" — the user's model: NO separate rim element.
# Each EXTERIOR wall simply grows up to the level-2 floor, so its exterior
# material (stucco, brick...) continues by itself. Before growing, the wall
# remembers where its ceiling is ('ceiling_h' = the original height) —
# crown molding and flat ceilings stop THERE, not at the raised top.
# One subfloor deck spans the whole footprint (to the interior faces of
# the exterior walls, over interior walls too), its top AT level-2 base.
module InteriorPro
  module LevelManager
    DEFAULT_WALL_HEIGHT = 96.0 unless const_defined?(:DEFAULT_WALL_HEIGHT, false)
    DEFAULT_JOIST_DEPTH = 9.25 unless const_defined?(:DEFAULT_JOIST_DEPTH, false) # 2x10 actual
    DEFAULT_SUBFLOOR    = 0.75 unless const_defined?(:DEFAULT_SUBFLOOR, false)    # plywood

    # ---------- The levels registry (model attributes) ----------

    def self.wall_height
      v = Sketchup.active_model.get_attribute('InteriorPro', 'level_wall_height').to_f
      v > 12.0 ? v : DEFAULT_WALL_HEIGHT
    end

    def self.joist_depth
      v = Sketchup.active_model.get_attribute('InteriorPro', 'level_joist_depth').to_f
      v > 0.5 ? v : DEFAULT_JOIST_DEPTH
    end

    def self.subfloor_depth
      v = Sketchup.active_model.get_attribute('InteriorPro', 'level_subfloor').to_f
      v > 0.05 ? v : DEFAULT_SUBFLOOR
    end

    # Console helper:
    #   InteriorPro::LevelManager.set_structure!(joist: 11.25)   # 2x12
    def self.set_structure!(wall_height: nil, joist: nil, subfloor: nil)
      model = Sketchup.active_model
      model.set_attribute('InteriorPro', 'level_wall_height', wall_height.to_f) if wall_height
      model.set_attribute('InteriorPro', 'level_joist_depth', joist.to_f) if joist
      model.set_attribute('InteriorPro', 'level_subfloor', subfloor.to_f) if subfloor
      puts "[Levels] wall=#{self.wall_height}\" joist=#{joist_depth}\" subfloor=#{subfloor_depth}\" -> level 2 base=#{level_base(2)}\""
      true
    end

    # Base z of level n. Level 1 = 0; each story adds walls + structure.
    def self.level_base(n)
      (n.to_i - 1) * (wall_height + joist_depth + subfloor_depth)
    end

    # ---------- Active level (2026-08-03, part 1) ----------
    # The level new walls are drawn on. Stored on the model; default 1.

    def self.active_level
      v = Sketchup.active_model.get_attribute('InteriorPro', 'active_level').to_i
      v >= 1 ? v : 1
    end

    def self.set_active_level!(n)
      n = n.to_i
      n = 1 if n < 1
      Sketchup.active_model.set_attribute('InteriorPro', 'active_level', n)
      puts "[Levels] active level = #{n} (base #{level_base(n)}\")"
      n
    end

    def self.wall_level(wall)
      (wall.get_attribute('InteriorPro', 'level') || 1).to_i
    end

    # A newly created wall lands on the active level: 'level' attribute +
    # a vertical lift to the level base. Level 1 = today's behavior exactly.
    def self.place_wall_on_active_level!(wall)
      return wall unless wall
      n = active_level
      wall.set_attribute('InteriorPro', 'level', n)
      if n > 1 && InteriorPro::WallTool.respond_to?(:set_wall_base!)
        InteriorPro::WallTool.set_wall_base!(wall, level_base(n))
      end
      wall
    rescue StandardError => e
      puts "[Levels] place_wall_on_active_level!: #{e.message}"
      wall
    end

    # ---------- Walls ----------

    # LEVEL-1 exterior walls — the ones that rise for the structure.
    def self.exterior_walls
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
          (g.get_attribute('InteriorPro', 'wall_category') || 'exterior') == 'exterior' &&
          (g.get_attribute('InteriorPro', 'level') || 1).to_i == 1
      end
    end

    def self.walls_of_level(n)
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
          (g.get_attribute('InteriorPro', 'level') || 1).to_i == n.to_i
      end
    end

    def self.all_walls
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
      end
    end

    # Rebuild a wall's body after a height change, keeping the STORED
    # corners — the footprint is untouched, so miters survive as-is.
    def self.rebuild_wall!(w)
      return unless InteriorPro::WallTool.respond_to?(:new)
      wt = InteriorPro::WallTool.new
      data = wt.wall_data(w)
      return unless data
      corners = wt.read_corners_attr(w) || wt.compute_perpendicular_corners_from_data(data)
      return unless corners
      wt.rebuild_wall_geometry(w, corners, data)
    rescue StandardError => e
      puts "[Levels] rebuild_wall!: #{e.message}"
    end

    def self.refresh_molding!
      InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
    rescue StandardError => e
      puts "[Molding] refresh after level change: #{e.message}"
    end

    # Every exterior wall grows to the level-2 floor. Running it again
    # after changing the structure numbers just re-tops the walls.
    def self.build_level2_structure!
      model = Sketchup.active_model
      ws = exterior_walls
      if ws.empty?
        UI.messagebox('No exterior walls found')
        return 0
      end
      target_top = level_base(2)
      raised = 0
      model.start_operation('InteriorPro Level 2 Structure', true)
      ws.each do |w|
        cur_h = w.get_attribute('InteriorPro', 'height').to_f
        # Remember where the ceiling is — ONCE (a second run must not
        # overwrite it with the already-raised height).
        if w.get_attribute('InteriorPro', 'ceiling_h').nil?
          w.set_attribute('InteriorPro', 'ceiling_h', cur_h)
        end
        new_h = target_top - w.get_attribute('InteriorPro', 'base_z').to_f
        next if new_h < 12.0 || (new_h - cur_h).abs < 0.01
        w.set_attribute('InteriorPro', 'height', new_h)
        rebuild_wall!(w)
        raised += 1
      end
      built = build_subfloor!
      model.commit_operation
      refresh_molding!
      puts "[Levels] level 2 structure: #{raised} wall(s) raised to #{target_top}\"#{built ? ', subfloor built' : ''}"
      raised
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Levels] build_level2_structure! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    # Undo: every wall that remembers a ceiling goes back to it.
    def self.remove_level2_structure!
      model = Sketchup.active_model
      lowered = 0
      model.start_operation('InteriorPro Remove Level 2 Structure', true)
      all_walls.each do |w|
        ch = w.get_attribute('InteriorPro', 'ceiling_h')
        next if ch.nil?
        w.set_attribute('InteriorPro', 'height', ch.to_f)
        w.delete_attribute('InteriorPro', 'ceiling_h')
        rebuild_wall!(w)
        lowered += 1
      end
      subs = subfloors
      subs.each { |s| s.erase! if s.valid? }
      model.commit_operation
      refresh_molding!
      puts "[Levels] removed: #{lowered} wall(s) back down, #{subs.length} subfloor(s) erased"
      lowered
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Levels] remove_level2_structure! failed: #{e.message}"
      0
    end

    # ---------- Subfloor deck ----------

    def self.subfloors
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'subfloor'
      end
    end

    def self.subfloor_material(model)
      m = model.materials['InteriorPro_Subfloor']
      return m if m
      m = model.materials.add('InteriorPro_Subfloor')
      m.color = Sketchup::Color.new(205, 170, 120) # plywood tan
      m
    end

    # Closed-loop outline of a set of walls, offset to their INTERIOR faces
    # (RoomManager machinery — same centerline/offset conventions as room
    # detection). Walls not in the set are ignored, so the polygon runs
    # OVER them with no gaps.
    def self.outline_from_walls(walls)
      rm = InteriorPro::RoomManager
      segs = walls.map { |w| rm.centerline(w) }.compact
      return nil if segs.length < 3
      nodes, edges = rm.build_graph(segs)
      faces = rm.trace_faces(nodes, edges)
      best = nil
      best_area = 0.0
      faces.each do |f|
        poly = f[:node_ids].map { |i| nodes[i] }
        sa = rm.signed_area(poly)
        next if sa <= 144.0 # interior faces only (outer face is negative)
        edata = f[:edge_ids].map { |i| edges[i] }
        inner = rm.inner_boundary(poly, edata)
        next unless inner
        if sa > best_area
          best_area = sa
          best = inner
        end
      end
      best
    rescue StandardError => e
      puts "[Levels] outline_from_walls: #{e.message}"
      nil
    end

    # The deck's footprint (user decision 2026-08-03): level 2 does not
    # always cover level 1 — where there is no level 2 a ROOF will come,
    # not a floor. So once LEVEL-2 walls close a loop, the deck spans only
    # between them. Before any level-2 walls exist, the whole level-1
    # footprint is the (temporary) default.
    def self.building_inner_outline
      lvl2 = walls_of_level(2)
      unless lvl2.empty?
        outline = outline_from_walls(lvl2)
        return outline if outline
        puts '[Levels] level-2 walls do not close a loop yet — deck falls back to the full footprint'
      end
      outline_from_walls(exterior_walls)
    end

    # The level-2 subfloor: top surface AT level_base(2), thickness DOWN
    # (like floors) so the walls' raised tops finish flush with it.
    def self.build_subfloor!
      model = Sketchup.active_model
      outline = building_inner_outline
      unless outline
        puts '[Levels] no closed exterior-wall loop — subfloor skipped'
        return nil
      end
      subfloors.each { |s| s.erase! if s.valid? }
      z_top = level_base(2)
      th = subfloor_depth
      pts = outline.map { |p| Geom::Point3d.new(p.x, p.y, z_top) }
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Subfloor'
      InteriorPro.assign_tag(grp, 'IP/Floors')
      face = begin
        grp.entities.add_face(pts)
      rescue StandardError
        nil
      end
      unless face
        grp.erase! if grp.valid?
        puts '[Levels] subfloor add_face failed'
        return nil
      end
      face.pushpull(face.normal.z > 0 ? -th : th)
      mat = subfloor_material(model)
      grp.entities.grep(Sketchup::Face).each { |f| f.material = mat }
      grp.set_attribute('InteriorPro', 'type', 'subfloor')
      grp.set_attribute('InteriorPro', 'id', format('sub-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'level', 2)
      grp.set_attribute('InteriorPro', 'thickness_in', th)
      grp.set_attribute('InteriorPro', 'top_z', z_top)
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      grp
    rescue StandardError => e
      puts "[Levels] build_subfloor! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end
  end
end

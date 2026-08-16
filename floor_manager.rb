# floor_manager.rb — floors built from room entities (CONTRACT_2D.md 4.6).
# Floor top surface sits at z=0, thickness goes DOWN (approved 2026-07-15).
# FLOOR_TYPES is the seed of the future floor library (tiles, grout etc.).
module InteriorPro
  module FloorManager
    FLOOR_TYPES = {
      'Hardwood' => { thickness: 0.75, color: [176, 132, 90],  texture: 'floor_hardwood.jpg', tex_size: 48 },
      'Tile'     => { thickness: 0.5,  color: [214, 212, 205], texture: 'floor_tile.jpg',     tex_size: 48 },
      'Carpet'   => { thickness: 0.5,  color: [196, 184, 166], texture: 'floor_carpet.jpg',   tex_size: 36 },
      'Concrete' => { thickness: 1.5,  color: [165, 165, 165], texture: 'floor_concrete.jpg', tex_size: 48 }
    }.freeze unless const_defined?(:FLOOR_TYPES, false)
    DEFAULT_TYPE = 'Hardwood' unless const_defined?(:DEFAULT_TYPE, false)

    # ---------- Dynamic floor library (2026-07-18) ----------
    # Every JPG/PNG dropped into textures/floors becomes a floor type
    # automatically — no code changes to add a material. Type name comes
    # from the file name (underscores -> spaces, capitalized). Defaults:
    # thickness 0.75", texture repeat 48".

    def self.floors_dir
      File.join(File.dirname(__FILE__), 'textures', 'floors')
    end

    def self.custom_types
      out = {}
      Dir.glob(File.join(floors_dir, '*.{jpg,jpeg,png,JPG,JPEG,PNG}')).sort.each do |f|
        name = File.basename(f, '.*').gsub(/[_-]+/, ' ').split.map(&:capitalize).join(' ')
        next if name.empty? || FLOOR_TYPES.key?(name)
        out[name] = { thickness: 0.75, color: [200, 200, 200], texture_path: f, tex_size: 48 }
      end
      out
    rescue StandardError => e
      puts "[Floors] custom_types: #{e.message}"
      {}
    end

    # Built-in types first, then everything found in textures/floors.
    def self.all_types
      FLOOR_TYPES.merge(custom_types)
    end

    # ---------- Texture picker (2026-07-18) ----------
    # The dialog separates WHAT the floor is (type -> thickness) from WHICH
    # material covers it (a texture file from textures/floors, stored per
    # floor as 'floor_texture' = file base name). Thumbnails live in
    # textures/floors/thumbs/<same name>.

    def self.texture_files
      Dir.glob(File.join(floors_dir, '*.{jpg,jpeg,png,JPG,JPEG,PNG}')).sort
    end

    # Special solid-color "materials" selectable like textures (no image).
    SOLID_COLORS = { 'White' => [255, 255, 255] }.freeze unless const_defined?(:SOLID_COLORS, false)

    def self.texture_material(model, base)
      if SOLID_COLORS.key?(base)
        name = "InteriorPro_FloorTex_#{base}"
        m = model.materials[name]
        return m if m
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*SOLID_COLORS[base])
        return m
      end
      f = texture_files.find { |p| File.basename(p, '.*') == base }
      return floor_material(model, DEFAULT_TYPE) unless f
      name = "InteriorPro_FloorTex_#{base.gsub(/\s+/, '_')}"
      m = model.materials[name]
      return m if m && m.texture
      m = model.materials.add(name) unless m
      m.texture = f
      m.texture.size = 48 if m.texture
      m
    end

    def self.floors_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'floor'
      end
    end

    # Real textures (2026-07-18): each floor type maps to a seamless JPG in
    # textures/ (V-Ray reads the SketchUp material directly). Existing
    # texture-less materials in old models are upgraded in place — the known
    # "existing material won't update" trap.
    def self.floor_material(model, type_name)
      types = all_types
      spec = types[type_name] || types[DEFAULT_TYPE]
      name = "InteriorPro_Floor_#{type_name.to_s.gsub(/\s+/, '_')}"
      m = model.materials[name]
      unless m
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*spec[:color])
      end
      if m.texture.nil?
        path = spec[:texture_path] ||
               (spec[:texture] && File.join(File.dirname(__FILE__), 'textures', spec[:texture]))
        if path && File.exist?(path)
          m.texture = path
          m.texture.size = spec[:tex_size] || 48 if m.texture
        end
      end
      m
    end

    # Build (or rebuild) the floor of one room group. Reads the room's
    # boundary_xy (world coords, interior wall faces). Returns the new group.
    def self.build_floor_for_room!(room_grp, type_name = nil, thickness: nil, texture: nil, level: nil)
      model = Sketchup.active_model
      room_id = room_grp.get_attribute('InteriorPro', 'id')
      flat = room_grp.get_attribute('InteriorPro', 'boundary_xy')
      return nil unless room_id && flat && flat.length >= 6

      old = floors_in_model.find { |f| f.get_attribute('InteriorPro', 'room_id') == room_id }
      type_name ||= old && old.get_attribute('InteriorPro', 'floor_type')
      types = all_types
      type_name = DEFAULT_TYPE unless types.key?(type_name)
      spec = types[type_name]
      thickness ||= old && old.get_attribute('InteriorPro', 'thickness_in')
      th = thickness.to_f > 0.05 ? thickness.to_f : spec[:thickness]
      # Pattern settings survive the rebuild (floor group is recreated).
      pat_attrs = {}
      if old
        %w[pattern unit_w unit_l pattern_ox pattern_oy pattern_angle pattern_center pattern_grout pattern_grout_color floor_texture floor_spec grout_spec floor_level drop_walls].each do |k|
          v = old.get_attribute('InteriorPro', k)
          pat_attrs[k] = v unless v.nil?
        end
      end
      # texture: nil = keep the old choice; '' = explicitly none; name = set.
      unless texture.nil?
        if texture.to_s.empty?
          pat_attrs.delete('floor_texture')
        else
          pat_attrs['floor_texture'] = texture.to_s
        end
      end
      # Per-room floor level (2026-07-18, garage at driveway height):
      # floor TOP surface sits at z = floor_level (inches; 0 = default).
      pat_attrs['floor_level'] = level.to_f unless level.nil?
      # Per-level rooms (2026-08-04): a room on an upper building level
      # defaults its floor TOP to that level's base (level 2 -> 106"),
      # instead of 0. An explicit floor_level always wins.
      room_lvl = (room_grp.get_attribute('InteriorPro', 'level') || 1).to_i
      if pat_attrs['floor_level'].nil? && room_lvl > 1 && defined?(InteriorPro::LevelManager)
        pat_attrs['floor_level'] = InteriorPro::LevelManager.level_base(room_lvl)
      end
      lvl = pat_attrs['floor_level'].to_f
      old.erase! if old && old.valid?

      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, lvl) }
      # Defensive: drop consecutive duplicate points (rooms stored before the
      # inner_boundary dedup fix, 2026-07-18) — add_face fails on them.
      clean = []
      pts.each { |p| clean << p if clean.empty? || clean.last.distance(p) > 0.01 }
      clean.pop if clean.length > 1 && clean.first.distance(clean.last) < 0.01
      return nil if clean.length < 3
      pts = clean
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Floor'
      InteriorPro.assign_tag(grp, 'IP/Floors')
      face = begin
        grp.entities.add_face(pts)
      rescue StandardError
        nil
      end
      unless face
        grp.erase! if grp.valid?
        puts "[Floors] add_face failed for room #{room_id}"
        return nil
      end
      # Extrude downward so the top surface stays at z = floor_level.
      face.pushpull(face.normal.z > 0 ? -th : th)
      tex = pat_attrs['floor_texture']
      mat = tex ? texture_material(model, tex) : floor_material(model, type_name)
      grp.entities.grep(Sketchup::Face).each { |f| f.material = mat }

      grp.set_attribute('InteriorPro', 'type', 'floor')
      grp.set_attribute('InteriorPro', 'id', format('floor-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'room_id', room_id)
      grp.set_attribute('InteriorPro', 'floor_type', type_name)
      grp.set_attribute('InteriorPro', 'thickness_in', th)
      grp.set_attribute('InteriorPro', 'area_sqft', room_grp.get_attribute('InteriorPro', 'area_sqft').to_f)
      grp.set_attribute('InteriorPro', 'level', room_lvl)
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      pat_attrs.each { |k, v| grp.set_attribute('InteriorPro', k, v) }
      grp
    rescue StandardError => e
      puts "[Floors] build_floor_for_room! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end

    # Toolbar action: build floors for ALL rooms, remove orphan floors.
    def self.build_floors!
      model = Sketchup.active_model
      rooms = InteriorPro::RoomManager.rooms_in_model
      if rooms.empty?
        puts '[Floors] no rooms — run Sync Rooms first'
        return 0
      end
      model.start_operation('InteriorPro Build Floors', true)
      n = rooms.count { |r| build_floor_for_room!(r) }
      room_ids = rooms.map { |r| r.get_attribute('InteriorPro', 'id') }
      floors_in_model.each do |f|
        f.erase! if f.valid? && !room_ids.include?(f.get_attribute('InteriorPro', 'room_id'))
      end
      build_door_patches!
      InteriorPro::FloorPattern.refresh_all! if defined?(InteriorPro::FloorPattern)
      model.commit_operation
      puts "[Floors] built #{n} floor(s)"
      n
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Floors] build_floors! failed: #{e.message}"
      0
    end

    # Called after room sync: rebuild only floors that already exist,
    # erase floors whose room disappeared. Rooms without floors are skipped.
    def self.refresh!
      model = Sketchup.active_model
      floors = floors_in_model
      return 0 if floors.empty?
      rooms_by_id = {}
      InteriorPro::RoomManager.rooms_in_model.each do |r|
        rooms_by_id[r.get_attribute('InteriorPro', 'id')] = r
      end
      model.start_operation('InteriorPro Refresh Floors', true)
      floors.each do |f|
        rid = f.get_attribute('InteriorPro', 'room_id')
        room = rooms_by_id[rid]
        if room
          build_floor_for_room!(room, f.get_attribute('InteriorPro', 'floor_type'))
        elsif f.valid?
          f.erase!
        end
      end
      build_door_patches!
      InteriorPro::FloorPattern.refresh_all! if defined?(InteriorPro::FloorPattern)
      model.commit_operation
      floors.length
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Floors] refresh! failed: #{e.message}"
      0
    end

    # ---------- Door threshold patches (2026-07-18) ----------
    # Floors stop at the interior wall faces, so a floor-level door opening
    # shows a hole the width of the wall. One patch group per opening fills
    # the wall thickness across the door width, using the adjacent floor's
    # type/thickness. Windows are excluded (floor_offset > 0).

    def self.patches_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'floor_patch'
      end
    end

    def self.remove_patches!
      patches_in_model.each { |p| p.erase! if p.valid? }
    end

    # ---------- Follow the door (2026-08-15) ----------
    #
    # The patch is worked out from the door's position along the wall, and it
    # was only ever worked out again when the user pressed Build Floors. So a
    # door that MOVED left its threshold behind, sitting in the old place -
    # which is exactly what the user saw: "the floor did not move with the
    # door". Adding a door had the same hole in it, and deleting one left a
    # patch floating in a wall with no opening.
    #
    # This is the door tools' door back into the floor code. It is the SAME
    # build_door_patches! the floor build already uses - there is no second
    # way to place a threshold - wrapped in its own operation so it can be
    # called from a tool that is not already inside one.
    #
    # transparent: true folds it into the step the caller just committed, so
    # one Ctrl+Z takes the door AND its threshold, not the threshold alone.
    # Same treatment MoldingManager.refresh! already gets.
    #
    # A model with no floors gets no operation at all - opening one would put
    # an empty step in the user's undo list for nothing.
    def self.refresh_door_patches!(transparent: false)
      return 0 if floors_in_model.empty?
      model = Sketchup.active_model
      model.start_operation('InteriorPro Door Thresholds', true, false, transparent)
      n = build_door_patches!
      model.commit_operation
      n
    rescue StandardError => e
      begin
        model.abort_operation
      rescue StandardError
        nil
      end
      puts "[Floors] refresh_door_patches! failed: #{e.class}: #{e.message}"
      0
    end

    def self.build_door_patches!
      model = Sketchup.active_model
      remove_patches!
      floors = floors_in_model
      return 0 if floors.empty?
      rooms_by_id = {}
      InteriorPro::RoomManager.rooms_in_model.each do |r|
        rooms_by_id[r.get_attribute('InteriorPro', 'id')] = r
      end
      floor_by_wall = {}
      floors.each do |f|
        room = rooms_by_id[f.get_attribute('InteriorPro', 'room_id')]
        next unless room
        (room.get_attribute('InteriorPro', 'bounding_wall_ids') || []).each do |wid|
          floor_by_wall[wid] ||= f
        end
      end
      n = 0
      model.entities.grep(Sketchup::Group).each do |w|
        next unless w.valid? && w.get_attribute('InteriorPro', 'type') == 'wall'
        fl = floor_by_wall[w.get_attribute('InteriorPro', 'id')]
        next unless fl
        openings = InteriorPro::WallTool.read_door_openings(w)
                                        .select { |o| o[:floor_offset].to_f <= 0.001 }
        next if openings.empty?
        geo = wall_patch_geometry(w)
        next unless geo
        openings.each { |o| n += 1 if build_patch!(w, geo, o, fl) }
      end
      puts "[Floors] #{n} door patch(es)" if n > 0
      n
    rescue StandardError => e
      puts "[Floors] build_door_patches! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    # World-space frame of a wall footprint: drawn start, along-unit u,
    # left perpendicular n, and the footprint's extent along n (from the
    # mitered corners) — enough to place an opening strip across the wall.
    def self.wall_patch_geometry(w)
      flat = w.get_attribute('InteriorPro', 'corners_xy')
      sx = w.get_attribute('InteriorPro', 'start_x')
      sy = w.get_attribute('InteriorPro', 'start_y')
      ex = w.get_attribute('InteriorPro', 'end_x')
      ey = w.get_attribute('InteriorPro', 'end_y')
      return nil unless flat && flat.length == 8 && sx && sy && ex && ey
      t = w.transformation
      s = Geom::Point3d.new(sx.to_f, sy.to_f, 0).transform(t)
      e = Geom::Point3d.new(ex.to_f, ey.to_f, 0).transform(t)
      s = Geom::Point3d.new(s.x, s.y, 0)
      e = Geom::Point3d.new(e.x, e.y, 0)
      u = e - s
      return nil if u.length < 1.0
      u.normalize!
      nvec = Geom::Vector3d.new(-u.y, u.x, 0)
      offs = flat.each_slice(2).map do |x, y|
        p = Geom::Point3d.new(x.to_f, y.to_f, 0).transform(t)
        (Geom::Point3d.new(p.x, p.y, 0) - s).dot(nvec)
      end
      { s: s, u: u, n: nvec, n_min: offs.min, n_max: offs.max }
    end

    def self.build_patch!(w, geo, o, floor)
      model = Sketchup.active_model
      types = all_types
      type_name = floor.get_attribute('InteriorPro', 'floor_type') || DEFAULT_TYPE
      type_name = DEFAULT_TYPE unless types.key?(type_name)
      th = floor.get_attribute('InteriorPro', 'thickness_in').to_f
      th = types[type_name][:thickness] if th <= 0.05
      lvl = floor.get_attribute('InteriorPro', 'floor_level').to_f
      u1 = o[:t] - o[:width] / 2.0
      u2 = o[:t] + o[:width] / 2.0
      pts = [[u1, geo[:n_min]], [u2, geo[:n_min]], [u2, geo[:n_max]], [u1, geo[:n_max]]].map do |uu, nn|
        Geom::Point3d.new(geo[:s].x + geo[:u].x * uu + geo[:n].x * nn,
                          geo[:s].y + geo[:u].y * uu + geo[:n].y * nn, lvl)
      end
      grp = model.entities.add_group
      grp.name = 'InteriorPro_FloorPatch'
      InteriorPro.assign_tag(grp, 'IP/Floors')
      face = begin
        grp.entities.add_face(pts)
      rescue StandardError
        nil
      end
      unless face
        grp.erase! if grp.valid?
        return false
      end
      face.pushpull(face.normal.z > 0 ? -th : th)
      tex = floor.get_attribute('InteriorPro', 'floor_texture')
      mat = tex ? texture_material(model, tex) : floor_material(model, type_name)
      grp.entities.grep(Sketchup::Face).each { |f| f.material = mat }
      grp.set_attribute('InteriorPro', 'type', 'floor_patch')
      grp.set_attribute('InteriorPro', 'host_wall_id', w.get_attribute('InteriorPro', 'id'))
      grp.set_attribute('InteriorPro', 'floor_type', type_name)
      grp.set_attribute('InteriorPro', 'thickness_in', th)
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      true
    rescue StandardError => e
      puts "[Floors] build_patch!: #{e.message}"
      false
    end

    # ---------- Drop walls with floor (2026-07-21) ----------
    # Garage automation: walls crossing the room boundary are split at the
    # boundary point (WallSplitTool.split_wall!, which re-syncs rooms), then
    # every wall bounding ONLY this room is dropped to the floor level via
    # WallTool.set_wall_base!. Walls shared with another room (the house)
    # keep their current base. Called from the floor dialog AFTER its own
    # operation commits (split_wall! opens operations of its own).
    CROSS_MIN = 12.0 unless const_defined?(:CROSS_MIN, false) # inches beyond room = crossing

    def self.find_room(room_id)
      InteriorPro::RoomManager.rooms_in_model.find do |r|
        r.get_attribute('InteriorPro', 'id') == room_id
      end
    end

    def self.drop_walls_with_floor!(room_id, level)
      model = Sketchup.active_model
      # Phase 1: split crossing walls, one at a time (each split re-syncs
      # rooms, so the room entity and wall ids are re-fetched every pass).
      20.times do
        room = find_room(room_id)
        break unless room
        break unless split_one_crossing_wall!(room)
      end
      room = find_room(room_id)
      unless room
        puts "[Floors] drop_walls: room #{room_id} not found after splits"
        return 0
      end
      my_ids = (room.get_attribute('InteriorPro', 'bounding_wall_ids') || []).compact.uniq
      shared = {}
      InteriorPro::RoomManager.rooms_in_model.each do |r|
        next if r == room
        (r.get_attribute('InteriorPro', 'bounding_wall_ids') || []).each { |wid| shared[wid] = true }
      end
      walls_by_id = {}
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        walls_by_id[g.get_attribute('InteriorPro', 'id')] = g
      end
      dropped = 0
      kept = 0
      dropped_groups = []
      model.start_operation('InteriorPro Drop Walls', true)
      my_ids.each do |wid|
        if shared[wid]
          kept += 1
          next
        end
        w = walls_by_id[wid]
        next unless w
        if InteriorPro::WallTool.set_wall_base!(w, level.to_f)
          dropped += 1
          dropped_groups << w
        end
      end
      square_mixed_base_corners!(dropped_groups)
      model.commit_operation
      # Foundation follows the walls' new bottoms (no-op when none exists).
      begin
        InteriorPro::FoundationManager.refresh! if defined?(InteriorPro::FoundationManager)
      rescue StandardError => fe
        puts "[Foundation] refresh after drop: #{fe.message}"
      end
      puts "[Floors] drop_walls: room #{room_id} level=#{level.to_f} -> #{dropped} dropped, #{kept} shared kept"
      dropped
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Floors] drop_walls_with_floor! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    # Find ONE wall of the room whose drawn line extends beyond the room's
    # boundary overlap by more than CROSS_MIN and split it at the boundary.
    # Returns true only when a split actually happened.
    def self.split_one_crossing_wall!(room)
      return false unless defined?(InteriorPro::WallSplitTool)
      flat = room.get_attribute('InteriorPro', 'boundary_xy')
      return false unless flat && flat.length >= 6
      verts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0) }
      ids = (room.get_attribute('InteriorPro', 'bounding_wall_ids') || []).compact.uniq
      walls = Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
          ids.include?(g.get_attribute('InteriorPro', 'id'))
      end
      walls.each do |w|
        drawn = InteriorPro::WallSplitTool.drawn_line_world(w)
        next unless drawn
        s = Geom::Point3d.new(drawn[0].x, drawn[0].y, 0)
        u = Geom::Point3d.new(drawn[1].x, drawn[1].y, 0) - s
        len = u.length
        next if len < 2.0 * CROSS_MIN
        u.normalize!
        th = w.get_attribute('InteriorPro', 'thickness').to_f
        tol = th + 2.0
        ts = []
        verts.each do |p|
          t = (p - s).dot(u)
          t = t.clamp(0.0, len)
          foot = s.offset(u, t)
          ts << t if p.distance(foot) <= tol
        end
        next if ts.length < 2
        tmin = ts.min
        tmax = ts.max
        next if tmax - tmin < 4.0 # touches at a point only, not an overlap
        cut = nil
        cut = tmin if tmin > CROSS_MIN
        cut = tmax if cut.nil? && tmax < len - CROSS_MIN
        next unless cut
        # The cut lands on the room boundary itself — the ROOM-facing face
        # of the touching separating wall — so the standing (house) wall
        # keeps the full corner and the dropped segment starts past it.
        # (An earlier snap_to_touching here moved the cut to the separating
        # wall's drawn line instead, leaving a base-height hole behind it —
        # removed 2026-07-21.)
        return true if InteriorPro::WallSplitTool.split_wall!(w, cut)
      end
      false
    rescue StandardError => e
      puts "[Floors] split_one_crossing_wall! failed: #{e.message}"
      false
    end

    # ---------- Mixed-base corner squaring (2026-07-21) ----------
    # An L-corner between a DROPPED wall and a STANDING wall keeps its 45deg
    # plan miter, so once one wall drops the exposed miter faces read as an
    # ugly diagonal. Convert such corners to a straight butt: the standing
    # wall gets a square end EXTENDED through the corner (to the dropped
    # wall's far face), the dropped wall gets a square end trimmed to the
    # standing wall's near face -> one straight vertical seam.
    # Corners between two walls dropped together keep their normal miter.
    # NOTE: assumes wall transformations are Z-translation only (true for
    # top-level walls + set_wall_base!), so local XY == world XY.
    MIXED_END_TOL = 1.0 unless const_defined?(:MIXED_END_TOL, false)

    def self.square_mixed_base_corners!(dropped_walls)
      return 0 if dropped_walls.nil? || dropped_walls.empty?
      wt = InteriorPro::WallTool.new
      all_walls = Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
      end
      fixed = 0
      dropped_walls.each do |w|
        next unless w.valid?
        [:start, :end].each do |side|
          dw = wt.wall_data_world(w)
          next unless dw
          w_base = w.get_attribute('InteriorPro', 'base_z').to_f
          cp = wt.endpoint_pt(dw, side)
          partner = nil
          p_side = nil
          p_data = nil
          all_walls.each do |g|
            next if g == w || !g.valid?
            next if (g.get_attribute('InteriorPro', 'base_z').to_f - w_base).abs < 0.01
            gd = wt.wall_data_world(g)
            next unless gd
            if cp.distance(wt.endpoint_pt(gd, :start)) < MIXED_END_TOL
              partner = g; p_side = :start; p_data = gd
            elsif cp.distance(wt.endpoint_pt(gd, :end)) < MIXED_END_TOL
              partner = g; p_side = :end; p_data = gd
            end
            break if partner
          end
          next unless partner
          u_w = axis_dir(dw)
          u_p = axis_dir(p_data)
          next unless u_w && u_p
          next if (u_w.x * u_p.y - u_w.y * u_p.x).abs < 0.05 # collinear seam is already straight
          fixed += 1 if square_corner!(wt, w, side, dw, u_w, partner, p_side, p_data, u_p)
        end
      end
      puts "[Floors] squared #{fixed} mixed-base corner(s)" if fixed > 0
      fixed
    rescue StandardError => e
      puts "[Floors] square_mixed_base_corners!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    # Unit vector along the drawn line (world, flattened), start -> end.
    def self.axis_dir(data)
      v = Geom::Vector3d.new(data[:drawn_end][0] - data[:drawn_start][0],
                             data[:drawn_end][1] - data[:drawn_start][1], 0)
      return nil if v.length < 0.001
      v.normalize!
      v
    end

    def self.anchor_offsets(h_anchor, t)
      case h_anchor
      when 'left' then [t, 0.0]
      when 'right' then [0.0, -t]
      else [t / 2.0, -t / 2.0]
      end
    end

    def self.square_corner!(wt, w, w_side, dw, u_w, p, p_side, pd, u_p)
      corner = wt.endpoint_pt(pd, p_side)
      u_out = p_side == :end ? u_p : Geom::Vector3d.new(-u_p.x, -u_p.y, 0)
      n_p = Geom::Vector3d.new(-u_p.y, u_p.x, 0)
      n_w = Geom::Vector3d.new(-u_w.y, u_w.x, 0)
      th_p = pd[:thickness].to_f
      th_w = dw[:thickness].to_f
      cl_w_s = Geom::Point3d.new(dw[:cl_start][0], dw[:cl_start][1], 0)
      cl_p_s = Geom::Point3d.new(pd[:cl_start][0], pd[:cl_start][1], 0)

      # 1) STANDING wall: square end extended to the dropped wall's far face.
      ext = 0.0
      [th_w / 2.0, -th_w / 2.0].each do |off|
        face_line = [cl_w_s.offset(n_w, off), u_w]
        hit = Geom.intersect_line_line([corner, u_out], face_line)
        next unless hit
        d = Geom::Vector3d.new(hit.x - corner.x, hit.y - corner.y, 0).dot(u_out)
        ext = d if d > ext
      end
      new_end_world = corner.offset(u_out, ext)
      p_inv = p.transformation.inverse
      pl = new_end_world.transform(p_inv)
      pl = Geom::Point3d.new(pl.x, pl.y, 0)
      pdl = wt.wall_data(p) # LOCAL frame
      return false unless pdl
      s_pt = Geom::Point3d.new(pdl[:drawn_start][0], pdl[:drawn_start][1], 0)
      e_pt = Geom::Point3d.new(pdl[:drawn_end][0], pdl[:drawn_end][1], 0)
      p_side == :start ? s_pt = pl : e_pt = pl
      perp = wt.perpendicular_corners_xy(s_pt, e_pt, th_p, pd[:h_anchor])
      return false unless perp
      pc = wt.read_corners_attr(p) || perp
      if p_side == :start
        pc[0] = perp[0]
        pc[3] = perp[3]
      else
        pc[1] = perp[1]
        pc[2] = perp[2]
      end
      wt.save_corners_attr(p, pc)
      wt.rebuild_wall_geometry(p, pc, pdl)

      # 2) DROPPED wall: square end trimmed to the standing wall's near face.
      w_far = wt.endpoint_pt(dw, w_side == :start ? :end : :start)
      ref = Geom::Vector3d.new(w_far.x - corner.x, w_far.y - corner.y, 0).dot(n_p)
      face_off = (ref >= 0 ? 1.0 : -1.0) * th_p / 2.0
      face_line = [cl_p_s.offset(n_p, face_off), u_p]
      pos_off, neg_off = anchor_offsets(dw[:h_anchor], th_w)
      ds = Geom::Point3d.new(dw[:drawn_start][0], dw[:drawn_start][1], 0)
      new_pos = Geom.intersect_line_line([ds.offset(n_w, pos_off), u_w], face_line)
      new_neg = Geom.intersect_line_line([ds.offset(n_w, neg_off), u_w], face_line)
      return false unless new_pos && new_neg
      w_inv = w.transformation.inverse
      lp = new_pos.transform(w_inv)
      ln = new_neg.transform(w_inv)
      wc = wt.read_corners_attr(w)
      wdl = wt.wall_data(w)
      return false unless wc && wdl
      if w_side == :start
        wc[0] = [lp.x, lp.y]
        wc[3] = [ln.x, ln.y]
      else
        wc[1] = [lp.x, lp.y]
        wc[2] = [ln.x, ln.y]
      end
      wt.save_corners_attr(w, wc)
      wt.rebuild_wall_geometry(w, wc, wdl)
      true
    rescue StandardError => e
      puts "[Floors] square_corner!: #{e.message}"
      false
    end

    def self.remove_floor_for_room!(room_id)
      f = floors_in_model.find { |g| g.get_attribute('InteriorPro', 'room_id') == room_id }
      f.erase! if f && f.valid?
      !f.nil?
    end

    def self.remove_all!
      model = Sketchup.active_model
      floors = floors_in_model
      return 0 if floors.empty?
      model.start_operation('InteriorPro Remove Floors', true)
      floors.each { |f| f.erase! if f.valid? }
      remove_patches!
      if defined?(InteriorPro::FloorPattern)
        InteriorPro::FloorPattern.patterns_in_model.each { |p| p.erase! if p.valid? }
      end
      model.commit_operation
      puts "[Floors] removed #{floors.length} floor(s)"
      floors.length
    end

    # Console helper until the floor dialog exists:
    #   InteriorPro::FloorManager.set_floor_type!('Kitchen', 'Tile')
    def self.set_floor_type!(room_name, type_name)
      unless all_types.key?(type_name)
        puts "[Floors] unknown type '#{type_name}'. Types: #{all_types.keys.join(', ')}"
        return false
      end
      room = InteriorPro::RoomManager.rooms_in_model.find do |g|
        g.get_attribute('InteriorPro', 'name') == room_name
      end
      unless room
        puts "[Floors] room '#{room_name}' not found"
        return false
      end
      model = Sketchup.active_model
      model.start_operation('InteriorPro Set Floor Type', true)
      grp = build_floor_for_room!(room, type_name)
      model.commit_operation
      puts "[Floors] #{room_name} -> #{type_name}" if grp
      !grp.nil?
    end
  end
end

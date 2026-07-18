# floor_manager.rb — floors built from room entities (CONTRACT_2D.md 4.6).
# Floor top surface sits at z=0, thickness goes DOWN (approved 2026-07-15).
# FLOOR_TYPES is the seed of the future floor library (tiles, grout etc.).
module InteriorPro
  module FloorManager
    FLOOR_TYPES = {
      'Hardwood' => { thickness: 0.75, color: [176, 132, 90] },
      'Tile'     => { thickness: 0.5,  color: [214, 212, 205] },
      'Carpet'   => { thickness: 0.5,  color: [196, 184, 166] },
      'Concrete' => { thickness: 1.5,  color: [165, 165, 165] }
    }.freeze unless const_defined?(:FLOOR_TYPES, false)
    DEFAULT_TYPE = 'Hardwood' unless const_defined?(:DEFAULT_TYPE, false)

    def self.floors_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'floor'
      end
    end

    def self.floor_material(model, type_name)
      spec = FLOOR_TYPES[type_name] || FLOOR_TYPES[DEFAULT_TYPE]
      name = "InteriorPro_Floor_#{type_name.to_s.gsub(/\s+/, '_')}"
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = Sketchup::Color.new(*spec[:color])
      m
    end

    # Build (or rebuild) the floor of one room group. Reads the room's
    # boundary_xy (world coords, interior wall faces). Returns the new group.
    def self.build_floor_for_room!(room_grp, type_name = nil, thickness: nil)
      model = Sketchup.active_model
      room_id = room_grp.get_attribute('InteriorPro', 'id')
      flat = room_grp.get_attribute('InteriorPro', 'boundary_xy')
      return nil unless room_id && flat && flat.length >= 6

      old = floors_in_model.find { |f| f.get_attribute('InteriorPro', 'room_id') == room_id }
      type_name ||= old && old.get_attribute('InteriorPro', 'floor_type')
      type_name = DEFAULT_TYPE unless FLOOR_TYPES.key?(type_name)
      spec = FLOOR_TYPES[type_name]
      thickness ||= old && old.get_attribute('InteriorPro', 'thickness_in')
      th = thickness.to_f > 0.05 ? thickness.to_f : spec[:thickness]
      # Pattern settings survive the rebuild (floor group is recreated).
      pat_attrs = {}
      if old
        %w[pattern unit_w unit_l pattern_ox pattern_oy pattern_angle pattern_center].each do |k|
          v = old.get_attribute('InteriorPro', k)
          pat_attrs[k] = v unless v.nil?
        end
      end
      old.erase! if old && old.valid?

      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0) }
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
      # Extrude downward so the top surface stays at z=0.
      face.pushpull(face.normal.z > 0 ? -th : th)
      mat = floor_material(model, type_name)
      grp.entities.grep(Sketchup::Face).each { |f| f.material = mat }

      grp.set_attribute('InteriorPro', 'type', 'floor')
      grp.set_attribute('InteriorPro', 'id', format('floor-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'room_id', room_id)
      grp.set_attribute('InteriorPro', 'floor_type', type_name)
      grp.set_attribute('InteriorPro', 'thickness_in', th)
      grp.set_attribute('InteriorPro', 'area_sqft', room_grp.get_attribute('InteriorPro', 'area_sqft').to_f)
      grp.set_attribute('InteriorPro', 'level', 1)
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
      type_name = floor.get_attribute('InteriorPro', 'floor_type') || DEFAULT_TYPE
      type_name = DEFAULT_TYPE unless FLOOR_TYPES.key?(type_name)
      th = floor.get_attribute('InteriorPro', 'thickness_in').to_f
      th = FLOOR_TYPES[type_name][:thickness] if th <= 0.05
      u1 = o[:t] - o[:width] / 2.0
      u2 = o[:t] + o[:width] / 2.0
      pts = [[u1, geo[:n_min]], [u2, geo[:n_min]], [u2, geo[:n_max]], [u1, geo[:n_max]]].map do |uu, nn|
        Geom::Point3d.new(geo[:s].x + geo[:u].x * uu + geo[:n].x * nn,
                          geo[:s].y + geo[:u].y * uu + geo[:n].y * nn, 0)
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
      mat = floor_material(model, type_name)
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
      unless FLOOR_TYPES.key?(type_name)
        puts "[Floors] unknown type '#{type_name}'. Types: #{FLOOR_TYPES.keys.join(', ')}"
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

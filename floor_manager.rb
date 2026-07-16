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
      model.commit_operation
      floors.length
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Floors] refresh! failed: #{e.message}"
      0
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

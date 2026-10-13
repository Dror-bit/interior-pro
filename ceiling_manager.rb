# ceiling_manager.rb — ceilings built from room entities (CONTRACT_2D.md 4.6).
# Mirror of FloorManager: floor top sits at floor_level and grows DOWN;
# the ceiling sits at floor_level + ceiling_height_in.
# ceiling_height_in is measured from the ROOM's floor level (a dropped
# garage keeps its own relative height). Default height comes from the
# lowest wall top among the room's bounding walls (base_z + height).
#
# Two styles (user decision 2026-08-03):
#   'flat'   — the DEFAULT. A single zero-thickness face painted white on
#              both sides. Future home of lighting fixtures etc.
#   'framed' — the thick ceiling under a second floor. For now it only
#              carries thickness (drywall); the full level-2 assembly
#              (2x10 joists, rim band in the wall's exterior material,
#              level-2 subfloor) arrives with the levels step.
module InteriorPro
  module CeilingManager
    STYLES            = %w[flat framed].freeze unless const_defined?(:STYLES, false)
    DEFAULT_STYLE     = 'flat' unless const_defined?(:DEFAULT_STYLE, false)
    DEFAULT_THICKNESS = 0.5  unless const_defined?(:DEFAULT_THICKNESS, false) # inches (drywall, framed only)
    DEFAULT_HEIGHT    = 96.0 unless const_defined?(:DEFAULT_HEIGHT, false)    # inches, fallback only

    # HOLES FOR RECESSED LIGHTS (2026-10-12, his words: "זה צריך לעשות חור
    # בתקרה איפה שהמנורה נופלת"). The rule of the floor (CLAUDE.md "חור ברצפה
    # חי על הרצפה"): the ceiling is BUILT with its holes, never cut after.
    # The holes come from the lights themselves - every placed light of
    # this room that carries 'hole_d' - so a rebuilt ceiling keeps them and a
    # light taken away gives its hole back on the next build.
    # Kill switch: false = every ceiling is built whole again.
    USE_CEILING_HOLES = true unless const_defined?(:USE_CEILING_HOLES, false)
    HOLE_SEGS = 24 unless const_defined?(:HOLE_SEGS, false)

    # [[x, y, d], ...] - the round holes the lights of this room need.
    def self.holes_for(room_id, model = Sketchup.active_model)
      return [] unless USE_CEILING_HOLES
      model.entities.grep(Sketchup::Group).map do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'electrical'
        next unless g.get_attribute('InteriorPro', 'mount') == 'ceiling' && g.get_attribute('InteriorPro', 'room_id') == room_id
        d = g.get_attribute('InteriorPro', 'hole_d').to_f
        next if d <= 0.0
        [g.get_attribute('InteriorPro', 'x_in').to_f, g.get_attribute('InteriorPro', 'y_in').to_f, d]
      end.compact
    end

    # Does a round hole sit wholly inside the outline (not touching an
    # edge)? PURE.
    def self.hole_fits?(poly, x, y, d)
      r = d / 2.0
      inside = false
      j = poly.length - 1
      poly.each_with_index do |(xi, yi), i|
        xj, yj = poly[j]
        inside = !inside if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi).to_f + xi
        # distance from the middle to this side
        dx = xj - xi
        dy = yj - yi
        l2 = dx * dx + dy * dy
        t = l2 > 0 ? [[((x - xi) * dx + (y - yi) * dy) / l2, 0.0].max, 1.0].min : 0.0
        px = xi + t * dx
        py = yi + t * dy
        return false if Math.sqrt((x - px)**2 + (y - py)**2) < r + 0.05
        j = i
      end
      inside
    end

    # Cut the holes into the flat ceiling face being built: a circle drawn
    # on the face splits off a disc, and the disc is taken away.
    def self.punch_holes!(grp, holes, z, poly)
      holes.each do |x, y, d|
        unless hole_fits?(poly, x, y, d)
          puts "[Ceilings] hole #{d.round(2)}\" at #{x.round(1)},#{y.round(1)} skipped - not wholly inside the ceiling"
          next
        end
        edges = grp.entities.add_circle(Geom::Point3d.new(x, y, z), Geom::Vector3d.new(0, 0, 1), d / 2.0, HOLE_SEGS)
        disc = edges.flat_map(&:faces).uniq.find { |f| f.edges.all? { |e| edges.include?(e) } }
        if disc
          disc.erase!
        else
          puts "[Ceilings] hole at #{x.round(1)},#{y.round(1)} - no disc found, nothing cut"
        end
      end
    end

    def self.ceilings_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'ceiling'
      end
    end

    def self.ceiling_material(model)
      name = 'InteriorPro_Ceiling'
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = Sketchup::Color.new(255, 255, 255)
      m
    end

    # The room's floor level (inches; 0 when the room has no floor yet).
    # Read straight from the floor group so this file does not depend on
    # FloorManager being loaded.
    def self.room_floor_level(room_id)
      f = Sketchup.active_model.entities.grep(Sketchup::Group).find do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'floor' &&
          g.get_attribute('InteriorPro', 'room_id') == room_id
      end
      f ? f.get_attribute('InteriorPro', 'floor_level').to_f : 0.0
    end

    # Default ceiling height ABOVE the room's floor: the lowest wall top
    # (base_z + height) among the bounding walls, minus the floor level.
    # The MINIMUM keeps a dropped room (garage) honest — its shared wall
    # with the house stands higher and must not push the ceiling up.
    def self.default_height_for_room(room_grp, floor_level)
      ids = (room_grp.get_attribute('InteriorPro', 'bounding_wall_ids') || []).compact.uniq
      tops = []
      Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        next unless ids.include?(g.get_attribute('InteriorPro', 'id'))
        h = g.get_attribute('InteriorPro', 'height').to_f
        # A wall raised for the level-2 structure remembers its ceiling in
        # 'ceiling_h' — the ceiling sits THERE, not at the raised top.
        ch = g.get_attribute('InteriorPro', 'ceiling_h').to_f
        h = ch if ch > 1.0 && ch < h
        next if h < 1.0
        tops << g.get_attribute('InteriorPro', 'base_z').to_f + h
      end
      return DEFAULT_HEIGHT if tops.empty?
      tops.min - floor_level
    end

    # Build (or rebuild) the ceiling of one room. Reads the room's
    # boundary_xy (world coords, interior wall faces). Returns the group.
    # Existing ceilings without a stored style become 'flat' on rebuild.
    def self.build_ceiling_for_room!(room_grp, height: nil, thickness: nil, style: nil)
      model = Sketchup.active_model
      room_id = room_grp.get_attribute('InteriorPro', 'id')
      flat = room_grp.get_attribute('InteriorPro', 'boundary_xy')
      return nil unless room_id && flat && flat.length >= 6

      old = ceilings_in_model.find { |c| c.get_attribute('InteriorPro', 'room_id') == room_id }
      height ||= old && old.get_attribute('InteriorPro', 'ceiling_height_in')
      thickness ||= old && old.get_attribute('InteriorPro', 'thickness_in')
      style ||= old && old.get_attribute('InteriorPro', 'ceiling_style')
      style = DEFAULT_STYLE unless STYLES.include?(style)
      th = style == 'flat' ? 0.0 : (thickness.to_f > 0.05 ? thickness.to_f : DEFAULT_THICKNESS)
      lvl = room_floor_level(room_id)
      ch = height.to_f > 1.0 ? height.to_f : default_height_for_room(room_grp, lvl)
      z_bottom = lvl + ch
      old.erase! if old && old.valid?

      pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, z_bottom) }
      # Defensive: drop consecutive duplicate points — add_face fails on them
      # (same guard as FloorManager).
      clean = []
      pts.each { |p| clean << p if clean.empty? || clean.last.distance(p) > 0.01 }
      clean.pop if clean.length > 1 && clean.first.distance(clean.last) < 0.01
      return nil if clean.length < 3
      pts = clean
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Ceiling'
      InteriorPro.assign_tag(grp, 'IP/Ceilings')
      face = begin
        grp.entities.add_face(pts)
      rescue StandardError
        nil
      end
      unless face
        grp.erase! if grp.valid?
        puts "[Ceilings] add_face failed for room #{room_id}"
        return nil
      end
      mat = ceiling_material(model)
      if style == 'framed'
        # Extrude UP so the bottom face stays at z_bottom.
        face.pushpull(face.normal.z > 0 ? th : -th)
        grp.entities.grep(Sketchup::Face).each { |f| f.material = mat }
      else
        # Flat: one zero-thickness face, white on both sides.
        face.material = mat
        face.back_material = mat
        holes = holes_for(room_id, model)
        punch_holes!(grp, holes, z_bottom, pts.map { |p| [p.x.to_f, p.y.to_f] }) unless holes.empty?
      end
      if style == 'framed' && !holes_for(room_id, model).empty?
        puts "[Ceilings] room #{room_id}: framed ceiling - light holes not cut yet (flat only)"
      end

      grp.set_attribute('InteriorPro', 'type', 'ceiling')
      grp.set_attribute('InteriorPro', 'id', format('ceil-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'room_id', room_id)
      grp.set_attribute('InteriorPro', 'ceiling_style', style)
      grp.set_attribute('InteriorPro', 'ceiling_height_in', ch)
      grp.set_attribute('InteriorPro', 'thickness_in', th)
      grp.set_attribute('InteriorPro', 'area_sqft', room_grp.get_attribute('InteriorPro', 'area_sqft').to_f)
      grp.set_attribute('InteriorPro', 'level', room_grp.get_attribute('InteriorPro', 'level') || 1)
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      grp
    rescue StandardError => e
      puts "[Ceilings] build_ceiling_for_room! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end

    # Toolbar action: build ceilings for ALL rooms, remove orphan ceilings.
    def self.build_ceilings!
      model = Sketchup.active_model
      rooms = InteriorPro::RoomManager.rooms_in_model
      if rooms.empty?
        puts '[Ceilings] no rooms — run Sync Rooms first'
        return 0
      end
      model.start_operation('InteriorPro Build Ceilings', true)
      n = rooms.count { |r| build_ceiling_for_room!(r) }
      room_ids = rooms.map { |r| r.get_attribute('InteriorPro', 'id') }
      ceilings_in_model.each do |c|
        c.erase! if c.valid? && !room_ids.include?(c.get_attribute('InteriorPro', 'room_id'))
      end
      model.commit_operation
      puts "[Ceilings] built #{n} ceiling(s)"
      n
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Ceilings] build_ceilings! failed: #{e.message}"
      0
    end

    # Called after room sync: rebuild only ceilings that already exist,
    # erase ceilings whose room disappeared. Rooms without a ceiling are
    # skipped (a ceiling is built only when asked for).
    def self.refresh!
      model = Sketchup.active_model
      ceilings = ceilings_in_model
      return 0 if ceilings.empty?
      rooms_by_id = {}
      InteriorPro::RoomManager.rooms_in_model.each do |r|
        rooms_by_id[r.get_attribute('InteriorPro', 'id')] = r
      end
      model.start_operation('InteriorPro Refresh Ceilings', true)
      ceilings.each do |c|
        rid = c.get_attribute('InteriorPro', 'room_id')
        room = rooms_by_id[rid]
        if room
          build_ceiling_for_room!(room)
        elsif c.valid?
          c.erase!
        end
      end
      model.commit_operation
      ceilings.length
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Ceilings] refresh! failed: #{e.message}"
      0
    end

    def self.remove_ceiling_for_room!(room_id)
      c = ceilings_in_model.find { |g| g.get_attribute('InteriorPro', 'room_id') == room_id }
      c.erase! if c && c.valid?
      !c.nil?
    end

    def self.remove_all!
      model = Sketchup.active_model
      ceilings = ceilings_in_model
      return 0 if ceilings.empty?
      model.start_operation('InteriorPro Remove Ceilings', true)
      ceilings.each { |c| c.erase! if c.valid? }
      model.commit_operation
      puts "[Ceilings] removed #{ceilings.length} ceiling(s)"
      ceilings.length
    end

    # Console helper:
    #   InteriorPro::CeilingManager.set_ceiling_height!('Kitchen', 108)
    def self.set_ceiling_height!(room_name, height_in)
      room = InteriorPro::RoomManager.rooms_in_model.find do |g|
        g.get_attribute('InteriorPro', 'name') == room_name
      end
      unless room
        puts "[Ceilings] room '#{room_name}' not found"
        return false
      end
      model = Sketchup.active_model
      model.start_operation('InteriorPro Set Ceiling Height', true)
      grp = build_ceiling_for_room!(room, height: height_in.to_f)
      model.commit_operation
      puts "[Ceilings] #{room_name} -> #{height_in}\"" if grp
      !grp.nil?
    end

    # Console helper:
    #   InteriorPro::CeilingManager.set_ceiling_style!('Kitchen', 'framed')
    def self.set_ceiling_style!(room_name, style)
      unless STYLES.include?(style)
        puts "[Ceilings] unknown style '#{style}'. Styles: #{STYLES.join(', ')}"
        return false
      end
      room = InteriorPro::RoomManager.rooms_in_model.find do |g|
        g.get_attribute('InteriorPro', 'name') == room_name
      end
      unless room
        puts "[Ceilings] room '#{room_name}' not found"
        return false
      end
      model = Sketchup.active_model
      model.start_operation('InteriorPro Set Ceiling Style', true)
      grp = build_ceiling_for_room!(room, style: style)
      model.commit_operation
      puts "[Ceilings] #{room_name} -> #{style}" if grp
      !grp.nil?
    end
  end
end

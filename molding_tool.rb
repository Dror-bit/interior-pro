# Interior Pro - Molding Tool (Stage A: baseboard)
# Click a wall face -> baseboard runs along that face at the floor,
# skipping door openings automatically.

module InteriorPro
  class MoldingTool

    def initialize(profile_name = nil)
      @profile_name = profile_name || MoldingLibrary::BASEBOARDS.keys.first
    end

    def activate
      Sketchup.status_text = "Baseboard (#{@profile_name}): click a wall face"
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      wall = find_wall(ph)
      unless wall
        UI.messagebox('Click on an Interior Pro wall')
        return
      end
      click_pt = view.inputpoint(x, y).position
      build_baseboard!(wall, click_pt)
      view.invalidate
    end

    private

    def find_wall(ph)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |ent|
          next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
          return ent if ent.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end
      nil
    end

    def build_baseboard!(wall, click_pt)
      model = Sketchup.active_model
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      flat = wall.get_attribute('InteriorPro', 'corners_xy')
      unless flat && flat.length == 8
        puts '[MoldingTool] wall has no corners_xy'
        return
      end
      # corners: [s_pos, e_pos, e_neg, s_neg] — the two long face edges.
      s_pos = Geom::Point3d.new(flat[0], flat[1], 0)
      e_pos = Geom::Point3d.new(flat[2], flat[3], 0)
      e_neg = Geom::Point3d.new(flat[4], flat[5], 0)
      s_neg = Geom::Point3d.new(flat[6], flat[7], 0)

      # pick the face edge closer to the click
      d_pos = click_pt.distance(click_pt.project_to_line([s_pos, e_pos]))
      d_neg = click_pt.distance(click_pt.project_to_line([s_neg, e_neg]))
      if d_pos <= d_neg
        p0, p1, q0 = s_pos, e_pos, s_neg
        side = 1
      else
        p0, p1, q0 = s_neg, e_neg, s_pos
        side = -1
      end

      face_len = p0.distance(p1)
      if face_len < 1.0
        puts "[MoldingTool] face too short: #{face_len}"
        return
      end
      u = Geom::Vector3d.new((p1.x - p0.x) / face_len, (p1.y - p0.y) / face_len, 0)
      nd = Geom::Vector3d.new(p0.x - q0.x, p0.y - q0.y, 0)
      nd.length = 1.0
      base = Geom::Point3d.new(p0.x, p0.y, 0)

      # openings t is measured along the drawn axis from the wall start —
      # shift into this face edge's parameter space.
      offset0 = Geom::Vector3d.new(sx - p0.x, sy - p0.y, 0).dot(u)

      spec = MoldingLibrary::BASEBOARDS[@profile_name]
      prof = MoldingLibrary.baseboard_profile(spec)
      openings = InteriorPro::WallTool.read_door_openings(wall)
      shifted = openings.map { |o| { t: o[:t] + offset0, width: o[:width] } }
      segs = segments(face_len, shifted)

      model.start_operation('Baseboard', true)
      grp = model.active_entities.add_group
      grp.name = 'Baseboard'
      grp.set_attribute('InteriorPro', 'type', 'baseboard')
      grp.set_attribute('InteriorPro', 'host_wall_id', wall.get_attribute('InteriorPro', 'id'))
      grp.set_attribute('InteriorPro', 'profile', @profile_name)
      grp.set_attribute('InteriorPro', 'side', side)
      ge = grp.entities

      built = 0
      segs.each do |a, b|
        next if b - a < 0.5
        pts = prof.map do |d, z|
          Geom::Point3d.new(base.x + u.x * a + nd.x * d,
                            base.y + u.y * a + nd.y * d, z)
        end
        face = ge.add_face(pts)
        next unless face
        dist = b - a
        face.pushpull(face.normal.dot(u) > 0 ? dist : -dist)
        built += 1
      end
      grp.material = molding_material(model)
      model.commit_operation
      puts "[MoldingTool] baseboard: wall=#{wall.get_attribute('InteriorPro', 'id')} side=#{side} segments=#{built} (openings=#{openings.length})"
    rescue StandardError => e
      begin; model.abort_operation; rescue StandardError; end
      puts "[MoldingTool] error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end

    # Complement of door-opening gaps along [0, len]. Opening t = center.
    def segments(len, openings)
      gaps = openings.map { |o| [o[:t] - o[:width] / 2.0, o[:t] + o[:width] / 2.0] }
                     .map { |a, b| [[a, 0.0].max, [b, len].min] }
                     .select { |a, b| b > a }
                     .sort_by(&:first)
      segs = []
      cur = 0.0
      gaps.each do |a, b|
        segs << [cur, a] if a > cur
        cur = b if b > cur
      end
      segs << [cur, len] if len > cur
      segs
    end

    def molding_material(model)
      m = model.materials['InteriorPro_Molding']
      return m if m
      m = model.materials.add('InteriorPro_Molding')
      m.color = Sketchup::Color.new(245, 245, 240)
      m
    end

  end
end

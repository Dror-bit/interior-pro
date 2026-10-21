# Interior Pro - Door Leaf Styles
# Standalone leaf-design catalog + geometry builder for interior doors.
# Data source: reports/metrie_interior_doors.json (verified Masonite/JELD-WEN specs).
# Coordinate system matches door_tool.rb: u = along wall (width), v = wall normal (n),
# w = height. All dims in inches. Leaf thickness 1-3/8".
#
# Usage (from door_tool.rb, later step):
#   InteriorPro::DoorLeafStyles.build_leaf_body!(ents, 'Caiman', u0, u1, w0, w1, vf, vb, unit, n)
#
# This file has NO dependencies on other plugin files and changes nothing by itself.

module InteriorPro
  module DoorLeafStyles

    %i[LEAF_THICKNESS PANEL_RECESS RAISE_BACK ARCH_SEGMENTS FRAMES STYLES
       PANEL_GAP SHOULDER_W RAISE_TOP_GAP REALISTIC_DETAILS EDGE_RADIUS].each do |c|
      remove_const(c) if const_defined?(c, false)
    end

    LEAF_THICKNESS = 1.375
    PANEL_RECESS   = 0.25   # recess depth per face
    RAISE_BACK     = 0.15   # (legacy, unused by raised styles - see frustum insert)
    ARCH_SEGMENTS  = 24
    PANEL_GAP      = 0.25   # visible groove between recess edge and raised field
    SHOULDER_W     = 0.75   # sloped shoulder width of the raised field
    RAISE_TOP_GAP  = 0.05   # raised field top sits this far below the slab face
    REALISTIC_DETAILS = true # false restores sharp slabs, original rail and no new hinges.
    EDGE_RADIUS = 0.06       # 1.524 mm; geometry, visible in rendered output too.

    # Frame member widths (inches) per family.
    FRAMES = {
      'shaker'   => { stile: 4.4375, top: 4.3125, bottom: 9.1875, mid: 4.3125, lock: 7.4375 },
      'moulded'  => { stile: 4.75,   top: 4.25,   bottom: 10.87,  mid: 4.25,   lock: 6.75 },
      'colonial' => { stile: 4.5625, top: 4.5,    bottom: 9.25,   frieze: 4.5, lock: 7.5, muntin: 4.5 },
      'french'   => { stile: 4.5625, top: 4.5625, bottom: 9.125 }
    }.freeze

    # The 10 selected designs (selected_by_user in metrie_interior_doors.json).
    # kind: :flush | :stacked | :colonial | :lite
    # split: relative panel heights top->bottom (nil = equal)
    # arch:  nil | :round | :eyebrow  (top edge of the TOP panel only)
    # raised: inner field pops back out (moulded/colonial look) vs flat shaker recess
    STYLES = {
      'Flush'            => { kind: :flush },
      '1 Panel Shaker'   => { kind: :stacked, frame: 'shaker', rows: 1 },
      '2 Panel Shaker'   => { kind: :stacked, frame: 'shaker', rows: 2, mid_key: :lock, handle_rail: true },
      '5 Panel Shaker'   => { kind: :stacked, frame: 'shaker', rows: 5 },
      '6 Panel Colonial' => { kind: :colonial, frame: 'colonial', raised: true },
      '1 Lite Clear'     => { kind: :lite, frame: 'french' },
      'Caiman'           => { kind: :stacked, frame: 'moulded', rows: 2, mid_key: :lock,
                              split: [0.58, 0.42], arch: :round, raised: true },
      'Carrara'          => { kind: :stacked, frame: 'moulded', rows: 2, mid_key: :lock,
                              split: [0.58, 0.42], raised: true },
      'Camden'           => { kind: :stacked, frame: 'moulded', rows: 2, mid_key: :lock,
                              split: [0.58, 0.42], arch: :eyebrow, raised: true },
      'Colonist'         => { kind: :colonial, frame: 'colonial', raised: true }
    }.freeze

    def self.style_names
      STYLES.keys
    end

    def self.default_style
      'Flush'
    end

    # ------------------------------------------------------------------
    # Main entry: builds one leaf as a Group inside parent_ents.
    # u0..u1 leaf width span, w0..w1 leaf height span, vf..vb leaf depth span.
    # unit = width unit vector, n = wall normal unit vector.
    # Returns the leaf Group (or nil on failure).
    # ------------------------------------------------------------------
    def self.build_leaf_body!(parent_ents, style_name, u0, u1, w0, w1, vf, vb, unit, n, name: 'Leaf', leaf_mat: nil)
      spec = STYLES[style_name.to_s] || STYLES[default_style]
      leaf = parent_ents.add_group
      leaf.name = name
      le = leaf.entities

      model = Sketchup.active_model
      frame_mat = leaf_mat || get_or_create_material(model, 'InteriorPro_Door_Leaf', [250, 248, 243], 1.0)
      glass_mat = get_or_create_material(model, 'InteriorPro_Glass', [180, 180, 180], 0.4)

      if spec[:kind] == :lite
        ok = build_lite_leaf!(le, spec, u0, u1, w0, w1, vf, vb, unit, n, glass_mat)
      else
        ok = if REALISTIC_DETAILS
               build_rounded_slab!(le, u0, u1, w0, w1, vf, vb, unit, n)
             else
               build_slab!(le, u0, u1, w0, w1, vf, vb, unit, n)
             end
        if ok && spec[:kind] != :flush
          panels = panel_rects(spec, u0, u1, w0, w1)
          panels.each do |p|
            carve_panel_both_faces!(le, p, vf, vb, unit, n, raised: spec[:raised])
          end
        end
      end

      unless ok
        leaf.erase! if leaf.valid?
        return nil
      end
      leaf.material = frame_mat
      leaf
    end

    # ------------------------------------------------------------------
    # Panel rectangles for a style, in leaf-local u/w coordinates.
    # Each entry: { u0:, u1:, w0:, w1:, arch: nil/:round/:eyebrow }
    # ------------------------------------------------------------------
    def self.panel_rects(spec, u0, u1, w0, w1)
      f = FRAMES[spec[:frame]]
      return [] unless f

      pu0 = u0 + f[:stile]
      pu1 = u1 - f[:stile]
      return [] if pu1 - pu0 < 2.0

      case spec[:kind]
      when :stacked
        rows = spec[:rows].to_i
        mid  = f[spec[:mid_key] || :mid] || f[:mid]
        field = (w1 - f[:top]) - (w0 + f[:bottom])
        return [] if field < 4.0
        gaps = rows - 1
        panel_space = field - gaps * mid
        heights =
          if spec[:split] && spec[:split].length == rows
            spec[:split].map { |r| panel_space * r }
          else
            Array.new(rows, panel_space / rows)
          end
        rects = []
        w_top = w1 - f[:top]
        rows.times do |i|
          h = heights[i]
          rects << { u0: pu0, u1: pu1, w0: w_top - h, w1: w_top,
                     arch: (i.zero? ? spec[:arch] : nil) }
          w_top -= (h + mid)
        end
        if REALISTIC_DETAILS && spec[:handle_rail] && rows == 2
          # Same 36-inch datum as DoorTool#place_leaf_handles!. Keep the top,
          # bottom and rail widths; only the two panel heights change.
          center = w0 + 36.0
          lo, hi = center - mid / 2.0, center + mid / 2.0
          if lo - rects.last[:w0] >= 2.0 && rects.first[:w1] - hi >= 2.0
            rects.first[:w0] = hi
            rects.last[:w1] = lo
          end
        end
        rects

      when :colonial
        # 2 cols x 3 rows, top row short. Rows scale with door height.
        mu = f[:muntin]
        col_w = (pu1 - pu0 - mu) / 2.0
        return [] if col_w < 2.0
        field = (w1 - f[:top]) - (w0 + f[:bottom]) - f[:frieze] - f[:lock]
        return [] if field < 6.0
        r_top = field * 0.2166
        r_mid = field * 0.3917
        r_bot = field - r_top - r_mid
        w_t1 = w1 - f[:top]
        w_t2 = w_t1 - r_top - f[:frieze]
        w_t3 = w_t2 - r_mid - f[:lock]
        rows = [[w_t1, r_top], [w_t2, r_mid], [w_t3, r_bot]]
        rects = []
        rows.each do |wt, h|
          [pu0, pu0 + col_w + mu].each do |cx|
            rects << { u0: cx, u1: cx + col_w, w0: wt - h, w1: wt, arch: nil }
          end
        end
        rects
      else
        []
      end
    end

    # ------------------------------------------------------------------
    # Geometry helpers
    # ------------------------------------------------------------------

    def self.local_uvw(u, v, w, unit, n)
      Geom::Point3d.new(
        u * unit.x + v * n.x,
        u * unit.y + v * n.y,
        w
      )
    end

    def self.build_slab!(le, u0, u1, w0, w1, vf, vb, unit, n)
      pts = [
        local_uvw(u0, vf, w0, unit, n),
        local_uvw(u1, vf, w0, unit, n),
        local_uvw(u1, vf, w1, unit, n),
        local_uvw(u0, vf, w1, unit, n)
      ]
      face = le.add_face(pts)
      return false unless face&.valid?
      depth = vb - vf
      depth = -depth if face.normal.dot(n) < 0
      face.pushpull(depth)
      true
    end

    # Build small rounds at 100x to avoid SketchUp's small-face tolerance.
    # Only these outer seams are softened; panel outlines remain hard edges.
    def self.build_rounded_slab!(le, u0, u1, w0, w1, vf, vb, unit, n)
      y0, y1 = [vf, vb].minmax
      r = [EDGE_RADIUS, (u1-u0)/4.0, (w1-w0)/4.0, (y1-y0)/4.0].min
      return false unless r > 0.0
      stations = 5.times.map do |i|
        a = i * Math::PI / 8.0
        [y0 + r * (1-Math.cos(a)), r * (1-Math.sin(a))]
      end
      stations += stations.reverse.map { |y, d| [y1-(y-y0), d] }
      rings = stations.map do |y, d|
        rounded_outline(u0+d, u1-d, w0+d, w1-d, y, r).map do |p|
          Geom::Point3d.new(*p.map { |x| x * 100.0 })
        end
      end
      front = le.add_face(rings.first)
      return false unless front&.valid?
      front.reverse! if front.normal.y > 0
      back = le.add_face(rings.last.reverse)
      return false unless back&.valid?
      back.reverse! if back.normal.y < 0
      rings.each_cons(2) do |a, b|
        a.length.times do |i|
          j = (i+1) % a.length
          le.add_face(a[i], b[i], b[j])
          le.add_face(a[i], b[j], a[j])
        end
      end
      axes = Geom::Transformation.axes(ORIGIN, unit, n, Z_AXIS)
      le.transform_entities(axes * Geom::Transformation.scaling(0.01), le.to_a)
      soften_rounds!(le, 40.degrees)
      true
    end

    def self.rounded_outline(u0, u1, w0, w1, v, r)
      [[u0+r, w0+r, Math::PI], [u1-r, w0+r, 1.5*Math::PI],
       [u1-r, w1-r, 0], [u0+r, w1-r, 0.5*Math::PI]].flat_map do |u, w, a|
        5.times.map do |i|
          angle = a + i * Math::PI / 8.0
          [u+r*Math.cos(angle), v, w+r*Math.sin(angle)]
        end
      end
    end

    def self.soften_rounds!(ents, angle)
      ents.grep(Sketchup::Edge).each do |edge|
        next unless edge.faces.length == 2
        next unless edge.faces[0].normal.angle_between(edge.faces[1].normal) < angle
        edge.soft = true
        edge.smooth = true
      end
    end

    # Closed butt hinges: each plate/knuckle is its own solid. No wall editing,
    # extra operation, or global style change. side is -1 left, +1 right.
    def self.build_hinges!(ents, u, side, w0, w1, vf, vb, out_sign, unit, n, mat)
      return unless REALISTIC_DETAILS
      height = w1-w0
      return if height < 8.0
      margin = [8.75, height/5.0].min
      centers = [w0+margin, (w0+w1)/2.0, w1-margin]
      face_v = out_sign > 0 ? [vf,vb].max : [vf,vb].min
      barrel_v = face_v + out_sign*0.18
      plate_vs = [face_v-out_sign*1.27, face_v+out_sign*0.07].minmax
      centers.each_with_index do |w, index|
        hinge = ents.add_group
        hinge.name = "Hinge_#{side < 0 ? 'Left' : 'Right'}_#{index+1}"
        hinge.material = get_or_create_material(Sketchup.active_model,
          'InteriorPro_Door_Hinge', [85, 88, 92], 1.0)
        # Both plates sit ON their host surfaces, facing into the 1/8-inch
        # reveal. The old intervals buried the plates and screws in the wood.
        [[u, u+side*0.055], [u+side*0.125, u+side*0.070]].each_with_index do |us, k|
          a,b = us.minmax
          hinge_plate!(hinge.entities, k.zero? ? 'Leaf plate' : 'Jamb plate',
            a, b, plate_vs[0], plate_vs[1], w, unit, n)
          screw_u = u+side*(k.zero? ? 0.055 : 0.070)
          screw_n = Geom::Vector3d.new(unit.x*side*(k.zero? ? 1 : -1), unit.y*side*(k.zero? ? 1 : -1), 0)
          [-1.1,0,1.1].each do |dz|
            hinge_cylinder!(hinge.entities, k.zero? ? 'Leaf screw' : 'Jamb screw',
              local_uvw(screw_u, face_v-out_sign*0.69, w+dz, unit,n),
              screw_n, 0.105, 0.024, slot_axis: n)
          end
        end
        5.times do |i|
          hinge_cylinder!(hinge.entities, 'Knuckle', local_uvw(u,barrel_v,w-1.75+i*0.7,unit,n), Z_AXIS, 0.22, 0.68)
        end
        hinge_cylinder!(hinge.entities, 'Pin cap', local_uvw(u,barrel_v,w+1.75,unit,n), Z_AXIS, 0.24, 0.06)
      end
    end

    def self.hinge_plate!(ents, name, u0, u1, v0, v1, w, unit, n)
      part = ents.add_group
      part.name = name
      le = part.entities
      r = 0.125
      pts = [[v0+r,w-1.75+r,Math::PI], [v1-r,w-1.75+r,1.5*Math::PI],
             [v1-r,w+1.75-r,0], [v0+r,w+1.75-r,0.5*Math::PI]].flat_map do |v,z,a|
        7.times.map do |i|
          q = a+i*Math::PI/12.0
          [u0*100, (v+r*Math.cos(q))*100, (z+r*Math.sin(q))*100]
        end
      end
      face = le.add_face(pts)
      face.reverse! if face.normal.x < 0
      face.pushpull((u1-u0)*100)
      axes = Geom::Transformation.axes(ORIGIN, unit, n, Z_AXIS)
      le.transform_entities(axes * Geom::Transformation.scaling(0.01), le.to_a)
      soften_rounds!(le, 25.degrees)
      part
    end

    def self.hinge_cylinder!(ents, name, point, axis, radius, length, slot_axis: nil)
      part = ents.add_group
      part.name = name
      le = part.entities
      center = Geom::Point3d.new(*point.to_a.map { |v| v*100 })
      edges = le.add_circle(center, axis, radius*100, 32)
      face = le.add_face(edges)
      face.reverse! if face.normal.dot(axis) < 0
      face.pushpull(length*100)
      if slot_axis
        cap = point.offset(axis, length)
        cross = [[-0.017,-0.070],[0.017,-0.070],[0.017,-0.017],[0.070,-0.017],
                 [0.070,0.017],[0.017,0.017],[0.017,0.070],[-0.017,0.070],
                 [-0.017,0.017],[-0.070,0.017],[-0.070,-0.017],[-0.017,-0.017]]
        cut = le.add_face(cross.map do |v,w|
          cap.offset(slot_axis,v).offset(Z_AXIS,w).to_a.map { |x| x*100 }
        end)
        cut.reverse! if cut.normal.dot(axis) < 0
        cut.pushpull(-1.2)
      end
      le.transform_entities(Geom::Transformation.scaling(0.01), le.to_a)
      soften_rounds!(le, 25.degrees)
      part
    end

    # Carve one recessed panel on BOTH faces of the slab.
    def self.carve_panel_both_faces!(le, rect, vf, vb, unit, n, raised: false)
      [[vf, vb], [vb, vf]].each do |v_face, v_other|
        outward = (v_face - v_other) <=> 0   # +1 or -1 along n
        carve_panel_one_face!(le, rect, v_face, outward, unit, n, raised: raised)
      end
    end

    def self.carve_panel_one_face!(le, rect, v_face, outward, unit, n, raised: false)
      pts = panel_outline(rect, v_face, unit, n)
      return if pts.length < 3
      face = le.add_face(pts)
      return unless face&.valid?
      d = face.normal.dot(n) * outward > 0 ? -PANEL_RECESS : PANEL_RECESS
      face.pushpull(d)

      return unless raised
      add_raised_field!(le, rect, v_face, outward, unit, n)
    end

    # Traditional raised panel: a sloped-shoulder field sitting inside the recess.
    # Bottom loop rests on the recess floor (inset by PANEL_GAP); the top loop is
    # inset further by SHOULDER_W and rises to just below the slab face, giving the
    # bevelled ovolo look. Loops share the same point count, sides built as triangles
    # (arch segments make quads non-planar).
    def self.add_raised_field!(le, rect, v_face, outward, unit, n)
      g1 = PANEL_GAP
      g2 = PANEL_GAP + SHOULDER_W
      lo = inset_rect(rect, g1)
      hi = inset_rect(rect, g2)
      return unless lo && hi

      v_lo = v_face - outward * PANEL_RECESS
      v_hi = v_face - outward * RAISE_TOP_GAP
      pts_lo = panel_outline(lo, v_lo, unit, n)
      pts_hi = panel_outline(hi, v_hi, unit, n)
      return if pts_lo.length != pts_hi.length || pts_lo.length < 3

      k = pts_lo.length
      seconds = []
      k.times do |i|
        j = (i + 1) % k
        f1 = add_tri(le, pts_lo[i], pts_lo[j], pts_hi[j])
        f2 = add_tri(le, pts_lo[i], pts_hi[j], pts_hi[i])
        smooth_edge_between(f1, pts_lo[i], pts_hi[j])
        seconds[i] = f2
      end
      # Smooth seams between adjacent segments where the outline barely turns
      # (i.e. along the arch curve) so the shoulder reads as one smooth surface.
      # The seam edge at point j (lo[j]-hi[j]) lies on segment j's second tri.
      k.times do |j|
        i = (j - 1) % k
        v1 = pts_lo[i].vector_to(pts_lo[j])
        v2 = pts_lo[j].vector_to(pts_lo[(j + 1) % k])
        next unless v1.valid? && v2.valid?
        next if v1.angle_between(v2) > 25.degrees
        smooth_edge_between(seconds[j], pts_lo[j], pts_hi[j])
      end
      cap = le.add_face(pts_hi)
      cap = nil unless cap&.valid?
      cap
    end

    # Soften the internal diagonal shared by the two triangles of one segment.
    def self.smooth_edge_between(face, pa, pb)
      return unless face&.valid?
      e = face.edges.find do |ed|
        s, t = ed.start.position, ed.end.position
        (s.distance(pa) < 0.01 && t.distance(pb) < 0.01) ||
          (s.distance(pb) < 0.01 && t.distance(pa) < 0.01)
      end
      return unless e
      e.soft = true
      e.smooth = true
    end

    def self.inset_rect(rect, d)
      r = { u0: rect[:u0] + d, u1: rect[:u1] - d,
            w0: rect[:w0] + d, w1: rect[:w1] - d, arch: rect[:arch] }
      return nil if r[:u1] - r[:u0] < 1.0 || r[:w1] - r[:w0] < 1.0
      r
    end

    def self.add_tri(le, a, b, c)
      return if a.distance(b) < 0.01 || b.distance(c) < 0.01 || a.distance(c) < 0.01
      le.add_face(a, b, c)
    rescue StandardError
      nil
    end

    # Outline points for a panel rect, with optional arched top edge
    # (:round = semicircle capped at panel width, :eyebrow = shallow arc).
    def self.panel_outline(rect, v, unit, n)
      u0, u1, w0, w1 = rect[:u0], rect[:u1], rect[:w0], rect[:w1]
      arch = rect[:arch]
      return rect_pts(u0, u1, w0, w1, v, unit, n) unless arch

      half = (u1 - u0) / 2.0
      rise = arch == :round ? half : (w1 - w0) * 0.18
      rise = [rise, w1 - w0 - 1.0].min
      return rect_pts(u0, u1, w0, w1, v, unit, n) if rise < 0.5

      cx = (u0 + u1) / 2.0
      w_spring = w1 - rise   # arc springs from this height
      # circle through (u0,w_spring),(u1,w_spring) with apex (cx,w1)
      r = (half**2 + rise**2) / (2.0 * rise)
      wc = w1 - r
      a0 = Math.atan2(w_spring - wc, u0 - cx)
      a1 = Math.atan2(w_spring - wc, u1 - cx)

      pts = []
      pts << local_uvw(u0, v, w0, unit, n)
      pts << local_uvw(u0, v, w_spring, unit, n)
      1.upto(ARCH_SEGMENTS - 1) do |i|
        t = a0 + (a1 - a0) * i / ARCH_SEGMENTS.to_f
        pts << local_uvw(cx + r * Math.cos(t), v, wc + r * Math.sin(t), unit, n)
      end
      pts << local_uvw(u1, v, w_spring, unit, n)
      pts << local_uvw(u1, v, w0, unit, n)
      pts
    end

    def self.rect_pts(u0, u1, w0, w1, v, unit, n)
      [
        local_uvw(u0, v, w0, unit, n),
        local_uvw(u1, v, w0, unit, n),
        local_uvw(u1, v, w1, unit, n),
        local_uvw(u0, v, w1, unit, n)
      ]
    end

    # 1 Lite: frame ring + glass plane at mid-depth (same approach as door_tool build_leaf).
    def self.build_lite_leaf!(le, spec, u0, u1, w0, w1, vf, vb, unit, n, glass_mat)
      f = FRAMES[spec[:frame]]
      hu0 = u0 + f[:stile]
      hu1 = u1 - f[:stile]
      hw0 = w0 + f[:bottom]
      hw1 = w1 - f[:top]
      return build_slab!(le, u0, u1, w0, w1, vf, vb, unit, n) if hu1 - hu0 < 2.0 || hw1 - hw0 < 2.0

      if REALISTIC_DETAILS
        return false unless build_rounded_slab!(le, u0, u1, w0, w1, vf, vb, unit, n)
        hole = le.add_face(rect_pts(hu0, hu1, hw0, hw1, vf, unit, n))
        return false unless hole&.valid?
        depth = vb-vf
        depth = -depth if hole.normal.dot(n) < 0
        hole.pushpull(depth)
      else
        outer = rect_pts(u0, u1, w0, w1, vf, unit, n)
        face = le.add_face(outer)
        return false unless face&.valid?
        hole = le.add_face(rect_pts(hu0, hu1, hw0, hw1, vf, unit, n))
        hole.erase! if hole&.valid?
        depth = vb - vf
        depth = -depth if face.normal.dot(n) < 0
        face.pushpull(depth)
      end

      vmid = (vf + vb) / 2.0
      gface = le.add_face(rect_pts(hu0, hu1, hw0, hw1, vmid, unit, n))
      if gface&.valid?
        gface.material = glass_mat
        gface.back_material = glass_mat
      end
      true
    end

    def self.get_or_create_material(model, name, rgb, alpha)
      mat = model.materials[name]
      return mat if mat
      mat = model.materials.add(name)
      mat.color = Sketchup::Color.new(*rgb)
      mat.alpha = alpha
      mat
    end

  end
end

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
       PANEL_GAP SHOULDER_W RAISE_TOP_GAP].each do |c|
      remove_const(c) if const_defined?(c, false)
    end

    LEAF_THICKNESS = 1.375
    PANEL_RECESS   = 0.25   # recess depth per face
    RAISE_BACK     = 0.15   # (legacy, unused by raised styles - see frustum insert)
    ARCH_SEGMENTS  = 24
    PANEL_GAP      = 0.25   # visible groove between recess edge and raised field
    SHOULDER_W     = 0.75   # sloped shoulder width of the raised field
    RAISE_TOP_GAP  = 0.05   # raised field top sits this far below the slab face

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
      '2 Panel Shaker'   => { kind: :stacked, frame: 'shaker', rows: 2, mid_key: :lock },
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
        ok = build_slab!(le, u0, u1, w0, w1, vf, vb, unit, n)
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

      outer = rect_pts(u0, u1, w0, w1, vf, unit, n)
      face = le.add_face(outer)
      return false unless face&.valid?
      hole = le.add_face(rect_pts(hu0, hu1, hw0, hw1, vf, unit, n))
      hole.erase! if hole&.valid?
      depth = vb - vf
      depth = -depth if face.normal.dot(n) < 0
      face.pushpull(depth)

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

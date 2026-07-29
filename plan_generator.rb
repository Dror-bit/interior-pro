# Interior Pro - 2D Plan Generator
# Step 1 (2026-07-27): wall poche + opening gaps + "2D Plan" scene.
# Step 2 (2026-07-27): door/window plan symbols + D#/W# marks.
#
# 2D contract: reads ONLY InteriorPro attributes (never geometry) and
# regenerates a flat symbol layer from scratch on every build!.
# All plan geometry lives in one top-level group (type='plan2d') on tag IP/2D.

module InteriorPro
  module PlanGenerator
    PLAN_TAG   = 'IP/2D' unless const_defined?(:PLAN_TAG, false)
    PLAN_Z     = 0.5 unless const_defined?(:PLAN_Z, false)
    SCENE_NAME = '2D Plan' unless const_defined?(:SCENE_NAME, false)
    MARK_R     = 8.0 unless const_defined?(:MARK_R, false)
    MARK_TEXT_H = 4.2 unless const_defined?(:MARK_TEXT_H, false)

    class << self
      # Rebuild the whole 2D plan layer from attributes.
      def build!
        model = Sketchup.active_model
        model.start_operation('2D Plan', true)
        remove_plan_groups(model)

        grp = model.entities.add_group
        grp.name = 'InteriorPro 2D Plan'
        grp.set_attribute('InteriorPro', 'type', 'plan2d')

        doors, windows = hosted_bodies(model)
        assign_marks!(doors, 'D')
        assign_marks!(windows, 'W')

        count = 0
        walls(model).each do |wall|
          d = wall_attrs(wall)
          next unless d
          next unless draw_wall_plan(grp.entities, d)
          count += 1
          begin
            draw_door_symbols(grp.entities, d, doors.select { |b| b[:host] == d[:id] })
            draw_window_symbols(grp.entities, d, windows.select { |b| b[:host] == d[:id] })
            draw_wall_dim(grp.entities, d) if d[:category] != 'interior'
          rescue StandardError => e
            puts "[Plan2D] symbols on wall #{d[:id]}: #{e.message}"
          end
        end

        begin
          draw_room_labels(grp.entities, model)
        rescue StandardError => e
          puts "[Plan2D] room labels: #{e.message}"
        end

        if count.zero?
          grp.erase! if grp.valid?
          model.commit_operation
          UI.messagebox('No walls found - draw walls first')
          return false
        end

        InteriorPro.assign_tag(grp, PLAN_TAG)
        setup_scene(model, grp)
        model.commit_operation
        puts "[Plan2D] built plan: #{count} wall(s), #{doors.length} door(s), #{windows.length} window(s)"
        true
      rescue StandardError => e
        begin; model.abort_operation; rescue StandardError; end
        puts "[Plan2D] build!: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        false
      end

      def remove_all!
        model = Sketchup.active_model
        model.start_operation('Remove 2D Plan', true)
        n = remove_plan_groups(model)
        model.commit_operation
        puts "[Plan2D] removed #{n} plan group(s)"
        n
      end

      private

      # ---- model queries ---------------------------------------------------

      def walls(model)
        model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end

      def remove_plan_groups(model)
        doomed = model.entities.grep(Sketchup::Group).select do |g|
          g.get_attribute('InteriorPro', 'type') == 'plan2d'
        end
        doomed.each { |g| g.erase! if g.valid? }
        doomed.length
      end

      # Door/window bodies with plan-relevant attributes.
      def hosted_bodies(model)
        doors = []
        windows = []
        model.entities.to_a.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next unless e.valid?
          tp = e.get_attribute('InteriorPro', 'type')
          next unless tp == 'door' || tp == 'window'
          info = {
            entity:  e,
            host:    e.get_attribute('InteriorPro', 'host_wall_id'),
            t:       e.get_attribute('InteriorPro', 'position_along_wall_in'),
            width:   e.get_attribute('InteriorPro', 'width_in').to_f,
            mark:    e.get_attribute('InteriorPro', 'mark').to_s,
            clicked: (e.get_attribute('InteriorPro', 'clicked_side') || 1).to_i
          }
          info[:t] = info[:t].to_f unless info[:t].nil?
          if tp == 'door'
            info[:door_type] = (e.get_attribute('InteriorPro', 'door_type') || 'Single').to_s
            info[:category]  = (e.get_attribute('InteriorPro', 'door_category') || 'interior').to_s
            info[:swing]     = (e.get_attribute('InteriorPro', 'swing_direction') || 'left').to_s
            info[:front_config] = (e.get_attribute('InteriorPro', 'front_config') || 'single').to_s
            info[:leaf_count]   = (e.get_attribute('InteriorPro', 'closet_leaf_count') || 2).to_i
            doors << info
          else
            info[:wtype] = (e.get_attribute('InteriorPro', 'window_type') || '').to_s
            windows << info
          end
        end
        [doors, windows]
      end

      # Keep existing marks; number the rest D1../W1.. after the max in use.
      def assign_marks!(list, prefix)
        used = list.map { |b| b[:mark][/^#{prefix}(\d+)$/, 1] }.compact.map(&:to_i)
        nxt = (used.max || 0) + 1
        list.sort_by { |b| [b[:host].to_s, b[:t].to_f] }.each do |b|
          next unless b[:mark].empty?
          b[:mark] = "#{prefix}#{nxt}"
          begin
            b[:entity].set_attribute('InteriorPro', 'mark', b[:mark])
          rescue StandardError
          end
          nxt += 1
        end
      end

      # ---- wall poche ------------------------------------------------------

      def wall_attrs(wall)
        sx = wall.get_attribute('InteriorPro', 'start_x')
        return nil if sx.nil?
        th = wall.get_attribute('InteriorPro', 'thickness').to_f
        return nil if th <= 0.0

        anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-left').to_s
        h_anchor = anchor == 'center' ? 'center' : (anchor.split('-')[1] || 'left')
        corners = wall.get_attribute('InteriorPro', 'corners_xy')
        corners = nil unless corners.is_a?(Array) && corners.length == 8

        s = Geom::Point3d.new(sx.to_f, wall.get_attribute('InteriorPro', 'start_y').to_f, 0)
        e = Geom::Point3d.new(wall.get_attribute('InteriorPro', 'end_x').to_f,
                              wall.get_attribute('InteriorPro', 'end_y').to_f, 0)
        u = e - s
        len = u.length.to_f
        return nil if len < 0.5
        u.normalize!

        d = {
          id:        wall.get_attribute('InteriorPro', 'id'),
          xform:     wall.transformation,
          s: s, e: e, u: u,
          n:         Geom::Vector3d.new(-u.y, u.x, 0),   # LEFT perpendicular
          len:       len,
          thickness: th,
          h_anchor:  h_anchor,
          corners:   corners,
          category:  (wall.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s,
          openings:  InteriorPro::WallTool.read_door_openings(wall)
        }
        d[:off_pos], d[:off_neg] = band_offsets(h_anchor, th)
        d
      rescue StandardError
        nil
      end

      # Band extents along the LEFT perpendicular of the drawn start->end
      # direction. Must match WallTool#perpendicular_corners_xy.
      def band_offsets(h_anchor, thickness)
        case h_anchor
        when 'left'  then [thickness, 0.0]
        when 'right' then [0.0, -thickness]
        else [thickness / 2.0, -thickness / 2.0]
        end
      end

      # One wall -> solid poche segments between the openings.
      def draw_wall_plan(ents, d)
        cuts = d[:openings]
               .map { |o| [o[:t] - o[:width] / 2.0, o[:t] + o[:width] / 2.0] }
               .map { |a, b| [[a, 0.0].max, [b, d[:len]].min] }
               .select { |a, b| (b - a) > 0.1 }
               .sort_by(&:first)

        segs = []
        pos = 0.0
        cuts.each do |a, b|
          segs << [pos, a] if (a - pos) > 0.05
          pos = b if b > pos
        end
        segs << [pos, d[:len]] if (d[:len] - pos) > 0.05
        segs = [[0.0, d[:len]]] if segs.empty?

        mat = plan_material(d[:category])
        segs.each do |a, b|
          pts = seg_points(d, a, b, a <= 0.05, b >= d[:len] - 0.05)
          world = pts.map { |p| flat_world(p, d[:xform]) }
          face = begin
            ents.add_face(world)
          rescue StandardError
            nil
          end
          next unless face
          face.material = mat
          face.back_material = mat
        end
        true
      end

      def seg_points(d, a, b, at_start, at_end)
        c = d[:corners]
        s_pos = s_neg = e_pos = e_neg = nil
        if at_start && c
          s_pos = Geom::Point3d.new(c[0], c[1], 0)
          s_neg = Geom::Point3d.new(c[6], c[7], 0)
        end
        if at_end && c
          e_pos = Geom::Point3d.new(c[2], c[3], 0)
          e_neg = Geom::Point3d.new(c[4], c[5], 0)
        end
        s_pos ||= lpt(d, a, d[:off_pos])
        s_neg ||= lpt(d, a, d[:off_neg])
        e_pos ||= lpt(d, b, d[:off_pos])
        e_neg ||= lpt(d, b, d[:off_neg])
        [s_pos, e_pos, e_neg, s_neg]
      end

      # Local frame point: distance along the drawn line + offset on LEFT perp.
      def lpt(d, along, off)
        d[:s].offset(d[:u], along).offset(d[:n], off)
      end

      def flat_world(pt, xform)
        w = pt.transform(xform)
        Geom::Point3d.new(w.x, w.y, PLAN_Z)
      end

      def add_poly(ents, d, local_pts, closed: false)
        world = local_pts.map { |p| flat_world(p, d[:xform]) }
        world << world.first if closed
        ents.add_edges(world)
      rescue StandardError
        nil
      end

      def add_dashed(ents, d, p1, p2, dash = 5.0, gap = 3.0)
        v = p2 - p1
        len = v.length
        return if len < 0.5
        v.normalize!
        pos = 0.0
        while pos < len
          seg_end = [pos + dash, len].min
          add_poly(ents, d, [p1.offset(v, pos), p1.offset(v, seg_end)])
          pos += dash + gap
        end
      end

      # ---- door symbols ----------------------------------------------------

      # Match a hosted body to its wall opening (exact x1/x2 from the wall data).
      def opening_span(d, body)
        t = body[:t]
        return nil if t.nil?
        op = d[:openings].min_by { |o| (o[:t] - t).abs }
        if op && (op[:t] - t).abs <= (op[:width] / 2.0 + 2.0)
          [op[:t] - op[:width] / 2.0, op[:t] + op[:width] / 2.0]
        elsif body[:width] > 1.0
          [t - body[:width] / 2.0, t + body[:width] / 2.0]
        end
      end

      # PLAN SWING CALIBRATION POINT:
      # clicked_side multiplies the RIGHT perpendicular (DoorManager convention);
      # our n is the LEFT perpendicular, so the clicked face sits at -clicked*n.
      # Assumption (to verify visually): the leaf swings toward the clicked face.
      def swing_sign(body)
        body[:clicked] >= 0 ? -1 : 1
      end

      def door_kind(body)
        t = body[:door_type]
        return :garage  if t == 'Garage Door'
        return :folding if t.include?('Folding')
        return :sliding if t.include?('Sliding') || t == 'Closet'
        return :pocket  if t == 'Pocket'
        dbl = t == 'Double' || t == 'French Hinged' || t == '4-Panel Center Hinged'
        dbl ||= (t == 'Front Door' || t == 'Arched') && body[:front_config] == 'double'
        dbl ? :double : :single
      end

      def draw_door_symbols(ents, d, bodies)
        bodies.each do |b|
          span = opening_span(d, b)
          next unless span
          x1, x2 = span
          kind = door_kind(b)
          case kind
          when :garage  then sym_garage(ents, d, x1, x2)
          when :sliding, :folding, :pocket
            draw_opening_jambs(ents, d, x1, x2)
            draw_header_dashes(ents, d, x1, x2)
            case kind
            when :sliding then sym_sliding(ents, d, x1, x2)
            when :folding then sym_folding(ents, d, b, x1, x2)
            else               sym_pocket(ents, d, b, x1, x2)
            end
          when :double  then sym_double_swing(ents, d, b, x1, x2)
          else               sym_single_swing(ents, d, b, x1, x2)
          end
          mark_badge(ents, d, b[:mark], (x1 + x2) / 2.0, d[:off_neg] - 13.0, :circle)
        end
      end

      JAMB_W = 1.5 unless const_defined?(:JAMB_W, false)

      # Jamb blocks flush with the wall faces (no protrusion, per user).
      def draw_opening_jambs(ents, d, x1, x2)
        [[x1, x1 + JAMB_W], [x2 - JAMB_W, x2]].each do |a, bx|
          rect(ents, d, a, bx, d[:off_neg], d[:off_pos])
        end
      end

      # Dashed header lines across the opening at both wall faces.
      def draw_header_dashes(ents, d, x1, x2)
        add_dashed(ents, d, lpt(d, x1 + JAMB_W, d[:off_pos] - 0.4),
                   lpt(d, x2 - JAMB_W, d[:off_pos] - 0.4), 4.0, 2.5)
        add_dashed(ents, d, lpt(d, x1 + JAMB_W, d[:off_neg] + 0.4),
                   lpt(d, x2 - JAMB_W, d[:off_neg] + 0.4), 4.0, 2.5)
      end

      # Leaf drawn as a thin double-line rectangle + handle knobs + thin arc.
      def draw_swing_leaf(ents, d, hinge_x, latch_x, edge, ss)
        leaf_len = (latch_x - hinge_x).abs
        return if leaf_len < 4.0
        dir = latch_x > hinge_x ? 1.0 : -1.0
        ua = [hinge_x, hinge_x + dir * 1.5].min
        ub = [hinge_x, hinge_x + dir * 1.5].max
        rect(ents, d, ua, ub, edge, edge + ss * leaf_len)
        # handle knobs near the free end, both sides of the leaf
        ko = edge + ss * (leaf_len - 4.0)
        [hinge_x - dir * 1.0, hinge_x + dir * 2.5].each do |kx|
          rect(ents, d, kx - 0.6, kx + 0.6, ko - 0.6, ko + 0.6)
        end
        hinge = lpt(d, hinge_x, edge)
        latch = lpt(d, latch_x, edge)
        leaf_end = hinge.offset(d[:n], ss * leaf_len)
        add_arc(ents, d, hinge, latch, leaf_end)
      end

      def sym_single_swing(ents, d, b, x1, x2)
        ss = swing_sign(b)
        edge = ss > 0 ? d[:off_pos] : d[:off_neg]
        draw_opening_jambs(ents, d, x1, x2)
        draw_header_dashes(ents, d, x1, x2)
        if b[:swing] == 'right'
          draw_swing_leaf(ents, d, x2 - JAMB_W, x1 + JAMB_W, edge, ss)
        else
          draw_swing_leaf(ents, d, x1 + JAMB_W, x2 - JAMB_W, edge, ss)
        end
      end

      def sym_double_swing(ents, d, b, x1, x2)
        ss = swing_sign(b)
        edge = ss > 0 ? d[:off_pos] : d[:off_neg]
        draw_opening_jambs(ents, d, x1, x2)
        draw_header_dashes(ents, d, x1, x2)
        xm = (x1 + x2) / 2.0
        draw_swing_leaf(ents, d, x1 + JAMB_W, xm, edge, ss)
        draw_swing_leaf(ents, d, x2 - JAMB_W, xm, edge, ss)
      end

      # Arc polyline from from_pt to to_pt around hinge (actual angle between them).
      def add_arc(ents, d, hinge, from_pt, to_pt)
        v0 = from_pt - hinge
        v1 = to_pt - hinge
        return if v0.length < 1.0
        sweep = Math.atan2(v0.x * v1.y - v0.y * v1.x, v0.x * v1.x + v0.y * v1.y)
        steps = 14
        pts = (0..steps).map do |i|
          a = sweep * i / steps
          ca = Math.cos(a); sa = Math.sin(a)
          Geom::Point3d.new(hinge.x + v0.x * ca - v0.y * sa,
                            hinge.y + v0.x * sa + v0.y * ca, 0)
        end
        add_poly(ents, d, pts)
      end

      def sym_sliding(ents, d, x1, x2)
        xm = (x1 + x2) / 2.0
        cmid = (d[:off_pos] + d[:off_neg]) / 2.0
        panel = 1.2
        rect(ents, d, x1 + 0.5, xm + 1.5, cmid + 0.3, cmid + 0.3 + panel)
        rect(ents, d, xm - 1.5, x2 - 0.5, cmid - 0.3 - panel, cmid - 0.3)
      end

      def sym_folding(ents, d, b, x1, x2)
        w = x2 - x1
        panels = b[:door_type][/^(\d)-Panel/, 1]
        panels = panels ? panels.to_i : [b[:leaf_count], 2].max
        panels = 2 if panels < 2
        ss = swing_sign(b)
        edge = ss > 0 ? d[:off_pos] : d[:off_neg]
        amp = w / panels
        pts = (0..panels).map do |i|
          off = i.odd? ? ss * amp : 0.0
          lpt(d, x1 + w * i / panels, edge).offset(d[:n], off)
        end
        add_poly(ents, d, pts)
      end

      def sym_pocket(ents, d, b, x1, x2)
        xm = (x1 + x2) / 2.0
        cmid = (d[:off_pos] + d[:off_neg]) / 2.0
        if b[:swing] == 'right'
          rect(ents, d, xm, x2, cmid - 0.6, cmid + 0.6)
          add_dashed(ents, d, lpt(d, x1, cmid), lpt(d, xm, cmid))
        else
          rect(ents, d, x1, xm, cmid - 0.6, cmid + 0.6)
          add_dashed(ents, d, lpt(d, xm, cmid), lpt(d, x2, cmid))
        end
      end

      # Heavy line on the exterior face (right perpendicular = -n side)
      # + dashed track line toward the interior.
      def sym_garage(ents, d, x1, x2)
        rect(ents, d, x1, x2, d[:off_neg] + 0.2, d[:off_neg] + 1.2, fill: true)
        add_dashed(ents, d, lpt(d, x1, d[:off_pos] + 3.0), lpt(d, x2, d[:off_pos] + 3.0))
      end

      def rect(ents, d, xa, xb, oa, ob, fill: false)
        pts = [lpt(d, xa, oa), lpt(d, xb, oa), lpt(d, xb, ob), lpt(d, xa, ob)]
        if fill
          world = pts.map { |p| flat_world(p, d[:xform]) }
          f = begin
            ents.add_face(world)
          rescue StandardError
            nil
          end
          if f
            m = get_plan_mat('InteriorPro_Plan_Line', [0, 0, 0])
            f.material = m
            f.back_material = m
          end
        else
          add_poly(ents, d, pts, closed: true)
        end
      end

      # ---- window symbols --------------------------------------------------

      def draw_window_symbols(ents, d, bodies)
        bodies.each do |b|
          span = opening_span(d, b)
          next unless span
          x1, x2 = span
          draw_opening_jambs(ents, d, x1, x2)
          fx1 = x1 + JAMB_W
          fx2 = x2 - JAMB_W
          rect(ents, d, fx1, fx2, d[:off_neg], d[:off_pos])
          draw_window_unit(ents, d, b[:wtype].to_s, fx1, fx2)
          mark_badge(ents, d, b[:mark], (x1 + x2) / 2.0, d[:off_pos] + 13.0, :hex)
        end
      end

      # Per-type plan symbol (approved 2026-07-29). Exterior = off_neg side
      # (right perpendicular). No glass center lines (per user).
      def draw_window_unit(ents, d, wtype, fx1, fx2)
        q = d[:off_neg]
        p = d[:off_pos]
        th = p - q
        e1 = q + th * 0.15
        e2 = q + th * 0.45
        i1 = p - th * 0.45
        i2 = p - th * 0.15
        len = fx2 - fx1
        blk = lambda { |cx| rect(ents, d, cx - 1.0, cx + 1.0, q + 1.0, p - 1.0) }
        case wtype
        when /Casement XX/
          draw_casement_leaf(ents, d, fx1, fx1 + len / 2.0, q)
          draw_casement_leaf(ents, d, fx2, fx2 - len / 2.0, q)
        when /Casement/
          draw_casement_leaf(ents, d, fx1, fx2, q)
        when /XOX/
          # Minimal slider style (user sketch 2026-07-29): inner frame,
          # dividers at the thirds, each panel = a single line at its depth.
          # Center fixed (exterior depth), sides sliding (interior depth).
          cm = (p + q) / 2.0
          w3 = len / 3.0
          d1 = fx1 + w3
          d2 = fx2 - w3
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7)
          rect(ents, d, d1 - 1.0, d1 + 1.0, q + 0.7, p - 0.7)
          rect(ents, d, d2 - 1.0, d2 + 1.0, q + 0.7, p - 0.7)
          add_poly(ents, d, [lpt(d, d1 + 1.0, cm - th * 0.11), lpt(d, d2 - 1.0, cm - th * 0.11)])
          add_poly(ents, d, [lpt(d, fx1 + 0.5, cm + th * 0.11), lpt(d, d1 - 1.0, cm + th * 0.11)])
          add_poly(ents, d, [lpt(d, d2 + 1.0, cm + th * 0.11), lpt(d, fx2 - 0.5, cm + th * 0.11)])
        when /Slider|XO/
          cm = (p + q) / 2.0
          xm = (fx1 + fx2) / 2.0
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7)
          rect(ents, d, xm - 1.0, xm + 1.0, q + 0.7, p - 0.7)
          add_poly(ents, d, [lpt(d, fx1 + 0.5, cm + th * 0.11), lpt(d, xm - 1.0, cm + th * 0.11)])
          add_poly(ents, d, [lpt(d, xm + 1.0, cm - th * 0.11), lpt(d, fx2 - 0.5, cm - th * 0.11)])
        when /Hung/
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, e1, e2)
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, i1, i2)
        when /Garden/
          gd = 12.0
          rect(ents, d, fx1 + 1.0, fx2 - 1.0, q - gd, q)
          rect(ents, d, fx1 + 2.0, fx2 - 2.0, q - gd + 1.0, q - 1.0)
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, i1, i2)
        when /Arched/
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7)
          draw_arch_hint(ents, d, fx1, fx2, q, p)
        else
          rect(ents, d, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7)
        end
      end

      # Casement leaf pivoted ~20deg toward the exterior + thin arc.
      def draw_casement_leaf(ents, d, hx, lx, q)
        len = (lx - hx).abs
        return if len < 4.0
        dir = lx > hx ? 1.0 : -1.0
        ang = 20.0 * Math::PI / 180.0
        u = d[:u]
        n = d[:n]
        lu = Geom::Vector3d.new(u.x * dir * Math.cos(ang) - n.x * Math.sin(ang),
                                u.y * dir * Math.cos(ang) - n.y * Math.sin(ang), 0)
        pd = Geom::Vector3d.new(n.x * Math.cos(ang) + u.x * dir * Math.sin(ang),
                                n.y * Math.cos(ang) + u.y * dir * Math.sin(ang), 0)
        h = lpt(d, hx, q)
        tip = h.offset(lu, len)
        add_poly(ents, d, [h, tip, tip.offset(pd, 2.0), h.offset(pd, 2.0)], closed: true)
        add_arc(ents, d, h, lpt(d, lx, q), tip)
      end

      # Dashed arc hint inside the band for Arched windows.
      def draw_arch_hint(ents, d, fx1, fx2, q, p)
        steps = 24
        pts = (0..steps).map do |i|
          t = i.to_f / steps
          lpt(d, fx1 + (fx2 - fx1) * t, p - 1.0 - (p - q - 2.0) * Math.sin(Math::PI * t))
        end
        pts.each_cons(2).each_with_index do |(a, b2), i|
          add_poly(ents, d, [a, b2]) if i.even?
        end
      end

      # ---- dimensions ------------------------------------------------------

      DIM_OFF   = 10.0 unless const_defined?(:DIM_OFF, false)
      DIM_TEXT_H = 5.0 unless const_defined?(:DIM_TEXT_H, false)

      def fmt_feet(len)
        ft = (len / 12.0).floor
        inch = (len - ft * 12).round(1)
        if inch >= 12.0
          ft += 1
          inch = 0.0
        end
        inch_s = inch % 1 == 0 ? inch.to_i.to_s : inch.to_s
        ft.positive? ? "#{ft}'-#{inch_s}\"" : "#{inch_s}\""
      end

      # Dimension line along the exterior face: extension lines + 45deg ticks
      # + feet-inches text, offset DIM_OFF outside the wall.
      def draw_wall_dim(ents, d)
        return if d[:len] < 24.0
        off_face = d[:off_neg]              # exterior face (right perpendicular)
        off_dim  = off_face - DIM_OFF
        p1 = lpt(d, 0, off_dim)
        p2 = lpt(d, d[:len], off_dim)
        add_poly(ents, d, [p1, p2])
        add_poly(ents, d, [lpt(d, 0, off_face - 2.0), lpt(d, 0, off_dim - 2.0)])
        add_poly(ents, d, [lpt(d, d[:len], off_face - 2.0), lpt(d, d[:len], off_dim - 2.0)])
        diag = Geom::Vector3d.new(d[:u].x + d[:n].x, d[:u].y + d[:n].y, 0)
        diag.normalize!
        [p1, p2].each do |p|
          add_poly(ents, d, [p.offset(diag, -2.0), p.offset(diag, 2.0)])
        end
        uw = d[:u].transform(d[:xform])
        ang = Math.atan2(uw.y, uw.x)
        ang += Math::PI if ang > Math::PI / 2 + 0.01 || ang < -Math::PI / 2 - 0.01
        center = flat_world(lpt(d, d[:len] / 2.0, off_dim - 5.0), d[:xform])
        add_text(ents, fmt_feet(d[:len]), DIM_TEXT_H, center, ang)
      end

      # ---- room labels -----------------------------------------------------

      def draw_room_labels(ents, model)
        rooms = model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'room'
        end
        rooms.each do |r|
          flat = r.get_attribute('InteriorPro', 'boundary_xy')
          next unless flat.is_a?(Array) && flat.length >= 6
          xs = []
          ys = []
          flat.each_slice(2) { |x, y| xs << x.to_f; ys << y.to_f }
          cx = xs.sum / xs.length
          cy = ys.sum / ys.length
          name = (r.get_attribute('InteriorPro', 'name') || 'Room').to_s.upcase
          area = r.get_attribute('InteriorPro', 'area_sqft').to_f
          add_text(ents, name, 7.0, Geom::Point3d.new(cx, cy + 5.0, PLAN_Z), 0.0)
          add_text(ents, "#{area.round} SF", 4.5, Geom::Point3d.new(cx, cy - 7.0, PLAN_Z), 0.0)
        end
      end

      # Filled 3D-text group centered at a world point, rotated by ang (radians).
      def add_text(ents, str, h, center, ang = 0.0)
        label = ents.add_group
        label.entities.add_3d_text(str.to_s, TextAlignCenter, 'Arial', false, false,
                                   h, 0.0, 0.0, true, 0.0)
        b = label.bounds
        label.transform!(Geom::Transformation.rotation(b.center, Geom::Vector3d.new(0, 0, 1), ang)) if ang.abs > 0.001
        label.transform!(Geom::Transformation.translation(center - label.bounds.center))
        m = get_plan_mat('InteriorPro_Plan_Line', [0, 0, 0])
        label.entities.grep(Sketchup::Face).each { |f| f.material = m; f.back_material = m }
        label
      rescue StandardError => e
        label.erase! if label && label.valid?
        puts "[Plan2D] text '#{str}': #{e.message}"
        nil
      end

      # ---- marks -----------------------------------------------------------

      def mark_badge(ents, d, text, along, off, shape)
        return if text.to_s.empty?
        center = flat_world(lpt(d, along, off), d[:xform])
        segs = shape == :hex ? 6 : 24
        begin
          ents.add_circle(center, Geom::Vector3d.new(0, 0, 1), MARK_R, segs)
        rescue StandardError
        end
        add_text(ents, text, MARK_TEXT_H, center, 0.0)
      end

      # ---- materials / scene ----------------------------------------------

      def plan_material(category)
        if category == 'interior'
          get_plan_mat('InteriorPro_Plan_Interior', [205, 205, 205])
        else
          get_plan_mat('InteriorPro_Plan_Exterior', [64, 64, 64])
        end
      end

      def get_plan_mat(name, rgb)
        mats = Sketchup.active_model.materials
        mat = mats[name]
        return mat if mat
        mat = mats.add(name)
        mat.color = Sketchup::Color.new(*rgb)
        mat
      end

      def setup_scene(model, plan_grp)
        bounds = plan_grp.bounds
        center = bounds.center
        dist = [bounds.width, bounds.height].max * 1.2 + 120
        eye = Geom::Point3d.new(center.x, center.y, center.z + dist)
        camera = Sketchup::Camera.new(eye, center, Geom::Vector3d.new(0, 1, 0), false)
        model.active_view.camera = camera

        pages = model.pages
        page = pages[SCENE_NAME]
        if page
          page.update(PAGE_USE_CAMERA)
        else
          page = pages.add(SCENE_NAME)
        end

        begin
          page.use_hidden_layers = true if page.respond_to?(:use_hidden_layers=)
        rescue StandardError
        end

        model.layers.each do |layer|
          next unless layer.name.start_with?('IP/')
          begin
            page.set_visibility(layer, layer.name == PLAN_TAG)
          rescue StandardError
          end
        end
        page
      rescue StandardError => e
        puts "[Plan2D] setup_scene: #{e.message}"
        nil
      end
    end
  end
end

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
        assign_marks!(doors.select { |b| b[:category] != 'interior' }, 'D')
        assign_marks!(doors.select { |b| b[:category] == 'interior' }, 'IN')
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
          draw_dim_chains(grp.entities, model)
        rescue StandardError => e
          puts "[Plan2D] dimension chains: #{e.message}"
        end

        begin
          draw_room_labels(grp.entities, model)
        rescue StandardError => e
          puts "[Plan2D] room labels: #{e.message}"
        end

        begin
          draw_sketches(grp.entities, model)
        rescue StandardError => e
          puts "[Plan2D] sketch shapes: #{e.message}"
        end

        begin
          draw_schedules(grp.entities, model, doors, windows)
        rescue StandardError => e
          puts "[Plan2D] schedules: #{e.message}"
        end

        begin
          draw_legend_and_title(grp.entities, model)
        rescue StandardError => e
          puts "[Plan2D] legend: #{e.message}"
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
          info[:height] = e.get_attribute('InteriorPro', 'height_in').to_f
          if tp == 'door'
            info[:door_type] = (e.get_attribute('InteriorPro', 'door_type') || 'Single').to_s
            info[:category]  = (e.get_attribute('InteriorPro', 'door_category') || 'interior').to_s
            info[:swing]     = (e.get_attribute('InteriorPro', 'swing_direction') || 'left').to_s
            info[:front_config] = (e.get_attribute('InteriorPro', 'front_config') || 'single').to_s
            info[:leaf_count]   = (e.get_attribute('InteriorPro', 'closet_leaf_count') || 2).to_i
            doors << info
          else
            info[:wtype] = (e.get_attribute('InteriorPro', 'window_type') || '').to_s
            info[:header] = e.get_attribute('InteriorPro', 'header_height_in').to_f
            windows << info
          end
        end
        [doors, windows]
      end

      # Target-set mark convention (TARGET_PLANS section 2): W<level><nn> /
      # D<level><nn> / IN<level><nn>. Level is 1 for now. Marks already in the
      # convention are kept; anything else (empty or legacy D1/W1) is renumbered.
      def assign_marks!(list, prefix)
        pat = /^#{prefix}1(\d{2})$/
        used = list.map { |b| b[:mark][pat, 1] }.compact.map(&:to_i)
        nxt = (used.max || 0) + 1
        list.sort_by { |b| [b[:host].to_s, b[:t].to_f] }.each do |b|
          next if b[:mark] =~ pat
          b[:mark] = format('%s1%02d', prefix, nxt)
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
        return :opening if t == 'Cased Opening'
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
          when :opening then draw_opening_jambs(ents, d, x1, x2)   # doorway, no door
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
        fx1 = x1 + JAMB_W
        fx2 = x2 - JAMB_W
        xm = (fx1 + fx2) / 2.0
        cmid = (d[:off_pos] + d[:off_neg]) / 2.0
        panel = 1.2
        rect(ents, d, fx1 + 0.5, xm + 1.5, cmid + 0.3, cmid + 0.3 + panel)
        rect(ents, d, xm - 1.5, fx2 - 0.5, cmid - 0.3 - panel, cmid - 0.3)
      end

      # Bi-fold: zigzag of THIN PANELS (1.5" thick rectangles), not bare lines.
      def sym_folding(ents, d, b, x1, x2)
        fx1 = x1 + JAMB_W
        fx2 = x2 - JAMB_W
        w = fx2 - fx1
        return if w < 6.0
        panels = b[:door_type][/^(\d)-Panel/, 1]
        panels = panels ? panels.to_i : [b[:leaf_count], 2].max
        panels = 2 if panels < 2
        ss = swing_sign(b)
        edge = ss > 0 ? d[:off_pos] : d[:off_neg]
        amp = w / panels
        verts = (0..panels).map do |i|
          lpt(d, fx1 + w * i / panels.to_f, i.odd? ? edge + ss * amp : edge)
        end
        verts.each_cons(2) do |a, b2|
          leg = b2 - a
          next if leg.length < 1.0
          leg.normalize!
          perp = Geom::Vector3d.new(-leg.y, leg.x, 0)
          add_poly(ents, d, [a, b2, b2.offset(perp, 1.5), a.offset(perp, 1.5)], closed: true)
        end
      end

      def sym_pocket(ents, d, b, x1, x2)
        fx1 = x1 + JAMB_W
        fx2 = x2 - JAMB_W
        xm = (fx1 + fx2) / 2.0
        cmid = (d[:off_pos] + d[:off_neg]) / 2.0
        if b[:swing] == 'right'
          rect(ents, d, xm, fx2, cmid - 0.6, cmid + 0.6)
          add_dashed(ents, d, lpt(d, fx1, cmid), lpt(d, xm, cmid))
        else
          rect(ents, d, fx1, xm, cmid - 0.6, cmid + 0.6)
          add_dashed(ents, d, lpt(d, xm, cmid), lpt(d, fx2, cmid))
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

      # Dimension strings along the exterior face (target-set style):
      # row 1 (closer): segments between wall ends and rough-opening edges;
      # row 2 (farther): overall face-to-face length. A wall without openings
      # gets only the overall row, at row-1 distance.
      def draw_wall_dim(ents, d)
        return if d[:len] < 24.0

        # EXTERIOR side: nothing per wall any more. From 2026-08-01 the outside
        # is dimensioned by BUILDING-LEVEL chains (draw_dim_chains), the way the
        # target set does it - keeping both would give every wall five rows.

        # INTERIOR side (off_pos): clear inside length between the neighbouring
        # walls' faces (what a contractor measures in the room).
        ia, ib = interior_clear_span(d)
        dim_row(ents, d, [[ia, ib]], d[:off_pos], -DIM_OFF, DIM_TEXT_H) if (ib - ia) > 12.0
      end

      # ---- building dimension chains (2026-08-01) --------------------------
      # The target set dimensions the BUILDING, not each wall: three stacked
      # bands run along every side. Nearest band = opening centres, middle =
      # wall-to-wall segments, outer = overall face to face. Everything here
      # works in world coordinates, off the real mitered band corners.

      CHAIN_GAP  = 13.0 unless const_defined?(:CHAIN_GAP, false)
      CHAIN_TOL  = 1.0  unless const_defined?(:CHAIN_TOL, false)

      def add_world_poly(ents, pts)
        ents.add_edges(pts)
      rescue StandardError
        nil
      end

      # Every wall as a world-space quad plus its world direction.
      def chain_wall_info(model)
        walls(model).map { |w| wall_attrs(w) }.compact.map do |d|
          q = seg_points(d, 0.0, d[:len], true, true).map { |p| flat_world(p, d[:xform]) }
          dir = q[1] - q[0]
          next nil if dir.length < 0.5
          dir.normalize!
          { d: d, q: q, dir: dir }
        end.compact
      end

      def chain_box(info)
        xs = info.flat_map { |i| i[:q].map { |p| p.x.to_f } }
        ys = info.flat_map { |i| i[:q].map { |p| p.y.to_f } }
        { x0: xs.min, x1: xs.max, y0: ys.min, y1: ys.max }
      end

      def dedupe_stops(vals, lo, hi)
        vals.select { |v| v >= lo - CHAIN_TOL && v <= hi + CHAIN_TOL }
            .sort
            .each_with_object([]) { |v, acc| acc << v if acc.empty? || (v - acc.last) > CHAIN_TOL }
      end

      # Segment band: the faces of every wall that runs ACROSS the chain. Those
      # are the positions a contractor sets out from. Faces sitting right at the
      # ends are dropped - they are the perimeter walls themselves, and a 6 in
      # tick in each corner is noise the overall band already covers.
      def chain_segment_stops(info, axis, lo, hi)
        vals = []
        info.each do |i|
          along = axis == :x ? i[:dir].x.abs : i[:dir].y.abs
          next if along > 0.35                      # runs along the chain, not across
          i[:q].each { |p| vals << (axis == :x ? p.x.to_f : p.y.to_f) }
        end
        inner = dedupe_stops(vals, lo, hi).reject { |v| (v - lo).abs < 8.0 || (hi - v).abs < 8.0 }
        dedupe_stops([lo] + inner + [hi], lo, hi)
      end

      # Opening band: the two EDGES of every opening on the walls facing THIS
      # side, so the band reads corner - window width - gap - window width -
      # corner. (User preference 2026-08-03: sizes and gaps, not centres.)
      def chain_opening_stops(info, axis, side, box)
        lo, hi = axis == :x ? [box[:x0], box[:x1]] : [box[:y0], box[:y1]]
        edge = if axis == :x
                 side == :low ? box[:y0] : box[:y1]
               else
                 side == :low ? box[:x0] : box[:x1]
               end
        vals = [lo, hi]
        info.each do |i|
          along = axis == :x ? i[:dir].x.abs : i[:dir].y.abs
          next if along < 0.9                        # must run ALONG the chain
          d = i[:d]
          near = i[:q].map { |p| ((axis == :x ? p.y.to_f : p.x.to_f) - edge).abs }.min
          next if near > d[:thickness] + 2.0         # not on this side of the building
          mid_off = (d[:off_pos] + d[:off_neg]) / 2.0
          d[:openings].each do |o|
            hw = o[:width].to_f / 2.0
            [o[:t] - hw, o[:t] + hw].each do |t|
              c = flat_world(lpt(d, t, mid_off), d[:xform])
              vals << (axis == :x ? c.x.to_f : c.y.to_f)
            end
          end
        end
        dedupe_stops(vals, lo, hi)
      end

      def draw_dim_chains(ents, model)
        info = chain_wall_info(model)
        return if info.empty?
        box = chain_box(info)
        return if (box[:x1] - box[:x0]) < 24.0 || (box[:y1] - box[:y0]) < 24.0
        [[:x, :low], [:x, :high], [:y, :low], [:y, :high]].each do |axis, side|
          begin
            draw_one_chain(ents, info, box, axis, side)
          rescue StandardError => e
            puts "[Plan2D] dim chain #{axis}/#{side}: #{e.message}"
          end
        end
      end

      # Which bands a side actually gets: the opening band only when it adds
      # something, the segment band only when the building is not a plain box.
      def chain_rows(info, box, axis, side)
        lo, hi = axis == :x ? [box[:x0], box[:x1]] : [box[:y0], box[:y1]]
        rows = []
        ops = chain_opening_stops(info, axis, side, box)
        rows << { stops: ops, text: 3.6 } if ops.length > 2
        seg = chain_segment_stops(info, axis, lo, hi)
        rows << { stops: seg, text: 4.0 } if seg.length > 2
        rows << { stops: [lo, hi], text: 5.0 }
        rows
      end

      def draw_one_chain(ents, info, box, axis, side)
        out = side == :low ? -1.0 : 1.0
        edge = if axis == :x
                 side == :low ? box[:y0] : box[:y1]
               else
                 side == :low ? box[:x0] : box[:x1]
               end
        ang = axis == :x ? 0.0 : Math::PI / 2
        mk = lambda do |along, off|
          if axis == :x
            Geom::Point3d.new(along, edge + out * off, PLAN_Z)
          else
            Geom::Point3d.new(edge + out * off, along, PLAN_Z)
          end
        end
        chain_rows(info, box, axis, side).each_with_index do |row, idx|
          draw_chain_row(ents, row[:stops], mk, CHAIN_GAP * (idx + 1), row[:text], ang)
        end
      end

      # One band: the run itself, a witness line and tick at every stop, and the
      # length between consecutive stops.
      def draw_chain_row(ents, stops, mk, dist, text_h, ang)
        return if stops.length < 2
        add_world_poly(ents, [mk.call(stops.first, dist), mk.call(stops.last, dist)])
        stops.each do |v|
          add_world_poly(ents, [mk.call(v, 2.0), mk.call(v, dist + 2.0)])
          a = mk.call(v, dist - 1.8)
          b = mk.call(v, dist + 1.8)
          add_world_poly(ents, [a, b])
        end
        stops.each_cons(2) do |a, b|
          next if (b - a) < 8.0
          add_text(ents, fmt_feet(b - a), text_h, mk.call((a + b) / 2.0, dist + 4.0), ang)
        end
      end

      # Inside clear span along the wall: from 0/len inwards by the thickness of
      # whatever wall meets each end (so the number is face-to-face in the room).
      def interior_clear_span(d)
        a = 0.0
        b = d[:len]
        s = d[:s]
        e = d[:e]
        walls(Sketchup.active_model).each do |w|
          next if w.get_attribute('InteriorPro', 'id') == d[:id]
          sx = w.get_attribute('InteriorPro', 'start_x')
          next if sx.nil?
          xf = w.transformation
          th = w.get_attribute('InteriorPro', 'thickness').to_f
          ws = Geom::Point3d.new(sx.to_f, w.get_attribute('InteriorPro', 'start_y').to_f, 0).transform(xf)
          we = Geom::Point3d.new(w.get_attribute('InteriorPro', 'end_x').to_f,
                                 w.get_attribute('InteriorPro', 'end_y').to_f, 0).transform(xf)
          [ws, we].each do |p|
            a = th if p.distance(s) < th + 2.0 && th > a
            b = d[:len] - th if p.distance(e) < th + 2.0 && (d[:len] - th) < b
          end
        end
        [a, b]
      end

      # One dimension row: continuous line, extension lines + ticks at every
      # stop, a length text per segment.
      def dim_row(ents, d, segs, off_face, dist, text_h)
        off_dim = off_face - dist
        diag = Geom::Vector3d.new(d[:u].x + d[:n].x, d[:u].y + d[:n].y, 0)
        diag.normalize!
        uw = d[:u].transform(d[:xform])
        ang = Math.atan2(uw.y, uw.x)
        ang += Math::PI if ang > Math::PI / 2 + 0.01 || ang < -Math::PI / 2 - 0.01

        add_poly(ents, d, [lpt(d, segs.first[0], off_dim), lpt(d, segs.last[1], off_dim)])
        stops = segs.flatten.uniq.sort
        stops.each do |x|
          add_poly(ents, d, [lpt(d, x, off_face - 2.0), lpt(d, x, off_dim - 2.0)])
          p = lpt(d, x, off_dim)
          add_poly(ents, d, [p.offset(diag, -2.0), p.offset(diag, 2.0)])
        end
        segs.each do |a, b|
          next if (b - a) < 8.0
          center = flat_world(lpt(d, (a + b) / 2.0, off_dim - 4.0), d[:xform])
          add_text(ents, fmt_feet(b - a), text_h, center, ang)
        end
      end

      # ---- free 2D lines / shapes ------------------------------------------

      # Shapes drawn with the editor's Line tool (type='sketch2d'). Outline
      # only - no fill, no hatch (same house rule as the floor hatch).
      def draw_sketches(ents, model)
        model.entities.grep(Sketchup::Group).each do |g|
          next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'sketch2d'
          pts = g.get_attribute('InteriorPro', 'pts')
          next unless pts.is_a?(Array) && pts.length >= 4
          xf = g.transformation
          world = pts.each_slice(2).map do |x, y|
            w = Geom::Point3d.new(x.to_f, y.to_f, 0).transform(xf)
            Geom::Point3d.new(w.x, w.y, PLAN_Z)
          end
          world << world.first if g.get_attribute('InteriorPro', 'closed') && world.length > 2
          style = (g.get_attribute('InteriorPro', 'style') || 'solid').to_s
          weight = (g.get_attribute('InteriorPro', 'weight') || 1).to_i
          begin
            if style == 'dashed'
              world.each_cons(2) { |a, b| dashed_edge(ents, a, b) }
            elsif weight == 2
              # A thick line reads as a close double line on paper.
              world.each_cons(2) do |a, b|
                v = b - a
                next if v.length < 0.5
                v.normalize!
                n2 = Geom::Vector3d.new(-v.y, v.x, 0)
                ents.add_edges(a.offset(n2, 0.4), b.offset(n2, 0.4))
                ents.add_edges(a.offset(n2, -0.4), b.offset(n2, -0.4))
              end
            else
              ents.add_edges(world)
            end
          rescue StandardError => e
            puts "[Plan2D] sketch #{g.get_attribute('InteriorPro', 'id')}: #{e.message}"
          end
        end
      end

      def dashed_edge(ents, a, b, dash = 6.0, gap = 4.0)
        v = b - a
        len = v.length
        return if len < 0.5
        v.normalize!
        pos = 0.0
        while pos < len
          e2 = [pos + dash, len].min
          begin
            ents.add_edges(a.offset(v, pos), a.offset(v, e2))
          rescue StandardError
          end
          pos += dash + gap
        end
      end

      # ---- room labels -----------------------------------------------------

      HATCH_SPACING = 18.0 unless const_defined?(:HATCH_SPACING, false)
      HATCH_ANGLE   = 45.0 unless const_defined?(:HATCH_ANGLE, false)

      def draw_room_labels(ents, model)
        rooms = model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'room'
        end
        rooms.each do |r|
          flat = r.get_attribute('InteriorPro', 'boundary_xy')
          next unless flat.is_a?(Array) && flat.length >= 6
          poly = flat.each_slice(2).map { |x, y| [x.to_f, y.to_f] }
          xs = poly.map(&:first)
          ys = poly.map(&:last)
          cx = xs.sum / xs.length
          cy = ys.sum / ys.length
          # (floor hatch intentionally NOT drawn — user preference 2026-07-30)
          name = (r.get_attribute('InteriorPro', 'name') || 'Room').to_s.upcase
          area = r.get_attribute('InteriorPro', 'area_sqft').to_f
          add_text(ents, name, 7.0, Geom::Point3d.new(cx, cy + 5.0, PLAN_Z), 0.0)
          add_text(ents, "#{area.round} SF", 4.5, Geom::Point3d.new(cx, cy - 7.0, PLAN_Z), 0.0)
        end
      end

      # Light 45-degree floor hatch clipped to the room polygon (scan-line:
      # rotate so the lines are horizontal, intersect each edge, draw pairs).
      def hatch_polygon(ents, poly, spacing = HATCH_SPACING, angle_deg = HATCH_ANGLE)
        a = angle_deg * Math::PI / 180.0
        ca = Math.cos(-a)
        sa = Math.sin(-a)
        rot = poly.map { |x, y| [x * ca - y * sa, x * sa + y * ca] }
        ymin = rot.map(&:last).min
        ymax = rot.map(&:last).max
        return if (ymax - ymin) < spacing
        back_ca = Math.cos(a)
        back_sa = Math.sin(a)
        y = ymin + spacing
        while y < ymax
          xs = []
          rot.each_with_index do |(x1, y1), i|
            x2, y2 = rot[(i + 1) % rot.length]
            next if (y1 > y) == (y2 > y)
            t = (y - y1) / (y2 - y1)
            xs << (x1 + (x2 - x1) * t)
          end
          xs.sort!
          xs.each_slice(2) do |xa, xb|
            next if xb.nil? || (xb - xa) < 2.0
            p1 = [xa * back_ca - y * back_sa, xa * back_sa + y * back_ca]
            p2 = [xb * back_ca - y * back_sa, xb * back_sa + y * back_ca]
            begin
              ents.add_edges(Geom::Point3d.new(p1[0], p1[1], PLAN_Z),
                             Geom::Point3d.new(p2[0], p2[1], PLAN_Z))
            rescue StandardError
            end
          end
          y += spacing
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
        h = text.to_s.length > 4 ? 3.2 : MARK_TEXT_H
        add_text(ents, text, h, center, 0.0)
      end

      # ---- schedules (A.114 style) ----------------------------------------

      SCHED_ROW_H  = 12.0 unless const_defined?(:SCHED_ROW_H, false)
      SCHED_TEXT_H = 3.6 unless const_defined?(:SCHED_TEXT_H, false)

      def door_type_label(b)
        case door_kind(b)
        when :garage  then 'GARAGE DOOR'
        when :sliding then 'SLIDING DOOR'
        when :folding then 'BI-FOLD DOOR'
        when :pocket  then 'POCKET DOOR'
        when :double  then 'DOUBLE SWING'
        else 'SWING DOOR'
        end
      end

      # Window + Door schedules drawn to the right of the plan.
      def draw_schedules(ents, model, doors, windows)
        return if doors.empty? && windows.empty?
        minx = miny = 1.0 / 0.0
        maxx = maxy = -1.0 / 0.0
        walls(model).each do |w|
          xf = w.transformation
          %w[start end].each do |k|
            x = w.get_attribute('InteriorPro', "#{k}_x")
            next if x.nil?
            pt = Geom::Point3d.new(x.to_f, w.get_attribute('InteriorPro', "#{k}_y").to_f, 0).transform(xf)
            minx = pt.x if pt.x < minx
            maxx = pt.x if pt.x > maxx
            miny = pt.y if pt.y < miny
            maxy = pt.y if pt.y > maxy
          end
        end
        return if maxx < minx
        ox = maxx + 60.0
        oy = maxy

        unless windows.empty?
          rows = windows.sort_by { |b| b[:mark] }.map do |b|
            [b[:mark], fmt_feet(b[:width]), fmt_feet(b[:height]),
             (b[:wtype].empty? ? 'WINDOW' : b[:wtype].upcase), fmt_feet(b[:header])]
          end
          oy = draw_schedule_table(ents, ox, oy, 'WINDOW SCHEDULE',
                                   ['MARK', 'R.O. W', 'R.O. H', 'TYPE', 'HEAD'],
                                   rows, [26.0, 26.0, 26.0, 72.0, 26.0])
          oy -= 18.0
        end

        unless doors.empty?
          rows = doors.sort_by { |b| b[:mark] }.map do |b|
            [b[:mark], fmt_feet(b[:width]), fmt_feet(b[:height]),
             door_type_label(b), b[:category] == 'interior' ? 'INTERIOR' : 'EXTERIOR']
          end
          draw_schedule_table(ents, ox, oy, 'DOOR SCHEDULE',
                              ['MARK', 'WIDTH', 'HEIGHT', 'TYPE', 'FUNCTION'],
                              rows, [26.0, 26.0, 26.0, 72.0, 34.0])
        end
      end

      # Grid + texts, world-aligned (X axis). Returns the bottom Y.
      def draw_schedule_table(ents, ox, oy, title, headers, rows, colws)
        total_w = colws.sum
        add_text(ents, title, 5.0, Geom::Point3d.new(ox + total_w / 2.0, oy + 8.0, PLAN_Z), 0.0)
        all_rows = [headers] + rows
        n = all_rows.length
        wline = lambda do |x1, y1, x2, y2|
          begin
            ents.add_edges(Geom::Point3d.new(x1, y1, PLAN_Z), Geom::Point3d.new(x2, y2, PLAN_Z))
          rescue StandardError
          end
        end
        (0..n).each { |i| wline.call(ox, oy - i * SCHED_ROW_H, ox + total_w, oy - i * SCHED_ROW_H) }
        cx = ox
        wline.call(cx, oy, cx, oy - n * SCHED_ROW_H)
        colws.each do |cw|
          cx += cw
          wline.call(cx, oy, cx, oy - n * SCHED_ROW_H)
        end
        all_rows.each_with_index do |row, ri|
          cy = oy - ri * SCHED_ROW_H - SCHED_ROW_H / 2.0
          cx = ox
          row.each_with_index do |cell, ci|
            cw = colws[ci]
            txt = cell.to_s
            h = SCHED_TEXT_H
            h = [h * cw / (txt.length * h * 0.62), h].min if txt.length > 0   # shrink long cells
            add_text(ents, txt, [h, 2.4].max, Geom::Point3d.new(cx + cw / 2.0, cy, PLAN_Z), 0.0) unless txt.empty?
            cx += cw
          end
        end
        oy - n * SCHED_ROW_H
      end

      # ---- legend + sheet title -------------------------------------------

      def plan_bounds(model)
        minx = miny = 1.0 / 0.0
        maxx = maxy = -1.0 / 0.0
        walls(model).each do |w|
          xf = w.transformation
          %w[start end].each do |k|
            x = w.get_attribute('InteriorPro', "#{k}_x")
            next if x.nil?
            p = Geom::Point3d.new(x.to_f, w.get_attribute('InteriorPro', "#{k}_y").to_f, 0).transform(xf)
            minx = p.x if p.x < minx
            maxx = p.x if p.x > maxx
            miny = p.y if p.y < miny
            maxy = p.y if p.y > maxy
          end
        end
        return nil if maxx < minx
        [minx, miny, maxx, maxy]
      end

      def draw_legend_and_title(ents, model)
        b = plan_bounds(model)
        return unless b
        minx, miny, maxx, = b

        # Sheet title + scale under the plan
        add_text(ents, 'FLOOR PLAN', 9.0, Geom::Point3d.new((minx + maxx) / 2.0, miny - 62.0, PLAN_Z), 0.0)
        add_text(ents, '1/4" = 1\'-0"', 5.0, Geom::Point3d.new((minx + maxx) / 2.0, miny - 74.0, PLAN_Z), 0.0)

        # Wall type legend (bottom-left of the plan)
        lx = minx
        ly = miny - 62.0
        add_text(ents, 'WALL LEGEND', 5.5, Geom::Point3d.new(lx + 30.0, ly + 12.0, PLAN_Z), 0.0)
        [['EXTERIOR WALL', plan_material('exterior'), 0.0],
         ['INTERIOR WALL', plan_material('interior'), -14.0]].each do |label, mat, dy|
          pts = [[lx, ly + dy], [lx + 22.0, ly + dy], [lx + 22.0, ly + dy - 6.0], [lx, ly + dy - 6.0]]
                .map { |x, y| Geom::Point3d.new(x, y, PLAN_Z) }
          f = begin
            ents.add_face(pts)
          rescue StandardError
            nil
          end
          if f
            f.material = mat
            f.back_material = mat
          end
          add_text(ents, label, 4.0, Geom::Point3d.new(lx + 62.0, ly + dy - 3.0, PLAN_Z), 0.0)
        end
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

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
    MARK_R     = 5.5 unless const_defined?(:MARK_R, false)
    MARK_TEXT_H = 5.0 unless const_defined?(:MARK_TEXT_H, false)

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
          rescue StandardError => e
            puts "[Plan2D] symbols on wall #{d[:id]}: #{e.message}"
          end
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
          case door_kind(b)
          when :garage  then sym_garage(ents, d, x1, x2)
          when :sliding then sym_sliding(ents, d, x1, x2)
          when :folding then sym_folding(ents, d, b, x1, x2)
          when :pocket  then sym_pocket(ents, d, b, x1, x2)
          when :double  then sym_double_swing(ents, d, b, x1, x2)
          else               sym_single_swing(ents, d, b, x1, x2)
          end
          mark_badge(ents, d, b[:mark], (x1 + x2) / 2.0, d[:off_neg] - 9.0, :circle)
        end
      end

      def sym_single_swing(ents, d, b, x1, x2)
        w = x2 - x1
        ss = swing_sign(b)
        edge = ss > 0 ? d[:off_pos] : d[:off_neg]
        hinge_x = b[:swing] == 'right' ? x2 : x1
        latch_x = hinge_x == x1 ? x2 : x1
        hinge = lpt(d, hinge_x, edge)
        latch = lpt(d, latch_x, edge)
        leaf_end = hinge.offset(d[:n], ss * w)
        add_poly(ents, d, [hinge, leaf_end])
        add_arc(ents, d, hinge, latch, leaf_end)
      end

      def sym_double_swing(ents, d, b, x1, x2)
        w = (x2 - x1) / 2.0
        ss = swing_sign(b)
        edge = ss > 0 ? d[:off_pos] : d[:off_neg]
        xm = (x1 + x2) / 2.0
        [[x1, xm], [x2, xm]].each do |hx, lx|
          hinge = lpt(d, hx, edge)
          latch = lpt(d, lx, edge)
          leaf_end = hinge.offset(d[:n], ss * w)
          add_poly(ents, d, [hinge, leaf_end])
          add_arc(ents, d, hinge, latch, leaf_end)
        end
      end

      # Quarter-circle polyline from latch to leaf_end around hinge.
      def add_arc(ents, d, hinge, from_pt, to_pt)
        v0 = from_pt - hinge
        v1 = to_pt - hinge
        r = v0.length
        return if r < 1.0
        cross_z = v0.x * v1.y - v0.y * v1.x
        sweep = cross_z >= 0 ? Math::PI / 2 : -Math::PI / 2
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
          rect(ents, d, x1, x2, d[:off_neg], d[:off_pos])
          cmid = (d[:off_pos] + d[:off_neg]) / 2.0
          add_poly(ents, d, [lpt(d, x1 + 0.5, cmid), lpt(d, x2 - 0.5, cmid)])
          mark_badge(ents, d, b[:mark], (x1 + x2) / 2.0, d[:off_pos] + 9.0, :hex)
        end
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
        label = ents.add_group
        begin
          label.entities.add_3d_text(text.to_s, TextAlignCenter, 'Arial', false, false,
                                     MARK_TEXT_H, 0.0, 0.0, true, 0.0)
          b = label.bounds
          label.transform!(Geom::Transformation.translation(center - b.center))
          m = get_plan_mat('InteriorPro_Plan_Line', [0, 0, 0])
          label.entities.grep(Sketchup::Face).each { |f| f.material = m; f.back_material = m }
        rescue StandardError => e
          label.erase! if label.valid?
          puts "[Plan2D] mark text '#{text}': #{e.message}"
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

# Interior Pro - 2D Plan Generator
# Step 1 (2026-07-27): wall poche + opening gaps + "2D Plan" scene.
#
# 2D contract: reads ONLY InteriorPro attributes (never geometry) and
# regenerates a flat symbol layer from scratch on every build!.
# All plan geometry lives in one top-level group (type='plan2d') on tag IP/2D.

module InteriorPro
  module PlanGenerator
    PLAN_TAG   = 'IP/2D' unless const_defined?(:PLAN_TAG, false)
    PLAN_Z     = 0.5 unless const_defined?(:PLAN_Z, false)
    SCENE_NAME = '2D Plan' unless const_defined?(:SCENE_NAME, false)

    class << self
      # Rebuild the whole 2D plan layer from attributes.
      def build!
        model = Sketchup.active_model
        model.start_operation('2D Plan', true)
        remove_plan_groups(model)

        grp = model.entities.add_group
        grp.name = 'InteriorPro 2D Plan'
        grp.set_attribute('InteriorPro', 'type', 'plan2d')

        count = 0
        walls(model).each do |wall|
          count += 1 if draw_wall_plan(grp.entities, wall)
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
        puts "[Plan2D] built plan for #{count} wall(s)"
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

      def wall_attrs(wall)
        sx = wall.get_attribute('InteriorPro', 'start_x')
        return nil if sx.nil?
        sy = wall.get_attribute('InteriorPro', 'start_y')
        ex = wall.get_attribute('InteriorPro', 'end_x')
        ey = wall.get_attribute('InteriorPro', 'end_y')
        th = wall.get_attribute('InteriorPro', 'thickness').to_f
        return nil if th <= 0.0

        anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-left').to_s
        h_anchor = anchor == 'center' ? 'center' : (anchor.split('-')[1] || 'left')

        corners = wall.get_attribute('InteriorPro', 'corners_xy')
        corners = nil unless corners.is_a?(Array) && corners.length == 8

        {
          xform:     wall.transformation,
          s:         Geom::Point3d.new(sx.to_f, sy.to_f, 0),
          e:         Geom::Point3d.new(ex.to_f, ey.to_f, 0),
          thickness: th,
          h_anchor:  h_anchor,
          corners:   corners,
          category:  (wall.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s,
          openings:  InteriorPro::WallTool.read_door_openings(wall)
        }
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
      # Openings become gaps; the segment end edges are the plan "cap lines".
      def draw_wall_plan(ents, wall)
        d = wall_attrs(wall)
        return false unless d

        u = d[:e] - d[:s]
        len = u.length.to_f
        return false if len < 0.5
        u.normalize!
        n = Geom::Vector3d.new(-u.y, u.x, 0)
        off_pos, off_neg = band_offsets(d[:h_anchor], d[:thickness])

        cuts = d[:openings]
               .map { |o| [o[:t] - o[:width] / 2.0, o[:t] + o[:width] / 2.0] }
               .map { |a, b| [[a, 0.0].max, [b, len].min] }
               .select { |a, b| (b - a) > 0.1 }
               .sort_by(&:first)

        segs = []
        pos = 0.0
        cuts.each do |a, b|
          segs << [pos, a] if (a - pos) > 0.05
          pos = b if b > pos
        end
        segs << [pos, len] if (len - pos) > 0.05
        segs = [[0.0, len]] if segs.empty?

        mat = plan_material(d[:category])
        segs.each do |a, b|
          pts = seg_points(d, u, n, off_pos, off_neg, a, b,
                           a <= 0.05, b >= len - 0.05)
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

      # Segment corners in the wall's LOCAL frame. End segments reuse the
      # stored (mitered) corners_xy so plan corners match the 3D miters.
      def seg_points(d, u, n, off_pos, off_neg, a, b, at_start, at_end)
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
        s_pos ||= d[:s].offset(u, a).offset(n, off_pos)
        s_neg ||= d[:s].offset(u, a).offset(n, off_neg)
        e_pos ||= d[:s].offset(u, b).offset(n, off_pos)
        e_neg ||= d[:s].offset(u, b).offset(n, off_neg)
        [s_pos, e_pos, e_neg, s_neg]
      end

      # Local point -> world XY, flattened to the plan plane.
      def flat_world(pt, xform)
        w = pt.transform(xform)
        Geom::Point3d.new(w.x, w.y, PLAN_Z)
      end

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

      # "2D Plan" scene: top-down parallel camera, only IP/2D visible
      # among the IP/* tags. Non-IP tags are left untouched.
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

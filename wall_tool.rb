# Interior Pro - Wall Tool

module InteriorPro
  class WallTool
    attr_accessor :height, :thickness, :exterior_material, :interior_material, :wall_type_name, :anchor, :wall_category, :side_a_color, :side_b_color

    def initialize
      @start_point = nil
      @end_point = nil
      @height = 96.0
      @thickness = 6.0
      @exterior_material = 'Stucco'
      @interior_material = 'Gypsum'
      @side_a_color = '#ffffff'
      @side_b_color = '#ffffff'
      @wall_type_name = 'Default'
      @anchor = 'bottom-center'
      @wall_category = 'exterior'
      @drawing = false
      @locked_axis = nil
      @auto_snap = nil
      @length_input = ''
      @ip = nil
      @preview_group = nil
    end

    def activate
      @ip = Sketchup::InputPoint.new
      Sketchup.set_status_text('Click to start drawing a wall. Press Escape to cancel.', SB_PROMPT)
      view = Sketchup.active_model.active_view
      view.invalidate
    end

    def deactivate(view)
      clear_preview
      view.invalidate
    end

    def draw(view)
      @ip.draw(view) if @ip && @ip.display?
      return unless @drawing && @start_point && @locked_axis

      if @locked_axis == :x
        view.drawing_color = Sketchup::Color.new(255, 0, 0)
        p1 = Geom::Point3d.new(@start_point.x - 10000, @start_point.y, @start_point.z)
        p2 = Geom::Point3d.new(@start_point.x + 10000, @start_point.y, @start_point.z)
      else
        view.drawing_color = Sketchup::Color.new(0, 200, 0)
        p1 = Geom::Point3d.new(@start_point.x, @start_point.y - 10000, @start_point.z)
        p2 = Geom::Point3d.new(@start_point.x, @start_point.y + 10000, @start_point.z)
      end
      view.line_width = 1
      view.line_stipple = '_'
      view.draw(GL_LINES, [p1, p2])
      view.line_stipple = ''
    end

    def compute_wall_points
      return nil unless @start_point && @end_point
      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.1

      nx = -dy / len * @thickness / 2
      ny = dx / len * @thickness / 2

      if @anchor == 'center'
        v_anchor = 'center'
        h_anchor = 'center'
      else
        parts = @anchor.split('-')
        v_anchor = parts[0]
        h_anchor = parts[1] || 'center'
      end

      case v_anchor
      when 'top'
        z1 = -@height
        z2 = 0
      when 'center'
        z1 = -@height / 2.0
        z2 = @height / 2.0
      else
        z1 = 0
        z2 = @height
      end

      case h_anchor
      when 'left'
        b1 = Geom::Point3d.new(@start_point.x, @start_point.y, z1)
        b2 = Geom::Point3d.new(@end_point.x, @end_point.y, z1)
        b3 = Geom::Point3d.new(@end_point.x + nx * 2, @end_point.y + ny * 2, z1)
        b4 = Geom::Point3d.new(@start_point.x + nx * 2, @start_point.y + ny * 2, z1)
      when 'right'
        b1 = Geom::Point3d.new(@start_point.x - nx * 2, @start_point.y - ny * 2, z1)
        b2 = Geom::Point3d.new(@end_point.x - nx * 2, @end_point.y - ny * 2, z1)
        b3 = Geom::Point3d.new(@end_point.x, @end_point.y, z1)
        b4 = Geom::Point3d.new(@start_point.x, @start_point.y, z1)
      else
        b1 = Geom::Point3d.new(@start_point.x + nx, @start_point.y + ny, z1)
        b2 = Geom::Point3d.new(@end_point.x + nx, @end_point.y + ny, z1)
        b3 = Geom::Point3d.new(@end_point.x - nx, @end_point.y - ny, z1)
        b4 = Geom::Point3d.new(@start_point.x - nx, @start_point.y - ny, z1)
      end

      { b: [b1, b2, b3, b4], z1: z1, z2: z2 }
    end

    def preview_material
      model = Sketchup.active_model
      mat = model.materials['InteriorPro_Preview']
      unless mat
        mat = model.materials.add('InteriorPro_Preview')
        mat.color = Sketchup::Color.new(200, 200, 200, 80)
      end
      mat.alpha = 0.5
      mat
    end

    def create_preview
      return unless @drawing
      pts = compute_wall_points
      return unless pts

      model = Sketchup.active_model
      model.start_operation('Preview Wall', true, false, true)
      begin
        @preview_group = model.active_entities.add_group
        @preview_group.set_attribute('InteriorPro', 'type', 'wall_preview')
        @preview_group.layer = Sketchup.active_model.layers['Untagged'] rescue nil
        ents = @preview_group.entities
        face = ents.add_face(*pts[:b])
        height = pts[:z2] - pts[:z1]
        dir = face.normal.z >= 0 ? 1 : -1
        face.pushpull(height * dir)
        @preview_group.material = preview_material
        model.commit_operation
      rescue => e
        model.abort_operation
        @preview_group = nil
        puts "[WallTool.create_preview] error: #{e.message}"
      end
    end

    def clear_preview
      return unless @preview_group && @preview_group.valid?
      model = Sketchup.active_model
      model.start_operation('Clear Preview', true, false, true)
      @preview_group.erase!
      model.commit_operation
      @preview_group = nil
    end

    def onMouseMove(flags, x, y, view)
      @preview_group.hidden = true if @preview_group && @preview_group.valid?
      @ip.pick(view, x, y)
      @preview_group.hidden = false if @preview_group && @preview_group.valid?
      if @drawing
        raw = raw_cursor_position(view, x, y)
        pt = @ip.position
        pt = snap_start_to_wall_centerline(pt)
        if @auto_snap == :manual
          @end_point = snap_to_axis(pt)
        elsif snapped_to_geometry?
          detect_auto_snap(raw) if raw
          @end_point = snap_to_axis(pt)
        else
          detect_auto_snap(raw) if raw
          @end_point = snap_to_axis(pt)
        end
        clear_preview
        create_preview
      end
      view.invalidate
    end

    def snapped_to_geometry?
      !@ip.vertex.nil? || !@ip.edge.nil?
    end

    def onLButtonDown(flags, x, y, view)
      @preview_group.hidden = true if @preview_group && @preview_group.valid?
      @ip.pick(view, x, y)
      @preview_group.hidden = false if @preview_group && @preview_group.valid?
      if !@drawing
        pt = Geom::Point3d.new(@ip.position.x, @ip.position.y, 0)
        @start_point = snap_start_to_wall_centerline(pt)
        @drawing = true
        @length_input = ''
        Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
      else
        # ALWAYS use preview result
        pt = @end_point

        # Safety: if somehow nil, fallback once
        if pt.nil?
          raw = raw_cursor_position(view, x, y)
          pt_input = @ip.position
          detect_auto_snap(raw) if raw
          pt = snap_to_axis(pt_input)
        end

        @end_point = pt
        create_wall
        @start_point = @end_point
        @length_input = ''
      end
    end

    def onLButtonDoubleClick(flags, x, y, view)
      finish_drawing
    end

    def onKeyDown(key, repeat, flags, view)
      if key == 27
        finish_drawing
        return
      end
      if key == 16 && @drawing && @start_point
        dx = @end_point ? (@end_point.x - @start_point.x).abs : 0
        dy = @end_point ? (@end_point.y - @start_point.y).abs : 0
        @locked_axis = dx > dy ? :x : :y
        @auto_snap = :manual
        Sketchup.set_status_text('Direction locked (hold Shift).', SB_PROMPT)
        view.invalidate
        return
      end

      return unless @drawing && @start_point

      if key >= 48 && key <= 57
        @length_input += (key - 48).to_s
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 190 || key == 110 || key == 46
        @length_input += '.' unless @length_input.include?('.')
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 222 || key == 39
        @length_input += "'"
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 186 || key == 34
        @length_input += '"'
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 8
        @length_input = @length_input[0...-1] if @length_input.length > 0
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 13
        apply_length_input if @length_input.length > 0
      end
    end

    def apply_length_input
      return unless @start_point && @end_point
      length = @length_input.to_l
      @length_input = ''
      return if length <= 0
      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      cur_len = Math.sqrt(dx**2 + dy**2)
      return if cur_len < 0.001
      new_x = @start_point.x + dx / cur_len * length
      new_y = @start_point.y + dy / cur_len * length
      @end_point = Geom::Point3d.new(new_x, new_y, 0)
      create_wall
      @start_point = @end_point
      Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
    end

    def onKeyUp(key, repeat, flags, view)
      if key == 16
        @locked_axis = nil
        @auto_snap = nil
        view.invalidate
      end
    end

    def detect_auto_snap(pt)
      return unless @start_point
      dx = pt.x - @start_point.x
      dy = pt.y - @start_point.y
      if dx.abs < 0.1 && dy.abs < 0.1
        @locked_axis = nil
        @auto_snap = nil
        return
      end
      if dx.abs >= dy.abs
        @locked_axis = :x
        @auto_snap = :auto
      else
        @locked_axis = :y
        @auto_snap = :auto
      end
    end

    def snap_to_axis(pt)
      return Geom::Point3d.new(pt.x, pt.y, 0) unless @drawing && @start_point
      if @locked_axis == :x
        Geom::Point3d.new(pt.x, @start_point.y, 0)
      elsif @locked_axis == :y
        Geom::Point3d.new(@start_point.x, pt.y, 0)
      else
        Geom::Point3d.new(pt.x, pt.y, 0)
      end
    end

    # Cursor position from the screen pickray, ignoring all geometry inference.
    # Used so the user's screen-direction (not the inferred snap target) drives
    # axis detection while drawing — fixes axis lock being hijacked when the
    # cursor passes over previous wall edges.
    def raw_cursor_position(view, x, y)
      ray = view.pickray(x, y)
      Geom.intersect_line_plane(ray, [Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1)])
    end

    def snap_start_to_wall_centerline(pt)
      best = nil
      best_d = 1000000.0 # inches - distance from projection to logical endpoint
      perp_tol = 15.0 # inches - max perpendicular distance from logical line
      flat = Geom::Point3d.new(pt.x, pt.y, 0.0)
      Sketchup.active_model.active_entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'wall'
        sx = g.get_attribute('InteriorPro', 'start_x')
        sy = g.get_attribute('InteriorPro', 'start_y')
        ex = g.get_attribute('InteriorPro', 'end_x')
        ey = g.get_attribute('InteriorPro', 'end_y')
        next unless sx && sy && ex && ey
        sp = Geom::Point3d.new(sx, sy, 0)
        ep = Geom::Point3d.new(ex, ey, 0)
        line_vec = ep - sp
        next if line_vec.length < 0.001
        line_vec.normalize!
        thickness = g.get_attribute('InteriorPro', 'thickness')
        tol = (thickness.to_f / 2.0) + 0.5
        # project pt onto infinite line through sp,ep
        to_pt = flat - sp
        t = to_pt.dot(line_vec)
        proj = sp.offset(line_vec, t)
        perp_d = flat.distance(proj)
        next if perp_d > perp_tol
        # check distance from projection to each endpoint
        d_start = proj.distance(sp)
        d_end = proj.distance(ep)
        if d_start < tol && d_start < best_d
          best_d = d_start
          best = sp
        end
        if d_end < tol && d_end < best_d
          best_d = d_end
          best = ep
        end
      end
      best || pt
    end

    def create_wall
      return unless @start_point && @end_point
      return if @start_point.distance(@end_point) < 0.1

      clear_preview

      model = Sketchup.active_model
      model.start_operation('Create Wall', true)

      attrs = current_attrs
      Sketchup.set_status_text("anchor=#{@anchor} t=#{@thickness} h=#{@height}", SB_PROMPT)

      group = build_wall_group(@start_point, @end_point, attrs, model)
      join_corners(group, model) if group

      model.commit_operation
    end

    def current_attrs
      {
        thickness: @thickness,
        height: @height,
        anchor: @anchor,
        wall_type: @wall_type_name,
        exterior_material: @exterior_material,
        interior_material: @interior_material,
        side_a_color: @side_a_color,
        side_b_color: @side_b_color,
        wall_category: @wall_category
      }
    end

    def build_wall_group(start_pt, end_pt, attrs, model)
      return nil if start_pt.distance(end_pt) < 0.1

      dx = end_pt.x - start_pt.x
      dy = end_pt.y - start_pt.y
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.001

      thickness = attrs[:thickness]
      height = attrs[:height]
      nx = -dy / len * thickness / 2
      ny = dx / len * thickness / 2

      if attrs[:anchor] == 'center'
        v_anchor = 'center'
        h_anchor = 'center'
      else
        parts = attrs[:anchor].split('-')
        v_anchor = parts[0]
        h_anchor = parts[1] || 'center'
      end

      case v_anchor
      when 'top'
        z_offset = -height
      when 'center'
        z_offset = -height / 2.0
      else
        z_offset = 0
      end

      case h_anchor
      when 'left'
        pt1 = Geom::Point3d.new(start_pt.x, start_pt.y, z_offset)
        pt2 = Geom::Point3d.new(end_pt.x, end_pt.y, z_offset)
        pt3 = Geom::Point3d.new(end_pt.x + nx * 2, end_pt.y + ny * 2, z_offset)
        pt4 = Geom::Point3d.new(start_pt.x + nx * 2, start_pt.y + ny * 2, z_offset)
      when 'right'
        pt1 = Geom::Point3d.new(start_pt.x - nx * 2, start_pt.y - ny * 2, z_offset)
        pt2 = Geom::Point3d.new(end_pt.x - nx * 2, end_pt.y - ny * 2, z_offset)
        pt3 = Geom::Point3d.new(end_pt.x, end_pt.y, z_offset)
        pt4 = Geom::Point3d.new(start_pt.x, start_pt.y, z_offset)
      else
        pt1 = Geom::Point3d.new(start_pt.x + nx, start_pt.y + ny, z_offset)
        pt2 = Geom::Point3d.new(end_pt.x + nx, end_pt.y + ny, z_offset)
        pt3 = Geom::Point3d.new(end_pt.x - nx, end_pt.y - ny, z_offset)
        pt4 = Geom::Point3d.new(start_pt.x - nx, start_pt.y - ny, z_offset)
      end

      group = model.active_entities.add_group
      group.name = 'InteriorPro_Wall'
      group.set_attribute('InteriorPro', 'type', 'wall')
      group.set_attribute('InteriorPro', 'wall_type', attrs[:wall_type])
      group.set_attribute('InteriorPro', 'height', height)
      group.set_attribute('InteriorPro', 'thickness', thickness)
      group.set_attribute('InteriorPro', 'exterior_material', attrs[:exterior_material])
      group.set_attribute('InteriorPro', 'interior_material', attrs[:interior_material])
      group.set_attribute('InteriorPro', 'side_a_color', attrs[:side_a_color])
      group.set_attribute('InteriorPro', 'side_b_color', attrs[:side_b_color])
      group.set_attribute('InteriorPro', 'anchor', attrs[:anchor])
      group.set_attribute('InteriorPro', 'start_x', start_pt.x.to_f)
      group.set_attribute('InteriorPro', 'start_y', start_pt.y.to_f)
      group.set_attribute('InteriorPro', 'end_x', end_pt.x.to_f)
      group.set_attribute('InteriorPro', 'end_y', end_pt.y.to_f)

      length_in = len.to_f
      gross_area_sqft = (length_in * height.to_f) / 144.0
      volume_cuft = (length_in * height.to_f * thickness.to_f) / 1728.0
      group.set_attribute('InteriorPro', 'id', generate_wall_id)
      group.set_attribute('InteriorPro', 'mark', '')
      group.set_attribute('InteriorPro', 'length_in', length_in)
      group.set_attribute('InteriorPro', 'gross_area_sqft', gross_area_sqft)
      group.set_attribute('InteriorPro', 'volume_cuft', volume_cuft)
      group.set_attribute('InteriorPro', 'wall_category', @wall_category)
      group.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      group.set_attribute('InteriorPro', 'plugin_version', '0.1')

      w_ents = group.entities
      pts = [pt1, pt2, pt3, pt4].uniq { |p| [p.x.round(4), p.y.round(4), p.z.round(4)] }
      if pts.length < 3
        group.erase!
        return nil
      end
      face = w_ents.add_face(pts)
      unless face
        group.erase!
        return nil
      end
      face.pushpull(-height)
      if attrs[:wall_category] == 'interior'
        apply_materials(face, attrs[:side_a_color], attrs[:side_b_color])
      else
        apply_materials(face, attrs[:exterior_material], attrs[:interior_material])
      end

      perp_corners = perpendicular_corners_xy(start_pt, end_pt, thickness, h_anchor)
      save_corners_attr(group, perp_corners) if perp_corners

      add_board_and_batten(group) if attrs[:exterior_material] == 'Board and Batten'

      group
    end

    def apply_materials(face, exterior_material, interior_material)
      mats = Sketchup.active_model.materials
      ext_mat = load_or_create_material(exterior_material)
      int_mat = load_or_create_material(interior_material)
      face.material = int_mat
      face.back_material = ext_mat
    end

    def load_or_create_material(name)
      mats = Sketchup.active_model.materials
      mat = mats[name]
      return mat if mat
      mat = mats.add(name)
      if name.start_with?('#')
        # Hex color (e.g. '#ffffff') — flat color material
        mat.color = Sketchup::Color.new(name)
      else
        # Named material — try to load texture from textures folder
        plugin_dir = File.dirname(__FILE__)
        texture_file = File.join(plugin_dir, 'textures', "#{name.downcase.gsub(' ', '_')}.jpg")
        if File.exist?(texture_file)
          mat.texture = texture_file
          mat.texture.size = 48 if mat.texture # 48 inches = 4 feet repeat
        end
      end
      mat
    end

    # Adds vertical batten boxes to the exterior face of a wall group.
    # Battens are 1.5" wide along the wall, 0.75" protruding outward, full wall
    # height, centered every 16" along the exterior face length. Painted white.
    # Z range is read from group.bounds so this works for both build paths
    # (build_wall_group extrudes down; build_geometry_in_group extrudes up).
    def add_board_and_batten(group)
      return unless group&.valid?

      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      return unless sx && sy && ex && ey

      corners = read_corners_attr(group)
      return unless corners

      # Exterior corners (right perpendicular of drawn start->end direction).
      s_neg = corners[3]
      e_neg = corners[2]

      dx = e_neg[0] - s_neg[0]
      dy = e_neg[1] - s_neg[1]
      wall_length = Math.sqrt(dx**2 + dy**2)
      return if wall_length < 0.001

      # Unit vector along the exterior face from s_neg toward e_neg.
      ux = dx / wall_length
      uy = dy / wall_length
      # Outward perpendicular (right of u) = away from wall body.
      rx = uy
      ry = -ux

      white_mat = load_or_create_material('#ffffff')

      # Paint the wall's exterior long face white BEFORE adding battens, so
      # the boards (wall surface between battens) read as painted siding.
      # Doing this before the loop guarantees the batten snapshot-diff sees
      # the painted wall face as pre-existing and doesn't repaint it.
      outward = Geom::Vector3d.new(rx, ry, 0)
      group.entities.grep(Sketchup::Face).each do |f|
        n = f.normal
        next if n.z.abs > 0.5         # skip top/bottom
        next if n.dot(outward) < 0.5  # skip interior face + end caps
        f.material = white_mat
        f.back_material = nil
      end

      z_min = group.bounds.min.z
      z_max = group.bounds.max.z
      h = z_max - z_min
      return if h < 0.001

      batten_width = 1.5
      batten_depth = 0.75
      spacing      = 16.0
      half_width   = batten_width / 2.0

      center_offset = spacing / 2.0
      while center_offset + half_width <= wall_length
        cx = s_neg[0] + ux * center_offset
        cy = s_neg[1] + uy * center_offset

        p1 = Geom::Point3d.new(cx - ux * half_width,
                               cy - uy * half_width,
                               z_min)
        p2 = Geom::Point3d.new(cx + ux * half_width,
                               cy + uy * half_width,
                               z_min)
        p3 = Geom::Point3d.new(cx + ux * half_width + rx * batten_depth,
                               cy + uy * half_width + ry * batten_depth,
                               z_min)
        p4 = Geom::Point3d.new(cx - ux * half_width + rx * batten_depth,
                               cy - uy * half_width + ry * batten_depth,
                               z_min)

        existing_faces = group.entities.grep(Sketchup::Face).to_a
        face = group.entities.add_face(p1, p2, p3, p4)
        if face
          sign = face.normal.z >= 0 ? 1 : -1
          face.pushpull(h * sign)

          new_faces = group.entities.grep(Sketchup::Face).to_a - existing_faces
          new_faces.each do |f|
            f.material = white_mat
            f.back_material = white_mat
          end
        end

        center_offset += spacing
      end
    end

    # Miter both ends of a newly-created wall against any existing wall whose
    # centerline endpoint is within tolerance. Geometry of BOTH walls in each
    # corner pair is rebuilt with the computed miter intersections.
    def join_corners(new_group, model, allow_centerline_fallback: false)
      return unless new_group&.valid?
      data = wall_data_world(new_group)
      return unless data

      [:start, :end].each do |side|
        break unless new_group.valid?
        corner = endpoint_pt(data, side)
        other  = find_neighbor_at(corner, new_group, model, allow_centerline_fallback: allow_centerline_fallback)
        next unless other
        butt_applied = apply_miter(new_group, side, other[:group], other[:side], model)
        next if butt_applied  # If butt joint was applied, skip further processing for this side.
        data = wall_data_world(new_group)
        break unless data
      end
    end

    # Two-pass neighbor search:
    #
    #  Pass 1 (tight): the caller's `point` should coincide with a candidate's
    #  DRAWN endpoint within 0.001". Matches legacy behavior and handles
    #  freshly-drawn walls whose drawn lines actually meet (the common case
    #  for create_wall and the wall-edit dialog — unchanged from before).
    #
    #  Pass 2 (centerline fallback): if pass 1 finds nothing, treat `point`
    #  as a drawn endpoint and look for a candidate whose CENTERLINE endpoint
    #  lands within max(t_a, t_b)/2 + 0.001" of it. This handles the merge
    #  case where two walls meeting at the same physical corner can have
    #  drawn endpoints separated by up to (t_a + t_b)/2 when their h_anchors
    #  put the drawn lines on opposite sides of the centerlines.
    def find_neighbor_at(point, exclude_group, model, allow_centerline_fallback: false)
      candidates = []
      model.active_entities.grep(Sketchup::Group).each do |g|
        next if g == exclude_group
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'wall'
        data = wall_data_world(g)
        next unless data
        candidates << [g, data]
      end

      # Pass 1: drawn-to-drawn, tol = 0.001
      tol = 0.001
      best = nil
      best_dist = tol
      candidates.each do |g, data|
        ws = Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0)
        we = Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0)
        d_s = point.distance(ws)
        if d_s < best_dist
          best_dist = d_s
          best = { group: g, side: :start, data: data }
        end
        d_e = point.distance(we)
        if d_e < best_dist
          best_dist = d_e
          best = { group: g, side: :end, data: data }
        end
      end
      return best if best
      return nil unless allow_centerline_fallback

      # Pass 2: point-vs-centerline, tol scaled by thickness.
      thickness_a = exclude_group.get_attribute('InteriorPro', 'thickness').to_f
      excl_data = wall_data_world(exclude_group)
      excl_cl = excl_data &&
                [Geom::Point3d.new(excl_data[:cl_start][0], excl_data[:cl_start][1], 0),
                 Geom::Point3d.new(excl_data[:cl_end][0],   excl_data[:cl_end][1],   0)]
      best_dist_p2 = Float::INFINITY
      candidates.each do |g, data|
        tol_p2 = thickness_a + data[:thickness].to_f + 0.001

        # Guard: skip unless the two centerlines actually intersect within
        # 0.5" of `point` -- rejects walls that are merely near but not joined.
        next unless excl_cl
        cand_cl = [Geom::Point3d.new(data[:cl_start][0], data[:cl_start][1], 0),
                   Geom::Point3d.new(data[:cl_end][0],   data[:cl_end][1],   0)]
        cl_hit = Geom.intersect_line_line(excl_cl, cand_cl)
        next if cl_hit.nil? || cl_hit.distance(point) > [thickness_a, data[:thickness].to_f].max

        cs = Geom::Point3d.new(data[:cl_start][0], data[:cl_start][1], 0)
        ce = Geom::Point3d.new(data[:cl_end][0],   data[:cl_end][1],   0)
        d_cs = point.distance(cs)
        if d_cs < tol_p2 && d_cs < best_dist_p2
          best_dist_p2 = d_cs
          best = { group: g, side: :start, data: data }
        end
        d_ce = point.distance(ce)
        if d_ce < tol_p2 && d_ce < best_dist_p2
          best_dist_p2 = d_ce
          best = { group: g, side: :end, data: data }
        end
      end
      best
    end

    # Compute the 2 miter points (outside + inside) where two walls meet, and
    # rebuild both walls' geometry. Uses Geom.intersect_line_line on each pair
    # of side-edge lines.
    # All geometry math runs in world space so two walls living in different
    # group transformations meet correctly. The four world-space miter points
    # are then inverse-transformed back into each group's local frame before
    # being written to attributes / face geometry by apply_miter_to_wall.
    def apply_miter(group_a, side_a, group_b, side_b, model)
      # Returns true if butt joint was applied, false otherwise.
      data_a = wall_data_world(group_a)
      data_b = wall_data_world(group_b)
      return unless data_a && data_b

      cl_a_start = endpoint_pt(data_a, :start)
      cl_a_end   = endpoint_pt(data_a, :end)
      cl_b_start = endpoint_pt(data_b, :start)
      cl_b_end   = endpoint_pt(data_b, :end)

      u_a_nat = (cl_a_end - cl_a_start)
      u_b_nat = (cl_b_end - cl_b_start)
      return if u_a_nat.length < 0.001 || u_b_nat.length < 0.001
      u_a_nat.normalize!
      u_b_nat.normalize!

      # Direction INTO the corner (from A) and OUT of the corner (toward B).
      u_into = (side_a == :end)   ? u_a_nat : Geom::Vector3d.new(-u_a_nat.x, -u_a_nat.y, 0)
      u_out  = (side_b == :start) ? u_b_nat : Geom::Vector3d.new(-u_b_nat.x, -u_b_nat.y, 0)

      cross_z = u_into.x * u_out.y - u_into.y * u_out.x
      return if cross_z.abs < 1e-6  # collinear walls -- no real corner

      # Outward bisector at the corner (points to the convex/outside side).
      outside_dir = Geom::Vector3d.new(-u_into.x + u_out.x, -u_into.y + u_out.y, 0)
      return if outside_dir.length < 1e-6
      outside_dir.normalize!

      # +n perpendicular (left of natural start->end direction) for each wall.
      n_a = Geom::Vector3d.new(-u_a_nat.y, u_a_nat.x, 0)
      n_b = Geom::Vector3d.new(-u_b_nat.y, u_b_nat.x, 0)

      # Compute per-wall offsets from the drawn endpoint based on h_anchor.
      # For 'left': wall extends from drawn (offset 0) to +n*t (offset +t)
      # For 'right': wall extends from -n*t (offset -t) to drawn (offset 0)
      # For 'center' (default): wall extends from -n*t/2 to +n*t/2
      ha_a = data_a[:h_anchor]
      ha_b = data_b[:h_anchor]
      t_a_full = data_a[:thickness]
      t_b_full = data_b[:thickness]

      a_pos_off = (ha_a == 'left') ? t_a_full : ((ha_a == 'right') ? 0.0 : t_a_full / 2.0)
      a_neg_off = (ha_a == 'left') ? 0.0      : ((ha_a == 'right') ? -t_a_full : -t_a_full / 2.0)
      b_pos_off = (ha_b == 'left') ? t_b_full : ((ha_b == 'right') ? 0.0 : t_b_full / 2.0)
      b_neg_off = (ha_b == 'left') ? 0.0      : ((ha_b == 'right') ? -t_b_full : -t_b_full / 2.0)

      # Corner = intersection of the two centerlines; fall back to wall A's
      # endpoint if the lines are parallel and never cross.
      line_a = [cl_a_start, u_a_nat]
      line_b = [cl_b_start, u_b_nat]
      cl_intersect = Geom.intersect_line_line(line_a, line_b)
      corner = cl_intersect || ((side_a == :end) ? cl_a_end : cl_a_start)

      a_pos_line = [Geom::Point3d.new(corner.x + n_a.x * a_pos_off, corner.y + n_a.y * a_pos_off, 0), u_a_nat]
      a_neg_line = [Geom::Point3d.new(corner.x + n_a.x * a_neg_off, corner.y + n_a.y * a_neg_off, 0), u_a_nat]
      b_pos_line = [Geom::Point3d.new(corner.x + n_b.x * b_pos_off, corner.y + n_b.y * b_pos_off, 0), u_b_nat]
      b_neg_line = [Geom::Point3d.new(corner.x + n_b.x * b_neg_off, corner.y + n_b.y * b_neg_off, 0), u_b_nat]

      # Which side of each wall is on the convex (outside) of the corner.
      a_pos_outside = n_a.dot(outside_dir) > 0
      b_pos_outside = n_b.dot(outside_dir) > 0

      a_outside = a_pos_outside ? a_pos_line : a_neg_line
      a_inside  = a_pos_outside ? a_neg_line : a_pos_line
      b_outside = b_pos_outside ? b_pos_line : b_neg_line
      b_inside  = b_pos_outside ? b_neg_line : b_pos_line

      miter_outside = Geom.intersect_line_line(a_outside, b_outside)
      miter_inside  = Geom.intersect_line_line(a_inside,  b_inside)
      return unless miter_outside && miter_inside

      a_miter_pos = a_pos_outside ? miter_outside : miter_inside
      a_miter_neg = a_pos_outside ? miter_inside  : miter_outside
      b_miter_pos = b_pos_outside ? miter_outside : miter_inside
      b_miter_neg = b_pos_outside ? miter_inside  : miter_outside

      # Inverse-transform world miter points into each group's local frame
      # so apply_miter_to_wall writes attributes and face vertices that are
      # consistent with the group's own transformation. Pass the LOCAL
      # wall_data so the perpendicular-corner fallback inside
      # apply_miter_to_wall produces local-frame corners as well.
      xform_a_inv = group_a.transformation.inverse
      xform_b_inv = group_b.transformation.inverse
      apply_miter_to_wall(group_a, side_a,
                          a_miter_pos.transform(xform_a_inv),
                          a_miter_neg.transform(xform_a_inv),
                          wall_data(group_a))
      apply_miter_to_wall(group_b, side_b,
                          b_miter_pos.transform(xform_b_inv),
                          b_miter_neg.transform(xform_b_inv),
                          wall_data(group_b))
      false
    end

      def apply_butt_joint(group_a, side_a, group_b, side_b, data_a, data_b, u_a_nat, u_b_nat, n_a, n_b, ha_a, ha_b, t_a_full, t_b_full, cl_a_start, cl_a_end, cl_b_start, cl_b_end, corner)
        if t_a_full >= t_b_full
          thick_group = group_a; thick_side = side_a; thick_data = data_a; thick_u = u_a_nat; thick_n = n_a; thick_ha = ha_a; thick_t = t_a_full; thick_cl_s = cl_a_start; thick_cl_e = cl_a_end
          thin_group = group_b; thin_side = side_b; thin_data = data_b; thin_u = u_b_nat; thin_n = n_b; thin_ha = ha_b; thin_t = t_b_full; thin_cl_s = cl_b_start; thin_cl_e = cl_b_end
        else
          thick_group = group_b; thick_side = side_b; thick_data = data_b; thick_u = u_b_nat; thick_n = n_b; thick_ha = ha_b; thick_t = t_b_full; thick_cl_s = cl_b_start; thick_cl_e = cl_b_end
          thin_group = group_a; thin_side = side_a; thin_data = data_a; thin_u = u_a_nat; thin_n = n_a; thin_ha = ha_a; thin_t = t_a_full; thin_cl_s = cl_a_start; thin_cl_e = cl_a_end
        end
        thick_pos_off = (thick_ha == 'left') ? thick_t : ((thick_ha == 'right') ? 0.0 : thick_t / 2.0)
        thick_neg_off = (thick_ha == 'left') ? 0.0 : ((thick_ha == 'right') ? -thick_t : -thick_t / 2.0)
        thick_end_cl = (thick_side == :end) ? thick_cl_e : thick_cl_s
        thick_pos_world = Geom::Point3d.new(thick_end_cl.x + thick_n.x * thick_pos_off, thick_end_cl.y + thick_n.y * thick_pos_off, 0)
        thick_neg_world = Geom::Point3d.new(thick_end_cl.x + thick_n.x * thick_neg_off, thick_end_cl.y + thick_n.y * thick_neg_off, 0)
        to_corner = Geom::Vector3d.new(corner.x - thick_cl_s.x, corner.y - thick_cl_s.y, 0)
        side_sign = (to_corner.dot(thick_n) >= 0) ? 1.0 : -1.0
        face_offset = side_sign * (thick_t / 2.0)
        face_pt = Geom::Point3d.new(thick_cl_s.x + thick_n.x * face_offset, thick_cl_s.y + thick_n.y * face_offset, 0)
        thick_face_line = [face_pt, thick_u]
        thin_pos_off = (thin_ha == 'left') ? thin_t : ((thin_ha == 'right') ? 0.0 : thin_t / 2.0)
        thin_neg_off = (thin_ha == 'left') ? 0.0 : ((thin_ha == 'right') ? -thin_t : -thin_t / 2.0)
        thin_pos_line = [Geom::Point3d.new(thin_cl_s.x + thin_n.x * thin_pos_off, thin_cl_s.y + thin_n.y * thin_pos_off, 0), thin_u]
        thin_neg_line = [Geom::Point3d.new(thin_cl_s.x + thin_n.x * thin_neg_off, thin_cl_s.y + thin_n.y * thin_neg_off, 0), thin_u]
        thin_pos_world = Geom.intersect_line_line(thin_pos_line, thick_face_line)
        thin_neg_world = Geom.intersect_line_line(thin_neg_line, thick_face_line)
        unless thin_pos_world && thin_neg_world
          return
        end
        thick_xform_inv = thick_group.transformation.inverse
        thin_xform_inv = thin_group.transformation.inverse
        # Update both walls with butt joint geometry.
        apply_miter_to_wall(thick_group, thick_side, thick_pos_world.transform(thick_xform_inv), thick_neg_world.transform(thick_xform_inv), wall_data(thick_group))
        apply_miter_to_wall(thin_group, thin_side, thin_pos_world.transform(thin_xform_inv), thin_neg_world.transform(thin_xform_inv), wall_data(thin_group))
      end

    def apply_miter_to_wall(group, side, miter_pos, miter_neg, data)
      return unless group&.valid?
      corners = read_corners_attr(group) || compute_perpendicular_corners_from_data(data)
      return unless corners
      if side == :start
        corners[0] = [miter_pos.x, miter_pos.y]   # s_pos
        corners[3] = [miter_neg.x, miter_neg.y]   # s_neg
      else
        corners[1] = [miter_pos.x, miter_pos.y]   # e_pos
        corners[2] = [miter_neg.x, miter_neg.y]   # e_neg
      end
      save_corners_attr(group, corners)
      rebuild_wall_geometry(group, corners, data)
    end

    def compute_perpendicular_corners_from_data(data)
      drawn_start = Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0)
      drawn_end   = Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0)
      perpendicular_corners_xy(drawn_start, drawn_end, data[:thickness], data[:h_anchor])
    end

    def rebuild_wall_geometry(group, corners_xy, data)
      return unless group&.valid?
      group.entities.clear!
      build_geometry_in_group(group, corners_xy, data[:z_offset], data[:height],
                              data[:ext_mat], data[:int_mat])
    end

    def build_geometry_in_group(group, corners_xy, z_offset, height, ext_mat, int_mat)
      pts = corners_xy.map { |c| Geom::Point3d.new(c[0], c[1], z_offset) }
      uniq_pts = pts.uniq { |p| [p.x.round(4), p.y.round(4), p.z.round(4)] }
      return false if uniq_pts.length < 3
      face = group.entities.add_face(uniq_pts)
      return false unless face
      sign = face.normal.z >= 0 ? 1 : -1
      face.pushpull(height * sign)
      # Apply materials only to the two long faces (interior/exterior), leave top/bottom/ends unpainted
      if ext_mat && int_mat
        sx = group.get_attribute('InteriorPro', 'start_x')
        sy = group.get_attribute('InteriorPro', 'start_y')
        ex = group.get_attribute('InteriorPro', 'end_x')
        ey = group.get_attribute('InteriorPro', 'end_y')
        if sx && sy && ex && ey
          dir = Geom::Vector3d.new(ex - sx, ey - sy, 0)
          if dir.length > 0.001
            dir.normalize!
            # Right perpendicular = exterior side (clockwise drawing convention)
            right = Geom::Vector3d.new(dir.y, -dir.x, 0)
            ext_material = load_or_create_material(ext_mat)
            int_material = load_or_create_material(int_mat)
            group.entities.grep(Sketchup::Face).each do |f|
              n = f.normal
              # Skip top and bottom faces (vertical normals)
              next if n.z.abs > 0.5
              # Skip end caps (normal parallel to wall direction)
              next if n.dot(dir).abs > 0.5
              # This is a long face - paint based on side
              if n.dot(right) > 0
                f.material = ext_material
                f.back_material = nil
              else
                f.material = int_material
                f.back_material = nil
              end
            end
          end
        end
      end
      add_board_and_batten(group) if ext_mat == 'Board and Batten'
      true
    end

    def wall_data(group)
      return nil unless group&.valid?
      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      return nil unless sx && sy && ex && ey
      thickness = group.get_attribute('InteriorPro', 'thickness').to_f
      height    = group.get_attribute('InteriorPro', 'height').to_f
      anchor    = group.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      ext_mat   = group.get_attribute('InteriorPro', 'exterior_material')
      int_mat   = group.get_attribute('InteriorPro', 'interior_material')
      wall_category = group.get_attribute('InteriorPro', 'wall_category') || 'exterior'
      if wall_category == 'interior'
        side_a = group.get_attribute('InteriorPro', 'side_a_color') || '#ffffff'
        side_b = group.get_attribute('InteriorPro', 'side_b_color') || '#ffffff'
        ext_mat = side_a
        int_mat = side_b
      end
      v_anchor, h_anchor = parse_anchor(anchor)

      cl_offset = case h_anchor
                  when 'left'  then  thickness / 2.0
                  when 'right' then -thickness / 2.0
                  else 0.0
                  end
      dx = ex - sx
      dy = ey - sy
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.001
      nx = -dy / len
      ny =  dx / len
      cl_start = [sx + nx * cl_offset, sy + ny * cl_offset]
      cl_end   = [ex + nx * cl_offset, ey + ny * cl_offset]

      {
        group:       group,
        drawn_start: [sx, sy],
        drawn_end:   [ex, ey],
        cl_start:    cl_start,
        cl_end:      cl_end,
        thickness:   thickness,
        height:      height,
        anchor:      anchor,
        v_anchor:    v_anchor,
        h_anchor:    h_anchor,
        z_offset:    z_offset_for(v_anchor, height),
        ext_mat:     ext_mat,
        int_mat:     int_mat
      }
    end

    # Same shape as wall_data, but with the four point fields transformed by
    # the group's transformation so they live in the parent's (world) frame.
    # Scalar fields (thickness, height, anchors, materials, z_offset) are
    # frame-independent and pass through unchanged. Used by the miter pipeline
    # so endpoints from two groups with different transformations can be
    # compared and intersected in a single coordinate system.
    def wall_data_world(group)
      data = wall_data(group)
      return nil unless data
      xform = group.transformation
      return data if xform.identity?
      s  = Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0).transform(xform)
      e  = Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0).transform(xform)
      cs = Geom::Point3d.new(data[:cl_start][0],    data[:cl_start][1],    0).transform(xform)
      ce = Geom::Point3d.new(data[:cl_end][0],      data[:cl_end][1],      0).transform(xform)
      data.merge(
        drawn_start: [s.x,  s.y],
        drawn_end:   [e.x,  e.y],
        cl_start:    [cs.x, cs.y],
        cl_end:      [ce.x, ce.y]
      )
    end

    def endpoint_pt(data, side)
      arr = side == :start ? data[:drawn_start] : data[:drawn_end]
      Geom::Point3d.new(arr[0], arr[1], 0)
    end

    def parse_anchor(anchor)
      return ['center', 'center'] if anchor == 'center'
      parts = anchor.to_s.split('-')
      [parts[0] || 'bottom', parts[1] || 'center']
    end

    def z_offset_for(v_anchor, height)
      case v_anchor
      when 'top'    then -height
      when 'center' then -height / 2.0
      else 0.0
      end
    end

    # 4 floor-plane corners in canonical order: [s_pos, e_pos, e_neg, s_neg]
    # where +n is the left perpendicular of the natural start->end direction.
    def perpendicular_corners_xy(start_pt, end_pt, thickness, h_anchor)
      dx = end_pt.x - start_pt.x
      dy = end_pt.y - start_pt.y
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.001
      half = thickness / 2.0
      nx = -dy / len * half
      ny =  dx / len * half

      case h_anchor
      when 'left'
        s_pos = [start_pt.x + nx * 2, start_pt.y + ny * 2]
        e_pos = [end_pt.x   + nx * 2, end_pt.y   + ny * 2]
        e_neg = [end_pt.x,            end_pt.y]
        s_neg = [start_pt.x,          start_pt.y]
      when 'right'
        s_pos = [start_pt.x,                start_pt.y]
        e_pos = [end_pt.x,                  end_pt.y]
        e_neg = [end_pt.x   - nx * 2,       end_pt.y   - ny * 2]
        s_neg = [start_pt.x - nx * 2,       start_pt.y - ny * 2]
      else
        s_pos = [start_pt.x + nx, start_pt.y + ny]
        e_pos = [end_pt.x   + nx, end_pt.y   + ny]
        e_neg = [end_pt.x   - nx, end_pt.y   - ny]
        s_neg = [start_pt.x - nx, start_pt.y - ny]
      end
      [s_pos, e_pos, e_neg, s_neg]
    end

    def save_corners_attr(group, corners_xy)
      group.set_attribute('InteriorPro', 'corners_xy', corners_xy.flatten)
    end

    def read_corners_attr(group)
      flat = group.get_attribute('InteriorPro', 'corners_xy')
      return nil unless flat && flat.length == 8
      [[flat[0], flat[1]], [flat[2], flat[3]], [flat[4], flat[5]], [flat[6], flat[7]]]
    end

    def generate_wall_id
      require 'securerandom'
      SecureRandom.uuid
    rescue StandardError
      "wall-#{Time.now.to_f}-#{rand(1_000_000)}"
    end

    def finish_drawing
      clear_preview
      @drawing = false
      @start_point = nil
      @end_point = nil
      Sketchup.active_model.select_tool(nil)
    end
  end
end

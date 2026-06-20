# Interior Pro - Door edit / move / delete operations

module InteriorPro
  module DoorManager

    def self.door_entity?(entity)
      return false unless entity&.valid?
      return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      entity.get_attribute('InteriorPro', 'type') == 'door'
    end

    def self.find_door_in_path(path)
      return nil unless path
      path.reverse.find { |e| door_entity?(e) }
    end

    def self.find_wall_by_id(model, wall_id)
      return nil if wall_id.to_s.empty?
      search_entities(model.entities) do |e|
        e.is_a?(Sketchup::Group) &&
          e.get_attribute('InteriorPro', 'type') == 'wall' &&
          e.get_attribute('InteriorPro', 'id') == wall_id
      end
    end

    def self.search_entities(entities, &block)
      entities.each do |e|
        return e if block.call(e)
        if e.is_a?(Sketchup::Group)
          found = search_entities(e.entities, &block)
          return found if found
        elsif e.is_a?(Sketchup::ComponentInstance)
          found = search_entities(e.definition.entities, &block)
          return found if found
        end
      end
      nil
    end

    def self.settings_from_door(door)
      {
        'door_category'         => door.get_attribute('InteriorPro', 'door_category', 'exterior'),
        'door_type'             => door.get_attribute('InteriorPro', 'door_type', 'French Hinged'),
        'width'                 => door.get_attribute('InteriorPro', 'width_in', 36).to_f,
        'height'                => door.get_attribute('InteriorPro', 'height_in', 80).to_f,
        'frame_width'           => door.get_attribute('InteriorPro', 'frame_width_in', 1.5).to_f,
        'glass_frame_width'     => door.get_attribute('InteriorPro', 'glass_frame_width_in', 5).to_f,
        'interior_depth'        => door.get_attribute('InteriorPro', 'interior_depth_in', 1).to_f,
        'floor_offset'          => door.get_attribute('InteriorPro', 'floor_offset_in', 0).to_f,
        'swing_direction'       => door.get_attribute('InteriorPro', 'swing_direction', 'left'),
        'swing_side'            => door.get_attribute('InteriorPro', 'swing_side', 'auto'),
        'slide_direction'       => door.get_attribute('InteriorPro', 'slide_direction', 'left'),
        'glass_grid_style'      => door.get_attribute('InteriorPro', 'glass_grid_style', '2x2'),
        'exterior_casing_style' => door.get_attribute('InteriorPro', 'exterior_casing_style', 'none'),
        'interior_casing_style' => door.get_attribute('InteriorPro', 'interior_casing_style', 'none'),
        'exterior_threshold'    => door.get_attribute('InteriorPro', 'exterior_threshold', true)
      }
    end

    def self.wall_geometry(wall_group)
      sx = wall_group.get_attribute('InteriorPro', 'start_x')
      sy = wall_group.get_attribute('InteriorPro', 'start_y')
      ex = wall_group.get_attribute('InteriorPro', 'end_x')
      ey = wall_group.get_attribute('InteriorPro', 'end_y')
      thickness = wall_group.get_attribute('InteriorPro', 'thickness').to_f
      wall_height = wall_group.get_attribute('InteriorPro', 'height').to_f
      anchor = wall_group.get_attribute('InteriorPro', 'anchor') || 'bottom-center'

      return nil unless sx && sy && ex && ey && thickness > 0 && wall_height > 0

      drawn_start = Geom::Point3d.new(sx, sy, 0)
      drawn_end = Geom::Point3d.new(ex, ey, 0)
      wall_vec = drawn_end - drawn_start
      wall_length = wall_vec.length
      return nil if wall_length < 0.1

      unit = wall_vec.clone
      unit.normalize!
      n = Geom::Vector3d.new(-unit.y, unit.x, 0)

      v_anchor, h_anchor = parse_anchor(anchor)
      center_offset = case h_anchor
                      when 'left'  then thickness / 2.0
                      when 'right' then -thickness / 2.0
                      else 0.0
                      end
      cline_start = Geom::Point3d.new(
        drawn_start.x + n.x * center_offset,
        drawn_start.y + n.y * center_offset,
        0
      )

      floor_z = case v_anchor
                when 'top'    then -wall_height
                when 'center' then -wall_height / 2.0
                else 0.0
                end

      {
        wall: wall_group,
        unit: unit,
        n: n,
        thickness: thickness,
        wall_height: wall_height,
        wall_length: wall_length,
        cline_start: cline_start,
        floor_z: floor_z,
        ceiling_z: floor_z + wall_height,
        n_side: -thickness / 2.0
      }
    end

    def self.parse_anchor(anchor)
      if anchor == 'center'
        ['center', 'center']
      else
        parts = anchor.split('-')
        [parts[0] || 'bottom', parts[1] || 'center']
      end
    end

    def self.opening_context(door, geo)
      t = door.get_attribute('InteriorPro', 'position_along_wall_in').to_f
      width = door.get_attribute('InteriorPro', 'width_in').to_f
      height = door.get_attribute('InteriorPro', 'height_in').to_f
      floor_offset = door.get_attribute('InteriorPro', 'floor_offset_in').to_f
      clicked_side = door.get_attribute('InteriorPro', 'clicked_side').to_i
      clicked_side = 1 if clicked_side == 0

      half_w = width / 2.0
      stored_bot = door.get_attribute('InteriorPro', 'bottom_z')
      stored_top = door.get_attribute('InteriorPro', 'top_z')
      if stored_bot && stored_top
        door_bot_z = stored_bot.to_f
        door_top_z = stored_top.to_f
      else
        door_bot_z = geo[:floor_z] + floor_offset
        door_top_z = door_bot_z + height
      end
      cx = geo[:cline_start].x + geo[:unit].x * t + geo[:n].x * geo[:n_side]
      cy = geo[:cline_start].y + geo[:unit].y * t + geo[:n].y * geo[:n_side]
      stored_fx = door.get_attribute('InteriorPro', 'face_x')
      stored_fy = door.get_attribute('InteriorPro', 'face_y')
      if !stored_fx.nil? && !stored_fy.nil?
        fx = stored_fx.to_f
        fy = stored_fy.to_f
      else
        fx, fy = opening_face_xy_from_center(cx, cy, clicked_side, geo)
      end
      outward = Geom::Vector3d.new(geo[:n].x * clicked_side, geo[:n].y * clicked_side, 0)

      {
        t: t,
        half_w: half_w,
        width: width,
        height: height,
        floor_offset: floor_offset,
        door_bot_z: door_bot_z,
        door_top_z: door_top_z,
        cx: cx,
        cy: cy,
        fx: fx,
        fy: fy,
        clicked_side: clicked_side,
        outward: outward
      }
    end

    # DoorTool cuts openings using the picked face point (fx, fy), not the jamb center (cx, cy).
    def self.opening_face_xy_from_center(cx, cy, clicked_side, geo)
      offset = clicked_side * geo[:thickness] / 2.0 - geo[:n_side]
      [cx + geo[:n].x * offset, cy + geo[:n].y * offset]
    end

    def self.opening_face_xy(ctx, geo, use_stored_face: true)
      if use_stored_face && !ctx[:fx].nil? && !ctx[:fy].nil?
        [ctx[:fx], ctx[:fy]]
      else
        cx = geo[:cline_start].x + geo[:unit].x * ctx[:t] + geo[:n].x * geo[:n_side]
        cy = geo[:cline_start].y + geo[:unit].y * ctx[:t] + geo[:n].y * geo[:n_side]
        opening_face_xy_from_center(cx, cy, ctx[:clicked_side], geo)
      end
    end

    def self.pick_point_for_opening(ctx, geo)
      fx, fy = opening_face_xy(ctx, geo, use_stored_face: false)
      Geom::Point3d.new(fx, fy, ctx[:door_bot_z])
    end

    def self.opening_data_for_ctx(wall_group, geo, ctx)
      tool = InteriorPro::DoorTool.new
      data = tool.build_opening_data(
        wall_group, geo,
        width: ctx[:width],
        height: ctx[:height],
        floor_offset: ctx[:floor_offset],
        t: ctx[:t],
        clicked_side: ctx[:clicked_side],
        fx: ctx[:fx],
        fy: ctx[:fy]
      )
      snap_opening_data_to_wall!(wall_group, data, geo, ctx)
      data
    end

    # Scan wall mesh near door position t — works when there are no SketchUp inner loops.
    def self.detect_opening_from_wall_geometry!(wall_group, data, geo, t)
      xform = wall_group.transformation
      unit = geo[:unit]
      n = geo[:n]
      cx = geo[:cline_start].x + unit.x * t + n.x * geo[:n_side]
      cy = geo[:cline_start].y + unit.y * t + n.y * geo[:n_side]
      original_half_w = data[:half_w]
      search_along = original_half_w + 3.0
      max_perp = geo[:thickness] * 1.5

      world_pts = []
      wall_group.entities.each do |ent|
        next unless ent.valid?
        if ent.is_a?(Sketchup::Face)
          ent.vertices.each { |v| world_pts << v.position.transform(xform) }
        elsif ent.is_a?(Sketchup::Edge)
          world_pts << ent.start.position.transform(xform)
          world_pts << ent.end.position.transform(xform)
        end
      end

      near = world_pts.uniq { |p| [p.x.round(3), p.y.round(3), p.z.round(3)] }.select do |p|
        along = (p.x - cx) * unit.x + (p.y - cy) * unit.y
        perp = (p.x - cx) * n.x + (p.y - cy) * n.y
        along.abs <= search_along && perp.abs <= max_perp
      end
      return false if near.length < 4

      z_min = near.map(&:z).min
      z_max = near.map(&:z).max
      return false if z_max - z_min < 1.0

      along_vals = near.map { |p| (p.x - cx) * unit.x + (p.y - cy) * unit.y }
      half_w = [along_vals.map(&:abs).max, original_half_w + 1.0].min
      return false if half_w < 1.0

      sx = sy = 0.0
      near.each { |p| sx += p.x; sy += p.y }
      nf = near.length.to_f
      fx = sx / nf
      fy = sy / nf

      data[:door_bot_z] = z_min
      data[:door_top_z] = z_max
      data[:half_w] = half_w
      data[:fx] = fx
      data[:fy] = fy
      data[:ux] = unit.x * half_w
      data[:uy] = unit.y * half_w
      data[:t] = t
      data[:picked_point] = Geom::Point3d.new(fx, fy, z_min)
      data[:mesh_pts] = near
      true
    end

    def self.fill_opening!(wall_group, ctx, geo)
      tool = InteriorPro::DoorTool.new
      data = tool.build_opening_data(
        wall_group, geo,
        width: ctx[:width],
        height: ctx[:height],
        floor_offset: ctx[:floor_offset],
        t: ctx[:t],
        clicked_side: ctx[:clicked_side],
        fx: ctx[:fx],
        fy: ctx[:fy]
      )
      if ctx[:door_bot_z] && ctx[:door_top_z]
        data[:door_bot_z] = ctx[:door_bot_z]
        data[:door_top_z] = ctx[:door_top_z]
        data[:picked_point] = Geom::Point3d.new(data[:fx], data[:fy], data[:door_bot_z])
      end
      data[:outward] = ctx[:outward]
      data[:clicked_side] = ctx[:clicked_side]
      tool.fill_wall_opening(wall_group, data, geo)
    end

    # Snap fill/cut data to the actual hole geometry on the wall.
    def self.snap_opening_data_to_wall!(wall_group, data, geo, ctx)
      tool = InteriorPro::DoorTool.new
      mid_z = (ctx[:door_bot_z] + ctx[:door_top_z]) / 2.0
      lp = tool.find_inner_loop_near_position(wall_group, geo, ctx[:t], mid_z, ctx[:half_w])
      lp ||= tool.find_opening_inner_loop(wall_group, data)

      if lp
        snap_opening_data_from_loop!(wall_group, data, geo, ctx, lp)
      else
        snap_opening_data_from_tunnel!(wall_group, data, geo, ctx, tool)
      end
    end

    def self.snap_opening_data_from_loop!(wall_group, data, geo, ctx, lp)
      xform = wall_group.transformation
      world_pts = lp.vertices.map { |v| v.position.transform(xform) }
      return if world_pts.empty?

      z_vals = world_pts.map(&:z)
      data[:door_bot_z] = z_vals.min
      data[:door_top_z] = z_vals.max

      unit = geo[:unit]
      sx = sy = 0.0
      world_pts.each { |p| sx += p.x; sy += p.y }
      n_pts = world_pts.length.to_f
      fx = sx / n_pts
      fy = sy / n_pts

      along_vals = world_pts.map { |p| (p.x - fx) * unit.x + (p.y - fy) * unit.y }
      half_w = along_vals.map(&:abs).max
      return if half_w < 0.1

      apply_snapped_xy!(data, geo, ctx, fx, fy, half_w, lp, wall_group, xform)
    end

    def self.snap_opening_data_from_tunnel!(wall_group, data, geo, ctx, tool)
      detect_opening_from_wall_geometry!(wall_group, data, geo, ctx[:t])
    end

    def self.apply_snapped_xy!(data, geo, ctx, fx, fy, half_w, lp, wall_group, xform)
      clicked_side = ctx[:clicked_side]
      unit = geo[:unit]
      data[:fx] = fx
      data[:fy] = fy
      data[:half_w] = half_w
      data[:ux] = unit.x * half_w
      data[:uy] = unit.y * half_w
      data[:picked_point] = Geom::Point3d.new(fx, fy, data[:door_bot_z])

      parent_face = if lp
                      wall_group.entities.grep(Sketchup::Face).find { |f| f.valid? && f.loops.include?(lp) }
                    end
      if parent_face
        n_world = parent_face.normal.transform(xform)
        outward = Geom::Vector3d.new(n_world.x, n_world.y, 0)
        if outward.length > 0.001
          outward.normalize!
          data[:outward] = outward
          dot = data[:n].x * outward.x + data[:n].y * outward.y
          data[:clicked_side] = dot >= 0 ? 1 : -1
        else
          data[:outward] = Geom::Vector3d.new(geo[:n].x * clicked_side, geo[:n].y * clicked_side, 0)
        end
      else
        data[:outward] = Geom::Vector3d.new(geo[:n].x * clicked_side, geo[:n].y * clicked_side, 0)
      end
    end

    def self.unlink_door(wall_group, door_id)
      return unless wall_group && door_id
      connected = (wall_group.get_attribute('InteriorPro', 'connected_doors') || []).dup
      connected.delete(door_id)
      wall_group.set_attribute('InteriorPro', 'connected_doors', connected)
    end

    def self.validate_position(geo, ctx, t)
      half_w = ctx[:half_w]
      if t - half_w < 0 || t + half_w > geo[:wall_length]
        UI.messagebox(
          "Door does not fit at this position.\n\n" \
          "Wall length: #{geo[:wall_length].round(2)}\"\n" \
          "Door width: #{ctx[:width]}\""
        )
        return false
      end
      true
    end

    def self.delete_door(door)
      return false unless door_entity?(door)
      wall_id = door.get_attribute('InteriorPro', 'host_wall_id')
      door_id = door.get_attribute('InteriorPro', 'id')
      wall = find_wall_by_id(Sketchup.active_model, wall_id)
      geo = wall ? wall_geometry(wall) : nil
      ctx = (wall && geo) ? opening_context(door, geo) : nil

      model = Sketchup.active_model

      # Operation 1: erase the door. Committed on its own so a later fill
      # failure can never abort it and bring the door back.
      model.start_operation('Delete Door', true)
      begin
        erased = erase_door_entity!(door, door_id)
        unlink_door(wall, door_id) if wall
        puts "[DoorManager] delete: door_id=#{door_id.inspect} erased=#{erased}"
        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        puts "[DoorManager] delete erase error: #{e.message}"
        UI.messagebox("Error deleting door: #{e.message}")
        return false
      end

      # Operation 2: patch the wall opening. Independent — if it fails the door
      # is already gone.
      return true unless wall && geo && ctx

      model.start_operation('Patch Wall Opening', true)
      begin
        fill_ok = fill_opening!(wall, ctx, geo)
        model.commit_operation
        unless fill_ok
          puts '[DoorManager] delete: door erased but wall patch incomplete'
        end
      rescue => e
        model.abort_operation rescue nil
        puts "[DoorManager] delete patch error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
      true
    end

    # Erase the door instance. Falls back to searching the model by id so a
    # stale/duplicated reference can't leave a visible door behind.
    def self.erase_door_entity!(door, door_id)
      erased = false
      if door && door.valid?
        door.erase!
        erased = true
      end

      return erased if door_id.to_s.empty?

      model = Sketchup.active_model
      loop do
        leftover = search_entities(model.entities) do |e|
          door_entity?(e) && e.get_attribute('InteriorPro', 'id') == door_id
        end
        break unless leftover && leftover.valid?
        leftover.erase!
        erased = true
      end
      erased
    end

    def self.move_door(door, delta_t)
      return false unless door_entity?(door)
      delta_t = delta_t.to_f
      return true if delta_t.abs < 0.001

      wall_id = door.get_attribute('InteriorPro', 'host_wall_id')
      wall = find_wall_by_id(Sketchup.active_model, wall_id)
      unless wall
        UI.messagebox('Host wall not found.')
        return false
      end

      geo = wall_geometry(wall)
      unless geo
        UI.messagebox('Wall geometry is invalid.')
        return false
      end

      ctx = opening_context(door, geo)
      settings = settings_from_door(door)
      new_t = ctx[:t] + delta_t
      new_ctx = ctx.merge(t: new_t)
      return false unless validate_position(geo, new_ctx, new_t)

      model = Sketchup.active_model
      model.start_operation('Move Door', true)
      begin
        fill_opening!(wall, ctx, geo) || (raise 'Could not patch the old opening in the wall.')

        tool = InteriorPro::DoorTool.new
        InteriorPro::DoorLibraryDialog.apply_to_tool(tool, settings)
        cut_data = tool.build_opening_data(
          wall, geo,
          width: settings['width'],
          height: settings['height'],
          floor_offset: settings['floor_offset'],
          t: new_t,
          clicked_side: ctx[:clicked_side]
        )
        tool.cut_opening_from_data(wall, cut_data, geo) || (raise 'Could not cut the new opening.')

        old_origin = door.transformation.origin
        new_cx = geo[:cline_start].x + geo[:unit].x * new_t + geo[:n].x * geo[:n_side]
        new_cy = geo[:cline_start].y + geo[:unit].y * new_t + geo[:n].y * geo[:n_side]
        new_origin = Geom::Point3d.new(new_cx, new_cy, old_origin.z)
        door.transform!(Geom::Transformation.translation(new_origin - old_origin))
        door.set_attribute('InteriorPro', 'position_along_wall_in', new_t)
        door.set_attribute('InteriorPro', 'face_x', cut_data[:fx])
        door.set_attribute('InteriorPro', 'face_y', cut_data[:fy])
        door.set_attribute('InteriorPro', 'bottom_z', cut_data[:door_bot_z])
        door.set_attribute('InteriorPro', 'top_z', cut_data[:door_top_z])

        model.commit_operation
        true
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Error moving door: #{e.message}")
        false
      end
    end

    def self.update_door(door, settings)
      return false unless door_entity?(door)

      wall_id = door.get_attribute('InteriorPro', 'host_wall_id')
      door_id = door.get_attribute('InteriorPro', 'id')
      wall = find_wall_by_id(Sketchup.active_model, wall_id)
      unless wall
        UI.messagebox('Host wall not found.')
        return false
      end

      geo = wall_geometry(wall)
      unless geo
        UI.messagebox('Wall geometry is invalid.')
        return false
      end

      ctx = opening_context(door, geo)
      door_mark = door.get_attribute('InteriorPro', 'mark')
      settings = settings.transform_keys(&:to_s)
      new_half = settings['width'].to_f / 2.0
      new_ctx = ctx.merge(
        half_w: new_half,
        width: settings['width'].to_f,
        height: settings['height'].to_f,
        floor_offset: settings['floor_offset'].to_f
      )
      new_ctx[:door_bot_z] = geo[:floor_z] + new_ctx[:floor_offset]
      new_ctx[:door_top_z] = new_ctx[:door_bot_z] + new_ctx[:height]
      return false unless validate_position(geo, new_ctx, ctx[:t])
      if new_ctx[:door_top_z] > geo[:ceiling_z] + 0.001
        UI.messagebox('Door height does not fit in the wall.')
        return false
      end

      model = Sketchup.active_model

      # If the OPENING geometry (width/height/floor_offset) is unchanged, only
      # the door body differs (type/casing/swing/glass). In that case DON'T touch
      # the wall at all — just swap the door component in the existing opening.
      # This is the robust path: patching + re-cutting the same wall region is
      # what distorts the wall.
      opening_unchanged =
        (new_ctx[:width] - ctx[:width]).abs < 0.001 &&
        (new_ctx[:height] - ctx[:height]).abs < 0.001 &&
        (new_ctx[:floor_offset] - ctx[:floor_offset]).abs < 0.001

      tool = InteriorPro::DoorTool.new
      InteriorPro::DoorLibraryDialog.apply_to_tool(tool, settings)

      if opening_unchanged
        puts '[DoorManager] edit: opening unchanged — swapping door body only (wall untouched)'
        model.start_operation('Edit Door', true)
        begin
          erase_door_entity!(door, door_id)
          unlink_door(wall, door_id)

          place_data = tool.build_opening_data(
            wall, geo,
            width: new_ctx[:width],
            height: new_ctx[:height],
            floor_offset: new_ctx[:floor_offset],
            t: ctx[:t],
            clicked_side: ctx[:clicked_side],
            fx: ctx[:fx],
            fy: ctx[:fy]
          )
          place_data[:outward] = ctx[:outward]

          unless tool.build_door_in_existing_opening(wall, place_data, mark: door_mark)
            raise 'Could not build the updated door body.'
          end
          model.commit_operation
          return true
        rescue => e
          model.abort_operation rescue nil
          puts "[DoorManager] edit body-swap error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          UI.messagebox("Error editing door: #{e.message}")
          return false
        end
      end

      # Opening size/offset changed → must patch old opening and cut a new one.
      # Operation 1: erase old door on its own so a later fill/cut failure can't
      # bring it back.
      model.start_operation('Edit Door — Remove', true)
      begin
        erased = erase_door_entity!(door, door_id)
        unlink_door(wall, door_id)
        puts "[DoorManager] edit: old door_id=#{door_id.inspect} erased=#{erased}"
        model.commit_operation
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Error editing door: #{e.message}")
        return false
      end

      # Operation 2: patch the old opening (independent).
      model.start_operation('Edit Door — Patch', true)
      begin
        fill_ok = fill_opening!(wall, ctx, geo)
        model.commit_operation
        puts '[DoorManager] edit: old opening patch incomplete' unless fill_ok
      rescue => e
        model.abort_operation rescue nil
        puts "[DoorManager] edit patch error: #{e.message}"
      end

      puts "[DoorManager] edit: placing type=#{tool.door_type.inspect} w=#{tool.width} h=#{tool.height}"

      place_data = tool.build_opening_data(
        wall, geo,
        width: new_ctx[:width],
        height: new_ctx[:height],
        floor_offset: new_ctx[:floor_offset],
        t: ctx[:t],
        clicked_side: ctx[:clicked_side],
        fx: ctx[:fx],
        fy: ctx[:fy]
      )
      place_data[:outward] = ctx[:outward]

      unless tool.cut_and_build_door_at(wall, place_data, geo, mark: door_mark)
        UI.messagebox('Error editing door: Could not place the updated door.')
        return false
      end
      true
    end

    def self.show_move_dialog(door)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Move Door',
        preferences_key: 'InteriorPro_DoorMove',
        width: 360,
        height: 300,
        resizable: false
      )

      html = <<~HTML
        <!DOCTYPE html><html><head><style>
          body{font-family:Arial,sans-serif;padding:16px;background:#f5f5f5;}
          h2{color:#5D4037;margin:0 0 8px;font-size:16px;}
          .hint{color:#666;font-size:12px;margin-bottom:12px;line-height:1.4;}
          label{display:block;font-size:13px;color:#555;}
          input{width:100%;padding:8px;margin-top:4px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;}
          .buttons{display:flex;gap:8px;margin-top:16px;}
          button{flex:1;padding:10px;border:none;border-radius:4px;font-size:14px;cursor:pointer;color:white;background:#5D4037;}
          button.cancel{background:#888;}
        </style></head><body>
        <h2>Move Door Along Wall</h2>
        <div class="hint">Positive = toward wall end. Negative = toward wall start.</div>
        <label>Distance (inches)</label>
        <input type="number" id="distance" value="0" step="0.5">
        <div class="buttons">
          <button onclick="applyMove()">Apply</button>
          <button class="cancel" onclick="sketchup.cancel()">Cancel</button>
        </div>
        <script>
          function applyMove(){
            sketchup.apply({distance: parseFloat(document.getElementById('distance').value) || 0});
          }
        </script>
        </body></html>
      HTML

      dialog.set_html(html)
      dialog.add_action_callback('apply') { |_, params|
        delta = params['distance'].to_f
        move_door(door, delta)
        dialog.close
      }
      dialog.add_action_callback('cancel') { |_| dialog.close }
      dialog.show
    end

  end
end

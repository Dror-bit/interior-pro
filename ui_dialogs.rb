# Interior Pro - UI Dialogs

module InteriorPro
  module UIDialogs

    MATERIALS = ['Brick', 'Stucco', 'Stone', 'Vertical Siding', 'Horizontal Siding', 'Plaster', 'Board and Batten']

    def self.wall_settings(tool)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Wall Settings',
        preferences_key: 'InteriorPro_WallSettings',
        width: 320,
        height: 420,
        resizable: false
      )
      html = build_wall_html(tool.height, tool.thickness, tool.exterior_material, tool.interior_material)
      dialog.set_html(html)
      dialog.add_action_callback('apply') { |_, params|
        tool.height = params['height'].to_f
        tool.thickness = params['thickness'].to_f
        tool.exterior_material = params['exterior']
        tool.interior_material = params['interior']
        tool.wall_category = params['wall_category']
        dialog.close
      }
      dialog.show
    end

    def self.wall_settings_standalone
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Wall Settings',
        preferences_key: 'InteriorPro_WallSettings',
        width: 320,
        height: 420,
        resizable: false
      )
      html = build_wall_html(96.0, 6.0, 'Stucco', '#ffffff')
      dialog.set_html(html)
      dialog.show
    end

    def self.wall_edit(group)
      height = group.get_attribute('InteriorPro', 'height', 96.0)
      thickness = group.get_attribute('InteriorPro', 'thickness', 6.0)
      ext_mat = group.get_attribute('InteriorPro', 'exterior_material', 'Stucco')
      int_mat = group.get_attribute('InteriorPro', 'interior_material', 'Gypsum')
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Edit Wall',
        preferences_key: 'InteriorPro_WallEdit',
        width: 320,
        height: 480,
        resizable: false
      )
      html = build_wall_html(height, thickness, ext_mat, int_mat, true)
      dialog.set_html(html)
      dialog.add_action_callback('apply') { |_, params|
        model = Sketchup.active_model
        model.start_operation('Edit Wall', true)
        group.set_attribute('InteriorPro', 'height', params['height'].to_f)
        group.set_attribute('InteriorPro', 'thickness', params['thickness'].to_f)
        group.set_attribute('InteriorPro', 'exterior_material', params['exterior'])
        group.set_attribute('InteriorPro', 'interior_material', params['interior'])
        # Rebuild geometry with updated attributes. Uses stored corners (preserves
        # miters); thickness-driven corner recompute is deferred — see TODO.
        wt = InteriorPro::WallTool.new
        data = wt.wall_data(group)
        if data
          # Recompute corners from current thickness (drops any existing miter).
          corners = wt.compute_perpendicular_corners_from_data(data)
          if corners
            wt.save_corners_attr(group, corners)
            wt.rebuild_wall_geometry(group, corners, data)
          end
          # Re-join corners to handle thickness changes with neighboring walls.
          wt.join_corners(group, model, allow_centerline_fallback: true)
        end
        model.commit_operation
        dialog.close
      }
      dialog.show
    end

    def self.wall_move(group)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Move Wall',
        preferences_key: 'InteriorPro_WallMove',
        width: 360,
        height: 280,
        resizable: false
      )

      html  = "<!DOCTYPE html><html><head><style>"
      html += "body{font-family:Arial,sans-serif;padding:16px;background:#f5f5f5;}"
      html += "h2{color:#333;margin-bottom:8px;font-size:16px;}"
      html += ".hint{color:#666;font-size:12px;margin-bottom:12px;}"
      html += "label{display:block;margin-top:0;font-size:13px;color:#555;}"
      html += "input[type=text]{width:100%;padding:6px;margin-top:4px;border:1px solid #ccc;border-radius:4px;font-size:13px;box-sizing:border-box;}"
      html += ".section{background:white;padding:12px;border-radius:6px;margin-bottom:12px;}"
      html += ".buttons{display:flex;gap:8px;}"
      html += "button{flex:1;padding:10px;background:#2196F3;color:white;border:none;border-radius:4px;font-size:14px;cursor:pointer;}"
      html += "button.cancel{background:#888;}"
      html += "button:hover{background:#1976D2;}"
      html += "button.cancel:hover{background:#666;}"
      html += "</style></head><body>"
      html += "<h2>Move Wall</h2>"
      html += "<div class='hint'>Positive = outward, negative = inward.</div>"
      html += "<div class='section'>"
      html += "<label>Distance</label><input type='text' id='distance' value='0'>"
      html += "</div>"
      html += "<div class='buttons'>"
      html += "<button onclick='applyMove()'>Apply</button>"
      html += "<button class='cancel' onclick='sketchup.cancel()'>Cancel</button>"
      html += "</div>"
      html += "<script>function applyMove(){sketchup.apply({distance:document.getElementById('distance').value});}"
      html += "document.getElementById('distance').addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();applyMove();}});</script>"
      html += "</body></html>"

      dialog.set_html(html)

      dialog.add_action_callback('apply') { |_, params|
        raw = params['distance'].to_s.strip
        if raw.empty?
          UI.messagebox('Invalid distance')
          next
        end
        begin
          distance = raw.to_l.to_f
        rescue StandardError
          UI.messagebox('Invalid distance')
          next
        end
        model = Sketchup.active_model

        # Read OLD endpoints of the moving wall
        sx = group.get_attribute('InteriorPro', 'start_x').to_f
        sy = group.get_attribute('InteriorPro', 'start_y').to_f
        ex = group.get_attribute('InteriorPro', 'end_x').to_f
        ey = group.get_attribute('InteriorPro', 'end_y').to_f

        dx = ex - sx
        dy = ey - sy
        len = Math.sqrt(dx**2 + dy**2)
        if len < 0.001
          dialog.close
          next
        end

        nx = dx / len
        ny = dy / len
        # right perpendicular of start->end (exterior direction)
        rx =  ny
        ry = -nx
        ox = rx * distance
        oy = ry * distance

        new_sx = sx + ox
        new_sy = sy + oy
        new_ex = ex + ox
        new_ey = ey + oy

        # STEP 1: detect connected walls (endpoint within tol of OLD endpoints)
        tol = 0.1
        connections = []
        model.entities.grep(Sketchup::Group).each do |g|
          next if g == group
          next unless g.get_attribute('InteriorPro', 'type') == 'wall'
          osx = g.get_attribute('InteriorPro', 'start_x')
          osy = g.get_attribute('InteriorPro', 'start_y')
          oex = g.get_attribute('InteriorPro', 'end_x')
          oey = g.get_attribute('InteriorPro', 'end_y')
          next unless osx && osy && oex && oey
          osx = osx.to_f; osy = osy.to_f; oex = oex.to_f; oey = oey.to_f

          connections << { wall: g, which: :start, linked: :start } if Math.sqrt((osx - sx)**2 + (osy - sy)**2) < tol
          connections << { wall: g, which: :end,   linked: :start } if Math.sqrt((oex - sx)**2 + (oey - sy)**2) < tol
          connections << { wall: g, which: :start, linked: :end   } if Math.sqrt((osx - ex)**2 + (osy - ey)**2) < tol
          connections << { wall: g, which: :end,   linked: :end   } if Math.sqrt((oex - ex)**2 + (oey - ey)**2) < tol
        end
        by_wall = connections.group_by { |c| c[:wall] }

        # STEP 3: validate — would any connected wall become shorter than 1 inch?
        too_short = by_wall.any? do |w, conns|
          wsx = w.get_attribute('InteriorPro', 'start_x').to_f
          wsy = w.get_attribute('InteriorPro', 'start_y').to_f
          wex = w.get_attribute('InteriorPro', 'end_x').to_f
          wey = w.get_attribute('InteriorPro', 'end_y').to_f
          conns.each do |c|
            tx = c[:linked] == :start ? new_sx : new_ex
            ty = c[:linked] == :start ? new_sy : new_ey
            if c[:which] == :start
              wsx = tx; wsy = ty
            else
              wex = tx; wey = ty
            end
          end
          Math.sqrt((wex - wsx)**2 + (wey - wsy)**2) < 1.0
        end

        if too_short
          UI.messagebox('Move would make a connected wall too short. Cancelled.')
          dialog.close
          next
        end

        # STEP 4: apply
        model.start_operation('Move Wall', true)

        group.set_attribute('InteriorPro', 'start_x', new_sx)
        group.set_attribute('InteriorPro', 'start_y', new_sy)
        group.set_attribute('InteriorPro', 'end_x',   new_ex)
        group.set_attribute('InteriorPro', 'end_y',   new_ey)

        wt = InteriorPro::WallTool.new
        data = wt.wall_data(group)
        if data
          start_pt = Geom::Point3d.new(new_sx, new_sy, 0)
          end_pt   = Geom::Point3d.new(new_ex, new_ey, 0)
          corners = wt.perpendicular_corners_xy(start_pt, end_pt, data[:thickness], data[:h_anchor])
          if corners
            wt.save_corners_attr(group, corners)
            wt.rebuild_wall_geometry(group, corners, data)
          end
        end

        by_wall.each do |w, conns|
          conns.each do |c|
            tx = c[:linked] == :start ? new_sx : new_ex
            ty = c[:linked] == :start ? new_sy : new_ey
            if c[:which] == :start
              w.set_attribute('InteriorPro', 'start_x', tx)
              w.set_attribute('InteriorPro', 'start_y', ty)
            else
              w.set_attribute('InteriorPro', 'end_x', tx)
              w.set_attribute('InteriorPro', 'end_y', ty)
            end
          end
          w_data = wt.wall_data(w)
          next unless w_data
          w_start = Geom::Point3d.new(w_data[:drawn_start][0], w_data[:drawn_start][1], 0)
          w_end   = Geom::Point3d.new(w_data[:drawn_end][0],   w_data[:drawn_end][1],   0)
          w_corners = wt.perpendicular_corners_xy(w_start, w_end, w_data[:thickness], w_data[:h_anchor])
          if w_corners
            wt.save_corners_attr(w, w_corners)
            wt.rebuild_wall_geometry(w, w_corners, w_data)
          end
        end

        wt.join_corners(group, model)
        by_wall.each_key { |w| wt.join_corners(w, model) }

        model.commit_operation
        dialog.close
        Sketchup.active_model.active_view.invalidate
      }

      dialog.add_action_callback('cancel') { |_, _| dialog.close }

      dialog.show
    end

    def self.wall_edit_multi(walls, all_mode: false)
      return if walls.nil? || walls.empty?
      first = walls.first
      height    = first.get_attribute('InteriorPro', 'height', 96.0)
      thickness = first.get_attribute('InteriorPro', 'thickness', 6.0)
      ext_mat   = first.get_attribute('InteriorPro', 'exterior_material', 'Stucco')
      int_mat   = first.get_attribute('InteriorPro', 'interior_material', '#ffffff')
      wall_category = first.get_attribute('InteriorPro', 'wall_category', 'exterior')
      side_a_color  = first.get_attribute('InteriorPro', 'side_a_color', '#ffffff')
      side_b_color  = first.get_attribute('InteriorPro', 'side_b_color', '#ffffff')
      int_color = (int_mat.is_a?(String) && int_mat.start_with?('#')) ? int_mat : '#ffffff'
      count = walls.length

      dialog = UI::HtmlDialog.new(
        dialog_title: "Edit #{count} Walls",
        preferences_key: 'InteriorPro_WallEditMulti',
        width: 360,
        height: 520,
        resizable: false
      )

      mat_options = MATERIALS.map { |m| "<option value='#{m}' #{m == ext_mat ? 'selected' : ''}>#{m}</option>" }.join

      html  = "<!DOCTYPE html><html><head><style>"
      html += "body{font-family:Arial,sans-serif;padding:16px;background:#f5f5f5;}"
      html += "h2{color:#333;margin-bottom:8px;font-size:16px;}"
      html += ".hint{color:#666;font-size:12px;margin-bottom:12px;}"
      html += "label{display:block;margin-top:0;font-size:13px;color:#555;}"
      html += "input[type=number],input[type=color],select{width:100%;padding:6px;margin-top:4px;border:1px solid #ccc;border-radius:4px;font-size:13px;box-sizing:border-box;}"
      html += "input[type=color]{height:36px;padding:2px;}"
      html += ".section{background:white;padding:12px;border-radius:6px;margin-bottom:12px;}"
      html += ".row{display:flex;align-items:flex-start;gap:10px;margin-bottom:10px;}"
      html += ".row > input[type=checkbox]{margin-top:6px;flex:0 0 auto;}"
      html += ".row > .field{flex:1;}"
      html += "button{width:100%;padding:10px;margin-top:8px;background:#2196F3;color:white;border:none;border-radius:4px;font-size:14px;cursor:pointer;}"
      html += "button:hover{background:#1976D2;}"
      html += "button.secondary{background:#4CAF50;margin-top:0;margin-bottom:12px;}"
      html += "button.secondary:hover{background:#388E3C;}"
      html += "</style></head><body>"
      if all_mode
        html += "<h2 style='background:#4CAF50;color:white;padding:10px;border-radius:6px;margin:-16px -16px 12px -16px;'>Editing ALL #{count} #{wall_category.capitalize} Walls</h2>"
      else
        html += "<h2>Edit #{count} Walls</h2>"
      end
      html += "<div class='hint'>Check a box to apply that change to all selected walls.</div>"
      unless all_mode
        html += "<button class='secondary' onclick='selectAllCategory()'>Edit All #{wall_category.capitalize} Walls in Model</button>"
      end
      html += "<div class='section'>"
      html += "<div class='row'><input type='checkbox' id='apply_height'>"
      html += "<div class='field'><label>Height (inches)</label><input type='number' id='height' value='#{height}' min='1' step='0.5'></div></div>"
      html += "<div class='row'><input type='checkbox' id='apply_thickness'>"
      html += "<div class='field'><label>Thickness (inches)</label><input type='number' id='thickness' value='#{thickness}' min='1' step='0.5'></div></div>"
      if wall_category == 'interior'
        html += "<div class='row'><input type='checkbox' id='apply_side_a'>"
        html += "<div class='field'><label>Side A Color (Right)</label><input type='color' id='sideAColor' value='#{side_a_color}'></div></div>"
        html += "<div class='row'><input type='checkbox' id='apply_side_b'>"
        html += "<div class='field'><label>Side B Color (Left)</label><input type='color' id='sideBColor' value='#{side_b_color}'></div></div>"
      else
        html += "<div class='row'><input type='checkbox' id='apply_exterior'>"
        html += "<div class='field'><label>Exterior Material</label><select id='exterior'>#{mat_options}</select></div></div>"
        html += "<div class='row'><input type='checkbox' id='apply_interior'>"
        html += "<div class='field'><label>Interior Color</label><input type='color' id='intColor' value='#{int_color}'></div></div>"
      end
      html += "</div>"
      html += "<button onclick='applySettings()'>Apply</button>"
      html += "<script>function applySettings(){sketchup.apply({"
      html += "apply_height:document.getElementById('apply_height').checked,"
      html += "height:document.getElementById('height').value,"
      html += "apply_thickness:document.getElementById('apply_thickness').checked,"
      html += "thickness:document.getElementById('thickness').value,"
      if wall_category == 'interior'
        html += "apply_side_a:document.getElementById('apply_side_a').checked,"
        html += "side_a:document.getElementById('sideAColor').value,"
        html += "apply_side_b:document.getElementById('apply_side_b').checked,"
        html += "side_b:document.getElementById('sideBColor').value"
      else
        html += "apply_exterior:document.getElementById('apply_exterior').checked,"
        html += "exterior:document.getElementById('exterior').value,"
        html += "apply_interior:document.getElementById('apply_interior').checked,"
        html += "interior:document.getElementById('intColor').value"
      end
      html += "});}"
      html += "function selectAllCategory(){sketchup.select_all_category();}</script>"
      html += "</body></html>"

      dialog.set_html(html)

      dialog.add_action_callback('select_all_category') { |_, _|
        model = Sketchup.active_model
        category = wall_category
        all_walls = []
        model.entities.each do |ent|
          next unless ent.is_a?(Sketchup::Group)
          next unless ent.get_attribute('InteriorPro', 'type', '') == 'wall'
          next unless ent.get_attribute('InteriorPro', 'wall_category', 'exterior') == category
          all_walls << ent
        end
        dialog.close
        UI.start_timer(0.1, false) {
          InteriorPro::UIDialogs.wall_edit_multi(all_walls, all_mode: true)
        }
      }

      dialog.add_action_callback('apply') { |_, params|
        truthy = ->(v) { v == true || v == 'true' }
        model = Sketchup.active_model
        model.start_operation("Edit #{count} Walls", true)
        wt = InteriorPro::WallTool.new
        walls.each do |group|
          next unless group&.valid?
          group.set_attribute('InteriorPro', 'height',            params['height'].to_f)    if truthy.call(params['apply_height'])
          group.set_attribute('InteriorPro', 'thickness',         params['thickness'].to_f) if truthy.call(params['apply_thickness'])
          group.set_attribute('InteriorPro', 'exterior_material', params['exterior'])       if truthy.call(params['apply_exterior'])
          group.set_attribute('InteriorPro', 'interior_material', params['interior'])       if truthy.call(params['apply_interior'])
          group.set_attribute('InteriorPro', 'side_a_color',      params['side_a'])         if truthy.call(params['apply_side_a'])
          group.set_attribute('InteriorPro', 'side_b_color',      params['side_b'])         if truthy.call(params['apply_side_b'])
          # Recompute corners from current attributes and re-join with neighbors.
          data = wt.wall_data(group)
          if data
            corners = wt.compute_perpendicular_corners_from_data(data)
            if corners
              wt.save_corners_attr(group, corners)
              wt.rebuild_wall_geometry(group, corners, data)
            end
            wt.join_corners(group, model, allow_centerline_fallback: true)
          end
        end
        model.commit_operation
        dialog.close
      }

      dialog.show
    end

    def self.build_wall_html(height, thickness, ext_mat, int_mat, edit_mode = false)
      title = edit_mode ? 'Edit Wall' : 'Wall Settings'
      mat_options = MATERIALS.map { |m| "<option value='#{m}' #{m == ext_mat ? 'selected' : ''}>#{m}</option>" }.join
      int_color = (int_mat.is_a?(String) && int_mat.start_with?('#')) ? int_mat : '#ffffff'
      html = "<!DOCTYPE html><html><head><style>"
      html += "body{font-family:Arial,sans-serif;padding:16px;background:#f5f5f5;}"
      html += "h2{color:#333;margin-bottom:16px;font-size:16px;}"
      html += "label{display:block;margin-top:12px;font-size:13px;color:#555;}"
      html += "input,select{width:100%;padding:6px;margin-top:4px;border:1px solid #ccc;border-radius:4px;font-size:13px;box-sizing:border-box;}"
      html += ".section{background:white;padding:12px;border-radius:6px;margin-bottom:12px;}"
      html += ".section-title{font-weight:bold;color:#444;margin-bottom:8px;font-size:13px;}"
      html += "button{width:100%;padding:10px;margin-top:16px;background:#2196F3;color:white;border:none;border-radius:4px;font-size:14px;cursor:pointer;}"
      html += "button:hover{background:#1976D2;}"
      html += "</style></head><body>"
      html += "<h2>#{title}</h2>"
      html += "<div class='section'><div class='section-title'>Dimensions</div>"
      html += "<div class='row'>"
      html += "<label>Wall Type</label>"
      html += "<input type='radio' name='wall_type' value='exterior' checked> Exterior"
      html += "<input type='radio' name='wall_type' value='interior'> Interior"
      html += "</div>"
      html += "<label>Height (inches)</label><input type='number' id='height' value='#{height}' min='1' step='0.5'>"
      html += "<label>Thickness (inches)</label><input type='number' id='thickness' value='#{thickness}' min='1' step='0.5'>"
      html += "</div>"
      html += "<div class='section'><div class='section-title'>Materials</div>"
      html += "<label>Exterior Material</label><select id='exterior'>#{mat_options}</select>"
      html += "<label>Interior Color</label><input type='color' id='intColor' value='#{int_color}' style='width:100%; height:36px; padding:2px; border:1px solid #ccc; border-radius:4px;'>"
      html += "</div>"
      html += "<button onclick='applySettings()'>Apply</button>"
      html += "<script>function applySettings(){var wallType = document.querySelector('input[name=\"wall_type\"]:checked').value; sketchup.apply({wall_category:wallType,height:document.getElementById('height').value,thickness:document.getElementById('thickness').value,exterior:document.getElementById('exterior').value,interior:document.getElementById('intColor').value});}</script>"
      html += "</body></html>"
      html
    end

  end
end

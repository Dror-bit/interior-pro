# Interior Pro - UI Dialogs

module InteriorPro
  module UIDialogs

    MATERIALS = ['Stucco', 'Brick', 'Siding', 'Concrete', 'Wood', 'Gypsum', 'Tile', 'Stone']

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
      html = build_wall_html(96.0, 6.0, 'Stucco', 'Gypsum')
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
        model.commit_operation
        dialog.close
      }
      dialog.show
    end

    def self.build_wall_html(height, thickness, ext_mat, int_mat, edit_mode = false)
      title = edit_mode ? 'Edit Wall' : 'Wall Settings'
      mat_options = MATERIALS.map { |m| "<option value='#{m}' #{m == ext_mat ? 'selected' : ''}>#{m}</option>" }.join
      int_options = MATERIALS.map { |m| "<option value='#{m}' #{m == int_mat ? 'selected' : ''}>#{m}</option>" }.join
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
      html += "<label>Height (inches)</label><input type='number' id='height' value='#{height}' min='1' step='0.5'>"
      html += "<label>Thickness (inches)</label><input type='number' id='thickness' value='#{thickness}' min='1' step='0.5'>"
      html += "</div>"
      html += "<div class='section'><div class='section-title'>Materials</div>"
      html += "<label>Exterior Material</label><select id='exterior'>#{mat_options}</select>"
      html += "<label>Interior Material</label><select id='interior'>#{int_options}</select>"
      html += "</div>"
      html += "<button onclick='applySettings()'>Apply</button>"
      html += "<script>function applySettings(){sketchup.apply({height:document.getElementById('height').value,thickness:document.getElementById('thickness').value,exterior:document.getElementById('exterior').value,interior:document.getElementById('interior').value});}</script>"
      html += "</body></html>"
      html
    end

  end
end

# Interior Pro - Window Dialog
# Single form: pick type, set parameters, click Place.
# No preset save/load. Only window TYPE names are persisted.

module InteriorPro
  module WindowLibraryDialog

    def self.show(tool)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Window',
        preferences_key: 'InteriorPro_Window',
        width: 400,
        height: 580,
        resizable: true
      )

      dialog.set_html(build_html)

      dialog.add_action_callback('get_types') { |action_context|
        types = InteriorPro::WindowLibrary.all_types
        dialog.execute_script("loadTypes(#{types.to_json})")
      }

      dialog.add_action_callback('add_custom_type') { |action_context, name|
        types = InteriorPro::WindowLibrary.add_custom(name.to_s)
        dialog.execute_script("loadTypes(#{types.to_json}, #{name.to_json})")
      }

      dialog.add_action_callback('place_window') { |action_context, data|
        window = JSON.parse(data)
        tool.window_type = window['window_type']
        tool.width = window['width'].to_f
        tool.height = window['height'].to_f
        tool.header_height = window['header_height'].to_f
        tool.frame_width = window['frame_width'].to_f
        tool.install_window = window['install_window']
        tool.exterior_trim = window['exterior_trim']
        tool.interior_casing = window['interior_casing']
        tool.preset_name = window['window_type']
        dialog.close
        Sketchup.active_model.select_tool(tool)
      }

      dialog.show
    end

    def self.build_html
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: Arial, sans-serif; background: #f0f0f0; }
          .header { background: #6A1B9A; color: white; padding: 12px 16px; font-size: 15px; font-weight: bold; }
          .content { padding: 14px; }
          .panel { background: white; border-radius: 6px; padding: 14px; border: 1px solid #ddd; }
          .section-title { font-size: 11px; color: #6A1B9A; font-weight: bold; text-transform: uppercase; margin-top: 12px; margin-bottom: 4px; border-bottom: 1px solid #eee; padding-bottom: 3px; }
          .section-title:first-child { margin-top: 0; }
          label { display: block; font-size: 12px; color: #555; margin-top: 8px; margin-bottom: 2px; }
          input, select { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
          .row { display: flex; gap: 8px; }
          .row > div { flex: 1; }
          .type-row { display: flex; gap: 6px; align-items: flex-end; }
          .type-row > select { flex: 1; }
          .btn-add-type { padding: 6px 10px; background: #43A047; color: white; border: none; border-radius: 4px; font-size: 12px; cursor: pointer; white-space: nowrap; }
          .btn-add-type:hover { background: #388E3C; }
          .checkbox-row { display: flex; align-items: center; gap: 6px; margin-top: 8px; }
          .checkbox-row input { width: auto; }
          .checkbox-row label { margin: 0; }
          .place-row { margin-top: 16px; }
          .btn-place { width: 100%; padding: 10px; background: #6A1B9A; color: white; border: none; border-radius: 6px; font-size: 14px; font-weight: bold; cursor: pointer; }
          .btn-place:hover { background: #4A148C; }
        </style>
        </head>
        <body>
        <div class="header">Interior Pro - Window</div>
        <div class="content">
          <div class="panel">
            <div class="section-title">Window Type</div>
            <label>Type</label>
            <div class="type-row">
              <select id="winType"></select>
              <button class="btn-add-type" onclick="addCustomType()">+ Add Custom Type</button>
            </div>

            <div class="section-title">Basic Options</div>
            <div class="row">
              <div>
                <label>Window Width (in)</label>
                <input type="number" id="winWidth" value="36" min="1" step="0.5">
              </div>
              <div>
                <label>Window Height (in)</label>
                <input type="number" id="winHeight" value="48" min="1" step="0.5">
              </div>
            </div>
            <div class="row">
              <div>
                <label>Header Height (in)</label>
                <input type="number" id="headerHeight" value="80" min="1" step="0.5">
              </div>
              <div>
                <label>Frame Width (in)</label>
                <input type="number" id="frameWidth" value="1.5" min="0.25" step="0.25">
              </div>
            </div>

            <div class="section-title">Install Options</div>
            <div class="checkbox-row">
              <input type="checkbox" id="installWindow" checked>
              <label for="installWindow">Install Window (frame + glass)</label>
            </div>
            <div class="checkbox-row">
              <input type="checkbox" id="exteriorTrim">
              <label for="exteriorTrim">Exterior Trim</label>
            </div>
            <div class="checkbox-row">
              <input type="checkbox" id="interiorCasing">
              <label for="interiorCasing">Interior Casing</label>
            </div>

            <div class="place-row">
              <button class="btn-place" onclick="placeWindow()">Place Window on Wall</button>
            </div>
          </div>
        </div>
        <script>
          window.onload = function() { sketchup.get_types(); };

          function loadTypes(types, selectName) {
            var sel = document.getElementById('winType');
            var current = selectName || sel.value;
            sel.innerHTML = types.map(function(t) {
              return '<option value="' + t + '">' + t + '</option>';
            }).join('');
            if (current && types.indexOf(current) !== -1) sel.value = current;
          }

          function addCustomType() {
            var name = prompt('Enter new window type name:');
            if (name === null) return;
            name = name.trim();
            if (!name) { alert('Name cannot be empty.'); return; }
            sketchup.add_custom_type(name);
          }

          function placeWindow() {
            var win = {
              window_type: document.getElementById('winType').value,
              width: parseFloat(document.getElementById('winWidth').value),
              height: parseFloat(document.getElementById('winHeight').value),
              header_height: parseFloat(document.getElementById('headerHeight').value),
              frame_width: parseFloat(document.getElementById('frameWidth').value),
              install_window: document.getElementById('installWindow').checked,
              exterior_trim: document.getElementById('exteriorTrim').checked,
              interior_casing: document.getElementById('interiorCasing').checked
            };
            sketchup.place_window(JSON.stringify(win));
          }
        </script>
        </body>
        </html>
      HTML
    end

  end
end

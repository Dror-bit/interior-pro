# Interior Pro - Window Library Dialog

module InteriorPro
  module WindowLibraryDialog

    WINDOW_TYPES = ['Single Hung', 'Double Hung', 'Slider', 'Casement', 'Picture']

    def self.show(tool)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Window Library',
        preferences_key: 'InteriorPro_WindowLibrary',
        width: 440,
        height: 700,
        resizable: true
      )

      dialog.set_html(build_html)

      dialog.add_action_callback('get_library') { |action_context|
        library = InteriorPro::WindowLibrary.load
        dialog.execute_script("loadLibrary(#{library.to_json})")
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
        tool.preset_name = window['name']
        dialog.close
        Sketchup.active_model.select_tool(tool)
      }

      dialog.add_action_callback('save_window') { |action_context, data|
        window = JSON.parse(data)
        library = InteriorPro::WindowLibrary.load
        existing = library.find_index { |w| w['name'] == window['name'] }
        if existing
          InteriorPro::WindowLibrary.update(existing, window)
        else
          InteriorPro::WindowLibrary.add(window)
        end
        dialog.execute_script("loadLibrary(#{InteriorPro::WindowLibrary.load.to_json})")
      }

      dialog.add_action_callback('delete_window') { |action_context, index|
        InteriorPro::WindowLibrary.delete(index.to_i)
        dialog.execute_script("loadLibrary(#{InteriorPro::WindowLibrary.load.to_json})")
      }

      dialog.show
    end

    def self.build_html
      types = WINDOW_TYPES.map { |t| "<option value='#{t}'>#{t}</option>" }.join
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: Arial, sans-serif; background: #f0f0f0; }
          .header { background: #6A1B9A; color: white; padding: 12px 16px; font-size: 15px; font-weight: bold; }
          .content { padding: 12px; }
          .win-list { background: white; border-radius: 6px; margin-bottom: 12px; overflow: hidden; border: 1px solid #ddd; }
          .win-item { padding: 10px 14px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; cursor: pointer; }
          .win-item:hover { background: #f3e5f5; }
          .win-name { font-weight: bold; font-size: 13px; color: #222; }
          .win-info { font-size: 11px; color: #777; margin-top: 2px; }
          .win-actions { display: flex; gap: 6px; }
          .btn { padding: 6px 12px; border: none; border-radius: 4px; font-size: 12px; cursor: pointer; }
          .btn-place { background: #6A1B9A; color: white; }
          .btn-edit { background: #f5f5f5; color: #333; border: 1px solid #ccc; }
          .btn-delete { background: #ffebee; color: #c62828; border: 1px solid #ef9a9a; }
          .btn-new { width: 100%; padding: 10px; background: #43A047; color: white; border: none; border-radius: 6px; font-size: 13px; cursor: pointer; margin-bottom: 8px; }
          .btn-new:hover { background: #388E3C; }
          .form-panel { background: white; border-radius: 6px; padding: 14px; border: 1px solid #ddd; display: none; }
          .form-panel.visible { display: block; }
          .form-title { font-weight: bold; color: #6A1B9A; margin-bottom: 12px; font-size: 13px; }
          .section-title { font-size: 11px; color: #6A1B9A; font-weight: bold; text-transform: uppercase; margin-top: 12px; margin-bottom: 4px; border-bottom: 1px solid #eee; padding-bottom: 3px; }
          label { display: block; font-size: 12px; color: #555; margin-top: 8px; margin-bottom: 2px; }
          input, select { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
          .row { display: flex; gap: 8px; }
          .row > div { flex: 1; }
          .checkbox-row { display: flex; align-items: center; gap: 6px; margin-top: 8px; }
          .checkbox-row input { width: auto; }
          .checkbox-row label { margin: 0; }
          .form-actions { display: flex; gap: 8px; margin-top: 14px; }
          .btn-save { flex: 1; padding: 8px; background: #6A1B9A; color: white; border: none; border-radius: 4px; cursor: pointer; }
          .btn-cancel { flex: 1; padding: 8px; background: #f5f5f5; color: #333; border: 1px solid #ccc; border-radius: 4px; cursor: pointer; }
          .empty-msg { padding: 24px; text-align: center; color: #999; font-size: 13px; }
        </style>
        </head>
        <body>
        <div class="header">Interior Pro - Window Library</div>
        <div class="content">
          <button class="btn-new" onclick="showForm()">+ New Window Preset</button>
          <div class="win-list" id="winList">
            <div class="empty-msg">No window presets yet. Click "+ New Window Preset" to create one.</div>
          </div>
          <div class="form-panel" id="formPanel">
            <div class="form-title" id="formTitle">New Window Preset</div>
            <input type="hidden" id="editIndex" value="-1">

            <label>Preset Name</label>
            <input type="text" id="winName" placeholder="e.g. Standard Bedroom Window">

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
            <label>Window Type</label>
            <select id="winType">#{types}</select>

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

            <div class="form-actions">
              <button class="btn-save" onclick="saveWindow()">Save</button>
              <button class="btn-cancel" onclick="hideForm()">Cancel</button>
            </div>
          </div>
        </div>
        <script>
          var library = [];

          window.onload = function() { sketchup.get_library(); };

          function loadLibrary(data) {
            library = data;
            var list = document.getElementById('winList');
            if (!data || data.length === 0) {
              list.innerHTML = '<div class="empty-msg">No window presets yet. Click "+ New Window Preset" to create one.</div>';
              return;
            }
            list.innerHTML = data.map(function(w, i) {
              var install = w.install_window ? 'Installed' : 'Opening only';
              return '<div class="win-item">' +
                '<div>' +
                  '<div class="win-name">' + w.name + ' <span style="font-size:10px;padding:2px 6px;border-radius:3px;background:#f3e5f5;color:#6A1B9A;font-weight:normal;">' + w.window_type + '</span></div>' +
                  '<div class="win-info">' + w.width + '"W x ' + w.height + '"H | Header: ' + w.header_height + '" | ' + install + '</div>' +
                '</div>' +
                '<div class="win-actions">' +
                  '<button class="btn btn-place" onclick="placeWindow(' + i + ')">Place</button>' +
                  '<button class="btn btn-edit" onclick="editWindow(' + i + ')">Edit</button>' +
                  '<button class="btn btn-delete" onclick="deleteWindow(' + i + ')">X</button>' +
                '</div>' +
              '</div>';
            }).join('');
          }

          function placeWindow(i) {
            sketchup.place_window(JSON.stringify(library[i]));
          }

          function editWindow(i) {
            var w = library[i];
            document.getElementById('formTitle').innerText = 'Edit Window Preset';
            document.getElementById('editIndex').value = i;
            document.getElementById('winName').value = w.name;
            document.getElementById('winWidth').value = w.width;
            document.getElementById('winHeight').value = w.height;
            document.getElementById('headerHeight').value = w.header_height;
            document.getElementById('frameWidth').value = w.frame_width;
            document.getElementById('winType').value = w.window_type;
            document.getElementById('installWindow').checked = !!w.install_window;
            document.getElementById('exteriorTrim').checked = !!w.exterior_trim;
            document.getElementById('interiorCasing').checked = !!w.interior_casing;
            document.getElementById('formPanel').className = 'form-panel visible';
          }

          function deleteWindow(i) {
            if (confirm('Delete this window preset?')) sketchup.delete_window(i);
          }

          function showForm() {
            document.getElementById('formTitle').innerText = 'New Window Preset';
            document.getElementById('editIndex').value = -1;
            document.getElementById('winName').value = '';
            document.getElementById('winWidth').value = 36;
            document.getElementById('winHeight').value = 48;
            document.getElementById('headerHeight').value = 80;
            document.getElementById('frameWidth').value = 1.5;
            document.getElementById('winType').value = 'Single Hung';
            document.getElementById('installWindow').checked = true;
            document.getElementById('exteriorTrim').checked = false;
            document.getElementById('interiorCasing').checked = false;
            document.getElementById('formPanel').className = 'form-panel visible';
          }

          function hideForm() {
            document.getElementById('formPanel').className = 'form-panel';
          }

          function saveWindow() {
            var name = document.getElementById('winName').value.trim();
            if (!name) { alert('Please enter a preset name.'); return; }
            var win = {
              name: name,
              window_type: document.getElementById('winType').value,
              width: parseFloat(document.getElementById('winWidth').value),
              height: parseFloat(document.getElementById('winHeight').value),
              header_height: parseFloat(document.getElementById('headerHeight').value),
              frame_width: parseFloat(document.getElementById('frameWidth').value),
              install_window: document.getElementById('installWindow').checked,
              exterior_trim: document.getElementById('exteriorTrim').checked,
              interior_casing: document.getElementById('interiorCasing').checked
            };
            sketchup.save_window(JSON.stringify(win));
            hideForm();
          }
        </script>
        </body>
        </html>
      HTML
    end

  end
end

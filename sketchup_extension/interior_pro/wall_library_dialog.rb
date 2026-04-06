# Interior Pro - Wall Library Dialog

module InteriorPro
  module WallLibraryDialog

    MATERIALS = ['Stucco', 'Brick', 'Siding', 'Concrete', 'Wood', 'Gypsum', 'Tile', 'Stone', 'Paint', 'Plaster']

    def self.show(tool)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Wall Library',
        preferences_key: 'InteriorPro_WallLibrary',
        width: 420,
        height: 580,
        resizable: true
      )

      dialog.set_html(build_html)

      dialog.add_action_callback('get_library') { |action_context|
        library = InteriorPro::WallLibrary.load
        dialog.execute_script("loadLibrary(#{library.to_json})")
      }

      dialog.add_action_callback('draw_wall') { |action_context, data|
        wall = JSON.parse(data)
        tool.height = wall['height'].to_f
        tool.thickness = wall['thickness'].to_f
        tool.exterior_material = wall['exterior_material']
        tool.interior_material = wall['interior_material']
        tool.wall_type_name = wall['name']
        tool.anchor = wall['anchor'] || 'bottom-center'
        tool.wall_category = wall['wall_category'] || 'both'
        dialog.close
        Sketchup.active_model.select_tool(tool)
      }

      dialog.add_action_callback('save_wall') { |action_context, data|
        wall = JSON.parse(data)
        library = InteriorPro::WallLibrary.load
        existing = library.find_index { |w| w['name'] == wall['name'] }
        if existing
          InteriorPro::WallLibrary.update(existing, wall)
        else
          InteriorPro::WallLibrary.add(wall)
        end
        dialog.execute_script("loadLibrary(#{InteriorPro::WallLibrary.load.to_json})")
      }

      dialog.add_action_callback('delete_wall') { |action_context, index|
        InteriorPro::WallLibrary.delete(index.to_i)
        dialog.execute_script("loadLibrary(#{InteriorPro::WallLibrary.load.to_json})")
      }

      dialog.show
    end

    def self.build_html
      mats = MATERIALS.map { |m| "<option value='#{m}'>#{m}</option>" }.join
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: Arial, sans-serif; background: #f0f0f0; }
          .header { background: #1565C0; color: white; padding: 12px 16px; font-size: 15px; font-weight: bold; }
          .content { padding: 12px; }
          .wall-list { background: white; border-radius: 6px; margin-bottom: 12px; overflow: hidden; border: 1px solid #ddd; }
          .wall-item { padding: 10px 14px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; cursor: pointer; }
          .wall-item:hover { background: #e3f2fd; }
          .wall-item.selected { background: #bbdefb; }
          .wall-name { font-weight: bold; font-size: 13px; color: #222; }
          .wall-info { font-size: 11px; color: #777; margin-top: 2px; }
          .wall-actions { display: flex; gap: 6px; }
          .btn { padding: 6px 12px; border: none; border-radius: 4px; font-size: 12px; cursor: pointer; }
          .btn-draw { background: #1565C0; color: white; }
          .btn-edit { background: #f5f5f5; color: #333; border: 1px solid #ccc; }
          .btn-delete { background: #ffebee; color: #c62828; border: 1px solid #ef9a9a; }
          .btn-new { width: 100%; padding: 10px; background: #43A047; color: white; border: none; border-radius: 6px; font-size: 13px; cursor: pointer; margin-bottom: 8px; }
          .btn-new:hover { background: #388E3C; }
          .form-panel { background: white; border-radius: 6px; padding: 14px; border: 1px solid #ddd; display: none; }
          .form-panel.visible { display: block; }
          .form-title { font-weight: bold; color: #1565C0; margin-bottom: 12px; font-size: 13px; }
          label { display: block; font-size: 12px; color: #555; margin-top: 8px; margin-bottom: 2px; }
          input, select { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
          .row { display: flex; gap: 8px; }
          .row > div { flex: 1; }
          .anchor-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 3px; margin-top: 4px; }
          .anchor-btn { padding: 6px; border: 1px solid #ccc; border-radius: 4px; background: #f5f5f5; cursor: pointer; font-size: 11px; text-align: center; }
          .anchor-btn.active { background: #1565C0; color: white; border-color: #1565C0; }
          .form-actions { display: flex; gap: 8px; margin-top: 14px; }
          .btn-save { flex: 1; padding: 8px; background: #1565C0; color: white; border: none; border-radius: 4px; cursor: pointer; }
          .btn-cancel { flex: 1; padding: 8px; background: #f5f5f5; color: #333; border: 1px solid #ccc; border-radius: 4px; cursor: pointer; }
          .empty-msg { padding: 24px; text-align: center; color: #999; font-size: 13px; }
        </style>
        </head>
        <body>
        <div class="header">Interior Pro - Wall Library</div>
        <div class="content">
          <button class="btn-new" onclick="showForm()">+ New Wall Type</button>
          <div class="wall-list" id="wallList">
            <div class="empty-msg">No wall types yet. Click "+ New Wall Type" to create one.</div>
          </div>
          <div class="form-panel" id="formPanel">
            <div class="form-title" id="formTitle">New Wall Type</div>
            <input type="hidden" id="editIndex" value="-1">
            <label>Wall Type Name</label>
            <input type="text" id="wallName" placeholder="e.g. Exterior Stucco Wall">
            <label>Wall Category</label>
            <select id="wallCategory">
              <option value="interior">Interior</option>
              <option value="exterior">Exterior</option>
              <option value="both" selected>Both</option>
            </select>
            <div class="row">
              <div>
                <label>Height (inches)</label>
                <input type="number" id="wallHeight" value="96" min="1" step="0.5">
              </div>
              <div>
                <label>Thickness (inches)</label>
                <input type="number" id="wallThickness" value="6" min="1" step="0.5">
              </div>
            </div>
            <div class="row">
              <div>
                <label>Exterior Material</label>
                <select id="extMat">#{mats}</select>
              </div>
              <div>
                <label>Interior Material</label>
                <select id="intMat">#{mats}</select>
              </div>
            </div>
            <label>Draw from (anchor point)</label>
            <div class="anchor-grid">
              <button class="anchor-btn" onclick="setAnchor('top-left')" id="anchor-top-left">Top Left</button>
              <button class="anchor-btn" onclick="setAnchor('top-center')" id="anchor-top-center">Top Center</button>
              <button class="anchor-btn" onclick="setAnchor('top-right')" id="anchor-top-right">Top Right</button>
              <button class="anchor-btn" onclick="setAnchor('center-left')" id="anchor-center-left">Center Left</button>
              <button class="anchor-btn" onclick="setAnchor('center')" id="anchor-center">Center</button>
              <button class="anchor-btn" onclick="setAnchor('center-right')" id="anchor-center-right">Center Right</button>
              <button class="anchor-btn" onclick="setAnchor('bottom-left')" id="anchor-bottom-left">Bottom Left</button>
              <button class="anchor-btn active" onclick="setAnchor('bottom-center')" id="anchor-bottom-center">Bottom Center</button>
              <button class="anchor-btn" onclick="setAnchor('bottom-right')" id="anchor-bottom-right">Bottom Right</button>
            </div>
            <input type="hidden" id="anchorVal" value="bottom-center">
            <div class="form-actions">
              <button class="btn-save" onclick="saveWall()">Save</button>
              <button class="btn-cancel" onclick="hideForm()">Cancel</button>
            </div>
          </div>
        </div>
        <script>
          var currentAnchor = 'bottom-center';
          var library = [];

          window.onload = function() { sketchup.get_library(); };

          function loadLibrary(data) {
            library = data;
            var list = document.getElementById('wallList');
            if (!data || data.length === 0) {
              list.innerHTML = '<div class="empty-msg">No wall types yet. Click "+ New Wall Type" to create one.</div>';
              return;
            }
            list.innerHTML = data.map(function(w, i) {
              return '<div class="wall-item">' +
                '<div>' +
                  '<div class="wall-name">' + w.name + ' <span style="font-size:10px;padding:2px 6px;border-radius:3px;background:#e3f2fd;color:#1565C0;font-weight:normal;">' + (w.wall_category || 'both') + '</span></div>' +
                  '<div class="wall-info">H: ' + w.height + '" | T: ' + w.thickness + '" | Ext: ' + w.exterior_material + ' | Int: ' + w.interior_material + '</div>' +
                '</div>' +
                '<div class="wall-actions">' +
                  '<button class="btn btn-draw" onclick="drawWall(' + i + ')">Draw</button>' +
                  '<button class="btn btn-edit" onclick="editWall(' + i + ')">Edit</button>' +
                  '<button class="btn btn-delete" onclick="deleteWall(' + i + ')">X</button>' +
                '</div>' +
              '</div>';
            }).join('');
          }

          function drawWall(i) {
            sketchup.draw_wall(JSON.stringify(library[i]));
          }

          function editWall(i) {
            var w = library[i];
            document.getElementById('formTitle').innerText = 'Edit Wall Type';
            document.getElementById('editIndex').value = i;
            document.getElementById('wallName').value = w.name;
            document.getElementById('wallHeight').value = w.height;
            document.getElementById('wallThickness').value = w.thickness;
            document.getElementById('extMat').value = w.exterior_material;
            document.getElementById('intMat').value = w.interior_material;
            setAnchor(w.anchor || 'bottom-center');
            document.getElementById('wallCategory').value = w.wall_category || 'both';
            document.getElementById('formPanel').className = 'form-panel visible';
          }

          function deleteWall(i) {
            if (confirm('Delete this wall type?')) sketchup.delete_wall(i);
          }

          function showForm() {
            document.getElementById('formTitle').innerText = 'New Wall Type';
            document.getElementById('editIndex').value = -1;
            document.getElementById('wallName').value = '';
            document.getElementById('wallHeight').value = 96;
            document.getElementById('wallThickness').value = 6;
            setAnchor('bottom-center');
            document.getElementById('formPanel').className = 'form-panel visible';
          }

          function hideForm() {
            document.getElementById('formPanel').className = 'form-panel';
          }

          function setAnchor(val) {
            currentAnchor = val;
            document.getElementById('anchorVal').value = val;
            ['top-left','top-center','top-right','center-left','center','center-right','bottom-left','bottom-center','bottom-right'].forEach(function(a) {
              document.getElementById('anchor-' + a).className = 'anchor-btn' + (a === val ? ' active' : '');
            });
          }

          function saveWall() {
            var name = document.getElementById('wallName').value.trim();
            if (!name) { alert('Please enter a wall type name.'); return; }
            var wall = {
              name: name,
              height: parseFloat(document.getElementById('wallHeight').value),
              thickness: parseFloat(document.getElementById('wallThickness').value),
              exterior_material: document.getElementById('extMat').value,
              interior_material: document.getElementById('intMat').value,
              anchor: currentAnchor,
              wall_category: document.getElementById('wallCategory').value
            };
            sketchup.save_wall(JSON.stringify(wall));
            hideForm();
          }
        </script>
        </body>
        </html>
      HTML
    end

  end
end

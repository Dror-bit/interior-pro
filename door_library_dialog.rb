# Interior Pro - Door Dialog
# Single form: pick type, set parameters, click Place.
# No preset save/load. Only door TYPE names are persisted.

module InteriorPro
  module DoorLibraryDialog

    def self.show(tool)
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Door',
        preferences_key: 'InteriorPro_Door',
        width: 400,
        height: 640,
        resizable: true
      )

      dialog.set_html(build_html)

      dialog.add_action_callback('get_types') { |action_context|
        types = InteriorPro::DoorLibrary.all_types
        dialog.execute_script("loadTypes(#{types.to_json})")
      }

      dialog.add_action_callback('add_custom_type') { |action_context, name|
        types = InteriorPro::DoorLibrary.add_custom(name.to_s)
        dialog.execute_script("loadTypes(#{types.to_json}, #{name.to_json})")
      }

      dialog.add_action_callback('place_door') { |action_context, data|
        door = JSON.parse(data)
        tool.door_type       = door['door_type']
        tool.width           = door['width'].to_f
        tool.height          = door['height'].to_f
        tool.frame_width     = door['frame_width'].to_f
        tool.interior_depth  = door['interior_depth'].to_f
        tool.floor_offset    = door['floor_offset'].to_f
        tool.swing_direction = door['swing_direction']
        tool.swing_side      = door['swing_side']
        tool.slide_direction = door['slide_direction']
        tool.handle_type     = door['handle_type']
        tool.preset_name     = door['door_type']
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
          .header { background: #5D4037; color: white; padding: 12px 16px; font-size: 15px; font-weight: bold; }
          .content { padding: 14px; }
          .panel { background: white; border-radius: 6px; padding: 14px; border: 1px solid #ddd; }
          .section-title { font-size: 11px; color: #5D4037; font-weight: bold; text-transform: uppercase; margin-top: 12px; margin-bottom: 4px; border-bottom: 1px solid #eee; padding-bottom: 3px; }
          .section-title:first-child { margin-top: 0; }
          label { display: block; font-size: 12px; color: #555; margin-top: 8px; margin-bottom: 2px; }
          input, select { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
          .row { display: flex; gap: 8px; }
          .row > div { flex: 1; }
          .type-row { display: flex; gap: 6px; align-items: flex-end; }
          .type-row > select { flex: 1; }
          .btn-add-type { padding: 6px 10px; background: #43A047; color: white; border: none; border-radius: 4px; font-size: 12px; cursor: pointer; white-space: nowrap; }
          .btn-add-type:hover { background: #388E3C; }
          .place-row { margin-top: 16px; }
          .btn-place { width: 100%; padding: 10px; background: #5D4037; color: white; border: none; border-radius: 6px; font-size: 14px; font-weight: bold; cursor: pointer; }
          .btn-place:hover { background: #4E342E; }
        </style>
        </head>
        <body>
        <div class="header">Interior Pro - Door</div>
        <div class="content">
          <div class="panel">
            <div class="section-title">Door Type</div>
            <label>Type</label>
            <div class="type-row">
              <select id="doorType" onchange="syncTypeFields()"></select>
              <button class="btn-add-type" onclick="addCustomType()">+ Add Custom Type</button>
            </div>

            <div class="section-title">Size</div>
            <div class="row">
              <div>
                <label>Door Width (in)</label>
                <input type="number" id="doorWidth" value="36" min="1" step="0.5">
              </div>
              <div>
                <label>Door Height (in)</label>
                <input type="number" id="doorHeight" value="80" min="1" step="0.5">
              </div>
            </div>
            <div class="row">
              <div>
                <label>Frame Width (in)</label>
                <input type="number" id="frameWidth" value="1.5" min="0.25" step="0.25">
              </div>
              <div>
                <label>Interior Depth (in)</label>
                <input type="number" id="interiorDepth" value="1" min="0.25" step="0.25">
              </div>
            </div>

            <div class="section-title">Position</div>
            <label>Threshold / Floor Offset (in)</label>
            <input type="number" id="floorOffset" value="0" min="0" step="0.25">

            <div class="section-title">Opening Direction</div>
            <div id="hingedFields">
              <div class="row">
                <div>
                  <label>Swing Direction</label>
                  <select id="swingDirection">
                    <option value="left">Left</option>
                    <option value="right">Right</option>
                  </select>
                </div>
                <div>
                  <label>Swing Side</label>
                  <select id="swingSide">
                    <option value="auto">Auto (click side)</option>
                    <option value="inward">Inward</option>
                    <option value="outward">Outward</option>
                  </select>
                </div>
              </div>
            </div>
            <div id="slidingFields">
              <label>Slide Direction</label>
              <select id="slideDirection">
                <option value="left">Slide Left</option>
                <option value="right">Slide Right</option>
              </select>
            </div>

            <div class="section-title">Hardware</div>
            <label>Handle Type</label>
            <select id="handleType">
              <option value="lever">Lever</option>
              <option value="knob">Knob</option>
              <option value="pull">Pull</option>
              <option value="none">None</option>
            </select>

            <div class="place-row">
              <button class="btn-place" onclick="placeDoor()">Place Door on Wall</button>
            </div>
          </div>
        </div>
        <script>
          window.onload = function() { sketchup.get_types(); };

          function loadTypes(types, selectName) {
            var sel = document.getElementById('doorType');
            var current = selectName || sel.value;
            sel.innerHTML = types.map(function(t) {
              return '<option value="' + t + '">' + t + '</option>';
            }).join('');
            if (current && types.indexOf(current) !== -1) sel.value = current;
            syncTypeFields();
          }

          // Show swing fields for hinged doors, slide field for sliding doors.
          function syncTypeFields() {
            var t = document.getElementById('doorType').value;
            var isSliding = (t === 'Sliding' || t === 'French Sliding');
            document.getElementById('slidingFields').style.display = isSliding ? 'block' : 'none';
            document.getElementById('hingedFields').style.display = isSliding ? 'none' : 'block';
          }

          function addCustomType() {
            var name = prompt('Enter new door type name:');
            if (name === null) return;
            name = name.trim();
            if (!name) { alert('Name cannot be empty.'); return; }
            sketchup.add_custom_type(name);
          }

          function placeDoor() {
            var door = {
              door_type: document.getElementById('doorType').value,
              width: parseFloat(document.getElementById('doorWidth').value),
              height: parseFloat(document.getElementById('doorHeight').value),
              frame_width: parseFloat(document.getElementById('frameWidth').value),
              interior_depth: parseFloat(document.getElementById('interiorDepth').value),
              floor_offset: parseFloat(document.getElementById('floorOffset').value),
              swing_direction: document.getElementById('swingDirection').value,
              swing_side: document.getElementById('swingSide').value,
              slide_direction: document.getElementById('slideDirection').value,
              handle_type: document.getElementById('handleType').value
            };
            sketchup.place_door(JSON.stringify(door));
          }
        </script>
        </body>
        </html>
      HTML
    end

  end
end

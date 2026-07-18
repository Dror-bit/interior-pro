# Interior Pro - Floor Dialog
# One row per room: floor type + thickness. Apply builds/rebuilds floors.
require 'json'

module InteriorPro
  module FloorDialog

    def self.show
      rooms = InteriorPro::RoomManager.rooms_in_model
      floors_by_room = {}
      InteriorPro::FloorManager.floors_in_model.each do |f|
        floors_by_room[f.get_attribute('InteriorPro', 'room_id')] = f
      end
      data = rooms.map do |r|
        rid = r.get_attribute('InteriorPro', 'id')
        fl  = floors_by_room[rid]
        {
          'id'        => rid,
          'name'      => r.get_attribute('InteriorPro', 'name').to_s,
          'area'      => r.get_attribute('InteriorPro', 'area_sqft').to_f.round(1),
          'type'      => fl ? fl.get_attribute('InteriorPro', 'floor_type') : (rooms.length == floors_by_room.length ? 'None' : 'Hardwood'),
          'has_floor' => !fl.nil?,
          'thickness' => fl ? fl.get_attribute('InteriorPro', 'thickness_in').to_f : nil
        }
      end

      types = {}
      InteriorPro::FloorManager::FLOOR_TYPES.each { |k, v| types[k] = v[:thickness] }

      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Floors',
        preferences_key: 'InteriorPro_Floors',
        width: 430, height: 420, resizable: true
      )
      dlg.add_action_callback('apply') do |_, json|
        apply_selections(JSON.parse(json))
        show # reopen with fresh state
      end
      dlg.add_action_callback('remove_all') do |_|
        InteriorPro::FloorManager.remove_all!
        show
      end
      dlg.add_action_callback('sync_rooms') do |_|
        InteriorPro::RoomManager.sync_rooms!
        show
      end
      dlg.set_html(build_html(data, types))
      dlg.show
      @dialog = dlg
    end

    def self.apply_selections(sel)
      model = Sketchup.active_model
      rooms_by_id = {}
      InteriorPro::RoomManager.rooms_in_model.each do |r|
        rooms_by_id[r.get_attribute('InteriorPro', 'id')] = r
      end
      model.start_operation('InteriorPro Apply Floors', true)
      count = 0
      sel.each do |rid, cfg|
        room = rooms_by_id[rid]
        next unless room
        if cfg['type'] == 'None'
          InteriorPro::FloorManager.remove_floor_for_room!(rid)
        else
          th = cfg['thickness'].to_f
          InteriorPro::FloorManager.build_floor_for_room!(
            room, cfg['type'], thickness: (th > 0.05 ? th : nil)
          )
          count += 1
        end
      end
      InteriorPro::FloorManager.build_door_patches!
      model.commit_operation
      puts "[Floors] dialog apply: #{count} floor(s)"
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Floors] dialog apply failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    def self.build_html(rooms, types)
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
          body { font-family: Arial, sans-serif; font-size: 13px; margin: 12px; background: #fff; }
          .section-title { font-weight: bold; margin: 0 0 8px; color: #5d4037; }
          table { width: 100%; border-collapse: collapse; }
          th { text-align: left; font-size: 11px; color: #888; padding: 2px 4px; }
          td { padding: 4px; border-top: 1px solid #eee; }
          td.nm { font-weight: bold; color: #333; }
          td.ar { color: #777; font-size: 12px; white-space: nowrap; }
          select, input[type=number] { padding: 3px; width: 100%; box-sizing: border-box; }
          td.th-col { width: 70px; }
          .empty { color: #999; margin: 16px 0; text-align: center; }
          button { width: 100%; padding: 10px; margin-top: 10px; border: none; border-radius: 6px;
                   background: #5d4037; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
        </style></head><body>
          <div class="section-title">Floors per Room</div>
          <div id="content"></div>
          <button onclick="applyAll()" id="applyBtn">Apply</button>
          <button class="secondary" onclick="sketchup.sync_rooms()">Sync Rooms</button>
          <button class="secondary" onclick="sketchup.remove_all()">Remove All Floors</button>
          <script>
            var ROOMS = #{rooms.to_json};
            var TYPES = #{types.to_json};

            function typeOptions(sel) {
              var opts = ['None'].concat(Object.keys(TYPES));
              return opts.map(function(t) {
                return '<option value="' + t + '"' + (t === sel ? ' selected' : '') + '>' + t + '</option>';
              }).join('');
            }
            function render() {
              if (!ROOMS.length) {
                document.getElementById('content').innerHTML =
                  '<div class="empty">No rooms found.<br>Close a wall loop and press Sync Rooms.</div>';
                document.getElementById('applyBtn').style.display = 'none';
                return;
              }
              var rows = ['<table><tr><th>Room</th><th>Area</th><th>Floor</th><th>Thick (in)</th></tr>'];
              ROOMS.forEach(function(r, i) {
                var th = r.thickness || TYPES[r.type] || '';
                rows.push('<tr><td class="nm">' + r.name + '</td>' +
                  '<td class="ar">' + r.area + ' sqft</td>' +
                  '<td><select id="type_' + i + '" onchange="typeChanged(' + i + ')">' + typeOptions(r.type) + '</select></td>' +
                  '<td class="th-col"><input type="number" id="th_' + i + '" step="0.25" min="0" value="' + th + '"></td></tr>');
              });
              rows.push('</table>');
              document.getElementById('content').innerHTML = rows.join('');
            }
            function typeChanged(i) {
              var t = document.getElementById('type_' + i).value;
              document.getElementById('th_' + i).value = TYPES[t] || '';
            }
            function applyAll() {
              var sel = {};
              ROOMS.forEach(function(r, i) {
                sel[r.id] = {
                  type: document.getElementById('type_' + i).value,
                  thickness: parseFloat(document.getElementById('th_' + i).value) || 0
                };
              });
              sketchup.apply(JSON.stringify(sel));
            }
            render();
          </script>
        </body></html>
      HTML
    end

  end
end

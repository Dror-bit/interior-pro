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
          'thickness' => fl ? fl.get_attribute('InteriorPro', 'thickness_in').to_f : nil,
          'pattern'   => fl ? (fl.get_attribute('InteriorPro', 'pattern') || 'None') : 'None',
          'unit_w'    => fl ? fl.get_attribute('InteriorPro', 'unit_w').to_f : 0,
          'unit_l'    => fl ? fl.get_attribute('InteriorPro', 'unit_l').to_f : 0,
          'ox'        => fl ? fl.get_attribute('InteriorPro', 'pattern_ox').to_f : 0,
          'oy'        => fl ? fl.get_attribute('InteriorPro', 'pattern_oy').to_f : 0,
          'angle'     => fl ? fl.get_attribute('InteriorPro', 'pattern_angle').to_f : 0,
          'center'    => fl ? (fl.get_attribute('InteriorPro', 'pattern_center') ? true : false) : true
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
        width: 470, height: 520, resizable: true
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
          fl_grp = InteriorPro::FloorManager.build_floor_for_room!(
            room, cfg['type'], thickness: (th > 0.05 ? th : nil)
          )
          if fl_grp
            fl_grp.set_attribute('InteriorPro', 'pattern', cfg['pattern'] || 'None')
            fl_grp.set_attribute('InteriorPro', 'unit_w', cfg['unit_w'].to_f)
            fl_grp.set_attribute('InteriorPro', 'unit_l', cfg['unit_l'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_ox', cfg['ox'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_oy', cfg['oy'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_angle', cfg['angle'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_center', cfg['center'] ? true : false)
          end
          count += 1
        end
      end
      InteriorPro::FloorManager.build_door_patches!
      InteriorPro::FloorPattern.refresh_all! if defined?(InteriorPro::FloorPattern)
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
          tr.pat td { border-top: none; background: #fafafa; font-size: 11px; color: #555; }
          tr.pat input[type=number] { width: 44px; padding: 2px; }
          tr.pat select { width: 84px; padding: 2px; }
          tr.pat label { white-space: nowrap; }
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
            function patternOptions(sel) {
              return ['None', 'Tile', 'Straight', 'Herringbone', 'Chevron'].map(function(t) {
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
                rows.push('<tr class="pat"><td colspan="4">' +
                  'Pattern <select id="pat_' + i + '">' + patternOptions(r.pattern) + '</select> ' +
                  'W <input type="number" id="pw_' + i + '" step="0.5" min="0" value="' + (r.unit_w || '') + '"> ' +
                  'L <input type="number" id="pl_' + i + '" step="0.5" min="0" value="' + (r.unit_l || '') + '"> ' +
                  'X <input type="number" id="px_' + i + '" step="0.5" value="' + (r.ox || 0) + '"> ' +
                  'Y <input type="number" id="py_' + i + '" step="0.5" value="' + (r.oy || 0) + '"> ' +
                  'Ang <input type="number" id="pa_' + i + '" step="5" value="' + (r.angle || 0) + '"> ' +
                  '<label><input type="checkbox" id="pc_' + i + '"' + (r.center ? ' checked' : '') + '> Center</label>' +
                  '</td></tr>');
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
                  thickness: parseFloat(document.getElementById('th_' + i).value) || 0,
                  pattern: document.getElementById('pat_' + i).value,
                  unit_w: parseFloat(document.getElementById('pw_' + i).value) || 0,
                  unit_l: parseFloat(document.getElementById('pl_' + i).value) || 0,
                  ox: parseFloat(document.getElementById('px_' + i).value) || 0,
                  oy: parseFloat(document.getElementById('py_' + i).value) || 0,
                  angle: parseFloat(document.getElementById('pa_' + i).value) || 0,
                  center: document.getElementById('pc_' + i).checked
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

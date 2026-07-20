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
          'center'    => fl ? (fl.get_attribute('InteriorPro', 'pattern_center') ? true : false) : true,
          'texture'   => fl ? (fl.get_attribute('InteriorPro', 'floor_texture') || '') : '',
          'grout'     => fl ? fl.get_attribute('InteriorPro', 'pattern_grout').to_f : 0,
          'grout_color' => fl ? (fl.get_attribute('InteriorPro', 'pattern_grout_color') || 'light') : 'light',
          'spec'        => fl ? (fl.get_attribute('InteriorPro', 'floor_spec') || '') : '',
          'grout_spec'  => fl ? (fl.get_attribute('InteriorPro', 'grout_spec') || '') : ''
        }
      end

      types = {}
      InteriorPro::FloorManager::FLOOR_TYPES.each { |k, v| types[k] = v[:thickness] }

      # Texture library: base name -> thumbnail file URL (thumbs/<name>, falls
      # back to the full image if no thumb exists).
      textures = {}
      InteriorPro::FloorManager::SOLID_COLORS.each_key { |c| textures[c] = '' }
      InteriorPro::FloorManager.texture_files.each do |f|
        base = File.basename(f, '.*')
        thumb = File.join(File.dirname(f), 'thumbs', File.basename(f))
        src = File.exist?(thumb) ? thumb : f
        textures[base] = 'file:///' + src.tr('\\', '/').gsub(' ', '%20')
      end

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
      dlg.set_html(build_html(data, types, textures))
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
        if cfg['texture'].to_s.empty?
          InteriorPro::FloorManager.remove_floor_for_room!(rid)
        else
          th = cfg['thickness'].to_f
          fl_grp = InteriorPro::FloorManager.build_floor_for_room!(
            room, cfg['type'], thickness: (th > 0.05 ? th : nil),
            texture: cfg['texture'].to_s
          )
          if fl_grp
            fl_grp.set_attribute('InteriorPro', 'pattern', cfg['pattern'] || 'None')
            fl_grp.set_attribute('InteriorPro', 'unit_w', cfg['unit_w'].to_f)
            fl_grp.set_attribute('InteriorPro', 'unit_l', cfg['unit_l'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_ox', cfg['ox'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_oy', cfg['oy'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_angle', cfg['angle'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_center', cfg['center'] ? true : false)
            fl_grp.set_attribute('InteriorPro', 'pattern_grout', cfg['grout'].to_f)
            fl_grp.set_attribute('InteriorPro', 'pattern_grout_color', cfg['grout_color'].to_s)
            fl_grp.set_attribute('InteriorPro', 'floor_spec', cfg['spec'].to_s)
            fl_grp.set_attribute('InteriorPro', 'grout_spec', cfg['grout_spec'].to_s)
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

    def self.build_html(rooms, types, textures = {})
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
            var TEXTURES = #{textures.to_json};

            function patternOptions(sel) {
              return ['None', 'Tile', 'Straight', 'Herringbone', 'Chevron'].map(function(t) {
                return '<option value="' + t + '"' + (t === sel ? ' selected' : '') + '>' + t + '</option>';
              }).join('');
            }
            function textureOptions(sel) {
              var opts = ['<option value=""' + (sel ? '' : ' selected') + '>None</option>'];
              Object.keys(TEXTURES).forEach(function(b) {
                opts.push('<option value="' + b + '"' + (b === sel ? ' selected' : '') + '>' + b.replace(/[_-]+/g, ' ') + '</option>');
              });
              return opts.join('');
            }
            function groutOptions(sel) {
              var opts = [[0, 'None'], [0.0625, '1/16"'], [0.125, '1/8"'], [0.1875, '3/16"'],
                          [0.25, '1/4"'], [0.375, '3/8"'], [0.5, '1/2"']];
              return opts.map(function(o) {
                var s = Math.abs((sel || 0) - o[0]) < 0.01 ? ' selected' : '';
                return '<option value="' + o[0] + '"' + s + '>' + o[1] + '</option>';
              }).join('');
            }
            function groutColorOptions(sel) {
              return [['white', 'White'], ['light', 'Light'], ['gray', 'Gray'], ['dark', 'Dark']].map(function(o) {
                return '<option value="' + o[0] + '"' + (o[0] === (sel || 'light') ? ' selected' : '') + '>' + o[1] + '</option>';
              }).join('');
            }
            function textureChanged(i) {
              var b = document.getElementById('tx_' + i).value;
              var img = document.getElementById('tximg_' + i);
              if (b && TEXTURES[b]) {
                img.src = TEXTURES[b];
                img.style.display = 'inline-block';
              } else {
                img.style.display = 'none';
              }
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
                var th = r.thickness || 0.75;
                rows.push('<tr><td class="nm">' + r.name + '</td>' +
                  '<td class="ar">' + r.area + ' sqft</td>' +
                  '<td><select id="tx_' + i + '" onchange="textureChanged(' + i + ')" style="width:120px;">' + textureOptions(r.texture) + '</select> ' +
                  '<img id="tximg_' + i + '" src="' + (r.texture && TEXTURES[r.texture] ? TEXTURES[r.texture] : '') + '" style="height:26px;width:26px;object-fit:cover;vertical-align:middle;border:1px solid #ccc;border-radius:3px;' + (r.texture && TEXTURES[r.texture] ? '' : 'display:none;') + '"></td>' +
                  '<td class="th-col"><input type="number" id="th_' + i + '" step="0.25" min="0" value="' + th + '"></td></tr>');
                rows.push('<tr class="pat"><td colspan="4">' +
                  'Pattern <select id="pat_' + i + '">' + patternOptions(r.pattern) + '</select> ' +
                  'W <input type="number" id="pw_' + i + '" step="0.5" min="0" value="' + (r.unit_w || '') + '"> ' +
                  'L <input type="number" id="pl_' + i + '" step="0.5" min="0" value="' + (r.unit_l || '') + '"> ' +
                  'X <input type="number" id="px_' + i + '" step="0.5" value="' + (r.ox || 0) + '"> ' +
                  'Y <input type="number" id="py_' + i + '" step="0.5" value="' + (r.oy || 0) + '"> ' +
                  'Ang <input type="number" id="pa_' + i + '" step="5" value="' + (r.angle || 0) + '"> ' +
                  'Grout <select id="pg_' + i + '" title="Grout width, Tile pattern only">' + groutOptions(r.grout) + '</select> ' +
                  '<select id="pgc_' + i + '" title="Grout color">' + groutColorOptions(r.grout_color) + '</select> ' +
                  '<label><input type="checkbox" id="pc_' + i + '"' + (r.center ? ' checked' : '') + '> Center</label>' +
                  '</td></tr>');
                rows.push('<tr class="pat"><td colspan="4">' +
                  'Spec <input type="text" id="sp_' + i + '" style="width:150px;" placeholder="e.g. Daltile 24x24 Matte" value="' + (r.spec || '').replace(/"/g, '&quot;') + '"> ' +
                  'Grout spec <input type="text" id="gs_' + i + '" style="width:130px;" placeholder="e.g. Mapei #38" value="' + (r.grout_spec || '').replace(/"/g, '&quot;') + '">' +
                  '</td></tr>');
              });
              rows.push('</table>');
              document.getElementById('content').innerHTML = rows.join('');
            }
            function applyAll() {
              var sel = {};
              ROOMS.forEach(function(r, i) {
                sel[r.id] = {
                  type: 'Hardwood',
                  thickness: parseFloat(document.getElementById('th_' + i).value) || 0,
                  pattern: document.getElementById('pat_' + i).value,
                  unit_w: parseFloat(document.getElementById('pw_' + i).value) || 0,
                  unit_l: parseFloat(document.getElementById('pl_' + i).value) || 0,
                  ox: parseFloat(document.getElementById('px_' + i).value) || 0,
                  oy: parseFloat(document.getElementById('py_' + i).value) || 0,
                  angle: parseFloat(document.getElementById('pa_' + i).value) || 0,
                  center: document.getElementById('pc_' + i).checked,
                  texture: document.getElementById('tx_' + i).value,
                  grout: parseFloat(document.getElementById('pg_' + i).value) || 0,
                  grout_color: document.getElementById('pgc_' + i).value,
                  spec: document.getElementById('sp_' + i).value,
                  grout_spec: document.getElementById('gs_' + i).value
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

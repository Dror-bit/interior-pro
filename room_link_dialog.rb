# encoding: utf-8
# Interior Pro - THE ROOM TABLE (2026-09-06)
#
# He asked for exactly this, in his own words: a table of the rooms that
# are in the model right now, and per room either a room from the chosen
# Invoice Studio project or a name he types himself. Hunting for groups
# in the model was the thing that did not work - "זה פשוט מלא קבוצות" -
# because a room is not one group: its walls and its floor are separate
# entities.
#
# The window is a shell. Everything it decides lives in SyncBridge and is
# tested there (rt163): which rooms exist, what a line means, what
# applying the table does.
module InteriorPro
  module RoomLinkDialog
    SB = InteriorPro::SyncBridge

    def self.show
      model = Sketchup.active_model
      r = SB.read_rooms
      unless r[:ok]
        UI.messagebox(SB.rooms_problem(r))
        return nil
      end
      @dlg = UI::HtmlDialog.new(dialog_title: 'Interior Pro - Rooms',
                                preferences_key: 'InteriorProRooms',
                                width: 720, height: 460, resizable: true)
      @dlg.set_html(html(model, r[:projects]))
      wire!(@dlg, model)
      @dlg.show
      @dlg
    rescue StandardError => e
      puts "[Rooms] show: #{e.message}"
      nil
    end

    def self.wire!(dlg, model)
      dlg.add_action_callback('save') do |_c, json|
        begin
          choices = JSON.parse(json)
          n = SB.apply_choices!(model, choices)
          UI.messagebox(format("Linked %d, named %d, left %d.", n[0], n[1], n[2]))
          dlg.close
        rescue StandardError => e
          UI.messagebox("Could not save: #{e.message}")
        end
      end
      dlg.add_action_callback('highlight') do |_c, gid|
        SB.highlight!(model, gid)
      end
      dlg.add_action_callback('project') do |_c, _x|
        pr = SB.pick_project!(model)
        if pr
          dlg.close
          show
        end
      end
    end

    def self.esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
       .gsub('"', '&quot;')
    end

    def self.html(model, projects)
      pid = SB.project_id(model)
      pr = projects.find { |p| p[:id] == pid }
      rooms = pr ? pr[:rooms] : []
      lines = SB.model_rooms(model)
      opts = rooms.map do |rm|
        "<option value=\"#{esc(rm[:id])}\">#{esc(rm[:name])}</option>"
      end.join
      body = lines.map do |ln|
        sel = ln[:room_id].to_s
        own = ln[:room_id] ? '' : esc(ln[:name])
        <<~ROW
          <tr data-gid="#{esc(ln[:gid])}">
            <td class="nm" onclick="hi('#{esc(ln[:gid])}')">#{esc(ln[:name])}</td>
            <td class="ar">#{format('%.1f', ln[:area])} sq ft</td>
            <td><select class="pick">
                  <option value="">-- none --</option>#{opts}
                </select></td>
            <td><input class="own" type="text" value="#{own}" placeholder="or type a name"></td>
          </tr>
          <script>document.currentScript.previousElementSibling
            .querySelector('.pick').value = "#{esc(sel)}";</script>
        ROW
      end.join

      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
          body { font: 13px system-ui, Arial; margin: 12px; color: #222; }
          h2 { font-size: 15px; margin: 0 0 2px; }
          .proj { color: #555; margin-bottom: 10px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #eee; }
          th { color: #666; font-weight: 600; }
          .nm { cursor: pointer; text-decoration: underline dotted; }
          .ar { color: #666; white-space: nowrap; }
          select, input { width: 100%; padding: 4px; }
          .bar { margin-top: 14px; display: flex; gap: 8px; }
          button { padding: 7px 16px; }
          .none { color: #a00; }
        </style></head><body>
          <h2>Rooms in this model</h2>
          <div class="proj">Project:
            <b>#{pr ? esc(pr[:name]) : '<span class="none">not chosen</span>'}</b>
            &nbsp; <a href="#" onclick="sketchup.project('');return false;">change</a>
          </div>
          <table>
            <tr><th>room in the model</th><th>area</th>
                <th>room in Invoice Studio</th><th>or your own name</th></tr>
            #{body}
          </table>
          <div class="bar">
            <button onclick="save()">Save</button>
            <span style="color:#666;padding-top:8px">
              click a room name to highlight it in SketchUp</span>
          </div>
        <script>
          function hi(g){ sketchup.highlight(g); }
          function save(){
            var out = [];
            document.querySelectorAll('tr[data-gid]').forEach(function(tr){
              out.push({ gid: tr.getAttribute('data-gid'),
                         room_id: tr.querySelector('.pick').value,
                         name: tr.querySelector('.own').value });
            });
            sketchup.save(JSON.stringify(out));
          }
        </script></body></html>
      HTML
    end
  end
end

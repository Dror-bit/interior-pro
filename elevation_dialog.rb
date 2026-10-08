# encoding: utf-8
# Interior Pro - Elevations panel (2026-10-08)
#
# The small panel behind the Elevations button, copied field for field from
# skylight_dialog.rb (the rule: a new window is an old window copied). Pick a
# room, say how many inches from the wall are seen (empty = the whole room),
# lines or shaded, and the four elevations land on the Sheet window as
# picture sheets. It opens whole (fit_height), Escape closes it.
module InteriorPro
  module ElevationDialog
    def self.show
      if @dialog
        begin
          @dialog.close
        rescue StandardError
          nil
        end
        @dialog = nil
      end
      unless InteriorPro::ElevationTool::USE_ELEVATIONS
        UI.messagebox('Elevations are switched off (ElevationTool::USE_ELEVATIONS).')
        return
      end
      rooms = InteriorPro::ElevationTool.rooms
      if rooms.empty?
        UI.messagebox('No rooms found. Build the rooms first (Rooms button).')
        return
      end
      @rooms = rooms
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Elevations',
        preferences_key: 'InteriorPro_Elevations',
        width: 360, height: 300, resizable: true,
        min_width: 320, min_height: 220,
        max_width: 520, max_height: 700
      )
      dlg.add_action_callback('make_elevations') do |_, idx, cut, style|
        begin
          room = @rooms[idx.to_i]
          raise 'pick a room' unless room
          paths = InteriorPro::ElevationTool.make!(room, cut: cut.to_f, style: style.to_s)
          dlg.execute_script("done(#{paths.size})")
          InteriorPro::PlanSheetDialog.show unless InteriorPro::PlanSheetDialog.instance_variable_get(:@dialog)
        rescue StandardError => e
          puts "[Elevation] #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          dlg.execute_script("failed(#{e.message.to_s.inspect})")
        end
      end
      dlg.add_action_callback('close_dialog') do |_|
        begin
          dlg.close
        rescue StandardError
          nil
        end
      end
      dlg.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46
          want = 220 if want < 220
          want = 700 if want > 700
          dlg.set_size(360, want)
        rescue StandardError => e
          puts "[Elevation] fit_height: #{e.message}"
        end
      end
      dlg.set_html(build_html(rooms))
      begin
        dlg.center if dlg.respond_to?(:center)
      rescue StandardError
        nil
      end
      dlg.show
      @dialog = dlg
    end

    def self.build_html(rooms)
      et = InteriorPro::ElevationTool
      opts = rooms.each_with_index.map do |r, i|
        "<option value=\"#{i}\">#{et.room_name(r).to_s.gsub('<', '&lt;')}</option>"
      end.join
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          body { font-family: Segoe UI, Arial, sans-serif; font-size: 13px;
                 margin: 0; padding: 14px 16px; color: #222; background: #fafafa; }
          h3 { margin: 0 0 12px; font-size: 15px; }
          .row { display: flex; align-items: center; justify-content: space-between;
                 margin: 8px 0; }
          label { flex: 1; }
          select, input[type=number] { width: 130px; padding: 5px 6px; font-size: 13px;
                               border: 1px solid #bbb; border-radius: 4px; }
          .btns { display: flex; gap: 8px; margin-top: 16px; }
          button { flex: 1; padding: 9px 0; font-size: 13px; border-radius: 5px;
                   border: 1px solid #888; background: #fff; cursor: pointer; }
          button.go { background: #2b6cb0; color: #fff; border-color: #2b6cb0;
                      font-weight: 600; }
          button:disabled { opacity: .6; cursor: default; }
          #msg { min-height: 16px; margin-top: 8px; color: #555; }
          #msg.err { color: #b00; }
        </style></head><body>
        <h3>Elevations</h3>
        <div class="row"><label>Room</label><select id="room">#{opts}</select></div>
        <div class="row"><label>Seen from the wall (in)</label>
          <input type="number" id="cut" min="1" step="1" placeholder="whole room"></div>
        <div class="row"><label>Style</label>
          <select id="style"><option value="lines">Lines</option><option value="shaded">Shaded</option></select></div>
        <div id="msg"></div>
        <div class="btns">
          <button onclick="sketchup.close_dialog()">Close</button>
          <button class="go" id="go" onclick="go()">Make 4 elevations</button>
        </div>
        <script>
          function go() {
            var b = document.getElementById('go'); b.disabled = true; b.textContent = 'Working...';
            var m = document.getElementById('msg'); m.className = ''; m.textContent = '';
            sketchup.make_elevations(document.getElementById('room').value,
                                     document.getElementById('cut').value || '0',
                                     document.getElementById('style').value);
          }
          function reset() { var b = document.getElementById('go'); b.disabled = false; b.textContent = 'Make 4 elevations'; }
          function done(n) { reset(); document.getElementById('msg').textContent = n + ' elevations are on the Sheet'; }
          function failed(why) { reset(); var m = document.getElementById('msg'); m.className = 'err'; m.textContent = why; }
          document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' || e.keyCode === 27) sketchup.close_dialog();
          });
          var ipFitLast = 0, ipFitTimer = null;
          function ipFitWindow() {
            if (!window.sketchup || !sketchup.fit_height) return;
            var b = document.body, d = document.documentElement;
            var h = Math.max(b.scrollHeight, b.offsetHeight, d.scrollHeight, d.offsetHeight);
            if (Math.abs(h - ipFitLast) < 3) return;
            ipFitLast = h;
            sketchup.fit_height(h);
          }
          function ipFitSoon() { if (ipFitTimer) clearTimeout(ipFitTimer); ipFitTimer = setTimeout(ipFitWindow, 60); }
          window.addEventListener('load', ipFitSoon);
        </script>
        </body></html>
      HTML
    end
  end
end

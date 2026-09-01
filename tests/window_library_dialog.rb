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
        height: 720,
        min_width: 380,
        min_height: 340,
        resizable: true
      )

      dialog.set_html(build_html)

      dialog.add_action_callback('get_types') { |action_context|
        types = InteriorPro::WindowLibrary.all_types
        sel = (@last && @last['window_type']).to_json
        dialog.execute_script("loadTypes(#{types.to_json}, #{sel})")
      }

      dialog.add_action_callback('add_custom_type') { |action_context, name|
        types = InteriorPro::WindowLibrary.add_custom(name.to_s)
        dialog.execute_script("loadTypes(#{types.to_json}, #{name.to_json})")
      }

      dialog.add_action_callback('place_window') { |action_context, data|
        window = JSON.parse(data)
        @last = window   # remember for the next time the dialog opens (this session)
        tool.window_type = window['window_type']
        tool.width = window['width'].to_f
        tool.height = window['height'].to_f
        tool.header_height = window['header_height'].to_f
        tool.frame_width = window['frame_width'].to_f
        tool.interior_depth = window['interior_depth'].to_f
        tool.garden_depth   = window['garden_depth'].to_f if window['garden_depth']
        tool.arch_rise      = window['arch_rise'].to_f
        tool.glass_grid_style = window['glass_grid_style'] if window['glass_grid_style']
        tool.install_window = window['install_window']
        tool.exterior_trim = window['exterior_trim']
        tool.interior_casing = window['interior_casing']
        tool.exterior_casing_style = window['exterior_casing_style'] || 'none'
        tool.interior_casing_style = window['interior_casing_style'] || 'none'
        tool.preset_name = window['window_type']
        dialog.close
        Sketchup.active_model.select_tool(tool)
      }

      # IT OPENS WHOLE (2026-09-12). Same mechanism the roof and dormer panels
      # got: the PAGE measures itself once it is laid out and the window
      # follows, so a row added later can never push a button under the scroll.
      dialog.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46            # title bar + frame
          want = 340 if want < 340
          want = 1100 if want > 1100
          dialog.set_size(400, want)
        rescue StandardError => e
          puts "[Window] fit_height: #{e.message}"
        end
      end

      dialog.set_size(400, 720)
      dialog.show
    end

    def self.show_for_edit(window)
      return unless window
      @last = {
        'window_type'    => window.get_attribute('InteriorPro', 'window_type'),
        'width'          => window.get_attribute('InteriorPro', 'width_in'),
        'height'         => window.get_attribute('InteriorPro', 'height_in'),
        'header_height'  => window.get_attribute('InteriorPro', 'header_height_in'),
        'frame_width'    => window.get_attribute('InteriorPro', 'frame_width_in'),
        'interior_depth' => window.get_attribute('InteriorPro', 'interior_depth_in'),
        'garden_depth'   => window.get_attribute('InteriorPro', 'garden_depth_in'),
        'arch_rise'      => window.get_attribute('InteriorPro', 'arch_rise_in'),
        'glass_grid_style' => window.get_attribute('InteriorPro', 'glass_grid_style'),
        'exterior_casing_style' => window.get_attribute('InteriorPro', 'exterior_casing_style'),
        'interior_casing_style' => window.get_attribute('InteriorPro', 'interior_casing_style')
      }
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Edit Window',
        preferences_key: 'InteriorPro_WindowEdit',
        width: 400,
        height: 720,
        min_width: 380,
        min_height: 340,
        resizable: true
      )
      dialog.set_html(build_html)

      dialog.add_action_callback('get_types') { |action_context|
        types = InteriorPro::WindowLibrary.all_types
        sel = (@last && @last['window_type']).to_json
        dialog.execute_script("loadTypes(#{types.to_json}, #{sel})")
      }

      dialog.add_action_callback('add_custom_type') { |action_context, name|
        types = InteriorPro::WindowLibrary.add_custom(name.to_s)
        dialog.execute_script("loadTypes(#{types.to_json}, #{name.to_json})")
      }

      dialog.add_action_callback('place_window') { |action_context, data|
        settings = JSON.parse(data)
        dialog.close
        InteriorPro::WindowManager.update_window(window, settings)
      }

      # IT OPENS WHOLE (2026-09-12). Same mechanism the roof and dormer panels
      # got: the PAGE measures itself once it is laid out and the window
      # follows, so a row added later can never push a button under the scroll.
      dialog.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46            # title bar + frame
          want = 340 if want < 340
          want = 1100 if want > 1100
          dialog.set_size(400, want)
        rescue StandardError => e
          puts "[EditWindow] fit_height: #{e.message}"
        end
      end

      dialog.set_size(400, 720)
      dialog.show
    end

    # ---------- THE GABLET WINDOW'S OWN PANEL (2026-09-07) --------------
    #
    # He asked for it in his words: "צריך להיות אופציה לערוך אותו - אולי
    # אם אני לוחץ על עריכה ואז על החלון הזה נפתח אופציות שונות, וגם צריך
    # רק גודל ועוד שתי סוגים של חלונות." So this is the SHORT form of the
    # window panel: the size, the three types he was shown, and nothing
    # else. A gablet window has no header height (it is centred in the
    # wall), no casing and no host wall, so those rows are simply absent
    # rather than present and ignored.
    #
    # Apply goes to DormerManager.set_window!, which stores the numbers on
    # the DORMER and rebuilds it - the hole and the body together.
    def self.show_for_dormer_window(window, dormer)
      return unless window && dormer
      lim = InteriorPro::DormerManager.window_limits(dormer) || {}
      cur = {
        'window_type' => window.get_attribute('InteriorPro', 'window_type').to_s,
        'width'       => window.get_attribute('InteriorPro', 'width_in').to_f,
        'height'      => window.get_attribute('InteriorPro', 'height_in').to_f
      }
      dialog = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Dormer Window',
        preferences_key: 'InteriorPro_DormerWindow',
        width: 360,
        height: 330,
        min_width: 320,
        min_height: 260,
        resizable: true
      )
      dialog.set_html(dormer_window_html(cur, lim))

      dialog.add_action_callback('apply_dormer_window') { |_ctx, data|
        settings = JSON.parse(data)
        dialog.close
        model = Sketchup.active_model
        model.start_operation('Edit Dormer Window', true)
        begin
          ok = InteriorPro::DormerManager.set_window!(dormer, settings)
          if ok
            model.commit_operation
          else
            model.abort_operation
            UI.messagebox('Could not rebuild the dormer window: ' \
                          "#{InteriorPro::DormerManager.last_reason}")
          end
        rescue StandardError => e
          model.abort_operation rescue nil
          UI.messagebox("Error editing the dormer window: #{e.message}")
        end
      }

      dialog.add_action_callback('cancel_dormer_window') { |_ctx| dialog.close }

      # IT OPENS WHOLE (2026-09-12). Same mechanism the roof and dormer panels
      # got: the PAGE measures itself once it is laid out and the window
      # follows, so a row added later can never push a button under the scroll.
      dialog.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46            # title bar + frame
          want = 260 if want < 260
          want = 900 if want > 900
          dialog.set_size(360, want)
        rescue StandardError => e
          puts "[DormerWindow] fit_height: #{e.message}"
        end
      end

      dialog.set_size(360, 330)
      dialog.show
    end

    def self.dormer_window_html(cur, lim)
      types = InteriorPro::DormerManager.window_types
      labels = { 'Picture' => 'Fixed - one pane, nothing opens',
                 'Slider XO' => 'Slider - one half slides across',
                 'Double Hung' => 'Hung - opens up and down' }
      sel = types.include?(cur['window_type']) ? cur['window_type'] : types.first
      opts = types.map { |t|
        "<option value=\"#{t}\"#{t == sel ? ' selected' : ''}>#{labels[t] || t}</option>"
      }.join
      max_w = (lim[:max_w] || 48.0).round(1)
      max_h = (lim[:max_h] || 24.0).round(1)
      min_w = (lim[:min_w] || 18.0).round(1)
      min_h = (lim[:min_h] || 12.0).round(1)
      w = cur['width'].to_f > 0 ? cur['width'].to_f.round(1) : max_w
      h = cur['height'].to_f > 0 ? cur['height'].to_f.round(1) : max_h
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          /* Same rules as the full window form: room under the last
             button, scroll down but never sideways (rt26). */
          * { box-sizing: border-box; margin: 0; padding: 0; }
          html, body { height: auto; overflow-y: auto; overflow-x: hidden; }
          body { font-family: Arial, sans-serif; background: #f0f0f0; padding-bottom: 8px; }
          .header { background: #6A1B9A; color: white; padding: 7px 12px; font-size: 13px; font-weight: bold; }
          .content { padding: 8px; }
          .panel { background: white; border-radius: 6px; padding: 10px; border: 1px solid #ddd; }
          .section-title { font-size: 10px; color: #6A1B9A; font-weight: bold; text-transform: uppercase; margin-top: 7px; margin-bottom: 2px; border-bottom: 1px solid #eee; padding-bottom: 2px; }
          .section-title:first-child { margin-top: 0; }
          label { display: block; font-size: 11px; color: #555; margin-top: 4px; margin-bottom: 1px; }
          input, select { width: 100%; padding: 4px 6px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; }
          .row { display: flex; gap: 6px; }
          .row > div { flex: 1; }
          .note { font-size: 10px; color: #888; margin-top: 5px; line-height: 1.4; }
          .place-row { margin-top: 10px; display: flex; gap: 6px; }
          .btn-place { flex: 2; padding: 8px; background: #6A1B9A; color: white; border: none; border-radius: 6px; font-size: 13px; font-weight: bold; cursor: pointer; }
          .btn-place:hover { background: #4A148C; }
          .btn-cancel { flex: 1; padding: 8px; background: #eee; color: #444; border: 1px solid #ccc; border-radius: 6px; font-size: 13px; cursor: pointer; }
        </style>
        </head>
        <body>
        <div class="header">Interior Pro - Dormer Window</div>
        <div class="content">
          <div class="panel">
            <div class="section-title">Window Type</div>
            <select id="winType">#{opts}</select>

            <div class="section-title">Size</div>
            <div class="row">
              <div>
                <label>Width (in)</label>
                <input type="number" id="winWidth" value="#{w}" min="#{min_w}" max="#{max_w}" step="0.5">
              </div>
              <div>
                <label>Height (in)</label>
                <input type="number" id="winHeight" value="#{h}" min="#{min_h}" max="#{max_h}" step="0.5">
              </div>
            </div>
            <div class="note">
              This gablet has room for #{max_w}" x #{max_h}".
              A bigger number is pulled back to that; the window stays
              centred in the front wall.
            </div>

            <div class="place-row">
              <button class="btn-place" onclick="apply()">Apply</button>
              <button class="btn-cancel" onclick="sketchup.cancel_dormer_window()">Cancel</button>
            </div>
          </div>
        </div>
        <script>
          function apply() {
            var d = {
              window_type: document.getElementById('winType').value,
              width: parseFloat(document.getElementById('winWidth').value) || 0,
              height: parseFloat(document.getElementById('winHeight').value) || 0
            };
            sketchup.apply_dormer_window(JSON.stringify(d));
          }
        </script>
        <script>
          var ipFitLast = 0, ipFitTimer = null;
          function ipFitWindow() {
            if (!window.sketchup || !sketchup.fit_height) return;
            var b = document.body, d = document.documentElement;
            var h = Math.max(b.scrollHeight, b.offsetHeight, d.scrollHeight, d.offsetHeight);
            if (Math.abs(h - ipFitLast) < 3) return;
            ipFitLast = h;
            sketchup.fit_height(h);
          }
          function ipFitSoon() {
            if (ipFitTimer) clearTimeout(ipFitTimer);
            ipFitTimer = setTimeout(ipFitWindow, 60);
          }
          window.addEventListener('load', ipFitSoon);
          if (window.ResizeObserver) {
            try { new ResizeObserver(ipFitSoon).observe(document.body); } catch (e) {}
          }
          ipFitSoon();
          setTimeout(ipFitSoon, 250);
        </script>
        </body>
        </html>
      HTML
    end

    def self.build_html
      s   = @last || {}
      dw  = s['width']          || 36
      dh  = s['height']         || 48
      dhh = s['header_height']  || 80
      dfw = s['frame_width']    || 1.5
      did = s['interior_depth'] || 1
      dgd = s['garden_depth']   || 16
      dgs = s['glass_grid_style'] || 'none'
      dec = s['exterior_casing_style'] || 'none'
      dic = s['interior_casing_style'] || 'none'
      dar = s['arch_rise'] || ''
      casing_opts = (defined?(InteriorPro::MoldingLibrary) ?
        InteriorPro::MoldingLibrary.skp_names('CASING') : [])
        .map { |c| "<option value=\"#{c}\">#{c}</option>" }.join
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          /* Compact on purpose (user 2026-08-12): the WHOLE form must fit
             the dialog with NO scrolling - every margin here is load-bearing. */
          * { box-sizing: border-box; margin: 0; padding: 0; }
          html, body { height: auto; overflow-y: auto; overflow-x: hidden; }
          body { font-family: Arial, sans-serif; background: #f0f0f0; padding-bottom: 8px; }
          .header { background: #6A1B9A; color: white; padding: 7px 12px; font-size: 13px; font-weight: bold; }
          .content { padding: 8px; }
          .panel { background: white; border-radius: 6px; padding: 10px; border: 1px solid #ddd; }
          .section-title { font-size: 10px; color: #6A1B9A; font-weight: bold; text-transform: uppercase; margin-top: 7px; margin-bottom: 2px; border-bottom: 1px solid #eee; padding-bottom: 2px; }
          .section-title:first-child { margin-top: 0; }
          label { display: block; font-size: 11px; color: #555; margin-top: 4px; margin-bottom: 1px; }
          input, select { width: 100%; padding: 4px 6px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; }
          .row { display: flex; gap: 6px; }
          .row > div { flex: 1; }
          .type-row { display: flex; gap: 6px; align-items: flex-end; }
          .type-row > select { flex: 1; }
          .btn-add-type { padding: 4px 8px; background: #43A047; color: white; border: none; border-radius: 4px; font-size: 11px; cursor: pointer; white-space: nowrap; }
          .btn-add-type:hover { background: #388E3C; }
          .checkbox-row { display: flex; align-items: center; gap: 6px; margin-top: 4px; }
          .checkbox-row input { width: auto; }
          .checkbox-row label { margin: 0; }
          .place-row { margin-top: 10px; }
          .btn-place { width: 100%; padding: 8px; background: #6A1B9A; color: white; border: none; border-radius: 6px; font-size: 13px; font-weight: bold; cursor: pointer; }
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
                <input type="number" id="winWidth" value="#{dw}" min="1" step="0.5">
              </div>
              <div>
                <label>Window Height (in)</label>
                <input type="number" id="winHeight" value="#{dh}" min="1" step="0.5">
              </div>
            </div>
            <div class="row">
              <div>
                <label>Header Height (in)</label>
                <input type="number" id="headerHeight" value="#{dhh}" min="1" step="0.5">
              </div>
              <div>
                <label>Frame Width (in)</label>
                <input type="number" id="frameWidth" value="#{dfw}" min="0.25" step="0.25">
              </div>
              <div>
                <label>Interior Depth (in)</label>
                <input type="number" id="interiorDepth" value="#{did}" min="0.25" step="0.25">
              </div>
              <div>
                <label>Garden Depth (in)</label>
                <input type="number" id="gardenDepth" value="#{dgd}" min="1" step="1">
              </div>
            </div>

            <div class="section-title">Arch &amp; Glass</div>
            <div class="row">
              <div>
                <label>Arch Height (in) — blank = semicircle</label>
                <input type="number" id="archHeight" value="#{dar}" min="0" step="0.5" placeholder="auto">
              </div>
              <div>
                <label>Glass Grid</label>
                <select id="glassGridStyle">
                  <option value="none">None</option>
                  <option value="2x2">2 x 2</option>
                  <option value="3x3">3 x 3</option>
                  <option value="2x3">2 x 3</option>
                  <option value="3x2">3 x 2</option>
                </select>
              </div>
            </div>

            <div class="section-title">Install Options</div>
            <div class="checkbox-row">
              <input type="checkbox" id="installWindow" checked>
              <label for="installWindow">Install Window (frame + glass)</label>
            </div>
            <div class="section-title">Casing &amp; Trim</div>
            <div class="row">
              <div>
                <label>Exterior Casing</label>
                <select id="exteriorCasingStyle">
                  <option value="none">None</option>
                  <option value="flat">Flat (square)</option>
                  #{casing_opts}
                </select>
              </div>
              <div>
                <label>Interior Casing</label>
                <select id="interiorCasingStyle">
                  <option value="none">None</option>
                  <option value="flat">Flat (square)</option>
                  #{casing_opts}
                </select>
              </div>
            </div>

            <div class="place-row">
              <button class="btn-place" onclick="placeWindow()">Place Window on Wall</button>
            </div>
          </div>
        </div>
        <script>
          window.onload = function() {
            sketchup.get_types();
            document.getElementById('glassGridStyle').value = '#{dgs}';
            document.getElementById('exteriorCasingStyle').value = '#{dec}';
            document.getElementById('interiorCasingStyle').value = '#{dic}';
          };

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
              interior_depth: parseFloat(document.getElementById('interiorDepth').value),
              garden_depth: parseFloat(document.getElementById('gardenDepth').value),
              arch_rise: (document.getElementById('archHeight').value === '' ? 0 : parseFloat(document.getElementById('archHeight').value)),
              glass_grid_style: document.getElementById('glassGridStyle').value,
              install_window: document.getElementById('installWindow').checked,
              exterior_casing_style: document.getElementById('exteriorCasingStyle').value,
              interior_casing_style: document.getElementById('interiorCasingStyle').value,
              exterior_trim: document.getElementById('exteriorCasingStyle').value !== 'none',
              interior_casing: document.getElementById('interiorCasingStyle').value !== 'none'
            };
            sketchup.place_window(JSON.stringify(win));
          }
        </script>
        <script>
          var ipFitLast = 0, ipFitTimer = null;
          function ipFitWindow() {
            if (!window.sketchup || !sketchup.fit_height) return;
            var b = document.body, d = document.documentElement;
            var h = Math.max(b.scrollHeight, b.offsetHeight, d.scrollHeight, d.offsetHeight);
            if (Math.abs(h - ipFitLast) < 3) return;
            ipFitLast = h;
            sketchup.fit_height(h);
          }
          function ipFitSoon() {
            if (ipFitTimer) clearTimeout(ipFitTimer);
            ipFitTimer = setTimeout(ipFitWindow, 60);
          }
          window.addEventListener('load', ipFitSoon);
          if (window.ResizeObserver) {
            try { new ResizeObserver(ipFitSoon).observe(document.body); } catch (e) {}
          }
          ipFitSoon();
          setTimeout(ipFitSoon, 250);
        </script>
        </body>
        </html>
      HTML
    end

  end
end

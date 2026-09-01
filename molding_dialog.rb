# Interior Pro - Molding Dialog
# Visual profile pickers (thumbnails generated from the actual profile
# geometry) + Apply to House / Remove All.

module InteriorPro
  module MoldingDialog

    def self.show
      MoldingLibrary.clear_profile_cache!
      base = MoldingLibrary.baseboard_names.map do |n|
        { 'name' => n, 'pts' => norm_pts(MoldingLibrary.baseboard_profile_by_name(n)) }
      end
      crown = MoldingLibrary.crown_names.map do |n|
        { 'name' => n, 'pts' => norm_pts(MoldingLibrary.crown_profile_by_name(n, 12.0)) }
      end

      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Molding',
        preferences_key: 'InteriorPro_Molding',
        width: 400, height: 620, resizable: true
      )
      dlg.add_action_callback('apply') do |_, b, c, bh, ch, cm|
        # Apply to House = the whole house: clear previous exclusions.
        MoldingManager.include_all_walls!
        MoldingManager.apply_all!(base_name: (b.to_s.empty? ? nil : b),
                                  crown_name: (c.to_s.empty? ? nil : c),
                                  base_h: (bh.to_f > 0.01 ? bh.to_f : nil),
                                  crown_h: (ch.to_f > 0.01 ? ch.to_f : nil),
                                  color_mode: (cm.to_s.empty? ? nil : cm))
      end
      dlg.add_action_callback('apply_sel') do |_, b, c, bh, ch, cm|
        MoldingManager.apply_to_selection!(base_name: (b.to_s.empty? ? nil : b),
                                           crown_name: (c.to_s.empty? ? nil : c),
                                           base_h: (bh.to_f > 0.01 ? bh.to_f : nil),
                                           crown_h: (ch.to_f > 0.01 ? ch.to_f : nil),
                                           color_mode: (cm.to_s.empty? ? nil : cm))
      end
      dlg.add_action_callback('remove') { |_| MoldingManager.remove_all! }
      dlg.set_html(build_html(base, crown, MoldingBuilder.color_mode(Sketchup.active_model)))
      # IT OPENS WHOLE (2026-09-12). Same mechanism the roof and dormer panels
      # got: the PAGE measures itself once it is laid out and the window
      # follows, so a row added later can never push a button under the scroll.
      dlg.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46            # title bar + frame
          want = 380 if want < 380
          want = 1000 if want > 1000
          dlg.set_size(400, want)
        rescue StandardError => e
          puts "[Molding] fit_height: #{e.message}"
        end
      end

      dlg.show
      @dialog = dlg
    end

    # Scale profile points into a 96x96 viewBox (SVG y grows downward).
    def self.norm_pts(prof)
      return [] unless prof && prof.length > 2
      xs = prof.map { |p| p[0] }
      zs = prof.map { |p| p[1] }
      w = [xs.max - xs.min, 0.01].max
      h = [zs.max - zs.min, 0.01].max
      s = 80.0 / [w, h].max
      prof.map do |x, z|
        [((x - xs.min) * s + 8).round(1), (88 - (z - zs.min) * s).round(1)]
      end
    end

    def self.build_html(base, crown, color_mode = 'white')
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
          body { font-family: Arial, sans-serif; font-size: 13px; margin: 12px; background: #fff; }
          .section-title { font-weight: bold; margin: 12px 0 6px; color: #5d4037; }
          .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
          .card { border: 2px solid #ddd; border-radius: 6px; padding: 4px; text-align: center;
                  cursor: pointer; background: #fafafa; }
          .card:hover { border-color: #a1887f; }
          .card.selected { border-color: #5d4037; background: #efebe9; }
          .card svg { width: 100%; height: 64px; }
          .card .nm { font-size: 11px; color: #444; margin-top: 2px; }
          button { width: 100%; padding: 10px; margin-top: 12px; border: none; border-radius: 6px;
                   background: #5d4037; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
          .hrow { margin: 6px 0 2px; color: #444; }
          .hrow input { width: 70px; padding: 3px; }
        </style></head><body>
          <div class="section-title">Baseboard</div>
          <div class="grid" id="baseGrid"></div>
          <div class="hrow">Height (in): <input id="baseH" type="number" step="0.25" min="0" placeholder="auto"></div>
          <div class="section-title">Crown (Ceiling)</div>
          <div class="grid" id="crownGrid"></div>
          <div class="hrow">Height (in): <input id="crownH" type="number" step="0.25" min="0" placeholder="auto"></div>
          <button onclick="applyAll()">Apply to House</button>
          <button onclick="applySel()">Apply to Selected Walls</button>
          <button class="secondary" onclick="sketchup.remove()">Remove All</button>
          <script>
            var BASE = #{base.to_json};
            var CROWN = #{crown.to_json};
            var selBase = BASE.length ? BASE[0].name : '';
            var selCrown = CROWN.length ? CROWN[0].name : '';

            function thumb(item) {
              if (!item) return '<svg viewBox="0 0 96 96"><circle cx="48" cy="48" r="20" fill="none" stroke="#bbb" stroke-width="2"/><line x1="34" y1="62" x2="62" y2="34" stroke="#bbb" stroke-width="2"/></svg>';
              var pts = item.pts.map(function(p) { return p[0] + ',' + p[1]; }).join(' ');
              return '<svg viewBox="0 0 96 96"><polygon points="' + pts + '" fill="#e8e6e1" stroke="#555" stroke-width="1.5"/></svg>';
            }
            function render(gridId, items, sel, kind) {
              var cards = ['<div class="card' + (sel === '' ? ' selected' : '') + '" onclick="pick(\\'' + kind + '\\', \\'\\')">' + thumb(null) + '<div class="nm">None</div></div>'];
              items.forEach(function(it) {
                cards.push('<div class="card' + (it.name === sel ? ' selected' : '') + '" onclick="pick(\\'' + kind + '\\', \\'' + it.name + '\\')">' + thumb(it) + '<div class="nm">' + it.name + '</div></div>');
              });
              document.getElementById(gridId).innerHTML = cards.join('');
            }
            function pick(kind, name) {
              if (kind === 'base') selBase = name; else selCrown = name;
              renderAll();
            }
            function renderAll() {
              render('baseGrid', BASE, selBase, 'base');
              render('crownGrid', CROWN, selCrown, 'crown');
            }
            function colorMode() {
              // Color picker removed from the UI for now — always white.
              return 'white';
            }
            function applyAll() {
              sketchup.apply(selBase, selCrown,
                             document.getElementById('baseH').value,
                             document.getElementById('crownH').value,
                             colorMode());
            }
            function applySel() {
              sketchup.apply_sel(selBase, selCrown,
                                 document.getElementById('baseH').value,
                                 document.getElementById('crownH').value,
                                 colorMode());
            }
            renderAll();
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
        </body></html>
      HTML
    end

  end
end

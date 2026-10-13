# encoding: utf-8
# Interior Pro - THE ELECTRICAL WINDOW (2026-10-12, step 1)
#
# Copied from the Plumbing window (fixture_dialog.rb), field by field: same
# look, same gallery of pictures, same fit_height so it opens whole
# (CLAUDE.md, 2026-09-18), same names for the numbers ('kind', 'height').
#
#   Kind      - pictures: Outlet, Switch
#   Switches  - pictures: 1 to 5 on one plate (only for a switch)
#   Height    - from the floor to the MIDDLE of the plate
#
# show(prefill) { |cfg| ... } - the block runs on OK with the numbers.
require 'json'

module InteriorPro
  module ElectricalDialog
    def self.defaults
      k = InteriorPro::ElectricalLibrary.kinds.keys.first
      { 'kind' => k, 'gangs' => 1, 'height' => InteriorPro::ElectricalLibrary.default_height(k) }
    end

    # What he chose last time, so the second one is one click away.
    def self.last
      @last ||= defaults
    end

    def self.catalog
      out = {}
      InteriorPro::ElectricalLibrary.kinds.each do |k, info|
        out[k] = { 'label' => info[:label], 'height' => info[:height], 'gangs' => info[:gangs] ? true : false }
      end
      out
    end

    def self.show(prefill = nil, button: 'Place', &on_ok)
      data = defaults.merge(last).merge(prefill || {})
      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      @on_ok = on_ok
      dlg = UI::HtmlDialog.new(dialog_title: 'Interior Pro - Electrical', preferences_key: 'InteriorPro_Electrical',
                               width: 470, height: 300, resizable: true)
      dlg.add_action_callback('ok') do |_, json|
        cfg = JSON.parse(json)
        cfg = defaults.merge(cfg.select { |k, _| defaults.key?(k) })
        cfg['kind'] = InteriorPro::ElectricalLibrary.kind_ok(cfg['kind'])
        cfg['gangs'] = InteriorPro::ElectricalLibrary.gangs_ok(cfg['kind'], cfg['gangs'])
        cfg['height'] = cfg['height'].to_f
        if cfg['height'] <= 0.0
          UI.messagebox('Type the height from the floor to its middle, e.g.  18')
          next
        end
        @last = cfg
        begin; dlg.close; rescue StandardError; end
        @dialog = nil
        @on_ok.call(cfg) if @on_ok
      end
      dlg.add_action_callback('cancel') do |_|
        begin; dlg.close; rescue StandardError; end
        @dialog = nil
      end
      dlg.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46
          want = 260 if want < 260
          want = 900 if want > 900
          dlg.set_size(470, want)
        rescue StandardError => e
          puts "[Electrical] fit_height: #{e.message}"
        end
      end
      dlg.set_html(build_html(data, catalog, button))
      dlg.show
      @dialog = dlg
    end

    def self.build_html(d, cat, button = 'Place')
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
          body { font-family: Arial, sans-serif; font-size: 13px; margin: 12px; background: #fff; }
          .section-title { font-weight: bold; margin: 0 0 8px; color: #5d4037; }
          .row { padding: 6px 0; border-top: 1px solid #eee; font-size: 11px; color: #555; }
          .row.first { border-top: none; }
          .row input[type=number] { width: 54px; padding: 2px; }
          .grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 6px; margin-top: 6px; }
          .design-card { border: 2px solid #ddd; border-radius: 4px; padding: 3px 2px 2px; cursor: pointer; text-align: center; background: #fafafa; }
          .design-card:hover { border-color: #a1887f; }
          .design-card.selected { border-color: #5d4037; background: #f0e8e4; }
          .design-card svg { width: 100%; height: 64px; display: block; }
          .design-card .dn { font-size: 9px; color: #555; margin-top: 2px; line-height: 1.1; min-height: 20px; }
          button { width: 100%; padding: 10px; margin-top: 10px; border: none; border-radius: 6px;
                   background: #5d4037; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
        </style></head><body>
          <div class="section-title">Electrical</div>
          <div class="row first">Kind<div class="grid" id="kindGrid"></div></div>
          <div class="row" id="gangRow" style="display:none;">Switches<div class="grid" id="gangGrid"></div></div>
          <div class="row" id="heightRow">
            Height from the floor to the middle of it <input type="number" id="height" step="0.5" min="0"> in
          </div>
          <div class="row" id="helpRow">After you click Place: move along a wall - it stays at this height.
            Type a number + Enter = that far from the nearer corner to its middle.</div>
          <button onclick="okAll()">#{button}</button>
          <button class="secondary" onclick="sketchup.cancel()">Cancel</button>
          <script>
            var D = #{d.to_json};
            var CAT = #{cat.to_json};
            var kind = CAT[D.kind] ? D.kind : Object.keys(CAT)[0];
            var gangs = Math.max(1, Math.min(5, parseInt(D.gangs, 10) || 1));
            // The plate as he will see it: 2.75 x 4.5, +1.8125 a switch.
            function plateSvg(k, n) {
              var W = 2.75 + (n - 1) * 1.8125, H = 4.5, s = 76 / Math.max(W, H);
              var w = W * s, h = H * s, x0 = 48 - w / 2, y0 = 48 - h / 2;
              var o = '<rect x="' + x0 + '" y="' + y0 + '" width="' + w + '" height="' + h + '" rx="2" fill="#fff" stroke="#555" stroke-width="1.5"/>';
              if (k === 'outlet') {
                [-0.75, 0.75].forEach(function(dz) {
                  var cy = 48 + dz * s;
                  o += '<rect x="' + (48 - 0.65 * s) + '" y="' + (cy - 0.6 * s) + '" width="' + (1.3 * s) + '" height="' + (1.2 * s) + '" rx="' + (0.45 * s) + '" fill="#f2f2f2" stroke="#777"/>';
                  o += '<rect x="' + (48 - 0.34 * s) + '" y="' + (cy - 0.42 * s) + '" width="' + (0.08 * s) + '" height="' + (0.37 * s) + '" fill="#333"/>';
                  o += '<rect x="' + (48 + 0.26 * s) + '" y="' + (cy - 0.42 * s) + '" width="' + (0.08 * s) + '" height="' + (0.37 * s) + '" fill="#333"/>';
                  o += '<ellipse cx="48" cy="' + (cy + 0.31 * s) + '" rx="' + (0.1 * s) + '" ry="' + (0.12 * s) + '" fill="#333"/>';
                });
              } else {
                for (var i = 0; i < n; i++) {
                  var cx = x0 + (2.75 / 2 + i * 1.8125) * s;
                  o += '<rect x="' + (cx - 0.17 * s) + '" y="' + (48 - 0.45 * s) + '" width="' + (0.34 * s) + '" height="' + (0.9 * s) + '" fill="#f2f2f2" stroke="#777"/>';
                  o += '<rect x="' + (cx - 0.1 * s) + '" y="' + (48 - 0.4 * s) + '" width="' + (0.2 * s) + '" height="' + (0.4 * s) + '" fill="#bbb"/>';
                }
              }
              return '<svg viewBox="0 0 96 96">' + o + '</svg>';
            }
            function card(sel, pic, name, click) {
              return '<div class="design-card' + (sel ? ' selected' : '') + '" onclick="' + click + '">' + pic +
                     '<div class="dn">' + name + '</div></div>';
            }
            function render() {
              document.getElementById('kindGrid').innerHTML = Object.keys(CAT).map(function(k) {
                return card(k === kind, plateSvg(k, 1), CAT[k].label, "pickKind('" + k + "')");
              }).join('');
              document.getElementById('gangRow').style.display = CAT[kind].gangs ? '' : 'none';
              var g = '';
              for (var n = 1; n <= 5; n++) g += card(n === gangs, plateSvg('switch', n), String(n), 'pickGangs(' + n + ')');
              document.getElementById('gangGrid').innerHTML = g;
            }
            function pickKind(k) {
              if (k !== kind) document.getElementById('height').value = CAT[k].height;
              kind = k;
              render();
            }
            function pickGangs(n) { gangs = n; render(); }
            function okAll() {
              sketchup.ok(JSON.stringify({ kind: kind, gangs: CAT[kind].gangs ? gangs : 1,
                                           height: parseFloat(document.getElementById('height').value) || 0 }));
            }
            // Escape closes the window (iron law 1)
            document.addEventListener('keydown', function(e) { if (e.keyCode === 27) sketchup.cancel(); });
            document.getElementById('height').value = D.height;
            render();
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

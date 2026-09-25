# encoding: utf-8
# Interior Pro - THE PLUMBING WINDOW (2026-09-25, step 1)
#
# Copied from the Shower Floor window (shower_floor_dialog.rb): same
# look, same gallery of pictures as the drains / door handles, same
# fit_height so it opens whole (CLAUDE.md, 2026-09-18).
#
#   Kind     - pictures: Shower head, Toilet
#   Product  - pictures: 'Simple' (built-in boxes) + every .skp in the
#              kind's folder, and "+ Add new..." to bring in any .skp
#   Height   - from the floor to the BOTTOM of the fixture
#
# show(prefill) { |cfg| ... } - the block runs on OK with the numbers.
require 'json'

module InteriorPro
  module FixtureDialog
    def self.defaults
      { 'kind' => 'shower_head', 'product' => InteriorPro::FixtureLibrary::SIMPLE,
        'height' => InteriorPro::FixtureLibrary.default_height('shower_head') }
    end

    # What he chose last time, so the second fixture is one click away.
    def self.last
      @last ||= defaults
    end

    def self.url_of(path)
      'file:///' + path.tr('\\', '/').gsub(' ', '%20')
    end

    # Every kind with its products and their pictures ('' = draw it).
    def self.catalog
      model = Sketchup.active_model
      out = {}
      InteriorPro::FixtureLibrary.kinds.each do |k, info|
        prods = InteriorPro::FixtureLibrary.products(k).map do |n|
          tp = InteriorPro::FixtureLibrary.ensure_thumb(model, k, n)
          { 'name' => n, 'img' => tp && File.exist?(tp) ? url_of(tp) + "?#{File.mtime(tp).to_i}" : '' }
        end
        out[k] = { 'label' => info[:label], 'height' => info[:height], 'products' => prods }
      end
      out
    end

    def self.show(prefill = nil, &on_ok)
      data = defaults.merge(last).merge(prefill || {})
      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      @on_ok = on_ok
      dlg = UI::HtmlDialog.new(dialog_title: 'Interior Pro - Plumbing', preferences_key: 'InteriorPro_Fixture',
                               width: 470, height: 300, resizable: true)
      dlg.add_action_callback('ok') do |_, json|
        cfg = JSON.parse(json)
        cfg = defaults.merge(cfg.select { |k, _| defaults.key?(k) })
        cfg['kind'] = InteriorPro::FixtureLibrary.kind_ok(cfg['kind'])
        cfg['height'] = cfg['height'].to_f
        if cfg['height'] < 0.0
          UI.messagebox('Type the height from the floor, e.g.  80')
          next
        end
        @last = cfg.dup
        begin; dlg.close; rescue StandardError; end
        @dialog = nil
        @on_ok.call(cfg) if @on_ok
      end
      dlg.add_action_callback('cancel') do |_|
        begin; dlg.close; rescue StandardError; end
        @dialog = nil
      end
      # "+ Add new": pick any .skp, copy it into the kind's folder, and
      # open the window again with it chosen.
      dlg.add_action_callback('add_new') do |_, json|
        cur = JSON.parse(json) rescue {}
        kind = InteriorPro::FixtureLibrary.kind_ok(cur['kind'])
        src = UI.openpanel('Choose a SketchUp file', '', 'SketchUp Files|*.skp||')
        name = src ? InteriorPro::FixtureLibrary.add_file!(kind, src) : nil
        UI.messagebox('That file could not be added - see the Ruby Console.') if src && name.nil?
        cur['product'] = name if name
        show(cur, &@on_ok)
      end
      dlg.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46
          want = 260 if want < 260
          want = 900 if want > 900
          dlg.set_size(470, want)
        rescue StandardError => e
          puts "[Fixture] fit_height: #{e.message}"
        end
      end
      dlg.set_html(build_html(data, catalog))
      dlg.show
      @dialog = dlg
    end

    def self.build_html(d, cat)
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
          .design-card svg, .design-card img { width: 100%; height: 64px; object-fit: contain; display: block; }
          .design-card .dn { font-size: 9px; color: #555; margin-top: 2px; line-height: 1.1; min-height: 20px; word-break: break-word; }
          .design-card.add { border-style: dashed; color: #5d4037; }
          .design-card.add .plus { font-size: 34px; line-height: 64px; height: 64px; }
          button { width: 100%; padding: 10px; margin-top: 10px; border: none; border-radius: 6px;
                   background: #5d4037; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
        </style></head><body>
          <div class="section-title">Plumbing</div>
          <div class="row first">Kind<div class="grid" id="kindGrid"></div></div>
          <div class="row">Product<div class="grid" id="prodGrid"></div></div>
          <div class="row">
            Height from the floor to the bottom of it <input type="number" id="height" step="0.5" min="0"> in
          </div>
          <div class="row">After you click Place: move along a wall - it stays at this height.
            Type a number + Enter = that far from the nearer corner to its middle.</div>
          <button onclick="okAll()">Place</button>
          <button class="secondary" onclick="sketchup.cancel()">Cancel</button>
          <script>
            var D = #{d.to_json};
            var CAT = #{cat.to_json};
            var kind = CAT[D.kind] ? D.kind : 'shower_head';
            var product = D.product;
            function kindSvg(k) {
              var s = '';
              if (k === 'toilet') {
                s = '<rect x="26" y="14" width="44" height="30" rx="3" fill="#f4f4f4" stroke="#777"/>' +
                    '<ellipse cx="48" cy="62" rx="20" ry="24" fill="#fff" stroke="#777"/>' +
                    '<ellipse cx="48" cy="64" rx="12" ry="15" fill="#dfe9ee" stroke="#999"/>';
              } else {
                s = '<rect x="14" y="10" width="8" height="76" fill="#ddd" stroke="#999"/>' +
                    '<path d="M22 24 L52 24 L58 30" stroke="#777" stroke-width="4" fill="none"/>' +
                    '<ellipse cx="62" cy="34" rx="18" ry="6" fill="#c9d0d3" stroke="#555"/>';
                for (var i = 0; i < 5; i++) s += '<line x1="' + (52 + i * 5) + '" y1="42" x2="' + (48 + i * 6) + '" y2="80" stroke="#6aa6d8" stroke-dasharray="3 4"/>';
              }
              return '<svg viewBox="0 0 96 96">' + s + '</svg>';
            }
            function card(sel, pic, name, click) {
              return '<div class="design-card' + (sel ? ' selected' : '') + '" onclick="' + click + '">' + pic +
                     '<div class="dn">' + name + '</div></div>';
            }
            function renderKinds() {
              document.getElementById('kindGrid').innerHTML = Object.keys(CAT).map(function(k) {
                return card(k === kind, kindSvg(k), CAT[k].label, "pickKind('" + k + "')");
              }).join('');
            }
            function renderProducts() {
              var list = CAT[kind].products;
              if (!list.some(function(p) { return p.name === product; })) product = list[0].name;
              var html = list.map(function(p, i) {
                var pic = p.img ? '<img src="' + p.img + '">' : kindSvg(kind);
                return card(p.name === product, pic, p.name, 'pickProduct(' + i + ')');
              }).join('');
              html += '<div class="design-card add" onclick="addNew()"><div class="plus">+</div><div class="dn">Add new...</div></div>';
              document.getElementById('prodGrid').innerHTML = html;
            }
            function pickKind(k) {
              if (k !== kind) document.getElementById('height').value = CAT[k].height;
              kind = k;
              renderKinds();
              renderProducts();
            }
            function pickProduct(i) { product = CAT[kind].products[i].name; renderProducts(); }
            function cur() {
              return { kind: kind, product: product, height: parseFloat(document.getElementById('height').value) || 0 };
            }
            function addNew() { sketchup.add_new(JSON.stringify(cur())); }
            function okAll() { sketchup.ok(JSON.stringify(cur())); }
            document.getElementById('height').value = D.height;
            renderKinds();
            renderProducts();
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

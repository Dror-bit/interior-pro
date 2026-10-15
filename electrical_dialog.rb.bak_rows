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
    def self.defaults(group = 'electrical')
      k = InteriorPro::ElectricalLibrary.kinds_in(group).first || InteriorPro::ElectricalLibrary.kinds.keys.first
      { 'kind' => k, 'product' => InteriorPro::ElectricalLibrary.products(k).first, 'gangs' => 1,
        'height' => InteriorPro::ElectricalLibrary.default_height(k), 'turn' => 0, 'countertop' => false }
    end

    # What he chose last time, so the second one is one click away.
    # One a window: the Electrical window and the Lighting window each
    # remember their own.
    def self.last(group = 'electrical')
      @last = {} unless @last.is_a?(Hash) && !@last.key?('kind')
      @last[group] ||= defaults(group)
    end

    def self.title_of(group)
      group == 'lighting' ? 'Lighting' : 'Electrical'
    end

    def self.url_of(path)
      'file:///' + path.tr('\\', '/').gsub(' ', '%20')
    end

    # Every kind with its products and their pictures ('' = draw it).
    def self.catalog(group = 'electrical')
      model = Sketchup.active_model
      out = {}
      InteriorPro::ElectricalLibrary.kinds.each do |k, info|
        next unless InteriorPro::ElectricalLibrary.group_of(k) == group
        # a kind made only of his files shows only when the folder has one
        next if info[:files_only] && InteriorPro::ElectricalLibrary.products(k).empty?
        next if info[:mount] == 'ceiling' && !InteriorPro::ElectricalLibrary::USE_CEILING_MOUNT
        prods = InteriorPro::ElectricalLibrary.products(k).map do |n|
          tp = InteriorPro::ElectricalLibrary.ensure_thumb(model, k, n)
          { 'name' => n, 'img' => tp && File.exist?(tp) ? url_of(tp) + "?#{File.mtime(tp).to_i}" : '' }
        end
        out[k] = { 'label' => info[:label], 'height' => info[:height], 'gangs' => info[:gangs] ? true : false,
                   'ceiling' => info[:mount] == 'ceiling',
                   'products' => prods }
      end
      out
    end

    def self.show(prefill = nil, button: 'Place', group: 'electrical', &on_ok)
      @group = group
      if catalog(group).empty?
        UI.messagebox("No #{title_of(group)} files yet - put a .skp in assets\\ELECTRICAL\\WALL_LIGHTS")
        return nil
      end
      data = defaults(group).merge(last(group)).merge(prefill || {})
      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      @on_ok = on_ok
      @button = button
      dlg = UI::HtmlDialog.new(dialog_title: "Interior Pro - #{title_of(group)}", preferences_key: "InteriorPro_#{title_of(group)}",
                               width: 470, height: 300, resizable: true)
      dlg.add_action_callback('ok') do |_, json|
        cfg = JSON.parse(json)
        cfg = defaults(group).merge(cfg.select { |k, _| defaults(group).key?(k) })
        cfg['kind'] = InteriorPro::ElectricalLibrary.kind_ok(cfg['kind'])
        cfg['product'] = cfg['product'].to_s
        cfg['gangs'] = InteriorPro::ElectricalLibrary.gangs_ok(cfg['kind'], cfg['gangs'])
        cfg['height'] = cfg['height'].to_f
        cfg['turn'] = cfg['turn'].to_i == 90 ? 90 : 0
        cfg['countertop'] = InteriorPro::ElectricalLibrary.countertop_of(cfg.merge('countertop' => cfg['countertop'] == true))
        if cfg['height'] <= 0.0 && !InteriorPro::ElectricalLibrary.ceiling?(cfg['kind'])
          UI.messagebox('Type the height from the floor to its middle, e.g.  18')
          next
        end
        last(group)
        @last[group] = cfg
        begin; dlg.close; rescue StandardError; end
        @dialog = nil
        @on_ok.call(cfg) if @on_ok
      end
      # "+ Add new": pick any .skp, copy it into the kind's folder, and
      # open the window again with it chosen.
      dlg.add_action_callback('add_new') do |_, json|
        cur = JSON.parse(json) rescue {}
        kind = InteriorPro::ElectricalLibrary.kind_ok(cur['kind'])
        src = UI.openpanel('Choose a SketchUp file', '', 'SketchUp Files|*.skp||')
        name = src ? InteriorPro::ElectricalLibrary.add_file!(kind, src) : nil
        UI.messagebox('That file could not be added - see the Ruby Console.') if src && name.nil?
        cur['product'] = name if name
        show(cur, button: @button, group: group, &@on_ok)
      end
      # "Save selected": the ONE group or component selected in the model
      # is saved into the kind's folder. Select it BEFORE clicking Electrical.
      dlg.add_action_callback('save_selected') do |_, json|
        cur = JSON.parse(json) rescue {}
        kind = InteriorPro::ElectricalLibrary.kind_ok(cur['kind'])
        sel = Sketchup.active_model.selection.to_a
        ent = sel.length == 1 ? sel.first : nil
        unless ent && InteriorPro::FixtureLibrary.saveable?(ent)
          UI.messagebox("Select ONE group or component in the model first (now: #{sel.length} selected).\n" \
                        'Then click Electrical and Save selected.')
          next
        end
        guess = ent.name.to_s.strip
        guess = ent.definition.name.to_s if guess.empty? && ent.respond_to?(:definition)
        res = UI.inputbox(['Name'], [guess], "Save #{InteriorPro::ElectricalLibrary.kinds[kind][:label]}")
        next unless res
        name = InteriorPro::ElectricalLibrary.save_selected!(kind, ent, res[0])
        UI.messagebox('It could not be saved - see the Ruby Console.') if name.nil?
        cur['product'] = name if name
        show(cur, button: @button, group: group, &@on_ok)
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
      dlg.set_html(build_html(data, catalog(group), button, title_of(group)))
      dlg.show
      @dialog = dlg
    end

    def self.build_html(d, cat, button = 'Place', title = 'Electrical')
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
          .design-card img.lying, .design-card svg.lying { transform: rotate(90deg); }
          .design-card.add { border-style: dashed; color: #5d4037; }
          .design-card.add .plus { font-size: 34px; line-height: 64px; height: 64px; }
          .design-card .dn { font-size: 9px; color: #555; margin-top: 2px; line-height: 1.1; min-height: 20px; }
          button { width: 100%; padding: 10px; margin-top: 10px; border: none; border-radius: 6px;
                   background: #5d4037; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
        </style></head><body>
          <div class="section-title">#{title}</div>
          <div class="row first">Kind<div class="grid" id="kindGrid"></div></div>
          <div class="row">Product<div class="grid" id="prodGrid"></div></div>
          <div class="row" id="turnRow" style="display:none;">Position<div class="grid" id="turnGrid"></div></div>
          <div class="row" id="counterRow" style="display:none;"><label><input type="checkbox" id="counter" onchange="pickCounter(this.checked)"> Countertop outlet</label></div>
          <div class="row" id="gangRow" style="display:none;">Switches<div class="grid" id="gangGrid"></div></div>
          <div class="row" id="heightRow">
            Height from the floor to the middle of it <input type="number" id="height" step="0.5" min="0"> in
          </div>
          <button onclick="okAll()">#{button}</button>
          <button class="secondary" onclick="sketchup.cancel()">Cancel</button>
          <script>
            var D = #{d.to_json};
            var CAT = #{cat.to_json};
            var kind = CAT[D.kind] ? D.kind : Object.keys(CAT)[0];
            var gangs = Math.max(1, Math.min(5, parseInt(D.gangs, 10) || 1));
            var product = D.product;
            var turn = parseInt(D.turn, 10) === 90 ? 90 : 0;
            var counter = D.countertop === true;
            var COUNTER_H = #{InteriorPro::ElectricalLibrary::COUNTERTOP_H};
            var USE_COUNTER = #{InteriorPro::ElectricalLibrary::USE_COUNTERTOP ? 'true' : 'false'};
            function curProduct() {
              var list = CAT[kind].products;
              for (var i = 0; i < list.length; i++) if (list[i].name === product) return list[i];
              return list[0];
            }
            // a kind of his files only: its first file's picture is the kind's picture
            function picOfKind(k) { var p = CAT[k].products[0]; return p && p.img ? '<img src="' + p.img + '">' : ''; }
            function picOf(p) { return p.img ? '<img src="' + p.img + '">' : plateSvg(kind, 1); }
            // The plate as he will see it: 2.75 x 4.5, +1.8125 a switch.
            function plateSvg(k, n) {
              var W = 2.75 + (n - 1) * 1.8125, H = 4.5, s = 76 / Math.max(W, H);
              var w = W * s, h = H * s, x0 = 48 - w / 2, y0 = 48 - h / 2;
              var o = '<rect x="' + x0 + '" y="' + y0 + '" width="' + w + '" height="' + h + '" rx="2" fill="#fff" stroke="#555" stroke-width="1.5"/>';
              if (k === 'outlet') {
                [-0.95, 0.95].forEach(function(dz) {
                  var cy = 48 + dz * s;
                  o += '<rect x="' + (48 - 0.65 * s) + '" y="' + (cy - 0.6 * s) + '" width="' + (1.3 * s) + '" height="' + (1.2 * s) + '" rx="' + (0.45 * s) + '" fill="#f2f2f2" stroke="#777"/>';
                  o += '<rect x="' + (48 - 0.34 * s) + '" y="' + (cy - 0.42 * s) + '" width="' + (0.08 * s) + '" height="' + (0.37 * s) + '" fill="#333"/>';
                  o += '<rect x="' + (48 + 0.26 * s) + '" y="' + (cy - 0.42 * s) + '" width="' + (0.08 * s) + '" height="' + (0.37 * s) + '" fill="#333"/>';
                  o += '<ellipse cx="48" cy="' + (cy + 0.31 * s) + '" rx="' + (0.1 * s) + '" ry="' + (0.12 * s) + '" fill="#333"/>';
                });
              } else {
                // flat rocker switches (his pick: "more modern")
                for (var i = 0; i < n; i++) {
                  var cx = x0 + (2.75 / 2 + i * 1.8125) * s;
                  o += '<rect x="' + (cx - 0.66 * s) + '" y="' + (48 - 1.31 * s) + '" width="' + (1.32 * s) + '" height="' + (2.62 * s) + '" rx="1" fill="#e9e7e1" stroke="#999"/>';
                  o += '<rect x="' + (cx - 0.6 * s) + '" y="' + (48 - 1.25 * s) + '" width="' + (1.2 * s) + '" height="' + (2.5 * s) + '" rx="1" fill="#fdfcf9" stroke="#bbb"/>';
                }
              }
              return '<svg viewBox="0 0 96 96">' + o + '</svg>';
            }
            function card(sel, pic, name, click) {
              return '<div class="design-card' + (sel ? ' selected' : '') + '" onclick="' + click + '">' + pic +
                     '<div class="dn">' + inches(name) + '</div></div>';
            }
            // "Recessed 6in Round White" is shown as  Recessed 6" Round White
            // (his words: "שתרשום שאחת היא 6 ואחת היא 4"); the file keeps its name
            function inches(name) {
              // his words: "תרשום רק את סוג המנורה ואת הגודל שלה" - Recessed 4"
              var m = String(name).match(/([0-9]+)in( |$)/);
              if (m && CAT[kind] && !CAT[kind].gangs && kind !== 'outlet') return CAT[kind].label + ' ' + m[1] + '&quot;';
              return String(name).replace(/([0-9]+)in( |$)/g, '$1&quot;$2');
            }
            function render() {
              document.getElementById('kindGrid').innerHTML = Object.keys(CAT).map(function(k) {
                var icon = (k === 'outlet' || k === 'switch') ? plateSvg(k, 1) : picOfKind(k);
                return card(k === kind, icon, CAT[k].label, "pickKind('" + k + "')");
              }).join('');
              var list = CAT[kind].products;
              if (!list.some(function(p) { return p.name === product; })) product = list[0].name;
              var html = list.map(function(p, i) { return card(p.name === product, picOf(p), p.name, 'pickProduct(' + i + ')'); }).join('');
              html += '<div class="design-card add" onclick="addNew()"><div class="plus">+</div><div class="dn">Add new...</div></div>';
              html += '<div class="design-card add" onclick="saveSel()"><div class="plus">&#8595;</div><div class="dn">Save selected</div></div>';
              document.getElementById('prodGrid').innerHTML = html;
              // the switches count is only for the built-in stand-in; his file is what it is
              document.getElementById('gangRow').style.display = (CAT[kind].gangs && product === 'Simple') ? '' : 'none';
              var g = '';
              for (var n = 1; n <= 5; n++) g += card(n === gangs, plateSvg('switch', n), String(n), 'pickGangs(' + n + ')');
              document.getElementById('gangGrid').innerHTML = g;
              // POSITION (his words: "אופציה בהתחלה של מאונך ומאוזן"): an outlet only
              document.getElementById('turnRow').style.display = kind === 'outlet' ? '' : 'none';
              // on the ceiling: no height, and the words say where it goes
              document.getElementById('heightRow').style.display = CAT[kind].ceiling ? 'none' : '';
              document.getElementById('counterRow').style.display = (kind === 'outlet' && USE_COUNTER) ? '' : 'none';
              document.getElementById('counter').checked = counter;
              var pic = picOf(curProduct());
              var lying = pic.replace('<img ', '<img class="lying" ').replace('<svg ', '<svg class="lying" ');
              document.getElementById('turnGrid').innerHTML =
                card(turn === 0, pic, 'Vertical', 'pickTurn(0)') + card(turn === 90, lying, 'Horizontal', 'pickTurn(90)');
            }
            function pickTurn(t) { turn = t; render(); }
            // ticked = 42" to the middle; unticked = back to the outlet's 18"
            function pickCounter(on) {
              counter = on;
              document.getElementById('height').value = on ? COUNTER_H : CAT[kind].height;
              render();
            }
            function pickKind(k) {
              if (k !== kind) { document.getElementById('height').value = CAT[k].height; counter = false; }
              kind = k;
              render();
            }
            function pickGangs(n) { gangs = n; render(); }
            function pickProduct(i) { product = CAT[kind].products[i].name; render(); }
            function cur() {
              return { kind: kind, product: product, gangs: CAT[kind].gangs ? gangs : 1,
                       height: parseFloat(document.getElementById('height').value) || 0,
                       turn: kind === 'outlet' ? turn : 0, countertop: kind === 'outlet' && counter };
            }
            function addNew() { sketchup.add_new(JSON.stringify(cur())); }
            function saveSel() { sketchup.save_selected(JSON.stringify(cur())); }
            function okAll() {
              sketchup.ok(JSON.stringify(cur()));
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

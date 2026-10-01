# encoding: utf-8
# Interior Pro - THE PLUMBING WINDOW (2026-09-25, step 1)
#
# Copied from the Shower Floor window (shower_floor_dialog.rb): same
# look, same gallery of pictures as the drains / door handles, same
# fit_height so it opens whole (CLAUDE.md, 2026-09-18).
#
#   Kind     - pictures: Shower head, Toilet, Vanity, Tub
#   Product  - pictures: 'Simple' (built-in boxes) + every .skp in the
#              kind's folder, and "+ Add new..." to bring in any .skp
#   Height   - from the floor to the BOTTOM of the fixture
#
# show(prefill) { |cfg| ... } - the block runs on OK with the numbers.
require 'json'
require 'fileutils'

module InteriorPro
  module FixtureDialog
    def self.defaults
      k = InteriorPro::FixtureLibrary.kinds.keys.first
      { 'kind' => k, 'product' => InteriorPro::FixtureLibrary.products(k).first,
        'height' => InteriorPro::FixtureLibrary.default_height(k), 'gap' => nil, 'len' => nil, 'wid' => nil,
        'deck_front' => nil, 'deck_left' => nil, 'deck_right' => nil }
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
          sp = InteriorPro::FixtureLibrary.set_thumb_path(k, n)
          { 'name' => n, 'img' => tp && File.exist?(tp) ? url_of(tp) + "?#{File.mtime(tp).to_i}" : '',
            'set_img' => sp && File.exist?(sp) ? url_of(sp) + "?#{File.mtime(sp).to_i}" : '',
            'have' => InteriorPro::FixtureLibrary.parts_available(k, n),
            'size' => InteriorPro::FixtureLibrary.resize?(k) ? InteriorPro::FixtureLibrary.size_of(model, k, n) : nil,
            'gap' => InteriorPro::FixtureLibrary.default_gap(k, n),
            'deck' => InteriorPro::FixtureLibrary.deck?(k, n),
            'deck_front' => InteriorPro::FixtureLibrary.deck?(k, n) && InteriorPro::FixtureLibrary.deck_front?(n),
            'parts' => InteriorPro::FixtureLibrary.default_parts(k, n) }
        end
        out[k] = { 'label' => info[:label], 'height' => info[:height], 'set' => info[:set] ? true : false,
                   'gap' => info[:gap], 'resize' => InteriorPro::FixtureLibrary.resize?(k),
                   'dir' => InteriorPro::FixtureLibrary.dir_for(k), 'products' => prods }
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
      @button = button
      dlg = UI::HtmlDialog.new(dialog_title: 'Interior Pro - Plumbing', preferences_key: 'InteriorPro_Fixture',
                               width: 470, height: 300, resizable: true)
      dlg.add_action_callback('ok') do |_, json|
        cfg = JSON.parse(json)
        corner = cfg['corner']
        parts = cfg['parts']
        cfg = defaults.merge(cfg.select { |k, _| defaults.key?(k) })
        cfg['parts'] = parts if parts.is_a?(Hash)
        # 'corner' only in the EDIT window: how far its middle is from
        # the nearer corner. Not remembered for the next placing.
        cfg['corner'] = corner.to_f if !corner.nil? && corner.to_s != ''
        cfg['kind'] = InteriorPro::FixtureLibrary.kind_ok(cfg['kind'])
        cfg['height'] = cfg['height'].to_f
        # the tub's gap from the wall; a kind without one keeps none
        cfg['gap'] = InteriorPro::FixtureLibrary.default_gap(cfg['kind']).nil? ? nil : InteriorPro::FixtureLibrary.wall_gap(cfg['kind'], cfg)
        # the deck round a drop-in tub: front / left / right, inches past it
        deck = InteriorPro::FixtureLibrary.deck?(cfg['kind'], cfg['product'])
        fr_, le_, ri_ = InteriorPro::FixtureLibrary.deck_sides(cfg)
        cfg['deck_front'] = deck ? fr_ : nil
        cfg['deck_left'] = deck ? le_ : nil
        cfg['deck_right'] = deck ? ri_ : nil
        # a tub's typed length / width; empty or 0 = its file's own size
        %w[len wid].each do |k|
          v = InteriorPro::FixtureLibrary.resize?(cfg['kind']) ? cfg[k].to_f : 0.0
          cfg[k] = v > 0.0 ? v : nil
        end
        if cfg['height'] < 0.0
          UI.messagebox('Type the height from the floor, e.g.  80')
          next
        end
        @last = cfg.reject { |k, _| k == 'corner' }
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
        # A SET IS A FOLDER HE FILLS HIMSELF (2026-09-25, his words: "אני
        # אכניס חלק חלק ואכוון אותם"). "+ New set" opens the sets folder;
        # he makes a folder, puts head.skp / valve.skp ... in it, and opens
        # this window again.
        if InteriorPro::FixtureLibrary.set_kind?(kind)
          dir = InteriorPro::FixtureLibrary.dir_for(kind)
          FileUtils.mkdir_p(dir)
          UI.openURL('file:///' + dir.tr('\\', '/'))
          next
        end
        src = UI.openpanel('Choose a SketchUp file', '', 'SketchUp Files|*.skp||')
        name = src ? InteriorPro::FixtureLibrary.add_file!(kind, src) : nil
        UI.messagebox('That file could not be added - see the Ruby Console.') if src && name.nil?
        cur['product'] = name if name
        show(cur, button: @button, &@on_ok)
      end
      # "Save selected" (2026-09-29): the ONE group or component selected in
      # the model is saved into the kind's folder, and the window opens
      # again with it chosen. Select it BEFORE clicking Plumbing.
      dlg.add_action_callback('save_selected') do |_, json|
        cur = JSON.parse(json) rescue {}
        kind = InteriorPro::FixtureLibrary.kind_ok(cur['kind'])
        sel = Sketchup.active_model.selection.to_a
        ent = sel.length == 1 ? sel.first : nil
        unless ent && InteriorPro::FixtureLibrary.saveable?(ent)
          UI.messagebox("Select ONE group or component in the model first (now: #{sel.length} selected).\n" \
                        'Then click Plumbing and Save selected.')
          next
        end
        guess = ent.name.to_s.strip
        guess = ent.definition.name.to_s if guess.empty?
        res = UI.inputbox(['Name'], [guess], "Save #{InteriorPro::FixtureLibrary.kinds[kind][:label]}")
        next unless res
        name = InteriorPro::FixtureLibrary.save_selected!(kind, ent, res[0])
        UI.messagebox('It could not be saved - see the Ruby Console.') if name.nil?
        cur['product'] = name if name
        show(cur, button: @button, &@on_ok)
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
          <div class="row" id="colorRow" style="display:none;">Color<div class="grid" id="colorGrid"></div></div>
          <div class="row" id="heightRow">
            Height from the floor to the bottom of it <input type="number" id="height" step="0.5" min="0"> in
          </div>
          <div class="row" id="sizeRow" style="display:none;">
            Length <input type="number" id="len" step="0.5" min="1"> in
            &nbsp; Width <input type="number" id="wid" step="0.5" min="1"> in
          </div>
          <div class="row" id="deckRow" style="display:none;">
            Deck past the tub: <span id="deckFrontBox">front <input type="number" id="deck_front" step="0.5" min="0"></span>
            left <input type="number" id="deck_left" step="0.5" min="0">
            right <input type="number" id="deck_right" step="0.5" min="0"> in
            <div style="margin-top:3px;">Left / right as you face the wall. The back is From the wall.</div>
          </div>
          <div class="row" id="gapRow" style="display:none;">
            From the wall <input type="number" id="gap" step="0.5" min="0"> in
          </div>
          <div class="row" id="partsRow" style="display:none;">
            <table style="width:100%;border-collapse:collapse;font-size:11px;">
              <tr><td></td><td><b>Part</b></td><td><b>Height</b> (to the pipe)</td><td><b>Sideways</b></td></tr>
              <tbody id="partsBody"></tbody>
            </table>
            <div style="margin-top:4px;">All parts stand on one line. Sideways = inches right (+) or left (-) of it.</div>
          </div>
          <div class="row" id="cornerRow" style="display:none;">
            From the nearer corner to its line <input type="number" id="corner" step="0.5" min="0"> in
          </div>
          <div class="row" id="helpRow">After you click Place: move along a wall - it stays at this height.
            Type a number + Enter = that far from the nearer corner to its line.</div>
          <button onclick="okAll()">#{button}</button>
          <button class="secondary" onclick="sketchup.cancel()">Cancel</button>
          <script>
            var D = #{d.to_json};
            var CAT = #{cat.to_json};
            var kind = CAT[D.kind] ? D.kind : Object.keys(CAT)[0];
            var product = D.product;
            var PARTS = [['head', 'Shower head'], ['valve', 'Handles'], ['hand', 'Hand shower'], ['spout', 'Tub spout']];
            var parts = D.parts || null;
            // which product the Length / Width boxes were filled for
            var sizedFor = '';
            // which product the From the wall box was filled for
            // A DROP-IN'S BACK STRIP IS A CHOICE, NOT A DEFAULT (2026-10-01, his
            // words: "החלק הזה צריך להיות יכול בחירה ולא ברירת מחדל"): its From
            // the wall always opens at its own 0, never at the last number typed.
            // The edit window (D.corner set) still shows the tub's own number.
            var keepGap = D.gap !== null && D.gap !== undefined && D.kind === kind &&
                          (D.corner !== undefined && D.corner !== null || !(curProduct().deck));
            var gapFor = keepGap ? kind + '|' + product : '';
            function kindSvg(k) {
              var s = '';
              if (k === 'shower_set') {
                s = '<rect x="10" y="6" width="76" height="84" fill="#e3e9ec" stroke="#aab"/>' +
                    '<line x1="48" y1="8" x2="48" y2="88" stroke="#c0392b" stroke-dasharray="4 3"/>' +
                    '<ellipse cx="48" cy="22" rx="14" ry="4" fill="#c9d0d3" stroke="#555"/>' +
                    '<rect x="40" y="44" width="16" height="16" rx="2" fill="#b0b7bb" stroke="#444"/>' +
                    '<rect x="64" y="34" width="4" height="30" fill="#c7cdd0" stroke="#555"/>' +
                    '<rect x="42" y="74" width="12" height="5" rx="2" fill="#aab2b6" stroke="#444"/>';
              } else if (k === 'toilet') {
                s = '<rect x="26" y="14" width="44" height="30" rx="3" fill="#f4f4f4" stroke="#777"/>' +
                    '<ellipse cx="48" cy="62" rx="20" ry="24" fill="#fff" stroke="#777"/>' +
                    '<ellipse cx="48" cy="64" rx="12" ry="15" fill="#dfe9ee" stroke="#999"/>';
              } else if (k === 'vanity') {
                s = '<rect x="12" y="34" width="72" height="6" fill="#eee" stroke="#777"/>' +
                    '<ellipse cx="48" cy="37" rx="12" ry="2.5" fill="#dfe9ee" stroke="#999"/>' +
                    '<rect x="14" y="40" width="68" height="44" fill="#d7c4b0" stroke="#777"/>' +
                    '<line x1="48" y1="40" x2="48" y2="84" stroke="#777"/>' +
                    '<rect x="44" y="26" width="3" height="10" fill="#aab2b6" stroke="#555"/>';
              } else if (k === 'tub') {
                s = '<rect x="8" y="40" width="80" height="34" rx="6" fill="#fff" stroke="#777"/>' +
                    '<rect x="14" y="44" width="68" height="10" rx="4" fill="#dfe9ee" stroke="#999"/>' +
                    '<rect x="14" y="74" width="6" height="8" fill="#ccc" stroke="#777"/>' +
                    '<rect x="76" y="74" width="6" height="8" fill="#ccc" stroke="#777"/>';
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
            function curProduct() {
              var list = CAT[kind].products;
              for (var i = 0; i < list.length; i++) if (list[i].name === product) return list[i];
              return list[0];
            }
            // The parts table: one row per part the set has (a missing file
            // = a greyed row that cannot be ticked).
            function renderParts() {
              var isSet = !!CAT[kind].set;
              document.getElementById('partsRow').style.display = isSet ? '' : 'none';
              document.getElementById('heightRow').style.display = isSet ? 'none' : '';
              document.getElementById('sizeRow').style.display = CAT[kind].resize ? '' : 'none';
              if (CAT[kind].resize && sizedFor !== kind + '|' + product) {
                var sz = curProduct().size;
                if (sz) { document.getElementById('len').value = sz[0]; document.getElementById('wid').value = sz[1]; }
                sizedFor = kind + '|' + product;
              }
              document.getElementById('deckRow').style.display = curProduct().deck ? '' : 'none';
              document.getElementById('deckFrontBox').style.display = curProduct().deck_front ? '' : 'none';
              var hasGap = CAT[kind].gap !== null && CAT[kind].gap !== undefined;
              document.getElementById('gapRow').style.display = hasGap ? '' : 'none';
              // each product starts at its own gap (an alcove tub at 0)
              if (hasGap && gapFor !== kind + '|' + product) {
                var pg = curProduct().gap;
                document.getElementById('gap').value = (pg !== null && pg !== undefined) ? pg : CAT[kind].gap;
                gapFor = kind + '|' + product;
              }
              if (!isSet) return;
              var pr = curProduct();
              if (!parts) parts = JSON.parse(JSON.stringify(pr.parts));
              document.getElementById('partsBody').innerHTML = PARTS.map(function(r) {
                var k = r[0], have = pr.have.indexOf(k) >= 0, p = parts[k] || { on: false, h: 0, side: 0 };
                var dis = have ? '' : ' disabled';
                return '<tr style="' + (have ? '' : 'opacity:0.4;') + '">' +
                  '<td><input type="checkbox" id="on_' + k + '"' + (p.on && have ? ' checked' : '') + dis + '></td>' +
                  '<td>' + r[1] + (have ? '' : ' (no file)') + '</td>' +
                  '<td><input type="number" id="h_' + k + '" step="0.5" value="' + p.h + '"' + dis + '> in</td>' +
                  '<td><input type="number" id="s_' + k + '" step="0.5" value="' + p.side + '"' + dis + '> in</td></tr>';
              }).join('');
            }
            function readParts() {
              if (!CAT[kind].set) return null;
              var out = {};
              PARTS.forEach(function(r) {
                var k = r[0], on = document.getElementById('on_' + k);
                out[k] = { on: !!(on && on.checked && !on.disabled),
                           h: parseFloat(document.getElementById('h_' + k).value) || 0,
                           side: parseFloat(document.getElementById('s_' + k).value) || 0 };
              });
              return out;
            }
            // A SET WITH COLOURS (2026-09-28): a product named "Set 1/Black"
            // is set "Set 1" in colour "Black". The sets show once each; the
            // colours of the chosen set show underneath, each with its picture.
            function setOf(n) { var i = n.indexOf('/'); return i < 0 ? n : n.substring(0, i); }
            function colorOf(n) { var i = n.indexOf('/'); return i < 0 ? '' : n.substring(i + 1); }
            function setNames() {
              var out = [];
              CAT[kind].products.forEach(function(p) { if (out.indexOf(setOf(p.name)) < 0) out.push(setOf(p.name)); });
              return out;
            }
            function picOf(p) { return p.img ? '<img src="' + p.img + '">' : kindSvg(kind); }
            function renderProducts() {
              var list = CAT[kind].products;
              if (!list.some(function(p) { return p.name === product; })) product = list[0].name;
              var html = setNames().map(function(s, i) {
                var shown = setOf(product) === s ? curProduct() : list.filter(function(p) { return setOf(p.name) === s; })[0];
                var pic = shown.set_img ? '<img src="' + shown.set_img + '">' : picOf(shown);
                return card(setOf(product) === s, pic, s, 'pickSet(' + i + ')');
              }).join('');
              html += '<div class="design-card add" onclick="addNew()"><div class="plus">+</div><div class="dn">' +
                      (CAT[kind].set ? 'New set (opens the folder)' : 'Add new...') + '</div></div>';
              if (!CAT[kind].set) html += '<div class="design-card add" onclick="saveSel()"><div class="plus">&#8595;</div>' +
                      '<div class="dn">Save selected</div></div>';
              document.getElementById('prodGrid').innerHTML = html;
              var cols = [];
              list.forEach(function(p, i) { if (setOf(p.name) === setOf(product) && colorOf(p.name) !== '') cols.push([p, i]); });
              document.getElementById('colorRow').style.display = cols.length ? '' : 'none';
              document.getElementById('colorGrid').innerHTML = cols.map(function(c) {
                return card(c[0].name === product, picOf(c[0]), colorOf(c[0].name), 'pickProduct(' + c[1] + ')');
              }).join('');
              renderParts();
            }
            // Another set: the same colour if it has one, else its first.
            // A new set starts from its own defaults.
            function pickSet(i) {
              var s = setNames()[i], list = CAT[kind].products;
              var same = list.filter(function(p) { return p.name === s + '/' + colorOf(product); })[0];
              var n = (same || list.filter(function(p) { return setOf(p.name) === s; })[0]).name;
              if (n !== product) parts = null;
              product = n;
              renderProducts();
            }
            function pickKind(k) {
              if (k !== kind) document.getElementById('height').value = CAT[k].height;
              if (k !== kind && CAT[k].gap !== null && CAT[k].gap !== undefined) document.getElementById('gap').value = CAT[k].gap;
              if (k !== kind) parts = null;
              kind = k;
              renderKinds();
              renderProducts();
            }
            // A new set starts from its own defaults (his call: "ברירת מחדל").
            // Another colour of the SAME set keeps the heights he typed.
            function pickProduct(i) {
              var n = CAT[kind].products[i].name;
              if (setOf(n) !== setOf(product)) parts = null;
              product = n;
              renderProducts();
            }
            function cur() {
              var o = { kind: kind, product: product, height: parseFloat(document.getElementById('height').value) || 0 };
              if (curProduct().deck) {
                ['deck_front', 'deck_left', 'deck_right'].forEach(function(k) {
                  var v = parseFloat(document.getElementById(k).value);
                  o[k] = isNaN(v) ? null : v;
                });
              }
              if (CAT[kind].resize) {
                var sz = curProduct().size || [0, 0];
                var lv = parseFloat(document.getElementById('len').value), wv = parseFloat(document.getElementById('wid').value);
                // the file's own size typed back = not stretched
                o.len = (isNaN(lv) || Math.abs(lv - sz[0]) < 0.005) ? null : lv;
                o.wid = (isNaN(wv) || Math.abs(wv - sz[1]) < 0.005) ? null : wv;
              }
              if (CAT[kind].gap !== null && CAT[kind].gap !== undefined) {
                var g = parseFloat(document.getElementById('gap').value);
                o.gap = isNaN(g) ? CAT[kind].gap : g;
              }
              var ps = readParts();
              if (ps) o.parts = ps;
              if (D.corner !== undefined && D.corner !== null) o.corner = parseFloat(document.getElementById('corner').value) || 0;
              return o;
            }
            function addNew() { sketchup.add_new(JSON.stringify(cur())); }
            function saveSel() { sketchup.save_selected(JSON.stringify(cur())); }
            function okAll() {
              var o = cur();
              if (o.parts && !Object.keys(o.parts).some(function(k) { return o.parts[k].on; })) {
                alert('Tick at least one part.');
                return;
              }
              sketchup.ok(JSON.stringify(o));
            }
            document.getElementById('height').value = D.height;
            document.getElementById('gap').value = (D.gap !== null && D.gap !== undefined && D.kind === kind) ? D.gap :
              (CAT[kind].gap !== null && CAT[kind].gap !== undefined ? CAT[kind].gap : 0);
            // THE EDIT WINDOW (2026-09-25): same window, plus how far from
            // the corner, and no placing help.
            if (D.corner !== undefined && D.corner !== null) {
              document.getElementById('corner').value = D.corner;
              document.getElementById('cornerRow').style.display = '';
              document.getElementById('helpRow').style.display = 'none';
            }
            // the size he typed last time / on this tub, if it is the same product
            if (CAT[kind].resize && D.product === product && (D.len || D.wid)) {
              var s0 = curProduct().size || [0, 0];
              document.getElementById('len').value = D.len || s0[0];
              document.getElementById('wid').value = D.wid || s0[1];
              sizedFor = kind + '|' + product;
            }
            // the deck: his last numbers, else front 3 / left 0 / right 0
            document.getElementById('deck_front').value = (D.deck_front !== null && D.deck_front !== undefined) ? D.deck_front : 3;
            document.getElementById('deck_left').value = (D.deck_left !== null && D.deck_left !== undefined) ? D.deck_left : 0;
            document.getElementById('deck_right').value = (D.deck_right !== null && D.deck_right !== undefined) ? D.deck_right : 0;
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

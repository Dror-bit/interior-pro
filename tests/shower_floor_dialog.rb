# encoding: utf-8
# Interior Pro - THE SHOWER FLOOR WINDOW (2026-09-22, his words: "פשוט
# תשתמש בקודים הקיימים ותעתיק אותם לאחד חדש").
#
# One window, copied field for field from the Floors window (floor_dialog.rb)
# - Pattern, W, L, X, Y, Ang, Grout, grout colour, Stagger, Center, Floor
# (texture), חומר (material card), Spec, Grout spec - plus the three
# shower fields (flat / raised, raised by, curb height) and one checkbox:
# "Same as the room floor", which lays the ROOM's own tile in the shower
# and greys the rest out. The numbers are stored on the shower pad under
# the SAME attribute names a floor uses, so FloorPattern lays them with
# the same code and the takeoff reads them the same way.
#
# show(prefill) { |cfg| ... } - the block runs on OK with the numbers.
require 'json'

module InteriorPro
  module ShowerFloorDialog
    KEYS = %w[kind rise curb_h same_room pattern unit_w unit_l ox oy angle center
              texture grout grout_color stagger material_card_id spec grout_spec].freeze unless const_defined?(:KEYS, false)
    # The keys added on 2026-09-22 (the curb options and the drain).
    # The list lives in the method, not in a guarded constant: a guarded
    # constant keeps its first value through reload!, so a new key added
    # there would be dropped until SketchUp restarts.
    def self.all_keys
      KEYS + %w[curb_room wall_joints drain drain_w drain_l drain_side drain_shift]
    end

    def self.defaults
      { 'kind' => 'flat', 'rise' => InteriorPro::ShowerFloor::DEFAULT_RISE,
        'curb_h' => InteriorPro::ShowerFloor::DEFAULT_CURB_H, 'curb_room' => false, 'wall_joints' => false, 'same_room' => true,
        'drain' => 'none', 'drain_w' => InteriorPro::ShowerFloor::DEFAULT_DRAIN_W,
        'drain_l' => InteriorPro::ShowerFloor::DEFAULT_DRAIN_W,
        'drain_side' => 'right', 'drain_shift' => 0,
        'pattern' => 'Tile', 'unit_w' => 0, 'unit_l' => 0, 'ox' => 0, 'oy' => 0, 'angle' => 0,
        'center' => true, 'texture' => '', 'grout' => 0.125, 'grout_color' => 'light',
        'stagger' => 0, 'material_card_id' => '', 'spec' => '', 'grout_spec' => '' }
    end

    # What he chose last time, so the second shower is one window away.
    def self.last
      @last ||= defaults
    end

    # The numbers a shower pad carries, in the window's shape.
    def self.from_pad(pad)
      at = lambda { |k| pad.get_attribute('InteriorPro', k) }
      d = defaults
      d['kind'] = at.call('kind').to_s == 'curb' ? 'curb' : 'flat'
      d['rise'] = at.call('rise_in').to_f > 0 ? at.call('rise_in').to_f : d['rise']
      d['curb_h'] = at.call('curb_h_in').to_f > 0 ? at.call('curb_h_in').to_f : d['curb_h']
      d['curb_room'] = at.call('curb_room') ? true : false
      d['wall_joints'] = at.call('wall_joints') ? true : false
      d['drain'] = (at.call('drain') || 'none').to_s
      d['drain_w'] = at.call('drain_w').to_f > 0 ? at.call('drain_w').to_f : d['drain_w']
      d['drain_l'] = at.call('drain_l').to_f > 0 ? at.call('drain_l').to_f : d['drain_l']
      d['drain_side'] = (at.call('drain_side') || 'right').to_s
      d['drain_shift'] = at.call('drain_shift').to_f
      d['same_room'] = at.call('tile').to_s.empty? || at.call('tile').to_s == InteriorPro::ShowerFloor::SAME_AS_ROOM
      d['pattern'] = (at.call('pattern') || d['pattern']).to_s
      d['unit_w'] = at.call('unit_w').to_f
      d['unit_l'] = at.call('unit_l').to_f
      d['ox'] = at.call('pattern_ox').to_f
      d['oy'] = at.call('pattern_oy').to_f
      d['angle'] = at.call('pattern_angle').to_f
      d['center'] = at.call('pattern_center').nil? ? true : (at.call('pattern_center') ? true : false)
      d['texture'] = (at.call('floor_texture') || '').to_s
      d['grout'] = at.call('pattern_grout').nil? ? d['grout'] : at.call('pattern_grout').to_f
      d['grout_color'] = (at.call('pattern_grout_color') || 'light').to_s
      d['stagger'] = at.call('pattern_stagger').to_f
      d['material_card_id'] = (at.call('material_card_id') || '').to_s
      d['spec'] = (at.call('floor_spec') || '').to_s
      d['grout_spec'] = (at.call('grout_spec') || '').to_s
      # "Same as the room floor": show the ROOM's numbers, so unticking the
      # box lets him play with exactly what the room has (2026-09-22).
      if d['same_room']
        begin
          loop_xy = Array(at.call('poly_xy')).map(&:to_f).each_slice(2).to_a
          unders = InteriorPro::ShowerFloor.floors_under(loop_xy, at.call('floor_z').to_f)
          slab = InteriorPro::ShowerFloor.slab_of(unders)
          pat = unders.find { |g| g.get_attribute('InteriorPro', 'type').to_s == 'floor_pattern' }
          got = InteriorPro::ShowerFloor.room_settings(slab || unders.first, pat)
          got.each { |k, v| d[k] = v if KEYS.include?(k) }
        rescue StandardError => e
          puts "[ShowerFloor] room numbers for the window: #{e.message}"
        end
      end
      d
    end

    def self.show(prefill = nil, title: 'Shower Floor', button: 'Draw', &on_ok)
      data = defaults.merge(last).merge(prefill || {})
      textures = {}
      InteriorPro::FloorManager::SOLID_COLORS.each_key { |c| textures[c] = '' }
      InteriorPro::FloorManager.texture_files.each do |f|
        base = File.basename(f, '.*')
        thumb = File.join(File.dirname(f), 'thumbs', File.basename(f))
        src = File.exist?(thumb) ? thumb : f
        textures[base] = 'file:///' + src.tr('\\', '/').gsub(' ', '%20')
      end
      cards = []
      if defined?(InteriorPro::MaterialLibrary) && InteriorPro::MaterialLibrary.folder?
        cards = (InteriorPro::MaterialLibrary.cards.map { |c| { 'id' => c['id'].to_s, 'name' => c['name'].to_s } } rescue [])
      end
      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      dlg = UI::HtmlDialog.new(dialog_title: "Interior Pro - #{title}", preferences_key: 'InteriorPro_ShowerFloor',
                               width: 470, height: 300, resizable: true)
      dlg.add_action_callback('ok') do |_, json|
        cfg = JSON.parse(json)
        cfg = defaults.merge(cfg.select { |k, _| all_keys.include?(k) })
        cfg['rise'] = cfg['rise'].to_f
        cfg['curb_h'] = cfg['curb_h'].to_f
        if cfg['rise'] <= 0.0 || cfg['curb_h'] <= 0.0
          UI.messagebox('Type the two heights, e.g.  1  and  4')
          next
        end
        @last = cfg.dup
        begin; dlg.close; rescue StandardError; end
        @dialog = nil
        on_ok.call(cfg) if on_ok
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
          puts "[ShowerFloor] fit_height: #{e.message}"
        end
      end
      dlg.set_html(build_html(data, textures, cards, button))
      dlg.show
      @dialog = dlg
    end

    def self.build_html(d, textures, cards, button)
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
          body { font-family: Arial, sans-serif; font-size: 13px; margin: 12px; background: #fff; }
          .section-title { font-weight: bold; margin: 0 0 8px; color: #5d4037; }
          .row { padding: 4px 0; border-top: 1px solid #eee; font-size: 11px; color: #555; }
          .row.first { border-top: none; }
          .row input[type=number] { width: 44px; padding: 2px; }
          .row select { width: 84px; padding: 2px; }
          .row label { white-space: nowrap; }
          .off { opacity: 0.45; }
          /* the drain pictures - copied from the door window's handle gallery */
          .design-card { border: 2px solid #ddd; border-radius: 4px; padding: 3px 2px 2px; cursor: pointer; text-align: center; background: #fafafa; }
          .design-card:hover { border-color: #a1887f; }
          .design-card.selected { border-color: #5d4037; background: #f0e8e4; }
          .design-card svg { width: 100%; height: auto; display: block; }
          .design-card .dn { font-size: 9px; color: #555; margin-top: 2px; line-height: 1.1; min-height: 20px; }
          .handle-head { display: inline-flex; align-items: center; gap: 8px; border: 1px solid #ccc; border-radius: 4px; padding: 2px 6px; cursor: pointer; background: #fafafa; vertical-align: middle; }
          .handle-head:hover { border-color: #a1887f; }
          .handle-head svg { width: 26px; height: 26px; display: block; }
          .handle-grid { display: none; grid-template-columns: repeat(6, 1fr); gap: 6px; margin-top: 6px; }
          .handle-grid.open { display: grid; }
          button { width: 100%; padding: 10px; margin-top: 10px; border: none; border-radius: 6px;
                   background: #5d4037; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
        </style></head><body>
          <div class="section-title">Shower Floor</div>
          <div class="row first">
            Shower floor <select id="kind" style="width:150px;" onchange="kindChanged()">
              <option value="flat">Flat - same height as the room</option>
              <option value="curb">Raised, with a curb</option>
            </select>
            Raised by <input type="number" id="rise" step="0.25" min="0"> in
            Curb height <input type="number" id="curb_h" step="0.25" min="0"> in
          </div>
          <div class="row" id="curbRow">
            <label><input type="checkbox" id="curb_room"> Curb same as the bathroom floor</label><br>
            <label><input type="checkbox" id="wall_joints"> Shower floor grout lines follow the walls, not the bathroom floor</label>
          </div>
          <div class="row">
            Drain <span class="handle-head" onclick="toggleDrainGallery()"><span id="drainPic"></span><span id="drainName"></span><span id="drainArrow">&#9656;</span></span>
            <select id="drain" style="display:none;" onchange="drainChanged()">
              <option value="none">None</option>
              <option value="square">Square, with a grate - middle</option>
              <option value="square_tile">Square, tile inside - middle</option>
              <option value="round">Round, with a grate - middle (W = across)</option>
              <option value="linear">Long, with a grate - by a wall</option>
              <option value="linear_tile">Long, tile inside - by a wall</option>
            </select>
            W <input type="number" id="drain_w" step="0.25" min="0">
            L <input type="number" id="drain_l" step="0.25" min="0"> in
            <div class="handle-grid" id="drainGrid"></div>
          </div>
          <div class="row" id="wallDrainRow">
            Wall <select id="drain_side" style="width:84px;">
              <option value="top">Top</option>
              <option value="bottom">Bottom</option>
              <option value="left">Left</option>
              <option value="right">Right</option>
            </select>
            Shift <input type="number" id="drain_shift" step="0.5"> in
            (W = across, L = along the wall)
          </div>
          <div class="row">
            <label><input type="checkbox" id="same_room" onchange="sameChanged()"> Same as the room floor - the room's tile runs on into the shower</label>
          </div>
          <div id="tile">
          <div class="row">
            Floor <select id="tx" onchange="textureChanged()" style="width:120px;"></select>
            <img id="tximg" style="height:26px;width:26px;object-fit:cover;vertical-align:middle;border:1px solid #ccc;border-radius:3px;display:none;">
            חומר <select id="mc" style="width:120px;"></select>
          </div>
          <div class="row">
            Pattern <select id="pat"></select>
            W <input type="number" id="pw" step="0.5" min="0">
            L <input type="number" id="pl" step="0.5" min="0">
            X <input type="number" id="px" step="0.5">
            Y <input type="number" id="py" step="0.5">
            Ang <input type="number" id="pa" step="5">
            Grout <select id="pg" title="Grout width, Tile pattern only"></select>
            <select id="pgc" title="Grout color"></select>
            Stagger <select id="st" title="Running bond: how far every second row is pushed along, as a fraction of one tile"></select>
            <label><input type="checkbox" id="pc"> Center</label>
          </div>
          <div class="row">
            Spec <input type="text" id="sp" style="width:150px;" placeholder="e.g. Daltile 24x24 Matte">
            Grout spec <input type="text" id="gs" style="width:150px;" placeholder="e.g. Mapei #38">
          </div>
          </div>
          <button onclick="okAll()" id="okBtn">#{button}</button>
          <button class="secondary" onclick="sketchup.cancel()">Cancel</button>
          <script>
            var D = #{d.to_json};
            var TEXTURES = #{textures.to_json};
            var CARDS = #{cards.to_json};
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
            function staggerOptions(sel) {
              var opts = [[0, 'Stack'], [0.5, '1/2'], [0.3333, '1/3'], [0.25, '1/4']];
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
            function cardOptions(sel) {
              var opts = ['<option value=""' + (sel ? '' : ' selected') + '>ללא</option>'];
              CARDS.forEach(function(c) {
                opts.push('<option value="' + c.id + '"' + (c.id === sel ? ' selected' : '') + '>' + c.name + '</option>');
              });
              return opts.join('');
            }
            function textureChanged() {
              var b = document.getElementById('tx').value;
              var img = document.getElementById('tximg');
              if (b && TEXTURES[b]) { img.src = TEXTURES[b]; img.style.display = 'inline-block'; }
              else { img.style.display = 'none'; }
            }
            // The curb's own options show only when there IS a curb
            // (2026-09-22, his words: "אופציה שנפתחת שאני מסמן ללכת עם סכר").
            function kindChanged() {
              document.getElementById('curbRow').style.display =
                document.getElementById('kind').value === 'curb' ? '' : 'none';
            }
            // The long drain's own row shows only for a long drain
            // (2026-09-23). Switching between a long and a middle drain
            // puts in that kind's own size: 3 x 24 or 5 x 5.
            // THE DRAINS AS PICTURES (2026-09-23, his ask: "כמו בדלתות").
            // The hidden select keeps the value; the cards only set it.
            var DRAIN_NAMES = { none: 'None', square: 'Square grate', square_tile: 'Square tile',
                                round: 'Round grate', linear: 'Long grate', linear_tile: 'Long tile' };
            function drainSvg(n) {
              var st = '#b8bbbe', dk = '#4a4d50', ch = '#8a8d90', tl = '#e8e2d6';
              var s = '';
              var holes = function(x0, y0, x1, y1, h, b) {
                var o = '';
                for (var x = x0; x + h <= x1 + 0.01; x += h + b)
                  for (var y = y0; y + h <= y1 + 0.01; y += h + b)
                    o += '<rect x="' + x + '" y="' + y + '" width="' + h + '" height="' + h + '" fill="' + dk + '"/>';
                return o;
              };
              switch (n) {
                case 'square':
                  s = '<rect x="18" y="18" width="60" height="60" fill="' + st + '" stroke="#777"/>' + holes(25, 25, 71, 71, 6, 4);
                  break;
                case 'square_tile':
                  s = '<rect x="18" y="18" width="60" height="60" fill="' + st + '" stroke="#777"/>' +
                      '<rect x="22" y="22" width="52" height="52" fill="' + ch + '"/>' +
                      '<rect x="26" y="26" width="44" height="44" fill="' + st + '"/>' +
                      '<rect x="28" y="28" width="40" height="40" fill="' + tl + '"/>';
                  break;
                case 'round':
                  s = '<circle cx="48" cy="48" r="30" fill="' + st + '" stroke="#777"/>';
                  for (var x = 30; x <= 60; x += 10) for (var y = 30; y <= 60; y += 10)
                    if (Math.pow(x + 3 - 48, 2) + Math.pow(y + 3 - 48, 2) < 22 * 22)
                      s += '<rect x="' + x + '" y="' + y + '" width="6" height="6" fill="' + dk + '"/>';
                  break;
                case 'linear':
                  s = '<rect x="6" y="38" width="84" height="20" fill="' + st + '" stroke="#777"/>' + holes(10, 42, 86, 54, 4, 2);
                  break;
                case 'linear_tile':
                  s = '<rect x="6" y="38" width="84" height="20" fill="' + st + '" stroke="#777"/>' +
                      '<rect x="9" y="41" width="78" height="14" fill="' + ch + '"/>' +
                      '<rect x="12" y="44" width="72" height="8" fill="' + st + '"/>' +
                      '<rect x="13" y="45" width="70" height="6" fill="' + tl + '"/>';
                  break;
                default:
                  s = '<circle cx="48" cy="48" r="20" fill="none" stroke="#bbb" stroke-width="2"/><line x1="34" y1="62" x2="62" y2="34" stroke="#bbb" stroke-width="2"/>';
              }
              return '<svg viewBox="0 0 96 96">' + s + '</svg>';
            }
            function renderDrainGallery() {
              var cur = document.getElementById('drain').value || 'none';
              document.getElementById('drainGrid').innerHTML = Object.keys(DRAIN_NAMES).map(function(n) {
                return '<div class="design-card' + (n === cur ? ' selected' : '') + '" data-drain="' + n +
                       '" onclick="selectDrainCard(this)">' + drainSvg(n) + '<div class="dn">' + DRAIN_NAMES[n] + '</div></div>';
              }).join('');
            }
            function syncDrainLabel() {
              var v = document.getElementById('drain').value || 'none';
              document.getElementById('drainPic').innerHTML = drainSvg(v);
              document.getElementById('drainName').textContent = DRAIN_NAMES[v] || v;
            }
            function toggleDrainGallery(force) {
              var g = document.getElementById('drainGrid');
              var open = (typeof force === 'boolean') ? force : g.className.indexOf('open') === -1;
              g.className = open ? 'handle-grid open' : 'handle-grid';
              document.getElementById('drainArrow').innerHTML = open ? '&#9662;' : '&#9656;';
              if (open) renderDrainGallery();
            }
            function selectDrainCard(el) {
              document.getElementById('drain').value = el.getAttribute('data-drain');
              drainChanged();
              toggleDrainGallery(false);
            }
            var lastDrain = null;
            function isWallDrain(v) { return v === 'linear' || v === 'linear_tile'; }
            function drainChanged() {
              var v = document.getElementById('drain').value;
              if (lastDrain !== null && isWallDrain(v) !== isWallDrain(lastDrain)) {
                document.getElementById('drain_w').value = isWallDrain(v) ? #{InteriorPro::ShowerFloor::LINEAR_W} : #{InteriorPro::ShowerFloor::DEFAULT_DRAIN_W};
                document.getElementById('drain_l').value = isWallDrain(v) ? #{InteriorPro::ShowerFloor::LINEAR_L} : #{InteriorPro::ShowerFloor::DEFAULT_DRAIN_W};
              }
              lastDrain = v;
              document.getElementById('wallDrainRow').style.display = isWallDrain(v) ? '' : 'none';
              syncDrainLabel();
            }
            function sameChanged() {
              var same = document.getElementById('same_room').checked;
              var box = document.getElementById('tile');
              box.className = same ? 'off' : '';
              box.querySelectorAll('input,select').forEach(function(el) { el.disabled = same; });
            }
            function fill() {
              var g = function(id) { return document.getElementById(id); };
              g('kind').value = D.kind;
              g('rise').value = D.rise;
              g('curb_h').value = D.curb_h;
              g('curb_room').checked = !!D.curb_room;
              g('wall_joints').checked = !!D.wall_joints;
              g('drain').value = D.drain || 'none';
              g('drain_w').value = D.drain_w;
              g('drain_l').value = D.drain_l;
              g('drain_side').value = D.drain_side || 'right';
              g('drain_shift').value = D.drain_shift || 0;
              g('same_room').checked = !!D.same_room;
              g('tx').innerHTML = textureOptions(D.texture);
              g('mc').innerHTML = cardOptions(D.material_card_id);
              g('pat').innerHTML = patternOptions(D.pattern);
              g('pw').value = D.unit_w || '';
              g('pl').value = D.unit_l || '';
              g('px').value = D.ox || 0;
              g('py').value = D.oy || 0;
              g('pa').value = D.angle || 0;
              g('pg').innerHTML = groutOptions(D.grout);
              g('pgc').innerHTML = groutColorOptions(D.grout_color);
              g('st').innerHTML = staggerOptions(D.stagger);
              g('pc').checked = !!D.center;
              g('sp').value = D.spec || '';
              g('gs').value = D.grout_spec || '';
              textureChanged();
              sameChanged();
              kindChanged();
              drainChanged();
            }
            function okAll() {
              var g = function(id) { return document.getElementById(id); };
              var cfg = {
                kind: g('kind').value,
                rise: parseFloat(g('rise').value) || 0,
                curb_h: parseFloat(g('curb_h').value) || 0,
                curb_room: g('curb_room').checked,
                wall_joints: g('wall_joints').checked,
                drain: g('drain').value,
                drain_w: parseFloat(g('drain_w').value) || 0,
                drain_l: parseFloat(g('drain_l').value) || 0,
                drain_side: g('drain_side').value,
                drain_shift: parseFloat(g('drain_shift').value) || 0,
                same_room: g('same_room').checked,
                pattern: g('pat').value,
                unit_w: parseFloat(g('pw').value) || 0,
                unit_l: parseFloat(g('pl').value) || 0,
                ox: parseFloat(g('px').value) || 0,
                oy: parseFloat(g('py').value) || 0,
                angle: parseFloat(g('pa').value) || 0,
                center: g('pc').checked,
                texture: g('tx').value,
                grout: parseFloat(g('pg').value) || 0,
                grout_color: g('pgc').value,
                stagger: parseFloat(g('st').value) || 0,
                material_card_id: g('mc').value,
                spec: g('sp').value,
                grout_spec: g('gs').value
              };
              sketchup.ok(JSON.stringify(cfg));
            }
            fill();
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

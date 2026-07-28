# Interior Pro - 2D Top-Down Editor
# MVP step 1 (2026-07-27): walls - click-click chain, typed lengths, ortho snap.
# Step 2 (2026-07-28): Door + Window tools - click a wall on the canvas,
# placement runs through the SAME pipelines as the 3D tools
# (DoorTool#cut_door_opening / WindowTool#cut_window_opening).
#
# Walls are ALWAYS applied as anchor 'bottom-left' (the proven wall path for
# door placement). Side R is realized by reversing the drawn direction
# (DoorManager.wall_geometry mis-centers exterior doors on bottom-right
# walls - known bug, root fix deferred).

require 'json'

module InteriorPro
  module PlanEditor
    class << self
      def show
        if @dialog
          begin; @dialog.close; rescue StandardError; end
          @dialog = nil
        end
        dlg = UI::HtmlDialog.new(
          dialog_title: 'Interior Pro - 2D Editor',
          preferences_key: 'InteriorPro_PlanEditor',
          width: 1040, height: 700, resizable: true
        )

        dlg.add_action_callback('editor_ready') { |_| push_walls(dlg) }
        dlg.add_action_callback('sync_model')   { |_| push_walls(dlg) }

        dlg.add_action_callback('apply_walls') do |_, json|
          n = apply_walls(JSON.parse(json))
          dlg.execute_script("applyDone(#{n})")
          push_walls(dlg)
        end

        dlg.add_action_callback('place_door') do |_, json|
          place_door(JSON.parse(json))
          push_walls(dlg)
        end

        dlg.add_action_callback('place_window') do |_, json|
          place_window(JSON.parse(json))
          push_walls(dlg)
        end

        dlg.add_action_callback('build_plan') do |_|
          ok = InteriorPro::PlanGenerator.build!
          dlg.execute_script("planDone(#{ok ? 'true' : 'false'})")
        end

        dlg.set_html(build_html)
        dlg.show
        @dialog = dlg
      end

      # ---- model -> editor -------------------------------------------------

      # kind per hosted body for the canvas symbols: door/double/sliding/
      # folding/pocket/garage/window (+ swing/clicked for the arc side).
      def bodies_by_wall(model)
        out = Hash.new { |h, k| h[k] = [] }
        model.entities.to_a.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next unless e.valid?
          tp = e.get_attribute('InteriorPro', 'type')
          next unless tp == 'door' || tp == 'window'
          host = e.get_attribute('InteriorPro', 'host_wall_id')
          t = e.get_attribute('InteriorPro', 'position_along_wall_in')
          next if host.nil? || t.nil?
          kind = 'window'
          swing = 'left'
          if tp == 'door'
            dt = (e.get_attribute('InteriorPro', 'door_type') || 'Single').to_s
            fc = (e.get_attribute('InteriorPro', 'front_config') || 'single').to_s
            swing = (e.get_attribute('InteriorPro', 'swing_direction') || 'left').to_s
            kind = if dt == 'Garage Door' then 'garage'
                   elsif dt.include?('Folding') then 'folding'
                   elsif dt.include?('Sliding') || dt == 'Closet' then 'sliding'
                   elsif dt == 'Pocket' then 'pocket'
                   elsif dt == 'Double' || dt == 'French Hinged' || dt == '4-Panel Center Hinged' ||
                         ((dt == 'Front Door' || dt == 'Arched') && fc == 'double') then 'double'
                   else 'door'
                   end
          end
          out[host] << {
            't' => t.to_f.round(3),
            'w' => e.get_attribute('InteriorPro', 'width_in').to_f,
            'kind' => kind,
            'swing' => swing,
            'clicked' => (e.get_attribute('InteriorPro', 'clicked_side') || 1).to_i
          }
        end
        out
      end

      def walls_payload
        model = Sketchup.active_model
        walls = model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        end
        syms = bodies_by_wall(model)
        walls.map do |w|
          sx = w.get_attribute('InteriorPro', 'start_x')
          next nil if sx.nil?
          xf = w.transformation
          s = Geom::Point3d.new(sx.to_f, w.get_attribute('InteriorPro', 'start_y').to_f, 0).transform(xf)
          e = Geom::Point3d.new(w.get_attribute('InteriorPro', 'end_x').to_f,
                                w.get_attribute('InteriorPro', 'end_y').to_f, 0).transform(xf)
          anchor = (w.get_attribute('InteriorPro', 'anchor') || 'bottom-left').to_s
          h_anchor = anchor == 'center' ? 'center' : (anchor.split('-')[1] || 'left')
          ops = InteriorPro::WallTool.read_door_openings(w).map { |o| [o[:t].round(3), o[:width].round(3)] }
          {
            'id' => w.get_attribute('InteriorPro', 'id').to_s,
            'sx' => s.x.to_f.round(3), 'sy' => s.y.to_f.round(3),
            'ex' => e.x.to_f.round(3), 'ey' => e.y.to_f.round(3),
            'th' => w.get_attribute('InteriorPro', 'thickness').to_f,
            'ha' => h_anchor,
            'cat' => (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s,
            'ops' => ops,
            'syms' => syms[w.get_attribute('InteriorPro', 'id')] || []
          }
        end.compact
      end

      def push_walls(dlg)
        dlg.execute_script("loadWalls(#{JSON.generate(walls_payload)})")
      rescue StandardError => e
        puts "[PlanEditor] push_walls: #{e.message}"
      end

      def find_wall(id)
        Sketchup.active_model.entities.grep(Sketchup::Group).find do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
            g.get_attribute('InteriorPro', 'id') == id
        end
      end

      # ---- editor -> model: walls -----------------------------------------

      def apply_walls(rows)
        model = Sketchup.active_model
        created = []
        model.start_operation('2D Editor Walls', true)
        rows.each do |r|
          s = Geom::Point3d.new(r['sx'].to_f, r['sy'].to_f, 0)
          e = Geom::Point3d.new(r['ex'].to_f, r['ey'].to_f, 0)
          next if s.distance(e) < 1.0
          cat = r['cat'] == 'interior' ? 'interior' : 'exterior'
          attrs = {
            thickness: r['th'].to_f > 0.5 ? r['th'].to_f : 4.5,
            height: r['h'].to_f > 1.0 ? r['h'].to_f : 96.0,
            anchor: 'bottom-left',
            wall_type: '2D Editor',
            exterior_material: cat == 'exterior' ? 'Stucco' : '#ffffff',
            interior_material: '#ffffff',
            side_a_color: '#ffffff',
            side_b_color: '#ffffff',
            wall_category: cat
          }
          wt = InteriorPro::WallTool.new
          wt.wall_category = cat
          wt.side_a_color = '#ffffff'
          wt.side_b_color = '#ffffff'
          g = wt.build_wall_group(s, e, attrs, model)
          created << g if g
        end
        created.each do |g|
          begin
            InteriorPro::WallTool.join_corners(g, model)
          rescue StandardError => e
            puts "[PlanEditor] join_corners: #{e.message}"
          end
        end
        model.commit_operation
        begin
          InteriorPro::RoomManager.sync_rooms! if created.any? && defined?(InteriorPro::RoomManager)
        rescue StandardError => e
          puts "[PlanEditor] rooms sync: #{e.message}"
        end
        puts "[PlanEditor] applied #{created.length} wall(s)"
        created.length
      rescue StandardError => e
        begin; model.abort_operation; rescue StandardError; end
        puts "[PlanEditor] apply_walls: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        0
      end

      # ---- editor -> model: doors / windows -------------------------------

      def place_door(r)
        wall = find_wall(r['wall_id'].to_s)
        unless wall
          puts '[PlanEditor] place_door: wall not found'
          return false
        end
        cat = r['category'] == 'exterior' ? 'exterior' : 'interior'
        tool = InteriorPro::DoorTool.new
        tool.apply_category_defaults(cat)
        tool.door_type = r['door_type'].to_s unless r['door_type'].to_s.empty?
        InteriorPro::DoorLibrary.type_setting_overrides(cat, tool.door_type).each do |k, v|
          setter = "#{k}="
          tool.send(setter, v) if tool.respond_to?(setter)
        end
        tool.width  = r['width'].to_f  if r['width'].to_f  > 6.0
        tool.height = r['height'].to_f if r['height'].to_f > 12.0
        tool.swing_direction = r['swing'] == 'right' ? 'right' : 'left'
        pt = Geom::Point3d.new(r['px'].to_f, r['py'].to_f, 0)
        tool.send(:cut_door_opening, wall, pt)
        puts "[PlanEditor] door #{tool.door_type} #{tool.width}x#{tool.height} placed"
        true
      rescue StandardError => e
        puts "[PlanEditor] place_door: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        false
      end

      def place_window(r)
        wall = find_wall(r['wall_id'].to_s)
        unless wall
          puts '[PlanEditor] place_window: wall not found'
          return false
        end
        tool = InteriorPro::WindowTool.new
        tool.window_type = r['window_type'].to_s unless r['window_type'].to_s.empty?
        tool.width  = r['width'].to_f  if r['width'].to_f  > 6.0
        tool.height = r['height'].to_f if r['height'].to_f > 6.0
        tool.header_height = r['header'].to_f if r['header'].to_f > 12.0
        pt = Geom::Point3d.new(r['px'].to_f, r['py'].to_f, 0)
        tool.send(:cut_window_opening, wall, pt)
        puts "[PlanEditor] window #{tool.window_type} #{tool.width}x#{tool.height} placed"
        true
      rescue StandardError => e
        puts "[PlanEditor] place_window: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        false
      end

      # ---- HTML ------------------------------------------------------------

      def build_html
        <<~HTML
          <!DOCTYPE html>
          <html><head><meta charset="utf-8"><style>
            html, body { margin:0; height:100%; overflow:hidden; font-family:Arial,sans-serif; font-size:13px; }
            #top { height:36px; background:#2f3542; color:#fff; display:flex; align-items:center; padding:0 10px; gap:8px; }
            #top .title { font-weight:bold; margin-right:auto; }
            button { border:0; border-radius:4px; padding:5px 10px; cursor:pointer; font-size:12px; }
            .blue { background:#4b89ff; color:#fff; } .gray { background:#57606f; color:#fff; }
            #main { display:flex; height:calc(100% - 66px); }
            #canvasWrap { flex:1; position:relative; background:#fbfcfe; }
            canvas { display:block; }
            #side { width:200px; background:#f4f6f9; border-left:1px solid #d6dae0; padding:10px; overflow-y:auto; }
            #side label { display:block; margin:8px 0 3px; color:#333; }
            #side input[type=text] { width:70px; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            #side select { width:100%; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            .seg { display:flex; gap:4px; }
            .seg button { background:#fff; border:1px solid #c3c9d1; color:#333; }
            .seg button.on { background:#dce9ff; border-color:#4b89ff; }
            #bottom { height:30px; background:#eceff3; border-top:1px solid #d6dae0; display:flex; align-items:center; padding:0 10px; gap:10px; }
            #vcb { background:#fffbe6; border:1px solid #e0b400; border-radius:3px; padding:3px 8px; min-width:70px; font-weight:bold; }
            #hint { color:#777; }
            #status { margin-top:14px; color:#555; font-size:12px; }
            .okmsg { color:#1a9d55; }
            .modebtn { flex:1; }
          </style></head><body>
          <div id="top">
            <span class="title">Interior Pro - 2D Editor</span>
            <button class="blue" onclick="applyPending()">Apply to Model</button>
            <button class="gray" onclick="sketchup.build_plan()">Plans (2D)</button>
            <button class="gray" onclick="sketchup.sync_model()">Sync</button>
          </div>
          <div id="main">
            <div id="canvasWrap"><canvas id="cv"></canvas></div>
            <div id="side">
              <div class="seg">
                <button id="modeWall" class="on modebtn" onclick="setMode('wall')">Wall</button>
                <button id="modeDoor" class="modebtn" onclick="setMode('door')">Door</button>
                <button id="modeWin" class="modebtn" onclick="setMode('win')">Window</button>
              </div>

              <div id="secWall">
                <label>Thickness (in)</label><input type="text" id="th" value="5">
                <label>Height (in)</label><input type="text" id="hh" value="96">
                <label>Category</label>
                <div class="seg"><button id="catE" class="on" onclick="setCat('exterior')">Ext</button><button id="catI" onclick="setCat('interior')">Int</button></div>
                <label>Draw side</label>
                <div class="seg"><button id="sideL" class="on" onclick="setSide('L')">L</button><button id="sideR" onclick="setSide('R')">R</button></div>
                <div style="margin-top:14px"><button class="gray" style="width:100%" onclick="undoPending()">Undo last wall</button></div>
              </div>

              <div id="secDoor" style="display:none">
                <label>Category</label>
                <div class="seg"><button id="dCatI" class="on" onclick="setDoorCat('interior')">Int</button><button id="dCatE" onclick="setDoorCat('exterior')">Ext</button></div>
                <label>Type</label><select id="dType" onchange="doorTypeChanged()"></select>
                <label>Width (in)</label><input type="text" id="dW" value="32">
                <label>Height (in)</label><input type="text" id="dH" value="80">
                <label>Hinge side</label>
                <div class="seg"><button id="dSwL" class="on" onclick="setSwing('left')">L</button><button id="dSwR" onclick="setSwing('right')">R</button></div>
                <div style="margin-top:10px; color:#777; font-size:11px">לחץ על קיר במודל (רק קירות שכבר עברו Apply)</div>
              </div>

              <div id="secWin" style="display:none">
                <label>Type</label><select id="wType" onchange="winTypeChanged()"></select>
                <label>Width (in)</label><input type="text" id="wW" value="24">
                <label>Height (in)</label><input type="text" id="wH" value="48">
                <label>Header (in)</label><input type="text" id="wHead" value="80">
                <div style="margin-top:10px; color:#777; font-size:11px">לחץ על קיר במודל (רק קירות שכבר עברו Apply)</div>
              </div>

              <div id="status"></div>
            </div>
          </div>
          <div id="bottom">
            <span>Length:</span><span id="vcb">&nbsp;</span>
            <span id="hint">Click to start a wall - move - type length + Enter, or click. Right-click / Esc ends the chain. Wheel = zoom, middle-drag = pan.</span>
          </div>
          <script>
            var cv = document.getElementById('cv'), ctx = cv.getContext('2d');
            var walls = [];          // existing model walls (read-only)
            var pending = [];        // walls drawn here, not yet applied
            var mode = 'wall';
            var cat = 'exterior', sideOpt = 'L';
            var doorCat = 'interior', doorSwing = 'left';
            var scale = 1.6, panX = 60, panY = 60;   // model inches -> px
            var drawing = false, startPt = null, cursor = {x:0, y:0};
            var typed = '';
            var panning = false, panFrom = null;
            var fitted = false;
            var hoverHit = null;

            var DOOR_TYPES = {
              interior: ['Single', 'Double', 'Pocket', 'Folding', 'Closet'],
              exterior: ['Front Door', 'French Hinged', 'Sliding', 'Garage Door', 'Arched']
            };
            var DOOR_WH = { 'Single':[32,80], 'Double':[60,80], 'Pocket':[32,80], 'Folding':[48,80],
                            'Closet':[72,80], 'Front Door':[36,80], 'French Hinged':[60,80],
                            'Sliding':[60,80], 'Garage Door':[192,84], 'Arched':[36,96] };
            var WIN_TYPES = ['Casement', 'Casement XX', 'Single Hung', 'XOX Single Hung',
                             'Slider XO', 'Slider XOX', 'Garden Window', 'Arched'];
            var WIN_WH = { 'Casement':[24,48], 'Casement XX':[48,48], 'Single Hung':[24,36],
                           'XOX Single Hung':[96,48], 'Slider XO':[48,36], 'Slider XOX':[72,48],
                           'Garden Window':[60,48], 'Arched':[36,60] };

            function fillSelect(id, list) {
              var el = document.getElementById(id);
              el.innerHTML = '';
              list.forEach(function(t){ var o = document.createElement('option'); o.value = t; o.textContent = t; el.appendChild(o); });
            }
            function doorTypeChanged() {
              var t = document.getElementById('dType').value;
              var wh = DOOR_WH[t] || [32, 80];
              document.getElementById('dW').value = wh[0];
              document.getElementById('dH').value = wh[1];
            }
            function winTypeChanged() {
              var t = document.getElementById('wType').value;
              var wh = WIN_WH[t] || [24, 48];
              document.getElementById('wW').value = wh[0];
              document.getElementById('wH').value = wh[1];
            }
            function setDoorCat(c) {
              doorCat = c;
              document.getElementById('dCatI').className = c === 'interior' ? 'on' : '';
              document.getElementById('dCatE').className = c === 'exterior' ? 'on' : '';
              fillSelect('dType', DOOR_TYPES[c]);
              doorTypeChanged();
            }
            function setSwing(s) {
              doorSwing = s;
              document.getElementById('dSwL').className = s === 'left' ? 'on' : '';
              document.getElementById('dSwR').className = s === 'right' ? 'on' : '';
            }
            function setMode(m) {
              mode = m; endChain(); hoverHit = null;
              document.getElementById('modeWall').className = (m === 'wall' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeDoor').className = (m === 'door' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeWin').className = (m === 'win' ? 'on ' : '') + 'modebtn';
              document.getElementById('secWall').style.display = m === 'wall' ? '' : 'none';
              document.getElementById('secDoor').style.display = m === 'door' ? '' : 'none';
              document.getElementById('secWin').style.display = m === 'win' ? '' : 'none';
              var hint = m === 'wall'
                ? 'Click to start a wall - move - type length + Enter, or click. Right-click / Esc ends the chain.'
                : 'Click on an applied wall to place. Green = fits, red = does not fit.';
              document.getElementById('hint').textContent = hint;
              draw();
            }

            function resize() {
              var w = document.getElementById('canvasWrap');
              cv.width = w.clientWidth; cv.height = w.clientHeight; draw();
            }
            window.onresize = resize;

            function sx(x) { return x * scale + panX; }
            function sy(y) { return cv.height - (y * scale + panY); }
            function mx(px) { return (px - panX) / scale; }
            function my(py) { return (cv.height - py - panY) / scale; }

            function fmtLen(v) {
              var neg = v < 0; v = Math.abs(v);
              var ft = Math.floor(v / 12), inch = v - ft * 12;
              var r = Math.round(inch * 2) / 2;
              if (r >= 12) { ft += 1; r = 0; }
              var s = (ft > 0 ? ft + "' " : '') + (r % 1 === 0 ? r : r.toFixed(1)) + '"';
              return (neg ? '-' : '') + s;
            }

            function parseLen(s) {
              s = String(s).trim(); if (!s) return null;
              var m = s.match(/^(\\d+(?:\\.\\d+)?)'\\s*(\\d+(?:\\.\\d+)?)?\\"?$/);
              if (m) return parseFloat(m[1]) * 12 + (m[2] ? parseFloat(m[2]) : 0);
              m = s.match(/^(\\d+(?:\\.\\d+)?)\\"?$/);
              if (m) return parseFloat(m[1]);
              return null;
            }

            function bandQuad(w) {
              var dx = w.ex - w.sx, dy = w.ey - w.sy;
              var len = Math.sqrt(dx*dx + dy*dy); if (len < 0.01) return null;
              var ux = dx/len, uy = dy/len, nx = -uy, ny = ux;
              var p, q;
              if (w.ha === 'left') { p = w.th; q = 0; }
              else if (w.ha === 'right') { p = 0; q = -w.th; }
              else { p = w.th/2; q = -w.th/2; }
              return { ux:ux, uy:uy, nx:nx, ny:ny, len:len, p:p, q:q };
            }

            function drawWallBand(w, fillEx, fillIn, alpha) {
              var b = bandQuad(w); if (!b) return;
              var cuts = (w.ops || []).map(function(o){ return [o[0]-o[1]/2, o[0]+o[1]/2]; })
                                       .sort(function(a,c){ return a[0]-c[0]; });
              var segs = []; var pos = 0;
              cuts.forEach(function(c){
                if (c[0] - pos > 0.5) segs.push([pos, c[0]]);
                if (c[1] > pos) pos = c[1];
              });
              if (b.len - pos > 0.5) segs.push([pos, b.len]);
              if (!segs.length) segs = [[0, b.len]];
              ctx.globalAlpha = alpha;
              ctx.fillStyle = (w.cat === 'interior') ? fillIn : fillEx;
              ctx.strokeStyle = '#000'; ctx.lineWidth = 0.8;
              segs.forEach(function(sg){
                var a = sg[0], c = sg[1];
                var x1 = w.sx + b.ux*a, y1 = w.sy + b.uy*a;
                var x2 = w.sx + b.ux*c, y2 = w.sy + b.uy*c;
                ctx.beginPath();
                ctx.moveTo(sx(x1 + b.nx*b.p), sy(y1 + b.ny*b.p));
                ctx.lineTo(sx(x2 + b.nx*b.p), sy(y2 + b.ny*b.p));
                ctx.lineTo(sx(x2 + b.nx*b.q), sy(y2 + b.ny*b.q));
                ctx.lineTo(sx(x1 + b.nx*b.q), sy(y1 + b.ny*b.q));
                ctx.closePath(); ctx.fill(); ctx.stroke();
              });
              ctx.globalAlpha = 1;
            }

            // ---- door/window plan symbols on the canvas ----
            function wpt(w, b, t, off) {
              return { x: w.sx + b.ux*t + b.nx*off, y: w.sy + b.uy*t + b.ny*off };
            }
            function polyline(pts) {
              ctx.beginPath();
              pts.forEach(function(p, i){ i ? ctx.lineTo(sx(p.x), sy(p.y)) : ctx.moveTo(sx(p.x), sy(p.y)); });
              ctx.stroke();
            }
            function symRect(w, b, xa, xb, oa, ob) {
              polyline([wpt(w,b,xa,oa), wpt(w,b,xb,oa), wpt(w,b,xb,ob), wpt(w,b,xa,ob), wpt(w,b,xa,oa)]);
            }
            function symArcDoor(w, b, x1, x2, swing, clicked) {
              var ww = x2 - x1;
              var ss = clicked >= 0 ? -1 : 1;              // leaf toward the clicked face
              var edge = ss > 0 ? b.p : b.q;
              var hx = swing === 'right' ? x2 : x1;
              var lx = hx === x1 ? x2 : x1;
              var h = wpt(w, b, hx, edge), l = wpt(w, b, lx, edge);
              var leafEnd = { x: h.x + b.nx*ss*ww, y: h.y + b.ny*ss*ww };
              polyline([h, leafEnd]);
              var v0 = { x: l.x - h.x, y: l.y - h.y };
              var crossZ = v0.x*(leafEnd.y - h.y) - v0.y*(leafEnd.x - h.x);
              var sweep = (crossZ >= 0 ? 1 : -1) * Math.PI/2;
              var pts = [];
              for (var i = 0; i <= 12; i++) {
                var a = sweep * i / 12, ca = Math.cos(a), sa = Math.sin(a);
                pts.push({ x: h.x + v0.x*ca - v0.y*sa, y: h.y + v0.x*sa + v0.y*ca });
              }
              polyline(pts);
            }
            function symDashed(w, b, x1, x2, off) {
              var pos = x1;
              while (pos < x2) {
                var e2 = Math.min(pos + 5, x2);
                polyline([wpt(w,b,pos,off), wpt(w,b,e2,off)]);
                pos += 8;
              }
            }
            function drawSyms(w) {
              var b = bandQuad(w); if (!b || !w.syms) return;
              ctx.strokeStyle = '#000'; ctx.lineWidth = 1;
              var cmid = (b.p + b.q) / 2;
              w.syms.forEach(function(s){
                var x1 = Math.max(0, s.t - s.w/2), x2 = Math.min(b.len, s.t + s.w/2);
                if (x2 - x1 < 1) return;
                if (s.kind === 'window') {
                  symRect(w, b, x1, x2, b.q, b.p);
                  polyline([wpt(w,b,x1+0.5,cmid), wpt(w,b,x2-0.5,cmid)]);
                } else if (s.kind === 'door') {
                  symArcDoor(w, b, x1, x2, s.swing, s.clicked);
                } else if (s.kind === 'double') {
                  var xm = (x1 + x2) / 2;
                  symArcDoor(w, b, x1, xm, 'left', s.clicked);
                  symArcDoor(w, b, xm, x2, 'right', s.clicked);
                } else if (s.kind === 'sliding') {
                  var xm2 = (x1 + x2) / 2;
                  symRect(w, b, x1+0.5, xm2+1.5, cmid+0.3, cmid+1.5);
                  symRect(w, b, xm2-1.5, x2-0.5, cmid-1.5, cmid-0.3);
                } else if (s.kind === 'garage') {
                  ctx.lineWidth = 2.5;
                  polyline([wpt(w,b,x1,b.q+0.7), wpt(w,b,x2,b.q+0.7)]);
                  ctx.lineWidth = 1;
                  symDashed(w, b, x1, x2, b.p + 3);
                } else if (s.kind === 'folding') {
                  var ss2 = s.clicked >= 0 ? -1 : 1;
                  var edge2 = ss2 > 0 ? b.p : b.q;
                  var amp = (x2 - x1) / 4;
                  var pts2 = [];
                  for (var i = 0; i <= 4; i++) {
                    var xx = x1 + (x2 - x1) * i / 4;
                    var oo = (i % 2 === 1) ? edge2 + ss2*amp : edge2;
                    pts2.push(wpt(w, b, xx, oo));
                  }
                  polyline(pts2);
                } else if (s.kind === 'pocket') {
                  var xm3 = (x1 + x2) / 2;
                  symRect(w, b, x1, xm3, cmid-0.6, cmid+0.6);
                  symDashed(w, b, xm3, x2, cmid);
                }
              });
            }

            function dimLabel(w, color) {
              var b = bandQuad(w); if (!b) return;
              var cxp = sx((w.sx + w.ex)/2 + b.nx * (b.p + 6));
              var cyp = sy((w.sy + w.ey)/2 + b.ny * (b.p + 6));
              ctx.fillStyle = color; ctx.font = '11px Arial';
              ctx.textAlign = 'center';
              ctx.fillText(fmtLen(b.len), cxp, cyp);
            }

            function drawGrid() {
              var stepPx = 12 * scale;
              while (stepPx < 14) stepPx *= 4;
              while (stepPx > 80) stepPx /= 2;
              ctx.strokeStyle = '#eef1f5'; ctx.lineWidth = 1;
              var x0 = ((panX % stepPx) + stepPx) % stepPx;
              for (var x = x0; x < cv.width; x += stepPx) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,cv.height); ctx.stroke(); }
              var y0 = ((((cv.height - panY) % stepPx) + stepPx) % stepPx);
              for (var y = y0; y < cv.height; y += stepPx) { if (y < 0) continue; ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(cv.width,y); ctx.stroke(); }
            }

            function draw() {
              ctx.clearRect(0, 0, cv.width, cv.height);
              drawGrid();
              walls.forEach(function(w){ drawWallBand(w, '#444', '#cfcfcf', 1); drawSyms(w); dimLabel(w, '#1a6ee0'); });
              pending.forEach(function(w){ drawWallBand(w, '#2f6bd8', '#9db8e8', 0.85); dimLabel(w, '#e0392b'); });
              if (mode === 'wall' && drawing && startPt) {
                var end = currentEnd();
                var w = tempWall(startPt, end);
                drawWallBand(w, '#2f6bd8', '#9db8e8', 0.5);
                ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 1;
                ctx.setLineDash([5,4]);
                ctx.beginPath(); ctx.moveTo(sx(startPt.x), sy(startPt.y)); ctx.lineTo(sx(end.x), sy(end.y)); ctx.stroke();
                ctx.setLineDash([]);
                var dd = Math.hypot(end.x - startPt.x, end.y - startPt.y);
                ctx.fillStyle = '#1a6ee0'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText(fmtLen(dd), sx(end.x) + 12, sy(end.y) - 8);
              }
              if (mode !== 'wall' && hoverHit) drawGhostOpening();
              updateStatus();
            }

            function openW() {
              return (mode === 'door' ? parseLen(document.getElementById('dW').value)
                                      : parseLen(document.getElementById('wW').value)) || 24;
            }

            function drawGhostOpening() {
              var h = hoverHit, b = h.b;
              var hw = openW() / 2;
              var ok = (h.t - hw >= 0) && (h.t + hw <= b.len);
              var x1 = h.t - hw, x2 = h.t + hw;
              ctx.strokeStyle = ok ? '#1a9d55' : '#e0392b';
              ctx.lineWidth = 2;
              ctx.beginPath();
              ctx.moveTo(sx(h.w.sx + b.ux*x1 + b.nx*b.p), sy(h.w.sy + b.uy*x1 + b.ny*b.p));
              ctx.lineTo(sx(h.w.sx + b.ux*x2 + b.nx*b.p), sy(h.w.sy + b.uy*x2 + b.ny*b.p));
              ctx.lineTo(sx(h.w.sx + b.ux*x2 + b.nx*b.q), sy(h.w.sy + b.uy*x2 + b.ny*b.q));
              ctx.lineTo(sx(h.w.sx + b.ux*x1 + b.nx*b.q), sy(h.w.sy + b.uy*x1 + b.ny*b.q));
              ctx.closePath(); ctx.stroke();
              hoverHit.ok = ok;
            }

            function hitWall(p) {
              var best = null;
              var tol = 8 / scale;
              walls.forEach(function(w){
                if (!w.id) return;
                var b = bandQuad(w); if (!b) return;
                var dx = p.x - w.sx, dy = p.y - w.sy;
                var tt = dx*b.ux + dy*b.uy;
                var off = dx*b.nx + dy*b.ny;
                if (tt < -2 || tt > b.len + 2) return;
                if (off < b.q - tol || off > b.p + tol) return;
                var mid = (b.p + b.q) / 2;
                var score = Math.abs(off - mid);
                if (!best || score < best.score) {
                  best = { w:w, b:b, t:Math.max(0, Math.min(b.len, tt)), off:off, score:score };
                }
              });
              return best;
            }

            function tempWall(s, e) {
              return { sx:s.x, sy:s.y, ex:e.x, ey:e.y,
                       th: parseLen(document.getElementById('th').value) || 5,
                       ha: mHa(), cat: cat, ops: [] };
            }
            function mHa() { return sideOpt === 'L' ? 'left' : 'right'; }   // preview only

            function snapPoint(p, from) {
              var best = null, bestD = 10 / scale;
              var cand = [];
              walls.concat(pending).forEach(function(w){
                cand.push({x:w.sx, y:w.sy}); cand.push({x:w.ex, y:w.ey});
              });
              cand.forEach(function(c){
                var d = Math.hypot(c.x - p.x, c.y - p.y);
                if (d < bestD) { best = c; bestD = d; }
              });
              if (best) return { x:best.x, y:best.y, snapped:true };
              var out = { x:p.x, y:p.y, snapped:false };
              if (from) {
                var dx = p.x - from.x, dy = p.y - from.y;
                var ang = Math.atan2(dy, dx), d = Math.hypot(dx, dy);
                var step = Math.PI / 4;
                var snapAng = Math.round(ang / step) * step;
                if (Math.abs(ang - snapAng) < 0.12) {
                  out.x = from.x + Math.cos(snapAng) * d;
                  out.y = from.y + Math.sin(snapAng) * d;
                }
              }
              out.x = Math.round(out.x * 2) / 2; out.y = Math.round(out.y * 2) / 2;
              return out;
            }

            function currentEnd() {
              var p = snapPoint(cursor, startPt);
              var typedLen = parseLen(typed);
              if (typedLen && startPt) {
                var dx = p.x - startPt.x, dy = p.y - startPt.y;
                var d = Math.hypot(dx, dy);
                if (d > 0.01) return { x: startPt.x + dx/d*typedLen, y: startPt.y + dy/d*typedLen };
              }
              return p;
            }

            function commitSegment() {
              var end = currentEnd();
              if (!startPt || Math.hypot(end.x - startPt.x, end.y - startPt.y) < 1) return;
              var w = tempWall(startPt, end);
              w.h = parseLen(document.getElementById('hh').value) || 96;
              w.anchor = 'bottom-left';
              if (sideOpt === 'R') {   // flip direction so the band side matches, keep bottom-left
                var t2 = { x: w.sx, y: w.sy };
                w.sx = w.ex; w.sy = w.ey; w.ex = t2.x; w.ey = t2.y;
                w.ha = 'left';
              }
              pending.push(w);
              startPt = end; typed = ''; updateVcb(); draw();
            }

            function endChain() { drawing = false; startPt = null; typed = ''; updateVcb(); draw(); }
            function updateVcb() { document.getElementById('vcb').innerHTML = typed ? typed : '&nbsp;'; }

            function updateStatus() {
              document.getElementById('status').innerHTML =
                'Model walls: ' + walls.length + '<br>Pending here: <b>' + pending.length + '</b>' +
                (pending.length ? '<br><span style="color:#e0392b">Not applied yet</span>' : '<br><span class="okmsg">All applied</span>');
            }

            // ---- events ----
            cv.addEventListener('mousedown', function(ev) {
              if (ev.button === 1) { panning = true; panFrom = {x:ev.offsetX, y:ev.offsetY}; ev.preventDefault(); return; }
              if (ev.button === 2) { endChain(); return; }
              if (ev.button !== 0) return;
              var p = {x:mx(ev.offsetX), y:my(ev.offsetY)};
              if (mode === 'door' || mode === 'win') {
                hoverHit = hitWall(p);
                draw();
                if (!hoverHit) return;
                if (!hoverHit.ok) return;
                if (mode === 'door') {
                  sketchup.place_door(JSON.stringify({
                    wall_id: hoverHit.w.id, px: p.x, py: p.y,
                    category: doorCat,
                    door_type: document.getElementById('dType').value,
                    width: parseLen(document.getElementById('dW').value) || 32,
                    height: parseLen(document.getElementById('dH').value) || 80,
                    swing: doorSwing
                  }));
                } else {
                  sketchup.place_window(JSON.stringify({
                    wall_id: hoverHit.w.id, px: p.x, py: p.y,
                    window_type: document.getElementById('wType').value,
                    width: parseLen(document.getElementById('wW').value) || 24,
                    height: parseLen(document.getElementById('wH').value) || 48,
                    header: parseLen(document.getElementById('wHead').value) || 80
                  }));
                }
                return;
              }
              var ps = snapPoint(p, drawing ? startPt : null);
              if (!drawing) { drawing = true; startPt = ps; }
              else commitSegment();
            });
            cv.addEventListener('mousemove', function(ev) {
              if (panning) {
                panX += ev.offsetX - panFrom.x; panY -= ev.offsetY - panFrom.y;
                panFrom = {x:ev.offsetX, y:ev.offsetY}; draw(); return;
              }
              cursor = {x:mx(ev.offsetX), y:my(ev.offsetY)};
              if (mode === 'door' || mode === 'win') { hoverHit = hitWall(cursor); draw(); return; }
              if (drawing) draw();
            });
            window.addEventListener('mouseup', function() { panning = false; });
            cv.addEventListener('contextmenu', function(ev) { ev.preventDefault(); });
            cv.addEventListener('wheel', function(ev) {
              ev.preventDefault();
              var f = ev.deltaY < 0 ? 1.15 : 1/1.15;
              var mxp = mx(ev.offsetX), myp = my(ev.offsetY);
              scale = Math.max(0.15, Math.min(12, scale * f));
              panX = ev.offsetX - mxp * scale;
              panY = (cv.height - ev.offsetY) - myp * scale;
              draw();
            }, { passive:false });

            window.addEventListener('keydown', function(ev) {
              if (ev.target.tagName === 'INPUT' || ev.target.tagName === 'SELECT') return;
              if (ev.key === 'Escape') { endChain(); return; }
              if (mode !== 'wall') return;
              if (ev.key === 'Enter') { if (drawing && typed) commitSegment(); return; }
              if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); if (drawing) draw(); ev.preventDefault(); return; }
              if (/^[0-9.'" ]$/.test(ev.key)) { typed += ev.key; updateVcb(); if (drawing) draw(); }
            });

            // ---- side panel (wall) ----
            function setCat(c) {
              cat = c;
              document.getElementById('catE').className = c === 'exterior' ? 'on' : '';
              document.getElementById('catI').className = c === 'interior' ? 'on' : '';
              document.getElementById('th').value = c === 'interior' ? '4.5' : '5';
            }
            function setSide(s) {
              sideOpt = s;
              document.getElementById('sideL').className = s === 'L' ? 'on' : '';
              document.getElementById('sideR').className = s === 'R' ? 'on' : '';
            }
            function undoPending() { pending.pop(); draw(); }

            // ---- Ruby bridge ----
            function applyPending() {
              if (!pending.length) return;
              sketchup.apply_walls(JSON.stringify(pending));
            }
            function applyDone(n) { pending = []; draw(); }
            function planDone(ok) {}
            function loadWalls(list) {
              walls = list || [];
              hoverHit = null;
              if (!fitted && walls.length) { fitView(); fitted = true; }
              draw();
            }
            function fitView() {
              var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
              walls.forEach(function(w){
                minX = Math.min(minX, w.sx, w.ex); maxX = Math.max(maxX, w.sx, w.ex);
                minY = Math.min(minY, w.sy, w.ey); maxY = Math.max(maxY, w.sy, w.ey);
              });
              if (minX > maxX) return;
              var pad = 60;
              scale = Math.min((cv.width - pad*2) / Math.max(maxX - minX, 60),
                               (cv.height - pad*2) / Math.max(maxY - minY, 60));
              scale = Math.max(0.15, Math.min(6, scale));
              panX = pad - minX * scale;
              panY = pad - minY * scale;
            }

            fillSelect('dType', DOOR_TYPES[doorCat]);
            fillSelect('wType', WIN_TYPES);
            doorTypeChanged();
            winTypeChanged();
            resize();
            sketchup.editor_ready();
          </script>
          </body></html>
        HTML
      end
    end
  end
end

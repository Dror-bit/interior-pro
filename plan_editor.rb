# Interior Pro - 2D Top-Down Editor (MVP step 1: walls, 2026-07-27)
#
# Draw walls on a 2D canvas (click-click chain, typed lengths, ortho snap)
# and apply them to the model through the EXISTING wall pipeline
# (WallTool#build_wall_group + join_corners + rooms sync).
# 2D contract: the editor writes attributes only - geometry comes from the
# same builders every other tool uses.

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

        dlg.add_action_callback('editor_ready') do |_|
          push_walls(dlg)
        end

        dlg.add_action_callback('sync_model') do |_|
          push_walls(dlg)
        end

        dlg.add_action_callback('apply_walls') do |_, json|
          n = apply_walls(JSON.parse(json))
          dlg.execute_script("applyDone(#{n})")
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

      def walls_payload
        model = Sketchup.active_model
        walls = model.entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        end
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
            'sx' => s.x.to_f.round(3), 'sy' => s.y.to_f.round(3),
            'ex' => e.x.to_f.round(3), 'ey' => e.y.to_f.round(3),
            'th' => w.get_attribute('InteriorPro', 'thickness').to_f,
            'ha' => h_anchor,
            'cat' => (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s,
            'ops' => ops
          }
        end.compact
      end

      def push_walls(dlg)
        dlg.execute_script("loadWalls(#{JSON.generate(walls_payload)})")
      rescue StandardError => e
        puts "[PlanEditor] push_walls: #{e.message}"
      end

      # ---- editor -> model -------------------------------------------------

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
            # Always bottom-left: the proven anchor for door placement
            # (DoorManager.wall_geometry mis-centers doors on bottom-right).
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
            #side { width:190px; background:#f4f6f9; border-left:1px solid #d6dae0; padding:10px; overflow-y:auto; }
            #side label { display:block; margin:8px 0 3px; color:#333; }
            #side input[type=text] { width:70px; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            .seg { display:flex; gap:4px; }
            .seg button { background:#fff; border:1px solid #c3c9d1; color:#333; }
            .seg button.on { background:#dce9ff; border-color:#4b89ff; }
            #bottom { height:30px; background:#eceff3; border-top:1px solid #d6dae0; display:flex; align-items:center; padding:0 10px; gap:10px; }
            #vcb { background:#fffbe6; border:1px solid #e0b400; border-radius:3px; padding:3px 8px; min-width:70px; font-weight:bold; }
            #hint { color:#777; }
            #status { margin-top:14px; color:#555; font-size:12px; }
            .okmsg { color:#1a9d55; }
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
              <b>Wall</b>
              <label>Thickness (in)</label><input type="text" id="th" value="5">
              <label>Height (in)</label><input type="text" id="hh" value="96">
              <label>Category</label>
              <div class="seg"><button id="catE" class="on" onclick="setCat('exterior')">Ext</button><button id="catI" onclick="setCat('interior')">Int</button></div>
              <label>Draw side</label>
              <div class="seg"><button id="sideL" class="on" onclick="setSide('L')">L</button><button id="sideR" onclick="setSide('R')">R</button></div>
              <div style="margin-top:14px"><button class="gray" style="width:100%" onclick="undoPending()">Undo last wall</button></div>
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
            var cat = 'exterior', sideOpt = 'L';
            var scale = 1.6, panX = 60, panY = 60;   // model inches -> px
            var drawing = false, startPt = null, cursor = {x:0, y:0};
            var typed = '';
            var panning = false, panFrom = null;
            var fitted = false;

            // Walls are ALWAYS applied as anchor 'bottom-left' (the proven wall
            // path for door placement). Side R is realized by reversing the
            // drawn direction instead of using anchor 'bottom-right'
            // (DoorManager.wall_geometry mis-centers exterior doors on
            // bottom-right walls - known bug, root fix deferred).
            function mHa() { return sideOpt === 'L' ? 'left' : 'right'; }   // preview only

            function resize() {
              var w = document.getElementById('canvasWrap');
              cv.width = w.clientWidth; cv.height = w.clientHeight; draw();
            }
            window.onresize = resize;

            // model (in) -> screen px. Model y up, screen y down.
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
              s = s.trim(); if (!s) return null;
              var m = s.match(/^(\\d+(?:\\.\\d+)?)'\\s*(\\d+(?:\\.\\d+)?)?\\"?$/);
              if (m) return parseFloat(m[1]) * 12 + (m[2] ? parseFloat(m[2]) : 0);
              m = s.match(/^(\\d+(?:\\.\\d+)?)\\"?$/);
              if (m) return parseFloat(m[1]);
              return null;
            }

            // Band quad for a wall row (same offsets as WallTool corners).
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
              if (w.len === undefined) w.len = b.len;
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

            function dimLabel(w, color) {
              var b = bandQuad(w); if (!b) return;
              var cxp = sx((w.sx + w.ex)/2 + b.nx * (b.p + 6));
              var cyp = sy((w.sy + w.ey)/2 + b.ny * (b.p + 6));
              ctx.fillStyle = color; ctx.font = '11px Arial';
              ctx.textAlign = 'center';
              ctx.fillText(fmtLen(b.len), cxp, cyp);
            }

            function drawGrid() {
              var stepPx = 12 * scale;           // 1 ft
              while (stepPx < 14) stepPx *= 4;
              while (stepPx > 80) stepPx /= 2;
              ctx.strokeStyle = '#eef1f5'; ctx.lineWidth = 1;
              var x0 = ((panX % stepPx) + stepPx) % stepPx;
              for (var x = x0; x < cv.width; x += stepPx) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,cv.height); ctx.stroke(); }
              var y0 = ((((cv.height - panY) % stepPx) + stepPx) % stepPx);
              for (var y = y0; y > 0 || y < cv.height; y += stepPx) { if (y > cv.height) break; ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(cv.width,y); ctx.stroke(); }
            }

            function draw() {
              ctx.clearRect(0, 0, cv.width, cv.height);
              drawGrid();
              walls.forEach(function(w){ drawWallBand(w, '#444', '#cfcfcf', 1); dimLabel(w, '#1a6ee0'); });
              pending.forEach(function(w){ drawWallBand(w, '#2f6bd8', '#9db8e8', 0.85); dimLabel(w, '#e0392b'); });
              if (drawing && startPt) {
                var end = currentEnd();
                var w = tempWall(startPt, end);
                drawWallBand(w, '#2f6bd8', '#9db8e8', 0.5);
                ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 1;
                ctx.setLineDash([5,4]);
                ctx.beginPath(); ctx.moveTo(sx(startPt.x), sy(startPt.y)); ctx.lineTo(sx(end.x), sy(end.y)); ctx.stroke();
                ctx.setLineDash([]);
                var d = Math.hypot(end.x - startPt.x, end.y - startPt.y);
                ctx.fillStyle = '#1a6ee0'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText(fmtLen(d), sx(end.x) + 12, sy(end.y) - 8);
              }
              updateStatus();
            }

            function tempWall(s, e) {
              return { sx:s.x, sy:s.y, ex:e.x, ey:e.y,
                       th: parseLen(document.getElementById('th').value) || 5,
                       ha: mHa(), cat: cat, ops: [] };
            }

            function snapPoint(p, from) {
              var best = null, bestD = 10 / scale;   // 10 px in model units
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
              var p = snapPoint({x:mx(ev.offsetX), y:my(ev.offsetY)}, drawing ? startPt : null);
              if (!drawing) { drawing = true; startPt = p; }
              else commitSegment();
            });
            cv.addEventListener('mousemove', function(ev) {
              if (panning) {
                panX += ev.offsetX - panFrom.x; panY -= ev.offsetY - panFrom.y;
                panFrom = {x:ev.offsetX, y:ev.offsetY}; draw(); return;
              }
              cursor = {x:mx(ev.offsetX), y:my(ev.offsetY)};
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
              if (ev.target.tagName === 'INPUT') return;
              if (ev.key === 'Escape') { endChain(); return; }
              if (ev.key === 'Enter') { if (drawing && typed) commitSegment(); return; }
              if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); if (drawing) draw(); ev.preventDefault(); return; }
              if (/^[0-9.'" ]$/.test(ev.key)) { typed += ev.key; updateVcb(); if (drawing) draw(); }
            });

            // ---- side panel ----
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

            resize();
            sketchup.editor_ready();
          </script>
          </body></html>
        HTML
      end
    end
  end
end

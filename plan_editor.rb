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

        dlg.add_action_callback('editor_ready') do |_|
          push_catalogs(dlg)
          push_walls(dlg)
        end
        dlg.add_action_callback('sync_model') { |_| push_walls(dlg) }

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

        dlg.add_action_callback('delete_wall') do |_, json|
          r = JSON.parse(json)
          wall = find_wall(r['wall_id'].to_s)
          if wall
            begin
              InteriorPro::WallDeleteTool.delete_wall!(wall)
              puts '[PlanEditor] wall deleted'
            rescue StandardError => e
              puts "[PlanEditor] delete_wall: #{e.message}"
            end
          end
          push_walls(dlg)
        end

        dlg.add_action_callback('delete_opening') do |_, json|
          r = JSON.parse(json)
          body = find_body(r['id'].to_s)
          if body
            begin
              if r['body'] == 'window'
                InteriorPro::WindowManager.delete_window(body)
              else
                InteriorPro::DoorManager.delete_door(body)
              end
              begin
                InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
              rescue StandardError
              end
              puts "[PlanEditor] #{r['body']} deleted"
            rescue StandardError => e
              puts "[PlanEditor] delete_opening: #{e.message}"
            end
          end
          push_walls(dlg)
        end

        dlg.add_action_callback('move_opening') do |_, json|
          r = JSON.parse(json)
          body = find_body(r['id'].to_s)
          delta = r['delta'].to_f
          if body && delta.abs > 0.01
            begin
              if r['body'] == 'window'
                InteriorPro::WindowManager.move_window(body, delta)
              else
                InteriorPro::DoorManager.move_door(body, delta)
              end
              begin
                InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
              rescue StandardError
              end
              puts "[PlanEditor] #{r['body']} moved #{delta.round(2)}\""
            rescue StandardError => e
              puts "[PlanEditor] move_opening: #{e.message}"
            end
          end
          push_walls(dlg)
        end

        dlg.add_action_callback('edit_door_swing') do |_, json|
          r = JSON.parse(json)
          door = find_body(r['id'].to_s)
          if door
            begin
              if r['flip_side']
                cs = (door.get_attribute('InteriorPro', 'clicked_side') || 1).to_i
                door.set_attribute('InteriorPro', 'clicked_side', -cs)
              end
              params = InteriorPro::DoorManager.params_from_door(door)
              params['swing_direction'] = r['swing'] == 'right' ? 'right' : 'left' if r['swing']
              InteriorPro::DoorManager.update_door(door, params)
              puts "[PlanEditor] door swing updated (#{params['swing_direction']}#{r['flip_side'] ? ', flipped' : ''})"
            rescue StandardError => e
              puts "[PlanEditor] edit_door_swing: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
            end
          end
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
            'id' => e.get_attribute('InteriorPro', 'id').to_s,
            'body' => tp,                       # 'door' / 'window' (for delete/move)
            't' => t.to_f.round(3),
            'w' => e.get_attribute('InteriorPro', 'width_in').to_f,
            'wtype' => tp == 'window' ? (e.get_attribute('InteriorPro', 'window_type') || '').to_s : '',
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
          corners = w.get_attribute('InteriorPro', 'corners_xy')
          cx = nil
          if corners.is_a?(Array) && corners.length == 8
            cx = corners.each_slice(2).flat_map do |x, y|
              p = Geom::Point3d.new(x.to_f, y.to_f, 0).transform(xf)
              [p.x.to_f.round(3), p.y.to_f.round(3)]
            end
          end
          {
            'id' => w.get_attribute('InteriorPro', 'id').to_s,
            'sx' => s.x.to_f.round(3), 'sy' => s.y.to_f.round(3),
            'ex' => e.x.to_f.round(3), 'ey' => e.y.to_f.round(3),
            'th' => w.get_attribute('InteriorPro', 'thickness').to_f,
            'ha' => h_anchor,
            'cat' => (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s,
            'ops' => ops,
            'corners' => cx,
            'syms' => syms[w.get_attribute('InteriorPro', 'id')] || []
          }
        end.compact
      end

      def push_walls(dlg)
        dlg.execute_script("loadWalls(#{JSON.generate(walls_payload)})")
      rescue StandardError => e
        puts "[PlanEditor] push_walls: #{e.message}"
      end

      # Real plugin catalogs: door types (built-in + custom) with their default
      # sizes, window types with presets, and the user's wall library.
      def catalogs_payload
        door_types = {}
        door_wh = {}
        %w[interior exterior].each do |cat|
          door_types[cat] = InteriorPro::DoorLibrary.all_types(cat)
          door_wh[cat] = {}
          door_types[cat].each do |t|
            d = InteriorPro::DoorLibrary.defaults_for_type(cat, t)
            door_wh[cat][t] = [d['width'].to_f, d['height'].to_f]
          end
        end
        win_types = InteriorPro::WindowLibrary.all_types
        win_wh = {}
        win_types.each do |t|
          p = InteriorPro::WindowLibrary::PRESETS[t]
          win_wh[t] = p ? [p['width'].to_f, p['height'].to_f] : [24.0, 48.0]
        end
        wall_types = InteriorPro::WallLibrary.load.map do |w|
          {
            'name' => w['name'].to_s,
            'th' => w['thickness'].to_f,
            'h' => w['height'].to_f,
            'cat' => (w['wall_category'] || 'exterior').to_s
          }
        end
        {
          'door_types' => door_types, 'door_wh' => door_wh,
          'win_types' => win_types, 'win_wh' => win_wh,
          'wall_types' => wall_types
        }
      end

      def push_catalogs(dlg)
        dlg.execute_script("loadCatalogs(#{JSON.generate(catalogs_payload)})")
      rescue StandardError => e
        puts "[PlanEditor] push_catalogs: #{e.message}"
      end

      def find_wall(id)
        Sketchup.active_model.entities.grep(Sketchup::Group).find do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
            g.get_attribute('InteriorPro', 'id') == id
        end
      end

      def find_body(id)
        return nil if id.empty?
        Sketchup.active_model.entities.to_a.find do |e|
          (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
            e.valid? &&
            %w[door window].include?(e.get_attribute('InteriorPro', 'type')) &&
            e.get_attribute('InteriorPro', 'id') == id
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
          # A wall type picked from the user's Wall Library brings its
          # materials/colors; otherwise plain editor defaults.
          lib = nil
          unless r['lib'].to_s.empty?
            lib = InteriorPro::WallLibrary.load.find { |t| t['name'].to_s == r['lib'].to_s }
          end
          attrs = {
            thickness: r['th'].to_f > 0.5 ? r['th'].to_f : 4.5,
            height: r['h'].to_f > 1.0 ? r['h'].to_f : 96.0,
            anchor: 'bottom-left',
            wall_type: lib ? lib['name'] : '2D Editor',
            exterior_material: lib ? (lib['exterior_material'] || 'Stucco') : (cat == 'exterior' ? 'Stucco' : '#ffffff'),
            interior_material: lib ? (lib['interior_color'] || lib['interior_material'] || '#ffffff') : '#ffffff',
            side_a_color: lib ? (lib['side_a_color'] || '#ffffff') : '#ffffff',
            side_b_color: lib ? (lib['side_b_color'] || '#ffffff') : '#ffffff',
            wall_category: cat
          }
          wt = InteriorPro::WallTool.new
          wt.wall_category = cat
          wt.side_a_color = attrs[:side_a_color]
          wt.side_b_color = attrs[:side_b_color]
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
            .red { background:#e0392b; color:#fff; }
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
            .modebtn { flex:0 0 47%; margin-bottom:4px; }
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
              <div class="seg" style="flex-wrap:wrap">
                <button id="modeSel" class="on modebtn" onclick="setMode('sel')">Select</button>
                <button id="modeWall" class="modebtn" onclick="setMode('wall')">Wall</button>
                <button id="modeDoor" class="modebtn" onclick="setMode('door')">Door</button>
                <button id="modeWin" class="modebtn" onclick="setMode('win')">Window</button>
              </div>

              <div id="secSel">
                <div id="selInfo" style="margin-top:12px; color:#555; font-size:12px">לא נבחר כלום — לחץ על קיר או פתח</div>
                <div id="selDoorOpts" style="display:none">
                  <label>Hinge side</label>
                  <div class="seg"><button id="selSwL" onclick="editSwing('left', false)">L</button><button id="selSwR" onclick="editSwing('right', false)">R</button></div>
                  <div style="margin-top:6px"><button class="gray" style="width:100%" onclick="editSwing(null, true)">Flip In / Out</button></div>
                </div>
                <div style="margin-top:10px"><button class="red" style="width:100%" id="selDelBtn" onclick="deleteSelected()">Delete selected</button></div>
                <div style="margin-top:8px; color:#777; font-size:11px">גרור דלת/חלון להזזה לאורך הקיר · מקש Delete מוחק</div>
              </div>

              <div id="secWall">
                <label>Wall type (library)</label><select id="wallType" onchange="wallTypeChanged()"><option value="">Custom</option></select>
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
            var mode = 'sel';
            var sel = null;           // {type:'wall', w} | {type:'sym', w, s} | {type:'pending', i}
            var dragSym = null;       // {w, s, startT, curT, valid, moved}
            var shiftDown = false;    // Shift = lock the current drawing direction (SketchUp style)
            var lockDir = null;       // locked unit direction while Shift is held
            var cat = 'exterior', sideOpt = 'L';
            var doorCat = 'interior', doorSwing = 'left';
            var scale = 1.6, panX = 60, panY = 60;   // model inches -> px
            var drawing = false, startPt = null, cursor = {x:0, y:0};
            var typed = '';
            var panning = false, panFrom = null;
            var fitted = false;
            var hoverHit = null;

            // Fallback catalogs - replaced by the real plugin libraries via
            // loadCatalogs() (DoorLibrary / WindowLibrary / WallLibrary).
            var DOOR_TYPES = {
              interior: ['Single', 'Double', 'Pocket', 'Folding', 'Closet'],
              exterior: ['Front Door', 'French Hinged', 'Sliding', 'Garage Door', 'Arched']
            };
            var DOOR_WH_CAT = null;   // {interior:{type:[w,h]}, exterior:{...}} from Ruby
            var DOOR_WH = { 'Single':[32,80], 'Double':[60,80], 'Pocket':[32,80], 'Folding':[48,80],
                            'Closet':[72,80], 'Front Door':[36,80], 'French Hinged':[60,80],
                            'Sliding':[60,80], 'Garage Door':[192,84], 'Arched':[36,96] };
            var WIN_TYPES = ['Casement', 'Casement XX', 'Single Hung', 'XOX Single Hung',
                             'Slider XO', 'Slider XOX', 'Garden Window', 'Arched'];
            var WIN_WH = { 'Casement':[24,48], 'Casement XX':[48,48], 'Single Hung':[24,36],
                           'XOX Single Hung':[96,48], 'Slider XO':[48,36], 'Slider XOX':[72,48],
                           'Garden Window':[60,48], 'Arched':[36,60] };
            var wallTypes = [];       // user's wall library
            var curWallLib = '';      // selected library wall type name ('' = custom)

            function loadCatalogs(c) {
              if (!c) return;
              if (c.door_types) DOOR_TYPES = c.door_types;
              if (c.door_wh) DOOR_WH_CAT = c.door_wh;
              if (c.win_types && c.win_types.length) WIN_TYPES = c.win_types;
              if (c.win_wh) WIN_WH = c.win_wh;
              wallTypes = c.wall_types || [];
              var sel2 = document.getElementById('wallType');
              sel2.innerHTML = '<option value="">Custom</option>';
              wallTypes.forEach(function(t){
                var o = document.createElement('option');
                o.value = t.name; o.textContent = t.name + ' (' + t.cat + ')';
                sel2.appendChild(o);
              });
              fillSelect('dType', DOOR_TYPES[doorCat] || []);
              fillSelect('wType', WIN_TYPES);
              doorTypeChanged();
              winTypeChanged();
            }

            function wallTypeChanged() {
              curWallLib = document.getElementById('wallType').value;
              var t = wallTypes.find(function(x){ return x.name === curWallLib; });
              if (!t) return;
              document.getElementById('th').value = t.th;
              document.getElementById('hh').value = t.h;
              setCat(t.cat === 'interior' ? 'interior' : 'exterior', true);
            }

            function fillSelect(id, list) {
              var el = document.getElementById(id);
              el.innerHTML = '';
              list.forEach(function(t){ var o = document.createElement('option'); o.value = t; o.textContent = t; el.appendChild(o); });
            }
            function doorTypeChanged() {
              var t = document.getElementById('dType').value;
              var wh = (DOOR_WH_CAT && DOOR_WH_CAT[doorCat] && DOOR_WH_CAT[doorCat][t]) || DOOR_WH[t] || [32, 80];
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
              mode = m; endChain(); hoverHit = null; sel = null; dragSym = null;
              // Doors/windows need applied walls - apply pending automatically.
              if ((m === 'door' || m === 'win') && pending.length) applyPending();
              document.getElementById('modeSel').className = (m === 'sel' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeWall').className = (m === 'wall' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeDoor').className = (m === 'door' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeWin').className = (m === 'win' ? 'on ' : '') + 'modebtn';
              document.getElementById('secSel').style.display = m === 'sel' ? '' : 'none';
              document.getElementById('secWall').style.display = m === 'wall' ? '' : 'none';
              document.getElementById('secDoor').style.display = m === 'door' ? '' : 'none';
              document.getElementById('secWin').style.display = m === 'win' ? '' : 'none';
              var hint = m === 'wall'
                ? 'Click to start a wall - move - type length + Enter, or click. Right-click / Esc ends the chain.'
                : (m === 'sel'
                  ? 'Click a wall or an opening to select. Drag an opening to move it. Delete key removes.'
                  : 'Click on an applied wall to place. Green = fits, red = does not fit.');
              document.getElementById('hint').textContent = hint;
              updateSelPanel();
              draw();
            }

            function updateSelPanel() {
              var info = document.getElementById('selInfo');
              var dopts = document.getElementById('selDoorOpts');
              if (!info) return;
              dopts.style.display = 'none';
              if (!sel) {
                info.textContent = 'לא נבחר כלום — לחץ על קיר או פתח';
                return;
              }
              if (sel.type === 'wall') {
                var b = bandQuad(sel.w);
                info.textContent = 'Wall: ' + fmtLen(b ? b.len : 0) + ' · ' + sel.w.th + '" · ' + sel.w.cat;
              } else if (sel.type === 'pending') {
                info.textContent = 'Pending wall (not applied)';
              } else {
                info.textContent = (sel.s.body === 'window' ? 'Window' : 'Door') + ' · ' + fmtLen(sel.s.w);
                if (sel.s.body === 'door') {
                  dopts.style.display = '';
                  document.getElementById('selSwL').className = sel.s.swing === 'left' ? 'on' : '';
                  document.getElementById('selSwR').className = sel.s.swing === 'right' ? 'on' : '';
                }
              }
            }

            function editSwing(swing, flip) {
              if (!sel || sel.type !== 'sym' || sel.s.body !== 'door') return;
              sketchup.edit_door_swing(JSON.stringify({
                id: sel.s.id,
                swing: swing || sel.s.swing,
                flip_side: !!flip
              }));
            }

            function deleteSelected() {
              if (!sel) return;
              if (sel.type === 'pending') { pending.splice(sel.i, 1); sel = null; updateSelPanel(); draw(); return; }
              if (!confirm('למחוק את מה שנבחר?')) return;
              if (sel.type === 'wall') {
                sketchup.delete_wall(JSON.stringify({ wall_id: sel.w.id }));
              } else {
                sketchup.delete_opening(JSON.stringify({ id: sel.s.id, body: sel.s.body }));
              }
              sel = null; updateSelPanel();
            }

            function hitOpening(p) {
              var best = null;
              walls.forEach(function(w){
                var b = bandQuad(w); if (!b || !w.syms) return;
                var dx = p.x - w.sx, dy = p.y - w.sy;
                var tt = dx*b.ux + dy*b.uy;
                var off = dx*b.nx + dy*b.ny;
                var tol = 8 / scale;
                w.syms.forEach(function(s){
                  if (tt < s.t - s.w/2 - 2 || tt > s.t + s.w/2 + 2) return;
                  if (off < b.q - tol - 4 || off > b.p + tol + 4) return;
                  best = { w:w, s:s, b:b };
                });
              });
              return best;
            }

            function hitPending(p) {
              for (var i = pending.length - 1; i >= 0; i--) {
                var w = pending[i];
                var b = bandQuad(w); if (!b) continue;
                var dx = p.x - w.sx, dy = p.y - w.sy;
                var tt = dx*b.ux + dy*b.uy;
                var off = dx*b.nx + dy*b.ny;
                if (tt >= -2 && tt <= b.len + 2 && off >= b.q - 3 && off <= b.p + 3) return i;
              }
              return -1;
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

            function lineInt(p1, d1, p2, d2) {
              var denom = d1.x*d2.y - d1.y*d2.x;
              if (Math.abs(denom) < 1e-9) return null;
              var t = ((p2.x - p1.x)*d2.y - (p2.y - p1.y)*d2.x) / denom;
              return { x: p1.x + d1.x*t, y: p1.y + d1.y*t };
            }

            // Band corner points at both wall ends. Applied walls use the exact
            // mitered corners_xy from the model; pending walls get a JS miter
            // against the neighbour that shares the endpoint.
            function endCorners(w, all, b) {
              if (w.corners && w.corners.length === 8) {
                return { sp:{x:w.corners[0],y:w.corners[1]}, ep:{x:w.corners[2],y:w.corners[3]},
                         eq:{x:w.corners[4],y:w.corners[5]}, sq:{x:w.corners[6],y:w.corners[7]} };
              }
              var def = {
                sp:{x:w.sx + b.nx*b.p, y:w.sy + b.ny*b.p},
                sq:{x:w.sx + b.nx*b.q, y:w.sy + b.ny*b.q},
                ep:{x:w.ex + b.nx*b.p, y:w.ey + b.ny*b.p},
                eq:{x:w.ex + b.nx*b.q, y:w.ey + b.ny*b.q}
              };
              ['s','e'].forEach(function(end){
                var P = end === 's' ? {x:w.sx, y:w.sy} : {x:w.ex, y:w.ey};
                var partner = null, cont = true;
                (all || []).forEach(function(o){
                  if (o === w || partner) return;
                  if (Math.hypot(o.sx - P.x, o.sy - P.y) < 1.0) { partner = o; cont = (end === 'e'); }
                  else if (Math.hypot(o.ex - P.x, o.ey - P.y) < 1.0) { partner = o; cont = (end === 's'); }
                });
                if (!partner) return;
                var ob = bandQuad(partner); if (!ob) return;
                if (Math.abs(b.ux*ob.ux + b.uy*ob.uy) > 0.985) return;   // collinear
                var maxR = (w.th + partner.th) * 2 + 6;
                // Head-to-tail chains pair p-edge with p-edge; head-to-head pair p with q.
                [['p', b.p, cont ? ob.p : ob.q],
                 ['q', b.q, cont ? ob.q : ob.p]].forEach(function(sd){
                  var A = {x: w.sx + b.nx*sd[1], y: w.sy + b.ny*sd[1]};
                  var B = {x: partner.sx + ob.nx*sd[2], y: partner.sy + ob.ny*sd[2]};
                  var I = lineInt(A, {x:b.ux, y:b.uy}, B, {x:ob.ux, y:ob.uy});
                  if (I && Math.hypot(I.x - P.x, I.y - P.y) < maxR) def[end + sd[0]] = I;
                });
              });
              return def;
            }

            function drawWallBand(w, fillEx, fillIn, alpha, all) {
              var b = bandQuad(w); if (!b) return;
              var C = endCorners(w, all, b);
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
                var P1 = {x: w.sx + b.ux*a + b.nx*b.p, y: w.sy + b.uy*a + b.ny*b.p};
                var Q1 = {x: w.sx + b.ux*a + b.nx*b.q, y: w.sy + b.uy*a + b.ny*b.q};
                var P2 = {x: w.sx + b.ux*c + b.nx*b.p, y: w.sy + b.uy*c + b.ny*b.p};
                var Q2 = {x: w.sx + b.ux*c + b.nx*b.q, y: w.sy + b.uy*c + b.ny*b.q};
                if (a <= 0.05) { P1 = C.sp; Q1 = C.sq; }
                if (c >= b.len - 0.05) { P2 = C.ep; Q2 = C.eq; }
                ctx.beginPath();
                ctx.moveTo(sx(P1.x), sy(P1.y));
                ctx.lineTo(sx(P2.x), sy(P2.y));
                ctx.lineTo(sx(Q2.x), sy(Q2.y));
                ctx.lineTo(sx(Q1.x), sy(Q1.y));
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
            var JAMB = 1.5;

            // Per-type window plan symbol (exterior = q side). No glass lines.
            function winUnit(w, b, t, fx1, fx2) {
              var q = b.q, p = b.p, th = p - q, len = fx2 - fx1;
              var e1 = q + th*0.15, e2 = q + th*0.45, i1 = p - th*0.45, i2 = p - th*0.15;
              function blk(cx) { symRect(w, b, cx - 1, cx + 1, q + 1, p - 1); }
              if (/Casement XX/.test(t)) {
                casLeaf(w, b, fx1, fx1 + len/2, q);
                casLeaf(w, b, fx2, fx2 - len/2, q);
              } else if (/Casement/.test(t)) {
                casLeaf(w, b, fx1, fx2, q);
              } else if (/XOX/.test(t)) {
                // minimal slider style (user sketch): dividers + one line per panel
                var cm = (p + q)/2, w3 = len/3, d1 = fx1 + w3, d2 = fx2 - w3;
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
                symRect(w, b, d1 - 1, d1 + 1, q + 0.7, p - 0.7);
                symRect(w, b, d2 - 1, d2 + 1, q + 0.7, p - 0.7);
                polyline([wpt(w,b,d1+1,cm - th*0.11), wpt(w,b,d2-1,cm - th*0.11)]);
                polyline([wpt(w,b,fx1+0.5,cm + th*0.11), wpt(w,b,d1-1,cm + th*0.11)]);
                polyline([wpt(w,b,d2+1,cm + th*0.11), wpt(w,b,fx2-0.5,cm + th*0.11)]);
              } else if (/Slider|XO/.test(t)) {
                var cm2 = (p + q)/2, xm = (fx1 + fx2)/2;
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
                symRect(w, b, xm - 1, xm + 1, q + 0.7, p - 0.7);
                polyline([wpt(w,b,fx1+0.5,cm2 + th*0.11), wpt(w,b,xm-1,cm2 + th*0.11)]);
                polyline([wpt(w,b,xm+1,cm2 - th*0.11), wpt(w,b,fx2-0.5,cm2 - th*0.11)]);
              } else if (/Hung/.test(t)) {
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, e1, e2);
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, i1, i2);
              } else if (/Garden/.test(t)) {
                var gd = 12;
                symRect(w, b, fx1 + 1, fx2 - 1, q - gd, q);
                symRect(w, b, fx1 + 2, fx2 - 2, q - gd + 1, q - 1);
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, i1, i2);
              } else if (/Arched/.test(t)) {
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
                for (var i3 = 0; i3 < 24; i3 += 2) {
                  var t1 = i3/24, t2 = (i3+1)/24;
                  polyline([wpt(w, b, fx1 + len*t1, p - 1 - (th - 2)*Math.sin(Math.PI*t1)),
                            wpt(w, b, fx1 + len*t2, p - 1 - (th - 2)*Math.sin(Math.PI*t2))]);
                }
              } else {
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
              }
            }

            // Casement leaf pivoted ~20deg toward the exterior + thin arc.
            function casLeaf(w, b, hx, lx, q) {
              var len = Math.abs(lx - hx); if (len < 4) return;
              var dir = lx > hx ? 1 : -1, ang = 20*Math.PI/180;
              var lux = b.ux*dir*Math.cos(ang) - b.nx*Math.sin(ang);
              var luy = b.uy*dir*Math.cos(ang) - b.ny*Math.sin(ang);
              var pdx = b.nx*Math.cos(ang) + b.ux*dir*Math.sin(ang);
              var pdy = b.ny*Math.cos(ang) + b.uy*dir*Math.sin(ang);
              var h = wpt(w, b, hx, q);
              var tip = { x: h.x + lux*len, y: h.y + luy*len };
              polyline([h, tip, {x:tip.x+pdx*2, y:tip.y+pdy*2}, {x:h.x+pdx*2, y:h.y+pdy*2}, h]);
              var l = wpt(w, b, lx, q);
              var v0 = {x:l.x-h.x, y:l.y-h.y}, v1 = {x:tip.x-h.x, y:tip.y-h.y};
              var sweep = Math.atan2(v0.x*v1.y - v0.y*v1.x, v0.x*v1.x + v0.y*v1.y);
              var pts = [];
              for (var i4 = 0; i4 <= 10; i4++) {
                var a = sweep*i4/10, ca = Math.cos(a), sa = Math.sin(a);
                pts.push({ x: h.x + v0.x*ca - v0.y*sa, y: h.y + v0.x*sa + v0.y*ca });
              }
              polyline(pts);
            }

            function symJambs(w, b, x1, x2) {
              symRect(w, b, x1, x1 + JAMB, b.q, b.p);
              symRect(w, b, x2 - JAMB, x2, b.q, b.p);
            }
            function symHeader(w, b, x1, x2) {
              symDashed(w, b, x1 + JAMB, x2 - JAMB, b.p - 0.4);
              symDashed(w, b, x1 + JAMB, x2 - JAMB, b.q + 0.4);
            }

            function symArcDoor(w, b, x1, x2, swing, clicked) {
              symJambs(w, b, x1, x2);
              symHeader(w, b, x1, x2);
              symLeaf(w, b, swing === 'right' ? x2 - JAMB : x1 + JAMB,
                      swing === 'right' ? x1 + JAMB : x2 - JAMB, clicked);
            }

            // Leaf as a thin rectangle + arc (Chief-Architect style).
            function symLeaf(w, b, hx, lx, clicked) {
              var ss = clicked >= 0 ? -1 : 1;
              var edge = ss > 0 ? b.p : b.q;
              var len = Math.abs(lx - hx);
              if (len < 4) return;
              var dir = lx > hx ? 1 : -1;
              var ua = Math.min(hx, hx + dir*1.5), ub = Math.max(hx, hx + dir*1.5);
              // leaf rectangle spans [ua..ub] along the wall, edge..edge+ss*len across
              polyline([wpt(w,b,ua,edge), wpt(w,b,ub,edge),
                        wpt(w,b,ub,edge + ss*len), wpt(w,b,ua,edge + ss*len), wpt(w,b,ua,edge)]);
              var h = wpt(w, b, hx, edge), l = wpt(w, b, lx, edge);
              var leafEnd = { x: h.x + b.nx*ss*len, y: h.y + b.ny*ss*len };
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
                  symJambs(w, b, x1, x2);
                  symRect(w, b, x1 + JAMB, x2 - JAMB, b.q, b.p);
                  winUnit(w, b, s.wtype || '', x1 + JAMB, x2 - JAMB);
                } else if (s.kind === 'door') {
                  symArcDoor(w, b, x1, x2, s.swing, s.clicked);
                } else if (s.kind === 'double') {
                  var xm = (x1 + x2) / 2;
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  symLeaf(w, b, x1 + JAMB, xm, s.clicked);
                  symLeaf(w, b, x2 - JAMB, xm, s.clicked);
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
              var all = walls.concat(pending);
              walls.forEach(function(w){ drawWallBand(w, '#444', '#cfcfcf', 1, all); drawSyms(w); dimLabel(w, '#1a6ee0'); });
              pending.forEach(function(w){ drawWallBand(w, '#2f6bd8', '#9db8e8', 1, all); dimLabel(w, '#e0392b'); });
              if (mode === 'wall' && drawing && startPt) {
                var end = currentEnd();
                var w = tempWall(startPt, end);
                drawWallBand(w, '#2f6bd8', '#9db8e8', 0.5, all);
                ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 1;
                ctx.setLineDash([5,4]);
                ctx.beginPath(); ctx.moveTo(sx(startPt.x), sy(startPt.y)); ctx.lineTo(sx(end.x), sy(end.y)); ctx.stroke();
                ctx.setLineDash([]);
                var dd = Math.hypot(end.x - startPt.x, end.y - startPt.y);
                ctx.fillStyle = '#1a6ee0'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText(fmtLen(dd), sx(end.x) + 12, sy(end.y) - 8);
                if (shiftDown && lockDir) {   // locked-direction guide line
                  ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1;
                  ctx.setLineDash([2,4]);
                  ctx.beginPath();
                  ctx.moveTo(sx(startPt.x - lockDir.x*2000), sy(startPt.y - lockDir.y*2000));
                  ctx.lineTo(sx(startPt.x + lockDir.x*4000), sy(startPt.y + lockDir.y*4000));
                  ctx.stroke();
                  ctx.setLineDash([]);
                  if (snapInd) {              // aim line: inference point -> locked wall end
                    ctx.strokeStyle = '#00b8d9'; ctx.lineWidth = 1;
                    ctx.setLineDash([3,3]);
                    ctx.beginPath();
                    ctx.moveTo(sx(snapInd.x), sy(snapInd.y));
                    ctx.lineTo(sx(end.x), sy(end.y));
                    ctx.stroke();
                    ctx.setLineDash([]);
                  }
                }
                if (snapInd) {                // inference point marker
                  ctx.fillStyle = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                  ctx.beginPath();
                  ctx.arc(sx(snapInd.x), sy(snapInd.y), 5, 0, Math.PI*2);
                  ctx.fill();
                }
              }
              if ((mode === 'door' || mode === 'win') && hoverHit) drawGhostOpening();
              if (mode === 'sel') drawSelection();
              updateStatus();
            }

            function outlineBand(w, color) {
              var b = bandQuad(w); if (!b) return;
              ctx.strokeStyle = color; ctx.lineWidth = 2.5;
              ctx.beginPath();
              ctx.moveTo(sx(w.sx + b.nx*b.p), sy(w.sy + b.ny*b.p));
              ctx.lineTo(sx(w.ex + b.nx*b.p), sy(w.ey + b.ny*b.p));
              ctx.lineTo(sx(w.ex + b.nx*b.q), sy(w.ey + b.ny*b.q));
              ctx.lineTo(sx(w.sx + b.nx*b.q), sy(w.sy + b.ny*b.q));
              ctx.closePath(); ctx.stroke();
            }

            function outlineOpening(w, s, t, color) {
              var b = bandQuad(w); if (!b) return;
              var x1 = t - s.w/2, x2 = t + s.w/2;
              ctx.strokeStyle = color; ctx.lineWidth = 2.5;
              ctx.beginPath();
              ctx.moveTo(sx(w.sx + b.ux*x1 + b.nx*(b.p+2)), sy(w.sy + b.uy*x1 + b.ny*(b.p+2)));
              ctx.lineTo(sx(w.sx + b.ux*x2 + b.nx*(b.p+2)), sy(w.sy + b.uy*x2 + b.ny*(b.p+2)));
              ctx.lineTo(sx(w.sx + b.ux*x2 + b.nx*(b.q-2)), sy(w.sy + b.uy*x2 + b.ny*(b.q-2)));
              ctx.lineTo(sx(w.sx + b.ux*x1 + b.nx*(b.q-2)), sy(w.sy + b.uy*x1 + b.ny*(b.q-2)));
              ctx.closePath(); ctx.stroke();
            }

            function drawSelection() {
              if (dragSym && dragSym.moved) {
                outlineOpening(dragSym.w, dragSym.s, dragSym.curT, dragSym.valid ? '#1a9d55' : '#e0392b');
                return;
              }
              if (!sel) return;
              if (sel.type === 'wall') outlineBand(sel.w, '#4b89ff');
              else if (sel.type === 'pending') { var w = pending[sel.i]; if (w) outlineBand(w, '#4b89ff'); }
              else outlineOpening(sel.w, sel.s, sel.s.t, '#4b89ff');
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

            var snapInd = null;   // last inference point {x, y, kind:'end'|'mid'} for display

            function snapPoint(p, from) {
              snapInd = null;
              var r = 14 / scale;
              var bestEnd = null, bestEndD = r, bestMid = null, bestMidD = r;
              walls.concat(pending).forEach(function(w){
                [{x:w.sx, y:w.sy}, {x:w.ex, y:w.ey}].forEach(function(c){
                  var d = Math.hypot(c.x - p.x, c.y - p.y);
                  if (d < bestEndD) { bestEnd = c; bestEndD = d; }
                });
                var m = {x:(w.sx + w.ex)/2, y:(w.sy + w.ey)/2};
                var dm = Math.hypot(m.x - p.x, m.y - p.y);
                if (dm < bestMidD) { bestMid = m; bestMidD = dm; }
              });
              if (bestEnd) {
                snapInd = { x:bestEnd.x, y:bestEnd.y, kind:'end' };
                return { x:bestEnd.x, y:bestEnd.y, snapped:true };
              }
              if (bestMid) {
                snapInd = { x:bestMid.x, y:bestMid.y, kind:'mid' };
                return { x:bestMid.x, y:bestMid.y, snapped:true };
              }
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

            // Capture the direction being drawn the moment Shift goes down
            // (snapped to 45deg when close to an axis) - SketchUp-style lock.
            function captureLockDir() {
              if (!drawing || !startPt) { lockDir = null; return; }
              var dx = cursor.x - startPt.x, dy = cursor.y - startPt.y;
              var d = Math.hypot(dx, dy);
              if (d < 1) { lockDir = null; return; }
              var ang = Math.atan2(dy, dx);
              var snapAng = Math.round(ang / (Math.PI/4)) * (Math.PI/4);
              if (Math.abs(ang - snapAng) < 0.18) ang = snapAng;
              lockDir = { x: Math.cos(ang), y: Math.sin(ang) };
            }

            function currentEnd() {
              var typedLen = parseLen(typed);
              if (shiftDown && lockDir && startPt) {
                // Locked direction: any point (incl. endpoint snaps) projects
                // onto the locked ray; typed length wins.
                var p0 = snapPoint(cursor, null);
                var t = (p0.x - startPt.x)*lockDir.x + (p0.y - startPt.y)*lockDir.y;
                if (typedLen) t = typedLen;
                if (t < 1) t = 1;
                return { x: startPt.x + lockDir.x*t, y: startPt.y + lockDir.y*t };
              }
              var p = snapPoint(cursor, startPt);
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
              w.lib = curWallLib;
              w.anchor = 'bottom-left';
              if (sideOpt === 'R') {   // flip direction so the band side matches, keep bottom-left
                var t2 = { x: w.sx, y: w.sy };
                w.sx = w.ex; w.sy = w.ey; w.ex = t2.x; w.ey = t2.y;
                w.ha = 'left';
              }
              if (!mergeCollinear(w)) pending.push(w);
              startPt = end; typed = ''; updateVcb(); draw();
            }

            // A wall drawn as an exact continuation of a pending wall (collinear,
            // sharing an endpoint, same thickness/category) EXTENDS it instead of
            // creating a second wall - no seam, one wall.
            function mergeCollinear(w) {
              var dx = w.ex - w.sx, dy = w.ey - w.sy;
              var len = Math.hypot(dx, dy); if (len < 0.5) return false;
              var ux = dx/len, uy = dy/len;
              for (var i5 = 0; i5 < pending.length; i5++) {
                var p = pending[i5];
                if (p.th !== w.th || p.cat !== w.cat) continue;
                var pdx = p.ex - p.sx, pdy = p.ey - p.sy;
                var pl = Math.hypot(pdx, pdy); if (pl < 0.5) continue;
                var pux = pdx/pl, puy = pdy/pl;
                var dot = pux*ux + puy*uy;
                if (Math.abs(dot) < 0.9995) continue;
                if (dot > 0 && Math.hypot(p.ex - w.sx, p.ey - w.sy) < 0.6) { p.ex = w.ex; p.ey = w.ey; return true; }
                if (dot > 0 && Math.hypot(p.sx - w.ex, p.sy - w.ey) < 0.6) { p.sx = w.sx; p.sy = w.sy; return true; }
                if (dot < 0 && Math.hypot(p.sx - w.sx, p.sy - w.sy) < 0.6) { p.sx = w.ex; p.sy = w.ey; return true; }
                if (dot < 0 && Math.hypot(p.ex - w.ex, p.ey - w.ey) < 0.6) { p.ex = w.sx; p.ey = w.sy; return true; }
              }
              return false;
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
              if (mode === 'sel') {
                var ho = hitOpening(p);
                if (ho) {
                  sel = { type:'sym', w:ho.w, s:ho.s };
                  dragSym = { w:ho.w, s:ho.s, b:ho.b, startT:ho.s.t, curT:ho.s.t, valid:true, moved:false };
                } else {
                  var hw = hitWall(p);
                  if (hw) sel = { type:'wall', w:hw.w };
                  else {
                    var pi = hitPending(p);
                    sel = pi >= 0 ? { type:'pending', i:pi } : null;
                  }
                  dragSym = null;
                }
                updateSelPanel(); draw();
                return;
              }
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
              if (mode === 'sel' && dragSym) {
                var w = dragSym.w, b = dragSym.b;
                var tt = (cursor.x - w.sx)*b.ux + (cursor.y - w.sy)*b.uy;
                var hw2 = dragSym.s.w / 2;
                tt = Math.max(hw2, Math.min(b.len - hw2, tt));
                if (Math.abs(tt - dragSym.startT) > 0.25) dragSym.moved = true;
                dragSym.curT = tt;
                dragSym.valid = true;
                draw();
                return;
              }
              if (mode === 'door' || mode === 'win') { hoverHit = hitWall(cursor); draw(); return; }
              if (drawing) draw();
            });
            window.addEventListener('mouseup', function() {
              panning = false;
              if (mode === 'sel' && dragSym) {
                var delta = dragSym.curT - dragSym.startT;
                if (dragSym.moved && Math.abs(delta) > 0.25) {
                  sketchup.move_opening(JSON.stringify({ id: dragSym.s.id, body: dragSym.s.body, delta: delta }));
                }
                dragSym = null;
                draw();
              }
            });
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

            window.addEventListener('keyup', function(ev) {
              if (ev.key === 'Shift') { shiftDown = false; lockDir = null; if (drawing) draw(); }
            });
            window.addEventListener('keydown', function(ev) {
              if (ev.key === 'Shift') {
                if (!shiftDown) { shiftDown = true; captureLockDir(); }
                if (drawing) draw();
                return;
              }
              if (ev.target.tagName === 'INPUT' || ev.target.tagName === 'SELECT') return;
              if (ev.key === 'Escape') { endChain(); if (mode === 'sel') { sel = null; dragSym = null; updateSelPanel(); draw(); } return; }
              if (mode === 'sel' && (ev.key === 'Delete' || ev.key === 'Backspace')) {
                deleteSelected(); ev.preventDefault(); return;
              }
              if (mode !== 'wall') return;
              if (ev.key === 'Enter') { if (drawing && typed) commitSegment(); return; }
              if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); if (drawing) draw(); ev.preventDefault(); return; }
              if (/^[0-9.'" ]$/.test(ev.key)) { typed += ev.key; updateVcb(); if (drawing) draw(); }
            });

            // ---- side panel (wall) ----
            function setCat(c, keep) {
              cat = c;
              document.getElementById('catE').className = c === 'exterior' ? 'on' : '';
              document.getElementById('catI').className = c === 'interior' ? 'on' : '';
              if (!keep) {
                document.getElementById('th').value = c === 'interior' ? '4.5' : '5';
                curWallLib = '';
                document.getElementById('wallType').value = '';
              }
            }
            function setSide(s) {
              sideOpt = s;
              document.getElementById('sideL').className = s === 'L' ? 'on' : '';
              document.getElementById('sideR').className = s === 'R' ? 'on' : '';
            }
            function undoPending() { pending.pop(); draw(); }

            // ---- Ruby bridge ----
            // Exterior walls always face OUT of the building, regardless of the
            // direction they were drawn in: if a wall's band points away from
            // the drawing's center, flip it (anchor stays bottom-left).
            function autoOrientExterior() {
              var ext = pending.filter(function(w){ return w.cat === 'exterior'; });
              if (ext.length < 3) return;
              var cx = 0, cy = 0, n = 0;
              ext.forEach(function(w){ cx += w.sx + w.ex; cy += w.sy + w.ey; n += 2; });
              cx /= n; cy /= n;
              ext.forEach(function(w){
                var b = bandQuad(w); if (!b) return;
                var mid = (b.p + b.q) / 2;
                var lx = (w.sx + w.ex)/2, ly = (w.sy + w.ey)/2;
                var bx = lx + b.nx*mid, by = ly + b.ny*mid;
                if (Math.hypot(bx - cx, by - cy) > Math.hypot(lx - cx, ly - cy)) {
                  var t = {x:w.sx, y:w.sy};
                  w.sx = w.ex; w.sy = w.ey; w.ex = t.x; w.ey = t.y;
                  w.ha = 'left';
                }
              });
              draw();
            }

            function applyPending() {
              if (!pending.length) return;
              autoOrientExterior();
              sketchup.apply_walls(JSON.stringify(pending));
            }
            function applyDone(n) { pending = []; draw(); }
            function planDone(ok) {}
            function loadWalls(list) {
              walls = list || [];
              hoverHit = null; sel = null; dragSym = null;
              if (typeof updateSelPanel === 'function') updateSelPanel();
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
            setMode('sel');
            resize();
            sketchup.editor_ready();
          </script>
          </body></html>
        HTML
      end
    end
  end
end

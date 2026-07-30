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
        dlg.add_action_callback('sync_model') do |_|
          push_catalogs(dlg)   # re-read the model's wall/door/window defaults
          push_walls(dlg)
        end

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

        dlg.add_action_callback('edit_opening_size') do |_, json|
          r = JSON.parse(json)
          body = find_body(r['id'].to_s)
          if body
            begin
              w = r['width'].to_f
              h = r['height'].to_f
              if r['body'] == 'window'
                g = ->(k, dv) { v = body.get_attribute('InteriorPro', k); v.nil? ? dv : v }
                settings = {
                  'window_type' => g.call('window_type', 'Casement').to_s,
                  'width' => w > 6 ? w : body.get_attribute('InteriorPro', 'width_in').to_f,
                  'height' => h > 6 ? h : body.get_attribute('InteriorPro', 'height_in').to_f,
                  'header_height' => r['header'].to_f > 12 ? r['header'].to_f : g.call('header_height_in', 80).to_f,
                  'frame_width' => g.call('frame_width_in', 1.5).to_f,
                  'interior_depth' => g.call('interior_depth_in', 1.0).to_f,
                  'arch_rise' => g.call('arch_rise_in', 0).to_f,
                  'glass_grid_style' => g.call('glass_grid_style', 'none').to_s,
                  'exterior_casing_style' => g.call('exterior_casing_style', 'none').to_s,
                  'interior_casing_style' => g.call('interior_casing_style', 'none').to_s
                }
                InteriorPro::WindowManager.update_window(body, settings)
              else
                params = InteriorPro::DoorManager.params_from_door(body)
                params['width'] = w if w > 6
                params['height'] = h if h > 12
                InteriorPro::DoorManager.update_door(body, params)
              end
              begin
                InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
              rescue StandardError
              end
              puts "[PlanEditor] opening resized to #{w}x#{h}"
            rescue StandardError => e
              puts "[PlanEditor] edit_opening_size: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
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

        # Set an opening's absolute position along the wall (from dimension edit).
        dlg.add_action_callback('set_opening_t') do |_, json|
          r = JSON.parse(json)
          body = find_body(r['id'].to_s)
          if body
            begin
              cur = body.get_attribute('InteriorPro', 'position_along_wall_in').to_f
              delta = r['t'].to_f - cur
              if delta.abs > 0.01
                if r['body'] == 'window'
                  InteriorPro::WindowManager.move_window(body, delta)
                else
                  InteriorPro::DoorManager.move_door(body, delta)
                end
                begin
                  InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
                rescue StandardError
                end
              end
            rescue StandardError => e
              puts "[PlanEditor] set_opening_t: #{e.message}"
            end
          end
          push_walls(dlg)
        end

        # Wall length edit. 'fixed' says WHICH corner stays put ('start'/'end');
        # the other end moves. Same sequence as WallStretchTool#commit! but
        # explicit (no ivar juggling) so it can be driven from the dialog.
        dlg.add_action_callback('set_wall_length') do |_, json|
          r = JSON.parse(json)
          wall = find_wall(r['wall_id'].to_s)
          keep = r['keep'].nil? ? true : (r['keep'] ? true : false)
          stretch_wall!(wall, r['len'].to_f, r['fixed'].to_s == 'end' ? :start : :end, keep)
          push_walls(dlg)
        end

        # Diagnostics for the selected wall: endpoints + how far every other
        # wall's endpoints are from them (why a corner does / does not follow).
        dlg.add_action_callback('debug_wall') do |_, json|
          r = JSON.parse(json)
          w = find_wall(r['wall_id'].to_s)
          if w.nil?
            puts '[Diag] wall not found'
          else
            sx = w.get_attribute('InteriorPro', 'start_x').to_f
            sy = w.get_attribute('InteriorPro', 'start_y').to_f
            ex = w.get_attribute('InteriorPro', 'end_x').to_f
            ey = w.get_attribute('InteriorPro', 'end_y').to_f
            puts "[Diag] SELECTED id=#{w.get_attribute('InteriorPro', 'id').to_s[0, 8]} " \
                 "cat=#{w.get_attribute('InteriorPro', 'wall_category')} " \
                 "anchor=#{w.get_attribute('InteriorPro', 'anchor')} th=#{w.get_attribute('InteriorPro', 'thickness')} " \
                 "s=(#{sx.round(2)},#{sy.round(2)}) e=(#{ex.round(2)},#{ey.round(2)}) xform_identity=#{w.transformation.identity?}"
            Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
              next if g == w
              next unless g.get_attribute('InteriorPro', 'type') == 'wall'
              gsx = g.get_attribute('InteriorPro', 'start_x').to_f
              gsy = g.get_attribute('InteriorPro', 'start_y').to_f
              gex = g.get_attribute('InteriorPro', 'end_x').to_f
              gey = g.get_attribute('InteriorPro', 'end_y').to_f
              d = [[gsx - sx, gsy - sy], [gsx - ex, gsy - ey],
                   [gex - sx, gey - sy], [gex - ex, gey - ey]].map { |a, b| Math.sqrt(a * a + b * b) }
              next if d.min > 24.0
              puts "[Diag]   other id=#{g.get_attribute('InteriorPro', 'id').to_s[0, 8]} " \
                   "cat=#{g.get_attribute('InteriorPro', 'wall_category')} " \
                   "s=(#{gsx.round(2)},#{gsy.round(2)}) e=(#{gex.round(2)},#{gey.round(2)}) " \
                   "dists=[#{d.map { |x| x.round(3) }.join(', ')}] -> #{d.min < 0.1 ? 'SHARES A CORNER' : 'no shared corner'}"
            end
          end
        end

        dlg.add_action_callback('move_wall') do |_, json|
          r = JSON.parse(json)
          keep = r['keep'].nil? ? true : (r['keep'] ? true : false)
          move_wall_sideways!(find_wall(r['wall_id'].to_s), r['dist'].to_f, keep)
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
            'h' => e.get_attribute('InteriorPro', 'height_in').to_f,
            'header' => tp == 'window' ? e.get_attribute('InteriorPro', 'header_height_in').to_f : 0,
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
            'cat' => (w['wall_category'] || 'exterior').to_s,
            'src' => 'lib'
          }
        end
        {
          'door_types' => door_types, 'door_wh' => door_wh,
          'win_types' => win_types, 'win_wh' => win_wh,
          'wall_types' => wall_types,
          'model_walls' => model_wall_types,
          'model_doors' => model_door_defaults,
          'model_windows' => model_window_defaults
        }
      end

      # Wall configurations that actually EXIST in the model (the 3D truth):
      # distinct wall_type + category, with thickness/height. These become the
      # default choices in the editor.
      def model_wall_types
        out = {}
        Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
          next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
          cat = (g.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
          name = g.get_attribute('InteriorPro', 'wall_type').to_s
          name = cat == 'interior' ? 'Interior wall' : 'Exterior wall' if name.empty?
          key = "#{name}|#{cat}"
          out[key] ||= {
            'name' => name,
            'th' => g.get_attribute('InteriorPro', 'thickness').to_f,
            'h' => g.get_attribute('InteriorPro', 'height').to_f,
            'cat' => cat,
            'src' => 'model',
            'count' => 0
          }
          out[key]['count'] += 1
        end
        out.values.sort_by { |t| -t['count'] }
      end

      # Last-placed door settings per category (used as the editor defaults).
      def model_door_defaults
        out = {}
        Sketchup.active_model.entities.to_a.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next unless e.valid? && e.get_attribute('InteriorPro', 'type') == 'door'
          cat = (e.get_attribute('InteriorPro', 'door_category') || 'interior').to_s
          out[cat] = {
            'type' => (e.get_attribute('InteriorPro', 'door_type') || '').to_s,
            'w' => e.get_attribute('InteriorPro', 'width_in').to_f,
            'h' => e.get_attribute('InteriorPro', 'height_in').to_f,
            'swing' => (e.get_attribute('InteriorPro', 'swing_direction') || 'left').to_s
          }
        end
        out
      end

      def model_window_defaults
        last = nil
        Sketchup.active_model.entities.to_a.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next unless e.valid? && e.get_attribute('InteriorPro', 'type') == 'window'
          last = {
            'type' => (e.get_attribute('InteriorPro', 'window_type') || '').to_s,
            'w' => e.get_attribute('InteriorPro', 'width_in').to_f,
            'h' => e.get_attribute('InteriorPro', 'height_in').to_f,
            'header' => e.get_attribute('InteriorPro', 'header_height_in').to_f
          }
        end
        last
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
            # Not in the library? Clone the settings of a wall of that type that
            # already exists in the model (the 3D is the default source of truth).
            if lib.nil?
              src = model.entities.grep(Sketchup::Group).find do |g|
                g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall' &&
                  g.get_attribute('InteriorPro', 'wall_type').to_s == r['lib'].to_s &&
                  (g.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s == cat
              end
              if src
                lib = {
                  'name' => r['lib'].to_s,
                  'exterior_material' => src.get_attribute('InteriorPro', 'exterior_material'),
                  'interior_color' => src.get_attribute('InteriorPro', 'interior_material'),
                  'side_a_color' => src.get_attribute('InteriorPro', 'side_a_color'),
                  'side_b_color' => src.get_attribute('InteriorPro', 'side_b_color')
                }
              end
            end
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

      # ---- editor -> model: wall length -----------------------------------

      # which = :end  -> the END point moves (start stays)
      # which = :start-> the START point moves (end stays)
      def stretch_wall!(wall, len_new, which = :end, keep_corners = true)
        unless wall && len_new > 6.0
          puts '[PlanEditor] stretch: bad wall/length'
          return false
        end
        model = Sketchup.active_model
        sx = wall.get_attribute('InteriorPro', 'start_x').to_f
        sy = wall.get_attribute('InteriorPro', 'start_y').to_f
        ex = wall.get_attribute('InteriorPro', 'end_x').to_f
        ey = wall.get_attribute('InteriorPro', 'end_y').to_f
        len_old = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
        if len_old < 1.0
          puts '[PlanEditor] stretch: wall too short'
          return false
        end
        delta = len_new - len_old
        if delta.abs < 0.05
          puts '[PlanEditor] stretch: no change'
          return false
        end

        if which == :end
          fixed = Geom::Point3d.new(sx, sy, 0)
          u = Geom::Vector3d.new((ex - sx) / len_old, (ey - sy) / len_old, 0)
        else
          fixed = Geom::Point3d.new(ex, ey, 0)
          u = Geom::Vector3d.new((sx - ex) / len_old, (sy - ey) / len_old, 0)
        end

        openings = InteriorPro::WallTool.read_door_openings(wall)
        shift = which == :start ? delta : 0.0
        bad = openings.any? do |o|
          t0 = o[:t].to_f + shift - o[:width].to_f / 2.0
          t1 = o[:t].to_f + shift + o[:width].to_f / 2.0
          t0 < 0.5 || t1 > len_new - 0.5
        end
        if bad
          UI.messagebox('New length would cut into a door/window opening.')
          return false
        end

        old_moving = Geom::Point3d.new(fixed.x + u.x * len_old, fixed.y + u.y * len_old, 0)
        # Partner walls whose endpoint sits on the moving corner. With
        # keep_corners they FOLLOW the corner (stay attached); otherwise they
        # are only re-squared/re-joined (the corner detaches).
        partners = []
        model.entities.grep(Sketchup::Group).each do |g|
          next if g == wall
          next unless g.get_attribute('InteriorPro', 'type') == 'wall'
          [%w[start_x start_y], %w[end_x end_y]].each do |kx, ky|
            px = g.get_attribute('InteriorPro', kx)
            py = g.get_attribute('InteriorPro', ky)
            next unless px && py
            ptol = (wall.get_attribute('InteriorPro', 'thickness').to_f +
                    g.get_attribute('InteriorPro', 'thickness').to_f) / 2.0 + 1.0
            next unless old_moving.distance(Geom::Point3d.new(px.to_f, py.to_f, 0)) < ptol
            partners << { wall: g, kx: kx, ky: ky }
            break
          end
        end

        model.start_operation('Set Wall Length', true)
        begin
          nx = fixed.x + u.x * len_new
          ny = fixed.y + u.y * len_new
          if which == :end
            wall.set_attribute('InteriorPro', 'end_x', nx)
            wall.set_attribute('InteriorPro', 'end_y', ny)
          else
            wall.set_attribute('InteriorPro', 'start_x', nx)
            wall.set_attribute('InteriorPro', 'start_y', ny)
            if openings.any?
              moved = openings.map { |o| o.merge(t: o[:t].to_f + delta) }
              InteriorPro::WallTool.persist_door_openings!(wall, moved)
              wid = wall.get_attribute('InteriorPro', 'id')
              model.entities.each do |g|
                next unless g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)
                next unless g.get_attribute('InteriorPro', 'host_wall_id') == wid
                t = g.get_attribute('InteriorPro', 'position_along_wall_in')
                g.set_attribute('InteriorPro', 'position_along_wall_in', t.to_f + delta) if t
              end
            end
          end

          if keep_corners
            partners.each do |p|
              p[:wall].set_attribute('InteriorPro', p[:kx], nx)
              p[:wall].set_attribute('InteriorPro', p[:ky], ny)
            end
          end

          wt = InteriorPro::WallTool.new
          group_list = [wall] + partners.map { |p| p[:wall] }
          group_list.each do |g|
            data = wt.wall_data(g)
            next unless data
            corners = wt.compute_perpendicular_corners_from_data(data)
            next unless corners
            wt.save_corners_attr(g, corners)
            wt.rebuild_wall_geometry(g, corners, data)
          end
          group_list.each { |g| wt.join_corners(g, model, allow_centerline_fallback: true) }
          model.commit_operation
        rescue StandardError => e
          begin; model.abort_operation; rescue StandardError; end
          puts "[PlanEditor] stretch failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          UI.messagebox("Wall length change failed: #{e.message}")
          return false
        end

        begin
          InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
        rescue StandardError
        end
        begin
          InteriorPro::RoomManager.sync_rooms! if defined?(InteriorPro::RoomManager)
        rescue StandardError
        end
        puts "[PlanEditor] wall length #{len_old.round(2)} -> #{len_new.round(2)} " \
             "(moving #{which}, #{partners.length} partner(s), corners #{keep_corners ? 'kept' : 'detached'})"
        true
      end

      # ---- editor -> model: move a wall sideways --------------------------
      # Ported from UIDialogs.wall_move (proven): corner partners follow within
      # the same category, endpoints touching the middle (T) get glued, then
      # rebuild + re-miter + hosted doors + molding/rooms refresh.
      # distance: positive = outward (right perpendicular of start->end).
      def move_wall_sideways!(wall, distance, keep_corners = true)
        unless wall
          puts '[PlanEditor] move: wall not found'
          return false
        end
        if distance.abs < 0.05
          puts '[PlanEditor] move: distance too small'
          return false
        end
        model = Sketchup.active_model
        sx = wall.get_attribute('InteriorPro', 'start_x').to_f
        sy = wall.get_attribute('InteriorPro', 'start_y').to_f
        ex = wall.get_attribute('InteriorPro', 'end_x').to_f
        ey = wall.get_attribute('InteriorPro', 'end_y').to_f
        dx = ex - sx
        dy = ey - sy
        len = Math.sqrt(dx**2 + dy**2)
        return false if len < 0.001
        nx = dx / len
        ny = dy / len
        ox = ny * distance          # right perpendicular
        oy = -nx * distance
        new_sx = sx + ox
        new_sy = sy + oy
        new_ex = ex + ox
        new_ey = ey + oy

        # Corner match tolerance: walls drawn with a different h_anchor have
        # DRAWN endpoints offset by up to half a thickness, so an exact 0.1"
        # match misses real corners (that is why corners detached).
        th_move = wall.get_attribute('InteriorPro', 'thickness').to_f
        moving_cat = (wall.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
        connections = []
        model.entities.grep(Sketchup::Group).each do |g|
          next unless keep_corners     # detached: nothing follows the wall
          next if g == wall
          next unless g.get_attribute('InteriorPro', 'type') == 'wall'
          osx = g.get_attribute('InteriorPro', 'start_x')
          osy = g.get_attribute('InteriorPro', 'start_y')
          oex = g.get_attribute('InteriorPro', 'end_x')
          oey = g.get_attribute('InteriorPro', 'end_y')
          next unless osx && osy && oex && oey
          osx = osx.to_f; osy = osy.to_f; oex = oex.to_f; oey = oey.to_f
          # "Keep joined" follows corner partners even ACROSS categories (an
          # interior wall meeting the exterior shell stays attached). The old
          # same-category-only rule is what made corners detach.
          same_cat = (g.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s == moving_cat
          tol = (th_move + g.get_attribute('InteriorPro', 'thickness').to_f) / 2.0 + 1.0
          if same_cat || keep_corners
            connections << { wall: g, which: :start, linked: :start } if Math.sqrt((osx - sx)**2 + (osy - sy)**2) < tol
            connections << { wall: g, which: :end,   linked: :start } if Math.sqrt((oex - sx)**2 + (oey - sy)**2) < tol
            connections << { wall: g, which: :start, linked: :end   } if Math.sqrt((osx - ex)**2 + (osy - ey)**2) < tol
            connections << { wall: g, which: :end,   linked: :end   } if Math.sqrt((oex - ex)**2 + (oey - ey)**2) < tol
          end
          g_dx = oex - osx
          g_dy = oey - osy
          g_len = Math.sqrt(g_dx**2 + g_dy**2)
          next unless g_len > 0.001 && ((g_dx * nx + g_dy * ny).abs / g_len) < 0.9
          perp_tol = wall.get_attribute('InteriorPro', 'thickness').to_f + 0.5
          tee = lambda do |px, py|
            t = (px - sx) * nx + (py - sy) * ny
            off = Math.sqrt((px - (sx + nx * t))**2 + (py - (sy + ny * t))**2)
            t >= 1.0 && t <= len - 1.0 && off <= perp_tol
          end
          already = connections.select { |c| c[:wall] == g }.map { |c| c[:which] }
          connections << { wall: g, which: :start, linked: :tee } if !already.include?(:start) && tee.call(osx, osy)
          connections << { wall: g, which: :end, linked: :tee } if !already.include?(:end) && tee.call(oex, oey)
        end
        by_wall = connections.group_by { |c| c[:wall] }

        too_short = by_wall.any? do |w, conns|
          wsx = w.get_attribute('InteriorPro', 'start_x').to_f
          wsy = w.get_attribute('InteriorPro', 'start_y').to_f
          wex = w.get_attribute('InteriorPro', 'end_x').to_f
          wey = w.get_attribute('InteriorPro', 'end_y').to_f
          conns.each do |c|
            if c[:linked] == :tee
              if c[:which] == :start then wsx += ox; wsy += oy else wex += ox; wey += oy end
            else
              tx = c[:linked] == :start ? new_sx : new_ex
              ty = c[:linked] == :start ? new_sy : new_ey
              if c[:which] == :start then wsx = tx; wsy = ty else wex = tx; wey = ty end
            end
          end
          Math.sqrt((wex - wsx)**2 + (wey - wsy)**2) < 1.0
        end
        if too_short
          UI.messagebox('Move would make a connected wall too short.')
          return false
        end

        model.start_operation('Move Wall', true)
        begin
          wall.set_attribute('InteriorPro', 'start_x', new_sx)
          wall.set_attribute('InteriorPro', 'start_y', new_sy)
          wall.set_attribute('InteriorPro', 'end_x', new_ex)
          wall.set_attribute('InteriorPro', 'end_y', new_ey)

          wt = InteriorPro::WallTool.new
          data = wt.wall_data(wall)
          if data
            corners = wt.perpendicular_corners_xy(Geom::Point3d.new(new_sx, new_sy, 0),
                                                  Geom::Point3d.new(new_ex, new_ey, 0),
                                                  data[:thickness], data[:h_anchor])
            if corners
              wt.save_corners_attr(wall, corners)
              wt.rebuild_wall_geometry(wall, corners, data)
            end
          end

          by_wall.each do |w, conns|
            conns.each do |c|
              if c[:linked] == :tee
                px = c[:which] == :start ? 'start_x' : 'end_x'
                py = c[:which] == :start ? 'start_y' : 'end_y'
                w.set_attribute('InteriorPro', px, w.get_attribute('InteriorPro', px).to_f + ox)
                w.set_attribute('InteriorPro', py, w.get_attribute('InteriorPro', py).to_f + oy)
              else
                tx = c[:linked] == :start ? new_sx : new_ex
                ty = c[:linked] == :start ? new_sy : new_ey
                if c[:which] == :start
                  w.set_attribute('InteriorPro', 'start_x', tx)
                  w.set_attribute('InteriorPro', 'start_y', ty)
                else
                  w.set_attribute('InteriorPro', 'end_x', tx)
                  w.set_attribute('InteriorPro', 'end_y', ty)
                end
              end
            end
            wd = wt.wall_data(w)
            next unless wd
            wc = wt.perpendicular_corners_xy(Geom::Point3d.new(wd[:drawn_start][0], wd[:drawn_start][1], 0),
                                             Geom::Point3d.new(wd[:drawn_end][0], wd[:drawn_end][1], 0),
                                             wd[:thickness], wd[:h_anchor])
            if wc
              wt.save_corners_attr(w, wc)
              wt.rebuild_wall_geometry(w, wc, wd)
            end
          end

          wt.join_corners(wall, model)
          by_wall.each_key { |w| wt.join_corners(w, model) }
          InteriorPro::DoorManager.move_hosted_doors!(wall, ox, oy)
          model.commit_operation
        rescue StandardError => e
          begin; model.abort_operation; rescue StandardError; end
          puts "[PlanEditor] move wall failed: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
          return false
        end

        begin
          InteriorPro::MoldingManager.refresh! if defined?(InteriorPro::MoldingManager)
        rescue StandardError
        end
        begin
          InteriorPro::RoomManager.sync_rooms! if defined?(InteriorPro::RoomManager)
        rescue StandardError
        end
        puts "[PlanEditor] wall moved #{distance.round(2)}\" " \
             "(#{by_wall.length} connected, corners #{keep_corners ? 'kept' : 'detached'})"
        true
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
            #top { height:36px; background:#2f3542; color:#fff; display:flex; align-items:center; padding:0 10px; gap:8px; overflow:hidden; }
            #top .title { font-weight:bold; margin-right:auto; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
            #top button { flex:0 0 auto; white-space:nowrap; }
            button { border:0; border-radius:4px; padding:5px 10px; cursor:pointer; font-size:12px; }
            .blue { background:#4b89ff; color:#fff; } .gray { background:#57606f; color:#fff; }
            .red { background:#e0392b; color:#fff; }
            #main { display:flex; height:calc(100% - 66px); min-width:0; }
            /* min-width:0 + overflow:hidden let the canvas shrink instead of
               pushing the side panel off-screen at small window sizes. */
            #canvasWrap { flex:1 1 auto; min-width:0; overflow:hidden; position:relative; background:#fbfcfe; }
            canvas { display:block; }
            #side { flex:0 0 200px; width:200px; box-sizing:border-box; background:#f4f6f9; border-left:1px solid #d6dae0; padding:10px; overflow-y:auto; }
            #side label { display:block; margin:8px 0 3px; color:#333; }
            #side input[type=text] { width:70px; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            #side select { width:100%; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            .seg { display:flex; gap:4px; }
            .seg button { background:#fff; border:1px solid #c3c9d1; color:#333; }
            .seg button.on { background:#dce9ff; border-color:#4b89ff; }
            #bottom { height:30px; background:#eceff3; border-top:1px solid #d6dae0; display:flex; align-items:center; padding:0 10px; gap:10px; overflow:hidden; }
            #vcb { background:#fffbe6; border:1px solid #e0b400; border-radius:3px; padding:3px 8px; min-width:70px; font-weight:bold; flex:0 0 auto; }
            #hint { color:#777; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
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
                <div id="selWallOpts" style="display:none">
                  <label>Length</label><input type="text" id="selLen">
                  <label>Which end moves</label>
                  <div class="seg"><button id="mvS" onclick="setMovingEnd('start')">Start ●</button><button id="mvE" class="on" onclick="setMovingEnd('end')">End ●</button></div>
                  <div style="color:#777; font-size:11px; margin-top:4px">אפשר גם ללחוץ על הפינה עצמה בקנבס — ירוק = הקצה שיזוז, אדום = נשאר</div>
                  <div style="margin-top:6px"><button class="blue" style="width:100%" onclick="applyWallLen()">Apply length</button></div>
                  <label style="margin-top:12px">Move sideways (in)</label>
                  <input type="text" id="selMove" value="6">
                  <div class="seg" style="margin-top:6px">
                    <button onclick="moveWall(1)">Out ▲</button><button onclick="moveWall(-1)">In ▼</button>
                  </div>
                  <div style="color:#777; font-size:11px; margin-top:4px">או פשוט לגרור את הקיר בקנבס</div>
                  <label style="margin-top:12px">Corners</label>
                  <div class="seg">
                    <button id="cnKeep" class="on" onclick="setKeepCorners(true)">Keep joined</button>
                    <button id="cnCut" onclick="setKeepCorners(false)">Detach ✂</button>
                  </div>
                  <div style="color:#777; font-size:11px; margin-top:4px">Detach = הקיר זז/מתארך לבד, בלי לגרור את הקירות בפינות</div>
                  <div style="margin-top:6px"><button class="gray" style="width:100%" onclick="diagWall()">Diag → Ruby Console</button></div>
                </div>
                <div id="selSizeOpts" style="display:none">
                  <label>Width (in)</label><input type="text" id="selW">
                  <label>Height (in)</label><input type="text" id="selH">
                  <div id="selHeaderRow"><label>Header (in)</label><input type="text" id="selHead"></div>
                  <div style="margin-top:6px"><button class="blue" style="width:100%" onclick="applySelSize()">Apply size</button></div>
                </div>
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
                  <span id="dbg" style="color:#b3261e; font-size:10.5px"></span>
            <span id="hint">Click to start a wall - move - type length + Enter, or click. Right-click / Esc ends the chain. Wheel = zoom, middle-drag = pan.</span>
          </div>
          <script>
            var cv = document.getElementById('cv'), ctx = cv.getContext('2d');
            var walls = [];          // existing model walls (read-only)
            var pending = [];        // walls drawn here, not yet applied
            var mode = 'sel';
            var sel = null;           // {type:'wall', w} | {type:'sym', w, s} | {type:'pending', i}
            var dragSym = null;       // {w, s, startT, curT, valid, moved}
            var dragWall = null;      // {w, b, from:{x,y}, off, moved} - sideways move
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
            var wallTypes = [];       // model wall types + user's wall library
            var curWallLib = '';      // selected wall type name ('' = custom)
            var modelDoors = {};      // per-category defaults from the model
            var modelWindow = null;

            function loadCatalogs(c) {
              if (!c) return;
              if (c.door_types) DOOR_TYPES = c.door_types;
              if (c.door_wh) DOOR_WH_CAT = c.door_wh;
              if (c.win_types && c.win_types.length) WIN_TYPES = c.win_types;
              if (c.win_wh) WIN_WH = c.win_wh;
              modelDoors = c.model_doors || {};
              modelWindow = c.model_windows || null;
              // Wall types IN THE MODEL come first and are the default.
              wallTypes = (c.model_walls || []).concat(c.wall_types || []);
              var sel2 = document.getElementById('wallType');
              sel2.innerHTML = '';
              var gm = null, gl = null;
              wallTypes.forEach(function(t){
                var o = document.createElement('option');
                o.value = t.name; o.textContent = t.name + ' — ' + t.th + '" (' + t.cat + ')';
                if (t.src === 'model') {
                  if (!gm) { gm = document.createElement('optgroup'); gm.label = 'In model (3D)'; sel2.appendChild(gm); }
                  gm.appendChild(o);
                } else {
                  if (!gl) { gl = document.createElement('optgroup'); gl.label = 'Library'; sel2.appendChild(gl); }
                  gl.appendChild(o);
                }
              });
              var oc = document.createElement('option');
              oc.value = ''; oc.textContent = 'Custom';
              sel2.appendChild(oc);
              // default = first model wall of the current category, else first entry
              var def = wallTypes.find(function(t){ return t.src === 'model' && t.cat === cat; }) ||
                        wallTypes.find(function(t){ return t.src === 'model'; });
              if (def) { sel2.value = def.name; wallTypeChanged(); } else { sel2.value = ''; curWallLib = ''; }
              fillSelect('dType', DOOR_TYPES[doorCat] || []);
              fillSelect('wType', WIN_TYPES);
              applyModelDoorDefaults();
              applyModelWindowDefaults();
            }

            // Door/window fields default to what was last placed in the model.
            function applyModelDoorDefaults() {
              var md = modelDoors[doorCat];
              if (!md || !md.type) { doorTypeChanged(); return; }
              var s = document.getElementById('dType');
              var has = Array.prototype.some.call(s.options, function(o){ return o.value === md.type; });
              if (has) s.value = md.type; else { doorTypeChanged(); return; }
              document.getElementById('dW').value = md.w || '';
              document.getElementById('dH').value = md.h || '';
              if (md.swing) setSwing(md.swing);
            }

            function applyModelWindowDefaults() {
              if (!modelWindow || !modelWindow.type) { winTypeChanged(); return; }
              var s = document.getElementById('wType');
              var has = Array.prototype.some.call(s.options, function(o){ return o.value === modelWindow.type; });
              if (has) s.value = modelWindow.type; else { winTypeChanged(); return; }
              document.getElementById('wW').value = modelWindow.w || '';
              document.getElementById('wH').value = modelWindow.h || '';
              document.getElementById('wHead').value = modelWindow.header || '';
            }

            function wallTypeChanged() {
              curWallLib = document.getElementById('wallType').value;
              var t = wallTypes.find(function(x){ return x.name === curWallLib; });
              if (!t) return;
              document.getElementById('th').value = t.th;
              if (t.h) document.getElementById('hh').value = t.h;
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
              applyModelDoorDefaults();
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
                  ? 'Click to select. Drag a wall sideways or an opening along the wall — while dragging you can TYPE an exact amount + Enter. Delete key removes.'
                  : 'Click on an applied wall to place. Green = fits, red = does not fit.');
              document.getElementById('hint').textContent = hint;
              updateSelPanel();
              draw();
            }

            function updateSelPanel() {
              var info = document.getElementById('selInfo');
              var dopts = document.getElementById('selDoorOpts');
              var sopts = document.getElementById('selSizeOpts');
              var wopts = document.getElementById('selWallOpts');
              if (!info) return;
              dopts.style.display = 'none';
              sopts.style.display = 'none';
              wopts.style.display = 'none';
              if (!sel) {
                info.textContent = 'לא נבחר כלום — לחץ על קיר או פתח';
                return;
              }
              if (sel.type === 'wall') {
                var b = bandQuad(sel.w);
                info.textContent = 'Wall: ' + fmtLen(b ? b.len : 0) + ' · ' + sel.w.th + '" · ' + sel.w.cat;
                wopts.style.display = '';
                document.getElementById('selLen').value = b ? fmtLen(b.len) : '';
              } else if (sel.type === 'pending') {
                var pw = pending[sel.i];
                var pb = pw ? bandQuad(pw) : null;
                info.innerHTML = 'Wall (not applied yet): ' + (pb ? fmtLen(pb.len) : '') +
                                 '<br><span style="color:#e0392b">עריכה כאן מקומית — ‏Apply to Model לבנייה</span>';
                wopts.style.display = '';
                document.getElementById('selLen').value = pb ? fmtLen(pb.len) : '';
              } else {
                info.textContent = (sel.s.body === 'window' ? 'Window' : 'Door') + ' · ' + fmtLen(sel.s.w);
                sopts.style.display = '';
                document.getElementById('selW').value = sel.s.w || '';
                document.getElementById('selH').value = sel.s.h || '';
                document.getElementById('selHeaderRow').style.display = sel.s.body === 'window' ? '' : 'none';
                document.getElementById('selHead').value = sel.s.header || '';
                if (sel.s.body === 'door') {
                  dopts.style.display = '';
                  document.getElementById('selSwL').className = sel.s.swing === 'left' ? 'on' : '';
                  document.getElementById('selSwR').className = sel.s.swing === 'right' ? 'on' : '';
                }
              }
            }

            // Which END of the wall moves when the length changes; the other
            // corner stays pinned. Set from the panel or by clicking the corner.
            var movingEnd = 'end';
            var keepCorners = true;   // false = corner partners do NOT follow
            function setKeepCorners(v) {
              keepCorners = v;
              document.getElementById('cnKeep').className = v ? 'on' : '';
              document.getElementById('cnCut').className = v ? '' : 'on';
              draw();
            }
            function setMovingEnd(e) {
              movingEnd = e;
              document.getElementById('mvS').className = e === 'start' ? 'on' : '';
              document.getElementById('mvE').className = e === 'end' ? 'on' : '';
              draw();
            }
            function fixedEndName() { return movingEnd === 'end' ? 'start' : 'end'; }
            function applyWallLen() {
              var v = parseLen(document.getElementById('selLen').value);
              if (!v || v <= 6 || !sel) return;
              if (sel.type === 'pending') { setPendingLength(sel.i, v); return; }
              if (sel.type !== 'wall' || !sel.w.id) return;
              keepSel = { kind:'wall', id: sel.w.id };
              sketchup.set_wall_length(JSON.stringify({ wall_id: sel.w.id, len: v, fixed: fixedEndName(), keep: keepCorners }));
            }

            // Apply the value typed during a drag: wall = sideways distance in
            // the drag direction; opening = distance moved along the wall.
            function applyTypedDrag() {
              var neg = typed.trim().charAt(0) === '-';
              var v = parseLen(typed.replace('-', ''));
              typed = ''; updateVcb();
              if (!v) return;
              if (dragWall) {
                var dir = (dragWall.off < 0 ? -1 : 1) * (neg ? -1 : 1);
                var off = dir * v;
                var w = dragWall.w;
                dragWall = null;
                if (sel && sel.type === 'pending') { movePendingWall(sel.i, off); return; }
                keepSel = { kind:'wall', id: w.id };
                sketchup.move_wall(JSON.stringify({ wall_id: w.id, dist: -off, keep: keepCorners }));
                draw();
                return;
              }
              if (dragSym) {
                var dir2 = (dragSym.curT - dragSym.startT < 0 ? -1 : 1) * (neg ? -1 : 1);
                var s = dragSym.s;
                dragSym = null;
                keepSel = { kind:'sym', id: s.id };
                sketchup.move_opening(JSON.stringify({ id: s.id, body: s.body, delta: dir2 * v }));
                draw();
              }
            }

            function diagWall() {
              if (!sel || sel.type !== 'wall') return;
              sketchup.debug_wall(JSON.stringify({ wall_id: sel.w.id }));
            }

            // --- pending (not yet applied) wall helpers -------------------
            // Endpoints of OTHER pending walls that sit on pt (corner partners).
            function pendingPartners(idx, pt) {
              var out = [];
              var tol = 1.0;
              pending.forEach(function(o, j){
                if (j === idx) return;
                tol = (pending[idx].th + o.th) / 2 + 1;
                if (Math.hypot(o.sx - pt.x, o.sy - pt.y) < tol) out.push({ w:o, k:'s' });
                if (Math.hypot(o.ex - pt.x, o.ey - pt.y) < tol) out.push({ w:o, k:'e' });
              });
              return out;
            }

            function movePendingWall(idx, off) {
              var pw = pending[idx], b = bandQuad(pw); if (!b) return;
              var s0 = { x:pw.sx, y:pw.sy }, e0 = { x:pw.ex, y:pw.ey };
              var ps = keepCorners ? pendingPartners(idx, s0) : [];
              var pe = keepCorners ? pendingPartners(idx, e0) : [];
              pw.sx += b.nx*off; pw.sy += b.ny*off;
              pw.ex += b.nx*off; pw.ey += b.ny*off;
              ps.forEach(function(p2){
                if (p2.k === 's') { p2.w.sx = pw.sx; p2.w.sy = pw.sy; } else { p2.w.ex = pw.sx; p2.w.ey = pw.sy; }
              });
              pe.forEach(function(p2){
                if (p2.k === 's') { p2.w.sx = pw.ex; p2.w.sy = pw.ey; } else { p2.w.ex = pw.ex; p2.w.ey = pw.ey; }
              });
              updateSelPanel(); draw();
            }

            function setPendingLength(idx, len) {
              var pw = pending[idx], b = bandQuad(pw); if (!b) return;
              var oldPt = movingEnd === 'end' ? { x:pw.ex, y:pw.ey } : { x:pw.sx, y:pw.sy };
              var partners = keepCorners ? pendingPartners(idx, oldPt) : [];
              if (movingEnd === 'end') { pw.ex = pw.sx + b.ux*len; pw.ey = pw.sy + b.uy*len; }
              else { pw.sx = pw.ex - b.ux*len; pw.sy = pw.ey - b.uy*len; }
              var np = movingEnd === 'end' ? { x:pw.ex, y:pw.ey } : { x:pw.sx, y:pw.sy };
              partners.forEach(function(p2){
                if (p2.k === 's') { p2.w.sx = np.x; p2.w.sy = np.y; } else { p2.w.ex = np.x; p2.w.ey = np.y; }
              });
              updateSelPanel(); draw();
            }

            // Out / In are relative to the BUILDING (away from / toward the
            // centroid of all walls) — not to the wall's drawing direction, so
            // the buttons always feel right no matter how the wall was drawn.
            function outwardSign(w, b) {
              var all = walls.concat(pending);
              var cx = 0, cy = 0, n = 0;
              all.forEach(function(o){ cx += o.sx + o.ex; cy += o.sy + o.ey; n += 2; });
              if (!n) return 1;
              cx /= n; cy /= n;
              var mid = { x:(w.sx + w.ex)/2, y:(w.sy + w.ey)/2 };
              var probe = { x: mid.x + b.nx*10, y: mid.y + b.ny*10 };
              return Math.hypot(probe.x - cx, probe.y - cy) > Math.hypot(mid.x - cx, mid.y - cy) ? 1 : -1;
            }

            function moveWall(sign) {
              var v = parseLen(document.getElementById('selMove').value);
              if (!v || !sel) return;
              if (sel.type === 'pending') {
                var pw = pending[sel.i], pb = bandQuad(pw); if (!pb) return;
                movePendingWall(sel.i, sign * v * outwardSign(pw, pb));
                return;
              }
              if (sel.type !== 'wall') return;
              var b = bandQuad(sel.w); if (!b) return;
              var offN = sign * v * outwardSign(sel.w, b);   // in +n units
              keepSel = { kind:'wall', id: sel.w.id };
              // Ruby's positive distance = RIGHT perpendicular = -n
              sketchup.move_wall(JSON.stringify({ wall_id: sel.w.id, dist: -offN, keep: keepCorners }));
            }

            function applySelSize() {
              if (!sel || sel.type !== 'sym') return;
              sketchup.edit_opening_size(JSON.stringify({
                id: sel.s.id,
                body: sel.s.body,
                width: parseLen(document.getElementById('selW').value) || 0,
                height: parseLen(document.getElementById('selH').value) || 0,
                header: parseLen(document.getElementById('selHead').value) || 0
              }));
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
              cv.width = Math.max(80, w.clientWidth);
              cv.height = Math.max(80, w.clientHeight);
              draw();
            }
            window.onresize = resize;
            // Some SketchUp/CEF builds fire no resize event on dialog resize —
            // observe the wrapper too so the canvas always matches its box.
            try {
              new ResizeObserver(resize).observe(document.getElementById('canvasWrap'));
            } catch (e) {}

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

            // Accepts: 42 | 42" | 3' | 3' 6 | 3'6" | 3 6 (feet space inches)
            function parseLen(s) {
              s = String(s).trim(); if (!s) return null;
              var m = s.match(/^(\\d+(?:\\.\\d+)?)'\\s*(\\d+(?:\\.\\d+)?)?\\"?$/);
              if (m) return parseFloat(m[1]) * 12 + (m[2] ? parseFloat(m[2]) : 0);
              m = s.match(/^(\\d+(?:\\.\\d+)?)\\s+(\\d+(?:\\.\\d+)?)$/);
              if (m) return parseFloat(m[1]) * 12 + parseFloat(m[2]);
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
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  var sf1 = x1 + JAMB, sf2 = x2 - JAMB, xm2 = (sf1 + sf2) / 2;
                  symRect(w, b, sf1+0.5, xm2+1.5, cmid+0.3, cmid+1.5);
                  symRect(w, b, xm2-1.5, sf2-0.5, cmid-1.5, cmid-0.3);
                } else if (s.kind === 'garage') {
                  ctx.lineWidth = 2.5;
                  polyline([wpt(w,b,x1,b.q+0.7), wpt(w,b,x2,b.q+0.7)]);
                  ctx.lineWidth = 1;
                  symDashed(w, b, x1, x2, b.p + 3);
                } else if (s.kind === 'folding') {
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  var ff1 = x1 + JAMB, ff2 = x2 - JAMB;
                  var ss2 = s.clicked >= 0 ? -1 : 1;
                  var edge2 = ss2 > 0 ? b.p : b.q;
                  var nPan = 4;
                  var amp = (ff2 - ff1) / nPan;
                  var vs = [];
                  for (var i = 0; i <= nPan; i++) {
                    vs.push(wpt(w, b, ff1 + (ff2 - ff1) * i / nPan,
                                (i % 2 === 1) ? edge2 + ss2*amp : edge2));
                  }
                  for (var iL = 0; iL < nPan; iL++) {   // each leaf = thin rectangle
                    var A = vs[iL], B = vs[iL+1];
                    var lx2 = B.x - A.x, ly2 = B.y - A.y;
                    var ll = Math.hypot(lx2, ly2); if (ll < 1) continue;
                    var px2 = -ly2/ll*1.5, py2 = lx2/ll*1.5;
                    polyline([A, B, {x:B.x+px2, y:B.y+py2}, {x:A.x+px2, y:A.y+py2}, A]);
                  }
                } else if (s.kind === 'pocket') {
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  var pf1 = x1 + JAMB, pf2 = x2 - JAMB, xm3 = (pf1 + pf2) / 2;
                  symRect(w, b, pf1, xm3, cmid-0.6, cmid+0.6);
                  symDashed(w, b, xm3, pf2, cmid);
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
              dimTags = [];
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
              if (dragWall && dragWall.moved) {   // live ghost of the sideways move
                var g = { sx:dragWall.w.sx + dragWall.b.nx*dragWall.off,
                          sy:dragWall.w.sy + dragWall.b.ny*dragWall.off,
                          ex:dragWall.w.ex + dragWall.b.nx*dragWall.off,
                          ey:dragWall.w.ey + dragWall.b.ny*dragWall.off,
                          th:dragWall.w.th, ha:dragWall.w.ha, cat:dragWall.w.cat, ops:dragWall.w.ops };
                drawWallBand(g, '#2f6bd8', '#9db8e8', 0.6, null);
                outlineBand(g, '#1a9d55');
                var mp = { x:(g.sx + g.ex)/2, y:(g.sy + g.ey)/2 };
                dimTag(sx(mp.x), sy(mp.y), typed ? typed : fmtLen(Math.abs(dragWall.off)), 'size', {});
                return;
              }
              if (dragSym && dragSym.moved) {
                outlineOpening(dragSym.w, dragSym.s, dragSym.curT, dragSym.valid ? '#1a9d55' : '#e0392b');
                return;
              }
              if (!sel) return;
              if (sel.type === 'wall') { outlineBand(sel.w, '#4b89ff'); drawWallDims(sel.w); }
              else if (sel.type === 'pending') {
                var w = pending[sel.i];
                if (w) { outlineBand(w, '#4b89ff'); drawWallDims(w, sel.i); }
              }
              else { outlineOpening(sel.w, sel.s, sel.s.t, '#4b89ff'); drawOpeningDims(sel.w, sel.s); }
            }

            // ---- clickable dimension tags -------------------------------------
            // dimTags collects screen-space boxes; a click on one opens an inline
            // edit that repositions/resizes the opening (or the wall length).
            var dimTags = [];

            function dimTag(px, py, text, kind, data) {
              ctx.font = 'bold 11px Arial';
              var tw = ctx.measureText(text).width + 8;
              var th2 = 15;
              ctx.fillStyle = '#fff';
              ctx.strokeStyle = kind === 'size' ? '#e0392b' : '#1a6ee0';
              ctx.lineWidth = 1;
              ctx.beginPath(); ctx.rect(px - tw/2, py - th2/2, tw, th2); ctx.fill(); ctx.stroke();
              ctx.fillStyle = kind === 'size' ? '#e0392b' : '#1a6ee0';
              ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
              ctx.fillText(text, px, py);
              ctx.textBaseline = 'alphabetic';
              dimTags.push({ x:px - tw/2, y:py - th2/2, w:tw, h:th2, kind:kind, data:data });
            }

            function dimLine(w, b, x1, x2, off) {
              polyline([wpt(w,b,x1,off), wpt(w,b,x2,off)]);
              [x1, x2].forEach(function(x){
                polyline([wpt(w,b,x,off - 2), wpt(w,b,x,off + 2)]);
              });
            }

            function drawOpeningDims(w, s) {
              var b = bandQuad(w); if (!b) return;
              var hw = s.w/2, a = s.t - hw, c = s.t + hw;
              // neighbours on the same wall
              var prev = 0, next = b.len;
              (w.syms || []).forEach(function(o){
                if (o.id === s.id) return;
                var oa = o.t - o.w/2, oc = o.t + o.w/2;
                if (oc <= a && oc > prev) prev = oc;
                if (oa >= c && oa < next) next = oa;
              });
              var off = b.p + 10;
              ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 0.9;
              dimLine(w, b, prev, a, off);
              dimLine(w, b, a, c, off);
              dimLine(w, b, c, next, off);
              var p1 = wpt(w, b, (prev + a)/2, off + 6);
              var p2 = wpt(w, b, (a + c)/2, off + 6);
              var p3 = wpt(w, b, (c + next)/2, off + 6);
              if (a - prev > 2) dimTag(sx(p1.x), sy(p1.y), fmtLen(a - prev), 'pos',
                                      { id:s.id, body:s.body, base:prev, hw:hw, wall:w });
              dimTag(sx(p2.x), sy(p2.y), fmtLen(s.w), 'size', { id:s.id, body:s.body, h:s.h });
              if (next - c > 2) dimTag(sx(p3.x), sy(p3.y), fmtLen(next - c), 'posEnd',
                                       { id:s.id, body:s.body, base:next, hw:hw, wall:w });
            }

            function drawWallDims(w, pi) {
              var b = bandQuad(w); if (!b) return;
              var off = b.q - 10;
              ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 0.9;
              dimLine(w, b, 0, b.len, off);
              var p = wpt(w, b, b.len/2, off - 6);
              dimTag(sx(p.x), sy(p.y), fmtLen(b.len), 'wallLen',
                     { wall_id:w.id, len:b.len, pi:(pi == null ? null : pi) });
              // green = the end that will move, red = pinned corner
              var mv  = movingEnd === 'end' ? {x:w.ex, y:w.ey} : {x:w.sx, y:w.sy};
              var pin = movingEnd === 'end' ? {x:w.sx, y:w.sy} : {x:w.ex, y:w.ey};
              ctx.fillStyle = '#e0392b';
              ctx.beginPath(); ctx.arc(sx(pin.x), sy(pin.y), 5, 0, Math.PI*2); ctx.fill();
              ctx.fillStyle = '#1a9d55';
              ctx.beginPath(); ctx.arc(sx(mv.x), sy(mv.y), 7, 0, Math.PI*2); ctx.fill();
              // direction arrow out of the moving end
              var dirS = movingEnd === 'end' ? 1 : -1;
              var ax = sx(mv.x) + b.ux*dirS*26, ay = sy(mv.y) - b.uy*dirS*26;
              ctx.strokeStyle = '#1a9d55'; ctx.lineWidth = 2;
              ctx.beginPath(); ctx.moveTo(sx(mv.x), sy(mv.y)); ctx.lineTo(ax, ay); ctx.stroke();
              var ang2 = Math.atan2(ay - sy(mv.y), ax - sx(mv.x));
              ctx.beginPath();
              ctx.moveTo(ax, ay);
              ctx.lineTo(ax - 8*Math.cos(ang2 - 0.4), ay - 8*Math.sin(ang2 - 0.4));
              ctx.moveTo(ax, ay);
              ctx.lineTo(ax - 8*Math.cos(ang2 + 0.4), ay - 8*Math.sin(ang2 + 0.4));
              ctx.stroke();
            }

            // Click near a selected wall's corner to make THAT end the moving one.
            function hitWallEnd(px, py) {
              if (!sel || sel.type !== 'wall') return null;
              var w = sel.w;
              var ds = Math.hypot(sx(w.sx) - px, sy(w.sy) - py);
              var de = Math.hypot(sx(w.ex) - px, sy(w.ey) - py);
              if (ds < 12 && ds <= de) return 'start';
              if (de < 12) return 'end';
              return null;
            }

            function hitDimTag(px, py) {
              for (var i = dimTags.length - 1; i >= 0; i--) {
                var t = dimTags[i];
                if (px >= t.x && px <= t.x + t.w && py >= t.y && py <= t.y + t.h) return t;
              }
              return null;
            }

            function editDimTag(t) {
              var cur = '';
              if (t.kind === 'wallLen') cur = fmtLen(t.data.len);
              else if (t.kind === 'size') cur = fmtLen(sel.s.w);
              else cur = '';
              // NOTE: never use backslash escapes inside this heredoc-embedded JS
              // (a single \\' would break the whole script).
              var v = prompt('הקלד מידה חדשה — feet inch, למשל: 3 6', cur);
              if (v === null) return;
              var val = parseLen(v);
              if (!val || val <= 0) return;
              if (t.kind === 'wallLen') {
                if (t.data.pi != null) { setPendingLength(t.data.pi, val); return; }
                if (!t.data.wall_id) { alert('הקיר עוד לא עבר Apply to Model'); return; }
                keepSel = { kind:'wall', id: t.data.wall_id };
                sketchup.set_wall_length(JSON.stringify({ wall_id: t.data.wall_id, len: val, fixed: fixedEndName(), keep: keepCorners }));
              } else if (t.kind === 'size') {
                sketchup.edit_opening_size(JSON.stringify({
                  id: t.data.id, body: t.data.body, width: val, height: 0, header: 0
                }));
              } else if (t.kind === 'pos') {
                sketchup.set_opening_t(JSON.stringify({
                  id: t.data.id, body: t.data.body, t: t.data.base + val + t.data.hw
                }));
              } else if (t.kind === 'posEnd') {
                sketchup.set_opening_t(JSON.stringify({
                  id: t.data.id, body: t.data.body, t: t.data.base - val - t.data.hw
                }));
              }
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
              evCount.md++; updateDbg();
              if (ev.button === 1) { panning = true; panFrom = {x:ev.offsetX, y:ev.offsetY}; ev.preventDefault(); return; }
              if (ev.button === 2) { endChain(); return; }
              if (ev.button !== 0) return;
              var p = {x:mx(ev.offsetX), y:my(ev.offsetY)};
              if (mode === 'sel') {
                var he = hitWallEnd(ev.offsetX, ev.offsetY);  // click a corner = choose moving end
                if (he) { setMovingEnd(he); return; }
                var dt = hitDimTag(ev.offsetX, ev.offsetY);   // click a dimension = edit it
                if (dt) { editDimTag(dt); return; }
                var ho = hitOpening(p);
                if (ho) {
                  sel = { type:'sym', w:ho.w, s:ho.s };
                  dragSym = { w:ho.w, s:ho.s, b:ho.b, startT:ho.s.t, curT:ho.s.t,
                              sxy:{x:ev.offsetX, y:ev.offsetY}, valid:true, moved:false };
                } else {
                  var hw = hitWall(p);
                  if (hw) {
                    sel = { type:'wall', w:hw.w };
                    dragWall = { w:hw.w, b:hw.b, from:{x:p.x, y:p.y},
                                 sxy:{x:ev.offsetX, y:ev.offsetY}, off:0, moved:false };
                  } else {
                      var pi = hitPending(p);
                    sel = pi >= 0 ? { type:'pending', i:pi } : null;
                    if (pi >= 0) {   // pending (blue) walls drag too
                      var pw0 = pending[pi];
                      dragWall = { w:pw0, b:bandQuad(pw0), pi:pi, from:{x:p.x, y:p.y},
                                   sxy:{x:ev.offsetX, y:ev.offsetY}, off:0, moved:false };
                    }
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
            // One movement handler in CANVAS pixel coords, driven by both the
            // canvas and the window (so a drag survives the cursor leaving the
            // canvas — that was why dragging felt dead).
            var evCount = { md:0, mm:0, mu:0 };
            function updateDbg() {
              var d = document.getElementById('dbg');
              if (d) d.textContent = 'md:' + evCount.md + ' mm:' + evCount.mm + ' mu:' + evCount.mu +
                                     (dragWall ? ' DRAG-WALL ' + dragWall.off.toFixed(2) + '"' : '') +
                                     (dragSym ? ' DRAG-OPENING' : '');
            }

            function handleMove(px, py) {
              evCount.mm++; updateDbg();
              if (panning) {
                panX += px - panFrom.x; panY -= py - panFrom.y;
                panFrom = {x:px, y:py}; draw(); return;
              }
              cursor = {x:mx(px), y:my(py)};
              if (mode === 'sel' && dragWall) {
                var sd = Math.hypot(px - dragWall.sxy.x, py - dragWall.sxy.y);
                if (sd < 4 && !dragWall.moved) return;   // plain click still selects
                dragWall.moved = true;
                var b3 = dragWall.b;
                var o = (cursor.x - dragWall.from.x)*b3.nx + (cursor.y - dragWall.from.y)*b3.ny;
                dragWall.off = Math.round(o * 4) / 4;   // 1/4" steps
                draw();
                return;
              }
              if (mode === 'sel' && dragSym) {
                var sd2 = Math.hypot(px - dragSym.sxy.x, py - dragSym.sxy.y);
                if (sd2 < 4 && !dragSym.moved) return;
                dragSym.moved = true;
                var w = dragSym.w, b = dragSym.b;
                var tt = (cursor.x - w.sx)*b.ux + (cursor.y - w.sy)*b.uy;
                var hw2 = dragSym.s.w / 2;
                tt = Math.max(hw2, Math.min(b.len - hw2, tt));
                dragSym.curT = tt;
                dragSym.valid = true;
                draw();
                return;
              }
              if (mode === 'door' || mode === 'win') { hoverHit = hitWall(cursor); draw(); return; }
              if (drawing) draw();
            }

            cv.addEventListener('mousemove', function(ev) {
              handleMove(ev.offsetX, ev.offsetY);
            });
            // Pointer events + capture: some SketchUp/CEF builds stop sending
            // mousemove once a button is held, which killed dragging.
            cv.addEventListener('pointerdown', function(ev) {
              try { cv.setPointerCapture(ev.pointerId); } catch (e) {}
            });
            cv.addEventListener('pointermove', function(ev) {
              if (!dragWall && !dragSym && !panning) return;
              var r = cv.getBoundingClientRect();
              handleMove(ev.clientX - r.left, ev.clientY - r.top);
            });
            cv.addEventListener('pointerup', function(ev) {
              try { cv.releasePointerCapture(ev.pointerId); } catch (e) {}
              finishDrag();
            });
            window.addEventListener('mousemove', function(ev) {
              if (!dragWall && !dragSym && !panning) return;
              var r = cv.getBoundingClientRect();
              handleMove(ev.clientX - r.left, ev.clientY - r.top);
            });
            window.addEventListener('mouseup', function() { finishDrag(); });

            function finishDrag() {
              evCount.mu++; updateDbg();
              panning = false;
              if (mode === 'sel' && dragWall) {
                if (dragWall.moved && Math.abs(dragWall.off) >= 0.25) {
                  if (dragWall.pi != null) {          // not applied yet -> local move
                    movePendingWall(dragWall.pi, dragWall.off);
                  } else {
                    // our n is the LEFT perpendicular; Ruby expects RIGHT (outward)
                    keepSel = { kind:'wall', id: dragWall.w.id };
                    sketchup.move_wall(JSON.stringify({ wall_id: dragWall.w.id, dist: -dragWall.off, keep: keepCorners }));
                  }
                }
                dragWall = null;
                draw();
                return;
              }
              if (mode === 'sel' && dragSym) {
                var delta = dragSym.curT - dragSym.startT;
                if (dragSym.moved && Math.abs(delta) > 0.25) {
                  keepSel = { kind:'sym', id: dragSym.s.id };
                  sketchup.move_opening(JSON.stringify({ id: dragSym.s.id, body: dragSym.s.body, delta: delta }));
                }
                dragSym = null;
                draw();
              }
            }
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
              // While dragging a wall / opening you can TYPE the exact amount
              // (SketchUp-style): digits go to the VCB, Enter applies.
              if (mode === 'sel' && (dragWall || dragSym)) {
                if (ev.key === 'Enter') { applyTypedDrag(); ev.preventDefault(); return; }
                if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); ev.preventDefault(); return; }
                if (/^[0-9.'" -]$/.test(ev.key)) { typed += ev.key; updateVcb(); ev.preventDefault(); return; }
              }
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
              if (keep) return;
              // Switching Ext/Int picks that category's wall type FROM THE MODEL.
              var m = wallTypes.find(function(t){ return t.src === 'model' && t.cat === c; }) ||
                      wallTypes.find(function(t){ return t.cat === c; });
              if (m) {
                document.getElementById('wallType').value = m.name;
                curWallLib = m.name;
                document.getElementById('th').value = m.th;
                if (m.h) document.getElementById('hh').value = m.h;
              } else {
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
            // Selection to restore after a model round-trip (edit/move/resize),
            // so the panel stays open on the same wall/opening.
            var keepSel = null;

            function loadWalls(list) {
              walls = list || [];
              hoverHit = null; dragSym = null; dragWall = null;
              var want = keepSel || (sel && sel.type === 'wall' ? { kind:'wall', id: sel.w.id } :
                        (sel && sel.type === 'sym' ? { kind:'sym', id: sel.s.id } : null));
              keepSel = null;
              sel = null;
              if (want) {
                for (var i6 = 0; i6 < walls.length && !sel; i6++) {
                  var w6 = walls[i6];
                  if (want.kind === 'wall' && w6.id === want.id) { sel = { type:'wall', w:w6 }; break; }
                  if (want.kind === 'sym') {
                    (w6.syms || []).forEach(function(s6){
                      if (!sel && s6.id === want.id) sel = { type:'sym', w:w6, s:s6 };
                    });
                  }
                }
              }
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

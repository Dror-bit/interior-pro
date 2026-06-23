# Interior Pro - Door Dialog
# Single form: pick type, set parameters, click Place.
# No preset save/load. Only door TYPE names are persisted.

module InteriorPro
  module DoorLibraryDialog

    DOOR_DIALOG_WIDTH = 400
    DOOR_DIALOG_MIN_HEIGHT = 900

    @session_by_category = {}
    @place_dialog = nil

    def self.session_settings(category = nil)
      cat = InteriorPro::DoorLibrary.normalize_category(
        category || (@session_last && @session_last['door_category']) || 'exterior'
      )
      saved = @session_by_category[cat]
      door_type = saved ? (saved['door_type'] || saved[:door_type]) : nil
      s = InteriorPro::DoorLibrary.defaults_for_type(cat, door_type)
      if saved
        merged = saved.transform_keys(&:to_s)
        s = s.merge(merged)
        s['door_type'] = merged['door_type'] || s['door_type']
      end
      apply_type_catalog_defaults!(s, cat)
      s
    end

    def self.apply_type_catalog_defaults!(settings, category)
      cat = InteriorPro::DoorLibrary.normalize_category(category)
      type = settings['door_type'].to_s
      overrides = InteriorPro::DoorLibrary.type_setting_overrides(cat, type)
      settings.merge!(overrides) if overrides.any?

      if type =~ /\A(\d+)-Panel/
        n = $1.to_i
        settings['width'] = InteriorPro::DoorLibrary.width_for_panel_count(n)
        settings['glass_frame_width'] = 2.5
        settings['glass_grid_style'] = 'none'
      elsif type == 'Sliding'
        settings['glass_frame_width'] = 2.0
        settings['glass_grid_style'] = 'none'
      elsif type == 'French Hinged'
        settings['width'] = 60.0
        settings['glass_frame_width'] = 5.0
        settings['glass_grid_style'] = '2x2'
      end
    end

    def self.type_defaults_payload(door_type, category)
      s = {
        'door_type' => door_type.to_s,
        'door_category' => InteriorPro::DoorLibrary.normalize_category(category)
      }
      apply_type_catalog_defaults!(s, s['door_category'])
      s
    end

    def self.session_last
      @session_last
    end

    def self.remember_session!(door)
      door = door.transform_keys(&:to_s)
      cat = InteriorPro::DoorLibrary.normalize_category(door['door_category'])
      @session_by_category[cat] = door
      @session_last = door
    end

    def self.apply_to_tool(tool, settings)
      tool.door_category       = InteriorPro::DoorLibrary.normalize_category(settings['door_category'])
      tool.door_type           = settings['door_type']
      tool.width              = settings['width'].to_f
      tool.height             = settings['height'].to_f
      tool.frame_width        = settings['frame_width'].to_f
      tool.glass_frame_width  = settings['glass_frame_width'].to_f
      tool.interior_depth     = settings['interior_depth'].to_f
      tool.floor_offset       = settings['floor_offset'].to_f
      tool.swing_direction    = settings['swing_direction']
      tool.swing_side         = settings['swing_side']
      tool.slide_direction    = settings['slide_direction']
      tool.glass_grid_style        = normalize_grid_style(settings)
      tool.exterior_casing_style   = InteriorPro::DoorLibrary.normalize_casing_style(settings, 'exterior')
      tool.interior_casing_style   = InteriorPro::DoorLibrary.normalize_casing_style(settings, 'interior')
      tool.exterior_threshold = if settings.key?('exterior_threshold')
        !!settings['exterior_threshold']
      else
        InteriorPro::DoorLibrary.normalize_category(settings['door_category']) != 'interior'
      end
      tool.preset_name        = settings['door_type']
    end

    def self.normalize_grid_style(settings)
      if settings['glass_grid_style']
        settings['glass_grid_style'].to_s
      elsif settings.key?('glass_grid')
        settings['glass_grid'] ? '2x2' : 'none'
      else
        '2x2'
      end
    end

    def self.show(tool)
      model = Sketchup.active_model
      if model.tools.active_tool != tool
        model.select_tool(tool)
      end
      tool.placement_ready = false if tool.respond_to?(:placement_ready=)
      cat = InteriorPro::DoorLibrary.normalize_category(
        (@session_last && @session_last['door_category']) || 'exterior'
      )
      settings = session_settings(cat)
      apply_to_tool(tool, settings)

      types = InteriorPro::DoorLibrary.all_types(cat)

      if @place_dialog
        begin
          @place_dialog.close
        rescue StandardError
          nil
        end
        @place_dialog = nil
      end

      dialog = build_door_html_dialog(
        dialog_title: 'Interior Pro - Door',
        preferences_key: 'InteriorPro_Door_v2'
      )
      @place_dialog = dialog

      wire_place_dialog_callbacks(dialog, tool)
      dialog.set_on_closed {
        @place_dialog = nil
        if tool.respond_to?(:stop_preview_pump!)
          tool.stop_preview_pump!
        end
      }
      dialog.set_html(build_html(
        edit_mode: false,
        initial_category: cat,
        initial_settings: settings,
        initial_types: types
      ))
      dialog.show
    end

    def self.show_for_edit(door)
      settings = InteriorPro::DoorManager.settings_from_door(door)
      cat = InteriorPro::DoorLibrary.normalize_category(settings['door_category'])

      types = InteriorPro::DoorLibrary.all_types(cat)

      dialog = build_door_html_dialog(
        dialog_title: 'Interior Pro - Edit Door',
        preferences_key: 'InteriorPro_DoorEdit_v2'
      )

      wire_edit_dialog_callbacks(dialog, door)
      dialog.set_html(build_html(
        edit_mode: true,
        initial_category: cat,
        initial_settings: settings,
        initial_types: types
      ))
      dialog.show
    end

    def self.build_door_html_dialog(dialog_title:, preferences_key:)
      dialog = UI::HtmlDialog.new(
        dialog_title: dialog_title,
        preferences_key: preferences_key,
        width: DOOR_DIALOG_WIDTH,
        height: DOOR_DIALOG_MIN_HEIGHT,
        min_width: DOOR_DIALOG_WIDTH,
        min_height: DOOR_DIALOG_MIN_HEIGHT,
        resizable: true,
        scrollable: false
      )

      dialog.add_action_callback('resize_to_fit') { |_, content_height|
        chrome = 40
        h = content_height.to_i + chrome
        h = DOOR_DIALOG_MIN_HEIGHT if h < DOOR_DIALOG_MIN_HEIGHT
        h = 1200 if h > 1200
        dialog.set_size(DOOR_DIALOG_WIDTH, h)
      }

      dialog.set_size(DOOR_DIALOG_WIDTH, DOOR_DIALOG_MIN_HEIGHT)
      dialog
    end

    def self.load_category_into_dialog(dialog, category, edit_mode: false)
      cat = InteriorPro::DoorLibrary.normalize_category(category)
      s = session_settings(cat)
      types = InteriorPro::DoorLibrary.all_types(cat)
      tail = edit_mode ? 'syncCategoryFields()' : 'syncCategoryFields(); applyTypeDefaults()'
      dialog.execute_script(
        "document.getElementById('doorCategory').value = #{cat.to_json}; " \
        "loadTypes(#{types.to_json}, #{s['door_type'].to_json}); " \
        "loadForm(#{s.to_json}); #{tail}"
      )
    end

    # Return OS focus to the SketchUp model view (HtmlDialog steals it on Windows).
    def self.yield_focus_to_sketchup
      return unless Sketchup.respond_to?(:focus)

      begin
        Sketchup.focus
      rescue StandardError
        nil
      end
    end

    # Arm the active DoorTool for ghost preview + placement (dialog stays open).
    def self.arm_placement_tool!(tool, door_settings)
      remember_session!(door_settings)
      apply_to_tool(tool, door_settings)
      model = Sketchup.active_model
      if model.tools.active_tool != tool
        model.select_tool(tool)
      end
      tool.mark_placement_ready! if tool.respond_to?(:mark_placement_ready!)
      tool.reset_preview! if tool.respond_to?(:reset_preview!)
      tool.start_preview_pump! if tool.respond_to?(:start_preview_pump!)
      UI.start_timer(0, false) {
        yield_focus_to_sketchup
        model.active_view.invalidate
      }
    end

    def self.wire_place_dialog_callbacks(dialog, tool)
      dialog.add_action_callback('get_types') { |_|
        cat = InteriorPro::DoorLibrary.normalize_category(
          (@session_last && @session_last['door_category']) || 'exterior'
        )
        load_category_into_dialog(dialog, cat, edit_mode: false)
      }

      dialog.add_action_callback('load_category') { |_, category|
        load_category_into_dialog(dialog, category, edit_mode: false)
      }

      dialog.add_action_callback('type_changed') { |_, type, category|
        payload = type_defaults_payload(type, category)
        dialog.execute_script("applyRubyTypeDefaults(#{payload.to_json})")
      }

      dialog.add_action_callback('add_custom_type') { |_, name, category|
        cat = InteriorPro::DoorLibrary.normalize_category(category)
        types = InteriorPro::DoorLibrary.add_custom(name.to_s, cat)
        dialog.execute_script("loadTypes(#{types.to_json}, #{name.to_json})")
      }

      dialog.add_action_callback('return_focus_to_model') { |_|
        yield_focus_to_sketchup
      }

      dialog.add_action_callback('place_door') { |_, data|
        arm_placement_tool!(tool, JSON.parse(data.to_s))
      }
    end

    def self.wire_edit_dialog_callbacks(dialog, door)
      settings = InteriorPro::DoorManager.settings_from_door(door)
      cat = InteriorPro::DoorLibrary.normalize_category(settings['door_category'])

      dialog.add_action_callback('get_types') { |_|
        types = InteriorPro::DoorLibrary.all_types(cat)
        dialog.execute_script(
          "document.getElementById('doorCategory').value = #{cat.to_json}; " \
          "loadTypes(#{types.to_json}, #{settings['door_type'].to_json}); " \
          "loadForm(#{settings.to_json}); syncCategoryFields()"
        )
      }

      dialog.add_action_callback('load_category') { |_, category|
        load_category_into_dialog(dialog, category, edit_mode: true)
      }

      dialog.add_action_callback('add_custom_type') { |_, name, category|
        c = InteriorPro::DoorLibrary.normalize_category(category)
        types = InteriorPro::DoorLibrary.add_custom(name.to_s, c)
        dialog.execute_script("loadTypes(#{types.to_json}, #{name.to_json})")
      }

      dialog.add_action_callback('apply_edit') { |_, data|
        door_settings = JSON.parse(data)
        if InteriorPro::DoorManager.update_door(door, door_settings)
          remember_session!(door_settings)
          dialog.close
        end
      }
    end

    def self.build_html(edit_mode: false, initial_category: 'exterior', initial_settings: nil, initial_types: nil)
      cat = InteriorPro::DoorLibrary.normalize_category(initial_category)
      settings = (initial_settings || session_settings(cat)).transform_keys(&:to_s)
      apply_type_catalog_defaults!(settings, cat) unless edit_mode
      types = initial_types || InteriorPro::DoorLibrary.all_types(cat)
      initial_width = settings['width']
      initial_height = settings['height']
      initial_frame = settings['frame_width']
      initial_glass_frame = settings['glass_frame_width']
      initial_depth = settings['interior_depth']
      initial_floor = settings['floor_offset']
      place_label = edit_mode ? 'Apply Changes' : 'Place Door on Wall'
      place_fn = edit_mode ? 'applyEdit()' : 'placeDoor()'
      door_place_mode = !edit_mode
      panel_width_in = InteriorPro::DoorLibrary::PANEL_WIDTH_IN
      jamb_total_in = InteriorPro::DoorLibrary::JAMB_TOTAL_IN
      settings_json = settings.to_json
      types_json = types.to_json
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: Arial, sans-serif; background: #f0f0f0; overflow-x: hidden; }
          .header { background: #5D4037; color: white; padding: 12px 16px; font-size: 15px; font-weight: bold; }
          .content { padding: 14px; }
          .panel { background: white; border-radius: 6px; padding: 14px; border: 1px solid #ddd; }
          .section-title { font-size: 11px; color: #5D4037; font-weight: bold; text-transform: uppercase; margin-top: 10px; margin-bottom: 4px; border-bottom: 1px solid #eee; padding-bottom: 3px; }
          .section-title:first-child { margin-top: 0; }
          label { display: block; font-size: 12px; color: #555; margin-top: 6px; margin-bottom: 2px; }
          input, select { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
          .row { display: flex; gap: 8px; }
          .row > div { flex: 1; }
          .type-row { display: flex; gap: 6px; align-items: flex-end; }
          .type-row > select { flex: 1; }
          .btn-add-type { padding: 6px 10px; background: #43A047; color: white; border: none; border-radius: 4px; font-size: 12px; cursor: pointer; white-space: nowrap; }
          .btn-add-type:hover { background: #388E3C; }
          .checkbox-row { display: flex; align-items: center; gap: 6px; margin-top: 8px; }
          .checkbox-row input { width: auto; }
          .checkbox-row label { margin: 0; }
          .place-row { margin-top: 16px; }
          .btn-place { width: 100%; padding: 10px; background: #5D4037; color: white; border: none; border-radius: 6px; font-size: 14px; font-weight: bold; cursor: pointer; }
          .btn-place:hover { background: #4E342E; }
        </style>
        </head>
        <body>
        <div id="doorDialogRoot">
        <div class="header">Interior Pro - Door</div>
        <div class="content">
          <div class="panel">
            <div class="section-title">Category</div>
            <label>Door Category</label>
            <select id="doorCategory" onchange="onCategoryChange()">
              <option value="exterior">Exterior (Outside)</option>
              <option value="interior">Interior (Inside)</option>
            </select>

            <div class="section-title">Door Type</div>
            <label>Type</label>
            <div class="type-row">
              <select id="doorType" onchange="onDoorTypeChange()"></select>
              <button class="btn-add-type" onclick="addCustomType()">+ Add Custom Type</button>
            </div>

            <div class="section-title">Size</div>
            <div class="row">
              <div>
                <label>Door Width (in)</label>
                <input type="number" id="doorWidth" value="#{initial_width}" min="1" step="0.5">
              </div>
              <div>
                <label>Door Height (in)</label>
                <input type="number" id="doorHeight" value="#{initial_height}" min="1" step="0.5">
              </div>
            </div>
            <div class="row">
              <div>
                <label>Frame Width (in)</label>
                <input type="number" id="frameWidth" value="#{initial_frame}" min="0.25" step="0.25">
              </div>
              <div>
                <label>Interior Depth (in)</label>
                <input type="number" id="interiorDepth" value="#{initial_depth}" min="0.25" step="0.25">
              </div>
            </div>
            <label>Glass Frame Width (in)</label>
            <input type="number" id="glassFrameWidth" value="#{initial_glass_frame}" min="0.5" step="0.25"
                   title="Width of the frame around each glass pane (reduces glass area)">

            <div class="section-title">Position</div>
            <label>Threshold / Floor Offset (in)</label>
            <input type="number" id="floorOffset" value="#{initial_floor}" min="0" step="0.25">

            <div class="section-title">Opening Direction</div>
            <div id="hingedFields">
              <div class="row">
                <div>
                  <label>Swing Direction</label>
                  <select id="swingDirection">
                    <option value="left">Left</option>
                    <option value="right">Right</option>
                  </select>
                </div>
                <div>
                  <label>Swing Side</label>
                  <select id="swingSide">
                    <option value="auto">Auto (click side)</option>
                    <option value="inward">Inward</option>
                    <option value="outward">Outward</option>
                  </select>
                </div>
              </div>
            </div>
            <div id="slidingFields">
              <label>Slide Direction</label>
              <select id="slideDirection">
                <option value="left">Slide Left</option>
                <option value="right">Slide Right</option>
              </select>
            </div>

            <div class="section-title">Casing &amp; Trim</div>
            <label id="exteriorCasingLabel">Exterior Casing</label>
            <select id="exteriorCasingStyle">
              <option value="none">None</option>
              <option value="kb103">KB103 — 3" wide</option>
              <option value="kb106">KB106 — 3-1/2" wide</option>
              <option value="kb117">KB117 — 4" wide</option>
            </select>
            <label>Interior Casing</label>
            <select id="interiorCasingStyle">
              <option value="none">None</option>
              <optgroup label="Door casing — 2&quot;">
                <option value="flat">Flat</option>
                <option value="ranch">Ranch — tapered</option>
                <option value="colonial">Colonial — cove</option>
                <option value="stafford">Stafford — double bead</option>
                <option value="windsor">Windsor — slope</option>
                <option value="belly">Belly — curve</option>
              </optgroup>
              <optgroup label="Baseboard catalog (smooth)">
                <option value="bm325">7/16&quot; × 3-1/4&quot; — simple eased</option>
                <option value="bm400">7/16&quot; × 4&quot; — rounded top</option>
                <option value="bm325_bevel">9/16&quot; × 3-1/4&quot; — bevel</option>
                <option value="bm425">9/16&quot; × 4-1/4&quot; — step</option>
                <option value="bm388_ogee">9/16&quot; × 3-7/8&quot; — ogee</option>
                <option value="bm525_cove">11/16&quot; × 5-1/4&quot; — cove</option>
              </optgroup>
            </select>

            <div class="section-title">Glass</div>
            <label>Glass Grid</label>
            <select id="glassGridStyle">
              <option value="none">None — clear glass</option>
              <option value="1x2">1 × 2 (2 lites)</option>
              <option value="2x2">2 × 2 (4 lites)</option>
              <option value="2x3">2 × 3 (6 lites)</option>
              <option value="2x5">2 × 5 (10 lites — French)</option>
              <option value="3x3">3 × 3 (9 lites)</option>
              <option value="3x4">3 × 4 (12 lites)</option>
            </select>
            <div class="checkbox-row" id="exteriorThresholdRow">
              <input type="checkbox" id="exteriorThreshold" checked>
              <label for="exteriorThreshold">Exterior Threshold (floor sill)</label>
            </div>

            <div class="place-row">
              <button class="btn-place" onclick="#{place_fn}">#{place_label}</button>
            </div>
          </div>
        </div>
        </div>
        <script>
          var doorPlaceMode = #{door_place_mode};
          var panelWidthIn = #{panel_width_in};
          var jambTotalIn = #{jamb_total_in};
          var initialSettings = #{settings_json};
          var initialTypes = #{types_json};

          function resizeDialogToContent() {
            var root = document.getElementById('doorDialogRoot');
            if (!root) return;
            var h = Math.ceil(root.getBoundingClientRect().height);
            if (window.sketchup && sketchup.resize_to_fit) {
              sketchup.resize_to_fit(h);
            }
          }

          function bootstrapDoorForm() {
            var s = initialSettings || {};
            var cat = s.door_category || 'exterior';
            document.getElementById('doorCategory').value = cat;
            loadTypes(initialTypes || [], s.door_type);
            loadForm(s);
            syncCategoryFields();
          }

          window.onload = function() {
            bootstrapDoorForm();
            setTimeout(resizeDialogToContent, 120);
            window.addEventListener('focus', function () {
              if (window.sketchup && sketchup.return_focus_to_model) {
                sketchup.return_focus_to_model();
              }
            });
          };

          function loadTypes(types, selectName) {
            var sel = document.getElementById('doorType');
            var current = selectName || sel.value;
            sel.innerHTML = types.map(function(t) {
              return '<option value="' + t + '">' + t + '</option>';
            }).join('');
            if (current && types.indexOf(current) !== -1) sel.value = current;
            syncTypeFields();
            if (doorPlaceMode) applyTypeDefaults();
            resizeDialogToContent();
          }

          // Restore last door settings from this SketchUp session (or defaults).
          function loadForm(s) {
            if (!s) return;
            if (s.door_category) {
              document.getElementById('doorCategory').value = s.door_category;
            }
            document.getElementById('doorWidth').value = s.width;
            document.getElementById('doorHeight').value = s.height;
            document.getElementById('frameWidth').value = s.frame_width;
            document.getElementById('glassFrameWidth').value = s.glass_frame_width;
            document.getElementById('interiorDepth').value = s.interior_depth;
            document.getElementById('floorOffset').value = s.floor_offset;
            document.getElementById('swingDirection').value = s.swing_direction;
            document.getElementById('swingSide').value = s.swing_side;
            document.getElementById('slideDirection').value = s.slide_direction;
            document.getElementById('glassGridStyle').value =
              s.glass_grid_style || (s.glass_grid ? '2x2' : 'none');
            document.getElementById('exteriorCasingStyle').value =
              s.exterior_casing_style || (s.exterior_casing ? 'flat' : 'none');
            document.getElementById('interiorCasingStyle').value =
              s.interior_casing_style || (s.interior_casing ? 'flat' : 'none');
            document.getElementById('exteriorThreshold').checked =
              s.exterior_threshold !== undefined ? !!s.exterior_threshold : true;
            syncTypeFields();
            syncCategoryFields();
            if (doorPlaceMode) applyTypeDefaults();
            resizeDialogToContent();
          }

          function onCategoryChange() {
            sketchup.load_category(document.getElementById('doorCategory').value);
          }

          function syncCategoryFields() {
            var isInterior = document.getElementById('doorCategory').value === 'interior';
            document.getElementById('exteriorThresholdRow').style.display = isInterior ? 'none' : 'block';
            document.getElementById('exteriorCasingLabel').style.display = isInterior ? 'none' : 'block';
            document.getElementById('exteriorCasingStyle').style.display = isInterior ? 'none' : 'block';
            resizeDialogToContent();
          }

          function applyRubyTypeDefaults(s) {
            if (!s) return;
            if (s.width != null) document.getElementById('doorWidth').value = s.width;
            if (s.glass_frame_width != null) {
              document.getElementById('glassFrameWidth').value = s.glass_frame_width;
            }
            if (s.glass_grid_style) {
              document.getElementById('glassGridStyle').value = s.glass_grid_style;
            }
            resizeDialogToContent();
          }

          // Show swing fields for hinged doors, slide field for sliding doors.
          function onDoorTypeChange() {
            if (doorPlaceMode && window.sketchup && sketchup.type_changed) {
              sketchup.type_changed(
                document.getElementById('doorType').value,
                document.getElementById('doorCategory').value
              );
            } else if (doorPlaceMode) {
              applyTypeDefaults();
            }
            syncTypeFields();
          }

          function panelCountFromType(t) {
            var m = t.match(/^(\d+)-Panel/);
            return m ? parseInt(m[1], 10) : null;
          }

          function isMultiPanelSliding(t) {
            return /^\d+-Panel Sliding$/.test(t);
          }

          function isFolding(t) {
            return /^\d+-Panel Folding$/.test(t);
          }

          function applyTypeDefaults() {
            var t = document.getElementById('doorType').value;
            var cat = document.getElementById('doorCategory').value;
            if (cat !== 'exterior') return;
            if (t === 'Sliding') {
              document.getElementById('glassFrameWidth').value = 2;
              document.getElementById('glassGridStyle').value = 'none';
            } else if (t === 'French Hinged') {
              document.getElementById('glassFrameWidth').value = 5;
              document.getElementById('glassGridStyle').value = '2x2';
            } else if (isMultiPanelSliding(t) || isFolding(t) || t === '4-Panel Center Hinged') {
              document.getElementById('glassFrameWidth').value = 2.5;
              document.getElementById('glassGridStyle').value = 'none';
            }
            var pc = panelCountFromType(t);
            if (pc) {
              document.getElementById('doorWidth').value = pc * panelWidthIn + jambTotalIn;
            } else if (t === 'French Hinged') {
              document.getElementById('doorWidth').value = 60;
            }
          }

          function syncTypeFields() {
            var t = document.getElementById('doorType').value;
            var isSliding = (t === 'Sliding' || t === 'French Sliding' || t === 'Pocket' ||
                             isMultiPanelSliding(t) || isFolding(t));
            document.getElementById('slidingFields').style.display = isSliding ? 'block' : 'none';
            document.getElementById('hingedFields').style.display = isSliding ? 'none' : 'block';
            resizeDialogToContent();
          }

          function addCustomType() {
            var name = prompt('Enter new door type name:');
            if (name === null) return;
            name = name.trim();
            if (!name) { alert('Name cannot be empty.'); return; }
            sketchup.add_custom_type(name, document.getElementById('doorCategory').value);
          }

          function placeDoor() {
            var door = collectDoorSettings();
            sketchup.place_door(JSON.stringify(door));
          }

          function applyEdit() {
            sketchup.apply_edit(JSON.stringify(collectDoorSettings()));
          }

          function collectDoorSettings() {
            return {
              door_category: document.getElementById('doorCategory').value,
              door_type: document.getElementById('doorType').value,
              width: parseFloat(document.getElementById('doorWidth').value),
              height: parseFloat(document.getElementById('doorHeight').value),
              frame_width: parseFloat(document.getElementById('frameWidth').value),
              glass_frame_width: parseFloat(document.getElementById('glassFrameWidth').value),
              interior_depth: parseFloat(document.getElementById('interiorDepth').value),
              floor_offset: parseFloat(document.getElementById('floorOffset').value),
              swing_direction: document.getElementById('swingDirection').value,
              swing_side: document.getElementById('swingSide').value,
              slide_direction: document.getElementById('slideDirection').value,
              glass_grid_style: document.getElementById('glassGridStyle').value,
              exterior_casing_style: document.getElementById('doorCategory').value === 'interior'
                ? 'none'
                : document.getElementById('exteriorCasingStyle').value,
              interior_casing_style: document.getElementById('interiorCasingStyle').value,
              exterior_threshold: document.getElementById('doorCategory').value === 'interior'
                ? false
                : document.getElementById('exteriorThreshold').checked
            };
          }
        </script>
        </body>
        </html>
      HTML
    end

  end
end

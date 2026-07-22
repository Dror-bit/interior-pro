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
      tool.leaf_style          = settings['leaf_style'] || 'Flush' if tool.respond_to?(:leaf_style=)
      tool.closet_leaf_count   = (settings['closet_leaf_count'] || 2).to_i if tool.respond_to?(:closet_leaf_count=)
      tool.handle_style        = settings['handle_style'] || 'none' if tool.respond_to?(:handle_style=)
      tool.front_config        = settings['front_config'] || 'single' if tool.respond_to?(:front_config=)
      tool.front_leaf_style    = settings['front_leaf_style'] || 'Craftsman 3-Lite' if tool.respond_to?(:front_leaf_style=)
      tool.front_glass_ratio   = (settings['front_glass_ratio'] || 50.0).to_f if tool.respond_to?(:front_glass_ratio=)
      tool.sidelite_width      = (settings['sidelite_width'] || 14.0).to_f if tool.respond_to?(:sidelite_width=)
      tool.transom             = !!settings['transom'] if tool.respond_to?(:transom=)
      tool.transom_height      = (settings['transom_height'] || 14.0).to_f if tool.respond_to?(:transom_height=)
      tool.garage_style        = settings['garage_style'] || 'Raised Short' if tool.respond_to?(:garage_style=)
      tool.garage_top_windows  = !!settings['garage_top_windows'] if tool.respond_to?(:garage_top_windows=)
      tool.door_color          = settings['door_color'] || '' if tool.respond_to?(:door_color=)
      tool.frame_color         = settings['frame_color'] || '' if tool.respond_to?(:frame_color=)
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
        h = 1400 if h > 1400
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
          # Re-cut molding around the edited door (no-op when no molding in model).
          if defined?(InteriorPro::MoldingManager)
            begin
              InteriorPro::MoldingManager.refresh!
            rescue StandardError => e
              puts "[DoorLibraryDialog] molding refresh failed: #{e.message}"
            end
          end
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
      handles_json = defined?(InteriorPro::DoorHandles) ?
        InteriorPro::DoorHandles.handle_names('interior').to_json : '[]'
      front_handles_json = defined?(InteriorPro::DoorHandles) ?
        InteriorPro::DoorHandles.handle_names('front').to_json : '[]'
      casing_skp_options = (defined?(InteriorPro::MoldingLibrary) ?
        InteriorPro::MoldingLibrary.skp_names('CASING') : [])
        .map { |c| "<option value=\"#{c}\">#{c}</option>" }.join
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
          .design-grid { display: grid; grid-template-columns: repeat(5, 34px); gap: 6px; margin-top: 6px; justify-content: center; }
          .design-card { border: 2px solid #ddd; border-radius: 4px; padding: 3px 2px 2px; cursor: pointer; text-align: center; background: #fafafa; }
          .design-card:hover { border-color: #a1887f; }
          .design-card.selected { border-color: #5D4037; background: #f0e8e4; }
          .design-card svg { width: 100%; height: auto; display: block; }
          .design-card .dn { font-size: 8.5px; color: #555; margin-top: 2px; line-height: 1.1; min-height: 18px; }
          .handle-head { display: flex; align-items: center; justify-content: space-between; border: 1px solid #ccc; border-radius: 4px; padding: 6px 8px; cursor: pointer; background: #fafafa; margin-top: 2px; }
          .handle-head:hover { border-color: #a1887f; }
          .handle-head .hn { font-size: 13px; color: #333; }
          .handle-head .arrow { font-size: 11px; color: #777; }
          .handle-grid { display: none; grid-template-columns: repeat(5, 1fr); gap: 6px; margin-top: 6px; }
          .handle-grid.open { display: grid; }
          .checkbox-row { display: flex; align-items: center; gap: 6px; margin-top: 8px; }
          .checkbox-row input { width: auto; }
          .checkbox-row label { margin: 0; }
          .place-row { position: sticky; bottom: 0; margin-top: 16px; padding: 10px 0;
                       background: white; box-shadow: 0 -6px 8px -6px rgba(0,0,0,0.35); }
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

            <div id="leafDesignSection">
              <div class="section-title">Leaf Design</div>
              <div class="handle-head" onclick="toggleDesignGrid()">
                <span class="hn" id="designCurrentLabel">Flush</span>
                <span class="arrow" id="designArrow">&#9656;</span>
              </div>
              <div class="design-grid" id="designGrid" style="display:none;"></div>
            </div>

            <div id="closetSection" style="display:none;">
              <div class="section-title">Closet Panels (Mirror)</div>
              <div class="design-grid" id="closetGrid" style="grid-template-columns: repeat(2, 1fr);"></div>
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
            <div class="row" style="align-items:center;">
              <div>
                <label style="display:inline;">Door Color</label>
                <input type="color" id="doorColor" value="#faf8f3" title="Leaf color"
                       onchange="onDoorColorChange()"
                       style="width:22px;height:22px;padding:0;border:1px solid #ccc;vertical-align:middle;margin-left:6px;">
              </div>
              <div>
                <label style="display:inline;">Frame Color</label>
                <input type="color" id="frameColor" value="#f5f5f0" title="Jamb / casing color"
                       style="width:22px;height:22px;padding:0;border:1px solid #ccc;vertical-align:middle;margin-left:6px;">
              </div>
            </div>
            <label style="display:block;margin-top:4px;">
              <input type="checkbox" id="sameColorCheck" onchange="onSameColorToggle()">
              Frame same color as door
            </label>

            <div id="frontDoorSection" style="display:none;">
              <div class="section-title">Front Door</div>
              <label>Design</label>
              <div class="handle-head" onclick="toggleFrontDesignGrid()">
                <span class="hn" id="frontDesignCurrentLabel">Craftsman 3-Lite</span>
                <span class="arrow" id="frontDesignArrow">&#9656;</span>
              </div>
              <div class="design-grid" id="frontDesignGrid" style="display:none;"></div>
              <label>Configuration</label>
              <select id="frontConfig" onchange="onFrontConfigChange()">
                <option value="single">Single</option>
                <option value="single_1sl">Single + 1 Sidelite</option>
                <option value="single_2sl">Single + 2 Sidelites</option>
                <option value="double">Double</option>
              </select>
              <label>Sidelite Width (in)</label>
              <input type="number" id="sideliteWidth" value="14" min="6" step="0.5">
              <label>Glass Height (% of door, Farmhouse)</label>
              <input type="number" id="frontGlassRatio" value="50" min="10" max="90" step="5">
              <div class="checkbox-row">
                <input type="checkbox" id="transomCheck" onchange="onTransomToggle()">
                <label for="transomCheck">Transom (window above)</label>
              </div>
              <label>Transom Height (in)</label>
              <input type="number" id="transomHeight" value="14" min="6" step="0.5">
            </div>

            <div id="garageDoorSection" style="display:none;">
              <div class="section-title">Garage Door</div>
              <label>Style</label>
              <select id="garageStyle" style="display:none;" onchange="onGarageStyleChange()">
                <option value="Raised Short">Raised Panel Short</option>
                <option value="Raised Long">Raised Panel Long</option>
                <option value="Flush">Flush</option>
                <option value="Full View Glass">Full View Glass (aluminum)</option>
              </select>
              <div class="handle-head" onclick="toggleGarageDesignGrid()">
                <span class="hn" id="garageDesignCurrentLabel">Raised Panel Short</span>
                <span class="arrow" id="garageDesignArrow">&#9656;</span>
              </div>
              <div class="design-grid" id="garageDesignGrid" style="display:none; grid-template-columns: repeat(2, 104px);"></div>
              <div class="checkbox-row">
                <input type="checkbox" id="garageTopWindows">
                <label for="garageTopWindows">Top section windows</label>
              </div>
            </div>

            <div id="handleSection" style="display:none;">
              <div class="section-title">Handle</div>
              <label>Door Handle</label>
              <select id="handleStyle" style="display:none;"></select>
              <div class="handle-head" onclick="toggleHandleGallery()">
                <span class="hn" id="handleCurrentLabel">None</span>
                <span class="arrow" id="handleArrow">&#9656;</span>
              </div>
              <div class="handle-grid" id="handleGrid"></div>
            </div>

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

            <div id="casingSection">
              <div class="section-title">Casing &amp; Trim</div>
              <label id="exteriorCasingLabel">Exterior Casing</label>
              <select id="exteriorCasingStyle">
                <option value="none">None</option>
                <option value="flat">Flat (square)</option>
                #{casing_skp_options}
              </select>
              <label>Interior Casing</label>
              <select id="interiorCasingStyle">
                <option value="none">None</option>
                <option value="flat">Flat (square)</option>
                #{casing_skp_options}
              </select>
            </div>

            <div id="glassGridSection">
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
            </div>
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
          var HANDLE_NAMES = #{handles_json};
          var FRONT_HANDLE_NAMES = #{front_handles_json};

          function onSameColorToggle() {
            var same = document.getElementById('sameColorCheck').checked;
            var fc = document.getElementById('frameColor');
            fc.disabled = same;
            if (same) fc.value = document.getElementById('doorColor').value;
          }
          function onDoorColorChange() {
            if (document.getElementById('sameColorCheck').checked) {
              document.getElementById('frameColor').value = document.getElementById('doorColor').value;
            }
          }

          function isFrontDoorType() {
            return document.getElementById('doorCategory').value === 'exterior' &&
                   document.getElementById('doorType').value === 'Front Door';
          }
          function currentHandleNames() {
            return isFrontDoorType() ? FRONT_HANDLE_NAMES : HANDLE_NAMES;
          }

          function renderHandleOptions() {
            var sel = document.getElementById('handleStyle');
            if (!sel) return;
            var names = currentHandleNames();
            var cur = sel.value;
            var opts = '<option value="none">None</option>';
            for (var i = 0; i < names.length; i++) {
              opts += '<option value="' + names[i] + '">' + names[i] + '</option>';
            }
            sel.innerHTML = opts;
            sel.value = (names.indexOf(cur) >= 0) ? cur : 'none';
          }

          // ---- Handle gallery (collapsed by default, minimalist 2D thumbs) ----
          function handleThumbSvg(name) {
            var s;
            switch (name) {
              case '1':
                s = '<circle cx="30" cy="48" r="15" fill="#e8e6e1" stroke="#777" stroke-width="2"/>' +
                    '<rect x="27" y="41" width="56" height="14" rx="5" fill="#f2f0ec" stroke="#777" stroke-width="2"/>';
                break;
              case '2':
                s = '<rect x="16" y="28" width="28" height="28" rx="3" fill="#c9c7c2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="12" y="35" width="72" height="12" fill="#dbd9d4" stroke="#777" stroke-width="2"/>' +
                    '<rect x="22" y="64" width="17" height="17" rx="2" fill="#c9c7c2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="28" y="68" width="5" height="9" rx="2.5" fill="#555"/>';
                break;
              case '3':
                s = '<rect x="22" y="8" width="26" height="80" rx="12" fill="#4a4a4a" stroke="#2c2c2a" stroke-width="2"/>' +
                    '<circle cx="35" cy="31" r="12" fill="#3d3d3d" stroke="#222" stroke-width="2"/>' +
                    '<circle cx="35" cy="31" r="6" fill="none" stroke="#666" stroke-width="1.5"/>' +
                    '<rect x="30" y="58" width="10" height="16" rx="5" fill="#2c2c2a"/>' +
                    '<line x1="35" y1="62" x2="35" y2="70" stroke="#888" stroke-width="1.5"/>';
                break;
              case '4':
                s = '<rect x="24" y="6" width="22" height="84" rx="10" fill="#3a3a3a" stroke="#222" stroke-width="2"/>' +
                    '<circle cx="35" cy="16" r="1.6" fill="#777"/><circle cx="35" cy="80" r="1.6" fill="#777"/>' +
                    '<circle cx="35" cy="32" r="8" fill="#2f2f2f" stroke="#222" stroke-width="2"/>' +
                    '<path d="M 40 30 C 54 24, 64 28, 72 36" fill="none" stroke="#3a3a3a" stroke-width="9" stroke-linecap="round"/>' +
                    '<circle cx="74" cy="38" r="6" fill="#3a3a3a" stroke="#222" stroke-width="1.5"/>' +
                    '<circle cx="35" cy="64" r="5" fill="none" stroke="#888" stroke-width="1.5"/>' +
                    '<line x1="35" y1="62" x2="35" y2="67" stroke="#888" stroke-width="1.5"/>';
                break;
              case '5':
                s = '<circle cx="30" cy="34" r="14" fill="#d9d7d2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="28" y="30" width="54" height="9" rx="4.5" fill="#e8e6e1" stroke="#777" stroke-width="2"/>' +
                    '<circle cx="30" cy="70" r="11" fill="#d9d7d2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="27" y="63" width="6" height="14" rx="3" fill="none" stroke="#777" stroke-width="1.5"/>';
                break;
              case '6':
                s = '<circle cx="30" cy="48" r="14" fill="#d9d7d2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="27" y="42" width="55" height="13" rx="6.5" fill="#e8e6e1" stroke="#777" stroke-width="2"/>';
                break;
              case 'Door knob':
                s = '<circle cx="48" cy="48" r="17" fill="#e8e6e1" stroke="#777" stroke-width="2"/>' +
                    '<circle cx="48" cy="48" r="10" fill="#d0cec9" stroke="#777" stroke-width="2"/>';
                break;
              case 'M - 7':
                s = '<circle cx="30" cy="48" r="15" fill="#d9d7d2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="22" y="42" width="12" height="13" fill="#b5b3ae" stroke="#555" stroke-width="1.5"/>' +
                    '<rect x="70" y="42" width="12" height="13" fill="#b5b3ae" stroke="#555" stroke-width="1.5"/>' +
                    '<rect x="34" y="41" width="36" height="15" fill="#2c2c2a"/>' +
                    '<rect x="24" y="45" width="7" height="7" fill="none" stroke="#555" stroke-width="1.5" transform="rotate(45 27.5 48.5)"/>';
                break;
              case 'M-8':
                s = '<circle cx="28" cy="44" r="14" fill="#d9d7d2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="24" y="34" width="58" height="20" rx="10" fill="#e8e6e1" stroke="#777" stroke-width="2"/>' +
                    '<circle cx="32" cy="44" r="8" fill="#d0cec9" stroke="#777" stroke-width="1.5"/>' +
                    '<rect x="56" y="40" width="18" height="9" rx="4.5" fill="none" stroke="#777" stroke-width="1.5"/>';
                break;
              default:
                s = '<circle cx="30" cy="48" r="15" fill="#e8e6e1" stroke="#777" stroke-width="2"/>' +
                    '<rect x="27" y="41" width="56" height="14" rx="5" fill="#f2f0ec" stroke="#777" stroke-width="2"/>';
            }
            return '<svg viewBox="0 0 96 96">' + s + '</svg>';
          }
          // Front handle thumbs (numeric names collide with interior — separate set).
          function frontHandleThumbSvg(name) {
            var s;
            switch (name) {
              case '1': // 24in pull
                s = '<rect x="40" y="16" width="6" height="6" fill="#2c2c2a"/><rect x="40" y="74" width="6" height="6" fill="#2c2c2a"/>' +
                    '<rect x="44" y="10" width="8" height="76" rx="4" fill="#2c2c2a"/>';
                break;
              case '2': // pull on backplate
                s = '<rect x="38" y="14" width="20" height="68" rx="3" fill="#c9c7c2" stroke="#777" stroke-width="2"/>' +
                    '<rect x="44" y="24" width="8" height="48" rx="4" fill="#2c2c2a"/>';
                break;
              case '3': // grip handle
                s = '<rect x="42" y="20" width="12" height="56" rx="6" fill="#4a4a4a" stroke="#2c2c2a" stroke-width="2"/>';
                break;
              case '4': // 12in pull
                s = '<rect x="40" y="32" width="6" height="6" fill="#2c2c2a"/><rect x="40" y="58" width="6" height="6" fill="#2c2c2a"/>' +
                    '<rect x="44" y="26" width="8" height="44" rx="4" fill="#2c2c2a"/>';
                break;
              default:
                s = '<rect x="44" y="20" width="8" height="56" rx="4" fill="#2c2c2a"/>';
            }
            return '<svg viewBox="0 0 96 96">' + s + '</svg>';
          }
          function renderHandleGallery() {
            var grid = document.getElementById('handleGrid');
            if (!grid) return;
            var cur = document.getElementById('handleStyle').value || 'none';
            var front = isFrontDoorType();
            var names = ['none'].concat(currentHandleNames());
            grid.innerHTML = names.map(function(n) {
              var sel = n === cur ? ' selected' : '';
              var svg = n === 'none'
                ? '<svg viewBox="0 0 96 96"><circle cx="48" cy="48" r="20" fill="none" stroke="#bbb" stroke-width="2"/><line x1="34" y1="62" x2="62" y2="34" stroke="#bbb" stroke-width="2"/></svg>'
                : (front ? frontHandleThumbSvg(n) : handleThumbSvg(n));
              return '<div class="design-card' + sel + '" data-handle="' + n +
                     '" onclick="selectHandleCard(this)">' + svg +
                     '<div class="dn">' + (n === 'none' ? 'None' : n) + '</div></div>';
            }).join('');
          }
          function selectHandleCard(el) {
            var n = el.getAttribute('data-handle');
            document.getElementById('handleStyle').value = n;
            syncHandleLabel();
            toggleHandleGallery(false);
          }
          function toggleHandleGallery(force) {
            var g = document.getElementById('handleGrid');
            var open = (typeof force === 'boolean') ? force : g.className.indexOf('open') === -1;
            g.className = open ? 'handle-grid open' : 'handle-grid';
            document.getElementById('handleArrow').innerHTML = open ? '&#9662;' : '&#9656;';
            if (open) renderHandleGallery();
            resizeDialogToContent();
          }
          function syncHandleLabel() {
            var v = document.getElementById('handleStyle').value || 'none';
            document.getElementById('handleCurrentLabel').textContent = (v === 'none') ? 'None' : v;
          }

          // ---- Leaf designs (must match InteriorPro::DoorLeafStyles::STYLES) ----
          var FR = {
            shaker:   { st: 13.3, tr: 12.9, br: 27.6, ir: 12.9, lock: 22.3 },
            mas:      { st: 14.25, tr: 12.75, br: 32.6, ir: 12.75, lock: 20.25 },
            colonial: { st: 13.7, tr: 13.5, fr2: 13.5, lock: 22.5, br: 27.75, mu: 13.5 },
            french:   { st: 13.7, tr: 13.7, br: 27.4 }
          };
          var LEAF_DESIGNS = [
            { name: 'Flush',            spec: { t: 'slab' } },
            { name: '1 Panel Shaker',   spec: { t: 'stack', f: 'shaker', rows: 1 } },
            { name: '2 Panel Shaker',   spec: { t: 'stack', f: 'shaker', rows: 2, useLock: true } },
            { name: '5 Panel Shaker',   spec: { t: 'stack', f: 'shaker', rows: 5 } },
            { name: '6 Panel Colonial', spec: { t: 'colonial' } },
            { name: '1 Lite Clear',     spec: { t: 'lite' } },
            { name: 'Caiman',           spec: { t: 'stack', f: 'mas', rows: 2, useLock: true, split: [0.58, 0.42], arch: 'round', inner: true } },
            { name: 'Carrara',          spec: { t: 'stack', f: 'mas', rows: 2, useLock: true, split: [0.58, 0.42], inner: true } },
            { name: 'Camden',           spec: { t: 'stack', f: 'mas', rows: 2, useLock: true, split: [0.58, 0.42], arch: 'eyebrow', inner: true, tex: true } },
            { name: 'Colonist',         spec: { t: 'colonial', tex: true } }
          ];
          var selectedLeafStyle = 'Flush';

          function svgR(x, y, w, h, f) {
            return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h +
                   '" fill="' + f + '" stroke="#777" stroke-width="1"/>';
          }
          function panelSvg(x, y, w, h, arch, inner) {
            var s = '';
            if (arch === 'round') {
              var r = w / 2;
              s += '<path d="M ' + x + ' ' + (y + h) + ' L ' + x + ' ' + (y + r) +
                   ' A ' + r + ' ' + r + ' 0 0 1 ' + (x + w) + ' ' + (y + r) +
                   ' L ' + (x + w) + ' ' + (y + h) + ' Z" fill="#efece5" stroke="#777"/>';
              if (inner) s += '<path d="M ' + (x + 3) + ' ' + (y + h - 3) + ' L ' + (x + 3) + ' ' + (y + r) +
                   ' A ' + (r - 3) + ' ' + (r - 3) + ' 0 0 1 ' + (x + w - 3) + ' ' + (y + r) +
                   ' L ' + (x + w - 3) + ' ' + (y + h - 3) + ' Z" fill="none" stroke="#a99"/>';
            } else if (arch === 'eyebrow') {
              var a = h * 0.18;
              s += '<path d="M ' + x + ' ' + (y + h) + ' L ' + x + ' ' + (y + a) +
                   ' Q ' + (x + w / 2) + ' ' + (y - a) + ' ' + (x + w) + ' ' + (y + a) +
                   ' L ' + (x + w) + ' ' + (y + h) + ' Z" fill="#efece5" stroke="#777"/>';
              if (inner) s += '<path d="M ' + (x + 3) + ' ' + (y + h - 3) + ' L ' + (x + 3) + ' ' + (y + a + 2) +
                   ' Q ' + (x + w / 2) + ' ' + (y - a + 5) + ' ' + (x + w - 3) + ' ' + (y + a + 2) +
                   ' L ' + (x + w - 3) + ' ' + (y + h - 3) + ' Z" fill="none" stroke="#a99"/>';
            } else {
              s += svgR(x, y, w, h, '#efece5');
              if (inner) s += '<rect x="' + (x + 3) + '" y="' + (y + 3) + '" width="' + (w - 6) +
                   '" height="' + (h - 6) + '" fill="none" stroke="#a99"/>';
            }
            return s;
          }
          function leafThumbSvg(spec) {
            var bg = spec.tex ? '#f3ead9' : '#fbfaf7';
            var s = svgR(1, 1, 94, 238, bg);
            if (spec.t === 'stack') {
              var f = FR[spec.f], pw = 96 - 2 * f.st;
              var top = f.tr, field = (240 - f.br) - top;
              var mid = spec.useLock ? f.lock : f.ir;
              var space = field - (spec.rows - 1) * mid;
              var y = top;
              for (var i = 0; i < spec.rows; i++) {
                var h = spec.split ? space * spec.split[i] : space / spec.rows;
                s += panelSvg(f.st, y, pw, h, i === 0 ? spec.arch : null, spec.inner);
                y += h + mid;
              }
            } else if (spec.t === 'colonial') {
              var f = FR.colonial;
              var cw = (96 - 2 * f.st - f.mu) / 2;
              var rows = [[f.tr, 35.25], [f.tr + 35.25 + f.fr2, 63.75], [f.tr + 35.25 + f.fr2 + 63.75 + f.lock, 63.75]];
              for (var i = 0; i < rows.length; i++) {
                s += panelSvg(f.st, rows[i][0], cw, rows[i][1], null, true);
                s += panelSvg(f.st + cw + f.mu, rows[i][0], cw, rows[i][1], null, true);
              }
            } else if (spec.t === 'lite') {
              var f = FR.french;
              s += svgR(f.st, f.tr, 96 - 2 * f.st, 240 - f.tr - f.br, '#dce8ee');
              s += '<line x1="' + (f.st + 5) + '" y1="' + (f.tr + 22) + '" x2="' + (f.st + 22) +
                   '" y2="' + (f.tr + 5) + '" stroke="#fff" stroke-width="3" opacity="0.8"/>';
            }
            return '<svg viewBox="0 0 96 240">' + s + '</svg>';
          }
          function renderDesignGrid() {
            var grid = document.getElementById('designGrid');
            if (!grid) return;
            var lbl = document.getElementById('designCurrentLabel');
            if (lbl) lbl.textContent = selectedLeafStyle || 'Flush';
            grid.innerHTML = LEAF_DESIGNS.map(function(d) {
              var sel = d.name === selectedLeafStyle ? ' selected' : '';
              return '<div class="design-card' + sel + '" data-style="' + d.name +
                     '" title="' + d.name + '" onclick="selectLeafDesign(this)">' +
                     leafThumbSvg(d.spec) + '</div>';
            }).join('');
          }
          function selectLeafDesign(el) {
            selectedLeafStyle = el.getAttribute('data-style');
            var cards = document.querySelectorAll('#designGrid .design-card');
            for (var i = 0; i < cards.length; i++) cards[i].className = 'design-card';
            el.className = 'design-card selected';
            toggleDesignGrid(false);
          }
          function toggleDesignGrid(force) {
            var g = document.getElementById('designGrid');
            var open = (typeof force === 'boolean') ? force : g.style.display === 'none';
            g.style.display = open ? 'grid' : 'none';
            document.getElementById('designArrow').innerHTML = open ? '&#9662;' : '&#9656;';
            renderDesignGrid();
            resizeDialogToContent();
          }

          // ---- Closet (mirror bypass sliding) ----
          var selectedClosetPanels = 2;

          function isCloset() {
            return document.getElementById('doorCategory').value === 'interior' &&
                   document.getElementById('doorType').value === 'Closet';
          }
          function closetThumbSvg(count) {
            var W = 150, H = 240, s = '';
            var pw = (W - 4) / count;
            for (var i = 0; i < count; i++) {
              var x = 2 + i * pw;
              var y = (i % 2 === 0) ? 6 : 2; // hint: alternating front/back tracks
              var h = H - 8;
              s += '<rect x="' + x + '" y="' + y + '" width="' + pw + '" height="' + h +
                   '" fill="#4a3f35" stroke="#333" stroke-width="1"/>';
              s += '<rect x="' + (x + 4) + '" y="' + (y + 4) + '" width="' + (pw - 8) +
                   '" height="' + (h - 8) + '" fill="#dce8ee"/>';
              s += '<line x1="' + (x + 8) + '" y1="' + (y + 44) + '" x2="' + (x + pw - 12) +
                   '" y2="' + (y + 12) + '" stroke="#fff" stroke-width="4" opacity="0.7"/>';
            }
            return '<svg viewBox="0 0 150 240">' + s + '</svg>';
          }
          function renderClosetGrid() {
            var grid = document.getElementById('closetGrid');
            if (!grid) return;
            var opts = [{ n: 2, label: '2 Panel Mirror' }, { n: 3, label: '3 Panel Mirror' }];
            grid.innerHTML = opts.map(function(o) {
              var sel = o.n === selectedClosetPanels ? ' selected' : '';
              return '<div class="design-card' + sel + '" data-panels="' + o.n +
                     '" onclick="selectClosetOption(this)">' + closetThumbSvg(o.n) +
                     '<div class="dn">' + o.label + '</div></div>';
            }).join('');
          }
          function selectClosetOption(el) {
            selectedClosetPanels = parseInt(el.getAttribute('data-panels'), 10) || 2;
            renderClosetGrid();
          }

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
              // Don't yank focus while the user interacts with a form control -
              // it instantly closes open <select> dropdowns ("blinking" bug).
              setTimeout(function () {
                var ae = document.activeElement;
                if (ae && /SELECT|INPUT|BUTTON|TEXTAREA/.test(ae.tagName)) return;
                if (window.sketchup && sketchup.return_focus_to_model) {
                  sketchup.return_focus_to_model();
                }
              }, 60);
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
            if (s.leaf_style) selectedLeafStyle = s.leaf_style;
            if (s.closet_leaf_count) selectedClosetPanels = parseInt(s.closet_leaf_count, 10) || 2;
            if (s.front_config) document.getElementById('frontConfig').value = s.front_config;
            if (s.front_leaf_style) selectedFrontStyle = s.front_leaf_style;
            if (s.garage_style) document.getElementById('garageStyle').value = s.garage_style;
            document.getElementById('garageTopWindows').checked = !!s.garage_top_windows;
            onGarageStyleChange();
            if (s.front_glass_ratio != null) document.getElementById('frontGlassRatio').value = s.front_glass_ratio;
            if (s.sidelite_width != null) document.getElementById('sideliteWidth').value = s.sidelite_width;
            document.getElementById('transomCheck').checked = !!s.transom;
            if (s.transom_height != null) document.getElementById('transomHeight').value = s.transom_height;
            if (s.door_color) document.getElementById('doorColor').value = s.door_color;
            if (s.frame_color) document.getElementById('frameColor').value = s.frame_color;
            if (s.door_color && s.door_color === s.frame_color) {
              document.getElementById('sameColorCheck').checked = true;
              document.getElementById('frameColor').disabled = true;
            }
            renderHandleOptions();
            if (s.handle_style) document.getElementById('handleStyle').value = s.handle_style;
            syncHandleLabel();
            renderDesignGrid();
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
            document.getElementById('leafDesignSection').style.display = (isInterior && !isCloset()) ? 'block' : 'none';
            document.getElementById('closetSection').style.display = (isInterior && isCloset()) ? 'block' : 'none';
            if (isInterior && !isCloset()) renderDesignGrid();
            if (isInterior && isCloset()) renderClosetGrid();
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
            var closet = isCloset();
            var isSliding = !closet && (t === 'Sliding' || t === 'French Sliding' || t === 'Pocket' ||
                             t === 'Folding' || isMultiPanelSliding(t) || isFolding(t));
            var isFront = document.getElementById('doorCategory').value === 'exterior' && t === 'Front Door';
            document.getElementById('frontDoorSection').style.display = isFront ? 'block' : 'none';
            if (isFront) renderFrontDesignGrid();
            var isGarage = document.getElementById('doorCategory').value === 'exterior' && t === 'Garage Door';
            document.getElementById('garageDoorSection').style.display = isGarage ? 'block' : 'none';
            if (isGarage) renderGarageDesignGrid();
            // Garage doors: no casing, no glass grid, no threshold, no
            // opening-direction fields (it opens on rails).
            document.getElementById('casingSection').style.display = isGarage ? 'none' : 'block';
            document.getElementById('glassGridSection').style.display = isGarage ? 'none' : 'block';
            if (isGarage) document.getElementById('exteriorThresholdRow').style.display = 'none';
            document.getElementById('slidingFields').style.display = (isSliding && !isGarage) ? 'block' : 'none';
            document.getElementById('hingedFields').style.display = (isSliding || closet || isGarage) ? 'none' : 'block';
            var isInterior = document.getElementById('doorCategory').value === 'interior';
            document.getElementById('leafDesignSection').style.display = (isInterior && !closet) ? 'block' : 'none';
            document.getElementById('closetSection').style.display = closet ? 'block' : 'none';
            if (closet) renderClosetGrid();
            var showHandle = (isInterior && !closet && t !== 'Pocket') || isFront;
            document.getElementById('handleSection').style.display = showHandle ? 'block' : 'none';
            if (showHandle) { renderHandleOptions(); syncHandleLabel(); }
            resizeDialogToContent();
          }

          // ---- Garage Door style gallery ----
          var GARAGE_DESIGNS = [
            ['Raised Short', 'Raised Panel Short'],
            ['Raised Long', 'Raised Panel Long'],
            ['Flush', 'Flush'],
            ['Full View Glass', 'Full View Glass']
          ];
          var selectedGarageStyle = 'Raised Short';
          function garageLabelFor(v) {
            for (var i = 0; i < GARAGE_DESIGNS.length; i++) {
              if (GARAGE_DESIGNS[i][0] === v) return GARAGE_DESIGNS[i][1];
            }
            return v;
          }
          function garageThumbSvg(name) {
            var s = '', r, c;
            if (name === 'Raised Short') {
              s = svgR(1, 1, 238, 108, '#efe8dc');
              for (r = 0; r < 4; r++) for (c = 0; c < 8; c++) s += svgR(6 + c * 29, 5 + r * 26, 25, 20, '#e3d9c8');
            } else if (name === 'Raised Long') {
              s = svgR(1, 1, 238, 108, '#f4f2ec');
              for (r = 0; r < 4; r++) for (c = 0; c < 3; c++) s += svgR(7 + c * 78, 5 + r * 26, 70, 20, '#e9e5da');
            } else if (name === 'Flush') {
              s = svgR(1, 1, 238, 108, '#e8e4da');
              for (r = 1; r < 4; r++) s += '<line x1="2" y1="' + (r * 27) + '" x2="238" y2="' + (r * 27) + '" stroke="#b9b2a4" stroke-width="1.5"/>';
            } else if (name === 'Full View Glass') {
              s = svgR(1, 1, 238, 108, '#1d1d1b');
              for (r = 0; r < 4; r++) for (c = 0; c < 4; c++) s += svgR(8 + c * 58, 7 + r * 25, 52, 20, '#cfdde5');
            }
            return '<svg viewBox="0 0 240 110">' + s + '</svg>';
          }
          function renderGarageDesignGrid() {
            var grid = document.getElementById('garageDesignGrid');
            if (!grid) return;
            var lbl = document.getElementById('garageDesignCurrentLabel');
            if (lbl) lbl.textContent = garageLabelFor(selectedGarageStyle);
            grid.innerHTML = GARAGE_DESIGNS.map(function(d) {
              var sel = d[0] === selectedGarageStyle ? ' selected' : '';
              return '<div class="design-card' + sel + '" data-style="' + d[0] + '" title="' + d[1] +
                     '" onclick="selectGarageDesign(this)">' + garageThumbSvg(d[0]) +
                     '<div class="dn">' + d[1] + '</div></div>';
            }).join('');
          }
          function selectGarageDesign(el) {
            selectedGarageStyle = el.getAttribute('data-style');
            document.getElementById('garageStyle').value = selectedGarageStyle;
            onGarageStyleChange();
            toggleGarageDesignGrid(false);
          }
          function toggleGarageDesignGrid(force) {
            var g = document.getElementById('garageDesignGrid');
            var open = (typeof force === 'boolean') ? force : g.style.display === 'none';
            g.style.display = open ? 'grid' : 'none';
            document.getElementById('garageDesignArrow').innerHTML = open ? '&#9662;' : '&#9656;';
            renderGarageDesignGrid();
            resizeDialogToContent();
          }
          function onGarageStyleChange() {
            selectedGarageStyle = document.getElementById('garageStyle').value;
            var lbl = document.getElementById('garageDesignCurrentLabel');
            if (lbl) lbl.textContent = garageLabelFor(selectedGarageStyle);
            var fv = selectedGarageStyle === 'Full View Glass';
            document.getElementById('garageTopWindows').disabled = fv;
          }

          // ---- Front Door leaf designs ----
          var FRONT_DESIGNS = [
            'Craftsman 3-Lite', '5-Lite Ladder', 'Steel Glass',
            'Farmhouse 4-Lite', 'Modern Lines', 'Steel Arch'
          ];
          var selectedFrontStyle = 'Craftsman 3-Lite';

          function frontThumbSvg(name) {
            var s = '';
            switch (name) {
              case 'Craftsman 3-Lite':
                s = svgR(1, 1, 94, 238, '#c68a4b') +
                    svgR(16, 14, 18, 34, '#dce8ee') + svgR(39, 14, 18, 34, '#dce8ee') + svgR(62, 14, 18, 34, '#dce8ee') +
                    svgR(12, 56, 72, 5, '#b57a3e') +
                    svgR(16, 72, 29, 150, '#b57a3e') + svgR(51, 72, 29, 150, '#b57a3e');
                break;
              case '5-Lite Ladder':
                s = svgR(1, 1, 94, 238, '#f5f2ea');
                for (var i = 0; i < 5; i++) s += svgR(14, 14 + i * 44, 68, 34, '#e7edf0');
                break;
              case 'Steel Glass':
                s = svgR(1, 1, 94, 238, '#2c2c2a') + svgR(12, 12, 72, 216, '#cfdde5') +
                    '<line x1="48" y1="12" x2="48" y2="228" stroke="#8aa0ab" stroke-width="2"/>' +
                    '<line x1="12" y1="120" x2="84" y2="120" stroke="#8aa0ab" stroke-width="2"/>';
                break;
              case 'Farmhouse 4-Lite':
                s = svgR(1, 1, 94, 238, '#e8b45a') + svgR(14, 14, 68, 106, '#dce8ee') +
                    '<line x1="48" y1="14" x2="48" y2="120" stroke="#e8b45a" stroke-width="5"/>' +
                    '<line x1="14" y1="67" x2="82" y2="67" stroke="#e8b45a" stroke-width="5"/>' +
                    svgR(16, 136, 64, 88, '#dfab4f');
                break;
              case 'Modern Lines':
                s = svgR(1, 1, 94, 238, '#9a6b3f');
                for (var j = 0; j < 4; j++) s += '<line x1="10" y1="' + (52 + j * 46) + '" x2="86" y2="' + (52 + j * 46) + '" stroke="#6e4a28" stroke-width="3"/>';
                break;
              case 'Steel Arch':
                s = svgR(1, 1, 94, 238, '#efece5') +
                    '<path d="M 8 232 L 8 60 A 40 40 0 0 1 88 60 L 88 232 Z" fill="#1e1e1c" stroke="#777"/>' +
                    '<path d="M 15 225 L 15 62 A 33 33 0 0 1 81 62 L 81 225 Z" fill="#dfe9ee" stroke="#777"/>' +
                    '<line x1="48" y1="30" x2="48" y2="225" stroke="#1e1e1c" stroke-width="4"/>' +
                    '<line x1="15" y1="95" x2="81" y2="95" stroke="#1e1e1c" stroke-width="4"/>' +
                    '<line x1="15" y1="160" x2="81" y2="160" stroke="#1e1e1c" stroke-width="4"/>';
                break;
              default:
                s = svgR(1, 1, 94, 238, '#fbfaf7');
            }
            return '<svg viewBox="0 0 96 240">' + s + '</svg>';
          }
          function renderFrontDesignGrid() {
            var grid = document.getElementById('frontDesignGrid');
            if (!grid) return;
            var lbl = document.getElementById('frontDesignCurrentLabel');
            if (lbl) lbl.textContent = selectedFrontStyle;
            grid.innerHTML = FRONT_DESIGNS.map(function(name) {
              var sel = name === selectedFrontStyle ? ' selected' : '';
              return '<div class="design-card' + sel + '" data-style="' + name +
                     '" title="' + name + '" onclick="selectFrontDesign(this)">' +
                     frontThumbSvg(name) + '</div>';
            }).join('');
          }
          function selectFrontDesign(el) {
            selectedFrontStyle = el.getAttribute('data-style');
            toggleFrontDesignGrid(false);
          }
          function toggleFrontDesignGrid(force) {
            var g = document.getElementById('frontDesignGrid');
            var open = (typeof force === 'boolean') ? force : g.style.display === 'none';
            g.style.display = open ? 'grid' : 'none';
            document.getElementById('frontDesignArrow').innerHTML = open ? '&#9662;' : '&#9656;';
            renderFrontDesignGrid();
            resizeDialogToContent();
          }

          function onTransomToggle() {
            var hEl = document.getElementById('doorHeight');
            var h = parseFloat(hEl.value) || 80;
            var th = parseFloat(document.getElementById('transomHeight').value) || 14;
            var add = th + 1.5;
            if (document.getElementById('transomCheck').checked) {
              window._transomAdded = add;
              hEl.value = h + add;
            } else {
              hEl.value = h - (window._transomAdded || add);
              window._transomAdded = 0;
            }
          }

          function onFrontConfigChange() {
            if (!doorPlaceMode) return;
            var cfg = document.getElementById('frontConfig').value;
            var sl = parseFloat(document.getElementById('sideliteWidth').value) || 14;
            var w = 36 + 3;
            if (cfg === 'single_1sl') w += sl + 1.5;
            if (cfg === 'single_2sl') w += 2 * (sl + 1.5);
            if (cfg === 'double') w = 72 + 3;
            document.getElementById('doorWidth').value = w;
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
              leaf_style: selectedLeafStyle,
              closet_leaf_count: selectedClosetPanels,
              handle_style: (document.getElementById('handleStyle').value || 'none'),
              front_config: document.getElementById('frontConfig').value,
              front_leaf_style: selectedFrontStyle,
              garage_style: document.getElementById('garageStyle').value,
              garage_top_windows: document.getElementById('garageTopWindows').checked,
              front_glass_ratio: parseFloat(document.getElementById('frontGlassRatio').value) || 50,
              sidelite_width: parseFloat(document.getElementById('sideliteWidth').value) || 14,
              transom: document.getElementById('transomCheck').checked,
              transom_height: parseFloat(document.getElementById('transomHeight').value) || 14,
              door_color: (document.getElementById('doorColor').value || ''),
              frame_color: (document.getElementById('sameColorCheck').checked
                ? (document.getElementById('doorColor').value || '')
                : (document.getElementById('frameColor').value || '')),
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

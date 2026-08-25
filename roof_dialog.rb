# Interior Pro - Roof Dialog (2026-08-04)
# Settings panel for the roof: style (hip/flat), pitch, eaves (overhang),
# fascia board, metal drip edge, roof + fascia colors. Values load from and
# save to the model via RoofManager.settings / build_roof!.
module InteriorPro
  module RoofDialog

    # `roof` (2026-08-26, step 4 of Edit Roof): open the panel FOR THAT
    # ROOF - its own settings fill the controls, and Apply rebuilds it
    # alone via build_roof!(replace:). With no roof this is the plain
    # panel it always was, except that Apply now scopes itself to the top
    # storey, so a lower roof built with level: survives it.
    def self.show(roof = nil)
      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      @target = roof && roof.respond_to?(:valid?) && roof.valid? ? roof : nil
      # preferences_key makes SketchUp remember the last size, and once a
      # window has been maximised it comes back maximised forever - which
      # is what happened after the panel grew three rows (2026-08-10).
      # min/max box it in, and set_size below forces the small side panel
      # every time it opens, whatever is remembered.
      dlg = UI::HtmlDialog.new(
        dialog_title: @target ? 'Interior Pro - Edit Roof' : 'Interior Pro - Roof',
        preferences_key: 'InteriorPro_Roof',
        # 820 tall (2026-08-26): the panel grew a storey row, a soffit row
        # and a slope row, and the user scrolls for the Apply button
        # ("שכל החלון של הגגות יהיה פתוח ולא רק חלק ממנו"). Tall enough
        # for every row and both buttons with nothing folded away.
        # 760 (2026-08-28): the Trim section grew two gutter rows, and the
        # Colors section went away - every colour now stands beside the
        # thing it paints (user: "כל הצבעים תחלק אותם ליד כל העמודות שהם
        # שייכים אליהם"), which is three rows saved.
        width: 340, height: 760, resizable: true,
        min_width: 300, min_height: 380,
        max_width: 560, max_height: 1100
      )
      dlg.add_action_callback('apply_roof') do |_, style, pitch, eaves, overhang,
                                                fascia, fdepth, drip, rcol, fcol,
                                                rmat, thick, rcap,
                                                soffit, scol, sslope, rlevel,
                                                gutt, gprof, gwidth, gcol, dspout|
        # Which roof this Apply belongs to: the one the Edit tool clicked,
        # or none (the plain Roof button). Checked NOW, not at show time -
        # the roof the panel opened on may have been rebuilt or removed
        # while the panel sat open.
        tgt = @target && @target.respond_to?(:valid?) && @target.valid? ? @target : nil
        # SWITCHING to Hip = a clean full hip: the click marks go (user
        # decision 2026-08-05C). Toggle-clicks afterwards re-add gables.
        #
        # ONLY on the switch, though (2026-08-26). Before today this ran on
        # EVERY Apply while the radio sat on Hip - so building a hip,
        # clicking three ends into gables and then changing nothing but the
        # TILE threw the three gables away and handed back the plain hip.
        # The user: "אני רוצה להחליף סוג של רעפים... הוא מחזיר לי את הגג
        # לצורה המקורית שלו ולא שומר שינויים." Marking a gable does not
        # move the radio off Hip - the marks are a separate thing entirely -
        # so "the radio says hip" was never the question worth asking. The
        # question is whether this Apply CHANGED the style, and that is what
        # is asked now. Switch away to Gable and back to Hip and the old
        # clean-slate behaviour is still there, unchanged.
        #
        # With a target roof the comparison is against ITS style, and only
        # ITS OWN walls' marks are dropped - the other roofs' gables are
        # not this panel's to clear (step 4).
        cur = (tgt ? RoofManager.roof_settings(tgt) : RoofManager.settings)[:style].to_s
        if style.to_s == 'hip' && cur != 'hip'
          m = Sketchup.active_model
          if tgt
            own = RoofManager.roof_wall_ids(tgt)
            ids = RoofManager.gable_wall_ids
            pts = RoofManager.gable_click_points
            keep = (0...ids.length).reject { |i| own.include?(ids[i]) }
            m.set_attribute('InteriorPro', 'roof_gable_wall_ids',
                            keep.map { |i| ids[i] })
            m.set_attribute('InteriorPro', 'roof_gable_click_xy',
                            keep.flat_map { |i| pts[i] || [1e9, 1e9] })
          else
            m.set_attribute('InteriorPro', 'roof_gable_wall_ids', [])
            m.set_attribute('InteriorPro', 'roof_gable_click_xy', [])
          end
        end
        kw = {
          style: style.to_s,
          pitch: pitch.to_f > 0.01 ? pitch.to_f : nil,
          overhang: truthy(eaves) ? overhang.to_f : 0.0,
          fascia: truthy(fascia),
          fascia_depth: fdepth.to_f > 0.01 ? fdepth.to_f : nil,
          drip: truthy(drip),
          roof_color: rcol.to_s,
          fascia_color: fcol.to_s,
          roof_material: rmat.nil? ? nil : rmat.to_s,
          thickness: thick.nil? ? nil : thick.to_f,
          ridge_cap: rcap.nil? ? nil : truthy(rcap),
          soffit: soffit.nil? ? nil : soffit.to_s,
          # '' on purpose, not nil: an empty string is the way to CLEAR a
          # colour that was picked before and go back to the texture. nil
          # would leave the old override in the model for ever.
          soffit_color: scol.nil? ? nil : scol.to_s,
          # LAST on purpose, same reason the two above are: a saved model
          # or an old console line that calls apply_roof with 14 arguments
          # still lands, and sslope simply arrives nil.
          soffit_slope: sslope.nil? ? nil : truthy(sslope),
          # THE GUTTER (2026-08-28), appended for the same reason - nil
          # from a shorter call means "leave it alone", NOT "switch it
          # off", which is why this is not a bare truthy().
          gutter: gutt.nil? ? nil : truthy(gutt),
          gutter_profile: gprof.nil? || gprof.to_s.empty? ? nil : gprof.to_s,
          gutter_width: gwidth.nil? ? nil : gwidth.to_f,
          # '' on purpose, exactly like soffit_color: an empty string is
          # how a picked colour is CLEARED and the gutter goes back to
          # following the fascia. nil is the older-call case and means
          # leave whatever is saved.
          gutter_color: gcol.nil? ? nil : gcol.to_s,
          downspouts: dspout.nil? ? nil : truthy(dspout)
        }
        # WHERE the roof goes (2026-08-26, step 5 - the storey picker,
        # user: "איך אני בוחר קומה ראשונה או שניה או שניהם?"):
        #   editing        - the clicked roof, wherever it lives;
        #   a storey number - that storey alone;
        #   'all'          - one roof per storey that has walls, top first;
        #   nothing (an old call with 15 arguments) - the top storey,
        #   which is everything the plain panel ever built.
        built =
          if tgt
            RoofManager.build_roof!(**kw, replace: tgt)
          elsif rlevel.to_s == 'all'
            RoofManager.wall_levels.reverse.map do |lv|
              RoofManager.build_roof!(**kw, level: lv)
            end.compact.last
          elsif rlevel.to_s =~ /\A\d+\z/
            RoofManager.build_roof!(**kw, level: rlevel.to_i)
          else
            RoofManager.build_roof!(**kw, level: RoofManager.top_level)
          end
        # the rebuild made a NEW group - keep editing that one, so a
        # second Apply from the same open panel still hits this roof
        @target = built if tgt && built
      end
      # Remove: the clicked roof alone from the Edit panel, everything from
      # the plain one - exactly the scope the panel itself has.
      dlg.add_action_callback('remove_roof') do |_|
        t = @target && @target.respond_to?(:valid?) && @target.valid? ? @target : nil
        if t
          Sketchup.active_model.start_operation('InteriorPro Remove Roof', true)
          t.erase!
          Sketchup.active_model.commit_operation
          @target = nil
        else
          RoofManager.remove_all!
        end
      end
      dlg.set_html(build_html(@target ? RoofManager.roof_settings(@target)
                                      : RoofManager.settings,
                              edit: !@target.nil?))
      begin
        dlg.set_size(340, 760)
        dlg.center if dlg.respond_to?(:center)
      rescue StandardError => e
        puts "[Roof] dialog size: #{e.message}"
      end
      dlg.show
      @dialog = dlg
    end

    def self.truthy(v)
      v == true || v.to_s == 'true'
    end

    # `edit:` - the panel opened on one clicked roof: that roof already
    # knows its storey, so the storey row is not drawn at all.
    def self.build_html(s, edit: false)
      # The storey picker (2026-08-26, step 5). Only when there is a
      # choice to make: two storeys or more, and not in edit mode. One
      # storey = the row is not drawn and Apply behaves exactly as ever.
      lvls = RoofManager.wall_levels
      level_row = ''
      if !edit && lvls.length > 1
        top = lvls.max
        opts = lvls.reverse.map do |lv|
          label = lv == top ? "Storey #{lv} (top)" : "Storey #{lv}"
          "<option value=\"#{lv}\">#{label}</option>"
        end.join
        # All storeys is the default (user 2026-08-26) - with two storeys
        # in the model, one Apply roofs the whole building.
        opts += '<option value="all" selected>All storeys (one roof each)</option>'
        level_row = '<div class="section-title">Storey</div>' \
                    "<div class=\"row\"><label>Build over</label>" \
                    "<select id=\"roofLevel\">#{opts}</select></div>"
      end
      pitch_options = (2..12).map do |p|
        sel = (s[:pitch].round - p).zero? ? ' selected' : ''
        "<option value=\"#{p}\"#{sel}>#{p}:12</option>"
      end.join
      # The colour picker below tints whatever is chosen here, so one
      # greyscale tile covers every shingle colour (2026-08-10).
      mat_options = [['color',   'Solid color'],
                     ['shingle', 'Shingles'],
                     # Barrel Tile was dropped from the menu on 2026-08-21 -
                     # Spanish Tile below is the shape it was standing in for,
                     # and two entries for one look is exactly the duplicate
                     # the UI rules in CLAUDE.md exist to prevent. The shape
                     # itself is still in RoofTileMath, so nothing that reads
                     # a saved model breaks.
                     ['roman',   'Roman Tile (flat pan)'],
                     ['slate',   'Flat Slate Tile'],
                     ['seam',    'Standing Seam Metal'],
                     ['metaltile', 'Spanish Tile']].map do |v, t|
        sel = s[:roof_material].to_s == v ? ' selected' : ''
        "<option value=\"#{v}\"#{sel}>#{t}</option>"
      end.join
      soffit_options = [['none',   'None'],
                        ['boxed',  'Boxed (painted)'],
                        ['wood',   'Wood'],
                        ['stucco', 'Stucco'],
                        ['beams',  'Exposed beams'],
                        ['spanish', 'Spanish (stucco + tails)']].map do |v, t|
        sel = s[:soffit].to_s == v ? ' selected' : ''
        "<option value=\"#{v}\"#{sel}>#{t}</option>"
      end.join
      # A colour input ALWAYS has a value, so "leave it to the texture"
      # cannot be one of its values - it has to be a flag beside it. The
      # flag starts on only if a colour really was saved last time; picking
      # one turns it on, and until then the swatch just previews the style's
      # own default. No second checkbox: the UI rules in CLAUDE.md say a
      # control that an existing one already covers does not get built.
      gutter_options = [['k',     'K-Style (ogee)'],
                        ['round', 'Half round'],
                        ['box',   'Square']].map do |v, t|
        sel = s[:gutter_profile].to_s == v ? ' selected' : ''
        "<option value=\"#{v}\"#{sel}>#{t}</option>"
      end.join
      gutter_picked = s[:gutter_color].to_s.start_with?('#')
      gutter_col = gutter_picked ? s[:gutter_color].to_s : s[:fascia_color].to_s
      soffit_picked = s[:soffit_color].to_s.start_with?('#')
      soffit_col = soffit_picked ? s[:soffit_color].to_s
                   : (RoofManager.soffit_colors[s[:soffit].to_s] || s[:fascia_color].to_s)
      soffit_defs = RoofManager.soffit_colors.reject { |_, v| v.nil? }
                               .map { |k, v| "\"#{k}\":\"#{v}\"" }.join(',')
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
          body { font-family: Arial, sans-serif; font-size: 13px; margin: 12px; background: #fff; }
          .section-title { font-weight: bold; margin: 12px 0 6px; color: #37474f; }
          .row { margin: 7px 0; color: #333; display: flex; align-items: center; gap: 8px; }
          .row label { flex: 1; }
          .row input[type=number], .row select { width: 84px; padding: 4px; }
          .row input[type=color] { width: 48px; height: 26px; padding: 0; border: 1px solid #bbb; }
          .sub { margin-left: 22px; }
          button { width: 100%; padding: 10px; margin-top: 12px; border: none; border-radius: 6px;
                   background: #37474f; color: #fff; font-size: 14px; cursor: pointer; }
          button.secondary { background: #9e9e9e; }
        </style></head><body>
          #{level_row}
          <div class="section-title">Roof Type</div>
          <div class="row">
            <label><input type="radio" name="style" value="hip"#{%w[flat gable].include?(s[:style]) ? '' : ' checked'} onchange="styleChanged()"> Hip</label>
            <label><input type="radio" name="style" value="gable"#{s[:style] == 'gable' ? ' checked' : ''} onchange="styleChanged()"> Gable</label>
            <label><input type="radio" name="style" value="flat"#{s[:style] == 'flat' ? ' checked' : ''} onchange="styleChanged()"> Flat</label>
          </div>
          <div class="row"><label>Pitch (rise : 12)</label>
            <select id="pitch">#{pitch_options}</select></div>

          <div class="section-title">Eaves</div>
          <div class="row"><label><input type="checkbox" id="eaves"#{s[:overhang] > 0.01 ? ' checked' : ''} onchange="eavesChanged()"> Eaves (overhang)</label>
            <input type="number" id="overhang" step="1" min="0" value="#{s[:overhang] > 0.01 ? s[:overhang] : RoofManager::DEFAULT_OVERHANG}"> in</div>

          <div class="section-title">Trim</div>
          <div class="row"><label><input type="checkbox" id="fascia"#{s[:fascia] ? ' checked' : ''}> Fascia board</label>
            <input type="number" id="fasciaDepth" step="0.25" min="1" value="#{s[:fascia_depth]}"> in
            <input type="color" id="fasciaColor" value="#{s[:fascia_color]}"></div>
          <div class="row"><label><input type="checkbox" id="drip"#{s[:drip] ? ' checked' : ''}> Metal drip edge</label></div>
          <div class="row"><label><input type="checkbox" id="gutter"#{s[:gutter] ? ' checked' : ''} onchange="gutterChanged()"> Gutter (eaves only)</label>
            <select id="gutterProfile" style="width:112px">#{gutter_options}</select></div>
          <div class="row sub"><label>Gutter size</label>
            <input type="number" id="gutterWidth" step="0.5" min="3" max="9" value="#{s[:gutter_width]}"> in
            <input type="color" id="gutterColor" value="#{gutter_col}" oninput="gutterPicked()"></div>
          <div class="row sub"><label><input type="checkbox" id="downspouts"#{s[:downspouts] ? ' checked' : ''}> Downspouts (one per corner)</label></div>
          <div class="row"><label>Soffit</label>
            <select id="soffit" onchange="soffitChanged()">#{soffit_options}</select>
            <input type="color" id="soffitColor" value="#{soffit_col}" oninput="soffitPicked()"></div>
          <div class="row sub"><label><input type="checkbox" id="soffitSlope"#{s[:soffit_slope] ? ' checked' : ''}> Sloped (follows the roof)</label></div>

          <div class="section-title">Surface</div>
          <div class="row"><label>Roof material</label>
            <select id="roofMat" style="width:112px">#{mat_options}</select>
            <input type="color" id="roofColor" value="#{s[:roof_color]}"></div>
          <div class="row"><label>Roof thickness</label>
            <input type="number" id="thickness" step="0.25" min="0" value="#{s[:thickness]}"> in</div>
          <div class="row"><label><input type="checkbox" id="ridgeCap"#{s[:ridge_cap] ? ' checked' : ''}> Ridge cap</label></div>


          <button onclick="applyRoof()">Apply - Build Roof</button>
          <button class="secondary" onclick="sketchup.remove_roof()">Remove Roof</button>
          <script>
            function styleChanged() {
              var flat = document.querySelector('input[name=style]:checked').value === 'flat';
              document.getElementById('pitch').disabled = flat;
            }
            function eavesChanged() {
              document.getElementById('overhang').disabled = !document.getElementById('eaves').checked;
            }
            var gutterPickedFlag = #{gutter_picked ? 'true' : 'false'};
            function gutterPicked() { gutterPickedFlag = true; }
            function gutterChanged() {
              var on = document.getElementById('gutter').checked;
              document.getElementById('gutterProfile').disabled = !on;
              document.getElementById('gutterWidth').disabled = !on;
              document.getElementById('gutterColor').disabled = !on;
              document.getElementById('downspouts').disabled = !on;
            }
            var SOFFIT_DEF = {#{soffit_defs}};
            var soffitPickedFlag = #{soffit_picked ? 'true' : 'false'};
            function soffitPicked() { soffitPickedFlag = true; }
            function soffitChanged() {
              var v = document.getElementById('soffit').value;
              var c = document.getElementById('soffitColor');
              c.disabled = (v === 'none');
              document.getElementById('soffitSlope').disabled = (v === 'none');
              if (!soffitPickedFlag && SOFFIT_DEF[v]) { c.value = SOFFIT_DEF[v]; }
            }
            function applyRoof() {
              sketchup.apply_roof(
                document.querySelector('input[name=style]:checked').value,
                document.getElementById('pitch').value,
                document.getElementById('eaves').checked,
                document.getElementById('overhang').value,
                document.getElementById('fascia').checked,
                document.getElementById('fasciaDepth').value,
                document.getElementById('drip').checked,
                document.getElementById('roofColor').value,
                document.getElementById('fasciaColor').value,
                document.getElementById('roofMat').value,
                document.getElementById('thickness').value,
                document.getElementById('ridgeCap').checked,
                document.getElementById('soffit').value,
                soffitPickedFlag ? document.getElementById('soffitColor').value : '',
                document.getElementById('soffitSlope').checked,
                (function () { var lv = document.getElementById('roofLevel');
                               return lv ? lv.value : ''; })(),
                document.getElementById('gutter').checked,
                document.getElementById('gutterProfile').value,
                document.getElementById('gutterWidth').value,
                gutterPickedFlag ? document.getElementById('gutterColor').value : '',
                document.getElementById('downspouts').checked);
            }
            styleChanged();
            eavesChanged();
            gutterChanged();
            soffitChanged();
          </script>
        </body></html>
      HTML
    end

  end
end

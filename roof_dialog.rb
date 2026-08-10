# Interior Pro - Roof Dialog (2026-08-04)
# Settings panel for the roof: style (hip/flat), pitch, eaves (overhang),
# fascia board, metal drip edge, roof + fascia colors. Values load from and
# save to the model via RoofManager.settings / build_roof!.
module InteriorPro
  module RoofDialog

    def self.show
      if @dialog
        begin; @dialog.close; rescue StandardError; end
        @dialog = nil
      end
      # preferences_key makes SketchUp remember the last size, and once a
      # window has been maximised it comes back maximised forever - which
      # is what happened after the panel grew three rows (2026-08-10).
      # min/max box it in, and set_size below forces the small side panel
      # every time it opens, whatever is remembered.
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Roof',
        preferences_key: 'InteriorPro_Roof',
        width: 340, height: 640, resizable: true,
        min_width: 300, min_height: 380,
        max_width: 560, max_height: 1000
      )
      dlg.add_action_callback('apply_roof') do |_, style, pitch, eaves, overhang,
                                                fascia, fdepth, drip, rcol, fcol,
                                                rmat, thick, rcap|
        # Apply in Hip mode = a clean full hip: clear click marks (user
        # decision 2026-08-05C). Toggle-clicks afterwards re-add gables.
        if style.to_s == 'hip'
          m = Sketchup.active_model
          m.set_attribute('InteriorPro', 'roof_gable_wall_ids', [])
          m.set_attribute('InteriorPro', 'roof_gable_click_xy', [])
        end
        RoofManager.build_roof!(
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
          ridge_cap: rcap.nil? ? nil : truthy(rcap)
        )
      end
      dlg.add_action_callback('remove_roof') { |_| RoofManager.remove_all! }
      dlg.set_html(build_html(RoofManager.settings))
      begin
        dlg.set_size(340, 640)
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

    def self.build_html(s)
      pitch_options = (2..12).map do |p|
        sel = (s[:pitch].round - p).zero? ? ' selected' : ''
        "<option value=\"#{p}\"#{sel}>#{p}:12</option>"
      end.join
      # The colour picker below tints whatever is chosen here, so one
      # greyscale tile covers every shingle colour (2026-08-10).
      mat_options = [['color', 'Solid color'], ['shingle', 'Shingles']].map do |v, t|
        sel = s[:roof_material].to_s == v ? ' selected' : ''
        "<option value=\"#{v}\"#{sel}>#{t}</option>"
      end.join
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
            <input type="number" id="fasciaDepth" step="0.25" min="1" value="#{s[:fascia_depth]}"> in</div>
          <div class="row"><label><input type="checkbox" id="drip"#{s[:drip] ? ' checked' : ''}> Metal drip edge</label></div>

          <div class="section-title">Surface</div>
          <div class="row"><label>Roof material</label>
            <select id="roofMat">#{mat_options}</select></div>
          <div class="row"><label>Roof thickness</label>
            <input type="number" id="thickness" step="0.25" min="0" value="#{s[:thickness]}"> in</div>
          <div class="row"><label><input type="checkbox" id="ridgeCap"#{s[:ridge_cap] ? ' checked' : ''}> Ridge cap</label></div>

          <div class="section-title">Colors</div>
          <div class="row"><label>Roof color</label>
            <input type="color" id="roofColor" value="#{s[:roof_color]}"></div>
          <div class="row"><label>Fascia color</label>
            <input type="color" id="fasciaColor" value="#{s[:fascia_color]}"></div>

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
                document.getElementById('ridgeCap').checked);
            }
            styleChanged();
            eavesChanged();
          </script>
        </body></html>
      HTML
    end

  end
end

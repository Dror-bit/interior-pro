# Interior Pro - Dormer Dialog (2026-09-02, step 4 of the dormer)
#
# The panel behind the Dormer toolbar button. It holds the numbers the
# user said he wants to type - WIDTH, LENGTH into the roof, SETBACK from
# the eave - plus the overhang, the gablet's own pitch and the fascia
# depth. "Place on roof" saves them on the model and hands over to
# DormerTool, which draws the ghost and takes the click.
#
# TWO ZEROES MEAN "FOLLOW THE HOUSE", and they are zeroes and not blanks
# so a number input always holds a number:
#   pitch 0        - the gablet takes the main roof's own pitch.
#   fascia depth 0 - the dormer wears the house's own fascia depth.
#
# THE STYLE ROW is here from the start, but only Gable is built today.
# Hip, Shed and Flat are the next three steps and their buttons say so
# rather than pretending.
module InteriorPro
  module DormerDialog
    BUILT_STYLES = %w[gable].freeze unless const_defined?(:BUILT_STYLES, false)

    def self.show
      if @dialog
        begin
          @dialog.close
        rescue StandardError
          nil
        end
        @dialog = nil
      end
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Interior Pro - Dormer',
        preferences_key: 'InteriorPro_Dormer',
        # Wide enough that no control is clipped and nothing needs
        # scrolling sideways (the user, 2026-09-02: "תוודא שכל
        # האופציות פתוחות ואני לא צריך לגלל").
        width: 430, height: 560, resizable: true,
        min_width: 400, min_height: 480,
        max_width: 560, max_height: 900
      )
      dlg.add_action_callback('place_dormer') do |_, style, width, length,
                                                  setback, overhang, pitch12,
                                                  fdepth|
        s = { style: BUILT_STYLES.include?(style.to_s) ? style.to_s : 'gable',
              width: width.to_f, length: length.to_f, setback: setback.to_f,
              overhang: overhang.to_f, pitch12: pitch12.to_f,
              fascia_depth: fdepth.to_f }
        InteriorPro::DormerManager.save_settings!(s)
        Sketchup.active_model.select_tool(InteriorPro::DormerTool.new)
      end
      dlg.set_html(build_html(InteriorPro::DormerManager.settings))
      begin
        dlg.set_size(430, 560)
        dlg.center if dlg.respond_to?(:center)
      rescue StandardError => e
        puts "[Dormer] dialog size: #{e.message}"
      end
      dlg.show
      @dialog = dlg
    end

    def self.build_html(s)
      pitch_options = ['<option value="0"' +
                       (s[:pitch12].to_f > 0.01 ? '' : ' selected') +
                       '>Same as roof</option>']
      pitch_options += (2..16).map do |p|
        sel = (s[:pitch12].to_f - p).abs < 0.01 ? ' selected' : ''
        "<option value=\"#{p}\"#{sel}>#{p}:12</option>"
      end
      pitch_options = pitch_options.join
      styles = [['gable', 'Gable'], ['hip', 'Hip'],
                ['shed', 'Shed'], ['flat', 'Flat']].map do |v, t|
        built = BUILT_STYLES.include?(v)
        chk = s[:style].to_s == v && built ? ' checked' : ''
        dis = built ? '' : ' disabled'
        note = built ? '' : ' <span class="soon">next</span>'
        "<label#{built ? '' : ' class="off"'}><input type=\"radio\" " \
          "name=\"style\" value=\"#{v}\"#{chk}#{dis}> #{t}#{note}</label>"
      end.join
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
          body { font-family: Arial, sans-serif; font-size: 13px; margin: 12px; background: #fff; }
          .section-title { font-weight: bold; margin: 12px 0 6px; color: #37474f; }
          .row { margin: 7px 0; color: #333; display: flex; align-items: center; gap: 8px; }
          .row label { flex: 1; }
          .row input[type=number] { width: 88px; padding: 4px; }
          .row select { width: 150px; padding: 4px; }
          .styles label { flex: none; margin-right: 10px; }
          .styles label.off { color: #9e9e9e; }
          .soon { font-size: 11px; color: #b0bec5; }
          .hint { color: #78909c; font-size: 12px; margin-top: 6px; }
          button { width: 100%; padding: 10px; margin-top: 14px; border: none; border-radius: 6px;
                   background: #37474f; color: #fff; font-size: 14px; cursor: pointer; }
        </style></head><body>
          <div class="section-title">Gablet</div>
          <div class="row styles">#{styles}</div>
          <div class="row"><label>Pitch (rise : 12)</label>
            <select id="pitch">#{pitch_options}</select></div>

          <div class="section-title">Size</div>
          <div class="row"><label>Width (across the roof)</label>
            <input type="number" id="width" step="1" min="12" value="#{s[:width].round}"> in</div>
          <div class="row"><label>Length (into the roof)</label>
            <input type="number" id="length" step="1" min="12" value="#{s[:length].round}"> in</div>
          <div class="row"><label>Setback from the eave</label>
            <input type="number" id="setback" step="1" min="0" value="#{s[:setback].round}"> in</div>

          <div class="section-title">Eaves and trim</div>
          <div class="row"><label>Overhang</label>
            <input type="number" id="overhang" step="1" min="0" value="#{s[:overhang].round}"> in</div>
          <div class="row"><label>Fascia depth (0 = like the house)</label>
            <input type="number" id="fasciaDepth" step="0.25" min="0" value="#{s[:fascia_depth]}"> in</div>

          <button onclick="placeDormer()">Place on roof</button>
          <div class="hint">Then hover a roof slope - the whole dormer is drawn
            where it would land - and click once to build it. Esc cancels.</div>
          <div class="hint">The front wall height is not typed: the gablet dies
            into the roof at the end of its length, so the height falls out of
            the width, the length and the pitch.</div>
          <script>
            function placeDormer() {
              sketchup.place_dormer(
                document.querySelector('input[name=style]:checked').value,
                document.getElementById('width').value,
                document.getElementById('length').value,
                document.getElementById('setback').value,
                document.getElementById('overhang').value,
                document.getElementById('pitch').value,
                document.getElementById('fasciaDepth').value);
            }
          </script>
        </body></html>
      HTML
    end
  end
end

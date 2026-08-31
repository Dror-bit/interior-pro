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
# HE TYPES THE WALL HEIGHT, NOT THE LENGTH (2026-09-02: "האורך לתוך הגג
# לא רלוונטי לי"). A window goes in that wall, so the height is the
# number he cares about; how far the gablet reaches into the roof falls
# out of it, and it is refused outright if it would climb to within a
# foot of the house's own ridge.
#
# THE STYLE ROW: all four are built - Gable, Hip, Shed, Flat.
# A shed's pitch must be FLATTER than the roof's - that is what makes it
# climb out instead of diving under - and "Same as roof" hands it half
# the roof's own pitch. A flat gablet has no pitch at all, so the
# control is disabled for it.
module InteriorPro
  module DormerDialog
    # A METHOD, NOT A CONSTANT, and for the reason written all over this
    # project: `X = ... unless const_defined?` is NOT re-read by
    # InteriorPro.reload!, so the day Shed was finished the panel still
    # showed it greyed out (the user, 2026-09-02: "הוא לא נותן לי ללחוץ
    # על שד"). Every list that grows step by step has to be a method.
    def self.built_styles
      %w[gable hip shed flat]
    end

    # `target` (2026-09-02): the panel opened ON one dormer by the Edit
    # tool. Its own numbers fill the controls and the button rebuilds
    # THAT dormer where it stands, instead of starting a placing tool.
    def self.show(target = nil)
      @target = target && target.respond_to?(:valid?) && target.valid? ? target : nil
      if @dialog
        begin
          @dialog.close
        rescue StandardError
          nil
        end
        @dialog = nil
      end
      dlg = UI::HtmlDialog.new(
        dialog_title: @target ? 'Interior Pro - Edit Dormer' : 'Interior Pro - Dormer',
        preferences_key: 'InteriorPro_Dormer',
        # Wide enough that no control is clipped and nothing needs
        # scrolling sideways (the user, 2026-09-02: "תוודא שכל
        # האופציות פתוחות ואני לא צריך לגלל").
        width: 430, height: 700, resizable: true,
        min_width: 400, min_height: 420,
        max_width: 560, max_height: 1000
      )
      # IT OPENS WHOLE (2026-09-06). He sent two shots of the panel with a
      # scrollbar down the side and the Place button cut in half: "אני רוצה
      # שהוא יפתח כולו". A typed height cannot know - the panel is taller
      # in Edit than in Place, and taller again when the depth row shows -
      # so the PAGE measures itself and the window follows.
      dlg.add_action_callback('fit_height') do |_, h|
        begin
          want = h.to_i + 46            # title bar + frame
          want = 420 if want < 420
          want = 1000 if want > 1000
          dlg.set_size(430, want)
        rescue StandardError => e
          puts "[Dormer] fit_height: #{e.message}"
        end
      end
      dlg.add_action_callback('place_dormer') do |_, style, width, height,
                                                  setback, overhang, pitch12,
                                                  fdepth, mode, win, wcol|
        old = InteriorPro::DormerManager.settings
        s = { style: built_styles.include?(style.to_s) ? style.to_s : 'gable',
              width: width.to_f, height: height.to_f, length: old[:length],
              setback: setback.to_s.empty? ? old[:setback] : setback.to_f,
              overhang: overhang.to_f, pitch12: pitch12.to_f,
              fascia_depth: fdepth.to_f,
              place_mode: %w[free depth flush].include?(mode.to_s) ?
                          mode.to_s : 'free',
              # HIS OPTION, ON THE PANEL (2026-09-06): "בסרגל של הגגונים
              # תהיה אופציה עם חלון או בלי חלון".
              window: !%w[false 0 off].include?(win.to_s.downcase),
              # '' = leave the frame as WindowTool builds it (white).
              # Anything else is a colour he picked (2026-09-09).
              window_color: wcol.to_s.start_with?('#') ? wcol.to_s : '' }
        InteriorPro::DormerManager.save_settings!(s)
        tgt = @target && @target.respond_to?(:valid?) && @target.valid? ? @target : nil
        if tgt
          model = Sketchup.active_model
          model.start_operation('Edit Dormer', true)
          g = InteriorPro::DormerManager.replace_dormer!(
            tgt,
            style: s[:style], width: s[:width], height: s[:height],
            overhang: s[:overhang],
            pitch: s[:pitch12].to_f > 0.01 ? s[:pitch12].to_f / 12.0 : nil,
            fascia_depth: s[:fascia_depth].to_f > 0.01 ? s[:fascia_depth].to_f : nil,
            # WHERE IT SITS, ON AN EDIT TOO (2026-09-06). Until now the
            # panel sent only sizes, so a typed "depth from the fascia"
            # did nothing and the mode was forgotten. Only 'depth' can
            # move a standing dormer from a dialog - 'free' needs a click
            # and 'flush' is already where it was put - so the other two
            # change the remembered mode and leave the dormer where it is.
            place_mode: s[:place_mode].to_s,
            setback: s[:place_mode].to_s == 'depth' ? s[:setback].to_f : nil,
            window: s[:window] ? true : false,
            window_color: s[:window_color].to_s
          )
          model.commit_operation
          if g.nil?
            why = InteriorPro::DormerManager.last_reason
            UI.messagebox(why ? "This dormer #{why}" :
                          'That change could not be built - see the Ruby Console.')
          else
            @target = g
          end
        else
          Sketchup.active_model.select_tool(InteriorPro::DormerTool.new)
        end
      end
      dlg.set_html(build_html(panel_values, edit: !@target.nil?))
      begin
        dlg.set_size(430, 700)
        dlg.center if dlg.respond_to?(:center)
      rescue StandardError => e
        puts "[Dormer] dialog size: #{e.message}"
      end
      dlg.show
      @dialog = dlg
    end

    # The numbers the panel shows: the dormer's own when editing one,
    # otherwise the last ones used.
    def self.panel_values
      base = InteriorPro::DormerManager.settings
      return base if @target.nil?
      sp = InteriorPro::DormerManager.dormer_spec(@target)
      return base if sp.nil?
      p12 = (sp[:pitch].to_f - sp[:slope].to_f).abs < 0.001 ? 0.0 :
            (sp[:pitch].to_f * 12.0).round
      base.merge(width: sp[:width], overhang: sp[:overhang],
                 style: sp[:style], pitch12: p12,
                 height: @target.get_attribute('InteriorPro', 'height').to_f,
                 fascia_depth: sp[:fascia_depth].to_f,
                 setback: sp[:setback].to_f,
                 place_mode: (sp[:place_mode] || base[:place_mode]).to_s,
                 window: sp.key?(:window) ? sp[:window] : base[:window],
                 window_color: sp.key?(:window_color) ?
                               sp[:window_color].to_s : base[:window_color])
    end

    def self.build_html(s, edit: false)
      # The frame colour: '' means "as WindowTool built it" (white), and a
      # colour input cannot hold that - so the swatch previews white and a
      # flag beside it remembers whether he actually picked (2026-09-09,
      # the same pattern as the roof panel's soffit colour).
      win_picked = s[:window_color].to_s.start_with?('#')
      win_col = win_picked ? s[:window_color].to_s : '#ffffff'
      pitch_options = ['<option value="0"' +
                       (s[:pitch12].to_f > 0.01 ? '' : ' selected') +
                       '>Same as roof</option>']
      pitch_options += (2..16).map do |p|
        sel = (s[:pitch12].to_f - p).abs < 0.01 ? ' selected' : ''
        "<option value=\"#{p}\"#{sel}>#{p}:12</option>"
      end
      pitch_options = pitch_options.join
      # SAME ORDER AS THE ROOF PANEL (2026-09-02, the user: "תעשה את סדר
      # הגגות בדורמר כמו בגגות"): Hip, Gable, Flat, Shed. One place in
      # the plugin, one order.
      # WHERE IT SITS - his three (2026-09-02B): "1- להציב איפה שרוצים
      # 2- מידה/מרחק מסוף הגג ... 3- פלש עם הקיר".
      modes = [['free', 'Click anywhere'],
               ['depth', 'Depth from the fascia'],
               ['flush', 'Flush with the wall']].map do |v, t|
        chk = (s[:place_mode].to_s == v) ||
              (s[:place_mode].to_s.empty? && v == 'free') ? ' checked' : ''
        "<label><input type=\"radio\" name=\"pmode\" " \
          "value=\"#{v}\"#{chk}> #{t}</label>"
      end.join
      styles = [['hip', 'Hip'], ['gable', 'Gable'],
                ['flat', 'Flat'], ['shed', 'Shed']].map do |v, t|
        built = built_styles.include?(v)
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
          .placing { flex-wrap: wrap; }
          .placing label { flex: none; margin-right: 12px; }
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
          <div class="hint" id="shedHint" style="display:none">A shed must be
            FLATTER than the roof - "Same as roof" gives it half the roof's
            pitch.</div>
          <div class="hint" id="flatHint" style="display:none">A flat gablet has
            no pitch at all: its deck is level, so its height is simply how far
            it reaches into the roof times the roof's own pitch.</div>

          <div class="section-title">Where it sits</div>
          <div class="row placing">#{modes}</div>
          <div class="row" id="depthRow"><label>Depth from the fascia</label>
            <input type="number" id="setback" step="1" min="0" value="#{s[:setback].round}"> in</div>
          <div class="hint" id="placeHint"></div>

          <div class="section-title">Window</div>
          <div class="row"><label>A window in the front wall</label>
            <input type="checkbox" id="hasWindow"#{s[:window] ? ' checked' : ''}></div>
          <div class="hint">Centred, at most 48" x 24". On a smaller gablet it
            keeps 6" clear on every side and never runs into the cheeks.</div>
          <div class="row"><label>Frame colour</label>
            <input type="color" id="winColor" value="#{win_col}"
                   oninput="winPicked()"></div>

          <div class="section-title">Size</div>
          <div class="row"><label>Width (across the roof)</label>
            <input type="number" id="width" step="1" min="12" value="#{s[:width].round}"> in</div>
          <div class="row"><label>Front wall height</label>
            <input type="number" id="height" step="1" min="12" value="#{(s[:height] > 0.01 ? s[:height] : 36.0).round}"> in</div>
          <div class="hint">How far it reaches into the roof follows from
            this. It stops you a foot short of the house ridge.</div>

          <div class="section-title">Eaves and trim</div>
          <div class="row"><label>Overhang</label>
            <input type="number" id="overhang" step="1" min="0" value="#{s[:overhang].round}"> in</div>
          <div class="row"><label>Fascia depth (0 = like the house)</label>
            <input type="number" id="fasciaDepth" step="0.25" min="0" value="#{s[:fascia_depth]}"> in</div>

          <button onclick="placeDormer()">#{edit ? 'Apply to this dormer' : 'Place on roof'}</button>
          #{edit ? '<div class="hint">This rebuilds the dormer you clicked, ' \
                   'where it stands. Move it with the Move Dormer button.</div>'
                 : '<div class="hint">Then hover a roof slope - the whole ' \
                   'dormer is drawn where it would land - and click once to ' \
                   'build it. The status bar says where it will sit. ' \
                   'Esc cancels.</div>'}
          <div class="hint">The gablet always dies into the roof at the end of
            its own length, so the length is what the height, the width and the
            pitch produce - never a fourth number that can argue with them.</div>
          <script>
            function styleChanged() {
              var v = document.querySelector('input[name=style]:checked').value;
              document.getElementById('shedHint').style.display =
                (v === 'shed') ? 'block' : 'none';
              document.getElementById('flatHint').style.display =
                (v === 'flat') ? 'block' : 'none';
              // a flat gablet HAS no pitch - the control would be a lie
              document.getElementById('pitch').disabled = (v === 'flat');
              fitWindow();
            }
            function modeChanged() {
              var v = document.querySelector('input[name=pmode]:checked').value;
              document.getElementById('depthRow').style.display =
                (v === 'depth') ? 'flex' : 'none';
              var h = {
                free: 'The click sets how far up the slope it sits.',
                depth: 'The mouse only slides it sideways - the depth stays what you typed.',
                flush: 'Its front wall lands in the plane of the house wall. The mouse only slides it sideways.'
              };
              document.getElementById('placeHint').textContent = h[v];
              fitWindow();
            }
            var winPickedFlag = #{win_picked ? 'true' : 'false'};
            function winPicked() { winPickedFlag = true; }
            function placeDormer() {
              sketchup.place_dormer(
                document.querySelector('input[name=style]:checked').value,
                document.getElementById('width').value,
                document.getElementById('height').value,
                document.getElementById('setback').value,
                document.getElementById('overhang').value,
                document.getElementById('pitch').value,
                document.getElementById('fasciaDepth').value,
                document.querySelector('input[name=pmode]:checked').value,
                document.getElementById('hasWindow').checked ? 'true' : 'false',
                winPickedFlag ? document.getElementById('winColor').value : '');
            }
            Array.prototype.forEach.call(
              document.querySelectorAll('input[name=style]'),
              function (r) { r.addEventListener('change', styleChanged); });
            Array.prototype.forEach.call(
              document.querySelectorAll('input[name=pmode]'),
              function (r) { r.addEventListener('change', modeChanged); });
            function fitWindow() {
              if (window.sketchup && sketchup.fit_height) {
                var b = document.body;
                var d = document.documentElement;
                sketchup.fit_height(Math.max(b.scrollHeight, b.offsetHeight,
                                             d.scrollHeight, d.offsetHeight));
              }
            }
            styleChanged();
            modeChanged();
            fitWindow();
            window.addEventListener('load', fitWindow);
          </script>
        </body></html>
      HTML
    end
  end
end

# Interior Pro - Skylight Dialog (2026-09-14)
#
# The small panel behind the Skylight button: width across the slope,
# height up it, and the frame colour. "Place on roof" saves the three and
# hands over to SkylightTool, which draws the rectangle under the cursor
# and takes one click. Nothing else - "החלון עצמו פשוט".
module InteriorPro
  module SkylightDialog
    # `target` (2026-09-14): the panel opened ON one skylight by the Edit
    # tool. Its own numbers fill the controls and the button rebuilds THAT
    # skylight where it stands, instead of starting a placing tool.
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
        dialog_title: @target ? 'Interior Pro - Edit Skylight' : 'Interior Pro - Skylight',
        preferences_key: 'InteriorPro_Skylight',
        width: 360, height: 330, resizable: true,
        min_width: 320, min_height: 280,
        max_width: 520, max_height: 600
      )
      dlg.add_action_callback('place_skylight') do |_, width, height, color|
        sp = InteriorPro::SkylightManager.save_settings!(
          width: width.to_f, height: height.to_f, color: color.to_s
        )
        tgt = @target && @target.respond_to?(:valid?) && @target.valid? ? @target : nil
        if tgt
          model = Sketchup.active_model
          model.start_operation('Edit Skylight', true)
          g = InteriorPro::SkylightManager.replace!(tgt, sp)
          model.commit_operation
          if g.nil?
            why = InteriorPro::SkylightManager.last_reason
            UI.messagebox(why ? "The skylight #{why}" :
                          'That change could not be built - see the Ruby Console.')
          else
            @target = g
          end
        else
          Sketchup.active_model.select_tool(InteriorPro::SkylightTool.new(sp))
        end
      end
      dlg.add_action_callback('close_dialog') do |_|
        begin
          dlg.close
        rescue StandardError
          nil
        end
      end
      vals = @target ? InteriorPro::SkylightManager.spec_of(@target) :
                       InteriorPro::SkylightManager.settings
      dlg.set_html(build_html(vals, edit: !@target.nil?))
      begin
        dlg.center if dlg.respond_to?(:center)
      rescue StandardError
        nil
      end
      dlg.show
      @dialog = dlg
    end

    def self.build_html(s, edit: false)
      sm = InteriorPro::SkylightManager
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          body { font-family: Segoe UI, Arial, sans-serif; font-size: 13px;
                 margin: 0; padding: 14px 16px; color: #222; background: #fafafa; }
          h3 { margin: 0 0 12px; font-size: 15px; }
          .row { display: flex; align-items: center; justify-content: space-between;
                 margin: 8px 0; }
          label { flex: 1; }
          input[type=number] { width: 90px; padding: 5px 6px; font-size: 13px;
                               border: 1px solid #bbb; border-radius: 4px; }
          input[type=color] { width: 60px; height: 30px; border: 1px solid #bbb;
                              border-radius: 4px; padding: 0; background: #fff; }
          .hint { color: #777; font-size: 11px; margin-top: 2px; }
          .btns { display: flex; gap: 8px; margin-top: 16px; }
          button { flex: 1; padding: 9px 0; font-size: 13px; border-radius: 5px;
                   border: 1px solid #888; background: #fff; cursor: pointer; }
          button.go { background: #2b6cb0; color: #fff; border-color: #2b6cb0;
                      font-weight: 600; }
        </style></head><body>
        <h3>#{edit ? 'Edit Skylight' : 'Skylight'}</h3>
        <div class="row"><label>Width across the slope (in)</label>
          <input type="number" id="w" min="#{sm.min_size.to_i}" max="#{sm.max_size.to_i}"
                 step="1" value="#{s[:width].to_f.round(1)}"></div>
        <div class="row"><label>Height up the slope (in)</label>
          <input type="number" id="h" min="#{sm.min_size.to_i}" max="#{sm.max_size.to_i}"
                 step="1" value="#{s[:height].to_f.round(1)}"></div>
        <div class="row"><label>Frame colour</label>
          <input type="color" id="c" value="#{s[:color]}"></div>
        <div class="hint">Then click a roof slope. The same hole is cut through the
          ceiling under it, with a white shaft up to the roof.</div>
        <div class="btns">
          <button onclick="sketchup.close_dialog()">Close</button>
          <button class="go" onclick="go()">#{edit ? 'Apply' : 'Place on roof'}</button>
        </div>
        <script>
          function go() {
            var w = document.getElementById('w').value;
            var h = document.getElementById('h').value;
            var c = document.getElementById('c').value;
            sketchup.place_skylight(w, h, c);
          }
        </script>
        </body></html>
      HTML
    end
  end
end

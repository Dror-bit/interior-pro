# encoding: utf-8
# Landscape Pro - Fence Library window (2026-08-16)
#
# Replaces the nine-field UI.inputbox the fence tool opened until now. The
# inputbox was right while there was nothing to choose FROM; the moment there
# are types, retyping six numbers to draw a fence you drew yesterday is the
# thing this window exists to end.
#
# It is a WINDOW ONLY. It builds no geometry, does no arithmetic, and knows no
# fence rule. Everything it collects goes to FenceLibrary.apply_to_tool, which
# is the single place that maps a saved type onto a FenceTool. If a fence comes
# out wrong, this file is not where to look.
#
# GROUND LIVES HERE, NOT IN THE TYPE
#
# ground_start / ground_end describe the SITE, not the fence product. A Wood
# Privacy fence is the same product whether the ground under it falls two feet
# or none. So the two ground numbers sit above the list, apply to the next
# fence built, and are never saved into a type.

require 'json'
require_relative 'fence_library.rb'

module InteriorPro
  module Landscape
    module FenceLibraryDialog

      def self.show(tool = nil)
        tool ||= InteriorPro::Landscape::FenceTool.new

        dialog = UI::HtmlDialog.new(
          dialog_title: 'Landscape Pro - Fence Library',
          preferences_key: 'LandscapePro_FenceLibrary',
          width: 460,
          height: 720,
          min_width: 420,
          min_height: 360,
          resizable: true
        )

        dialog.set_html(build_html)
        # preferences_key makes SketchUp remember the last size, so a window
        # that was once squashed opens squashed for ever. Force it open.
        dialog.set_size(460, 720) if dialog.respond_to?(:set_size)

        dialog.add_action_callback('get_library') { |_ctx|
          push_library(dialog)
        }

        dialog.add_action_callback('build_fence') { |_ctx, data|
          begin
            payload = JSON.parse(data)
            type = payload['type']
            InteriorPro::Landscape::FenceLibrary.apply_to_tool(
              tool, type,
              payload['ground_start'].to_f, payload['ground_end'].to_f
            )
            dialog.close
            Sketchup.active_model.select_tool(tool)
          rescue StandardError => e
            puts "[FenceLibrary] build: #{e.class}: #{e.message}"
            UI.messagebox("Could not start the fence tool: #{e.message}")
          end
        }

        dialog.add_action_callback('save_fence') { |_ctx, data|
          begin
            InteriorPro::Landscape::FenceLibrary.save_type(JSON.parse(data))
          rescue StandardError => e
            puts "[FenceLibrary] save: #{e.class}: #{e.message}"
          end
          push_library(dialog)
        }

        dialog.add_action_callback('delete_fence') { |_ctx, name|
          begin
            InteriorPro::Landscape::FenceLibrary.delete_type(name.to_s)
          rescue StandardError => e
            puts "[FenceLibrary] delete: #{e.class}: #{e.message}"
          end
          push_library(dialog)
        }

        # IT OPENS WHOLE (2026-09-12). Same mechanism the roof and dormer panels
        # got: the PAGE measures itself once it is laid out and the window
        # follows, so a row added later can never push a button under the scroll.
        dialog.add_action_callback('fit_height') do |_, h|
          begin
            want = h.to_i + 46            # title bar + frame
            want = 360 if want < 360
            want = 1100 if want > 1100
            dialog.set_size(460, want)
          rescue StandardError => e
            puts "[Fence] fit_height: #{e.message}"
          end
        end

        dialog.show
        dialog
      end

      def self.push_library(dialog)
        list = InteriorPro::Landscape::FenceLibrary.all
        dialog.execute_script("loadLibrary(#{list.to_json})")
      end

      # The words a person would use, next to the words the code uses. Built
      # from the list in FenceLibrary rather than typed out again, so a new
      # infill cannot appear in one place and not the other.
      INFILL_LABELS = {
        'boards'     => 'Boards - touching (privacy)',
        'spaced'     => 'Spaced - pickets, balusters, bars',
        'horizontal' => 'Horizontal - slats lying down',
        'glass'      => 'Glass - one panel per bay',
        'none'       => 'Nothing - rails only'
      }.freeze unless const_defined?(:INFILL_LABELS, false)

      def self.build_html
        infills = InteriorPro::Landscape::FenceLibrary::INFILLS.map { |i|
          "<option value='#{i}'>#{INFILL_LABELS[i] || i}</option>"
        }.join
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html, body { height: auto; overflow-y: auto; overflow-x: hidden; }
            body { font-family: Arial, sans-serif; background: #f0f0f0; padding-bottom: 24px; }
            .header { background: #2E7D32; color: white; padding: 12px 16px; font-size: 15px; font-weight: bold; }
            .content { padding: 12px; }
            .ground { background: white; border: 1px solid #ddd; border-radius: 6px; padding: 10px 12px; margin-bottom: 12px; }
            .ground-title { font-size: 12px; font-weight: bold; color: #2E7D32; margin-bottom: 6px; }
            .hint { font-size: 11px; color: #888; margin-top: 6px; line-height: 1.4; }
            .fence-list { background: white; border-radius: 6px; margin-bottom: 12px; overflow: hidden; border: 1px solid #ddd; }
            .fence-item { padding: 10px 14px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; gap: 8px; }
            .fence-item:hover { background: #e8f5e9; }
            .fence-name { font-weight: bold; font-size: 13px; color: #222; }
            .fence-info { font-size: 11px; color: #777; margin-top: 2px; }
            .tag { font-size: 10px; padding: 2px 6px; border-radius: 3px; background: #e8f5e9; color: #2E7D32; font-weight: normal; }
            .tag-soon { background: #fff3e0; color: #E65100; }
            .swatch { display: inline-block; width: 10px; height: 10px; border-radius: 2px; border: 1px solid #bbb; vertical-align: -1px; margin-right: 4px; }
            .fence-actions { display: flex; gap: 6px; align-items: center; flex-shrink: 0; }
            .btn { padding: 6px 12px; border: none; border-radius: 4px; font-size: 12px; cursor: pointer; }
            .btn-build { background: #2E7D32; color: white; }
            .btn-edit { background: #f5f5f5; color: #333; border: 1px solid #ccc; }
            .btn-delete { background: #ffebee; color: #c62828; border: 1px solid #ef9a9a; }
            .btn-new { width: 100%; padding: 10px; background: #43A047; color: white; border: none; border-radius: 6px; font-size: 13px; cursor: pointer; margin-bottom: 8px; }
            .btn-new:hover { background: #388E3C; }
            .form-panel { background: white; border-radius: 6px; padding: 14px; border: 1px solid #ddd; display: none; }
            .form-panel.visible { display: block; }
            .form-title { font-weight: bold; color: #2E7D32; margin-bottom: 12px; font-size: 13px; }
            .group-title { font-size: 11px; font-weight: bold; color: #2E7D32; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 16px; padding-top: 10px; border-top: 1px solid #eee; }
            label { display: block; font-size: 12px; color: #555; margin-top: 8px; margin-bottom: 2px; }
            input, select { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
            .row { display: flex; gap: 8px; }
            .row > div { flex: 1; }
            .form-actions { display: flex; gap: 8px; margin-top: 14px; }
            .btn-save { flex: 1; padding: 8px; background: #2E7D32; color: white; border: none; border-radius: 4px; cursor: pointer; }
            .btn-cancel { flex: 1; padding: 8px; background: #f5f5f5; color: #333; border: 1px solid #ccc; border-radius: 4px; cursor: pointer; }
            .empty-msg { padding: 24px; text-align: center; color: #999; font-size: 13px; }
          </style>
          </head>
          <body>
          <div class="header">Landscape Pro - Fence Library</div>
          <div class="content">

            <div class="ground">
              <div class="ground-title">Ground (this fence only, not saved in the type)</div>
              <div class="row">
                <div>
                  <label>Ground at start (in)</label>
                  <input type="number" id="groundStart" value="0" step="1">
                </div>
                <div>
                  <label>Ground at end (in)</label>
                  <input type="number" id="groundEnd" value="0" step="1">
                </div>
              </div>
              <div class="hint">Both 0 means level ground. When terrain arrives these two fill themselves in.</div>
            </div>

            <button class="btn-new" onclick="showForm()">+ New Fence Type</button>

            <div class="fence-list" id="fenceList">
              <div class="empty-msg">Loading...</div>
            </div>

            <div class="form-panel" id="formPanel">
              <div class="form-title" id="formTitle">New Fence Type</div>
              <label>Type name</label>
              <input type="text" id="fenceName" placeholder="e.g. Cedar 6ft">
              <div class="row">
                <div>
                  <label>Height (in)</label>
                  <input type="number" id="fHeight" value="72" min="1" step="1">
                </div>
                <div>
                  <label>Post spacing max (in)</label>
                  <input type="number" id="fSpacing" value="96" min="1" step="1">
                </div>
              </div>
              <div class="row">
                <div>
                  <label>Post size (in)</label>
                  <input type="number" id="fPost" value="4" min="0.25" step="0.25">
                </div>
                <div>
                  <label>Post above top rail (in)</label>
                  <input type="number" id="fPostExtra" value="2" min="0" step="0.5">
                </div>
              </div>

              <div class="group-title">Rails</div>
              <div class="row">
                <div>
                  <label>How many</label>
                  <select id="fRailCount">
                    <option value="0">None</option>
                    <option value="1">Bottom only</option>
                    <option value="2" selected>Top and bottom</option>
                    <option value="3">Top, middle, bottom</option>
                  </select>
                </div>
                <div>
                  <label>Bottom rail off ground (in)</label>
                  <input type="number" id="fRailBottom" value="2" min="0" step="0.5">
                </div>
              </div>
              <div class="row">
                <div>
                  <label>Rail height (in)</label>
                  <input type="number" id="fRailHeight" value="3.5" min="0" step="0.25">
                </div>
                <div>
                  <label>Rail thickness (in)</label>
                  <input type="number" id="fRailThick" value="1.5" min="0" step="0.25">
                </div>
              </div>

              <div class="group-title">Between the rails</div>
              <label>Infill</label>
              <select id="fInfill">#{infills}</select>
              <div class="row">
                <div>
                  <label id="lblWidth">Board width (in)</label>
                  <input type="number" id="fWidth" value="5.5" min="0.25" step="0.25">
                </div>
                <div>
                  <label id="lblGap">Gap between (in)</label>
                  <input type="number" id="fGap" value="0" min="0" step="0.25">
                </div>
              </div>
              <label id="lblThick">Board thickness (in)</label>
              <input type="number" id="fThick" value="0.75" min="0.05" step="0.05">

              <div class="group-title">Post cap</div>
              <div class="row">
                <div>
                  <label>Cap size (in, 0 = none)</label>
                  <input type="number" id="fCapSize" value="0" min="0" step="0.5">
                </div>
                <div>
                  <label>Cap height (in)</label>
                  <input type="number" id="fCapHeight" value="0" min="0" step="0.25">
                </div>
              </div>

              <div class="group-title">Finish</div>
              <div class="row">
                <div>
                  <label>On a slope</label>
                  <select id="fMode">
                    <option value="rake">Rake - follows the ground</option>
                    <option value="step">Step - level panels</option>
                  </select>
                </div>
                <div>
                  <label>Colour</label>
                  <input type="color" id="fColor" value="#A1887F" style="width:100%; height:32px; padding:2px; border:1px solid #ccc; border-radius:4px;">
                </div>
              </div>
              <div class="hint">
                Boards fill the bay and are shaved to fit. Spaced keeps the board and
                shares out the gap - that is what a picket or a bar wants.
              </div>
              <div class="form-actions">
                <button class="btn-save" onclick="saveFence()">Save</button>
                <button class="btn-cancel" onclick="hideForm()">Cancel</button>
              </div>
            </div>
          </div>

          <script>
            var library = [];

            window.onload = function() {
              sketchup.get_library();
              document.getElementById('fInfill').addEventListener('change', relabel);
            };

            function num(id) {
              var v = parseFloat(document.getElementById(id).value);
              return isNaN(v) ? 0 : v;
            }

            function esc(s) {
              return String(s === undefined || s === null ? '' : s)
                .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;');
            }

            function loadLibrary(data) {
              library = data || [];
              var list = document.getElementById('fenceList');
              if (library.length === 0) {
                list.innerHTML = '<div class="empty-msg">No fence types.</div>';
                return;
              }
              list.innerHTML = library.map(function(f, i) {
                var tag = '<span class="tag">' + esc(f.infill) + '</span>';
                // A type with no rails is worth flagging: measuring six real
                // fences found rails on every single one of them.
                if (!f.rail_count) {
                  tag += ' <span class="tag tag-soon">no rails</span>';
                }
                if (f.cap_height > 0) { tag += ' <span class="tag">cap</span>'; }
                var bits = [
                  'H ' + f.height + '"',
                  'posts every ' + f.max_spacing + '"',
                  (f.rail_count ? f.rail_count + ' rails' : 'no rails'),
                  f.board_width + '" x ' + f.board_gap + '" gap',
                  esc(f.mode)
                ];
                return '<div class="fence-item">' +
                  '<div>' +
                    '<div class="fence-name">' +
                      '<span class="swatch" style="background:' + esc(f.color) + '"></span>' +
                      esc(f.name) + ' ' + tag +
                    '</div>' +
                    '<div class="fence-info">' + bits.join(' | ') + '</div>' +
                  '</div>' +
                  '<div class="fence-actions">' +
                    '<button class="btn btn-build" onclick="buildFence(' + i + ')">Build</button>' +
                    '<button class="btn btn-edit" onclick="editFence(' + i + ')">Edit</button>' +
                    (f.builtin ? '' :
                      '<button class="btn btn-delete" onclick="deleteFence(' + i + ')">X</button>') +
                  '</div>' +
                '</div>';
              }).join('');
            }

            function buildFence(i) {
              sketchup.build_fence(JSON.stringify({
                type: library[i],
                ground_start: parseFloat(document.getElementById('groundStart').value) || 0,
                ground_end: parseFloat(document.getElementById('groundEnd').value) || 0
              }));
            }

            function fill(f) {
              document.getElementById('fenceName').value = f.name || '';
              document.getElementById('fHeight').value = f.height;
              document.getElementById('fSpacing').value = f.max_spacing;
              document.getElementById('fPost').value = f.post_size;
              document.getElementById('fPostExtra').value = f.post_extra;
              document.getElementById('fRailCount').value = f.rail_count;
              document.getElementById('fRailBottom').value = f.rail_bottom_z;
              document.getElementById('fRailHeight').value = f.rail_height;
              document.getElementById('fRailThick').value = f.rail_thickness;
              document.getElementById('fThick').value = f.board_thickness;
              document.getElementById('fWidth').value = f.board_width;
              document.getElementById('fGap').value = f.board_gap;
              document.getElementById('fInfill').value = f.infill;
              document.getElementById('fCapSize').value = f.cap_size;
              document.getElementById('fCapHeight').value = f.cap_height;
              document.getElementById('fMode').value = f.mode;
              document.getElementById('fColor').value = f.color;
              relabel();
              document.getElementById('formPanel').className = 'form-panel visible';
            }

            // The same three boxes mean different things depending on the
            // infill, so they say what they mean. A field called "board width"
            // when you are drawing glass is how a person types 5.5 into it.
            function relabel() {
              var k = document.getElementById('fInfill').value;
              var w = 'Board width (in)', g = 'Gap between (in)', t = 'Board thickness (in)';
              if (k === 'spaced')     { w = 'Picket / bar width (in)'; g = 'Gap between (in)'; t = 'Picket / bar depth (in)'; }
              if (k === 'horizontal') { w = 'Slat height (in)'; g = 'Gap between slats (in)'; t = 'Slat thickness (in)'; }
              if (k === 'glass')      { w = 'Panel width max (in)'; g = 'Gap (in)'; t = 'Glass thickness (in)'; }
              document.getElementById('lblWidth').innerText = w;
              document.getElementById('lblGap').innerText = g;
              document.getElementById('lblThick').innerText = t;
              var none = (k === 'none');
              ['fWidth','fGap','fThick'].forEach(function(id) {
                document.getElementById(id).disabled = none;
              });
            }

            function editFence(i) {
              document.getElementById('formTitle').innerText = 'Edit ' + library[i].name;
              fill(library[i]);
            }

            function deleteFence(i) {
              var f = library[i];
              if (confirm('Delete "' + f.name + '"?')) sketchup.delete_fence(f.name);
            }

            // A new type starts as a copy of the first preset rather than as a
            // blank form. Fourteen empty boxes is a wall; an ordinary wood
            // fence you can change one number in is a starting point.
            function showForm() {
              document.getElementById('formTitle').innerText = 'New Fence Type';
              var base = library[0] || {};
              fill(base);
              document.getElementById('fenceName').value = '';
            }

            function hideForm() {
              document.getElementById('formPanel').className = 'form-panel';
            }

            function saveFence() {
              var name = document.getElementById('fenceName').value.trim();
              if (!name) { alert('Please give the fence type a name.'); return; }
              sketchup.save_fence(JSON.stringify({
                name: name,
                height: num('fHeight'),
                max_spacing: num('fSpacing'),
                post_size: num('fPost'),
                post_extra: num('fPostExtra'),
                rail_count: num('fRailCount'),
                rail_bottom_z: num('fRailBottom'),
                rail_height: num('fRailHeight'),
                rail_thickness: num('fRailThick'),
                board_thickness: num('fThick'),
                board_width: num('fWidth'),
                board_gap: num('fGap'),
                infill: document.getElementById('fInfill').value,
                cap_size: num('fCapSize'),
                cap_height: num('fCapHeight'),
                mode: document.getElementById('fMode').value,
                color: document.getElementById('fColor').value
              }));
              hideForm();
            }
          </script>
          <script>
            var ipFitLast = 0, ipFitTimer = null;
            function ipFitWindow() {
              if (!window.sketchup || !sketchup.fit_height) return;
              var b = document.body, d = document.documentElement;
              var h = Math.max(b.scrollHeight, b.offsetHeight, d.scrollHeight, d.offsetHeight);
              if (Math.abs(h - ipFitLast) < 3) return;
              ipFitLast = h;
              sketchup.fit_height(h);
            }
            function ipFitSoon() {
              if (ipFitTimer) clearTimeout(ipFitTimer);
              ipFitTimer = setTimeout(ipFitWindow, 60);
            }
            window.addEventListener('load', ipFitSoon);
            if (window.ResizeObserver) {
              try { new ResizeObserver(ipFitSoon).observe(document.body); } catch (e) {}
            }
            ipFitSoon();
            setTimeout(ipFitSoon, 250);
          </script>
          </body>
          </html>
        HTML
      end

    end
  end
end

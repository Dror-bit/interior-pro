# encoding: utf-8
# Interior Pro - THE MATERIAL LIBRARY WINDOW (2026-09-15)
#
# His words: "שאני אוכל לבחור חומרים מהתיקיה בפלאג אין שמראה לי אותם
# כמו בכל תוכנת רינדור" - a wall of thumbnails, click one, it lands on
# what is selected.
#
# Reads the cards written by material_library.rb out of the synced
# OneDrive folder, so the same wall of materials shows up on the Mac.
#
# The images are inlined as base64 rather than linked with file:// -
# an HtmlDialog's access to local files is not something to bet a
# feature on, and a library of a few dozen textures is small enough.
require 'base64'
require 'json'

module InteriorPro
  module MaterialLibraryDialog
    USE_MATERIAL_LIBRARY_DIALOG = true unless const_defined?(:USE_MATERIAL_LIBRARY_DIALOG, false)
    @dialog = nil

    def self.lib
      InteriorPro::MaterialLibrary
    end

    def self.show
      return unless USE_MATERIAL_LIBRARY_DIALOG
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return @dialog
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'חומרים - Interior Pro',
        preferences_key: 'InteriorPro_MaterialLibrary',
        width: 760, height: 620, min_width: 420, min_height: 320,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      wire(@dialog)
      @dialog.show
      @dialog
    end

    def self.wire(dlg)
      dlg.add_action_callback('ready')   { |_| push(dlg) ; nil }
      dlg.add_action_callback('refresh') { |_| push(dlg) ; nil }
      dlg.add_action_callback('folder')  { |_| lib.choose_folder! ; push(dlg) ; nil }
      dlg.add_action_callback('save')    { |_| save_selected(dlg) ; nil }
      dlg.add_action_callback('import_studio') { |_| import_studio(dlg) ; nil }
      dlg.add_action_callback('apply')   { |_, id| apply(dlg, id) ; nil }
      dlg.add_action_callback('newfolder') { |_, parent| new_folder(dlg, parent) ; nil }
      dlg.add_action_callback('delfolder') { |_, path| del_folder(dlg, path) ; nil }
      dlg.add_action_callback('movefolder') { |_, from, to| lib.move_folder!(from, to) ; push(dlg) ; nil }
      dlg.add_action_callback('renamefolder') { |_, path| rename_folder(dlg, path) ; nil }
      dlg.add_action_callback('renamecard') { |_, id| rename_card(dlg, id) ; nil }
      dlg.add_action_callback('delcard')    { |_, id| del_card(dlg, id) ; nil }
      dlg.add_action_callback('move')      { |_, id, path| lib.move!(id, path) ; push(dlg) ; nil }
      dlg.add_action_callback('savein')    { |_, path| save_selected(dlg, path) ; nil }
    end

    # ---- data --------------------------------------------------------
    def self.push(dlg)
      all = lib.cards
      cards = all.map { |c| card_for_js(c) }
      data = { 'folder' => lib.folder.to_s,
               'folders' => lib.folders,
               'cards' => cards }
      dlg.execute_script("render(#{JSON.generate(data)})")
    rescue StandardError => e
      puts "[MaterialLibraryDialog] push: #{e.class} #{e.message}"
    end

    def self.card_for_js(c)
      {
        'id'       => c['id'],
        'name'     => c['name'],
        'category' => c['category'].to_s,
        'path'     => c['path'].to_s,
        'gloss'    => (c['vray'] || {})['reflect_glossiness'],
        'rough'    => (c['vray'] || {})['roughness'],
        'color'    => c['color'],
        'img'      => thumb(c)
      }
    end

    # base64 of the texture, or nil - then the card draws its flat colour.
    def self.thumb(c)
      path = lib.texture_path(c)
      return nil if path.nil?
      return nil if File.size(path) > 4_000_000   # do not choke the window
      ext = File.extname(path).downcase.sub('.', '')
      ext = 'jpeg' if ext == 'jpg'
      "data:image/#{ext};base64," + Base64.strict_encode64(File.binread(path))
    rescue StandardError
      nil
    end

    # ---- actions -----------------------------------------------------
    def self.selected_face(model)
      sel = model.selection.to_a
      f = sel.grep(Sketchup::Face).first
      return f if f
      sel.each do |e|
        ents = if e.is_a?(Sketchup::Group) then e.entities
               elsif e.respond_to?(:definition) then e.definition.entities
               end
        next if ents.nil?
        g = ents.grep(Sketchup::Face).first
        return g if g
      end
      nil
    end

    # "מהתוכנה": every material he ticked 3D in Invoice Studio becomes a
    # card (material_import.rb). Runs outside any model operation - it only
    # touches files. Downloads can take a few seconds; the window says so.
    def self.import_studio(dlg)
      return UI.messagebox('הייבוא כבוי (USE_MATERIAL_IMPORT).') unless defined?(InteriorPro::MaterialImport)
      res = InteriorPro::MaterialImport.import!
      push(dlg)
      UI.messagebox(InteriorPro::MaterialImport.summary(res))
    rescue StandardError => e
      UI.messagebox("הייבוא נכשל: #{e.message}")
    end

    def self.new_folder(dlg, parent)
      name = UI.inputbox(['שם התיקייה:'], [''], 'תיקייה חדשה')
      return if name.nil? || name[0].to_s.strip.empty?
      p = parent.to_s.empty? ? name[0].to_s : "#{parent}/#{name[0]}"
      lib.add_folder!(p)
      push(dlg)
    end

    def self.del_folder(dlg, path)
      return if path.to_s.empty?
      ans = UI.messagebox("למחוק את התיקייה \"#{path}\"?\nהחומרים שבתוכה יעברו לתיקייה שמעליה, כלום לא נמחק.",
                          MB_YESNO)
      return unless ans == IDYES
      lib.remove_folder!(path)
      push(dlg)
    end

    def self.rename_folder(dlg, path)
      cur = path.to_s.split('/').last.to_s
      ans = UI.inputbox(['שם חדש:'], [cur], 'שינוי שם תיקייה')
      return if ans.nil? || ans[0].to_s.strip.empty?
      lib.rename_folder!(path, ans[0])
      push(dlg)
    end

    def self.rename_card(dlg, id)
      c = lib.cards.find { |x| x['id'].to_s == id.to_s }
      return if c.nil?
      ans = UI.inputbox(['שם החומר:'], [c['name'].to_s], 'שינוי שם')
      return if ans.nil? || ans[0].to_s.strip.empty?
      lib.rename!(id, ans[0])
      push(dlg)
    end

    def self.del_card(dlg, id)
      c = lib.cards.find { |x| x['id'].to_s == id.to_s }
      return if c.nil?
      ans = UI.messagebox("למחוק את \"#{c['name']}\" מהתיקייה?\nזה לא נוגע בשום מודל.", MB_YESNO)
      return unless ans == IDYES
      lib.delete!(id)
      push(dlg)
    end

    def self.save_selected(dlg, path = nil)
      model = Sketchup.active_model
      f = selected_face(model)
      return UI.messagebox('סמן פאה שיש עליה חומר.') if f.nil? || f.material.nil?
      mat = f.material
      path = nil
      model.start_operation('Interior Pro: save material', true)
      begin
        path = lib.save!(mat, path: path)
      ensure
        model.commit_operation
      end
      push(dlg)
      UI.messagebox(path ? "נשמר: #{mat.display_name}" : 'לא נשמר.')
    end

    # Click a thumbnail -> that material goes on every selected face.
    def self.apply(dlg, id)
      model = Sketchup.active_model
      card = lib.cards.find { |c| c['id'].to_s == id.to_s }
      return UI.messagebox('לא מצאתי את החומר בתיקייה.') if card.nil?

      faces = faces_in_selection(model)
      return UI.messagebox('סמן קודם פאה או קבוצה.') if faces.empty?

      model.start_operation('Interior Pro: apply material', true)
      mat = nil
      begin
        mat = material_from_card(model, card)
        faces.each { |f| f.material = mat }
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        return UI.messagebox("נכשל: #{e.message}")
      end

      # The V-Ray numbers ride along, but OUTSIDE the operation on purpose:
      # V-Ray gives no way to read them back (measured 2026-09-16), so the
      # card is the source of truth - and a V-Ray failure must never roll
      # back the paint he already saw. MaterialLibrary.LAST_TRACE says why
      # when nothing landed, so it is never a silent skip.
      vray_ok = (InteriorPro::MaterialLibrary.apply_vray_numbers!(mat, card['vray']) rescue false)
      why = (InteriorPro::MaterialLibrary::LAST_TRACE.last.to_s rescue '')
      line = if vray_ok
               "\nמספרי V-Ray הוחלו."
             elsif card['vray'].nil? || card['vray'].empty?
               ''
             else
               "\nמספרי V-Ray לא הוחלו: #{why}"
             end
      UI.messagebox("#{card['name']} הוחל על #{faces.length} פאות.#{line}")
    end

    def self.faces_in_selection(model)
      out = []
      model.selection.each do |e|
        if e.is_a?(Sketchup::Face)
          out << e
        elsif e.is_a?(Sketchup::Group)
          out.concat(e.entities.grep(Sketchup::Face))
        elsif e.respond_to?(:definition)
          out.concat(e.definition.entities.grep(Sketchup::Face))
        end
      end
      out.uniq
    end

    # The card becomes a real SketchUp material: same id, same picture,
    # same tile size. If a material with that id is already in the model
    # we reuse it instead of making a twin.
    def self.material_from_card(model, card)
      id = card['id'].to_s
      if defined?(InteriorPro::MaterialIds)
        found = (InteriorPro::MaterialIds.find(id, model) rescue nil)
        return found if found
      end
      mat = model.materials.add(card['name'].to_s)
      c = card['color']
      mat.color = Sketchup::Color.new(c[0], c[1], c[2]) if c.is_a?(Array) && c.length >= 3
      mat.alpha = card['alpha'] if card['alpha']
      f = card['texture_file']
      if f && !f.to_s.empty?
        path = File.join(lib.folder.to_s, f.to_s)
        if File.exist?(path)
          mat.texture = path
          w = card['texture_width_inches']
          h = card['texture_height_inches']
          mat.texture.size = [w, h] if w && h
        end
      end
      mat.set_attribute(InteriorPro::MaterialIds::DICT,
                        InteriorPro::MaterialIds::KEY, id) if defined?(InteriorPro::MaterialIds)
      mat
    end

    # ---- the window --------------------------------------------------
    def self.html
      <<~HTML
        <!DOCTYPE html><html lang="he" dir="rtl"><head><meta charset="utf-8">
        <style>
          body { font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #2b2b2b;
                 color: #eee; overflow: hidden; }
          header { padding: 9px 12px; background: #1f1f1f; display: flex; gap: 8px;
                   align-items: center; }
          header .path { font-size: 11px; color: #888; margin-inline-start: auto;
                         direction: ltr; unicode-bidi: plaintext; }
          button { background: #3d7eff; color: #fff; border: 0; padding: 7px 12px;
                   border-radius: 5px; cursor: pointer; font-size: 13px; }
          button.ghost { background: #444; }
          #wrap { display: flex; height: calc(100vh - 42px); }
          #side { width: 190px; flex: 0 0 190px; background: #262626; overflow-y: auto;
                  padding: 8px 6px; }
          #side .row { display: flex; align-items: center; gap: 4px; padding: 5px 8px;
                       border-radius: 5px; cursor: pointer; font-size: 13px; color: #ccc; }
          #side .row:hover { background: #383838; }
          #side .row.on { background: #3d7eff; color: #fff; }
          #side .row.drop { outline: 2px dashed #3d7eff; }
          #side .row .x { margin-inline-start: auto; opacity: 0; font-size: 15px; color: #ff8080; }
          #side .row:hover .x { opacity: 1; }
          #side .count { margin-inline-start: auto; font-size: 11px; color: #888; }
          #side .row:hover .count { display: none; }
          #newf { margin: 8px 6px; width: calc(100% - 12px); }
          #menu { position: fixed; background: #3a3a3a; border: 1px solid #555;
                  border-radius: 6px; padding: 4px; display: none; z-index: 99;
                  min-width: 160px; box-shadow: 0 6px 20px rgba(0,0,0,.5); }
          #menu div { padding: 7px 12px; font-size: 13px; border-radius: 4px; cursor: pointer; }
          #menu div:hover { background: #3d7eff; }
          #menu .sep { height: 1px; background: #555; padding: 0; margin: 4px 2px; cursor: default; }
          #menu .sep:hover { background: #555; }
          #menu .head { color: #999; font-size: 11px; cursor: default; }
          #menu .head:hover { background: transparent; }
          #grid { flex: 1; overflow-y: auto; display: grid; align-content: start;
                  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
                  gap: 12px; padding: 14px; }
          .card { background: #333; border-radius: 8px; overflow: hidden; cursor: pointer;
                  border: 2px solid transparent; }
          .card:hover { border-color: #3d7eff; }
          .sw { height: 110px; background-size: cover; background-position: center; }
          .nm { padding: 7px 8px 2px; font-size: 13px; }
          .sub { padding: 0 8px 8px; font-size: 11px; color: #999; }
          .empty { padding: 40px; text-align: center; color: #888; grid-column: 1 / -1; }
        </style></head><body>
        <header>
          <button onclick="saveHere()">שמור את החומר המסומן</button>
          <button class="ghost" onclick="sketchup.import_studio()" title="מייבא את החומרים שסימנת 3D ב-Invoice Studio">מהתוכנה</button>
          <button class="ghost" onclick="sketchup.refresh()">רענן</button>
          <button class="ghost" onclick="sketchup.folder()">תיקייה בדיסק...</button>
          <span class="path" id="path"></span>
        </header>
        <div id="menu"></div>
        <div id="wrap">
          <div id="side">
            <button class="ghost" id="newf" onclick="sketchup.newfolder(PICKED)">+ תיקייה חדשה</button>
            <div id="tree"></div>
          </div>
          <div id="grid"></div>
        </div>
        <script>
          var DATA = { cards: [], folders: [] };
          var PICKED = '';

          function countIn(p) {
            return DATA.cards.filter(function (c) {
              var cp = c.path || '';
              return p === '' ? true : (cp === p || cp.indexOf(p + '/') === 0);
            }).length;
          }

          function render(data) {
            DATA = data;
            document.getElementById('path').textContent = data.folder || '';
            var t = document.getElementById('tree');
            t.innerHTML = '';
            t.appendChild(rowFor('', 'כל החומרים', 0));
            (data.folders || []).forEach(function (f) {
              var depth = f.split('/').length;
              t.appendChild(rowFor(f, f.split('/').pop(), depth));
            });
            draw();
          }

          function rowFor(path, label, depth) {
            var d = document.createElement('div');
            d.className = 'row' + (path === PICKED ? ' on' : '');
            d.style.paddingInlineStart = (8 + depth * 14) + 'px';
            var name = document.createElement('span');
            name.textContent = (depth ? '' : '') + label;
            d.appendChild(name);
            var n = document.createElement('span');
            n.className = 'count';
            n.textContent = countIn(path);
            d.appendChild(n);
            if (path) {
              var x = document.createElement('span');
              x.className = 'x';
              x.textContent = '\u00d7';
              x.onclick = function (ev) { ev.stopPropagation(); sketchup.delfolder(path); };
              d.appendChild(x);
            }
            d.onclick = function () { PICKED = path; render(DATA); };
            if (path) {
              d.oncontextmenu = function (ev) { ev.preventDefault(); showMenu(ev, path); };
            }
            d.ondragover = function (ev) { ev.preventDefault(); d.classList.add('drop'); };
            d.ondragleave = function () { d.classList.remove('drop'); };
            d.ondrop = function (ev) {
              ev.preventDefault();
              d.classList.remove('drop');
              var id = ev.dataTransfer.getData('text/plain');
              if (id) sketchup.move(id, path);
            };
            return d;
          }

          function showMenu(ev, path) {
            var m = document.getElementById('menu');
            m.innerHTML = '';
            function item(label, fn, cls) {
              var d = document.createElement('div');
              d.textContent = label;
              if (cls) d.className = cls;
              if (fn) d.onclick = function () { hideMenu(); fn(); };
              m.appendChild(d);
            }
            item(path, null, 'head');
            item('\u05e9\u05e0\u05d4 \u05e9\u05dd', function () { sketchup.renamefolder(path); });
            item('\u05de\u05d7\u05e7 \u05ea\u05d9\u05e7\u05d9\u05d9\u05d4', function () { sketchup.delfolder(path); });
            item('', null, 'sep');
            item('\u05d4\u05e2\u05d1\u05e8 \u05dc\u05ea\u05d5\u05da:', null, 'head');
            var targets = (DATA.folders || []);
            targets.forEach(function (t) {
              if (t === path || t.indexOf(path + '/') === 0) return;
              var parent = path.indexOf('/') >= 0 ? path.slice(0, path.lastIndexOf('/')) : '';
              if (t === parent) return;
              item(t, function () { sketchup.movefolder(path, t); });
            });
            m.style.display = 'block';
            m.style.left = Math.min(ev.clientX, window.innerWidth - 180) + 'px';
            m.style.top = Math.min(ev.clientY, window.innerHeight - m.offsetHeight - 10) + 'px';
          }
          function cardMenu(ev, c) {
            var m = document.getElementById('menu');
            m.innerHTML = '';
            function item(label, fn, cls) {
              var d = document.createElement('div');
              d.textContent = label;
              if (cls) d.className = cls;
              if (fn) d.onclick = function () { hideMenu(); fn(); };
              m.appendChild(d);
            }
            item(c.name || c.id, null, 'head');
            item('\u05e6\u05d1\u05e2 \u05d0\u05ea \u05de\u05d4 \u05e9\u05de\u05e1\u05d5\u05de\u05df', function () { sketchup.apply(c.id); });
            item('\u05e9\u05e0\u05d4 \u05e9\u05dd', function () { sketchup.renamecard(c.id); });
            item('\u05de\u05d7\u05e7 \u05de\u05d4\u05ea\u05d9\u05e7\u05d9\u05d9\u05d4', function () { sketchup.delcard(c.id); });
            item('', null, 'sep');
            item('\u05d4\u05e2\u05d1\u05e8 \u05dc\u05ea\u05d9\u05e7\u05d9\u05d9\u05d4:', null, 'head');
            var targets = (DATA.folders || []);
            targets.forEach(function (t) {
              if (t === (c.path || '')) return;
              item(t, function () { sketchup.move(c.id, t); });
            });
            m.style.display = 'block';
            m.style.left = Math.min(ev.clientX, window.innerWidth - 180) + 'px';
            m.style.top = Math.min(ev.clientY, window.innerHeight - 260) + 'px';
          }

          function hideMenu() { document.getElementById('menu').style.display = 'none'; }
          window.addEventListener('click', hideMenu);
          window.addEventListener('scroll', hideMenu, true);

          function draw() {
            var g = document.getElementById('grid');
            var cards = DATA.cards.filter(function (c) {
              var cp = c.path || '';
              return PICKED === '' ? true : (cp === PICKED || cp.indexOf(PICKED + '/') === 0);
            });
            g.innerHTML = '';
            if (!cards.length) {
              g.innerHTML = '<div class="empty">אין כאן חומרים.<br>סמן חומר במודל ולחץ "שמור את החומר המסומן".</div>';
              return;
            }
            cards.forEach(function (c) {
              var d = document.createElement('div');
              d.className = 'card';
              d.draggable = true;
              var bg = c.img ? ('url(' + c.img + ')')
                     : (c.color ? ('rgb(' + c.color.join(',') + ')') : '#555');
              var sub = [];
              if (c.path) sub.push(c.path);
              if (c.gloss !== null && c.gloss !== undefined) sub.push('ברק ' + c.gloss);
              d.innerHTML = '<div class="sw"></div><div class="nm"></div><div class="sub"></div>';
              d.querySelector('.sw').style.background = bg;
              d.querySelector('.sw').style.backgroundSize = 'cover';
              d.querySelector('.nm').textContent = c.name || c.id;
              d.querySelector('.sub').textContent = sub.join(' \u00b7 ');
              d.ondragstart = function (ev) { ev.dataTransfer.setData('text/plain', c.id); };
              d.onclick = function () { sketchup.apply(c.id); };
              d.oncontextmenu = function (ev) { ev.preventDefault(); cardMenu(ev, c); };
              g.appendChild(d);
            });
          }

          function saveHere() { sketchup.savein(PICKED); }

          window.addEventListener('load', function () { sketchup.ready(); });
        </script></body></html>
      HTML
    end
  end
end

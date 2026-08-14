# encoding: utf-8
# plan_sheet_dialog.rb - the sheet window. See the page before it is printed.
#
# Shows the drawing document exactly as it will come out: pick the page size
# and the scale from the lists, drag the plan where you want it, turn layers
# off, then press Export PDF. Nothing is decided for the user.
#
# Ruby owns the document (plan_doc.rb) and the plan (plan_canvas.rb).
# The window only draws it and sends back what the user changed, so the
# preview and the PDF can never disagree - they are the same document.
#
#   InteriorPro::PlanSheetDialog.show

require 'json'

module InteriorPro
  module PlanSheetDialog
    ATTR_DICT  = 'InteriorPro'    unless const_defined?(:ATTR_DICT, false)
    ATTR_STATE = 'sheet_state'    unless const_defined?(:ATTR_STATE, false)

    class << self
      def show
        if @dialog
          begin; @dialog.close; rescue StandardError; end
          @dialog = nil
        end
        # Always read the model again when the window opens. Otherwise a door
        # or a window added since last time would be missing from the sheet
        # and from the tables (2026-08-12, the user hit exactly this).
        @doc = nil

        dlg = UI::HtmlDialog.new(
          dialog_title: 'Interior Pro - Sheet',
          preferences_key: 'InteriorPro_PlanSheet',
          width: 1180, height: 820, resizable: true
        )

        dlg.add_action_callback('sheet_ready') { |_| push_all(dlg) }

        dlg.add_action_callback('rebuild') do |_|
          @doc = nil
          push_all(dlg)
        end

        # Anything selected in SketchUp right now joins the SITE layer. This is
        # for the parts modelled by hand - a back yard, a bench, an import.
        dlg.add_action_callback('add_selection') do |_|
          begin
            sel = Sketchup.active_model.selection.to_a
            st  = load_state
            if sel.empty?
              dlg.execute_script("siteDone(#{JSON.generate(0)}, #{JSON.generate('nothing selected')})")
            else
              # Take the lines now, while we are holding the entities. Looking
              # them up again later never worked on a real model.
              fresh = InteriorPro::PlanGeometry.snapshot(
                sel, hide_soft: st['site_soft'] != true,
                     z_max: st['site_z_max'] ? st['site_z_max'].to_f * 12.0 : nil
              )
              self.site_lines = site_lines + fresh
              save_state(st)
              @doc = nil
              push_all(dlg)
              r = InteriorPro::PlanGeometry.last_report
              r[:total] = site_lines.length
              r[:kept]  = @site_saved ? 1 : 0
              dlg.execute_script("siteReport(#{JSON.generate(sel.length)}, #{JSON.generate(r)})")
            end
          rescue StandardError => e
            puts "[Sheet] add_selection: #{e.message}"
            dlg.execute_script("siteDone(0, #{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('clear_selection') do |_|
          begin
            st = load_state
            st['site_pids'] = []
            save_state(st)
            self.site_lines = []
            @doc = nil
            push_all(dlg)
            dlg.execute_script('siteDone(0, null)')
          rescue StandardError => e
            puts "[Sheet] clear_selection: #{e.message}"
          end
        end

        # -------------------------------------------------------- the pictures
        #
        # ONE way in, on purpose (2026-08-14). There were three buttons - one
        # file, a whole folder, and several at once - and the user's answer was
        # that "several at once" already covers all of it: from the file window
        # he picks one or twenty, and if he would rather drag them in he drags
        # them in. Both land in the same place, so there is one thing to explain
        # and one thing that can break.
        #
        # debug_drop.rb measured this on the user's machine: eighteen files were
        # dragged in and every one arrived with
        #
        #     path property: NOT THERE
        #
        # The window is handed the CONTENTS of a file and never its address -
        # that is the browser protecting the disk, not a bug we can fix. So the
        # bytes are carried across in pieces and written into a folder beside
        # the model, and from there everything works the ordinary way.
        dlg.add_action_callback('drop_begin') do |_, json|
          begin
            r    = JSON.parse(json.to_s)
            dir  = drop_dir
            name = safe_name(r['name'])
            same = File.join(dir, name)
            if File.file?(same) && File.size(same) == r['size'].to_i
              # already carried across once; do not spend a minute on it again
              @drop_path = nil
              @drop_done = same.tr('\\', '/')
              dlg.execute_script('dropReady(true)')
            else
              @drop_path = File.join(dir, free_name(dir, name)).tr('\\', '/')
              @drop_done = nil
              File.binwrite(@drop_path, '')
              dlg.execute_script('dropReady(false)')
            end
          rescue StandardError => e
            puts "[Sheet] drop_begin: #{e.message}"
            dlg.execute_script("dropFailed(#{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('drop_chunk') do |_, b64|
          begin
            if @drop_path
              File.open(@drop_path, 'ab') { |f| f.write(b64.to_s.unpack1('m0').to_s) }
            end
            dlg.execute_script('chunkDone()')
          rescue StandardError => e
            puts "[Sheet] drop_chunk: #{e.message}"
            dlg.execute_script("dropFailed(#{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('drop_end') do |_|
          begin
            got = @drop_done || @drop_path
            (@drop_list ||= []) << got if got && File.file?(got.to_s)
            @drop_path = nil
            @drop_done = nil
            dlg.execute_script('fileDone()')
          rescue StandardError => e
            puts "[Sheet] drop_end: #{e.message}"
            dlg.execute_script("dropFailed(#{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('drop_finish') do |_|
          begin
            list = Array(@drop_list)
            @drop_list = []
            add_images!(dlg, list)
          rescue StandardError => e
            puts "[Sheet] drop_finish: #{e.message}"
            dlg.execute_script("dropFailed(#{JSON.generate(e.message)})")
          end
        end

        # The window shows ONE list of every sheet - plan, schedules, renders -
        # and an x on each. What "throw this sheet away" means depends on what
        # the sheet is, and only Ruby knows: a render leaves the picture list, a
        # schedules sheet gets its layer turned off. The plan sheet has no x,
        # because the drawing is the point of the whole document.
        dlg.add_action_callback('delete_page') do |_, json|
          begin
            r  = JSON.parse(json.to_s)
            st = load_state
            case r['kind']
            when 'image'
              list = Array(st['images'])
              i = r['ref'].to_i
              list.delete_at(i) if i >= 0 && i < list.length
              st['images'] = list
            when 'schedules'
              st['hidden'] = (Array(st['hidden']) +
                              [InteriorPro::PlanTables::LAYER]).uniq
            else
              dlg.execute_script("imageReport(0, #{JSON.generate('אי אפשר למחוק את דף התוכנית')})")
              next
            end
            st['active'] = 0
            save_state(st)
            @doc = nil
            push_all(dlg)
          rescue StandardError => e
            puts "[Sheet] delete_page: #{e.message}"
            dlg.execute_script("imageReport(0, #{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('set_state') do |_, json|
          begin
            st = JSON.parse(json.to_s)
            save_state(st)
            apply_state!(document, st)
            push_pages(dlg)
          rescue StandardError => e
            puts "[Sheet] set_state: #{e.message}"
          end
        end

        dlg.add_action_callback('export_pdf') do |_, json|
          begin
            st = JSON.parse(json.to_s)
            save_state(st)
            apply_state!(document, st)
            path = UI.savepanel('Save the sheet as PDF', default_dir,
                                default_name(st))
            if path
              path = "#{path}.pdf" unless path.downcase.end_with?('.pdf')
              InteriorPro::PlanPDF.export(document, path)
              dlg.execute_script("exportDone(#{JSON.generate(path)})")
            else
              dlg.execute_script('exportDone(null)')
            end
          rescue StandardError => e
            puts "[Sheet] export_pdf: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
            dlg.execute_script("exportFailed(#{JSON.generate(e.message)})")
          end
        end

        dlg.set_html(html)
        dlg.show
        @dialog = dlg
        dlg
      end

      # ------------------------------------------------------------ document

      def document
        @doc ||= begin
          st = load_state
          InteriorPro::PlanCanvas.build_document(
            Sketchup.active_model,
            size: st['size'], orientation: (st['orientation'] || 'landscape').to_sym,
            scale: st['scale'], address: st['address'],
            sheet_number: st['sheet_number'], sheet_title: st['sheet_title'],
            date: st['date'],
            site: { lines: site_lines, pids: st['site_pids'],
                    z_max: st['site_z_max'] ? st['site_z_max'].to_f * 12.0 : nil,
                    hide_soft: st['site_soft'] != true }
          ).tap { |d| apply_state!(d, st) }
        end
      end

      # Everything the user can change, put back onto the document. Every page
      # is rebuilt out of his choices, so the window and the PDF cannot drift
      # apart - there is only one layout routine and they both run it.
      def apply_state!(doc, st)
        doc.job_address = st['address'].to_s if st.key?('address')
        doc.date        = st['date'] if st.key?('date')
        InteriorPro::PlanCanvas.layout_pages!(doc, st)
        doc
      end

      # ---------------------------------------------------------------- push

      def push_all(dlg)
        d = document
        st = load_state
        payload = {
          doc: d.to_h,
          state: st.merge('site_count' => site_lines.length),
          page_sizes: InteriorPro::PlanDoc.page_size_names,
          scales: InteriorPro::PlanDoc.scale_labels,
          images: image_payload(st),
          bounds: d.canvas('MODEL').bounds
        }
        dlg.execute_script("loadSheet(#{JSON.generate(payload)})")
      rescue StandardError => e
        puts "[Sheet] push_all: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
      end

      # Only the paper changes when a control moves; the plan itself does not,
      # so the shapes stay where they are in the window.
      def push_pages(dlg)
        d = document
        dlg.execute_script("applyPages(#{JSON.generate(d.pages.map(&:to_h))})")
      rescue StandardError => e
        puts "[Sheet] push_pages: #{e.message}"
      end

      # --------------------------------------------------------------- state

      # A METHOD, not a constant, and that is the whole point (2026-08-14).
      #
      # This used to be `DEFAULT_STATE = {...} unless const_defined?`. The guard
      # is right for a constant - reloading a file must not warn about it - but
      # it also means InteriorPro.reload! keeps the OLD hash forever. So on the
      # day 'images' was added, save_state went on stripping it out: the user
      # picked a folder, the window said "18 pictures added", and every one of
      # them was thrown away on the way to the model. Nothing was wrong with the
      # pictures; the settings list simply had not heard of them.
      #
      # A method is redefined on every load, so a new setting works after
      # reload! instead of after a restart.
      def default_state
        { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
          'address' => '', 'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
          'hidden' => [], 'tables_own_page' => true,
          'site_pids' => [], 'site_z_max' => nil, 'site_soft' => false,
          'images' => [], 'image_title' => 'RENDERING' }
      end

      # Settings that are remembered but have no default: where the plan sits,
      # which sheet is open, the zoom.
      def extra_state_keys
        %w[origin_x origin_y date active zoom]
      end

      # -------------------------------------------------- the free geometry
      #
      # These lines do NOT go in the state. A real back yard is thousands of
      # them, and a model attribute that big is swallowed without a word - the
      # user pressed the button, saw "3270 added", and the page stayed empty
      # (2026-08-13). So they live in memory, and only a small site is also
      # written to the model so it survives a restart.
      SITE_ATTR      = 'sheet_site_lines' unless const_defined?(:SITE_ATTR, false)
      SITE_ATTR_MAX  = 60_000 unless const_defined?(:SITE_ATTR_MAX, false)

      def site_lines
        return @site_lines if @site_lines
        raw = begin
          Sketchup.active_model.get_attribute(ATTR_DICT, SITE_ATTR)
        rescue StandardError
          nil
        end
        @site_lines = raw ? (JSON.parse(raw.to_s) rescue []) : []
      end

      def site_lines=(lines)
        @site_lines = Array(lines)
        json = JSON.generate(@site_lines)
        @site_saved = json.bytesize <= SITE_ATTR_MAX
        begin
          if @site_saved
            Sketchup.active_model.set_attribute(ATTR_DICT, SITE_ATTR, json)
          else
            Sketchup.active_model.delete_attribute(ATTR_DICT, SITE_ATTR)
          end
        rescue StandardError => e
          puts "[Sheet] site_lines: #{e.message}"
          @site_saved = false
        end
        @site_lines
      end

      # ------------------------------------------------------- the pictures
      #
      # Only the PATHS live in the state - a path is a few dozen bytes, so a
      # sheet full of renders still saves onto the model. The pixels are read
      # again when the PDF is written.

      def add_images!(dlg, paths)
        wanted = Array(paths).map { |p| p.to_s.tr('\\', '/') }.reject(&:empty?)
        if wanted.empty?
          dlg.execute_script('imageReport(0, null)')
          return
        end
        st = load_state
        st['images'] = Array(st['images']) + wanted
        save_state(st)
        @doc = nil
        push_all(dlg)
        dlg.execute_script("imageReport(#{wanted.length}, null)")
      end

      # Where a picture is put down: beside the SketchUp file, so it travels
      # with the job. An unsaved model has no folder of its own, so it falls
      # back to the plugin folder rather than refusing.
      #
      # main.rb sets InteriorPro::PLUGIN_DIR, but this file is also loaded on its
      # own by the test suites, where main.rb never runs. Same folder either way.
      def plugin_dir
        (defined?(PLUGIN_DIR) ? PLUGIN_DIR.to_s
                              : File.dirname(File.expand_path(__FILE__))).tr('\\', '/')
      end

      def drop_dir
        m = Sketchup.active_model
        base = m.path.to_s.empty? ? plugin_dir : File.dirname(m.path.to_s)
        d = File.join(base.tr('\\', '/'), 'InteriorPro_images')
        Dir.mkdir(d) unless File.directory?(d)
        d
      rescue StandardError => e
        puts "[Sheet] drop_dir: #{e.message}"
        plugin_dir
      end

      # The window hands over whatever the file was called. It is not allowed to
      # become a path: a name with a slash or ".." in it would write outside the
      # folder we chose.
      def safe_name(name)
        n = File.basename(name.to_s.tr('\\', '/'))
        n = n.gsub(/[<>:"|?*\x00-\x1f]/, '_').sub(/\A\.+/, '')
        n = 'image.jpg' if n.strip.empty?
        n[0, 120]
      end

      # Two different renders can easily be called "1_1 - Photo.jpg". Keep both.
      def free_name(dir, name)
        return name unless File.exist?(File.join(dir, name))
        ext  = File.extname(name)
        stem = File.basename(name, ext)
        i = 2
        i += 1 while File.exist?(File.join(dir, "#{stem} (#{i})#{ext}"))
        "#{stem} (#{i})#{ext}"
      end

      # An address the window can load the picture from, straight off the disk.
      #
      # This started life as a thumbnail maker: load the file with
      # Sketchup::ImageRep, shrink it, hand the small copy to the window as a
      # data: URL. It always came back empty, and the sheet showed a dashed box
      # (2026-08-14). The probe in debug_images.rb said why: on SketchUp 2024
      # ImageRep has neither #resize nor #save_as, so there was nothing to send.
      # The same probe showed the window loads file:/// happily - it read the
      # user's own 3840x2160 render off disk. So there is nothing to convert:
      # point at the file and let the window do the work.
      #
      # A path is not a URL. Spaces, commas and Hebrew all have to be spelt out
      # in bytes, or the address stops at the first space - and this user's
      # renders live under "15723 E La Belle St, La Puente, CA 91745".
      def file_url(path)
        p = path.to_s.tr('\\', '/').sub(%r{\A/+}, '')
        safe = p.b.gsub(%r{[^A-Za-z0-9\-_.~/:]}n) { |c| format('%%%02X', c.ord) }
        "file:///#{safe}"
      end

      def image_payload(st)
        Array(st['images']).each_with_index.map do |p, i|
          { 'i' => i, 'path' => p, 'name' => File.basename(p.to_s),
            'url' => file_url(p), 'there' => File.file?(p.to_s) }
        end
      end

      def load_state
        raw = Sketchup.active_model.get_attribute(ATTR_DICT, ATTR_STATE)
        st  = raw ? JSON.parse(raw.to_s) : {}
        default_state.merge(st)
      rescue StandardError
        default_state
      end

      def save_state(st)
        keep  = default_state.keys + extra_state_keys
        clean = st.select { |k, _| keep.include?(k) }
        dropped = st.keys - clean.keys - ['site_count']
        puts "[Sheet] save_state dropped: #{dropped.join(', ')}" unless dropped.empty?
        Sketchup.active_model.set_attribute(ATTR_DICT, ATTR_STATE, JSON.generate(clean))
      rescue StandardError => e
        puts "[Sheet] save_state: #{e.message}"
      end

      def default_dir
        home = ENV['USERPROFILE'] || ENV['HOME'] || '.'
        d = File.join(home.tr('\\', '/'), 'Desktop')
        File.directory?(d) ? d : home.tr('\\', '/')
      end

      def default_name(st)
        base = st['sheet_number'].to_s.strip
        base = 'plan' if base.empty?
        "#{base.gsub(/[^A-Za-z0-9._-]/, '_')}.pdf"
      end

      # ---------------------------------------------------------------- html

      def html
        <<~'HTML'
          <!DOCTYPE html>
          <html><head><meta charset="utf-8">
          <style>
            * { box-sizing: border-box; }
            body { margin:0; font:13px/1.4 Segoe UI, Arial, sans-serif;
                   background:#3a3a3a; color:#eee; display:flex; height:100vh; }
            #side { width:230px; flex:none; background:#2b2b2b; padding:12px;
                    overflow:auto; border-right:1px solid #111; }
            #stage { flex:1; overflow:auto; position:relative; padding:20px;
                     display:flex; align-items:flex-start; justify-content:center; }
            #sheetWrap { background:#fff; box-shadow:0 0 22px rgba(0,0,0,.55);
                         flex:none; margin:auto; }
            #zoombar { position:absolute; right:14px; bottom:14px; display:flex; gap:4px;
                       background:#2b2b2b; border:1px solid #555; border-radius:4px;
                       padding:4px; z-index:5; }
            #zoombar button { width:34px; margin:0; padding:4px 0; }
            #zoombar button.wide { width:52px; font-size:12px; }
            h4 { margin:14px 0 6px; font-size:11px; letter-spacing:.08em;
                 text-transform:uppercase; color:#9a9a9a; font-weight:600; }
            h4:first-child { margin-top:0; }
            select, input { width:100%; padding:5px 6px; background:#1e1e1e; color:#eee;
                            border:1px solid #555; border-radius:3px; font-size:13px; }
            .row { display:flex; gap:6px; }
            button { width:100%; padding:8px; margin-top:6px; background:#4a4a4a;
                     color:#fff; border:1px solid #666; border-radius:3px; cursor:pointer;
                     font-size:13px; }
            button:hover { background:#5a5a5a; }
            button.go { background:#1f6feb; border-color:#1f6feb; font-weight:600; }
            button.go:hover { background:#2b7cf7; }
            button.go2 { background:#3b5a86; border-color:#4a6ea3; font-weight:600; }
            button.go2:hover { background:#47699b; }
            label.chk { display:flex; align-items:center; gap:7px; padding:3px 0;
                        cursor:pointer; font-size:13px; }
            label.chk input { width:auto; }
            #msg { margin-top:10px; font-size:12px; color:#9ecbff; min-height:16px;
                   word-break:break-all; }
            #fit { font-size:12px; color:#c9c9c9; margin-top:6px; }
            .hint { font-size:11px; color:#888; margin-top:4px; }
            #pages { border:1px solid #444; border-radius:3px; overflow:hidden;
                     max-height:210px; overflow-y:auto; background:#1e1e1e; }
            .pg { display:flex; align-items:center; gap:6px; padding:5px 6px;
                  cursor:pointer; border-bottom:1px solid #333; font-size:12px; }
            .pg:last-child { border-bottom:none; }
            .pg:hover { background:#333; }
            .pg.sel { background:#1f6feb; color:#fff; }
            .pg b { flex:none; font-weight:600; font-size:11px; opacity:.85;
                    direction:ltr; }
            .pg span { flex:1; overflow:hidden; text-overflow:ellipsis;
                       white-space:nowrap; direction:ltr; text-align:left; }
            .pg button { width:18px; margin:0; padding:0; font-size:13px;
                         line-height:16px; flex:none; background:none;
                         border:none; color:#999; opacity:0; }
            .pg:hover button { opacity:1; }
            .pg button:hover { color:#ff8a8a; background:none; }
            #filepick { display:none; }
            #curtain { position:fixed; inset:0; z-index:50; display:none;
                       background:rgba(20,40,70,.82); color:#cfe4ff;
                       align-items:center; justify-content:center; font-size:22px;
                       border:4px dashed #1f6feb; pointer-events:none; }
            #curtain.on { display:flex; }
          </style></head>
          <body>
            <div id="side">
              <h4>דפים</h4>
              <div id="pages"></div>

              <h4>גודל דף</h4>
              <select id="size"></select>
              <div class="row" style="margin-top:6px">
                <button id="land">לרוחב</button>
                <button id="port">לאורך</button>
              </div>

              <h4>קנה מידה</h4>
              <select id="scale"></select>
              <div id="fit"></div>

              <h4>שכבות</h4>
              <div id="layers"></div>
              <label class="chk" style="margin-top:6px">
                <input type="checkbox" id="ownpage"> טבלאות בדף נפרד
              </label>

              <h4>תמונות ורינדורים</h4>
              <button id="addmany" class="go2">העלאת תמונות</button>
              <input type="file" id="filepick" multiple accept="image/jpeg,image/png">
              <div id="imginfo" class="hint">אחת או כמה, או גרור אותן לחלון.</div>

              <h4>גיאומטריה חופשית</h4>
              <button id="addsel">הוסף את מה שנבחר בסקצ'אפ</button>
              <button id="clrsel">נקה הכל</button>
              <div id="siteinfo" class="hint"></div>

              <h4>טייטל בלוק</h4>
              <input id="address" placeholder="Job address">
              <div class="row" style="margin-top:6px">
                <input id="num" placeholder="A-101">
                <input id="title" placeholder="FLOOR PLAN">
              </div>

              <h4>&nbsp;</h4>
              <button id="fitplan" class="go2">התאם את התוכנית לדף</button>
              <button id="center">מרכז את התוכנית</button>
              <button id="rebuild">קרא שוב מהמודל</button>
              <button id="pdf" class="go">Export PDF</button>
              <div class="hint">גרירה = מזיז את התוכנית על הדף.<br>
                גלגלת = זום פנימה והחוצה.<br>
                Shift+גרירה = מזיז את הדף עצמו.</div>
              <div id="msg"></div>
            </div>
            <div id="curtain">שחרר כאן — כל תמונה תקבל דף</div>
            <div id="stage">
              <div id="sheetWrap"></div>
              <div id="zoombar">
                <button id="zout">&minus;</button>
                <button id="zfit" class="wide">התאם</button>
                <button id="zin">+</button>
              </div>
            </div>

          <script>
          var DOC=null, STATE=null, PAGE=null, BOUNDS=null, SCALES=[];
          var URLS={};                // path -> file:/// address, for the sheet
          var SF = {};      // scale label -> paper inches per model inch
          var ZOOM = null;  // null = fit the window; otherwise a multiplier

          function $(id){ return document.getElementById(id); }

          function scaleFactor(lbl){ return SF[lbl] || 0.25/12; }

          // ---- drawing ---------------------------------------------------
          function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

          function shapeSVG(s, tp, k){
            var o=[];
            function P(x,y){ var p=tp(x,y); return (p[0]*k).toFixed(2)+','+((PAGE.height-p[1])*k).toFixed(2); }
            var w = ((s.weight||0.012)*k).toFixed(2);
            if(s.type==='line'){
              o.push('<line x1="'+P(s.x1,s.y1).split(',')[0]+'" y1="'+P(s.x1,s.y1).split(',')[1]+
                     '" x2="'+P(s.x2,s.y2).split(',')[0]+'" y2="'+P(s.x2,s.y2).split(',')[1]+
                     '" stroke="#000" stroke-width="'+Math.max(w,0.6)+'"/>');
            } else if(s.type==='polyline'||s.type==='polygon'){
              var pts=s.points.map(function(p){ return P(p[0],p[1]); }).join(' ');
              if(s.fill){
                var c='rgb('+s.fill[0]+','+s.fill[1]+','+s.fill[2]+')';
                o.push('<polygon points="'+pts+'" fill="'+c+'" stroke="none"/>');
              } else {
                o.push('<'+(s.closed?'polygon':'polyline')+' points="'+pts+
                       '" fill="none" stroke="#000" stroke-width="'+Math.max(w,0.6)+'"/>');
              }
            } else if(s.type==='text'){
              var p=tp(s.x,s.y), px=p[0]*k, py=(PAGE.height-p[1])*k;
              // text drawn on the plan is in model inches and shrinks with the
              // scale; text put straight on the sheet is already paper inches.
              var hp = s.h * (s.__paper ? 1 : scaleFactor(STATE.scale));
              var fs = hp * k / 0.717;
              if(fs<1.5) return '';
              var anchor = s.__paper ? 'start' : 'middle';
              var base   = s.__paper ? 'alphabetic' : 'central';
              var rot = s.rotation ? ' transform="rotate('+(-s.rotation)+','+px.toFixed(1)+','+py.toFixed(1)+')"' : '';
              o.push('<text x="'+px.toFixed(1)+'" y="'+py.toFixed(1)+'" font-family="Helvetica,Arial"'+
                     ' font-size="'+fs.toFixed(1)+'" text-anchor="'+anchor+'" dominant-baseline="'+base+
                     '" fill="#000"'+(s.bold?' font-weight="700"':'')+(s.italic?' font-style="italic"':'')+
                     rot+'>'+esc(s.text)+'</text>');
            } else if(s.type==='table'){
              var cols=s.col_widths||[], rh=s.row_h||0.22, th=s.h||0.1;
              var all=[s.headers||[]].concat(s.rows||[]);
              var tw=cols.reduce(function(a,b){return a+b;},0);
              function L(x1,y1,x2,y2){
                o.push('<line x1="'+(x1*k).toFixed(1)+'" y1="'+((PAGE.height-y1)*k).toFixed(1)+
                       '" x2="'+(x2*k).toFixed(1)+'" y2="'+((PAGE.height-y2)*k).toFixed(1)+
                       '" stroke="#000" stroke-width="0.7"/>');
              }
              for(var i=0;i<=all.length;i++) L(s.x, s.y-i*rh, s.x+tw, s.y-i*rh);
              var xa=0;
              L(s.x, s.y, s.x, s.y-all.length*rh);
              for(var c=0;c<cols.length;c++){ xa+=cols[c]; L(s.x+xa, s.y, s.x+xa, s.y-all.length*rh); }
              all.forEach(function(row,ri){
                var cx=0;
                row.forEach(function(cell,ci){
                  var fs=th*k/0.717;
                  if(fs>=1.5&&cell) o.push('<text x="'+((s.x+cx+0.05)*k).toFixed(1)+'" y="'+
                    ((PAGE.height-(s.y-(ri+1)*rh+rh*0.3))*k).toFixed(1)+
                    '" font-family="Helvetica,Arial" font-size="'+fs.toFixed(1)+
                    '" fill="#000"'+(ri===0?' font-weight="700"':'')+'>'+esc(cell)+'</text>');
                  cx+=cols[ci]||1.2;
                });
              });
            } else if(s.type==='image'){
              var a=tp(s.x,s.y);
              var ix=(a[0]*k).toFixed(1), iy=((PAGE.height-(s.y+s.h))*k).toFixed(1);
              var iw=(s.w*k).toFixed(1), ih=(s.h*k).toFixed(1);
              var t=URLS[s.path];
              if(t){
                // meet = keep the proportions and sit in the middle, which is
                // exactly what plan_pdf does when it prints.
                o.push('<image x="'+ix+'" y="'+iy+'" width="'+iw+'" height="'+ih+
                       '" preserveAspectRatio="xMidYMid meet" href="'+t+'"/>');
              } else {
                o.push('<rect x="'+ix+'" y="'+iy+'" width="'+iw+'" height="'+ih+
                       '" fill="none" stroke="#bbb" stroke-dasharray="3 3"/>');
              }
            }
            return o.join('');
          }

          function activePage(){
            if(!DOC||!DOC.pages.length) return null;
            var i=STATE.active||0;
            return DOC.pages[i]||DOC.pages[0];
          }

          function fitK(){
            var stage=$('stage');
            return Math.min((stage.clientWidth-56)/PAGE.width,(stage.clientHeight-56)/PAGE.height);
          }

          function render(){
            PAGE=activePage();
            if(!DOC||!PAGE) return;
            var k=fitK()*(ZOOM||1);
            var W=PAGE.width*k, H=PAGE.height*k;
            function same(x,y){ return [x,y]; }

            var o=['<svg xmlns="http://www.w3.org/2000/svg" width="'+W.toFixed(0)+'" height="'+H.toFixed(0)+
                   '" viewBox="0 0 '+W.toFixed(0)+' '+H.toFixed(0)+'" style="display:block">'];
            o.push('<rect width="100%" height="100%" fill="#fff"/>');

            var v=(PAGE.views||[])[0];
            if(v){
              var sf=scaleFactor(STATE.scale);
              var cx=v.x+v.w/2, cy=v.y+v.h/2;
              var toPaper=function(mx,my){ return [cx+(mx-STATE.origin_x)*sf, cy+(my-STATE.origin_y)*sf]; };
              o.push('<clipPath id="vclip"><rect x="'+(v.x*k).toFixed(1)+'" y="'+((PAGE.height-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+'"/></clipPath>');
              o.push('<g clip-path="url(#vclip)">');
              var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
              if(cv) cv.layers.forEach(function(l){
                if(STATE.hidden.indexOf(l.name)>=0) return;
                l.shapes.forEach(function(s){ o.push(shapeSVG(s,toPaper,k)); });
              });
              o.push('</g>');
              // the window itself, so the user can see where the plan may sit
              o.push('<rect x="'+(v.x*k).toFixed(1)+'" y="'+((PAGE.height-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+
                     '" fill="none" stroke="#bcd" stroke-width="1" stroke-dasharray="5 4"/>');
            }

            (PAGE.layers||[]).forEach(function(l){
              if(STATE.hidden.indexOf(l.name)>=0) return;
              l.shapes.forEach(function(s){ s.__paper=true; o.push(shapeSVG(s,same,k)); });
            });
            o.push('</svg>');
            $('sheetWrap').innerHTML=o.join('');
            hookDrag();
          }

          function setZoom(z){
            ZOOM = z;
            STATE.zoom = z;
            render();
          }

          // ---- dragging the plan -----------------------------------------
          var DRAG=null;
          function hookDrag(){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return;
            svg.style.cursor='grab';
            svg.onmousedown=function(e){
              var stage=$('stage');
              var pan = e.shiftKey || e.button===1 || !(PAGE.views||[])[0];
              DRAG={x:e.clientX,y:e.clientY,ox:STATE.origin_x,oy:STATE.origin_y,
                    pan:pan, sl:stage.scrollLeft, st:stage.scrollTop};
              svg.style.cursor= pan ? 'move' : 'grabbing';
              e.preventDefault();
            };
          }

          function onMove(e){
            if(!DRAG) return;
            var stage=$('stage');
            if(DRAG.pan){
              stage.scrollLeft = DRAG.sl-(e.clientX-DRAG.x);
              stage.scrollTop  = DRAG.st-(e.clientY-DRAG.y);
              return;
            }
            var k=fitK()*(ZOOM||1);
            var sf=scaleFactor(STATE.scale);
            STATE.origin_x=DRAG.ox-(e.clientX-DRAG.x)/k/sf;
            STATE.origin_y=DRAG.oy+(e.clientY-DRAG.y)/k/sf;
            render();
          }

          function onUp(){
            if(!DRAG) return;
            var moved=!DRAG.pan;
            DRAG=null;
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor='grab';
            if(moved) push();
          }

          // ---- talking to Ruby -------------------------------------------
          function push(){ sketchup.set_state(JSON.stringify(STATE)); }

          function loadSheet(p){
            DOC=p.doc; STATE=p.state; BOUNDS=p.bounds; SCALES=p.scales;
            URLS={};
            (p.images||[]).forEach(function(im){ if(im.url) URLS[im.path]=im.url; });
            if(STATE.active===undefined||STATE.active===null) STATE.active=0;
            ZOOM = STATE.zoom || null;
            PAGE=DOC.pages[0];
            SF={};
            // 12" = 1' means one foot of building is 12 paper inches
            var per={'12"':12,'6"':6,'3"':3,'1-1/2"':1.5,'1"':1,'3/4"':0.75,'1/2"':0.5,
                     '3/8"':0.375,'1/4"':0.25,'3/16"':0.1875,'1/8"':0.125,'3/32"':0.09375,
                     '1/16"':0.0625,'1/32"':0.03125,'1/64"':0.015625,'1/128"':0.0078125};
            SCALES.forEach(function(s){ SF[s]=(per[s]||0.25)/12; });
            // First time on this model: nothing was ever chosen, so open on a
            // scale that shows the whole house instead of an empty-looking
            // sheet. From then on his own choice is kept, whatever it is.
            var first = (STATE.origin_x===undefined||STATE.origin_x===null);
            if(first) centerPlan(true);
            fill('size',p.page_sizes,STATE.size);
            fill('scale',SCALES,STATE.scale);
            $('address').value=DOC.job_address||'';
            $('num').value=STATE.sheet_number||'';
            $('title').value=STATE.sheet_title||'';
            $('ownpage').checked = STATE.tables_own_page!==false;
            siteDone(STATE.site_count||0, null);
            buildLayers();
            fillPages();
            if(first){ fitPlan(); return; }
            showFit();
            render();
          }

          function applyPages(pages){
            DOC.pages=pages;
            if(STATE.active>=pages.length) STATE.active=0;
            fillPages();
            buildLayers();
            showFit();
            render();
          }

          // One list for every sheet in the set - plan, schedules, renders.
          // Click a row to go there, press the x to throw that sheet away.
          // The plan sheet has no x: it is the drawing, not an extra.
          function fillPages(){
            var box=$('pages'); box.innerHTML='';
            (DOC.pages||[]).forEach(function(p,i){
              var row=document.createElement('div');
              row.className='pg'+(i===(STATE.active||0)?' sel':'');
              row.onclick=function(){
                STATE.active=i; fillPages(); showFit(); render(); push();
              };
              var num=document.createElement('b');
              num.textContent=p.sheet_number||('#'+(i+1));
              row.appendChild(num);
              var nm=document.createElement('span');
              nm.textContent=p.name; nm.title=p.name;
              row.appendChild(nm);
              if(p.kind && p.kind!=='plan'){
                var x=document.createElement('button');
                x.textContent='×'; x.title='הסר את הדף הזה';
                x.onclick=function(e){
                  e.stopPropagation();
                  sketchup.delete_page(JSON.stringify({kind:p.kind, ref:p.ref}));
                };
                row.appendChild(x);
              }
              box.appendChild(row);
            });
          }

          function fill(id,list,val){
            var el=$(id); el.innerHTML='';
            list.forEach(function(s){
              var o=document.createElement('option'); o.value=s; o.textContent=s;
              if(s===val) o.selected=true; el.appendChild(o);
            });
          }

          function buildLayers(){
            var box=$('layers'); box.innerHTML='';
            var names=[];
            function add(n){ if(names.indexOf(n)<0) names.push(n); }
            (DOC.canvases||[]).forEach(function(c){ c.layers.forEach(function(l){ add(l.name); }); });
            // every sheet's layers, so a layer that moved to another page can
            // still be turned off from here
            (DOC.pages||[]).forEach(function(p){ (p.layers||[]).forEach(function(l){ add(l.name); }); });
            if(STATE.hidden.indexOf('SCHEDULES')>=0) add('SCHEDULES');
            names.forEach(function(n){
              var lab=document.createElement('label'); lab.className='chk';
              var cb=document.createElement('input'); cb.type='checkbox';
              cb.checked=STATE.hidden.indexOf(n)<0;
              cb.onchange=function(){
                var i=STATE.hidden.indexOf(n);
                if(cb.checked){ if(i>=0) STATE.hidden.splice(i,1); } else if(i<0) STATE.hidden.push(n);
                render(); push();
              };
              lab.appendChild(cb);
              lab.appendChild(document.createTextNode(n));
              box.appendChild(lab);
            });
          }

          function centerPlan(quiet){
            if(!BOUNDS) return;
            STATE.origin_x=(BOUNDS[0]+BOUNDS[2])/2;
            STATE.origin_y=(BOUNDS[1]+BOUNDS[3])/2;
            if(!quiet){ render(); push(); }
          }

          // The user pressed a button, so this one MAY change the scale: the
          // biggest one in his list that holds the whole drawing, centred.
          function fitPlan(){
            var pg=activePage(), v=pg&&(pg.views||[])[0];
            if(!BOUNDS||!v) return;
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              if((BOUNDS[2]-BOUNDS[0])*SF[s]<=v.w&&(BOUNDS[3]-BOUNDS[1])*SF[s]<=v.h) best=s;
            });
            if(best){ STATE.scale=best; $('scale').value=best; }
            centerPlan(true);
            ZOOM=null; STATE.zoom=null;
            showFit(); render(); push();
          }

          // says what would fit. never changes the scale by itself.
          function showFit(){
            var pg=activePage();
            var v=pg&&(pg.views||[])[0];
            if(!BOUNDS||!v){ $('fit').textContent=''; return; }
            var sf=scaleFactor(STATE.scale);
            var mw=(BOUNDS[2]-BOUNDS[0])*sf, mh=(BOUNDS[3]-BOUNDS[1])*sf;
            if(mw<=v.w&&mh<=v.h){ $('fit').textContent='נכנס בדף ✓'; $('fit').style.color='#8fdf8f'; return; }
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              var f=SF[s];
              if((BOUNDS[2]-BOUNDS[0])*f<=v.w&&(BOUNDS[3]-BOUNDS[1])*f<=v.h) best=s;
            });
            $('fit').textContent='לא נכנס. הכי גדול שנכנס: '+(best||'—');
            $('fit').style.color='#f0a860';
          }

          // ---- carrying dragged / ticked files across ----------------------
          //
          // The window never learns where a file lives, only what is in it. So
          // the bytes go to Ruby in pieces and Ruby writes them down.
          //
          // Each piece is base64'd on its own and decoded on its own at the
          // other end, so the pieces can be any size - the bytes are appended,
          // never the text. 786432 is three quarters of a megabyte: big enough
          // that a 7MB render is ten trips and not two hundred, small enough
          // that no single message is enormous. It also divides by three, so
          // no piece wastes room on padding.
          //
          // Ruby answers every piece before the next one is sent. Without that
          // the window would race ahead and queue a whole 100MB of messages.
          var CHUNK = 786432;
          var DROP = { list:[], fi:0, off:0, busy:false };

          function takeFiles(list){
            if(DROP.busy) return;
            var files=[];
            for(var i=0;i<list.length;i++){
              var f=list[i];
              if(/\.(jpe?g|png)$/i.test(f.name)) files.push(f);
            }
            if(!files.length){ $('imginfo').textContent='לא היו תמונות בגרירה'; return; }
            DROP.list=files; DROP.fi=0; DROP.busy=true;
            setBusy(true);
            nextFile();
          }

          function setBusy(on){
            ['addmany','pdf','rebuild'].forEach(function(id){
              if($(id)) $(id).disabled=on;
            });
          }

          function nextFile(){
            if(DROP.fi>=DROP.list.length){
              $('imginfo').textContent='מסיים...';
              sketchup.drop_finish();
              DROP.busy=false; setBusy(false);
              return;
            }
            var f=DROP.list[DROP.fi];
            $('imginfo').textContent='מעתיק '+(DROP.fi+1)+' מתוך '+DROP.list.length+
                                     ' · '+f.name;
            sketchup.drop_begin(JSON.stringify({name:f.name,size:f.size}));
          }

          function dropReady(already){
            if(already){ sketchup.drop_end(); return; }
            DROP.off=0; sendChunk();
          }

          function sendChunk(){
            var f=DROP.list[DROP.fi];
            if(DROP.off>=f.size){ sketchup.drop_end(); return; }
            var end=Math.min(DROP.off+CHUNK,f.size);
            var blob=f.slice(DROP.off,end);
            DROP.off=end;
            var r=new FileReader();
            r.onload=function(){
              var s=r.result;
              sketchup.drop_chunk(s.substring(s.indexOf(',')+1));
            };
            r.onerror=function(){ dropFailed('לא הצלחתי לקרוא את '+f.name); };
            r.readAsDataURL(blob);
          }

          function chunkDone(){ sendChunk(); }
          function fileDone(){ DROP.fi++; nextFile(); }
          function dropFailed(m){
            $('imginfo').textContent='שגיאה: '+m;
            DROP.busy=false; setBusy(false);
          }

          function imageReport(n, err){
            $('imginfo').textContent = err ? ('שגיאה: '+err)
              : (n ? (n===1 ? 'נוספה תמונה אחת' : ('נוספו '+n+' תמונות'))
                   : 'לא נבחר כלום');
          }

          function siteDone(n, err){
            $('siteinfo').textContent = err ? ('לא נוסף: ' + err)
              : (n ? (n + ' קווים על הדף') : 'אין גיאומטריה חופשית');
          }

          // Says where it got to, so an empty result is never a mystery.
          function siteReport(sel, r){
            var t = 'נבחרו ' + sel + ' · קווים במודל ' + r.edges +
                    ' · נוספו ' + r.lines + ' · על הדף ' + (r.total||r.lines);
            if(!r.edges)      t += '  ⟵ אין קווים במה שבחרת';
            else if(!r.lines) t += '  ⟵ כל הקווים סוננו';
            else if(!r.kept)  t += '  ⟵ גדול מדי לשמירה, יישאר עד סגירת סקצ\'אפ';
            $('siteinfo').textContent = t;
          }

          function exportDone(path){
            $('msg').textContent = path ? ('נשמר: '+path) : 'בוטל';
          }
          function exportFailed(m){ $('msg').textContent='שגיאה: '+m; }

          // ---- wiring -----------------------------------------------------
          window.addEventListener('load',function(){
            $('size').onchange=function(){ STATE.size=this.value; push(); };
            $('scale').onchange=function(){ STATE.scale=this.value; showFit(); render(); push(); };
            $('ownpage').onchange=function(){ STATE.tables_own_page=this.checked; push(); };
            $('zin').onclick=function(){ setZoom((ZOOM||1)*1.3); };
            $('zout').onclick=function(){ setZoom(Math.max((ZOOM||1)/1.3,0.2)); };
            $('zfit').onclick=function(){ setZoom(null); };
            $('stage').addEventListener('wheel',function(e){
              e.preventDefault();
              var z=(ZOOM||1)*(e.deltaY<0?1.15:1/1.15);
              setZoom(Math.min(Math.max(z,0.2),14));
            },{passive:false});
            window.addEventListener('mousemove',onMove);
            window.addEventListener('mouseup',onUp);
            $('land').onclick=function(){ STATE.orientation='landscape'; push(); };
            $('port').onclick=function(){ STATE.orientation='portrait'; push(); };
            $('center').onclick=function(){ centerPlan(false); };
            $('fitplan').onclick=function(){ fitPlan(); };
            $('rebuild').onclick=function(){ sketchup.rebuild(); };
            $('addsel').onclick=function(){
              $('siteinfo').textContent='קורא מהמודל...'; sketchup.add_selection();
            };
            $('clrsel').onclick=function(){ sketchup.clear_selection(); };
            $('addmany').onclick=function(){ $('filepick').value=''; $('filepick').click(); };
            $('filepick').onchange=function(){ takeFiles(this.files||[]); };

            // Drop anywhere on the window. The browser opens a dropped file in
            // place unless BOTH of these are stopped, which loses the sheet.
            var deep=0;
            window.addEventListener('dragenter',function(e){
              e.preventDefault(); deep++; $('curtain').className='on';
            });
            window.addEventListener('dragover',function(e){ e.preventDefault(); });
            window.addEventListener('dragleave',function(e){
              e.preventDefault(); if(--deep<=0){ deep=0; $('curtain').className=''; }
            });
            window.addEventListener('drop',function(e){
              e.preventDefault(); deep=0; $('curtain').className='';
              takeFiles((e.dataTransfer&&e.dataTransfer.files)||[]);
            });
            $('pdf').onclick=function(){ $('msg').textContent='שומר...'; sketchup.export_pdf(JSON.stringify(STATE)); };
            ['address','num','title'].forEach(function(id){
              $(id).onchange=function(){
                STATE.address=$('address').value;
                STATE.sheet_number=$('num').value;
                STATE.sheet_title=$('title').value;
                push();
              };
            });
            window.addEventListener('resize',render);
            sketchup.sheet_ready();
          });
          </script></body></html>
        HTML
      end
    end
  end
end

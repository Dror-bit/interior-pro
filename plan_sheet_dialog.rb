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
    # The window is told where the paper really put the plan (2026-10-07,
    # see window_origin). false = it is handed the remembered place as before.
    USE_ORIGIN_SYNC = true unless const_defined?(:USE_ORIGIN_SYNC, false)
    # The window draws a run of plain lines as ONE element and does not redraw
    # the page strip while the plan is being moved or zoomed (2026-10-07, see
    # layerSVG in the page). false = one element per line and the strip on
    # every redraw, as before.
    USE_FAST_SHEET = true unless const_defined?(:USE_FAST_SHEET, false)
    # The wheel zooms to the spot under the mouse by PLACING the sheet there
    # (2026-10-07, see zoomAt in the page). false = the older way, which could
    # only scroll and so ran away to one side.
    USE_ZOOM_TO_MOUSE = true unless const_defined?(:USE_ZOOM_TO_MOUSE, false)
    # A sheet sent again to a window that is already open leaves the zoom where
    # the user has it (2026-10-07, see loadSheet in the page). false = every
    # refresh goes back to the zoom saved on the model, as before.
    USE_KEEP_VIEW = true unless const_defined?(:USE_KEEP_VIEW, false)
    # The wheel goes in to 200x instead of 14x, and past a certain closeness the
    # lines stop getting fatter (2026-10-07, see ZMAX / KSTROKE in the page).
    # false = stops at 14x and every line thickens with the zoom, as before.
    USE_DEEP_ZOOM = true unless const_defined?(:USE_DEEP_ZOOM, false)
    # Rubbing a loose line out takes it off the sheet in the window at once and
    # only tells Ruby which one went; nothing is built again (2026-10-07, see
    # drop_site_line). false = the whole sheet is rebuilt and sent for every
    # sweep of the eraser, as before.
    USE_FAST_ERASE = true unless const_defined?(:USE_FAST_ERASE, false)
    # Escape drops whatever is half done AND puts the select arrow back in his
    # hand (2026-10-07, see escapeAll in the page). false = Escape only drops
    # the half-done thing and leaves him in the same tool, as before.
    USE_ESCAPE_EXITS = true unless const_defined?(:USE_ESCAPE_EXITS, false)
    # Ctrl+Z in the sheet window takes back the last thing done to the drawing:
    # lines rubbed out come back where they were, and so does any change to the
    # hand-drawn dimensions and notes (2026-10-07, see undoLast in the page and
    # undo_site_drop here). false = Ctrl+Z does nothing, as before.
    USE_SHEET_UNDO = true unless const_defined?(:USE_SHEET_UNDO, false)
    # Loose lines can be PICKED with the select arrow - a click, Shift+click for
    # more, a rubber band - and Delete takes every picked one at once
    # (2026-10-07, see SSEL in the page). false = only the eraser reaches them.
    USE_LINE_PICK = true unless const_defined?(:USE_LINE_PICK, false)

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
              # A fresh read starts the rubbing-out over: whatever was taken
              # off the sheet may well be in this batch again, and putting the
              # old list back would draw those lines twice.
              self.site_dropped = []
              save_state(st)
              @doc = nil
              push_all(dlg)
              r = InteriorPro::PlanGeometry.last_report
              r[:total] = site_lines.length
              r[:kept]  = @site_saved ? 1 : 0
              dlg.execute_script("siteReport(#{JSON.generate(sel.length)}, #{JSON.generate(r)})")
            end
          rescue StandardError => e
            puts "[Sheet] add_selection: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
            dlg.execute_script("siteDone(0, #{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('clear_selection') do |_|
          begin
            st = load_state
            st['site_pids'] = []
            save_state(st)
            self.site_lines = []
            self.site_dropped = []
            @doc = nil
            push_all(dlg)
            dlg.execute_script('siteDone(0, null)')
          rescue StandardError => e
            puts "[Sheet] clear_selection: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # Rubbing out ONE line (2026-08-17).
        #
        # "Clear the free geometry" throws away the whole back yard. What the
        # user actually asked for is smaller and sharper: the seam down the
        # middle of the pool coping gone, and the three lines that cross the
        # path, and NOTHING else. A cleaner drawing, not an empty one.
        #
        # The trick is that no lookup is needed. PlanGeometry.build! writes the
        # lines onto the SITE layer in the order they sit in the list, one
        # polyline each, so shape number i on the sheet IS site_lines[i]. The
        # window sends a number and this takes that number out of the list.
        #
        # NOTHING HERE TOUCHES THE MODEL. The seam in the pool coping is a real
        # edge between two real faces and it stays exactly where it is; only
        # the drawing loses it. That is the whole point of the feature - the
        # user said so in the same breath as he asked for it.
        dlg.add_action_callback('drop_site_line') do |_, json|
          begin
            r = JSON.parse(json.to_s)
            # One line, or a whole sweep of them (2026-08-19). Dragging the
            # eraser across the sheet the way SketchUp does can cross a dozen
            # lines, and rebuilding the document once per line would make it
            # crawl - so the window collects them and sends the lot.
            want  = r.key?('is') ? Array(r['is']).map(&:to_i) : [r['i'].to_i]
            lines = site_lines
            # Highest index first, so removing one cannot move the next one.
            gone = want.uniq.select { |i| i >= 0 && i < lines.length }.sort.reverse
            if gone.empty?
              # Out of range is not worth an error message - the sheet was
              # rebuilt under the mouse. Just say where things stand.
              dlg.execute_script("siteDropped(#{JSON.generate(lines.length)}, " \
                                 "#{JSON.generate(site_dropped.length)})")
            else
              t0 = Time.now
              # THE QUICK ROAD (2026-10-07). The window has ALREADY taken these
              # lines off the sheet it is showing, by the same numbers, and is
              # only saying which ones went. Nothing has to be built: the list
              # loses them, the document Ruby is holding loses the same shapes
              # (shape number i IS line number i, and stays so), and the answer
              # is two numbers. The user: "לוקח לו קצת זמן עד שהוא מוחק וצריך
              # שזה יהיה יותר מהיר" - before this, every sweep read the whole
              # model again, built every wall and fifteen thousand lines, and
              # sent a megabyte and a half back to be drawn from nothing.
              #
              # Only when both sides agree how many lines there were. If they
              # do not, something is out of step and the old road - build it,
              # send all of it - puts the window right.
              before = lines.length
              quiet  = USE_FAST_ERASE && r['quiet'] == true && r['n'].to_i == before
              gone.each do |i|
                site_dropped.push(lines[i])
                lines = lines[0, i] + lines[(i + 1)..-1]
              end
              self.site_lines = lines
              road = 'quick'
              unless quiet && drop_from_document!(gone, before)
                road = quiet ? 'full (document out of step)' : 'full'
                @doc = nil
                push_all(dlg)
              end
              dlg.execute_script("siteDropped(#{JSON.generate(site_lines.length)}, " \
                                 "#{JSON.generate(site_dropped.length)})")
              erase_trace("#{gone.length} gone, #{site_lines.length} left, #{road}, " \
                          "#{((Time.now - t0) * 1000).round} ms")
            end
          rescue StandardError => e
            puts "[Sheet] drop_site_line: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # Everything rubbed out comes back at once.
        #
        # This window has no general undo, and without this a line taken off by
        # mistake would mean pressing "add what is selected" again - which
        # would undo every OTHER rub-out along with it. One button, and the
        # decision is reversible.
        dlg.add_action_callback('restore_site_lines') do |_|
          begin
            back = site_dropped
            unless back.empty?
              self.site_lines   = site_lines + back
              self.site_dropped = []
              @doc = nil
              push_all(dlg)
            end
            dlg.execute_script("siteDropped(#{JSON.generate(site_lines.length)}, 0)")
          rescue StandardError => e
            puts "[Sheet] restore_site_lines: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # Ctrl+Z on rubbed-out lines (2026-10-07).
        #
        # "אם מחקתי משהו ואני לוחץ קונטרול Z הוא צריך לחזור." The button above
        # puts back EVERYTHING rubbed out, at the end of the list. This puts back
        # exactly the lines of ONE sweep, each at the number it had - so shape
        # number i is still line number i, and the sweep before it can be taken
        # back next, and the one before that.
        #
        # The window has already put the lines back on its own sheet and sends
        # each one with its number. Ruby checks three things before believing
        # it: both sides count the same number of lines, every number fits, and
        # every line really is one that was rubbed out (it is waiting in
        # site_dropped). Anything else is out of step, and the whole sheet is
        # built and sent so the window shows what Ruby actually has.
        dlg.add_action_callback('undo_site_drop') do |_, json|
          begin
            t0     = Time.now
            r      = JSON.parse(json.to_s)
            items  = Array(r['items']).map { |it| [it['i'].to_i, it['p']] }.sort_by(&:first)
            lines  = site_lines.dup
            left   = site_dropped.dup
            before = lines.length
            good   = USE_SHEET_UNDO && !items.empty? && r['n'].to_i == before
            if good
              items.each do |i, pts|
                k = pts.is_a?(Array) ? left.index(pts) : nil
                if k.nil? || i < 0 || i > lines.length
                  good = false
                  break
                end
                left.delete_at(k)
                lines.insert(i, pts)
              end
            end
            road = 'quick'
            if good
              self.site_lines   = lines
              self.site_dropped = left
              unless put_back_in_document!(items, before)
                road = 'full (document out of step)'
                @doc = nil
                push_all(dlg)
              end
            else
              road = 'REFUSED - out of step, sheet sent again'
              @doc = nil
              push_all(dlg)
            end
            dlg.execute_script("siteDropped(#{JSON.generate(site_lines.length)}, " \
                               "#{JSON.generate(site_dropped.length)})")
            erase_trace("undo: #{items.length} back, #{site_lines.length} on the sheet, #{road}, " \
                        "#{((Time.now - t0) * 1000).round} ms")
          rescue StandardError => e
            puts "[Sheet] undo_site_drop: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
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
            puts "[Sheet] drop_begin: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
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
            puts "[Sheet] drop_chunk: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
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
            puts "[Sheet] drop_end: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
            dlg.execute_script("dropFailed(#{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('drop_finish') do |_|
          begin
            list = Array(@drop_list)
            @drop_list = []
            add_images!(dlg, list)
          rescue StandardError => e
            puts "[Sheet] drop_finish: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
            dlg.execute_script("dropFailed(#{JSON.generate(e.message)})")
          end
        end

        # The window shows ONE list of every sheet - plan, schedules, renders -
        # and an x on each. What "throw this sheet away" means depends on what
        # the sheet is, and only Ruby knows: a render leaves the picture list, a
        # schedules sheet gets its layer turned off. The plan sheet has no x,
        # because the drawing is the point of the whole document.
        # The logo. ONE file, so UI.openpanel is right here - it hands back a
        # real path, and nothing has to be copied anywhere. (The pictures go the
        # long way round only because SketchUp cannot pick several at once.)
        dlg.add_action_callback('choose_logo') do |_|
          begin
            path = UI.openpanel('בחר קובץ לוגו', logo_dir,
                                'Images|*.jpg;*.jpeg;*.png;*.JPG;*.JPEG;*.PNG||')
            if path
              st = load_state
              st['logo'] = path.to_s.tr('\\', '/')
              save_state(st)
              @doc = nil
              push_all(dlg)
            else
              dlg.execute_script('logoDone(null)')
            end
          rescue StandardError => e
            puts "[Sheet] choose_logo: #{e.class}: #{e.message}\n  " +
                 Array(e.backtrace).first(4).join("\n  ")
            dlg.execute_script("logoDone(#{JSON.generate(e.message)})")
          end
        end

        dlg.add_action_callback('clear_logo') do |_|
          begin
            st = load_state
            st['logo'] = nil
            save_state(st)
            @doc = nil
            push_all(dlg)
          rescue StandardError => e
            puts "[Sheet] clear_logo: #{e.class}: #{e.message}"
          end
        end

        # The x in the page list. Every sheet can go now, the plan sheet
        # included (2026-08-19) - the old refusal is gone.
        #
        # The three kinds are removed three different ways because they are
        # made three different ways, and using each page's own maker is what
        # keeps this from becoming a fourth source of truth about what a page
        # set contains (the mistake §3 of ROOF_TILES_PROPOSAL warns about).
        dlg.add_action_callback('delete_page') do |_, json|
          begin
            r    = JSON.parse(json.to_s)
            st   = load_state
            kind = r['kind'].to_s
            kind = 'plan' if kind.empty?
            # Never leave him with no pages at all: the window would draw
            # nothing and PlanPDF.export refuses to print an empty set.
            if document.pages.length <= 1
              dlg.execute_script("imageReport(0, #{JSON.generate('זה הדף האחרון - אי אפשר למחוק אותו')})")
              next
            end
            skip = Array(st['pdf_skip']).map(&:to_s)
            case kind
            when 'image'
              list = Array(st['images'])
              i = r['ref'].to_i
              if i >= 0 && i < list.length
                list.delete_at(i)
                # A picture key carries the picture's PLACE in the list, so
                # every picture after the one that went shuffles down. Without
                # this the ticks would silently start pointing one sheet along.
                skip = shift_image_keys(skip, i)
              end
              st['images'] = list
            when 'schedules'
              st['hidden'] = (Array(st['hidden']) +
                              [InteriorPro::PlanTables::LAYER]).uniq
              skip -= ['schedules']
            when 'plan'
              st['drop_plan'] = true
              skip -= ['plan']
            else
              dlg.execute_script("imageReport(0, #{JSON.generate("דף לא מוכר: #{kind}")})")
              next
            end
            st['pdf_skip'] = skip
            st['active'] = 0
            save_state(st)
            @doc = nil
            push_all(dlg)
          rescue StandardError => e
            puts "[Sheet] delete_page: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
            dlg.execute_script("imageReport(0, #{JSON.generate(e.message)})")
          end
        end

        # Putting the plan sheet back. The x is a real delete, and a real
        # delete with no way back is a trap - a picture can be added again from
        # the file picker and the schedules from their own tick, but the plan
        # sheet has no other door. This is that door, and it only shows in the
        # window while the plan sheet is actually missing.
        dlg.add_action_callback('restore_plan') do |_|
          begin
            st = load_state
            st['drop_plan'] = false
            st['active'] = 0
            save_state(st)
            @doc = nil
            push_all(dlg)
          rescue StandardError => e
            puts "[Sheet] restore_plan: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        dlg.add_action_callback('set_state') do |_, json|
          begin
            st = JSON.parse(json.to_s)
            save_state(st)
            apply_state!(document, st)
            push_pages(dlg)
          rescue StandardError => e
            puts "[Sheet] set_state: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # How big the writing is (2026-08-17).
        #
        # Its own way in rather than riding on set_state, because of WHERE the
        # writing lives. set_state answers with push_pages, which ships the
        # pages and the hand-drawn marks - everything that sits on paper. But
        # the dimension numbers, the room names and the door tags are on the
        # MODEL canvas, which push_pages deliberately leaves alone so the plan
        # does not flicker every time a control moves. Resizing them and
        # answering with push_pages would change the PDF and leave the picture
        # in the window exactly as it was: the user types 130, sees nothing,
        # and reports it as broken.
        #
        # A full push is cheap enough here - nobody drags a text size.
        dlg.add_action_callback('set_text_scale') do |_, json|
          begin
            r  = JSON.parse(json.to_s)
            st = load_state
            st['text_scale'] = (st['text_scale'] || {}).merge(r || {})
            save_state(st)
            apply_state!(document, st)
            push_all(dlg)
          rescue StandardError => e
            puts "[Sheet] set_text_scale: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # One label's own settings (2026-08-17).
        #
        #   { key: "ROOMS|ROOM 2|1", pct: 150, bold: true }
        #   { key: "...", clear: true }        - back to whatever its group says
        #
        # Full push for the same reason set_text_scale needs one: most labels
        # live on the MODEL canvas, which push_pages leaves alone.
        dlg.add_action_callback('set_text_mark') do |_, json|
          begin
            r   = JSON.parse(json.to_s)
            key = r['key'].to_s
            if key.empty?
              puts '[Sheet] set_text_mark: no key'
            else
              st = load_state
              m  = (st['text_marks'] || {}).dup
              if r['clear']
                m.delete(key)
              else
                cur = (m[key] || {}).dup
                cur['pct']    = r['pct'].to_f if r.key?('pct')
                cur['bold']   = !!r['bold']   if r.key?('bold')
                cur['italic'] = !!r['italic'] if r.key?('italic')
                # Where he shoved it (2026-08-19). Merged, not replaced, so a
                # drag does not wipe the size he set and the size box does not
                # snap the label back.
                cur['dx'] = r['dx'].to_f if r.key?('dx')
                cur['dy'] = r['dy'].to_f if r.key?('dy')
                m[key] = cur
              end
              st['text_marks'] = m
              save_state(st)
              apply_state!(document, st)
              push_all(dlg)
            end
          rescue StandardError => e
            puts "[Sheet] set_text_mark: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # ---- the probe (2026-08-19) ---------------------------------------
        #
        # Three rounds went by arguing about why a click in this window does
        # not find the dimension under it. The window cannot say: an error in
        # an event handler is swallowed by the page, and a near miss looks
        # exactly like a dead handler. So every press in select or rubber mode
        # writes down what the hit test was given and what it answered, and the
        # file gets read. Same habit as debug_change_watch.rb, which is the
        # only reason the wall bug was found rather than argued about.
        #
        # READ ONLY as far as the model is concerned - it appends to a text
        # file beside the plugin and touches nothing else. Switch it off with
        #   InteriorPro::PlanSheetDialog.probe = false
        dlg.add_action_callback('sheet_probe') do |_, json|
          begin
            next unless probe?
            path = File.join(File.dirname(__FILE__), 'sheet_probe.txt')
            File.open(path, 'a') { |f| f.puts(json.to_s) }
          rescue StandardError => e
            puts "[Sheet] sheet_probe: #{e.class}: #{e.message}"
          end
        end

        dlg.add_action_callback('export_pdf') do |_, json|
          begin
            st = JSON.parse(json.to_s)
            save_state(st)
            apply_state!(document, st)
            # Only the ticked sheets go in (2026-08-19). AFTER apply_state!,
            # never before: that call rebuilds every page, so a list taken
            # first would be holding pages that no longer exist.
            pages = pages_for_pdf(document, st)
            if pages.empty?
              dlg.execute_script("exportFailed(#{JSON.generate('לא סימנת אף דף ל-PDF')})")
              next
            end
            path = UI.savepanel('Save the sheet as PDF', default_dir,
                                default_name(st))
            if path
              path = "#{path}.pdf" unless path.downcase.end_with?('.pdf')
              InteriorPro::PlanPDF.export(document, path, pages: pages)
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
            scale: st['scale'], address: st['address'], marks: st['marks'],
            logo: (st['logo'].to_s.empty? ? nil : st['logo']),
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
          state: st.merge(window_origin(d, st))
                  .merge('site_count'   => site_lines.length,
                          'site_dropped' => site_dropped.length),
          page_sizes: InteriorPro::PlanDoc.page_size_names,
          scales: InteriorPro::PlanDoc.scale_labels,
          images: image_payload(st),
          logo: (st['logo'].to_s.empty? ? nil :
                 { 'path' => st['logo'], 'name' => File.basename(st['logo'].to_s),
                   'url' => file_url(st['logo']),
                   'there' => File.file?(st['logo'].to_s) }),
          bounds: d.canvas('MODEL').bounds,
          # How tall a dimension's number is when the mark does not carry its
          # own height - which is every mark the window makes (2026-08-19).
          # The window needs it to know WHERE that number is before it can let
          # him grab it, and guessing the number here is how the window and the
          # paper start disagreeing. So Ruby says it out loud.
          fast: USE_FAST_SHEET,
          zoom_hold: USE_ZOOM_TO_MOUSE,
          keep_view: USE_KEEP_VIEW,
          deep_zoom: USE_DEEP_ZOOM,
          fast_erase: USE_FAST_ERASE,
          escape_exits: USE_ESCAPE_EXITS,
          undo: USE_SHEET_UNDO,
          line_pick: USE_LINE_PICK,
          dim_text_h: InteriorPro::PlanCanvas.mark_text_h,
          dim_label_off: InteriorPro::PlanCanvas::DIM_LABEL_OFF
        }
        dlg.execute_script("loadSheet(#{JSON.generate(payload)})")
      rescue StandardError => e
        puts "[Sheet] push_all: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
      end

      # Where the window should draw the plan, when that is NOT where the
      # state says.
      #
      # The paper draws the plan from the VIEW's origin; the window draws it
      # from the STATE's (sheetSVG / toPaper). They are the same two numbers -
      # except when layout_pages! finds that the remembered place shows not one
      # inch of the drawing and goes back to the middle. Then the PDF had the
      # plan on it and the window drew a white sheet.
      #
      # 2026-10-07, 6 Bronco Ln: a landscape job, no wall of ours in the model.
      # He brought the plan sheet back, added 21,276 lines of yard, the window
      # said they were on the sheet, and the sheet was empty. Measured with
      # debug_sheet_site.rb: remembered place 399, 671; the yard around
      # 495, -1730; 26,780 lines inside the paper's window and none in his.
      #
      # So every full push says where the paper really is. Only then: a place
      # that does show the drawing is his own and is passed through untouched,
      # and with no place remembered at all nothing is invented, because "no
      # place yet" is how the window knows to fit the drawing the first time.
      # Nothing is written to the model here - the window saves the place
      # itself the next time he touches anything.
      def window_origin(doc, st)
        return {} unless USE_ORIGIN_SYNC
        return {} unless st['origin_x'] && st['origin_y']
        pg = doc.pages.find { |p| p.kind.to_s == 'plan' }
        v  = pg && pg.views.first
        return {} unless v
        return {} if (v.origin_x.to_f - st['origin_x'].to_f).abs < 0.001 &&
                     (v.origin_y.to_f - st['origin_y'].to_f).abs < 0.001
        puts format('[Sheet] the remembered place (%.1f, %.1f) shows nothing of the ' \
                    'drawing - the window is moved to where the paper put it (%.1f, %.1f)',
                    st['origin_x'].to_f, st['origin_y'].to_f, v.origin_x.to_f, v.origin_y.to_f)
        { 'origin_x' => v.origin_x.to_f, 'origin_y' => v.origin_y.to_f }
      rescue StandardError => e
        puts "[Sheet] window_origin: #{e.class}: #{e.message}"
        {}
      end

      # Only the paper changes when a control moves; the plan itself does not,
      # so the shapes stay where they are in the window.
      #
      # The one exception is the hand-drawn marks. They ARE on the plan, and the
      # user has just stretched one, so that single layer goes back too - built
      # by the same Ruby that builds it for the PDF. The window never draws a
      # dimension of its own; if it did, the paper and the preview would slowly
      # stop agreeing, which is the whole thing this file exists to prevent.
      def push_pages(dlg)
        d   = document
        lay = d.canvas('MODEL').layers
               .find { |l| l.name == InteriorPro::PlanCanvas::MARK_LAYER }
        dlg.execute_script("applyPages(#{JSON.generate(d.pages.map(&:to_h))}, " \
                           "#{JSON.generate(lay && lay.to_h)})")
      rescue StandardError => e
        puts "[Sheet] push_pages: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
      end

      # The click probe. On by default while this is being chased down; it
      # costs one line in a text file per press and nothing else.
      # OFF now that it has done its job (2026-08-19): the clicks it recorded
      # said the catch radius was 10 pixels and his presses landed 11-43 away.
      # The code stays - it cost one line per press and it ended three rounds
      # of arguing - and comes back with
      #   InteriorPro::PlanSheetDialog.probe = true
      def probe?
        @probe.nil? ? false : @probe
      end

      def probe=(v)
        @probe = !!v
      end

      # ----------------------------------------------------------- page keys
      #
      # The name a page answers to in the settings.
      #
      # NOT the sheet number and NOT the position in the list: both of those
      # move the instant a sheet is added or thrown away, and a tick that
      # follows them would quietly start meaning a different sheet. The JS side
      # has the same three lines in pageKey() - if one of them changes, both do.
      def page_key(pg)
        k = (pg.respond_to?(:kind) ? pg.kind.to_s : '')
        k = 'plan' if k.empty?
        k == 'image' ? "image:#{pg.ref}" : k
      end

      # Which sheets actually go into the PDF: everything except the ones he
      # un-ticked. PlanPDF.export has always taken opts[:pages]; until
      # 2026-08-19 nobody handed it one and the whole set always printed.
      #
      # Its own method so the suite can call THE code that ships. A copy of
      # these two lines inside rt80 would pass just as happily on the day the
      # callback stopped using them - the trap from HANDOFF 2026-08-19 §3א.
      def pages_for_pdf(doc, st)
        skip = Array(st['pdf_skip']).map(&:to_s)
        return doc.pages.dup if skip.empty?
        doc.pages.reject { |pg| skip.include?(page_key(pg)) }
      end

      # Picture number `removed` has just left st['images'], so every picture
      # after it moves down one. Returns the keys renumbered to match, with the
      # removed one dropped.
      def shift_image_keys(keys, removed)
        Array(keys).each_with_object([]) do |k, out|
          unless k.to_s.start_with?('image:')
            out << k
            next
          end
          n = k.to_s.split(':', 2).last.to_i
          next if n == removed
          out << "image:#{n > removed ? n - 1 : n}"
        end
      end

      # Takes the same shapes out of the document Ruby is holding, so it does
      # not have to be built again. gone = line numbers, HIGHEST FIRST;
      # before = how many lines there were. false = could not, build it again.
      def drop_from_document!(gone, before)
        return true if @doc.nil?        # nothing built yet; the next build reads the list
        cv  = @doc.canvas('MODEL')
        lay = cv.layers.find { |l| l.name == InteriorPro::PlanGeometry::LAYER }
        return false unless lay && lay.shapes.length == before
        gone.each { |i| lay.shapes.delete_at(i) }
        cv.layers.delete(lay) if lay.shapes.empty?
        true
      rescue StandardError => e
        puts "[Sheet] drop_from_document!: #{e.class}: #{e.message}"
        false
      end

      # The other way: the same shapes go back into the document Ruby is
      # holding, each at its number. items = [[number, points], ...] LOWEST
      # FIRST; before = how many lines there were. false = build it again.
      def put_back_in_document!(items, before)
        return true if @doc.nil?
        cv  = @doc.canvas('MODEL')
        lay = cv.layers.find { |l| l.name == InteriorPro::PlanGeometry::LAYER }
        lay = cv.layer(InteriorPro::PlanGeometry::LAYER) if lay.nil? && before.zero?
        return false unless lay && lay.shapes.length == before
        items.each do |i, pts|
          lay.polyline(pts, weight: 0.010)          # written the way PlanGeometry.build! writes it
          lay.shapes.insert(i, lay.shapes.pop)
        end
        true
      rescue StandardError => e
        puts "[Sheet] put_back_in_document!: #{e.class}: #{e.message}"
        false
      end

      # One line per sweep of the eraser, beside the plugin: what went, which
      # road it took and how long Ruby spent on it. Read it instead of asking
      # him how it felt.
      def erase_trace(text)
        File.open(File.join(plugin_dir, 'sheet_erase_trace.txt'), 'a:UTF-8') do |f|
          f.puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}  #{text}"
        end
      rescue StandardError
        nil
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
          'images' => [], 'image_title' => 'RENDERING', 'marks' => [],
          'note_arrow' => true, 'strip' => false, 'open' => {}, 'logo' => nil,
          # Which sheets do NOT go into the PDF (2026-08-19). The user asked
          # for both, and they are different things: a TICK keeps the sheet in
          # the set and only leaves it out of the print, an X throws it away.
          #
          # Held by page_key, never by page number or position - both of those
          # shift the moment a sheet is added or removed, and a tick that
          # quietly slides onto the next sheet is worse than no tick at all.
          'pdf_skip' => [],
          # How far a NEW hand dimension stands off the thing it measures, in
          # inches (2026-08-19). 0 is exactly where dimensions have always been
          # drawn - straight onto the two clicked points - so an old drawing
          # opens unchanged, and the user sets this once instead of shoving
          # every dimension he draws.
          'dim_off' => 0,
          # The plan sheet, thrown away with the x. It is the only page that
          # needs a flag: a picture leaves through st['images'] and the
          # schedules through st['hidden'], both of which already existed.
          'drop_plan' => false,
          # How big the writing is, in per cent. 100 is the drawing exactly as
          # it always looked, so an old model that has never heard of this
          # opens unchanged. See PlanCanvas::TEXT_GROUPS.
          'text_scale' => { 'dims' => 100, 'rooms' => 100,
                            'tags' => 100, 'tables' => 100 },
          # One label at a time, keyed by PlanCanvas.text_key. Empty until he
          # double-clicks something, so an old model is untouched.
          'text_marks' => {} }
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
            # Hand-picked site geometry - backed up like everything else
            # (2026-08-15, see state_backup.rb).
            if defined?(InteriorPro::StateBackup)
              InteriorPro::StateBackup.write!(SITE_ATTR, json)
            else
              Sketchup.active_model.set_attribute(ATTR_DICT, SITE_ATTR, json)
            end
          else
            Sketchup.active_model.delete_attribute(ATTR_DICT, SITE_ATTR)
          end
        rescue StandardError => e
          puts "[Sheet] site_lines: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          @site_saved = false
        end
        @site_lines
      end

      # What has been rubbed off the sheet since the last read or clear, kept
      # so "put them back" has something to put back.
      #
      # In MEMORY ONLY, on purpose. Rubbing out is a drawing decision about the
      # sheet in front of him, not a fact about the model, and the moment he
      # reads the model again he is making that decision over from scratch.
      # Writing it onto the model would also risk the very thing site_lines is
      # careful about: a real back yard is thousands of lines, and a big
      # attribute is swallowed without a word.
      def site_dropped
        @site_dropped ||= []
      end

      def site_dropped=(list)
        @site_dropped = Array(list)
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

      def logo_dir
        st = load_state
        st['logo'].to_s.empty? ? default_dir : File.dirname(st['logo'].to_s)
      rescue StandardError
        default_dir
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
        puts "[Sheet] drop_dir: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
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
        dropped = st.keys - clean.keys - %w[site_count site_dropped]
        puts "[Sheet] save_state dropped: #{dropped.join(', ')}" unless dropped.empty?
        # Through StateBackup since 2026-08-15. The sheet state holds the
        # page, the scale, the image list and every hand-drawn dimension and
        # note - work that cannot be made again by pressing a button. One bad
        # write used to be enough to lose all of it, exactly as it was for the
        # 2D editor's draft. Every write now keeps the version it replaced.
        json = JSON.generate(clean)
        if defined?(InteriorPro::StateBackup)
          InteriorPro::StateBackup.write!(ATTR_STATE, json)
        else
          Sketchup.active_model.set_attribute(ATTR_DICT, ATTR_STATE, json)
        end
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
                     display:flex; align-items:flex-start; justify-content:flex-start; }
            #sheetWrap { background:#fff; box-shadow:0 0 22px rgba(0,0,0,.55);
                         flex:none; margin:auto; }
            h4 { margin:14px 0 6px; font-size:11px; letter-spacing:.08em;
                 text-transform:uppercase; color:#9a9a9a; font-weight:600; }
            h4:first-child { margin-top:0; }
            select, input { width:100%; padding:5px 6px; background:#1e1e1e; color:#eee;
                            border:1px solid #555; border-radius:3px; font-size:13px; }
            .row { display:flex; gap:6px; }
            /* label - box - % on one line, so four sizes fit without scrolling */
            .tsrow { display:flex; align-items:center; gap:6px; margin-top:6px; }
            .tsrow > span:first-child { flex:1; font-size:12px; color:#ccc; }
            .tsrow input { width:64px; flex:none; text-align:center; }
            .tsrow .pc { color:#888; font-size:12px; }
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
                     max-height:210px; overflow-y:auto; background:#1e1e1e;
                     outline:none; }
            #pages:focus { border-color:#1f6feb; }
            #strip { display:none; width:190px; flex:none; background:#242424;
                     border-left:1px solid #111; overflow-y:auto; padding:10px; }
            #strip.on { display:block; }
            .thumb { margin-bottom:12px; cursor:pointer; }
            .thumb .sheet { background:#fff; border:2px solid #444; border-radius:2px;
                            overflow:hidden; display:flex; }
            .thumb.sel .sheet { border-color:#1f6feb; }
            .thumb .cap { font-size:11px; color:#aaa; padding:3px 1px 0;
                          direction:ltr; text-align:left; white-space:nowrap;
                          overflow:hidden; display:flex; align-items:center;
                          gap:5px; }
            .thumb .cap span { overflow:hidden; text-overflow:ellipsis; }
            .thumb .cap input[type=checkbox] { width:auto; margin:0; flex:none;
                                               accent-color:#1f6feb; cursor:pointer; }
            /* a sheet that is staying in the set but out of the print */
            .thumb.off .sheet { opacity:.35; }
            .thumb.off .cap span { text-decoration:line-through; opacity:.6; }
            .thumb.sel .cap { color:#9ecbff; }
            .thumb svg { width:100%; height:auto; }
            /* A section is a box you press. Closed it is a raised blue-grey
               slab; open it turns solid blue and the arrow points down. The
               user asked for headings that stand out and invite a click, with
               everything else folded away behind them. */
            .sec { margin-bottom:7px; }
            .sec > h4 { margin:0; padding:9px 10px; background:#2f3d52;
                        border:1px solid #43587a; border-radius:5px;
                        display:flex; align-items:center; gap:8px; cursor:pointer;
                        color:#dfe7f2; font-size:12px; font-weight:600;
                        letter-spacing:.03em; text-transform:none;
                        user-select:none; }
            .sec > h4:hover { background:#3a4c66; border-color:#5b76a1; }
            .sec.open > h4 { background:#1f6feb; border-color:#1f6feb; color:#fff;
                             border-bottom-left-radius:0; border-bottom-right-radius:0; }
            .sec > h4 .ar { font-size:10px; opacity:.9; width:9px; flex:none; }
            .sec > h4 .tag { margin-right:auto; font-weight:400; font-size:11px;
                             opacity:.8; letter-spacing:0; }
            .sec > .bd { display:none; padding:9px 8px 5px;
                         border:1px solid #43587a; border-top:none;
                         border-radius:0 0 5px 5px; background:#262626; }
            .sec.open > .bd { display:block; }
            .sec > .bd > button:first-child,
            .sec > .bd > select:first-child { margin-top:0; }
            #logoshow { display:none; width:100%; max-height:90px;
                        object-fit:contain; background:#fff; border-radius:3px;
                        padding:6px; margin-bottom:6px; }
            #logoshow.on { display:block; }
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
            /* The tick is what goes into the PDF; the x throws the sheet away.
               A sheet that is staying in the set but out of the print is
               greyed and struck through, so the list says which is which
               without having to open anything. */
            .pg input[type=checkbox] { width:auto; margin:0; flex:none;
                                       accent-color:#1f6feb; cursor:pointer; }
            .pg.off b, .pg.off span { opacity:.45; text-decoration:line-through; }
            #planback { width:auto; margin:6px; padding:4px 8px; font-size:11px; }
            #filepick { display:none; }
            button.tool { width:auto; flex:1; padding:5px 0; margin-top:0;
                          display:flex; align-items:center; justify-content:center; }
            button.tool svg { width:20px; height:20px; display:block; }
            button.tool svg .s { fill:none; stroke:#e8e8e8; stroke-width:1.6;
                                 stroke-linecap:round; stroke-linejoin:round; }
            button.tool.on { background:#1f6feb; border-color:#1f6feb; }
            button.tool.on svg .s { stroke:#fff; }
            button.tool:disabled { opacity:.35; }
            /* FIXED, not absolute (2026-08-17).
               Both bars used to be positioned inside #stage, which is the
               thing that scrolls. Zoom in far enough to have to scroll and
               they slid off the top with the paper - the user was left
               changing a label through a panel he could no longer see.
               Fixed takes them out of the drawing altogether: they float over
               the window and stay put however far he scrolls. */
            #notebar { position:fixed; top:22px; left:50%;
                       transform:translateX(-50%); z-index:20; display:none;
                       background:#2b2b2b; border:1px solid #1f6feb;
                       border-radius:5px; padding:8px; gap:6px; width:380px;
                       box-shadow:0 6px 24px rgba(0,0,0,.5); }
            #notebar.on { display:flex; align-items:center; }
            #notebar input { flex:1; }
            #notebar button { width:auto; margin:0; padding:6px 12px; }
            #notebar button.tool { flex:none; width:36px; padding:5px 0; }
            /* the same bar, for one piece of writing */
            #textbar { position:fixed; top:22px; left:50%;
                       transform:translateX(-50%); z-index:21; display:none;
                       background:#2b2b2b; border:1px solid #1f6feb;
                       border-radius:5px; padding:8px; gap:6px; width:400px;
                       box-shadow:0 6px 24px rgba(0,0,0,.5); }
            #textbar.on { display:flex; align-items:center; }
            /* the grip: the bar is dragged by its name, so it can be parked
               off the label it is changing */
            #textbar .what { flex:1; color:#cfe4ff; font-size:12px;
                             white-space:nowrap; overflow:hidden;
                             text-overflow:ellipsis; cursor:move;
                             user-select:none; padding:2px 4px;
                             border-radius:3px; }
            #textbar .what:hover { background:#37475e; }
            #textbar input { width:64px; flex:none; text-align:center; }
            #textbar .pc { color:#888; font-size:12px; }
            #textbar button { width:auto; margin:0; padding:6px 10px; flex:none; }
            #textbar button.tool { width:32px; padding:5px 0; color:#eee; }
            #curtain { position:fixed; inset:0; z-index:50; display:none;
                       background:rgba(20,40,70,.82); color:#cfe4ff;
                       align-items:center; justify-content:center; font-size:22px;
                       border:4px dashed #1f6feb; pointer-events:none; }
            #curtain.on { display:flex; }
          </style></head>
          <body>
            <div id="side">
              <!-- Everything lives in a box that opens. The user's words:
                   "not everything needs to be on the screen - it should be in
                   boxes that open, and the boxes have to be obvious and invite
                   a click." Only the page list starts open; the Export button
                   stays out of the boxes, because it is the point of the
                   window and should never be one click away. -->
              <div class="sec" data-k="pages">
                <h4><span class="ar">&#9656;</span>דפים<span class="tag" id="pagestag"></span></h4>
                <div class="bd">
                  <div id="pages" tabindex="0"></div>
                  <button id="stripbtn">הצג את הדפים ובחר מה יוצא ל-PDF</button>
                </div>
              </div>

              <div class="sec" data-k="paper">
                <h4><span class="ar">&#9656;</span>דף וקנה מידה<span class="tag" id="papertag"></span></h4>
                <div class="bd">
                  <select id="size"></select>
                  <div class="row" style="margin-top:6px">
                    <button id="land">לרוחב</button>
                    <button id="port">לאורך</button>
                  </div>
                  <select id="scale" style="margin-top:8px"></select>
                  <div id="fit"></div>
                  <button id="fitplan" class="go2">התאם את התוכנית לדף</button>
                  <button id="center">מרכז את התוכנית</button>
                </div>
              </div>

              <div class="sec" data-k="text">
                <h4><span class="ar">&#9656;</span>גודל טקסט<span class="tag" id="texttag"></span></h4>
                <div class="bd">
                  <div class="tsrow"><span>מידות</span><input id="tsDims" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <div class="tsrow"><span>שמות חדרים</span><input id="tsRooms" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <div class="tsrow"><span>תגי דלת/חלון</span><input id="tsTags" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <div class="tsrow"><span>טבלאות</span><input id="tsTables" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <button id="tsReset">חזור ל-100%</button>
                  <div class="hint">100% = הגודל שהיה תמיד. משפיע גם על התצוגה וגם על ה-PDF.</div>
                </div>
              </div>

              <div class="sec" data-k="marks">
                <h4><span class="ar">&#9656;</span>מידות והערות<span class="tag" id="markstag"></span></h4>
                <div class="bd">
                  <div class="row" id="tools">
                    <button id="thand" class="tool on" title="בחירה והזזה">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <path d="M12 3 L12 21 M3 12 L21 12"/>
                        <path d="M12 3 L9.5 6 M12 3 L14.5 6"/>
                        <path d="M12 21 L9.5 18 M12 21 L14.5 18"/>
                        <path d="M3 12 L6 9.5 M3 12 L6 14.5"/>
                        <path d="M21 12 L18 9.5 M21 12 L18 14.5"/>
                      </g></svg>
                    </button>
                    <button id="tdim" class="tool" title="קו מידה">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <path d="M4 5 L4 19 M20 5 L20 19"/>
                        <path d="M4 12 L20 12"/>
                        <path d="M4 12 L7.5 9.5 M4 12 L7.5 14.5"/>
                        <path d="M20 12 L16.5 9.5 M20 12 L16.5 14.5"/>
                      </g></svg>
                    </button>
                    <button id="tnote" class="tool" title="הערה">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <rect x="8.5" y="4" width="12.5" height="8" rx="1"/>
                        <path d="M8.5 10 L3 20"/>
                        <path d="M3 20 L4.6 16.2 M3 20 L6.8 18.4"/>
                      </g></svg>
                    </button>
                    <button id="terase" class="tool" title="מחק קו מהתוכנית">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <path d="M9.5 19 L20 19"/>
                        <path d="M14.5 4.5 L20.5 10.5 L11 20 L5 14 Z"/>
                        <path d="M8 11 L14 17"/>
                      </g></svg>
                    </button>
                    <button id="tundo" class="tool" title="בטל אחרון">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <path d="M4 11 A7 7 0 1 1 11 18"/>
                        <path d="M4 11 L7.5 8 M4 11 L7.5 14"/>
                      </g></svg>
                    </button>
                  </div>
                  <!-- How far a new dimension stands off the thing it
                       measures. Sitting ON the wall is what the user hit:
                       nothing to read and nothing to grab (2026-08-19).
                       With a dimension picked, this box changes THAT one. -->
                  <div class="row" style="margin-top:7px; align-items:center">
                    <span style="font-size:12px; flex:none">מרחק מהאובייקט</span>
                    <input id="dimoff" type="number" step="1" style="width:70px">
                    <span style="font-size:11px; color:#888; flex:none">אינץ'</span>
                  </div>
                  <div id="markinfo" class="hint">בחר כלי ולחץ על הציור.</div>
                </div>
              </div>

              <div class="sec" data-k="layers">
                <h4><span class="ar">&#9656;</span>שכבות<span class="tag" id="laycount"></span></h4>
                <div class="bd">
                  <div id="layers"></div>
                  <label class="chk" style="margin-top:8px">
                    <input type="checkbox" id="ownpage"> טבלאות בדף נפרד
                  </label>
                </div>
              </div>

              <div class="sec" data-k="images">
                <h4><span class="ar">&#9656;</span>תמונות ורינדורים<span class="tag" id="imgtag"></span></h4>
                <div class="bd">
                  <button id="addmany" class="go2">העלאת תמונות</button>
                  <input type="file" id="filepick" multiple accept="image/jpeg,image/png">
                  <div id="imginfo" class="hint">אחת או כמה, או גרור אותן לחלון.</div>
                </div>
              </div>

              <div class="sec" data-k="model">
                <h4><span class="ar">&#9656;</span>מהמודל<span class="tag" id="sitetag"></span></h4>
                <div class="bd">
                  <button id="addsel">הוסף את מה שנבחר בסקצ'אפ</button>
                  <button id="clrsel">נקה גיאומטריה חופשית</button>
                  <button id="undrop">החזר קווים שנמחקו</button>
                  <button id="rebuild">קרא שוב מהמודל</button>
                  <div id="siteinfo" class="hint"></div>
                </div>
              </div>

              <div class="sec" data-k="title">
                <h4><span class="ar">&#9656;</span>טייטל בלוק</h4>
                <div class="bd">
                  <input id="address" placeholder="Job address">
                  <div class="row" style="margin-top:6px">
                    <input id="num" placeholder="A-101">
                    <input id="title" placeholder="FLOOR PLAN">
                  </div>
                </div>
              </div>

              <div class="sec" data-k="settings">
                <h4><span class="ar">&#9656;</span>הגדרות<span class="tag" id="settag"></span></h4>
                <div class="bd">
                  <div class="hint" style="margin:0 0 6px">הלוגו שלך, בפינת הטייטל בלוק.</div>
                  <img id="logoshow" alt="">
                  <button id="logopick" class="go2">בחר קובץ לוגו</button>
                  <button id="logoclear">חזור ל-VISUALIZE by Dror</button>
                  <div id="logoinfo" class="hint"></div>
                </div>
              </div>

              <div class="sec" data-k="help">
                <h4><span class="ar">&#9656;</span>איך זה עובד</h4>
                <div class="bd">
                  <div class="hint">גרירה = מזיז את התוכנית על הדף.<br>
                    גלגלת = זום לאן שהעכבר מצביע.<br>
                    Shift+גרירה = מזיז את הדף עצמו.<br>
                    לחיצה על סימון בוחרת, Delete מוחק.<br>
                    לחיצה כפולה על הערה פותחת אותה לעריכה.</div>
                </div>
              </div>

              <button id="pdf" class="go">Export PDF</button>
              <div id="msg"></div>
            </div>
            <div id="curtain">שחרר כאן — כל תמונה תקבל דף</div>
            <div id="stage">
              <div id="notebar">
                <input id="notetext" placeholder="מה לכתוב כאן?">
                <button id="notearrow" class="tool on" title="ראש חץ בקצה הקו">
                  <svg viewBox="0 0 24 24"><g class="s">
                    <rect x="12" y="3" width="9" height="7" rx="1"/>
                    <path d="M12 8 L4 19"/>
                    <path d="M4 19 L5.4 15.4 M4 19 L7.6 17.6"/>
                  </g></svg>
                </button>
                <button id="noteok" class="go">הוסף</button>
                <button id="notecancel">ביטול</button>
              </div>
              <div id="textbar">
                <span id="txwhat" class="what"></span>
                <input id="txsize" type="number" min="25" max="400" step="5" title="גודל באחוזים">
                <span class="pc">%</span>
                <button id="txbold" class="tool" title="מודגש"><b>B</b></button>
                <button id="txitalic" class="tool" title="נטוי"><i>I</i></button>
                <button id="txreset">אפס</button>
                <button id="txdone" class="go">סיים</button>
              </div>
              <div id="sheetWrap"></div>
              <!-- There was a - / fit / + bar pinned to this corner. It sat on
                   top of the drawing and the user asked for it gone: the wheel
                   already zooms, and it zooms where he is pointing. -->
            </div>
            <!-- The page strip sits on the FAR side of the drawing, away from
                 the knobs and lists, the way it does in Rayon. It is the last
                 thing in the body, and the page reads right to left, so it
                 lands on the opposite edge from the controls. -->
            <div id="strip"></div>

          <script>
          var DOC=null, STATE=null, PAGE=null, BOUNDS=null, SCALES=[];
          // Told by Ruby in the payload, never guessed here - see markTextH.
          var DIM_TEXT_H=5, DIM_LABEL_OFF=0.8;
          var URLS={};                // path -> file:/// address, for the sheet
          var MODE='hand';            // hand | dim | note | erase
          var ERA=null;               // which SITE line the rubber is over
          var PEND=null;              // the first point of a dimension
          // The second point, and then the dimension is not finished yet
          // (2026-08-19). A dimension tool in SketchUp, in LayOut and in Rayon
          // takes THREE clicks: what to measure from, what to measure to, and
          // then you pull the line off the wall and click to leave it there.
          //
          // Ours took two, and where the line sat was a separate job with a
          // separate tool afterwards - which is exactly the "צריך לעשות פעמיים
          // כדי להגיע לתוצאה פשוטה" the user called out, and exactly what the
          // "fewer clicks, always" rule in CLAUDE.md exists to stop.
          var PEND2=null;
          var PEND3=null;             // and the end of a note's shoulder
          var PENDOFF=0;              // how far off the wall, while he is choosing
          var HOVER=null;             // where the mouse is, in model inches
          var VIEW=null;              // how to get from the screen to the model
          var SEL=null;               // which mark is picked, by place in the list
          var EDIT=null;              // which note's words are open for changing
          var MDRAG=null;             // a mark being moved right now
          // CARRYING (2026-08-19). The user: "אני רוצה שהוא יזיז את הקו או כל
          // דבר אחר בלייב ואז עוד לחיצה זה יקבע אותם שם... מספיק עם העיגולים
          // הכחולים האלו."
          //
          // So a mark is not dragged with handles - it is PICKED UP by a click,
          // it follows the mouse, and the next click puts it down. SketchUp's
          // move tool, and Rayon's. Holding the button and dragging still works
          // for anyone who reaches for it; letting go without having moved is
          // what starts a carry.
          //
          // {i, part, at:[model x,y], snap:<the mark as it was>}
          var CARRY=null;
          // Everything picked, not just the last thing (2026-08-19). The user:
          // "כמו בסקאצ'אפ אני רוצה למתוח נגיד ריבוע לבחירת דברים ומחוק ביחד."
          // SEL stays the ONE that the panels talk about; SELS is the whole
          // pick, and Delete and carrying both work on all of it.
          var SELS=[];
          // The rubber band being pulled right now, in screen pixels.
          var BAND=null;
          var GRAB=10;                // how near the mouse has to be, in pixels
          // ...except for a MARK, which gets a much wider one (2026-08-19).
          //
          // MEASURED, not chosen. The user reported over three rounds that he
          // could not pick up or erase a dimension. The click probe wrote down
          // every press: they landed 11 to 43 pixels from the dimension line,
          // most of them 11-22. At GRAB=10 not one of them could ever have
          // caught. Nothing was broken - the target was a hair wide, on a
          // sheet 15,876 pixels across, with 1622 free lines lying over it for
          // the mouse to find instead.
          //
          // 26 catches every attempt he made bar the wildest, and a mark is
          // tested BEFORE the free lines, so a dimension always wins over a
          // line lying under it. tests/t51.js pins both.
          var MARK_GRAB=26;
          var SF = {};      // scale label -> paper inches per model inch
          var ZOOM = null;  // null = fit the window; otherwise a multiplier

          function $(id){ return document.getElementById(id); }

          function scaleFactor(lbl){ return SF[lbl] || 0.25/12; }

          // ---- drawing ---------------------------------------------------
          function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

          function shapeSVG(s, tp, k, ph){
            var o=[];
            function P(x,y){ var p=tp(x,y); return (p[0]*k).toFixed(2)+','+((ph-p[1])*k).toFixed(2); }
            var w = ((s.weight||0.012)*Math.min(k,KSTROKE)).toFixed(2);
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
              var p=tp(s.x,s.y), px=p[0]*k, py=(ph-p[1])*k;
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
                o.push('<line x1="'+(x1*k).toFixed(1)+'" y1="'+((ph-y1)*k).toFixed(1)+
                       '" x2="'+(x2*k).toFixed(1)+'" y2="'+((ph-y2)*k).toFixed(1)+
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
                    ((ph-(s.y-(ri+1)*rh+rh*0.3))*k).toFixed(1)+
                    '" font-family="Helvetica,Arial" font-size="'+fs.toFixed(1)+
                    '" fill="#000"'+(ri===0?' font-weight="700"':'')+'>'+esc(cell)+'</text>');
                  cx+=cols[ci]||1.2;
                });
              });
            } else if(s.type==='image'){
              var a=tp(s.x,s.y);
              var ix=(a[0]*k).toFixed(1), iy=((ph-(s.y+s.h))*k).toFixed(1);
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

          // A run of plain lines is ONE element, not one each (2026-10-07).
          //
          // 6 Bronco Ln: a back yard is 15,000 loose lines, and every one of
          // them was its own <polyline>. The sheet is drawn again from nothing
          // on every step of a drag and every click of the wheel, so each step
          // threw away 15,394 elements and made 15,394 new ones - 286 ms a
          // step, measured, with the page strip doubling it. He said it in
          // three words: "זה זז לאט".
          //
          // The lines were never the problem; the ELEMENTS were. Consecutive
          // open lines of one weight are written into a single <path> - same
          // points, same weight, same order on the page, so the picture does
          // not change by a pixel - and the same yard is 225 elements.
          //
          // Only open, unfilled polylines join a run. Everything else - walls,
          // fills, closed outlines, writing, tables - goes through shapeSVG
          // exactly as it always did.
          // How close he can get, and how fat a line may grow (2026-10-07).
          //
          // "אני רוצה לעשות יותר זום אין." The wheel stopped at 14 times - on a
          // whole lot drawn at 3/32" that is about four pixels to the inch of
          // yard, and he was rubbing out lines closer together than that.
          // Measured on his drawing in a browser up to 200 times: the same
          // 170 ms a click all the way in, and the spot under the mouse holds.
          //
          // But a line on this sheet has a real PAPER thickness, and it was
          // drawn that thickness times the zoom: at 50 times a hairline is
          // 20 pixels wide and the treads of his stairs are one black smear.
          // Getting closer showed him less. So the drawing keeps growing and
          // the line stops: past KSTROKE pixels to the paper inch a line is
          // drawn as if the zoom had stopped there. Every weight is held at
          // the same point, so a heavy line stays heavier than a light one.
          // Below it - the whole sheet, the page strip, any zoom up to about
          // four - nothing is drawn differently. The PDF never sees any of it.
          var ZMAX = 200, KSTROKE = 160;
          var FAST = true;
          function layerSVG(shapes,tp,k,ph,paper){
            var o=[], run=[], runW=null;
            function flush(){
              if(run.length){
                o.push('<path d="'+run.join('')+'" fill="none" stroke="#000" stroke-width="'+runW+'"/>');
                run=[];
              }
            }
            (shapes||[]).forEach(function(s){
              if(paper) s.__paper=true;
              if(FAST && s.type==='polyline' && !s.fill && !s.closed && s.points && s.points.length>1){
                var w=Math.max(((s.weight||0.012)*Math.min(k,KSTROKE)).toFixed(2),0.6);
                if(runW!==null && w!==runW) flush();
                runW=w;
                var d='M';
                for(var i=0;i<s.points.length;i++){
                  var p=tp(s.points[i][0],s.points[i][1]);
                  d+=(i?'L':'')+(p[0]*k).toFixed(2)+' '+((ph-p[1])*k).toFixed(2);
                }
                run.push(d);
                return;
              }
              flush();
              o.push(shapeSVG(s,tp,k,ph));
            });
            flush();
            return o.join('');
          }

          // ONE routine draws a sheet, whether it fills the window or sits in
          // the page strip at 180 pixels wide. Two drawing routines would drift
          // apart the same way the window and the PDF would, and the whole file
          // is built to stop that happening.
          //
          // live = the sheet the user is working on: it remembers how to get
          // from the screen back to the house, shows the view frame, and paints
          // what is picked. A thumbnail wants none of that.
          function sheetSVG(pg, k, live){
            var W=pg.width*k, H=pg.height*k, ph=pg.height;
            function same(x,y){ return [x,y]; }
            var o=['<svg xmlns="http://www.w3.org/2000/svg" width="'+W.toFixed(0)+
                   '" height="'+H.toFixed(0)+'" viewBox="0 0 '+W.toFixed(0)+' '+
                   H.toFixed(0)+'" style="display:block">'];
            o.push('<rect width="100%" height="100%" fill="#fff"/>');

            var v=(pg.views||[])[0];
            if(live) VIEW=null;
            if(v){
              var sf=scaleFactor(STATE.scale);
              var cx=v.x+v.w/2, cy=v.y+v.h/2;
              var toPaper=function(mx,my){ return [cx+(mx-STATE.origin_x)*sf, cy+(my-STATE.origin_y)*sf]; };
              // remembered so a click on the screen can be turned back into a
              // place in the house
              if(live) VIEW={k:k, sf:sf, cx:cx, cy:cy, toPaper:toPaper};
              var cid='vclip'+(live?'':'t'+(pg.name||'').replace(/[^A-Za-z0-9]/g,''));
              o.push('<clipPath id="'+cid+'"><rect x="'+(v.x*k).toFixed(1)+'" y="'+((ph-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+'"/></clipPath>');
              o.push('<g clip-path="url(#'+cid+')">');
              var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
              if(cv) cv.layers.forEach(function(l){
                if(STATE.hidden.indexOf(l.name)>=0) return;
                o.push(layerSVG(l.shapes,toPaper,k,ph,false));
              });
              o.push('</g>');
              // the window itself, so the user can see where the plan may sit
              if(live) o.push('<rect x="'+(v.x*k).toFixed(1)+'" y="'+((ph-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+
                     '" fill="none" stroke="#bcd" stroke-width="1" stroke-dasharray="5 4"/>');
            }

            (pg.layers||[]).forEach(function(l){
              if(STATE.hidden.indexOf(l.name)>=0) return;
              o.push(layerSVG(l.shapes,same,k,ph,true));
            });

            if(live){
              // what is picked, drawn over the top. Presentation only - the mark
              // itself is still the one Ruby built, so the paper cannot drift.
              // picked loose lines: ONE element however many there are - a
              // rubber band over the whole yard picks thousands
              if(SSEL.length && VIEW){
                var psl=siteLayer(), pd='';
                if(psl) SSEL.forEach(function(i){
                  var ps=psl.shapes[i]; if(!ps||!ps.points) return;
                  ps.points.forEach(function(q,j){
                    var t=screenOf(q[0],q[1]);
                    pd+=(j?'L':'M')+t[0].toFixed(1)+' '+t[1].toFixed(1);
                  });
                });
                if(pd) o.push('<path id="sitepick" d="'+pd+'" fill="none" stroke="#1f6feb" stroke-width="2.5" opacity=".85"/>');
              }
              var picked = SELS.length ? SELS : (SEL===null ? [] : [SEL]);
              picked.forEach(function(pi){
              if(marks()[pi] && VIEW){
                var sm=marks()[pi];
                // No handles. The user, 2026-08-19: "מספיק עם העיגולים
                // הכחולים האלו." What is picked is shown by drawing the THING
                // in blue over itself - the same way SketchUp shows a
                // selection - and it is moved by carrying it, not by grabbing
                // a dot on it.
                if(sm.t==='dim'){
                  // the dimension line where it actually stands...
                  var dl=dimLine(sm);
                  var pa=screenOf(dl[0],dl[1]), pb=screenOf(dl[2],dl[3]);
                  o.push('<line x1="'+pa[0].toFixed(1)+'" y1="'+pa[1].toFixed(1)+
                         '" x2="'+pb[0].toFixed(1)+'" y2="'+pb[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="2" opacity=".55"/>');
                  // ...and the two points on the object that it measures
                  // and its witness lines, so the whole dimension reads as
                  // picked rather than just its middle
                  var wa=screenOf(sm.x1,sm.y1), wb=screenOf(sm.x2,sm.y2);
                  o.push('<line x1="'+wa[0].toFixed(1)+'" y1="'+wa[1].toFixed(1)+
                         '" x2="'+pa[0].toFixed(1)+'" y2="'+pa[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="1.5" opacity=".45"/>');
                  o.push('<line x1="'+wb[0].toFixed(1)+'" y1="'+wb[1].toFixed(1)+
                         '" x2="'+pb[0].toFixed(1)+'" y2="'+pb[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="1.5" opacity=".45"/>');
                } else {
                  // a note: its leader, drawn over itself in blue
                  var seg=function(p1,p2){
                    o.push('<line x1="'+p1[0].toFixed(1)+'" y1="'+p1[1].toFixed(1)+
                           '" x2="'+p2[0].toFixed(1)+'" y2="'+p2[1].toFixed(1)+
                           '" stroke="#1f6feb" stroke-width="2" opacity=".55"/>');
                  };
                  var pw=screenOf(sm.x,sm.y);
                  if(sm.kx!==undefined){
                    var pk=screenOf(sm.kx,sm.ky);
                    if(sm.lx!==undefined) seg(screenOf(sm.lx,sm.ly), pk);
                    seg(pk, pw);
                  } else if(sm.lx!==undefined){
                    seg(screenOf(sm.lx,sm.ly), pw);
                  }
                }
              }
              });

              // the dimension being drawn right now, before it is real
              if(PEND && VIEW){
                var SP=function(mx,my){
                  var q=VIEW.toPaper(mx,my);
                  return [(q[0]*k), ((ph-q[1])*k)];
                };
                var dash=function(p1,p2,w){
                  o.push('<line x1="'+p1[0].toFixed(1)+'" y1="'+p1[1].toFixed(1)+
                         '" x2="'+p2[0].toFixed(1)+'" y2="'+p2[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="'+(w||1.5)+
                         '" stroke-dasharray="4 3"/>');
                };
                if(MODE==='note'){
                  // the leader being drawn, one segment per click
                  var kp = PEND2 || HOVER;
                  if(kp) dash(SP(PEND[0],PEND[1]), SP(kp[0],kp[1]), 1.5);
                  if(PEND2){
                    var ep = PEND3 || HOVER;
                    // the shoulder is level with the knee whatever height the
                    // mouse is at - he is choosing its LENGTH
                    if(ep) dash(SP(PEND2[0],PEND2[1]), SP(ep[0],PEND2[1]), 1.5);
                  }
                } else if(PEND2){
                  // stage three: the real thing, following the mouse. What he
                  // is looking at IS the dimension he is about to leave there,
                  // witness lines and all - not a hint of one.
                  var tmp={t:'dim', x1:PEND[0], y1:PEND[1],
                           x2:PEND2[0], y2:PEND2[1], off:PENDOFF};
                  var L=dimLine(tmp);
                  dash(SP(PEND[0],PEND[1]),  SP(L[0],L[1]), 1);   // witness
                  dash(SP(PEND2[0],PEND2[1]),SP(L[2],L[3]), 1);   // witness
                  dash(SP(L[0],L[1]), SP(L[2],L[3]), 2);          // the line
                } else if(HOVER){
                  dash(SP(PEND[0],PEND[1]), SP(HOVER[0],HOVER[1]));
                }
              }
            }
            o.push('</svg>');
            return o.join('');
          }

          // moving = the plan is being dragged or zoomed right now. The little
          // sheets down the side are not drawn again for every step of that:
          // zooming does not change them at all, and a drag redraws them once,
          // when Ruby answers the move. Drawing them on every step was half
          // the cost of the step (2026-10-07).
          function render(moving){
            PAGE=activePage();
            if(!DOC||!PAGE) return;
            $('sheetWrap').innerHTML=sheetSVG(PAGE, fitK()*(ZOOM||1), true);
            hookDrag();
            paintErase();
            paintSnap();
            paintTextPick();
            if(!(moving===true && FAST) && $('strip').className==='on') paintStrip();
          }

          function setZoom(z){
            ZOOM = z;
            STATE.zoom = z;
            render(true);
          }

          // Zoom towards a point on the screen instead of towards a corner.
          //
          // Zooming only makes the sheet bigger; the scroll box stays where it
          // was, so whatever happened to be at the top left stayed put and
          // everything the user was looking at slid away. Remember which spot
          // on the SHEET is under the mouse, redraw, then scroll so that same
          // spot is back under the mouse. Works the same whether the sheet is
          // centred in the window or scrolled.
          function zoomAt(cx, cy, z){
            z = Math.min(Math.max(z, 0.2), ZMAX);
            var stage = $('stage');
            var svg = $('sheetWrap').firstChild;
            if(!svg){ setZoom(z); return; }
            var r = svg.getBoundingClientRect();
            if(!r.width || !r.height){ setZoom(z); return; }
            // 0..1 across the sheet. Off the sheet, hold on to the nearest edge
            // rather than flinging the page away.
            var fx = Math.max(0, Math.min(1, (cx - r.left) / r.width));
            var fy = Math.max(0, Math.min(1, (cy - r.top) / r.height));

            setZoom(z);

            var svg2 = $('sheetWrap').firstChild;
            if(!svg2) return;
            var r2 = svg2.getBoundingClientRect();
            if(!ZHOLD){
              stage.scrollLeft += (r2.left + fx * r2.width)  - cx;
              stage.scrollTop  += (r2.top  + fy * r2.height) - cy;
              return;
            }
            // PUT the sheet where that spot is back under the mouse
            // (2026-10-07). The user, for the second time: "איפה שאני שם את
            // העכבר ועושה זום אני רוצה שזה יהיה לשם".
            //
            // Scrolling alone could not do it, and measuring his own drawing
            // in a browser showed why. A scroll box cannot scroll below zero:
            // while the sheet still fits the window there is nothing to scroll
            // at all, and once it is bigger the window kept it CENTRED, so
            // half of what stuck out went off the left edge where no scroll
            // bar reaches. With the mouse on the left of the sheet the spot
            // under it slid 45 feet in six clicks of the wheel, always the
            // same way - "it only goes to one place".
            //
            // So the sheet is given a place instead of being left to the
            // layout: a margin when its corner belongs INSIDE the window, a
            // scroll when it belongs outside, and a margin on the far side so
            // the scroll has room to get there. Zooming out past "fits" works
            // the same way - the sheet shrinks towards the mouse.
            var wrap = $('sheetWrap');
            var sr = stage.getBoundingClientRect();
            var PAD = 20;                              // #stage padding
            // Off the sheet the nearest edge is held where it IS, not dragged
            // under the mouse.
            var ax = Math.max(r.left, Math.min(r.left + r.width,  cx));
            var ay = Math.max(r.top,  Math.min(r.top  + r.height, cy));
            var L = ax - fx * r2.width, T = ay - fy * r2.height;    // the corner, on screen
            var SL = sr.left + PAD, ST = sr.top + PAD;
            var SR = sr.left + stage.clientWidth - PAD, SB = sr.top + stage.clientHeight - PAD;
            wrap.style.marginLeft   = Math.max(0, L - SL) + 'px';
            wrap.style.marginTop    = Math.max(0, T - ST) + 'px';
            wrap.style.marginRight  = Math.max(0, SR - (L + r2.width)) + 'px';
            wrap.style.marginBottom = Math.max(0, SB - (T + r2.height)) + 'px';
            stage.scrollLeft = Math.max(0, SL - L);
            stage.scrollTop  = Math.max(0, ST - T);
          }
          var ZHOLD = true;

          // ---- from the screen back to the house --------------------------
          //
          // render() draws the house onto paper and the paper onto the screen.
          // To put a dimension where the user clicked, both have to be undone.
          function atMouse(e){
            var svg=$('sheetWrap').firstChild;
            if(!svg||!VIEW||!PAGE) return null;
            var r=svg.getBoundingClientRect();
            var px=(e.clientX-r.left)/VIEW.k;                 // paper inches
            var py=PAGE.height-(e.clientY-r.top)/VIEW.k;
            return [(px-VIEW.cx)/VIEW.sf+STATE.origin_x,      // model inches
                    (py-VIEW.cy)/VIEW.sf+STATE.origin_y];
          }

          function marks(){ return STATE.marks||(STATE.marks=[]); }

          // ---- snapping a dimension onto the drawing ----------------------
          //
          // The user, 2026-08-19: "הלחיצה צריכה להינעל על פינות וקצוות כמו
          // בשאר הכלים". A dimension that starts a quarter of an inch off the
          // corner reads 15' 1/16" when the wall is 15' - and he has no way to
          // see which one it did.
          //
          // So the click looks for a corner first: every END of a line and
          // every VERTEX of a polyline or polygon that is drawn on the plan -
          // walls, free geometry, anything on a visible layer. The search is
          // in SCREEN pixels, not model inches, so the pull feels the same
          // however far he is zoomed in, exactly like SketchUp.
          var SNAP_PX = 12;
          var SNAPPED = null;   // where the last snap landed, for the marker

          function eachVertex(fn){
            if(!DOC||!STATE||!PAGE) return;
            var v=(PAGE.views||[])[0]; if(!v) return;
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
            if(!cv) return;
            var hid=STATE.hidden||[];
            cv.layers.forEach(function(l){
              if(hid.indexOf(l.name)>=0) return;
              (l.shapes||[]).forEach(function(s){
                if(s.type==='line'){ fn(s.x1,s.y1); fn(s.x2,s.y2); }
                else if(s.points){ s.points.forEach(function(q){ fn(q[0],q[1]); }); }
              });
            });
            // the ends of dimensions already drawn, so a run of them lines up
            marks().forEach(function(m){
              if(m.t==='dim'){ fn(m.x1,m.y1); fn(m.x2,m.y2); }
            });
          }

          // p is where the mouse really is, in model inches. Returns the
          // corner it should lock onto, or p itself when there is none near.
          function snapPoint(p){
            if(!p||!VIEW) return p;
            var ps=screenOf(p[0],p[1]);
            var best=null, bd=SNAP_PX;
            eachVertex(function(x,y){
              var q=screenOf(x,y);
              var d=Math.hypot(q[0]-ps[0], q[1]-ps[1]);
              if(d<bd){ bd=d; best=[x,y]; }
            });
            SNAPPED = best ? best.slice() : null;
            return best || p;
          }

          // model inches -> pixels inside the drawing, for hit testing
          function screenOf(mx,my){
            var p=VIEW.toPaper(mx,my);
            return [p[0]*VIEW.k, (PAGE.height-p[1])*VIEW.k];
          }

          function mouseAt(e){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return null;
            var r=svg.getBoundingClientRect();
            return [e.clientX-r.left, e.clientY-r.top];
          }

          function distToSeg(X,Y,a,b){
            var vx=b[0]-a[0], vy=b[1]-a[1];
            var L=vx*vx+vy*vy;
            var t = L ? ((X-a[0])*vx+(Y-a[1])*vy)/L : 0;
            t=Math.max(0,Math.min(1,t));
            return Math.hypot(a[0]+vx*t-X, a[1]+vy*t-Y);
          }

          // What is under the mouse, and which bit of it. The ends of a
          // dimension and the arrow tip of a note win over the body, so a
          // careful click adjusts instead of dragging the whole thing.
          function hitMark(e){
            if(!VIEW||!PAGE) return null;
            var p=mouseAt(e); if(!p) return null;
            var X=p[0], Y=p[1], best=null, bd=MARK_GRAB;
            marks().forEach(function(m,i){
              if(m.t==='dim'){
                // the two CLICKED points - they sit on the thing being
                // measured and they are what 'a' and 'b' move
                var a=screenOf(m.x1,m.y1), b=screenOf(m.x2,m.y2);
                var da=Math.hypot(a[0]-X,a[1]-Y), db=Math.hypot(b[0]-X,b[1]-Y);
                if(da<bd){ bd=da; best={i:i,part:'a'}; }
                if(db<bd){ bd=db; best={i:i,part:'b'}; }
                // the NUMBER itself, before the line: they overlap on a short
                // dimension, and the thing he reached for is the one he can
                // see (2026-08-19). The ends still win over both.
                var lp=dimLabelXY(m), ls=screenOf(lp[0],lp[1]);
                var dl=Math.hypot(ls[0]-X,ls[1]-Y);
                if(dl<bd){ bd=dl; best={i:i,part:'text'}; }
                // and the DIMENSION LINE, which is where it stands now - not
                // where it was clicked. Dragging it pulls it off the wall.
                var L=dimLine(m);
                var la=screenOf(L[0],L[1]), lb=screenOf(L[2],L[3]);
                var ds=distToSeg(X,Y,la,lb);
                if(ds<bd){ bd=ds; best={i:i,part:'off'}; }
              } else if(m.t==='note'){
                if(m.lx!==undefined){
                  var t=screenOf(m.lx,m.ly);
                  var dt=Math.hypot(t[0]-X,t[1]-Y);
                  if(dt<bd){ bd=dt; best={i:i,part:'tip'}; }
                }
                if(m.kx!==undefined){
                  var kp=screenOf(m.kx,m.ky);
                  var dk=Math.hypot(kp[0]-X,kp[1]-Y);
                  if(dk<bd){ bd=dk; best={i:i,part:'knee'}; }
                }
                var c=screenOf(m.x,m.y);
                var dc=Math.hypot(c[0]-X,c[1]-Y);
                if(dc<bd+8){ bd=Math.min(bd,dc); best={i:i,part:'all'}; }
              }
            });
            return best;
          }

          // ---- rubbing a line off the sheet ------------------------------
          //
          // Only the free geometry - the lines traced off the model by hand.
          // The walls, doors and windows are drawn from their attributes and
          // are switched off by their own layer, not one at a time.
          //
          // Shape number i on this layer is line number i in Ruby's list; see
          // the note over drop_site_line. Nothing is looked up by position, so
          // two lines lying on top of each other cannot be confused.
          function siteLayer(){
            if(!DOC||!PAGE||!STATE) return null;
            if((STATE.hidden||[]).indexOf('SITE')>=0) return null;   // switched off
            var v=(PAGE.views||[])[0]; if(!v) return null;
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
            if(!cv) return null;
            return (cv.layers||[]).filter(function(l){ return l.name==='SITE'; })[0]||null;
          }

          function hitSite(e){
            var lay=siteLayer(); if(!lay||!VIEW) return null;
            var p=mouseAt(e); if(!p) return null;
            var X=p[0], Y=p[1], best=null, bd=GRAB;
            (lay.shapes||[]).forEach(function(s,i){
              var pts=s.points; if(!pts||pts.length<2) return;
              for(var j=0;j<pts.length-1;j++){
                var a=screenOf(pts[j][0],pts[j][1]);
                var b=screenOf(pts[j+1][0],pts[j+1][1]);
                var d=distToSeg(X,Y,a,b);
                if(d<bd){ bd=d; best=i; }
              }
            });
            return best;
          }

          // The line about to go, in red.
          //
          // Painted straight onto the drawing as ONE extra element instead of
          // going through render(). A real back yard is thousands of lines and
          // rebuilding all of them every time the mouse crosses a new one would
          // make the rubber feel stuck.
          //
          // It sits outside the view frame's clip, so a line running off the
          // edge of the sheet lights up along its whole length. That is on
          // purpose: it shows what is about to be deleted, not what is printed.
          // WHAT THE ERASER CAN TAKE (2026-08-19).
          //
          // It used to rub out free SITE geometry and nothing else, so a
          // dimension could only go by picking it and pressing Delete - which
          // is not how the user works. In SketchUp the eraser is THE way you
          // get rid of a dimension: you pass over it, it lights up, you click
          // or you drag across a run of them. He sent a picture of exactly
          // that. So the eraser now takes marks too - dimensions and notes -
          // and marks win over site lines, because they are the small thing
          // drawn on top and they are what he is aiming at.
          //
          // ERA is {kind:'mark'|'site', i:index} or null.
          function hitErase(e){
            var h=hitMark(e);
            if(h) return {kind:'mark', i:h.i};
            var s=hitSite(e);
            return (s===null) ? null : {kind:'site', i:s};
          }

          function sameEra(a,b){
            if(a===null||b===null) return a===b;
            return a.kind===b.kind && a.i===b.i;
          }

          function eraKey(x){ return x.kind+':'+x.i; }

          // Everything the current sweep has crossed, in the order it was
          // crossed. Dragging the eraser over a run of things is how SketchUp
          // does it, and one round trip per item would make it crawl - so the
          // sweep collects and the whole lot goes on letting go.
          var ERASWEEP=null;
          var FASTERASE=true;  // rubbed-out lines leave the sheet here, at once
          var ERADONE=false;   // a sweep just ran; swallow the click behind it

          function eraShapePoints(x){
            if(x.kind==='site'){
              var lay=siteLayer(); if(!lay) return null;
              var s=(lay.shapes||[])[x.i];
              return (s&&s.points) ? s.points.map(function(q){ return screenOf(q[0],q[1]); }) : null;
            }
            var m=marks()[x.i]; if(!m) return null;
            if(m.t==='dim'){
              var L=dimLine(m);
              return [screenOf(L[0],L[1]), screenOf(L[2],L[3])];
            }
            // a note: ring its words
            var c=screenOf(m.x,m.y);
            return [[c[0]-14,c[1]],[c[0]+14,c[1]]];
          }

          // The green square on the corner the dimension is about to lock to.
          // Painted straight onto the drawing, like the eraser's highlight -
          // going through render() on every mouse move would make it stick.
          // ---- the rubber band ---------------------------------------------
          //
          // Painted straight onto the drawing, like the eraser's highlight and
          // the snap marker: going through render() on every mouse move would
          // rebuild every line on the sheet and the band would feel stuck.
          function paintBand(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#bandhi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(!BAND) return;
            var x=Math.min(BAND.x0,BAND.x1), y=Math.min(BAND.y0,BAND.y1);
            var w=Math.abs(BAND.x1-BAND.x0), h=Math.abs(BAND.y1-BAND.y0);
            var n=document.createElementNS('http://www.w3.org/2000/svg','rect');
            n.setAttribute('id','bandhi');
            n.setAttribute('x',x.toFixed(1)); n.setAttribute('y',y.toFixed(1));
            n.setAttribute('width',w.toFixed(1)); n.setAttribute('height',h.toFixed(1));
            n.setAttribute('fill','#1f6feb');
            n.setAttribute('fill-opacity','.08');
            n.setAttribute('stroke','#1f6feb');
            n.setAttribute('stroke-width','1');
            n.setAttribute('stroke-dasharray','4 3');
            svg.appendChild(n);
          }

          // Is any part of this mark inside the box he pulled? A mark that
          // merely CROSSES it counts - reaching a dimension means reaching its
          // line, and asking him to swallow the whole of a 70 foot one before
          // it will pick would be its own kind of fiddling.
          function markInBox(m, x0, y0, x1, y1) {
            var lo=[Math.min(x0,x1), Math.min(y0,y1)];
            var hi=[Math.max(x0,x1), Math.max(y0,y1)];
            var inside=function(p){
              return p[0]>=lo[0] && p[0]<=hi[0] && p[1]>=lo[1] && p[1]<=hi[1];
            };
            var pts=[];
            if(m.t==='dim'){
              var L=dimLine(m);
              pts.push(screenOf(m.x1,m.y1), screenOf(m.x2,m.y2),
                       screenOf(L[0],L[1]), screenOf(L[2],L[3]));
              var lab=dimLabelXY(m); pts.push(screenOf(lab[0],lab[1]));
              // and the middle, so a long dimension lying across the box counts
              pts.push(screenOf((L[0]+L[2])/2, (L[1]+L[3])/2));
            } else {
              pts.push(screenOf(m.x,m.y));
              if(m.kx!==undefined) pts.push(screenOf(m.kx,m.ky));
              if(m.lx!==undefined) pts.push(screenOf(m.lx,m.ly));
            }
            return pts.some(inside);
          }

          // ---- picking loose lines (2026-10-07) ----------------------------
          //
          // "בחירה של קווים גם עם שיפט ואז יכולת מחיקה של כולם ביחד."
          //
          // Until now a loose line could only be met by the eraser, one sweep
          // at a time, and a sweep is a commitment: what it crosses is gone.
          // Picking is the other way of working - gather first, look at what
          // is lit up, THEN press Delete - and it is how every other thing in
          // SketchUp is removed.
          //
          //   click on a line           picks it (and lets go of the rest)
          //   Shift+click               adds it, or lets go of it if it was picked
          //   rubber band, left to right  everything wholly inside the box
          //   rubber band, right to left  everything the box touches - SketchUp's rule
          //   Delete                    all of them, and any picked dimension or note,
          //                             as ONE step for Ctrl+Z
          //   Escape                    lets go of everything
          //
          // SSEL holds NUMBERS in the SITE layer, the same numbers the eraser
          // and Ruby use. So it is emptied whenever those numbers change: a
          // rub-out, an undo, a sheet from Ruby.
          var SSEL=[], LINEPICK=true;

          function segCross(p1,p2,p3,p4){
            var d=function(a,b,c){ return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]); };
            var d1=d(p3,p4,p1), d2=d(p3,p4,p2), d3=d(p1,p2,p3), d4=d(p1,p2,p4);
            return ((d1>0&&d2<0)||(d1<0&&d2>0)) && ((d3>0&&d4<0)||(d3<0&&d4>0));
          }

          // Is this loose line caught by the box? touching=false: every point
          // of it is inside. touching=true: any part of it is.
          function siteInBox(s, x0, y0, x1, y1, touching){
            var a=Math.min(x0,x1), b=Math.max(x0,x1), c=Math.min(y0,y1), d=Math.max(y0,y1);
            var pts=(s.points||[]).map(function(q){ return screenOf(q[0],q[1]); });
            if(pts.length<2) return false;
            var inside=function(t){ return t[0]>=a&&t[0]<=b&&t[1]>=c&&t[1]<=d; };
            if(!touching) return pts.every(inside);
            if(pts.some(inside)) return true;
            for(var j=0;j<pts.length-1;j++){
              if(segCross(pts[j],pts[j+1],[a,c],[b,c])||segCross(pts[j],pts[j+1],[b,c],[b,d])||
                 segCross(pts[j],pts[j+1],[b,d],[a,d])||segCross(pts[j],pts[j+1],[a,d],[a,c])) return true;
            }
            return false;
          }

          // Shift+click: one thing joins what is picked, or leaves it.
          function togglePick(x){
            if(x.kind==='site'){
              var at=SSEL.indexOf(x.i);
              if(at>=0) SSEL.splice(at,1); else SSEL.push(x.i);
              return;
            }
            if(!SELS.length && SEL!==null) SELS=[SEL];
            var am=SELS.indexOf(x.i);
            if(am>=0) SELS.splice(am,1); else SELS.push(x.i);
            SEL = SELS.length ? SELS[0] : null;
          }

          // Delete: every picked line, and every picked dimension and note,
          // through the same door as the eraser - so it is quick, it is one
          // step for Ctrl+Z, and Ruby hears about it the same way.
          function dropPicked(){
            var list=[];
            (SELS.length ? SELS : (SEL===null ? [] : [SEL])).forEach(function(i){ list.push({kind:'mark', i:i}); });
            SSEL.forEach(function(i){ list.push({kind:'site', i:i}); });
            SSEL=[]; SELS=[]; SEL=null;
            if(!list.length) return;
            eraseSweep(list);
            render(); showMarks();
          }

          function pickInBand(band){
            SELS=[];
            marks().forEach(function(m,i){
              if(markInBox(m, band.x0, band.y0, band.x1, band.y1)) SELS.push(i);
            });
            SEL = SELS.length ? SELS[0] : null;
            SSEL=[];
            var lay=LINEPICK ? siteLayer() : null;
            if(lay && VIEW){
              var touching = band.x1 < band.x0;       // pulled right to left
              (lay.shapes||[]).forEach(function(sh,i){
                if(siteInBox(sh, band.x0, band.y0, band.x1, band.y1, touching)) SSEL.push(i);
              });
            }
          }

          function paintSnap(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#snaphi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(MODE!=='dim'||!SNAPPED||!VIEW) return;
            var q=screenOf(SNAPPED[0],SNAPPED[1]);
            var n=document.createElementNS('http://www.w3.org/2000/svg','rect');
            n.setAttribute('id','snaphi');
            n.setAttribute('x',(q[0]-4).toFixed(1)); n.setAttribute('y',(q[1]-4).toFixed(1));
            n.setAttribute('width','8'); n.setAttribute('height','8');
            n.setAttribute('fill','none');
            n.setAttribute('stroke','#2fbf5f');
            n.setAttribute('stroke-width','2');
            svg.appendChild(n);
          }

          function paintErase(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#erahi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(MODE!=='erase'||!VIEW) return;
            var show=[];
            if(ERASWEEP) show=ERASWEEP.slice();
            else if(ERA) show=[ERA];
            if(!show.length) return;
            var g=document.createElementNS('http://www.w3.org/2000/svg','g');
            g.setAttribute('id','erahi');
            show.forEach(function(x){
              var pts=eraShapePoints(x); if(!pts) return;
              var n=document.createElementNS('http://www.w3.org/2000/svg','polyline');
              n.setAttribute('points',pts.map(function(t){
                return t[0].toFixed(1)+','+t[1].toFixed(1); }).join(' '));
              n.setAttribute('fill','none');
              // Blue, like the picture he sent of SketchUp: this is "the
              // eraser is on it", not "it is already gone".
              n.setAttribute('stroke','#1f6feb');
              n.setAttribute('stroke-width','4');
              n.setAttribute('stroke-linecap','round');
              n.setAttribute('opacity','.85');
              g.appendChild(n);
            });
            svg.appendChild(g);
          }

          // Take everything the sweep crossed. Marks live in the settings, so
          // they go here; site lines live in Ruby, so they go in ONE message.
          function eraseSweep(list){
            if(!list||!list.length) return;
            UCUR=++UGROUP;           // everything this sweep takes is one Ctrl+Z
            try { eraseSweepNow(list); } finally { UCUR=null; }
          }
          function eraseSweepNow(list){
            var seen={}, marksGone=[], siteGone=[];
            list.forEach(function(x){
              var k=eraKey(x); if(seen[k]) return; seen[k]=1;
              if(x.kind==='mark') marksGone.push(x.i); else siteGone.push(x.i);
            });
            // highest first, so taking one out cannot move the next
            marksGone.sort(function(a,b){ return b-a; })
                     .forEach(function(i){ marks().splice(i,1); });
            if(marksGone.length){ SEL=null; push(); render(); showMarks(); }
            if(siteGone.length){
              // Off the sheet NOW, here, and Ruby is only told which ones
              // went (2026-10-07). Waiting for Ruby to build the whole sheet
              // again and send it back was the pause he felt after every
              // sweep. The numbers are the ones Ruby holds - shape i is line
              // i on both sides - and n says how many there were, so Ruby can
              // tell if the two have drifted and send everything after all.
              var lay=siteLayer();
              if(FASTERASE && lay && lay.shapes){
                SSEL=[];                     // the numbers are about to move
                var n=lay.shapes.length, took=[];
                siteGone.slice().sort(function(a,b){ return b-a; }).forEach(function(i){
                  if(i>=0 && i<lay.shapes.length){ took.push({i:i, s:lay.shapes[i]}); lay.shapes.splice(i,1); }
                });
                if(UNDOON && took.length){
                  UNDO.push({g:(UCUR!==null ? UCUR : ++UGROUP), site:took});
                  if(UNDO.length>300) UNDO.shift();
                }
                USITE_N=lay.shapes.length;
                ERA=null;
                STATE.site_count=lay.shapes.length;
                render();
                sketchup.drop_site_line(JSON.stringify({is:siteGone, quiet:true, n:n}));
              } else {
                sketchup.drop_site_line(JSON.stringify({is:siteGone}));
              }
            }
          }

          // The eraser's own pointer, so the tool says what it is the way it
          // does in SketchUp - he asked for this by name. Drawn here rather
          // than shipped as a file: it is eleven characters of path data and a
          // missing file would silently fall back to an arrow.
          // The select tool's own pointer - a plain black arrow, which is what
          // it is in SketchUp and what the user asked for. A grabbing hand said
          // "this pans", and panning is not what this tool does any more.
          function arrowCursor(){
            var s='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'+
                  '<path d="M4 2 L4 18 L8.4 14 L11.2 20.4 L14 19.2 L11.3 13 L17 13 Z" '+
                  'fill="#000" stroke="#fff" stroke-width="1.1" stroke-linejoin="round"/>'+
                  '</svg>';
            return 'url("data:image/svg+xml;utf8,'+encodeURIComponent(s)+'") 4 2, default';
          }

          function eraserCursor(){
            var s='<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26">'+
                  '<g fill="none" stroke="#000" stroke-width="1.6" stroke-linejoin="round">'+
                  '<path d="M3 17.5 L10.5 10 L18 17.5 L14 21.5 L7 21.5 Z" fill="#fff"/>'+
                  '<path d="M10.5 10 L15 5.5 L22.5 13 L18 17.5"/>'+
                  '<path d="M7 21.5 L18.5 21.5"/>'+
                  '</g></svg>';
            return 'url("data:image/svg+xml;utf8,'+encodeURIComponent(s)+'") 4 21, crosshair';
          }

          // ---- one label at a time ----------------------------------------
          //
          // Double-click any writing on the sheet - a room name, a tag, a
          // dimension, a note - and set that one. Ruby keeps the choice under
          // the label's key (PlanCanvas.text_key) so it survives the sheet
          // being rebuilt from the model.
          var TSEL=null;   // {key, shape, paper} - the label being changed
          // A label being shoved right now. Ruby draws the writing, so the
          // window cannot really move it until Ruby has heard - a round trip
          // per mouse move would crawl. So the highlight box moves live and
          // the real move is sent once, on letting go.
          var TDRAG=null;
          // and a label being CARRIED - picked up by a click, put down by the
          // next one. See CARRY.
          var TCARRY=null;

          // Where a piece of writing sits on the screen, near enough to click.
          //
          // The width is ESTIMATED - half the height per letter is close for
          // Helvetica, and plan_pdf's real width tables are Ruby's. A box a
          // little too wide is the right way to be wrong here: it makes small
          // writing easier to hit, and the worst case is that a click near a
          // tag opens that tag.
          function textBox(s, paper){
            var h = s.h * (paper ? 1 : scaleFactor(STATE.scale));  // paper inches
            var w = Math.max(String(s.text||'').length * h * 0.55, h * 0.8);
            var p = paper ? [s.x, s.y] : VIEW.toPaper(s.x, s.y);
            var cx = p[0], cy = p[1];
            // Writing put straight on the sheet hangs off its start point;
            // writing on the plan is centred on it. Same rule as shapeSVG.
            if(paper){ cx = p[0] + w/2; cy = p[1] + h/2; }
            return { x:(cx - w/2)*VIEW.k, y:(PAGE.height - cy - h/2)*VIEW.k,
                     w:w*VIEW.k, h:h*VIEW.k };
          }

          // Every piece of writing on the sheet right now, with its key.
          // VIEW is deliberately NOT required here. This also runs straight
          // after a sheet arrives, to point the open panel at the label that
          // came back, and at that moment nothing has been drawn yet.
          function eachText(fn){
            if(!DOC||!STATE) return;
            var PG = PAGE || activePage(); if(!PG) return;
            var hid = STATE.hidden||[];
            var v=(PG.views||[])[0];
            if(v){
              var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
              if(cv) cv.layers.forEach(function(l){
                if(hid.indexOf(l.name)>=0) return;
                (l.shapes||[]).forEach(function(s){
                  if(s.type==='text'&&s.key) fn(s,false);
                });
              });
            }
            (PG.layers||[]).forEach(function(l){
              if(hid.indexOf(l.name)>=0) return;
              (l.shapes||[]).forEach(function(s){
                if(s.type==='text'&&s.key) fn(s,true);
              });
            });
          }

          function hitText(e){
            var p=mouseAt(e); if(!p||!VIEW||!PAGE) return null;
            var X=p[0], Y=p[1], best=null, ba=Infinity;
            eachText(function(s,paper){
              var b=textBox(s,paper);
              if(X<b.x||X>b.x+b.w||Y<b.y||Y>b.y+b.h) return;
              var a=b.w*b.h;             // the tightest box wins, not the first
              if(a<ba){ ba=a; best={key:s.key, shape:s, paper:paper}; }
            });
            return best;
          }

          function textMarks(){ return STATE.text_marks||(STATE.text_marks={}); }

          function openTextBar(hit){
            TSEL=hit;
            var m=textMarks()[hit.key]||{};
            // What it is RIGHT NOW, not what was overridden - so the number in
            // the box is the number on the sheet and he is never editing blind.
            var shown = m.pct ? +m.pct
                      : Math.round((hit.shape.h/(hit.shape.h0||hit.shape.h))*100);
            $('txsize').value = isFinite(shown)&&shown>0 ? shown : 100;
            $('txbold').className   = 'tool'+(hit.shape.bold?' on':'');
            $('txitalic').className = 'tool'+(hit.shape.italic?' on':'');
            $('txwhat').textContent = String(hit.shape.text||'').slice(0,22);
            $('textbar').className='on';
            placeTextBar();
            paintTextPick();
            $('txsize').focus();
            $('txsize').select();
          }

          // Shutting the note bar, from OUT HERE.
          //
          // closeNote() is declared inside the window's load handler, so it
          // does not exist at this level. Calling it from the drawing's
          // dblclick threw a ReferenceError that killed the handler on its
          // first line - two clicks on a label did nothing at all, and the
          // window looked like the feature had never shipped. That was the
          // user's "אין לי בכלל את האופציה לבחור את הכיתוב" (2026-08-17).
          //
          // Nothing in the console said so: an error inside an event handler
          // is swallowed by the page. t46 drives the real handler now, which
          // is the only reason this was found rather than argued about.
          function hideNoteBar(){
            $('notebar').className=''; PEND=null; PEND2=null; PEND3=null; EDIT=null;
          }

          function closeTextBar(){
            $('textbar').className='';
            TSEL=null;
            paintTextPick();
          }

          // ---- parking the panel ------------------------------------------
          //
          // Fixed keeps it on screen, but the middle of the top is exactly
          // where a label can be. Dragging it by its name lets him put it
          // somewhere it is not in the way. Where he puts it is remembered for
          // as long as the window is open - not written onto the model, since
          // it says nothing about the drawing.
          var TBAR=null;    // {x, y} in pixels, or null for "where it starts"

          function placeTextBar(){
            var el=$('textbar');
            if(!TBAR){ el.style.left='50%'; el.style.top='22px';
                       el.style.transform='translateX(-50%)'; return; }
            el.style.left=TBAR.x+'px';
            el.style.top=TBAR.y+'px';
            el.style.transform='none';
          }

          function dragTextBar(e){
            var el=$('textbar');
            var r=el.getBoundingClientRect();
            var grab={ dx:e.clientX-r.left, dy:e.clientY-r.top, w:r.width, h:r.height };
            function move(ev){
              // Kept on screen. A panel dragged off the edge cannot be dragged
              // back, and closing it is not the same as putting it away.
              var x=Math.min(Math.max(ev.clientX-grab.dx, 4),
                             Math.max((window.innerWidth||900)-grab.w-4, 4));
              var y=Math.min(Math.max(ev.clientY-grab.dy, 4),
                             Math.max((window.innerHeight||700)-grab.h-4, 4));
              TBAR={x:x, y:y};
              placeTextBar();
              ev.preventDefault();
            }
            function up(){
              window.removeEventListener('mousemove', move);
              window.removeEventListener('mouseup', up);
            }
            window.addEventListener('mousemove', move);
            window.addEventListener('mouseup', up);
            e.preventDefault();
          }

          // A blue box round the label being changed. Its own element on top of
          // the drawing, for the same reason the rubber's red line is - render()
          // rebuilds the whole sheet and this happens while he is clicking.
          function paintTextPick(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#txhi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(!TSEL||!VIEW||!PAGE) return;
            // The document is rebuilt from the model on every change, so the
            // shape object we are holding is a ghost the moment Ruby answers.
            // Find the label by its KEY again - that is what the key is for.
            if(!TDRAG && !TCARRY){
              var want=TSEL.key, found=null;
              eachText(function(s,paper){
                if(!found && s.key===want) found={key:s.key, shape:s, paper:paper};
              });
              if(found) TSEL=found;
            }
            var b=textBox(TSEL.shape, TSEL.paper);
            // while it is being shoved, the box follows the mouse even though
            // the writing itself cannot move until Ruby redraws it
            var tc = TDRAG || TCARRY;
            if(tc){
              b.x += tc.dx*VIEW.sf*VIEW.k;
              b.y -= tc.dy*VIEW.sf*VIEW.k;      // paper y is up, screen y is down
            }
            var n=document.createElementNS('http://www.w3.org/2000/svg','rect');
            n.setAttribute('id','txhi');
            n.setAttribute('x',b.x.toFixed(1)); n.setAttribute('y',b.y.toFixed(1));
            n.setAttribute('width',Math.max(b.w,3).toFixed(1));
            n.setAttribute('height',Math.max(b.h,3).toFixed(1));
            n.setAttribute('fill','none');
            n.setAttribute('stroke','#1f6feb');
            n.setAttribute('stroke-width','1.5');
            svg.appendChild(n);
          }

          // Shove the picked label by dx,dy MORE than it is already shoved.
          // Only the position is sent - the size and the weight are left out
          // of the message entirely, so a drag cannot quietly reset them
          // (set_text_mark merges what it is given onto what is there).
          // Put down what is being carried, wherever it is now.
          function dropCarry(){
            if(!CARRY) return;
            CARRY=null;
            push(); render(); showMarks();
          }

          function dropTextCarry(){
            if(!TCARRY) return;
            var dx=TCARRY.dx, dy=TCARRY.dy;
            TCARRY=null;
            if(dx||dy) nudgeText(dx, dy);
            else { paintTextPick(); showMarks(); }
          }

          // Esc while carrying puts it back where it was picked up from -
          // otherwise a slip of the mouse costs him the position he had.
          function cancelCarry(){
            if(CARRY){
              if(CARRY.many && CARRY.many.length>1 && CARRY.snaps){
                CARRY.many.forEach(function(i,n){
                  if(marks()[i] && CARRY.snaps[n]) marks()[i]=CARRY.snaps[n];
                });
              } else if(marks()[CARRY.i] && CARRY.snap){
                marks()[CARRY.i]=CARRY.snap;
              }
              CARRY=null;
              render();
            }
            if(TCARRY){ TCARRY=null; paintTextPick(); }
          }

          function nudgeText(dx, dy){
            if(!TSEL) return;
            var cur=textMarks()[TSEL.key]||{};
            var bx=(typeof cur.dx==='number')?cur.dx:0;
            var by=(typeof cur.dy==='number')?cur.dy:0;
            sketchup.set_text_mark(JSON.stringify(
              {key:TSEL.key, dx:bx+dx, dy:by+dy}));
          }

          function sendTextMark(extra){
            if(!TSEL) return;
            var v=parseFloat($('txsize').value);
            if(!isFinite(v)||v<=0) v=100;
            v=Math.min(400,Math.max(25,v));
            $('txsize').value=v;
            var out={ key:TSEL.key, pct:v,
                      bold:$('txbold').className.indexOf('on')>=0,
                      italic:$('txitalic').className.indexOf('on')>=0 };
            if(extra) for(var k in extra) out[k]=extra[k];
            sketchup.set_text_mark(JSON.stringify(out));
          }

          // How tall a dimension's number is when the mark carries no height of
          // its own - which is every mark this window makes. Ruby says the
          // number in the payload rather than the window guessing it; a guess
          // here is how the window and the paper start disagreeing.
          function markTextH(){ return (DIM_TEXT_H>0) ? DIM_TEXT_H : 5; }

          // Where a dimension's NUMBER sits. The SAME arithmetic as
          // PlanCanvas.dim_label_xy - see the long note over it. Two copies of
          // one formula is a drift risk and is treated as one: rt81 and t50
          // check both sides against the same numbers.
          //
          //   oa  along the line   - his right/left
          //   oc  across the line  - his up/down
          // in the LINE'S own frame, so the number keeps its place relative to
          // the dimension however the line was drawn or later moved.
          // The two ends of the DIMENSION LINE - the clicked points pushed off
          // the object by `off`. The SAME arithmetic as PlanCanvas.dim_line.
          // Returns [ax,ay,bx,by,ux,uy,len].
          // How far point q lies to the LEFT of a -> b. This is the number the
          // third click of the dimension tool is choosing, and it is the same
          // `off` the finished mark stores - so what he sees while he is
          // pulling it is exactly what he gets.
          function offsetToward(a, b, q){
            var dx=b[0]-a[0], dy=b[1]-a[1];
            var L=Math.sqrt(dx*dx+dy*dy);
            if(L<1e-9) return 0;
            var ux=dx/L, uy=dy/L;
            return (q[0]-a[0])*(-uy) + (q[1]-a[1])*(ux);
          }

          function dimLine(m){
            var dx=m.x2-m.x1, dy=m.y2-m.y1;
            var len=Math.sqrt(dx*dx+dy*dy);
            if(len<1e-9) return [m.x1,m.y1,m.x2,m.y2,0,0,len];
            var ux=dx/len, uy=dy/len;
            var off=(m.off===undefined||m.off===null)?0:m.off;
            var nx=-uy*off, ny=ux*off;
            return [m.x1+nx,m.y1+ny,m.x2+nx,m.y2+ny,ux,uy,len];
          }

          function dimLabelXY(m){
            var L=dimLine(m);
            var mx=(L[0]+L[2])/2, my=(L[1]+L[3])/2;
            if(L[6]<1e-9) return [mx,my];
            var ux=L[4], uy=L[5];
            var h=(m.h>0)?m.h:markTextH();
            var oa=(m.oa===undefined||m.oa===null)?0:m.oa;
            var oc=(m.oc===undefined||m.oc===null)?h*DIM_LABEL_OFF:m.oc;
            return [mx+ux*oa-uy*oc, my+uy*oa+ux*oc];
          }

          // How far a NEW dimension stands off the wall. Remembered, because
          // a distance he liked once he will like again.
          function dimOff(){
            var v=(STATE&&STATE.dim_off);
            return (typeof v==='number' && isFinite(v)) ? v : 0;
          }

          // The box shows the PICKED dimension's own distance when there is
          // one, and the setting for the next one when there is not - so the
          // number in the box is always the number that typing in it changes.
          function paintDimOff(){
            var b=$('dimoff'); if(!b) return;
            var m=(SEL!==null)?marks()[SEL]:null;
            var v=(m&&m.t==='dim') ? ((m.off===undefined||m.off===null)?0:m.off)
                                   : dimOff();
            if(document.activeElement!==b) b.value=Math.round(v*100)/100;
          }

          function setDimOff(v){
            if(!isFinite(v)) return;
            var m=(SEL!==null)?marks()[SEL]:null;
            if(m && m.t==='dim'){ m.off=v; }      // the one he has picked
            else { STATE.dim_off=v; }             // and otherwise the next one
            push(); render(); showMarks();
          }

          // Everything a press knows about itself, written to a file so it can
          // be READ instead of argued about. Wrapped whole: if the probe
          // itself throws it must not take the click down with it, which is
          // the exact failure it exists to catch.
          function probeClick(e){
            try {
              var p=mouseAt(e), am=atMouse(e);
              var h=null, ht=null, hs=null;
              try { h=hitMark(e); } catch(err){ h={ERROR:String(err)}; }
              try { var t=hitText(e); ht=t?t.key:null; } catch(err){ ht='ERROR '+String(err); }
              try { hs=hitSite(e); } catch(err){ hs='ERROR '+String(err); }
              var ms=[];
              (STATE&&STATE.marks?STATE.marks:[]).forEach(function(m,i){
                if(m.t!=='dim'){ ms.push({i:i,t:m.t}); return; }
                var L=dimLine(m);
                var a=screenOf(L[0],L[1]), b=screenOf(L[2],L[3]);
                var lab=dimLabelXY(m), ls=screenOf(lab[0],lab[1]);
                ms.push({i:i, t:'dim',
                         a:[Math.round(a[0]),Math.round(a[1])],
                         b:[Math.round(b[0]),Math.round(b[1])],
                         label:[Math.round(ls[0]),Math.round(ls[1])],
                         dLine: p?Math.round(distToSeg(p[0],p[1],a,b)):null,
                         dLabel: p?Math.round(Math.hypot(ls[0]-p[0],ls[1]-p[1])):null});
              });
              sketchup.sheet_probe(JSON.stringify({
                mode:MODE, shift:!!e.shiftKey,
                mouseScreen: p?[Math.round(p[0]),Math.round(p[1])]:null,
                mouseModel: am?[Math.round(am[0]*10)/10,Math.round(am[1]*10)/10]:null,
                svgSize: (function(){
                  var s=$('sheetWrap').firstChild;
                  if(!s) return 'NO SVG';
                  var r=s.getBoundingClientRect();
                  return {rectW:Math.round(r.width), rectH:Math.round(r.height),
                          attrW:s.getAttribute?s.getAttribute('width'):null,
                          attrH:s.getAttribute?s.getAttribute('height'):null};
                })(),
                view: VIEW?{k:Math.round(VIEW.k*100)/100, sf:VIEW.sf,
                            cx:VIEW.cx, cy:VIEW.cy}:null,
                pageH: PAGE?PAGE.height:null,
                grab: GRAB,
                hitMark: h, hitTextKey: ht, hitSite: hs,
                SEL: SEL, TSEL: TSEL?TSEL.key:null,
                marks: ms
              }));
            } catch(err){
              try { sketchup.sheet_probe(JSON.stringify({PROBE_THREW:String(err)})); }
              catch(e2){ /* nothing left to do */ }
            }
          }

          // A note from the THREE points HE clicked (2026-08-19), which is
          // the shape in the Rayon screenshot he sent:
          //
          //   tip  --\                                  the arrow, click 1
          //           \____________________  [123]      the knee is click 2,
          //           knee            end              the shoulder end is 3
          //
          // The shoulder is kept level with the knee - he chooses how LONG it
          // is, not how crooked - and the words sit a small gap past its end.
          // All three points still drag afterwards.
          //
          // The gap is measured in PAPER inches and divided back out by the
          // scale, so a note looks the same on a 1/8" sheet and a 1/2" one.
          //
          // Its own function so t52 can build the note THE WINDOW builds,
          // rather than a copy of it - saveNote lives inside the load handler
          // and no suite can reach in there.
          function noteMark(tip, knee, end, text, arrow, sf){
            var off = 0.7 / (sf || (1/96));
            // Which way the shoulder runs is HIS - it is the third click.
            var away = (end[0] >= knee[0]) ? 1 : -1;
            // x/y is the MIDDLE of the words (draw_mark_note centres them), so
            // clearing the end of the line means half the words plus a pad -
            // not a flat nudge. With a flat one the left half of a long note
            // ran back over the shoulder, which is not what the picture shows:
            // there the box STARTS after the line ends.
            //
            // The width is the same rough estimate plan_canvas falls back to
            // (0.6 of the height per letter). It only decides where the words
            // start, so being a few per cent out costs nothing.
            var h = markTextH();
            var half = String(text || '').length * h * 0.6 / 2;
            // The shoulder is kept LEVEL with the knee, the way it is in the
            // picture he sent: he chooses how long it is, not how crooked.
            return {t:'note',
                    x: end[0] + away*(half + off*0.12), y: knee[1],
                    kx: knee[0], ky: knee[1],
                    lx: tip[0],  ly: tip[1],
                    text: text, arrow: !!arrow};
          }

          function moveMark(m, part, dx, dy){
            if(m.t==='dim'){
              if(part==='text'){
                // The mouse moved dx,dy across the sheet; the mark stores the
                // move ALONG the line and ACROSS it, so it survives the line
                // being dragged somewhere else afterwards.
                var ddx=m.x2-m.x1, ddy=m.y2-m.y1;
                var L=Math.sqrt(ddx*ddx+ddy*ddy);
                if(L<1e-9) return;
                var ux=ddx/L, uy=ddy/L;
                var h=(m.h>0)?m.h:markTextH();
                if(m.oa===undefined||m.oa===null) m.oa=0;
                if(m.oc===undefined||m.oc===null) m.oc=h*DIM_LABEL_OFF;
                m.oa += dx*ux + dy*uy;
                m.oc += dx*(-uy) + dy*ux;
              }
              else if(part==='off'){
                // Dragging the dimension LINE pulls it off the wall, the way a
                // dimension behaves in any drawing program. Only the sideways
                // part of the drag counts - sliding it along its own length
                // would mean nothing, and the two clicked points stay exactly
                // on the thing being measured.
                var edx=m.x2-m.x1, edy=m.y2-m.y1;
                var E=Math.sqrt(edx*edx+edy*edy);
                if(E<1e-9) return;
                if(m.off===undefined||m.off===null) m.off=0;
                m.off += dx*(-edy/E) + dy*(edx/E);
              }
              else if(part==='a'){ m.x1+=dx; m.y1+=dy; }
              else if(part==='b'){ m.x2+=dx; m.y2+=dy; }
              else { m.x1+=dx; m.y1+=dy; m.x2+=dx; m.y2+=dy; }
            } else {
              if(part==='tip'){ m.lx+=dx; m.ly+=dy; }
              else if(part==='knee'){ m.kx+=dx; m.ky+=dy; }
              else {
                // moving the words takes the shoulder with them, so the label
                // never drifts away from its own leader
                m.x+=dx; m.y+=dy;
                if(m.kx!==undefined){ m.kx+=dx; m.ky+=dy; }
              }
            }
          }

          function dropMark(){
            // Everything he picked, not just one - that is what the rubber band
            // is for (2026-08-19). Highest index first, or taking one out moves
            // the next.
            var gone = SELS.length ? SELS.slice() : (SEL===null ? [] : [SEL]);
            if(!gone.length) return;
            gone.sort(function(a,b){ return b-a; })
                .forEach(function(i){ if(marks()[i]) marks().splice(i,1); });
            SELS=[]; SEL=null;
            push(); render(); showMarks();
          }

          // A head on the end of the leader, or a bare line. SketchUp's own text
          // tool draws a bare one - the user sent a picture of it and asked for
          // both. Whatever he chose last is what the next note starts with.
          function paintArrow(){
            $('notearrow').className = 'tool' + (STATE.note_arrow===false ? '' : ' on');
          }

          function undoMark(){
            if(!marks().length) return;
            marks().pop();
            SEL=null;
            push(); showMarks();
          }

          // ESCAPE: out of whatever he is in the middle of (2026-10-07).
          //
          // The user: "אם אני מסמן משהו למחיקה או כל פעולה אחרת... ואני לוחץ
          // אסקייפ, זה יוצא לי אוטומטית מהפעולה שאני עושה." It is the first
          // line of the iron law in CLAUDE.md.
          //
          // What Escape did before: dropped a half-drawn dimension and what
          // was picked, and left him holding the same tool. And it did NOT
          // stop the eraser: a sweep already under way went on collecting and
          // rubbed everything out when the mouse was let go - Escape pressed
          // to save the lines, and the lines gone anyway.
          //
          // Now: everything half done is DROPPED, never finished -
          //   a sweep of the eraser      nothing is rubbed out
          //   a dimension or a note      the clicks so far are forgotten
          //   something being carried    goes back where it was picked up
          //   the plan being slid        goes back where it was
          //   a rubber band, a pick      gone
          // - and he is back on the select arrow, whatever tool he was in.
          var ESCEXITS = true;
          function escapeAll(){
            if(!ESCEXITS){
              // switched off: exactly what Escape did before 2026-10-07
              cancelCarry();
              BAND=null; SELS=[];
              PEND=null; PEND2=null; PEND3=null; HOVER=null; SEL=null; ERA=null;
              closeTextBar();
              render(); showMarks();
              return;
            }
            cancelCarry();                       // a mark in the hand goes home
            SSEL=[];                             // and the picked lines are let go
            TCARRY=null; TDRAG=null; MDRAG=null; // a label or a mark mid-drag stays put
            if(DRAG){
              if(DRAG.pan){
                var stg=$('stage'); stg.scrollLeft=DRAG.sl; stg.scrollTop=DRAG.st;
              } else {
                STATE.origin_x=DRAG.ox; STATE.origin_y=DRAG.oy;
              }
              DRAG=null;
            }
            BAND=null; SELS=[]; SEL=null;
            PEND=null; PEND2=null; PEND3=null; HOVER=null;
            ERA=null; ERASWEEP=null; ERADONE=false; SNAPPED=null;
            hideNoteBar();
            closeTextBar();
            if(MODE!=='hand'){ setMode('hand'); return; }   // setMode redraws
            render(); showMarks();
          }

          function setMode(m){
            cancelCarry();
            BAND=null; SELS=[];
            MODE=m; PEND=null; PEND2=null; PEND3=null; HOVER=null; ERA=null; ERASWEEP=null; ERADONE=false; SNAPPED=null;
            SSEL=[];
            if(m!=='hand') SEL=null;
            ['thand','tdim','tnote','terase'].forEach(function(id){
              $(id).className='tool'+(($(id).id==='t'+m)?' on':'');
            });
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor = m==='hand' ? 'default' : 'crosshair';
            showMarks();
            render();
          }

          function showMarks(){
            var n=marks().length;
            $('tundo').disabled = !n;
            var tip={hand:'לחץ על קו או סימון כדי לבחור · Shift+לחיצה מוסיף · מתח ריבוע לבחירת כמה · Delete מוחק · Alt+גרירה מזיז את התוכנית.',
                     dim:'1 לחץ בהתחלה · 2 לחץ בסוף · 3 משוך את הקו מהקיר ולחץ.',
                     note:'1 לחץ על מה שההערה מדברת עליו · 2 איפה שהקו נשבר · 3 סוף הקו · ואז כתוב.',
                     erase:'העבר על מידה, הערה או קו — הם נצבעים. לחיצה או גרירה מוחקת. המודל לא משתנה.'}[MODE];
            if(MODE==='note'&&PEND&&!PEND2) tip='2 עכשיו לחץ איפה שהקו נשבר.';
            if(MODE==='note'&&PEND&&PEND2&&!PEND3) tip='3 עכשיו לחץ בסוף הקו, שם ייכתב הטקסט.';
            if(MODE==='dim'&&PEND&&!PEND2) tip='2 עכשיו לחץ על הנקודה השנייה.';
            if(MODE==='dim'&&PEND&&PEND2)
              tip='3 משוך את הקו לאיפה שאתה רוצה ולחץ. Esc מבטל.';
            if(MODE==='hand'&&SEL!==null){
              tip='נבחר. לחיצה מרימה, לחיצה שנייה מניחה. Delete מוחק.';
              if(marks()[SEL] && marks()[SEL].t==='dim')
                tip='נבחר. לחץ על הקו או על המספר כדי להרים, הזז, ולחץ שוב להניח. חיצים לדיוק.';
            }
            if(SELS.length>1) tip=SELS.length+' נבחרו. לחיצה מרימה את כולם יחד, Delete מוחק את כולם.';
            if(MODE==='hand'&&SSEL.length)
              tip=SSEL.length+(SSEL.length===1?' קו נבחר':' קווים נבחרו')+' · Shift+לחיצה מוסיף או מוריד · Delete מוחק · Ctrl+Z מחזיר · Esc משחרר.';
            if(CARRY||TCARRY) tip='מחזיק — הזז ולחץ כדי להניח. Esc מחזיר.';
            paintDimOff();
            // No free geometry is no longer a dead end - the eraser still
            // takes dimensions and notes (2026-08-19).
            if(MODE==='erase'&&!siteLayer()&&!n)
              tip='אין מה למחוק על הדף הזה.';
            // The mark counter belongs to the marks, not to the rubber.
            $('markinfo').textContent = tip +
              ((n && MODE!=='erase') ? ('  ·  ' + n + ' על הדף') : '');
            headings();
          }

          // ---- dragging the plan -----------------------------------------
          var DRAG=null;
          function hookDrag(){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return;
            svg.style.cursor = MODE==='hand' ? arrowCursor()
                             : MODE==='erase' ? eraserCursor() : 'crosshair';

            svg.onmousemove=function(e){
              if(MODE==='erase'){
                var h3=hitErase(e);
                if(ERASWEEP){
                  // dragging: everything crossed joins the sweep
                  if(h3 && !ERASWEEP.some(function(x){ return sameEra(x,h3); })){
                    ERASWEEP.push(h3);
                  }
                  paintErase();
                } else if(!sameEra(h3,ERA)){
                  ERA=h3; paintErase();
                }
                svg.style.cursor = eraserCursor();
                return;
              }
              if(MODE==='note'&&PEND&&!PEND3){
                var np=atMouse(e);
                if(np){ HOVER=np; render(); }
                return;
              }
              if(MODE==='dim'){
                if(PEND&&PEND2){
                  // the third stage: the mouse is choosing how far off the
                  // wall the line sits. Only the sideways part of where he is
                  // counts - sliding along the measured line means nothing.
                  var mp=atMouse(e);
                  if(mp){ PENDOFF=offsetToward(PEND,PEND2,mp); render(); }
                  return;
                }
                // Show the corner it will lock onto BEFORE he clicks, so he is
                // never guessing whether it caught - the whole point of a snap.
                var hp=snapPoint(atMouse(e));
                if(PEND){ HOVER=hp; render(); }
                else { paintSnap(); }
                return;
              }
              if(MODE==='hand'&&!MDRAG&&!DRAG){
                svg.style.cursor = hitMark(e) ? 'move' : arrowCursor();
              }
            };

            svg.onmousedown=function(e){
              // In the hand tool a mark under the mouse is picked up; empty
              // paper still drags the plan the way it always did.
              if(MODE==='hand'&&!e.shiftKey){
                // Carrying something? Then this click PUTS IT DOWN. Nothing
                // else gets to happen on it.
                if(CARRY){ dropCarry(); e.preventDefault(); return; }
                if(TCARRY){ dropTextCarry(); e.preventDefault(); return; }
                var h=hitMark(e);
                if(h){
                  if(TSEL) closeTextBar();
                  // clicking one thing picks that one thing, and drops
                  // whatever the band had picked before
                  SSEL=[];
                  if(SELS.indexOf(h.i)<0) SELS=[h.i];
                  SEL=h.i;
                  MDRAG={part:h.part, at:atMouse(e)};
                  svg.style.cursor='move';
                  render(); showMarks();
                  e.preventDefault();
                  return;
                }
                // Nothing hand-drawn under the mouse - so try any WRITING on
                // the sheet (2026-08-19). This is the one the user was after:
                // the dimensions the plugin draws on the walls itself are not
                // marks, so there was nothing to grab and the click panned the
                // whole plan instead. They could already be picked with two
                // clicks to change their SIZE; now one click picks them and
                // they drag, the way they do in every other program.
                var ht=hitText(e);
                if(ht){
                  SEL=null;
                  SSEL=[];
                  TSEL=ht;
                  TDRAG={at:atMouse(e), dx:0, dy:0, moved:false};
                  TCARRY=null;
                  svg.style.cursor='move';
                  paintTextPick(); showMarks();
                  e.preventDefault();
                  return;
                }
                if(TSEL){ closeTextBar(); }
                if(SEL!==null||SELS.length){ SEL=null; SELS=[]; render(); showMarks(); }
              }
              // Write down what this press was given and what the hit test
              // made of it (2026-08-19). See the sheet_probe callback.
              if(MODE==='hand'||MODE==='erase') probeClick(e);
              // The eraser starts a SWEEP: whatever the mouse crosses from
              // here until it is let go goes together, the way dragging the
              // eraser across a drawing works in SketchUp (2026-08-19).
              if(MODE==='erase'&&!e.shiftKey){
                var h4=hitErase(e);
                ERASWEEP = h4 ? [h4] : [];
                ERA=null;
                paintErase();
                e.preventDefault();
                return;
              }
              if(MODE!=='hand'&&!e.shiftKey){ e.preventDefault(); return; }
              // Empty paper in SELECT mode pulls a rubber band, the way it does
              // in SketchUp (2026-08-19). Moving the DRAWING around the sheet
              // used to live on this gesture; it is on Alt-drag now, and the
              // hint line says so. Shift still pans the view.
              if(MODE==='hand' && !e.shiftKey && !e.altKey && e.button!==1 &&
                 (PAGE.views||[])[0]){
                var bp=mouseAt(e);
                if(bp){
                  BAND={x0:bp[0], y0:bp[1], x1:bp[0], y1:bp[1], moved:false,
                        hit:(LINEPICK ? hitSite(e) : null)};
                  paintBand();
                  e.preventDefault();
                  return;
                }
              }
              var stage=$('stage');
              var pan = e.shiftKey || e.button===1 || !(PAGE.views||[])[0];
              DRAG={x:e.clientX,y:e.clientY,ox:STATE.origin_x,oy:STATE.origin_y,
                    pan:pan, sl:stage.scrollLeft, st:stage.scrollTop};
              // Shift held: dragging still slides the view, as it always has.
              // But a press that goes nowhere is a CLICK, and Shift+click adds
              // to what is picked - so remember what was under it.
              if(pan && e.shiftKey && MODE==='hand' && LINEPICK){
                var sm=hitMark(e), shs=sm ? null : hitSite(e);
                DRAG.pick = sm ? {kind:'mark', i:sm.i} : (shs!==null ? {kind:'site', i:shs} : null);
              }
              svg.style.cursor= pan ? 'move' : arrowCursor();
              e.preventDefault();
            };

            // Two clicks on a note open its words for changing, the way any
            // drawing program does it. The leader and the box stay where they
            // are; only the writing changes.
            svg.ondblclick=function(e){
              var h=hitMark(e);
              // A note's own words come first - two clicks on a note has meant
              // "change what it says" since 2026-08-14 and that is not being
              // taken away. Anything else falls through to the size and weight
              // of whatever writing is under the mouse.
              if(!h || marks()[h.i].t!=='note'){
                var ht=hitText(e);
                if(ht){ hideNoteBar(); openTextBar(ht); e.preventDefault(); }
                return;
              }
              closeTextBar();
              var m=marks()[h.i];
              SEL=h.i;
              EDIT=h.i;
              PEND=null;
              $('notebar').className='on';
              $('notetext').value=m.text||'';
              STATE.note_arrow = m.arrow!==false;
              paintArrow();
              $('notetext').focus();
              $('notetext').select();
              e.preventDefault();
            };

            svg.onclick=function(e){
              if(MODE==='hand'||e.shiftKey) return;
              if(MODE==='erase'){
                // Letting go has already taken the sweep; this click is the
                // browser's echo of it and has nothing left to do.
                if(ERADONE){ ERADONE=false; return; }
                var hi=hitErase(e);
                if(hi===null){
                  $('markinfo').textContent='אין כלום מתחת לעכבר.';
                  return;
                }
                ERA=null; paintErase();
                eraseSweep([hi]);
                return;
              }
              var p=atMouse(e);
              if(!p){ $('markinfo').textContent='אין תוכנית בדף הזה'; return; }
              if(MODE==='dim'){
                // THREE clicks, like every other drawing program:
                //   1  what to measure from   (locks onto a corner)
                //   2  what to measure to     (locks onto a corner)
                //   3  where the line sits    (pull it off the wall)
                if(!PEND){
                  PEND=snapPoint(p); HOVER=PEND; PEND2=null; PENDOFF=dimOff();
                  showMarks(); return;
                }
                if(!PEND2){
                  PEND2=snapPoint(p);
                  PENDOFF=dimOff();      // start from the distance he last used
                  HOVER=PEND2;
                  render(); showMarks(); return;
                }
                // the third click leaves it where he pulled it to
                marks().push({t:'dim',x1:PEND[0],y1:PEND[1],x2:PEND2[0],y2:PEND2[1],
                              off:PENDOFF});
                STATE.dim_off=PENDOFF;   // and the next one starts there too
                PEND=null; PEND2=null; PEND3=null; HOVER=null; SNAPPED=null;
                push(); render(); showMarks();
              } else if(MODE==='note'){
                // A leader is DRAWN, not guessed (2026-08-19). The user, on
                // how Rayon does it: "קודם לחיצה אחת זה מותח קו אחד, ואז עוד
                // לחיצה מותח קו שני, ורק אז כותבים בריבוע מה שרוצים."
                //
                //   1  what the note is about   (the arrow tip, snaps)
                //   2  where the leader bends   (and the words sit there)
                //   3  type
                //
                // It used to be one click and the plugin chose the other two
                // points for him - up and to the right, always - and then he
                // dragged them where he actually wanted them. Two jobs for one
                // note, which is the thing he called out.
                if($('notebar').className==='on') return;   // already typing
                if(!PEND){
                  PEND=snapPoint(p); PEND2=null; PEND3=null; HOVER=PEND;
                  render(); showMarks(); return;
                }
                if(!PEND2){
                  PEND2=p; HOVER=p;
                  render(); showMarks(); return;
                }
                PEND3=p;
                HOVER=p;
                render();
                $('notebar').className='on';
                $('notetext').value='';
                paintArrow();
                $('notetext').focus();
              }
            };
          }

          function onMove(e){
            if(BAND){
              var bq=mouseAt(e);
              if(bq){ BAND.x1=bq[0]; BAND.y1=bq[1]; BAND.moved=true; paintBand(); }
              return;
            }
            // carrying a mark: it follows the mouse, live, with no button held
            if(CARRY){
              var nc=atMouse(e);
              if(nc){
                var ddx=nc[0]-CARRY.at[0], ddy=nc[1]-CARRY.at[1];
                if(CARRY.many && CARRY.many.length>1){
                  // several things picked: they all travel together, and they
                  // travel WHOLE - nobody wants one end of one dimension to
                  // come along and not the other
                  CARRY.many.forEach(function(i){
                    if(marks()[i]) moveMark(marks()[i], 'all', ddx, ddy);
                  });
                } else if(marks()[CARRY.i]){
                  moveMark(marks()[CARRY.i], CARRY.part, ddx, ddy);
                }
                CARRY.at=nc;
                render();
              }
              return;
            }
            // and carrying a label - only the highlight can move live, because
            // Ruby draws the writing; the real move goes on the drop click
            if(TCARRY){
              var nt2=atMouse(e);
              if(nt2){
                TCARRY.dx += nt2[0]-TCARRY.at[0];
                TCARRY.dy += nt2[1]-TCARRY.at[1];
                TCARRY.at = nt2;
                paintTextPick();
              }
              return;
            }
            if(TDRAG){
              var nowt=atMouse(e);
              if(nowt){
                TDRAG.dx += nowt[0]-TDRAG.at[0];
                TDRAG.dy += nowt[1]-TDRAG.at[1];
                TDRAG.at = nowt;
                TDRAG.moved = true;
                paintTextPick();
              }
              return;
            }
            if(MDRAG){
              var now=atMouse(e);
              if(now){
                moveMark(marks()[SEL], MDRAG.part, now[0]-MDRAG.at[0], now[1]-MDRAG.at[1]);
                MDRAG.at=now;
                MDRAG.moved=true;
                render();
              }
              return;
            }
            if(!DRAG) return;
            var stage=$('stage');
            if(DRAG.pan){
              if(Math.abs(e.clientX-DRAG.x)+Math.abs(e.clientY-DRAG.y)>3) DRAG.dragged=true;
              stage.scrollLeft = DRAG.sl-(e.clientX-DRAG.x);
              stage.scrollTop  = DRAG.st-(e.clientY-DRAG.y);
              return;
            }
            var k=fitK()*(ZOOM||1);
            var sf=scaleFactor(STATE.scale);
            STATE.origin_x=DRAG.ox-(e.clientX-DRAG.x)/k/sf;
            STATE.origin_y=DRAG.oy+(e.clientY-DRAG.y)/k/sf;
            render(true);
          }

          function onUp(){
            if(BAND){
              var band=BAND;
              BAND=null;
              paintBand();
              if(band.moved) pickInBand(band);
              else {
                // a plain click: on a loose line it picks that line, on empty
                // paper it lets go of everything
                SELS=[]; SEL=null;
                SSEL=(band.hit!==null && band.hit!==undefined) ? [band.hit] : [];
              }
              render(); showMarks();
              return;
            }
            if(ERASWEEP){
              var sweep=ERASWEEP;
              ERASWEEP=null;
              ERADONE=true;          // the click that follows has nothing left to do
              paintErase();
              eraseSweep(sweep);
              return;
            }
            if(TDRAG){
              var tmoved=TDRAG.moved, tdx=TDRAG.dx, tdy=TDRAG.dy, tat=TDRAG.at;
              TDRAG=null;
              var svgt=$('sheetWrap').firstChild;
              if(svgt) svgt.style.cursor='move';
              if(tmoved){ nudgeText(tdx, tdy); }
              else {
                // a plain click on a label PICKS IT UP
                TCARRY={at:tat, dx:0, dy:0};
                paintTextPick(); showMarks();
              }
              return;
            }
            if(MDRAG){
              var moved=MDRAG.moved, mpart=MDRAG.part, mat=MDRAG.at;
              MDRAG=null;
              var svg0=$('sheetWrap').firstChild;
              if(svg0) svg0.style.cursor='move';
              if(moved){ push(); }
              else if(SEL!==null && marks()[SEL]){
                // a plain click PICKS IT UP - it now follows the mouse and the
                // next click puts it down
                CARRY={i:SEL, part:mpart, at:mat,
                       many:SELS.slice(),
                       snap:JSON.parse(JSON.stringify(marks()[SEL])),
                       snaps:JSON.parse(JSON.stringify(SELS.map(function(i){ return marks()[i]; })))};
                showMarks();
              }
              return;
            }
            if(!DRAG) return;
            var moved=!DRAG.pan;
            var shiftPick=(DRAG.pan && !DRAG.dragged) ? (DRAG.pick||null) : null;
            DRAG=null;
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor = MODE==='hand' ? arrowCursor() : 'crosshair';
            if(shiftPick){ togglePick(shiftPick); render(); showMarks(); }
            if(moved) push();
          }

          // ---- talking to Ruby -------------------------------------------
          // ---- Ctrl+Z ------------------------------------------------------
          //
          // "אם מחקתי משהו ואני לוחץ קונטרול Z הוא צריך לחזור" (2026-10-07) -
          // line 2 of the iron law in CLAUDE.md. This window had no undo at
          // all: a line rubbed out by mistake could only come back by putting
          // back EVERYTHING ever rubbed out.
          //
          // One list, newest last. Two kinds of step go on it:
          //   marks  what the hand-drawn dimensions and notes were BEFORE the
          //          change. Caught in push(), the one door every change to
          //          them leaves by - so adding, moving, rewording and rubbing
          //          one out are all caught, without each having to remember.
          //   site   the loose lines one sweep of the eraser took, each with
          //          the number it had, so it goes back exactly there.
          // A sweep that took both is ONE step (same g), because to him it
          // was one movement of the hand.
          var UNDO=[], UGROUP=0, UCUR=null, UNDOON=true, UNDOING=false;
          var LASTMARKS='[]';      // the marks as they were the last time they were saved
          var USITE_N=null;        // how many loose lines the sheet has, by our own count

          function noteMarksForUndo(){
            var now=JSON.stringify(STATE.marks||[]);
            if(now===LASTMARKS) return;
            if(UNDOON && !UNDOING){
              UNDO.push({g:(UCUR!==null ? UCUR : ++UGROUP), marks:LASTMARKS});
              if(UNDO.length>300) UNDO.shift();
            }
            LASTMARKS=now;
          }

          function push(){
            noteMarksForUndo();
            sketchup.set_state(JSON.stringify(STATE));
          }

          // The SITE layer whether or not it is switched off: a line rubbed
          // out while it was showing must be able to come back either way.
          function rawSiteLayer(){
            if(!DOC) return null;
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name==='MODEL'; })[0];
            if(!cv) return null;
            return (cv.layers||[]).filter(function(l){ return l.name==='SITE'; })[0]||null;
          }

          function undoLast(){
            if(!UNDOON) return false;
            if(!UNDO.length){ $('markinfo').textContent='אין מה לבטל.'; return false; }
            var g=UNDO[UNDO.length-1].g, marksBack=null, siteBack=[];
            while(UNDO.length && UNDO[UNDO.length-1].g===g){
              var u=UNDO.pop();
              if(u.marks!==undefined) marksBack=u.marks;   // popped newest first: the oldest wins
              if(u.site) siteBack=siteBack.concat(u.site);
            }
            // nothing half done survives an undo - it was drawn on the sheet as it was
            SSEL=[];
            cancelCarry();
            TCARRY=null; TDRAG=null; MDRAG=null; BAND=null; SELS=[]; SEL=null;
            PEND=null; PEND2=null; PEND3=null; HOVER=null; ERA=null; ERASWEEP=null; SNAPPED=null;
            if(siteBack.length){
              var lay=rawSiteLayer();
              if(lay && lay.shapes){
                var n=lay.shapes.length;
                siteBack.sort(function(a,b){ return a.i-b.i; }).forEach(function(x){
                  lay.shapes.splice(Math.min(x.i, lay.shapes.length), 0, x.s);
                });
                STATE.site_count=lay.shapes.length;
                USITE_N=lay.shapes.length;
                sketchup.undo_site_drop(JSON.stringify({
                  items:siteBack.map(function(x){ return {i:x.i, p:x.s.points}; }), n:n}));
              }
            }
            if(marksBack!==null){
              UNDOING=true;
              STATE.marks=JSON.parse(marksBack);
              LASTMARKS=marksBack;
              sketchup.set_state(JSON.stringify(STATE));
              UNDOING=false;
            }
            render(); showMarks();
            return true;
          }


          var LOADED = false;      // has this window been given a sheet yet
          var KEEPVIEW = true;
          function loadSheet(p){
            DOC=p.doc; STATE=p.state; BOUNDS=p.bounds; SCALES=p.scales;
            FAST = (p.fast!==false);
            ZHOLD = (p.zoom_hold!==false);
            KEEPVIEW = (p.keep_view!==false);
            if(p.deep_zoom===false){ ZMAX=14; KSTROKE=Infinity; } else { ZMAX=200; KSTROKE=160; }
            FASTERASE = (p.fast_erase!==false);
            ESCEXITS = (p.escape_exits!==false);
            UNDOON = (p.undo!==false);
            LINEPICK = (p.line_pick!==false);
            SSEL=[];                 // the numbers belonged to the sheet that was just replaced
            if(p.dim_text_h>0) DIM_TEXT_H=p.dim_text_h;
            if(p.dim_label_off!==undefined && p.dim_label_off!==null)
              DIM_LABEL_OFF=p.dim_label_off;
            // Every picture the sheet can show needs an address here, not just
            // the renders. The logo is a picture too - it sits in the title
            // block - and leaving it out of this list is why the user picked a
            // logo and saw nothing but the empty dashed box (2026-08-14).
            URLS={};
            (p.images||[]).forEach(function(im){ if(im.url) URLS[im.path]=im.url; });
            if(p.logo && p.logo.url) URLS[p.logo.path]=p.logo.url;
            if(STATE.active===undefined||STATE.active===null) STATE.active=0;
            // A sheet sent AGAIN to a window that is already open is a
            // refresh, not a fresh start (2026-10-07).
            //
            // Rubbing out a line, adding what is selected, a new logo - each
            // makes Ruby build the sheet again and send all of it, with the
            // settings that are SAVED ON THE MODEL. The wheel never saves:
            // it would mean a trip to Ruby and a full redraw for every click
            // of it. So the saved zoom is whatever it was the last time
            // something else was saved - usually nothing - and every refresh
            // threw him back to the whole sheet in the corner of the window.
            // Measured on his drawing: zoom 3.06 and scrolled to 901, 665;
            // one line rubbed out; zoom "fit" and scrolled to 0, 0. His words:
            // "הוא כאילו קופץ לי אחורה ואז אני מתחיל מהתחלה כאילו נכנסתי
            // לתוכנה. הוא לא פשוט מוחק ואפשר להמשיך."
            //
            // The first sheet a window is given still opens on the saved zoom.
            // After that the zoom on the screen is the one that counts.
            if(LOADED && KEEPVIEW){ STATE.zoom = ZOOM; }
            else { ZOOM = STATE.zoom || null; }
            LOADED = true;
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
            siteDropped(STATE.site_count||0, STATE.site_dropped||0);
            showTextScale();
            // The label that is open for changing is a shape out of the OLD
            // document, and the one that just came back is a different object
            // with the same key. Point at the new one, or the blue box would
            // stay where the label used to be and the next change would be
            // worked out from a stale size.
            if(TSEL){
              var again=null;
              eachText(function(s){ if(s.key===TSEL.key) again=s; });
              if(again) TSEL.shape=again; else closeTextBar();
            }
            if(!STATE.marks) STATE.marks=[];
            // A sheet from Ruby is the truth about the marks, so it is the new
            // baseline. And if it does not have the number of loose lines this
            // window counted, the list was read again or cleared behind the
            // undo list's back: the numbers in those steps point at other
            // lines now, so those steps are forgotten rather than trusted.
            LASTMARKS=JSON.stringify(STATE.marks);
            var usl=rawSiteLayer(), usn=(usl&&usl.shapes) ? usl.shapes.length : 0;
            if(USITE_N!==null && usn!==USITE_N) UNDO=UNDO.filter(function(u){ return !u.site; });
            USITE_N=usn;
            if(STATE.strip){
              $('strip').className='on';
              $('stripbtn').textContent='הסתר את הדפים';
            }
            buildLayers();
            buildSections();
            showLogo(p.logo);
            fillPages();
            showMarks();
            if(first){ fitPlan(); return; }
            showFit();
            render();
          }

          function applyPages(pages, marksLayer){
            DOC.pages=pages;
            if(marksLayer) putLayer('MODEL', marksLayer);
            if(STATE.active>=pages.length) STATE.active=0;
            fillPages();
            buildLayers();
            showFit();
            render();
          }

          // Drop a layer Ruby just rebuilt in over the one we were holding.
          function putLayer(canvasName, lay){
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===canvasName; })[0];
            if(!cv) return;
            var at=-1;
            cv.layers.forEach(function(l,i){ if(l.name===lay.name) at=i; });
            if(at>=0) cv.layers[at]=lay; else cv.layers.push(lay);
          }

          // One list for every sheet in the set - plan, schedules, renders.
          // Click a row to go there, the TICK says whether it goes into the
          // PDF, the x throws it away. Since 2026-08-19 the x is on every row
          // including the plan sheet, and the tick is the answer to "print
          // only some of these" - two different questions, two controls.
          // ---- the page strip ---------------------------------------------
          //
          // Every sheet drawn small, down the far side of the drawing. Same
          // routine as the big one - see sheetSVG - so a thumbnail can never
          // show something the sheet does not.
          function goToPage(i){
            if(!DOC||!DOC.pages.length) return;
            STATE.active=Math.max(0, Math.min(DOC.pages.length-1, i));
            fillPages(); showFit(); render(); push();
          }

          function paintStrip(){
            var box=$('strip');
            if(box.className!=='on'){ box.innerHTML=''; return; }
            // Drawn at 520 across and shown at 166. shapeSVG throws away any
            // text under 1.5 pixels, because at that size it is a smudge - so
            // a thumbnail built at its finished size came out with no words on
            // it at all (t36 caught this). Draw it big, let the browser shrink
            // it, and the little sheet says the same things the big one does.
            var W=520;
            box.innerHTML='';
            var skip=(STATE.pdf_skip||[]);
            (DOC.pages||[]).forEach(function(pg,i){
              var key=pageKey(pg);
              var out=skip.indexOf(key)>=0;
              var d=document.createElement('div');
              d.className='thumb'+(i===(STATE.active||0)?' sel':'')+(out?' off':'');
              d.onclick=function(){ goToPage(i); };
              d.innerHTML='<div class="sheet">'+sheetSVG(pg, W/pg.width, false)+'</div>';
              // the tick lives HERE now - next to the picture of the sheet, so
              // he is choosing pages he can see
              var cap=document.createElement('div');
              cap.className='cap';
              var c=document.createElement('input');
              c.type='checkbox'; c.checked=!out;
              c.title='לצרף את הדף הזה ל-PDF';
              c.onclick=function(e){ e.stopPropagation(); togglePdf(key); };
              cap.appendChild(c);
              var t=document.createElement('span');
              t.textContent=(pg.sheet_number||('#'+(i+1)))+'  '+pg.name;
              cap.appendChild(t);
              d.appendChild(cap);
              box.appendChild(d);
            });
            var sel=box.querySelector('.thumb.sel');
            if(sel && sel.scrollIntoView) sel.scrollIntoView({block:'nearest'});
          }

          function toggleStrip(){
            var box=$('strip');
            var on = box.className!=='on';
            box.className = on ? 'on' : '';
            $('stripbtn').textContent = on ? 'הסתר את הדפים' : 'הצג את הדפים ובחר מה יוצא ל-PDF';
            STATE.strip = on;
            paintStrip();
            render();                        // the drawing area just changed width
          }

          // The name a sheet answers to in the settings. The SAME three lines
          // as PlanSheetDialog.page_key on the Ruby side - not the number and
          // not the position, because both of those move the moment a sheet is
          // added or thrown away, and a tick that moved with them would
          // quietly start meaning a different sheet.
          function pageKey(p){
            var k=(p&&p.kind)||'plan';
            return k==='image' ? ('image:'+p.ref) : k;
          }

          // The tick keeps the sheet in the set and only leaves it out of the
          // print. Nothing is deleted here and nothing is rebuilt - the state
          // goes back to Ruby and the PDF reads it at export time.
          function togglePdf(key){
            var s=(STATE.pdf_skip||[]).slice();
            var at=s.indexOf(key);
            if(at>=0) s.splice(at,1); else s.push(key);
            STATE.pdf_skip=s;
            fillPages();      // which repaints the strip too
            push();
          }

          function fillPages(){
            var box=$('pages'); box.innerHTML='';
            var skip=(STATE.pdf_skip||[]);
            var off=0;
            (DOC.pages||[]).forEach(function(p,i){
              var key=pageKey(p);
              var out=skip.indexOf(key)>=0;
              if(out) off++;
              var row=document.createElement('div');
              row.className='pg'+(i===(STATE.active||0)?' sel':'')+(out?' off':'');
              row.onclick=function(){ $('pages').focus(); goToPage(i); };
              // The tick moved to the THUMBNAILS (2026-08-19). The user:
              // "אני רוצה שהווי יעבור לתמונות של הדפים... כי מרגיש לי שיותר קל
              // לבחור דפים שרואים בהוצאה ל-PDF." So this list is the x - what
              // is in the set - and the strip is the tick - what gets printed.
              // A row still shows struck through when its sheet is out, which
              // tells him where things stand without being a second control.
              var num=document.createElement('b');
              num.textContent=p.sheet_number||('#'+(i+1));
              row.appendChild(num);
              var nm=document.createElement('span');
              nm.textContent=p.name; nm.title=p.name;
              row.appendChild(nm);
              // and the x - every sheet, the plan sheet included (2026-08-19).
              var x=document.createElement('button');
              x.textContent='×'; x.title='למחוק את הדף הזה מהתוכנית';
              x.onclick=function(e){
                e.stopPropagation();
                sketchup.delete_page(JSON.stringify({kind:(p.kind||'plan'), ref:p.ref}));
              };
              row.appendChild(x);
              box.appendChild(row);
            });
            // the one page that cannot be added back from anywhere else
            if(STATE.drop_plan){
              var b=document.createElement('button');
              b.id='planback'; b.textContent='החזר את דף התוכנית';
              b.onclick=function(){ sketchup.restore_plan(); };
              box.appendChild(b);
            }
            var t=$('pagestag');
            if(t){
              var n=(DOC.pages||[]).length;
              t.textContent = off ? ((n-off)+' מתוך '+n+' ל-PDF') : '';
            }
            var sel=box.querySelector('.pg.sel');
            if(sel && sel.scrollIntoView) sel.scrollIntoView({block:'nearest'});
            paintStrip();
          }

          function fill(id,list,val){
            var el=$(id); el.innerHTML='';
            list.forEach(function(s){
              var o=document.createElement('option'); o.value=s; o.textContent=s;
              if(s===val) o.selected=true; el.appendChild(o);
            });
          }

          // ---- the boxes that open ----------------------------------------
          //
          // The side used to be one long column with everything on show at
          // once. Now every group is a box with a heading you press. Only the
          // page list starts open; the rest wait until they are wanted.
          //
          // Each heading carries a small note of what is inside - how many
          // layers are switched off, how many marks are on the sheet - because
          // a setting that is both changed AND out of sight is how a drawing
          // comes out wrong and nobody can see why.
          var OPEN_AT_FIRST = {pages:true};

          function sections(){
            return document.querySelectorAll('#side .sec');
          }

          function openSection(key, on){
            var l=sections();
            for(var i=0;i<l.length;i++){
              if(l[i].getAttribute('data-k')!==key) continue;
              l[i].className='sec'+(on?' open':'');
              var ar=l[i].querySelector('.ar');
              if(ar) ar.innerHTML = on ? '&#9662;' : '&#9656;';
            }
            if(!STATE.open) STATE.open={};
            STATE.open[key]=!!on;
          }

          function isOpen(key){
            var o=STATE.open||{};
            return o[key]===undefined ? (OPEN_AT_FIRST[key]===true) : !!o[key];
          }

          function buildSections(){
            var l=sections();
            for(var i=0;i<l.length;i++){
              (function(sec){
                var key=sec.getAttribute('data-k');
                sec.querySelector('h4').onclick=function(){
                  openSection(key, sec.className.indexOf('open')<0);
                  push();
                };
                openSection(key, isOpen(key));
              })(l[i]);
            }
          }

          function tag(id, text){
            var el=$(id);
            if(el) el.textContent = text || '';
          }

          function layerCount(){
            var off=(STATE.hidden||[]).length;
            tag('laycount', off ? (off + ' כבויות') : '');
          }

          // what each heading says about itself when it is shut
          function headings(){
            layerCount();
            var n=marks().length;
            tag('markstag', n ? (n + ' על הדף') : '');
            var imgs=(DOC&&DOC.pages||[]).filter(function(p){ return p.kind==='image'; }).length;
            tag('imgtag', imgs ? (imgs + ' דפים') : '');
            tag('papertag', (STATE.size||'') + ' · ' + (STATE.scale||''));
            tag('sitetag', STATE.site_count ? (STATE.site_count + ' קווים') : '');
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
                layerCount(); render(); push();
              };
              lab.appendChild(cb);
              lab.appendChild(document.createTextNode(n));
              box.appendChild(lab);
            });
            layerCount();
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

          // ---- the logo ----------------------------------------------------
          function showLogo(l){
            var img=$('logoshow');
            if(l && l.url && l.there){
              img.src=l.url; img.className='on';
              $('logoinfo').textContent=l.name;
              tag('settag','לוגו');
              $('logoclear').style.display='';
            } else {
              img.removeAttribute('src'); img.className='';
              $('logoinfo').textContent = l && !l.there
                ? ('הקובץ לא נמצא: ' + l.name) : '';
              tag('settag','');
              $('logoclear').style.display = l ? '' : 'none';
            }
          }

          function logoDone(err){
            $('logoinfo').textContent = err ? ('שגיאה: '+err) : '';
          }

          function imageReport(n, err){
            $('imginfo').textContent = err ? ('שגיאה: '+err)
              : (n ? (n===1 ? 'נוספה תמונה אחת' : ('נוספו '+n+' תמונות'))
                   : 'לא נבחר כלום');
          }

          // ---- how big the writing is -------------------------------------
          //
          // Ruby owns the sizes. These boxes only say what they are and send a
          // new number; the picture comes back from the same routine that
          // writes the PDF, so what he sees is what prints.
          var TS_FIELDS = { dims:'tsDims', rooms:'tsRooms',
                            tags:'tsTags', tables:'tsTables' };

          function textScale(){ return STATE.text_scale||(STATE.text_scale={}); }

          function showTextScale(){
            var ts=textScale(), off=0;
            for(var k in TS_FIELDS){
              var v=ts[k]; if(v===undefined||v===null||!(+v>0)) v=100;
              $(TS_FIELDS[k]).value = +v;
              if(+v!==100) off++;
            }
            // The heading says so when something is not at 100, because the
            // box is shut most of the time and a shrunken tag three sheets
            // later is otherwise a mystery.
            $('texttag').textContent = off ? (off+' שונו') : '';
            $('tsReset').disabled = !off;
          }

          function sendTextScale(){
            var out={};
            for(var k in TS_FIELDS){
              var v=parseFloat($(TS_FIELDS[k]).value);
              if(!isFinite(v)||v<=0) v=100;
              v=Math.min(400,Math.max(25,v));
              $(TS_FIELDS[k]).value=v;
              out[k]=v;
            }
            textScale();
            for(var k2 in out) STATE.text_scale[k2]=out[k2];
            showTextScale();
            sketchup.set_text_scale(JSON.stringify(out));
          }

          function resetTextScale(){
            for(var k in TS_FIELDS) $(TS_FIELDS[k]).value=100;
            sendTextScale();
          }

          function siteDone(n, err){
            $('siteinfo').textContent = err ? ('לא נוסף: ' + err)
              : (n ? (n + ' קווים על הדף') : 'אין גיאומטריה חופשית');
          }

          // After a line is rubbed out, or after they all come back. Says how
          // many are left AND how many are waiting to be put back, so the
          // "put them back" button is never a button whose effect is a mystery.
          function siteDropped(left, dropped){
            var t = left ? (left + ' קווים על הדף') : 'אין גיאומטריה חופשית';
            if(dropped) t += '  ·  ' + dropped + ' נמחקו';
            $('siteinfo').textContent = t;
            $('undrop').disabled = !dropped;
          }

          // Says where it got to, so an empty result is never a mystery.
          function siteReport(sel, r){
            var t = 'נבחרו ' + sel + ' · קווים במודל ' + r.edges +
                    ' · נוספו ' + r.lines + ' · על הדף ' + (r.total||r.lines);
            if(r.skipped) t += ' · ' + r.skipped + ' דולגו';
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
            $('stage').addEventListener('wheel',function(e){
              e.preventDefault();
              zoomAt(e.clientX, e.clientY, (ZOOM||1)*(e.deltaY<0?1.15:1/1.15));
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
            $('thand').onclick=function(){ setMode('hand'); };
            $('tdim').onclick=function(){ setMode('dim'); };
            $('tnote').onclick=function(){ setMode('note'); };
            $('terase').onclick=function(){ setMode('erase'); };
            $('tundo').onclick=function(){ undoMark(); };
            $('undrop').onclick=function(){ sketchup.restore_site_lines(); };
            for(var tk in TS_FIELDS){
              // change, not input: typing "1" on the way to "130" would send a
              // sheet at 25% and a full redraw with it.
              $(TS_FIELDS[tk]).onchange=function(){ sendTextScale(); };
            }
            $('tsReset').onclick=function(){ resetTextScale(); };

            $('txsize').onchange=function(){ sendTextMark(); };
            $('txsize').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); sendTextMark(); }
            };
            $('txbold').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              sendTextMark();
            };
            $('txitalic').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              sendTextMark();
            };
            // Back to whatever its group says, rather than back to 100 - the
            // group is the drawing's own standard and that is what "normal"
            // means for one label inside it.
            $('txreset').onclick=function(){
              if(!TSEL) return;
              sketchup.set_text_mark(JSON.stringify({key:TSEL.key, clear:true}));
              closeTextBar();
            };
            $('txdone').onclick=function(){ closeTextBar(); };
            $('txwhat').onmousedown=function(e){ dragTextBar(e); };
            $('txwhat').title='גרור כדי להזיז את החלונית';

            $('stripbtn').onclick=function(){ toggleStrip(); };
            $('logopick').onclick=function(){
              $('logoinfo').textContent='בוחר קובץ...'; sketchup.choose_logo();
            };
            $('logoclear').onclick=function(){ sketchup.clear_logo(); };

            // Once he has clicked a page in the list, up and down walk through
            // the set without going back to the mouse.
            $('pages').onkeydown=function(e){
              if(e.key==='ArrowDown'||e.key==='ArrowUp'){
                e.preventDefault();
                goToPage((STATE.active||0)+(e.key==='ArrowDown'?1:-1));
              } else if(e.key==='Home'){ e.preventDefault(); goToPage(0); }
              else if(e.key==='End'){ e.preventDefault(); goToPage((DOC.pages||[]).length-1); }
            };

            // Delete removes what is picked. Not while he is typing a note, and
            // not while the cursor is in the address or sheet-number boxes.
            window.addEventListener('keydown',function(e){
              var t=(e.target&&e.target.tagName)||'';
              if(t==='INPUT'||t==='SELECT'||t==='TEXTAREA') return;
              if(e.target && e.target.id==='pages') return;   // the list handles its own keys
              // Ctrl+Z. By the KEY's place on the keyboard as well as its
              // letter: with the keyboard in Hebrew that key types a zayin.
              if((e.ctrlKey||e.metaKey) && !e.shiftKey && !e.altKey &&
                 (e.code==='KeyZ'||e.key==='z'||e.key==='Z')){
                e.preventDefault();
                undoLast();
                return;
              }
              // The space bar picks the arrow up, the way it does in SketchUp.
              // Whatever tool he is in, one thump on the widest key on the
              // keyboard puts him back in select-and-drag - his words, and the
              // same habit the modelling window gives him.
              if(e.key===' '||e.code==='Space'||e.key==='Spacebar'){
                e.preventDefault();
                closeNote(); closeTextBar();
                setMode('hand');
                return;
              }
              // Nudging the picked dimension's number, for when the mouse is
              // not accurate enough (2026-08-19). The arrows move it the way
              // he sees it; what is STORED is along-and-across the line, so it
              // stays put when the dimension itself is moved later.
              // Shift = a whole text height a press, otherwise a quarter.
              var ar={ArrowLeft:[-1,0],ArrowRight:[1,0],
                      ArrowUp:[0,1],ArrowDown:[0,-1]}[e.key];
              if(ar && MODE==='hand' && SEL!==null && marks()[SEL] &&
                 marks()[SEL].t==='dim'){
                e.preventDefault();
                var st1=markTextH()*(e.shiftKey?1:0.25);
                moveMark(marks()[SEL],'text',ar[0]*st1,ar[1]*st1);
                push(); render(); showMarks();
                return;
              }
              // and the same for a picked LABEL - the plugin's own dimensions,
              // a room name, a tag
              if(ar && MODE==='hand' && SEL===null && TSEL){
                e.preventDefault();
                var st2=markTextH()*(e.shiftKey?1:0.25);
                nudgeText(ar[0]*st2, ar[1]*st2);
                return;
              }
              if(e.key==='Delete'||e.key==='Backspace'){
                if(SSEL.length){ e.preventDefault(); dropPicked(); }
                else if(SEL!==null){ e.preventDefault(); dropMark(); }
              } else if(e.key==='Escape'){
                e.preventDefault();
                escapeAll();
              }
            });

            $('dimoff').onchange=function(){ setDimOff(parseFloat(this.value)); };
            $('dimoff').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); this.blur(); }
            };

            $('notearrow').onclick=function(){
              STATE.note_arrow = (STATE.note_arrow===false);
              paintArrow();
              $('notetext').focus();
            };

            // One place knows how to shut this bar; see hideNoteBar above.
            function closeNote(){ hideNoteBar(); }
            function saveNote(){
              var t=$('notetext').value.trim();
              if(EDIT!==null && marks()[EDIT]){
                // changing one that is already there
                if(t){
                  marks()[EDIT].text=t;
                  marks()[EDIT].arrow=(STATE.note_arrow!==false);
                } else {
                  marks().splice(EDIT,1);       // emptied it = threw it away
                  SEL=null;
                }
                closeNote();
                push(); showMarks();
                return;
              }
              if(t&&PEND&&PEND2&&PEND3){
                marks().push(noteMark(PEND, PEND2, PEND3, t,
                                      STATE.note_arrow!==false,
                                      scaleFactor(STATE.scale)));
                SEL=marks().length-1;
              }
              closeNote();
              push(); render(); showMarks();
            }
            $('noteok').onclick=saveNote;
            $('notecancel').onclick=function(){ closeNote(); showMarks(); };
            $('notetext').onkeydown=function(e){
              if(e.key==='Enter') saveNote();
              else if(e.key==='Escape'){ closeNote(); showMarks(); }
            };

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

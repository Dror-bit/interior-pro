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
    # Loose lines can be DRAWN on the sheet: one line with two clicks, or a
    # running line that carries on from click to click (2026-10-07, see
    # addSiteLine in the page and add_site_line here). false = the two buttons
    # are not shown and Ruby takes no drawn line.
    USE_LINE_DRAW = true unless const_defined?(:USE_LINE_DRAW, false)
    # A SIDE of the drawing's box cuts the drawing: only that side moves and
    # the drawing stays where it is on the sheet (2026-10-07, see dragBox in
    # the page). false = a side moves the whole box, as it did the day the box
    # was built.
    USE_BOX_CROP = true unless const_defined?(:USE_BOX_CROP, false)
    # The second line of a note (the shoulder) goes where the third click is,
    # any way at all, and the words sit past its end (2026-10-08, "הערה לא
    # נמתחת לאן שאני רוצה בקו השני אלא רק לשני כיוונים"; see noteEnd in the
    # page). Within NOTE_SNAP_DEG of level or upright it locks there. false =
    # the shoulder is always level with the knee, as before.
    USE_NOTE_ANY_WAY = true unless const_defined?(:USE_NOTE_ANY_WAY, false)
    # Zooming out all the way - to "fits" - puts the sheet back in the middle
    # of the window, whole (2026-10-08, "כשאני עושה זום אווט עד הסוף הוא יחזור
    # למרכז את הדף באמצע"; see zoomAt in the page). false = the sheet keeps
    # shrinking towards the mouse down to "fits" and stays where that leaves
    # it, part of it off the top of the window, as before.
    USE_FIT_CENTRE = true unless const_defined?(:USE_FIT_CENTRE, false)
    # A new note's words are typed on the sheet, where they will stand - past
    # the end of the shoulder - and not in a bar at the top (2026-10-08, his
    # rule: "כל כיתוב... לא יפתח לו קופסא אלא הקופסא תהיה על הכיתוב עצמו";
    # see noteEditOpen in the page). false = the third click opens the note
    # bar at the top, as before.
    USE_NOTE_IN_PLACE = true unless const_defined?(:USE_NOTE_IN_PLACE, false)
    # The VISUALIZE by Dror logo is in the title block of every sheet from the
    # start, from a file that ships with the plugin (2026-10-07, "זה צריך להיות
    # הלוגו של VISUALIZE"); a logo he picks himself still wins. false = a model
    # with no logo picked prints the two words set in type, as before.
    USE_DEFAULT_LOGO = true unless const_defined?(:USE_DEFAULT_LOGO, false)
    DEFAULT_LOGO = 'assets/LOGO/visualize_by_dror.jpg' unless const_defined?(:DEFAULT_LOGO, false)
    # A set of loose lines too big to live on the model is kept in a file
    # beside the model instead of only in memory, so what he rubbed out and
    # what he drew are still there after SketchUp is closed (2026-10-07, see
    # site_file_later! and site_file_read). false = too big means memory only,
    # gone when SketchUp closes, as before.
    USE_SITE_FILE  = true unless const_defined?(:USE_SITE_FILE, false)
    SITE_FILE_DIR  = 'InteriorPro_sheet'  unless const_defined?(:SITE_FILE_DIR, false)
    SITE_FILE_EXT  = '.sheet_lines.json'  unless const_defined?(:SITE_FILE_EXT, false)
    SITE_FILE_WAIT = 2.0                  unless const_defined?(:SITE_FILE_WAIT, false)
    SITE_ID_ATTR   = 'sheet_site_id'      unless const_defined?(:SITE_ID_ATTR, false)

    class << self
      def show
        if @dialog
          begin; @dialog.close; rescue StandardError; end
          @dialog = nil
        end
        # Lines taken before the file beside the model existed - or before
        # this code was loaded - are written down now, not at the next change.
        site_file_ensure! if USE_SITE_FILE
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
              r[:kept]  = site_kept? ? 1 : 0
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

        # Drawing a line onto the sheet (2026-10-07).
        #
        # "הוספת קווים ע"י ציור" - and asked which way, he said both: one line
        # with two clicks, and a running line that carries on from click to
        # click. To Ruby they are the same thing, one line of two points at a
        # time; the only difference is where the window starts the next one.
        #
        # A drawn line is a loose line like any other. It goes on the END of
        # the same list, so shape number i is still line number i, and the
        # eraser, the select arrow, Delete and Ctrl+Z reach it with no code of
        # their own. NOTHING HERE TOUCHES THE MODEL.
        #
        # The quick road is the eraser's, the other way round: the window has
        # already put the line on its own sheet and says how many lines there
        # were before. If both sides agree, the list and the document Ruby is
        # holding gain the same shape and the answer is two numbers. If they do
        # not - or the sheet had no loose-line layer to add to - the sheet is
        # built and sent, which puts the window right.
        dlg.add_action_callback('add_site_line') do |_, json|
          begin
            t0  = Time.now
            r   = JSON.parse(json.to_s)
            pts = drawn_points(r['p'])
            if !USE_LINE_DRAW || pts.nil?
              why = USE_LINE_DRAW ? 'not a line' : 'switched off'
              puts "[Sheet] add_site_line: #{why} - nothing added, the sheet is sent again"
              @doc = nil
              push_all(dlg)
              erase_trace("draw: REFUSED - #{why}, sheet sent again")
            else
              lines  = site_lines
              before = lines.length
              quiet  = r['quiet'] == true && r['n'].to_i == before
              self.site_lines = lines + [pts]
              road = 'quick'
              unless quiet && add_to_document!(pts, before)
                road = quiet ? 'full (document out of step)' : 'full'
                @doc = nil
                push_all(dlg)
              end
              erase_trace("draw: 1 added, #{site_lines.length} on the sheet, #{road}, " \
                          "#{((Time.now - t0) * 1000).round} ms")
            end
            dlg.execute_script("siteDropped(#{JSON.generate(site_lines.length)}, " \
                               "#{JSON.generate(site_dropped.length)})")
          rescue StandardError => e
            puts "[Sheet] add_site_line: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        # Ctrl+Z on a drawn line: it comes off again.
        #
        # The window has already taken it off its own sheet and says which
        # number it had and what it was. Ruby believes it only if both sides
        # count the same number of lines and that number really holds that
        # line. Anything else: nothing is changed and the whole sheet is sent.
        #
        # It does NOT join the rubbed-out lines. Those are lines of the model's
        # own drawing waiting to be put back; a line he drew and took back was
        # never there, and "put back everything" must not bring it.
        dlg.add_action_callback('undo_site_add') do |_, json|
          begin
            t0     = Time.now
            r      = JSON.parse(json.to_s)
            items  = Array(r['items']).map { |it| [it['i'].to_i, drawn_points(it['p'])] }
            lines  = site_lines.dup
            before = lines.length
            good   = USE_SHEET_UNDO && !items.empty? && r['n'].to_i == before &&
                     items.map(&:first).uniq.length == items.length &&
                     items.all? { |i, pts| pts && i >= 0 && i < before && same_line?(lines[i], pts) }
            road = 'quick'
            if good
              gone = items.map(&:first).sort.reverse       # highest first
              gone.each { |i| lines.delete_at(i) }
              self.site_lines = lines
              unless drop_from_document!(gone, before)
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
            erase_trace("undo draw: #{good ? items.length : 0} off, #{site_lines.length} on the sheet, " \
                        "#{road}, #{((Time.now - t0) * 1000).round} ms")
          rescue StandardError => e
            puts "[Sheet] undo_site_add: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
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

        dlg.add_action_callback('drop_finish') do |_, json|
          begin
            list = Array(@drop_list)
            @drop_list = []
            # "onto the sheet that is open" (2026-10-07): the window says which
            # sheet. Nothing said = a sheet of its own for each, as always.
            on = begin
              json.to_s.empty? ? nil : JSON.parse(json.to_s)['on']
            rescue StandardError
              nil
            end
            add_images!(dlg, list, on)
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

        # An editor drawing put on a sheet of its own (2026-10-07, "לבחור איזה
        # שרטוט נכנס לאיזה דף"): {src: 'draft:0'}. The sheet comes after the
        # schedules and before the pictures, and opens.
        dlg.add_action_callback('add_drawing') do |_, json|
          begin
            r   = JSON.parse(json.to_s)
            src = r['src'].to_s
            names = InteriorPro::PlanCanvas.draft_names(Sketchup.active_model)
            unless src =~ /\Adraft:(\d+)\z/ && names.any? { |d| d['i'] == $1.to_i }
              dlg.execute_script("imageReport(0, #{JSON.generate('אין שרטוט כזה בעורך')})")
              next
            end
            st = load_state
            st['drawn'] = Array(st['drawn']) + [{ 'src' => src }]
            save_state(st)
            @doc = nil
            at = document.pages.index { |pg| pg.kind == 'drawing' && pg.ref == st['drawn'].length - 1 }
            if at
              st['active'] = at
              save_state(st)
            end
            erase_trace("drawing sheet: #{src} added, #{document.pages.length} pages")
            push_all(dlg)
          rescue StandardError => e
            puts "[Sheet] add_drawing: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
            dlg.execute_script("imageReport(0, #{JSON.generate(e.message)})")
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
                # and so do the boxes: the one this picture had goes with it,
                # the pictures added to its sheet go with the sheet, and the
                # ones after it shuffle down
                shift_pics!(st, i)
                st['page_order'] = shift_image_keys(st['page_order'], i) if st['page_order'].is_a?(Array)
              end
              st['images'] = list
            when 'drawing'
              # an editor drawing's sheet (2026-10-07): off the list; the ones
              # after it move down one, and everything named by them with them
              list = Array(st['drawn'])
              j = r['ref'].to_i
              if j >= 0 && j < list.length
                list.delete_at(j)
                skip = shift_image_keys(skip, j, 'drawing:')
                st['page_order'] = shift_image_keys(st['page_order'], j, 'drawing:') if st['page_order'].is_a?(Array)
                shift_pics!(st, j, 'drawing:')
              end
              st['drawn'] = list
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

        # Turning the drawing on its sheet (2026-10-07).
        #
        # Its own way in, for the same reason set_text_scale has one: the
        # writing lives on the MODEL canvas, and set_state answers with the
        # pages and the hand-drawn marks only. The lines turn in the window by
        # themselves; which writing turns with them and which stays level is
        # decided in PlanCanvas.turn_texts!, so the layers that carry writing
        # go back - all of them except the loose lines, which have none and
        # are a megabyte on his yard.
        dlg.add_action_callback('set_rotation') do |_, json|
          begin
            r  = JSON.parse(json.to_s)
            st = load_state
            st['rotation'] = InteriorPro::PlanCanvas.view_rotation('rotation' => r['rotation'])
            # a box that turns as a whole may have been made smaller or pushed
            # in by the turn (2026-10-07): the window sends where it left it
            st['view_box'] = (r['view_box'].is_a?(Array) ? r['view_box'] : nil) if r.key?('view_box')
            save_state(st)
            apply_state!(document, st)
            push_turned(dlg)
            pv = document.pages.map { |pg| pg.views.first }.compact.first
            erase_trace(format('turn: %s deg, box [%.3f, %.3f, %.3f, %.3f]%s', st['rotation'], pv.x, pv.y, pv.w, pv.h,
                               (pv.respond_to?(:box_turn) && pv.box_turn) ? ' (the box turns as a whole)' : '')) if pv
          rescue StandardError => e
            puts "[Sheet] set_rotation: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
          end
        end

        dlg.add_action_callback('set_state') do |_, json|
          begin
            t0 = Time.now
            st = JSON.parse(json.to_s)
            was_order = (load_state['page_order'] rescue nil)
            save_state(st)
            apply_state!(document, st)
            push_pages(dlg)
            if st.key?('page_order') && st['page_order'] != was_order
              erase_trace('page order: ' + document.pages.map { |pg| "#{page_key(pg)}=#{pg.sheet_number}" }.join('  '))
            end
            text_trace(st, t0)
            note_trace(st)
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
              # an elevation's number: its look is one setting for all of them (13:09, "2")
              # (two clicks on one of them, 13:26: 'one' = this number alone; its words and where
              # it was shoved are always its own)
              skey = r['one'] ? key : shared_text_key(key)
              if r['clear']
                m.delete(key)
                m.delete(skey) if skey != key
              elsif skey != key
                own = (m[key] || {}).dup
                if r.key?('text')
                  t = r['text'].to_s.strip
                  t.empty? ? own.delete('text') : (own['text'] = t)
                end
                own['dx'] = r['dx'].to_f if r.key?('dx')
                own['dy'] = r['dy'].to_f if r.key?('dy')
                own.empty? ? m.delete(key) : (m[key] = own)
                cur = (m[skey] || {}).dup
                cur['pct'] = r['pct'].to_f if r.key?('pct')
                %w[bold italic underline].each { |k| cur[k] = !!r[k] if r.key?(k) }
                if r.key?('font')
                  fo = r['font'].to_s.strip
                  (fo.empty? || fo.length > 40) ? cur.delete('font') : (cur['font'] = fo)
                end
                if r.key?('color')
                  col = r['color'].to_s.downcase
                  (col =~ /\A#[0-9a-f]{6}\z/ && col != '#000000') ? (cur['color'] = col) : cur.delete('color')
                end
                m[skey] = cur unless cur.empty? && !m.key?(skey)
              else
                cur = (m[key] || {}).dup
                cur['pct']    = r['pct'].to_f if r.key?('pct')
                cur['bold']   = !!r['bold']   if r.key?('bold')
                cur['italic'] = !!r['italic'] if r.key?('italic')
                cur['underline'] = !!r['underline'] if r.key?('underline')
                # a lettering of its own (2026-10-07); emptied = the drawing's own
                if r.key?('font')
                  fo = r['font'].to_s.strip
                  (fo.empty? || fo.length > 40) ? cur.delete('font') : (cur['font'] = fo)
                end
                if r.key?('color')
                  col = r['color'].to_s.downcase
                  (col =~ /\A#[0-9a-f]{6}\z/ && col != '#000000') ? (cur['color'] = col) : cur.delete('color')
                end
                # his own words for the label (2026-10-07); emptied = the label's own
                if r.key?('text')
                  t = r['text'].to_s.strip
                  t.empty? ? cur.delete('text') : (cur['text'] = t)
                end
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
            site_file_flush! if USE_SITE_FILE
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

        # Closing the window does not wait for the two seconds: whatever is
        # still to be written beside the model is written now.
        dlg.set_on_closed { site_file_flush! } if USE_SITE_FILE && dlg.respond_to?(:set_on_closed)

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
            scale: st['scale'], address: job_name(st), marks: st['marks'],
            logo: logo_path(st),
            drawn: st['drawn'],
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
        doc.job_address = job_name(st) if st.key?('address')
        doc.date        = st['date'] if st.key?('date')
        InteriorPro::PlanCanvas.layout_pages!(doc, st)
        doc
      end

      # ---------------------------------------------------------------- push

      def push_all(dlg)
        d = document
        st = load_state
        text_seen!(st)
        payload = {
          doc: d.to_h,
          state: st.merge(window_origin(d, st))
                  .merge('site_count'   => site_lines.length,
                          'site_dropped' => site_dropped.length),
          page_sizes: InteriorPro::PlanDoc.page_size_names,
          scales: InteriorPro::PlanDoc.scale_labels,
          images: image_payload(st),
          logo: logo_payload(st),
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
          note_any: USE_NOTE_ANY_WAY,
          fit_centre: USE_FIT_CENTRE,
          note_in_place: USE_NOTE_IN_PLACE,
          undo: USE_SHEET_UNDO,
          line_pick: USE_LINE_PICK,
          line_draw: USE_LINE_DRAW,
          rotate: InteriorPro::PlanCanvas::USE_VIEW_ROTATION,
          pic_box: InteriorPro::PlanCanvas::USE_PIC_BOX,
          pics: pic_payload(st),
          # writing in boxes of its own is handled by a picture's handles, so
          # it needs those switched on too
          text_box: InteriorPro::PlanCanvas::USE_TEXT_BOX && InteriorPro::PlanCanvas::USE_PIC_BOX,
          text_rules: text_rules_for_window,
          text_words: InteriorPro::PlanCanvas::USE_TEXT_WORDS,
          text_style: InteriorPro::PlanCanvas::USE_TEXT_STYLE,
          page_order: InteriorPro::PlanCanvas::USE_PAGE_ORDER,
          drawn: InteriorPro::PlanCanvas::USE_DRAWN_SHEETS,
          drafts: (InteriorPro::PlanCanvas::USE_DRAWN_SHEETS ? InteriorPro::PlanCanvas.draft_names(Sketchup.active_model) : []),
          text_font: InteriorPro::PlanCanvas::USE_TEXT_FONT,
          view_box: InteriorPro::PlanCanvas::USE_VIEW_BOX,
          box_crop: USE_BOX_CROP,
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

      # After the drawing is turned: the pages, and every layer of the plan
      # except the loose lines. See set_rotation.
      def push_turned(dlg)
        d    = document
        lays = d.canvas('MODEL').layers
                .reject { |l| l.name == InteriorPro::PlanGeometry::LAYER }
        dlg.execute_script("applyLayers(#{JSON.generate(d.pages.map(&:to_h))}, " \
                           "#{JSON.generate(lays.map(&:to_h))})")
      rescue StandardError => e
        puts "[Sheet] push_turned: #{e.class}: #{e.message}\n  " + Array(e.backtrace).first(4).join("\n  ")
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
        return "image:#{pg.ref}" if k == 'image'
        return "drawing:#{pg.ref}" if k == 'drawing'     # an editor drawing on a sheet (2026-10-07)
        k
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
      # (prefix: 'image:' for a picture sheet, 'drawing:' for an editor drawing's - 2026-10-07)
      def shift_image_keys(keys, removed, prefix = 'image:')
        Array(keys).each_with_object([]) do |k, out|
          unless k.to_s.start_with?(prefix)
            out << k
            next
          end
          n = k.to_s.split(':', 2).last.to_i
          next if n == removed
          out << "#{prefix}#{n > removed ? n - 1 : n}"
        end
      end

      # Picture sheet number `removed` has just been thrown away (2026-10-07).
      # Its own box is forgotten, the pictures that were added to it go with
      # it, and everything that named a later picture sheet moves down one -
      # the same shuffle shift_image_keys does for the ticks.
      def shift_pics!(st, removed, prefix = 'image:')
        geo = st['image_geo']
        if geo.is_a?(Hash) && prefix == 'image:'
          out = {}
          geo.each do |k, v|
            n = k.to_s.to_i
            next if n == removed
            out[(n > removed ? n - 1 : n).to_s] = v
          end
          st['image_geo'] = out
        end
        # the pictures added to a sheet, and the writing put on one, the same way
        %w[pics texts].each do |list|
          rows = st[list]
          next unless rows.is_a?(Array)
          st[list] = rows.each_with_object([]) do |pc, keep|
            next unless pc.is_a?(Hash)
            on = pc['on'].to_s
            if on.start_with?(prefix)
              n = on.split(':', 2).last.to_i
              next if n == removed
              pc = pc.merge('on' => "#{prefix}#{n > removed ? n - 1 : n}")
            end
            keep << pc
          end
        end
        st
      end

      # ------------------------------------------ writing in boxes: the trace
      #
      # One line in sheet_erase_trace.txt every time the writing he put on the
      # sheets changes: what changed, where Ruby laid it, how long the answer
      # took. Read it instead of asking him how it went - the boxes of the
      # drawing and of the pictures left no trace at all and all that could be
      # said about them was what he said.
      def text_rows(st)
        Array(st['texts']).select { |t| t.is_a?(Hash) }
      end

      # what the writing was when the window was last sent everything
      def text_seen!(st)
        @texts_sig = JSON.generate(text_rows(st))
      rescue StandardError
        @texts_sig = nil
      end

      # A line in the trace for every change to a hand-drawn note (2026-10-08):
      # added, taken off, its words changed, or moved. Read it before saying
      # that changing a note's words works on his machine.
      def note_trace(st)
        now = Array(st['marks']).select { |m| (m['t'] || m[:t]).to_s == 'note' }
                                .map { |m| %w[text x y kx ky lx ly arrow].map { |k| m[k] } }
        sig = JSON.generate(now)
        was = @notes_sig
        @notes_sig = sig
        return if was.nil? || was == sig
        old = JSON.parse(was) rescue []
        what =
          if now.length > old.length
            "#{now.length - old.length} added: '#{now.last[0]}'"
          elsif now.length < old.length
            "#{old.length - now.length} taken off"
          else
            at = (0...now.length).find { |k| now[k] != old[k] }
            a = old[at] || []
            b = now[at] || []
            if a[0] != b[0]
              "words of note #{at}: '#{a[0]}' -> '#{b[0]}'"
            elsif a[7] != b[7]
              "note #{at}: arrow #{b[7] == false ? 'off' : 'on'}"
            else
              "note #{at} moved"
            end
          end
        erase_trace("note: #{what}; #{now.length} on the sheet")
      rescue StandardError => e
        puts "[Sheet] note_trace: #{e.class}: #{e.message}"
      end

      def text_trace(st, t0)
        now = text_rows(st)
        sig = JSON.generate(now)
        was = @texts_sig
        @texts_sig = sig
        return if was.nil? || was == sig
        old = begin
          JSON.parse(was)
        rescue StandardError
          []
        end
        at = nil
        what =
          if now.length > old.length
            at = now.length - 1
            "#{now.length - old.length} added"
          elsif now.length < old.length
            "#{old.length - now.length} taken off"
          else
            at = (0...now.length).find { |k| now[k] != old[k] }
            a = old[at] || {}
            b = now[at] || {}
            kinds = []
            kinds << 'words'  if a['text'] != b['text']
            kinds << 'size'   if a['pt'] != b['pt']
            kinds << 'turned' if a['rot'].to_f != b['rot'].to_f
            kinds << 'style'  if %w[bold italic underline color].any? { |k| a[k] != b[k] }
            kinds << 'box'    if a['box'] != b['box']
            "one changed (#{kinds.join(', ')})"
          end
        laid  = @doc ? @doc.pages.flat_map { |pg| Array(pg.text_boxes) } : []
        where = ''
        if at
          en = laid.find { |e| e[:pic] == "t:#{at}" }
          where = en ? format(', laid at [%.2f, %.2f, %.2f, %.2f] %.1f pt turned %.1f, %d lines',
                              en[:x], en[:y], en[:w], en[:h], en[:pt], en[:rot], en[:lines].length)
                     : ', NOT ON ANY SHEET'
        end
        erase_trace("text box: #{what}#{where}; #{now.length} saved, #{laid.length} on the sheets, " \
                    "#{((Time.now - t0) * 1000).round} ms")
      rescue StandardError => e
        puts "[Sheet] text_trace: #{e.class}: #{e.message}"
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

      # What the window sent as a drawn line, checked: exactly two points, four
      # real numbers, not both in the same place. Rounded to a hundredth of an
      # inch, the way PlanGeometry.snapshot writes every other loose line.
      # nil = not a line.
      def drawn_points(raw)
        return nil unless raw.is_a?(Array) && raw.length == 2
        pts = []
        raw.each do |q|
          return nil unless q.is_a?(Array) && q.length >= 2 && q[0].is_a?(Numeric) && q[1].is_a?(Numeric)
          x = q[0].to_f
          y = q[1].to_f
          return nil unless x.finite? && y.finite?
          pts << [x.round(2), y.round(2)]
        end
        return nil if pts[0] == pts[1]
        pts
      end

      # Is this line of the list the two points the window says it is?
      def same_line?(line, pts)
        return false unless line.is_a?(Array) && line.length == 2
        line.each_with_index.all? do |q, k|
          q.is_a?(Array) && (q[0].to_f - pts[k][0]).abs < 0.011 && (q[1].to_f - pts[k][1]).abs < 0.011
        end
      rescue StandardError
        false
      end

      # A drawn line goes onto the END of the loose lines in the document Ruby
      # is holding, written the way PlanGeometry.build! writes every one of
      # them, so the document does not have to be built again. before = how
      # many lines there were. false = could not, build it again.
      def add_to_document!(pts, before)
        return true if @doc.nil?        # nothing built yet; the next build reads the list
        cv  = @doc.canvas('MODEL')
        lay = cv.layers.find { |l| l.name == InteriorPro::PlanGeometry::LAYER }
        return false unless lay && lay.shapes.length == before
        lay.polyline(pts, weight: 0.010)
        true
      rescue StandardError => e
        puts "[Sheet] add_to_document!: #{e.class}: #{e.message}"
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
          # Pictures in boxes of their own (2026-10-07, PlanCanvas.place_pictures!):
          # the box of a picture that owns a sheet, by its place in 'images',
          # and the pictures added to a sheet that was already there. Both
          # empty is every model made before this.
          'image_geo' => {}, 'pics' => [],
          # Writing in boxes of its own, on any sheet (2026-10-07,
          # PlanCanvas.place_texts!). Empty is every model made before this.
          'texts' => [],
          # How far the drawing is turned on its sheet, in degrees, anticlockwise
          # (2026-10-07). 0 is every drawing made before this existed.
          'rotation' => 0,
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
          # The order of the sheets, dragged in the page list (2026-10-07): page
          # keys, like pdf_skip. Empty = the old order (plan, schedules, pictures).
          'page_order' => [],
          # The editor's drawings on sheets of their own (2026-10-07): [{'src' => 'draft:0'}]
          'drawn' => [],
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

      # The key a label's look is kept under: its own, or - for the numbers of an
      # elevation's dimensions - the one key they all share (PlanCanvas::ELEV_SHARED_KEY).
      def shared_text_key(key)
        pc = InteriorPro::PlanCanvas
        k = key.to_s
        return k unless pc.const_defined?(:ELEV_DIM_LAYER) && k.start_with?("#{pc::ELEV_DIM_LAYER}|")
        pc::ELEV_SHARED_KEY
      end

      # Settings that are remembered but have no default: where the plan sits,
      # which sheet is open, the zoom.
      def extra_state_keys
        # view_box / scale_f: the drawing's box and a size set by hand (2026-10-07).
        # No default on purpose - nil is "the whole sheet, the scale from the list".
        # image_titles (2026-10-08): a name of its own for a picture, by path - the elevations.
        # image_dims (2026-10-08): the automatic dimensions of an elevation, by path.
        %w[origin_x origin_y date active zoom view_box scale_f image_titles image_dims]
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
        site_other_model_check! if USE_SITE_FILE
        return @site_lines if @site_lines
        raw = begin
          Sketchup.active_model.get_attribute(ATTR_DICT, SITE_ATTR)
        rescue StandardError
          nil
        end
        @site_lines = if raw
                        (JSON.parse(raw.to_s) rescue [])
                      else
                        (USE_SITE_FILE && site_file_read) || []
                      end
        site_own! if USE_SITE_FILE
        @site_lines
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
        if USE_SITE_FILE
          site_own!
          # too big for the model: beside the model. Small enough: the model
          # holds it, and a file left from when it was big is taken away.
          site_file_later!(@site_saved ? nil : json)
        end
        @site_lines
      end

      # ------------------------------------- the lines, beside the model
      #
      # 2026-10-07, 6 Bronco Ln. A yard of 14,710 lines is 1.3 MB, the model
      # takes 60 KB, and so the whole list lived in memory: he spent a day
      # rubbing two thousand lines out and drawing new ones, and all of it
      # would have gone the moment SketchUp closed. The window even said so
      # ("יישאר עד סגירת סקצ'אפ") - which is an apology, not a feature.
      #
      # So a list too big for the model is written to
      #     <the model's folder>/InteriorPro_sheet/<the model's name>.sheet_lines.json
      # and read back when the sheet opens and the model holds no list.
      #
      # - NOT on every sweep of the eraser. The newest list waits two seconds
      #   and is written once, so twenty sweeps in a row cost one write and a
      #   sweep stays as quick as it was. Closing the window or exporting the
      #   PDF writes at once.
      # - Written to one side and then moved into place, so a crash in the
      #   middle leaves the old file whole.
      # - A model that has never been saved has no folder: memory only, as
      #   before, and the trace says so once.
      # - The model carries a small mark (SITE_ID_ATTR) and so does the file.
      #   That is how a model saved under a NEW NAME still finds its lines,
      #   and how the lines of one model are never shown on - or written
      #   beside - another model opened in the same SketchUp.
      # Every write and every read leaves a line in sheet_erase_trace.txt.

      def site_model_path
        Sketchup.active_model.path.to_s.tr('\\', '/')
      rescue StandardError
        ''
      end

      # nil = the model has never been saved, there is nowhere to write
      def site_file_path(model_path = site_model_path)
        return nil if model_path.to_s.empty?
        File.join(File.dirname(model_path), SITE_FILE_DIR,
                  "#{File.basename(model_path, '.*')}#{SITE_FILE_EXT}")
      end

      def site_token
        t = Sketchup.active_model.get_attribute(ATTR_DICT, SITE_ID_ATTR).to_s
        t.empty? ? nil : t
      rescue StandardError
        nil
      end

      # Will these lines still be there after SketchUp is closed?
      def site_kept?
        return true if @site_saved
        USE_SITE_FILE && !site_file_path.nil?
      end

      # These lines belong to the model that is open now. A model with lines
      # gets its mark here if it has none (or lost it to an undo).
      def site_own!
        tok = site_token
        if tok.nil? && @site_lines && !@site_lines.empty?
          tok = @site_owner || format('%08x%08x', rand(2**32), rand(2**32))
          Sketchup.active_model.set_attribute(ATTR_DICT, SITE_ID_ATTR, tok)
        end
        @site_owner      = tok
        @site_owner_path = site_model_path
      rescue StandardError => e
        puts "[Sheet] site_own!: #{e.class}: #{e.message}"
      end

      # Is the list in memory another model's? Then it is let go, and this
      # model's own is read. Careful by design: a new path alone is "Save As",
      # a missing mark alone is an undo - neither loses a line. Only a
      # DIFFERENT mark, or no mark AND another path, is another model.
      def site_other_model_check!
        return if @site_lines.nil?
        if @site_owner.nil? && @site_owner_path.nil?
          site_own!            # taken before this code was loaded: they are this model's
          return
        end
        tok   = site_token
        other = if tok && @site_owner then tok != @site_owner
                else site_model_path != @site_owner_path.to_s
                end
        unless other
          site_own!
          return
        end
        site_file_flush!       # what is waiting belongs to the model that was open
        puts '[Sheet] another model is open: the loose lines of the last one are let go'
        @site_lines      = nil
        @site_dropped    = []
        @site_saved      = nil
        @site_owner      = nil
        @site_owner_path = nil
        @doc             = nil
      rescue StandardError => e
        puts "[Sheet] site_other_model_check!: #{e.class}: #{e.message}"
      end

      # The newest list is to be written (json) or its file taken away (nil) -
      # in two seconds, once, however many times this is called before then.
      def site_file_later!(json)
        path = site_file_path
        if path.nil?
          if json && !@site_file_warned
            @site_file_warned = true
            erase_trace('lines file: the model has never been saved, so there is nowhere to keep ' \
                        "#{@site_lines.length} lines - they stay until SketchUp is closed")
          end
          return
        end
        # something waiting for ANOTHER model's file goes first, to its own file
        site_file_flush! if @site_file_job && @site_file_job[:path] != path
        if json.nil? && !File.file?(path)
          @site_file_job = nil               # nothing to write and nothing to take away
          return
        end
        @site_file_job = { path: path, count: @site_lines.length,
                           body: json && site_file_body(json) }
        @site_file_timer ||= UI.start_timer(SITE_FILE_WAIT, false) { site_file_flush! }
      rescue StandardError => e
        puts "[Sheet] site_file_later!: #{e.class}: #{e.message}"
      end

      # The file is the list Ruby already made for measuring it, with a small
      # head in front. The mark comes FIRST so it can be read without reading
      # a megabyte.
      def site_file_body(json)
        m = site_model_path
        "{\"id\":#{JSON.generate(@site_owner.to_s)},\"model\":#{JSON.generate(File.basename(m))}," \
        "\"saved\":#{JSON.generate(Time.now.strftime('%Y-%m-%d %H:%M:%S'))}," \
        "\"count\":#{@site_lines.length},\"lines\":#{json}}"
      end

      # Write what is waiting, now. true = written (or taken away).
      def site_file_flush!
        t = @site_file_timer
        @site_file_timer = nil
        begin
          UI.stop_timer(t) if t
        rescue StandardError
          nil
        end
        job = @site_file_job
        @site_file_job = nil
        return false unless job
        t0   = Time.now
        path = job[:path]
        name = File.basename(path)
        if job[:body].nil?
          if File.file?(path)
            File.delete(path)
            erase_trace("lines file: the list fits on the model again, #{name} taken away")
          end
          return true
        end
        dir = File.dirname(path)
        Dir.mkdir(dir) unless File.directory?(dir)
        tmp = "#{path}.tmp"
        File.binwrite(tmp, job[:body])
        begin
          File.rename(tmp, path)
        rescue StandardError
          # held open by something else for a moment: write over it instead
          File.binwrite(path, job[:body])
          File.delete(tmp) if File.file?(tmp)
        end
        size  = File.size(path)
        check = ''
        if @site_file_checked != path
          # the first time in this folder, read it back and count - before he
          # is told it is safe to close SketchUp
          back = site_file_parse(path)
          if back && back[:lines].length == job[:count]
            @site_file_checked = path
            check = ', read back and counted'
          else
            check = ', READ BACK DOES NOT MATCH'
          end
        end
        erase_trace("lines file: #{job[:count]} lines, #{(size / 1024.0).round} KB, " \
                    "#{((Time.now - t0) * 1000).round} ms#{check} -> #{name}")
        true
      rescue StandardError => e
        puts "[Sheet] site_file_flush!: #{e.class}: #{e.message}"
        erase_trace("lines file: FAILED - #{e.class}: #{e.message}")
        false
      end

      # { id:, lines: } out of a file, or nil if it is not one of ours.
      def site_file_parse(path)
        h = JSON.parse(File.read(path, mode: 'rb').force_encoding('UTF-8'))
        lines = h.is_a?(Hash) ? h['lines'] : nil
        return nil unless lines.is_a?(Array) && lines.all? { |l| l.is_a?(Array) }
        { id: h['id'].to_s, lines: lines }
      rescue StandardError => e
        puts "[Sheet] site_file_parse: #{File.basename(path.to_s)}: #{e.class}: #{e.message}"
        nil
      end

      # The list for THIS model, from beside it. nil = there is none.
      def site_file_read
        path = site_file_path
        return nil unless path
        tok  = site_token
        from = nil
        got  = nil
        if File.file?(path)
          got  = site_file_parse(path)
          # a file with this model's name but another model's mark is not its list
          got  = nil if got && tok && !got[:id].empty? && got[:id] != tok
          from = path if got
        end
        if got.nil? && tok
          # Saved under a new name since the file was written: the file still
          # has the old name, and the mark inside it says whose it is.
          dir = File.dirname(path)
          if File.directory?(dir)
            mine = Dir.children(dir).select { |n| n.end_with?(SITE_FILE_EXT) }
                      .map { |n| File.join(dir, n) }
                      .select { |f| File.open(f, 'rb') { |io| io.read(200).to_s } =~ /"id":"#{Regexp.escape(tok)}"/ }
                      .max_by { |f| File.mtime(f) }
            got  = mine && site_file_parse(mine)
            from = mine if got
          end
        end
        return nil unless got
        @site_saved        = false
        @site_file_checked = path if from == path
        @site_owner        = got[:id] if tok.nil? && !got[:id].empty?   # the model lost its mark; the file kept it
        erase_trace("lines file: #{got[:lines].length} lines read back from #{File.basename(from)}")
        got[:lines]
      rescue StandardError => e
        puts "[Sheet] site_file_read: #{e.class}: #{e.message}"
        nil
      end

      # When the window opens: a big list that is in memory and has no file
      # yet gets one now. That is the list taken before this code existed.
      def site_file_ensure!
        lines = site_lines
        return if lines.empty? || @site_file_job
        path = site_file_path
        return if path.nil? || File.file?(path)
        return unless Sketchup.active_model.get_attribute(ATTR_DICT, SITE_ATTR).nil?
        site_own!
        site_file_later!(JSON.generate(lines))
        site_file_flush!
      rescue StandardError => e
        puts "[Sheet] site_file_ensure!: #{e.class}: #{e.message}"
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

      # on = the sheet they go ONTO ('plan', 'schedules', 'image:2'), each in a
      # box of its own. nil = a sheet of its own for each, as always.
      def add_images!(dlg, paths, on = nil)
        wanted = Array(paths).map { |p| p.to_s.tr('\\', '/') }.reject(&:empty?)
        if wanted.empty?
          dlg.execute_script('imageReport(0, null)')
          return
        end
        st = load_state
        on = nil unless InteriorPro::PlanCanvas::USE_PIC_BOX &&
                        on.to_s =~ /\A(plan|schedules|image:\d+)\z/
        if on
          st['pics'] = Array(st['pics']) + wanted.map { |p| { 'path' => p, 'on' => on.to_s } }
        else
          st['images'] = Array(st['images']) + wanted
        end
        save_state(st)
        @doc = nil
        push_all(dlg)
        dlg.execute_script("imageReport(#{wanted.length}, null)")
      end

      # The logo that ships with the plugin - the VISUALIZE by Dror picture -
      # or nil when it is switched off or the file is not there (then the
      # title block sets the two words in type, as it always did).
      def default_logo
        return nil unless USE_DEFAULT_LOGO
        path = File.join(plugin_dir, DEFAULT_LOGO)
        File.file?(path) ? path : nil
      end

      # What the title block prints: the logo he picked, else the built-in one.
      def logo_path(st)
        st['logo'].to_s.empty? ? default_logo : st['logo']
      end

      # What the window is told about it. 'builtin' => true is the shipped
      # one: the window shows it and puts away the "back to VISUALIZE" button,
      # because there is nothing to go back to.
      def logo_payload(st)
        if st['logo'].to_s.empty?
          d = default_logo
          return nil unless d
          { 'path' => d, 'name' => 'VISUALIZE by Dror', 'url' => file_url(d),
            'there' => true, 'builtin' => true }
        else
          { 'path' => st['logo'], 'name' => File.basename(st['logo'].to_s),
            'url' => file_url(st['logo']), 'there' => File.file?(st['logo'].to_s) }
        end
      end

      # The rules of writing, with the letterings' files as addresses the
      # window can load (@font-face), so the sheet shows the very fonts the
      # PDF prints with (2026-10-08).
      def text_rules_for_window
        r = InteriorPro::PlanCanvas.text_rules
        if r['fonts'].is_a?(Hash)
          r['fonts'].each_value do |t|
            t['url']  = file_url(t['path'])  if t['path']
            t['urlb'] = file_url(t['pathb']) if t['pathb']
          end
        end
        r
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

      # An address for every picture that was added ONTO a sheet. The owners
      # of the picture sheets are in image_payload, as they always were.
      def pic_payload(st)
        Array(st['pics']).select { |pc| pc.is_a?(Hash) && !pc['path'].to_s.empty? }.map do |pc|
          p = pc['path'].to_s
          { 'path' => p, 'name' => File.basename(p), 'url' => file_url(p), 'there' => File.file?(p) }
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

      # The job in the title block (2026-10-08, "שם הפרויקט שבו הוא נשמר יהיה
      # הכותרת כי זה בדרך כלל הכתובת"): what he typed in the address box, and
      # when that is empty the name the model is saved under - which is the
      # address, the way he names them. '' until the model has been saved.
      def model_name
        p = Sketchup.active_model.path.to_s.tr('\\', '/')
        p.empty? ? '' : File.basename(p, '.*').strip
      rescue StandardError
        ''
      end

      def job_name(st)
        a = (st['address'] || st[:address]).to_s.strip
        a.empty? ? model_name : a
      end

      # The PDF is named after the job - the address (2026-10-08, "השם של
      # הקובץ צריך להיות שם הפרויקט (הכתובת)"); the sheet number only when
      # there is no job name at all. Only what Windows cannot take in a file
      # name is replaced: spaces, commas and Hebrew stay.
      def default_name(st)
        base = job_name(st)
        base = st['sheet_number'].to_s.strip if base.empty?
        base = base.gsub(%r{[\\/:*?"<>|]}, '_').sub(/[\s.]+\z/, '').strip
        base = 'plan' if base.empty?
        "#{base}.pdf"
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
            .pg.drag { opacity:.45; }
            .pg.dropb { box-shadow:inset 0 3px 0 #ffd400; }
            .pg.dropa { box-shadow:inset 0 -3px 0 #ffd400; }
            .thumb.drag { opacity:.45; }
            .thumb.dropb .sheet { box-shadow:0 -6px 0 #ffd400; }
            .thumb.dropa .sheet { box-shadow:0 6px 0 #ffd400; }
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
            /* One label's own settings (2026-10-07): INSIDE the "גודל טקסט"
               box at the side, under the group sizes - one place, like Word:
               "אני לוחץ על טקסט מסוים ואז אני משנה את ההגדרות בחלון ההגדרות".
               It used to be a bar floating over the sheet. */
            /* the letterings, each name in its own letters (2026-10-08) */
            #txfontbox { position:relative; margin-top:6px; }
            #txfontbtn { width:100%; text-align:right; font-size:15px; padding:4px 8px; }
            #txfontmenu { display:none; position:absolute; right:0; left:0; top:100%; z-index:30;
                          background:#2a2a2a; border:1px solid #555; border-radius:4px;
                          box-shadow:0 4px 14px rgba(0,0,0,.5); }
            #txfontmenu.on { display:block; }
            #txfontmenu div { padding:6px 10px; cursor:pointer; font-size:17px; text-align:right;
                              border-bottom:1px solid #383838; color:#eee; }
            #txfontmenu div:last-child { border-bottom:none; }
            #txfontmenu div:hover { background:#3b5a86; }
            #txfontmenu div.on { background:#1f6feb; color:#fff; }
            #textbar { display:block; margin-top:0; padding-top:0;
                       border-top:none; opacity:.45; pointer-events:none; }
            /* always there, under the group sizes ("הגדרות הטקסט צריכות להיות
               פה"); it comes alive when a label is clicked */
            #textbar.on { opacity:1; pointer-events:auto; }
            /* the bar a box of writing is typed in (2026-10-07). FIXED, like the
               note bar - the day this rule went missing the bar sat in the
               flow at the top of #stage and squeezed the sheet to a thumbnail. */
            #tbbar { position:fixed; top:22px; left:50%;
                     transform:translateX(-50%); z-index:22; display:none;
                     background:#2b2b2b; border:1px solid #1f6feb;
                     border-radius:5px; padding:8px; gap:8px; width:470px;
                     box-shadow:0 6px 24px rgba(0,0,0,.5); }
            /* (2026-10-07, "אני לא רוצה שייפתח חלון עריכה... אני רוצה שהחלון
               ייפתח שהוא הכיתוב עצמו", like LayOut) the bar stays in the page
               as the keeper of the words and the size, but it is not shown:
               the words are typed in #tbedit, laid over the box on the sheet. */
            #tbbar.on { display:none; }
            #tbedit { position:absolute; display:none; z-index:7; margin:0;
                      background:#fff; color:#000; border:1px solid #1f6feb;
                      outline:none; resize:none; overflow:hidden; white-space:pre-wrap;
                      word-break:normal; overflow-wrap:normal;
                      font-family:Helvetica,Arial,sans-serif; box-sizing:border-box;
                      transform-origin:50% 50%; }
            #tbedit.on { display:block; }
            #tbedit.one { white-space:nowrap; }
            #tbbar textarea { flex:1; min-height:74px; resize:vertical; padding:6px;
                              background:#1e1e1e; color:#eee; border:1px solid #555;
                              border-radius:3px; font:14px/1.35 Segoe UI, Arial, sans-serif; }
            #tbbar .col { width:118px; flex:none; display:flex; flex-direction:column; gap:6px; }
            #tbbar .col .row { align-items:center; }
            #tbbar .col .row span { font-size:12px; color:#ccc; flex:none; }
            #tbbar .col input { text-align:center; }
            #tbbar button { margin:0; padding:6px 10px; }
            #tbbar .hint { margin:0; }
            #textbar .what { color:#cfe4ff; font-size:12px; white-space:nowrap;
                             overflow:hidden; text-overflow:ellipsis;
                             padding:2px 4px; direction:ltr; text-align:left; }
            #textbar .row button.tool { padding:5px 0; }
            #textbar input#txcolor { width:44px; flex:none; height:31px; padding:2px 3px;
                                     cursor:pointer; }
            #textbar input#txwords { width:100%; margin-top:6px; direction:auto; }
            #textbar .row button { width:auto; flex:1; margin-top:0; }
            /* The handle that turns the drawing (2026-10-07). An element of
               its own over the sheet, not a mark inside the drawing: it must
               never print, never reach a thumbnail, and never be counted as a
               line. It sits inside #stage, so it scrolls with the paper. */
            #rothandle { position:absolute; display:none; z-index:5;
                         width:24px; height:24px; margin:-12px 0 0 -12px; }
            #rothandle.on { display:block; }
            #rothandle svg { width:24px; height:24px; display:block; }
            /* The drawing's box (2026-10-07): a square on each corner to make
               it bigger or smaller, a grip and four thin strips along its
               sides to move it. Elements of their own over the sheet, for the
               same reasons the turning handle is. */
            .boxc { position:absolute; display:none; z-index:6; width:12px;
                    height:12px; margin:-6px 0 0 -6px; background:#fff;
                    border:2px solid #1f6feb; }
            .boxc.on { display:block; }
            .boxe { position:absolute; display:none; z-index:4; }
            .boxe.on { display:block; }
            /* a small bar in the middle of each side: this is where the box
               is cut. Drawn by the style sheet, so it is not an element. */
            .boxe::after { content:''; position:absolute; left:50%; top:50%;
                           background:#fff; border:2px solid #1f6feb;
                           border-radius:3px; }
            #boxe-n::after, #boxe-s::after { width:22px; height:6px; margin:-5px 0 0 -13px; }
            #boxe-w::after, #boxe-e::after { width:6px; height:22px; margin:-13px 0 0 -5px; }
            #boxmove { position:absolute; display:none; z-index:6; width:24px;
                       height:24px; margin:-12px 0 0 -12px; }
            #boxmove.on { display:block; }
            #boxmove svg { width:24px; height:24px; display:block; }
            #rotdeg { position:absolute; right:28px; top:3px; display:none;
                      font:700 14px Helvetica,Arial,sans-serif; color:#1f6feb;
                      background:rgba(255,255,255,.9); padding:0 4px;
                      border-radius:3px; white-space:nowrap; direction:ltr; }
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
                  <div id="drawadd" class="row" style="display:none;margin-top:6px">
                    <select id="drawsrc" style="flex:1"></select>
                    <button id="drawbtn" class="go2" style="width:auto;flex:none;padding:0 10px">הוסף דף</button>
                  </div>
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
                <h4><span class="ar">&#9656;</span>הגדרות טקסט<span class="tag" id="texttag"></span></h4>
                <div class="bd">
                  <!-- The four group sizes are KEPT (Ruby still honours them, and
                       the suites drive them) but not shown: "לא הבנתי בשביל מה
                       צריך את כל האחוזים האלו, תוריד אותם" (2026-10-07). -->
                  <div id="tsgroups" style="display:none">
                  <div class="tsrow"><span>מידות</span><input id="tsDims" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <div class="tsrow"><span>שמות חדרים</span><input id="tsRooms" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <div class="tsrow"><span>תגי דלת/חלון</span><input id="tsTags" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <div class="tsrow"><span>טבלאות</span><input id="tsTables" type="number" min="25" max="400" step="5"><span class="pc">%</span></div>
                  <button id="tsReset">חזור ל-100%</button>
                  </div>
                  <!-- the label he clicked on: its own size, weight, line,
                       colour and words. Shown while one is picked. -->
                  <div id="textbar">
                    <div id="txwhat" class="what"></div>
                    <div class="tsrow"><span>גודל</span><input id="txsize" type="number" min="4" max="400" step="1" title="גודל האותיות, בנקודות"><span class="pc" id="txunit">pt</span></div>
                    <div class="row" style="margin-top:6px">
                      <button id="txbold" class="tool" title="מודגש"><b>B</b></button>
                      <button id="txitalic" class="tool" title="נטוי"><i>I</i></button>
                      <button id="txunder" class="tool" title="קו תחתון"><u>U</u></button>
                      <input id="txcolor" type="color" value="#000000" title="צבע">
                    </div>
                    <div class="row" id="txnote" style="display:none;margin-top:6px">
                      <button id="txarrow" class="tool on" title="ראש חץ בקצה הקו">
                        <svg viewBox="0 0 24 24"><g class="s">
                          <rect x="12" y="3" width="9" height="7" rx="1"/>
                          <path d="M12 8 L4 19"/>
                          <path d="M4 19 L5.4 15.4 M4 19 L7.6 17.6"/>
                        </g></svg>
                      </button>
                    </div>
                    <div id="txfontbox" style="display:none">
                      <select id="txfont" style="display:none"></select>
                      <button id="txfontbtn" title="סוג כתב">כתב רגיל</button>
                      <div id="txfontmenu"></div>
                    </div>
                    <input id="txwords" placeholder="מה כתוב" title="מה כתוב במקום המספר. ריק = המספר האמיתי">
                    <div class="row" style="margin-top:6px">
                      <button id="txreset" title="חזרה להגדרות הקבוצה">אפס</button>
                      <button id="txdone">סיים</button>
                    </div>
                  </div>
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
                    <!-- A box of writing, anywhere on any sheet (2026-10-07). -->
                    <button id="ttext" class="tool" title="כיתוב: קופסה עם טקסט, בכל דף">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <rect x="3" y="4.5" width="18" height="15" rx="1.5" stroke-dasharray="3 2.2"/>
                        <path d="M8 9 L16 9 M12 9 L12 16"/>
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
                  <!-- Drawing loose lines onto the sheet (2026-10-07). He
                       asked for both: ONE line with two clicks, and a RUNNING
                       line that carries on from click to click. -->
                  <div class="row" id="tools2" style="margin-top:6px">
                    <button id="tline" class="tool" title="קו אחד: שני קליקים">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <path d="M6.2 17.8 L17.8 6.2"/>
                        <circle cx="5" cy="19" r="1.9"/>
                        <circle cx="19" cy="5" r="1.9"/>
                      </g></svg>
                    </button>
                    <button id="tchain" class="tool" title="קו רציף: כל קליק ממשיך מהקודם">
                      <svg viewBox="0 0 24 24"><g class="s">
                        <path d="M4.2 16.6 L8.2 8.4 M10 8.6 L14.2 15.4 M15.8 15.4 L19.8 7.4"/>
                        <circle cx="3.5" cy="18" r="1.6"/>
                        <circle cx="9" cy="7" r="1.6"/>
                        <circle cx="15" cy="17" r="1.6"/>
                        <circle cx="20.5" cy="6" r="1.6"/>
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
                  <div id="markinfo" class="hint"></div>
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
                  <!-- Still ONE way in (2026-10-07). This only says WHERE the
                       pictures land: a sheet of its own for each, as always,
                       or onto the sheet that is open - beside the drawing, or
                       beside another picture. -->
                  <label class="chk" id="pichererow" style="margin-top:6px">
                    <input type="checkbox" id="pichere"> להוסיף לדף הפתוח, לא דף חדש לכל תמונה
                  </label>
                  <div id="imginfo" class="hint"></div>
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
                  <img id="logoshow" alt="">
                  <button id="logopick" class="go2">בחר קובץ לוגו</button>
                  <button id="logoclear">חזור ל-VISUALIZE by Dror</button>
                  <div id="logoinfo" class="hint"></div>
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
              <div id="tbbar">
                <textarea id="tbtext" dir="auto" maxlength="4000" placeholder="מה לכתוב כאן?"></textarea>
                <div class="col">
                  <div class="row"><span>גודל</span><input id="tbsize" type="number" min="4" max="400" step="1" title="גודל האותיות, בנקודות"></div>
                  <button id="tbok" class="go">הוסף</button>
                  <button id="tbcancel">ביטול</button>
                </div>
              </div>
              <div id="sheetWrap"></div>
              <div id="rothandle" title="סובב את השרטוט">
                <svg viewBox="-12 -12 24 24"><g fill="none" stroke-linecap="round" stroke-linejoin="round">
                  <circle r="11" fill="#fff" stroke="#1f6feb" stroke-width="1.2"/>
                  <path d="M-5.2 3.4 A6.2 6.2 0 1 1 3.4 5.2" stroke="#1f6feb" stroke-width="1.8"/>
                  <path d="M3.4 5.2 L3.9 1.4 M3.4 5.2 L7.1 4.7" stroke="#1f6feb" stroke-width="1.8"/>
                </g></svg>
                <span id="rotdeg"></span>
              </div>
              <div id="boxmove" title="הזז את השרטוט על הדף">
                <svg viewBox="-12 -12 24 24"><g fill="none" stroke-linecap="round" stroke-linejoin="round">
                  <circle r="11" fill="#fff" stroke="#1f6feb" stroke-width="1.2"/>
                  <path d="M0 -7 L0 7 M-7 0 L7 0" stroke="#1f6feb" stroke-width="1.8"/>
                  <path d="M0 -7 L-2.4 -4.6 M0 -7 L2.4 -4.6 M0 7 L-2.4 4.6 M0 7 L2.4 4.6 M-7 0 L-4.6 -2.4 M-7 0 L-4.6 2.4 M7 0 L4.6 -2.4 M7 0 L4.6 2.4" stroke="#1f6feb" stroke-width="1.8"/>
                </g></svg>
              </div>
              <textarea id="tbedit" dir="auto" maxlength="4000" spellcheck="false"></textarea>
              <div id="boxc-nw" class="boxc"></div>
              <div id="boxc-ne" class="boxc"></div>
              <div id="boxc-sw" class="boxc"></div>
              <div id="boxc-se" class="boxc"></div>
              <div id="boxe-n" class="boxe"></div>
              <div id="boxe-s" class="boxe"></div>
              <div id="boxe-w" class="boxe"></div>
              <div id="boxe-e" class="boxe"></div>
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
          var MODE='hand';            // hand | dim | note | erase | line | chain
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

          // ---- turning the drawing on its sheet (2026-10-07) ---------------
          //
          // "אני רוצה שתהיה אפשרות לסובב את השרטוט... כמו בתמונה שיש סימון על
          // הפינה למטה של סיבוב." A handle sits by the bottom corner of the
          // drawing's frame; he takes hold of it and drags, and the drawing
          // turns about the middle of the frame.
          //
          // STATE.rotation is the angle, in degrees, anticlockwise. ALL of the
          // turning is in two places: toPaper (the house onto the paper) and
          // atMouse (the mouse back into the house). Every tool in this window
          // goes through one of those two, so the eraser, the select arrow,
          // the dimensions and the drawing tools all work on a turned sheet
          // with nothing of their own to know.
          //
          // The WRITING is Ruby's: which of it turns with the drawing and
          // which stays level is decided in PlanCanvas.turn_texts!, and the
          // window only adds the sheet's angle to each piece's own. So while
          // he is dragging, the writing rides round with the drawing, and when
          // he lets go Ruby sends it back the way it prints (set_rotation).
          //
          // The iron law: Escape in the middle puts it back as it was; Ctrl+Z
          // takes the last turn back; the zoom and the place do not change;
          // near a quarter turn it locks onto the quarter turn.
          var ROTON=true;      // told by Ruby
          var ROT=null;        // {a0, r0, moved} while the handle is held
          var VROT=0;          // the turn of the sheet being drawn right now
          var ROT_SNAP=4;      // degrees either side of a quarter turn

          // Does the drawing's box turn as a whole - frame, clip and handles
          // with the lines (2026-10-07, stage 5)? Ruby says so on the view.
          function boxTurns(){
            var v=planView();
            return !!(ROTON && v && v.box_turn);
          }

          // The drawing's box as a turned rectangle on the paper, like picRect
          // for a picture: {x, y, w, h, rot}. rot is 0 unless the box turns.
          function viewRect(){
            var v=planView(); if(!v) return null;
            return {x:v.x, y:v.y, w:v.w, h:v.h, rot:(boxTurns() ? viewTurn().deg : 0), crop:[0,0,0,0]};
          }

          function viewTurn(){
            var d=(ROTON && STATE && +STATE.rotation) || 0;
            if(!d) return {deg:0, c:1, s:0};
            var r=d*Math.PI/180;
            return {deg:d, c:Math.cos(r), s:Math.sin(r)};
          }

          // How wide and how tall the drawing is once it is turned.
          function turnedSize(){
            var bw=BOUNDS[2]-BOUNDS[0], bh=BOUNDS[3]-BOUNDS[1], t=viewTurn();
            if(!t.deg) return [bw,bh];
            return [Math.abs(bw*t.c)+Math.abs(bh*t.s), Math.abs(bw*t.s)+Math.abs(bh*t.c)];
          }

          // Where the handle sits: just outside the bottom right corner of the
          // drawing's frame, in pixels on the sheet.
          function rotHandleAt(v,k,ph){
            return [(v.x+v.w)*k+22, (ph-v.y)*k+8];      // clear of the square on that corner
          }

          // The direction of the mouse from the middle of the frame, in
          // degrees, anticlockwise - the way the angle itself is counted.
          function rotAngleAt(e){
            if(!VIEW||!PAGE) return null;
            var p=mouseAt(e); if(!p) return null;
            var cxs=VIEW.cx*VIEW.k, cys=(PAGE.height-VIEW.cy)*VIEW.k;
            return Math.atan2(-(p[1]-cys), p[0]-cxs)*180/Math.PI;
          }

          // A right angle wins: near a quarter turn it IS the quarter turn.
          function snapTurn(d){
            while(d>180) d-=360;
            while(d<=-180) d+=360;
            var q=Math.round(d/90)*90;
            d = Math.abs(d-q)<ROT_SNAP ? q : Math.round(d*10)/10;
            if(d<=-180) d+=360;
            return d===0 ? 0 : d;
          }

          function sendTurn(){
            var msg={rotation:viewTurn().deg};
            // the box the turn left (a box that turns as a whole can be made
            // smaller or pushed in by the turn) - null = all the margins leave
            if(boxTurns()) msg.view_box = STATE.view_box ? STATE.view_box.slice() : null;
            sketchup.set_rotation(JSON.stringify(msg));
          }

          // The box held on the sheet at this angle: a turned box that would
          // hang off the margins is made smaller (as a whole, so the scale of
          // the drawing is not touched) and pushed in - the same sum as
          // PlanCanvas.pic_inside with the box's own least size.
          function viewHold(r,a){ return picHold(r, a, BOX_MIN); }

          // While the round arrow is held: the drawing's box at this angle.
          // Only a box that turns as a whole can change by a turn.
          function turnBoxTo(deg){
            var v=planView(), a=boxArea();
            if(!v||!a||!ROT||!ROT.v0||!boxTurns()) return;
            var o=ROT.v0, hb=viewHold({x:o.x, y:o.y, w:o.w, h:o.h, rot:deg, crop:[0,0,0,0]}, a);
            var same=Math.abs(hb.x-o.x)<1e-9 && Math.abs(hb.y-o.y)<1e-9 && Math.abs(hb.w-o.w)<1e-9 && Math.abs(hb.h-o.h)<1e-9;
            if(same){ setBox(v, o.x, o.y, o.w, o.h); STATE.view_box=ROT.was.box ? ROT.was.box.slice() : null; }
            else { setBox(v, hb.x, hb.y, hb.w, hb.h); STATE.view_box=[hb.x, hb.y, hb.w, hb.h]; }
          }

          // He takes hold of the handle.
          function startTurn(e){
            if(MODE!=='hand'||CARRY||TCARRY||TBED) return;
            var tg=boxTarget();
            if(tg && tg.pic){
              // a picture: its whole box turns, about its own middle
              if(!PICON||!LIVEK) return;
              if(TSEL) closeTextBar();
              var pr=picRect(tg.pic);
              ROT={pic:tg.pic, p0:pr, s0:picKeep(tg.pic), was:picsSnap(),
                   a0:angleAbout(e, pr.x+pr.w/2, pr.y+pr.h/2), r0:pr.rot, moved:false};
              paintRot();
              if(e.preventDefault) e.preventDefault();
              if(e.stopPropagation) e.stopPropagation();
              return;
            }
            if(!ROTON||!VIEW) return;
            if(TSEL) closeTextBar();
            var tv=planView();
            ROT={a0:rotAngleAt(e), r0:viewTurn().deg, moved:false,
                 // the box as it stands: a turn may make it smaller or push it in
                 v0:(tv ? {x:tv.x, y:tv.y, w:tv.w, h:tv.h} : null),
                 was:{box:(STATE.view_box ? STATE.view_box.slice() : null), scale_f:(STATE.scale_f>0 ? STATE.scale_f : null)}};
            paintRot();
            if(e.preventDefault) e.preventDefault();
            if(e.stopPropagation) e.stopPropagation();
          }

          // Put the handle by the corner of the frame, or put it away: it is
          // only there with the select arrow, on a sheet that has a drawing.
          // While he is turning, the angle is written beside it.
          function paintRot(){
            paintBoxBar();          // and the settings at the side follow what is picked
            paintBoxH();            // the box's own handles go wherever this one goes
            var h=$('rothandle'); if(!h||!h.style) return;
            var tg=(MODE==='hand' && !TBED) ? boxTarget() : null;
            if(tg && tg.pic && PICON && LIVEK){
              // by the bottom right corner of the PICTURE, turned as it is turned
              var pr=picRect(tg.pic), pq=picScreen(pr, pr.w*LIVEK/2+22, pr.h*LIVEK/2+8);
              h.style.left=pq[0].toFixed(1)+'px';
              h.style.top=pq[1].toFixed(1)+'px';
              h.className='on';
              var pd=$('rotdeg');
              if(pd&&pd.style){
                pd.textContent = (ROT&&ROT.pic) ? (pr.rot+'°') : '';
                pd.style.display = (ROT&&ROT.pic) ? 'block' : 'none';
              }
              return;
            }
            var v=pageView();
            if(!ROTON||MODE!=='hand'||!VIEW||!v){ h.className=''; return; }
            var c=rotHandleAt(v,VIEW.k,PAGE.height), w=$('sheetWrap');
            if(boxTurns() && viewTurn().deg){
              // the box turns as a whole: by ITS bottom right corner, turned
              var vr=viewRect(), vq=picScreen(vr, vr.w*VIEW.k/2+22, vr.h*VIEW.k/2+8);
              c=[vq[0]-(w.offsetLeft||0), vq[1]-(w.offsetTop||0)];
            }
            h.style.left=((w.offsetLeft||0)+c[0]).toFixed(1)+'px';
            h.style.top=((w.offsetTop||0)+c[1]).toFixed(1)+'px';
            h.className='on';
            var d=$('rotdeg');
            if(d&&d.style){
              d.textContent = ROT ? (viewTurn().deg+'°') : '';
              d.style.display = ROT ? 'block' : 'none';
            }
          }

          // ---- the drawing's own box (2026-10-07) --------------------------
          //
          // What he likes in Rayon: "השרטוט הוא כאילו חצי תמונה - הוא נמצא בתוך
          // כמו קופסה משל עצמו. את הקופסה אני יכול להגדיל ולהקטין בעיקר
          // מהפינות... ולהזיז אותה על הדף." And on how: "הקופסה לא צריכה
          // להיצמד, אבל... שוליים לדף שהקופסה לא תוכל לצאת מהם. לא רוצה שקנה
          // המידה יקפוץ - אני רוצה שתהיה אופציה להגדיל ידנית."
          //
          //   a square on each corner   the box AND the drawing grow or shrink
          //                             together, about the opposite corner -
          //                             any size, nothing snaps
          //   the grip                  the box moves about the sheet, and the
          //                             drawing goes with it
          //   a side                    CUTS: "אני יכול לחתוך מהצלעות". Only
          //                             that side moves; the drawing stays
          //                             exactly where it is on the sheet, and
          //                             less of it (or more of it) is seen
          //   the margins               the box cannot leave what they leave
          //                             (PAGE.view_area, worked out by Ruby)
          //   the scale list            picking a scale there puts the drawing
          //                             back on an exact scale
          //
          // While he drags, the window moves the view it was given; on letting
          // go the two numbers go to Ruby with everything else (STATE.view_box,
          // STATE.scale_f) and Ruby lays the sheet out from them - the same
          // routine the PDF comes from.
          //
          // The iron law: Escape in the middle puts the box back; Ctrl+Z takes
          // the last move or resize back; the zoom and the place do not change.
          var BOXON=true;      // told by Ruby
          var CROPON=true;     // told by Ruby: a side cuts (false = a side moves the box)
          var BOXD=null;       // {kind, mx, my, v0, s0, o0, was, moved} while a handle is held
          var BOX_MIN=1.0;     // paper inches, either way

          // The view the hand tools work in: the plan sheet's. An editor
          // drawing's sheet (kind 'drawing') is seen, not worked on - no box,
          // no turn, no marks; it pans like a picture sheet (2026-10-07).
          function pageView(){
            var v=PAGE ? ((PAGE.views||[])[0]||null) : null;
            return (v && PAGE.kind!=='drawing') ? v : null;
          }
          function planView(){ return pageView(); }

          // What the margins leave - the box may not leave it.
          function boxArea(){
            if(!PAGE || !planView()) return null;
            var a=PAGE.view_area;
            if(a && a.length===4) return a;
            // a sheet from before Ruby said so: the same sum PlanDoc.new_sheet does
            var m=(typeof PAGE.margin==='number') ? PAGE.margin : 0.5;
            return [m+0.25, m+1.1+0.25, PAGE.width-2*m-0.5, PAGE.height-2*m-1.1-0.5];
          }

          function setBox(v, x, y, w, h){ v.x=x; v.y=y; v.w=w; v.h=h; }

          // He takes hold of a corner ('nw','ne','sw','se'), of a side
          // ('n','s','w','e') or of the box ('move').
          function startBox(kind,e){
            if(MODE!=='hand'||CARRY||TCARRY||TBED) return;
            var tg=boxTarget();
            if(tg && tg.pic){ startPic(tg.pic, kind, e); return; }
            if(!BOXON||!VIEW) return;
            var v=planView(); if(!v||!boxArea()) return;
            if(kind.length===1 && !CROPON) kind='move';
            if(TSEL) closeTextBar();
            BOXD={kind:kind, mx:e.clientX, my:e.clientY, v0:{x:v.x, y:v.y, w:v.w, h:v.h},
                  s0:scaleFactor(STATE.scale)*12,
                  o0:{x:STATE.origin_x, y:STATE.origin_y},
                  was:{box:(STATE.view_box ? STATE.view_box.slice() : null),
                       scale_f:(STATE.scale_f>0 ? STATE.scale_f : null)},
                  moved:false};
            if(e.preventDefault) e.preventDefault();
            if(e.stopPropagation) e.stopPropagation();
          }

          // The mouse has moved with a handle held.
          function dragBox(e){
            if(BOXD.pic){ dragPic(e); return; }
            if(boxTurns() && viewTurn().deg){ dragBoxTurned(e); return; }
            var v=planView(), a=boxArea();
            if(!v||!a||!VIEW) return;
            var o=BOXD.v0, k=VIEW.k;
            var dx=(e.clientX-BOXD.mx)/k, dy=-(e.clientY-BOXD.my)/k;      // paper inches; up is up
            var nx, ny, nw=o.w, nh=o.h, f=1;
            if(BOXD.kind==='move'){
              nx=Math.min(Math.max(o.x+dx, a[0]), a[0]+a[2]-o.w);
              ny=Math.min(Math.max(o.y+dy, a[1]), a[1]+a[3]-o.h);
            } else if(BOXD.kind.length===1){
              // A SIDE CUTS. Only that side moves: never past the margin, and
              // never closer than an inch to the side across from it.
              var hold=function(d,lo,hi){ return Math.max(lo, Math.min(d, hi)); };
              var d;
              nx=o.x; ny=o.y;
              if(BOXD.kind==='e'){ d=hold(dx, BOX_MIN-o.w, a[0]+a[2]-(o.x+o.w)); nw=o.w+d; }
              if(BOXD.kind==='w'){ d=hold(dx, a[0]-o.x, o.w-BOX_MIN); nx=o.x+d; nw=o.w-d; }
              if(BOXD.kind==='n'){ d=hold(dy, BOX_MIN-o.h, a[1]+a[3]-(o.y+o.h)); nh=o.h+d; }
              if(BOXD.kind==='s'){ d=hold(dy, a[1]-o.y, o.h-BOX_MIN); ny=o.y+d; nh=o.h-d; }
              // The drawing is hung from the MIDDLE of its box, and the middle
              // has just moved by half of what the side moved. So the point of
              // the house that sits in the middle moves the same way, and
              // every line stays on the very spot of the paper it was on.
              var mcx=(nx+nw/2)-(o.x+o.w/2), mcy=(ny+nh/2)-(o.y+o.h/2);
              var ct=viewTurn(), csf=BOXD.s0/12;
              STATE.origin_x=BOXD.o0.x+(mcx*ct.c+mcy*ct.s)/csf;
              STATE.origin_y=BOXD.o0.y+(-mcx*ct.s+mcy*ct.c)/csf;
            } else {
              var sx=(BOXD.kind.indexOf('e')>=0) ? 1 : -1, sy=(BOXD.kind.indexOf('n')>=0) ? 1 : -1;
              // the corner across from the one he holds stays where it is
              var ax=(sx>0) ? o.x : o.x+o.w, ay=(sy>0) ? o.y : o.y+o.h;
              // how far along the box's own diagonal the mouse has gone
              f=1+((dx*sx)*o.w+(dy*sy)*o.h)/(o.w*o.w+o.h*o.h);
              // never past the margins, never smaller than a box worth having
              var fmax=Math.min(((sx>0) ? a[0]+a[2]-ax : ax-a[0])/o.w, ((sy>0) ? a[1]+a[3]-ay : ay-a[1])/o.h);
              var fmin=Math.min(Math.max(BOX_MIN/o.w, BOX_MIN/o.h), fmax);
              f=Math.max(fmin, Math.min(f, fmax));
              nw=o.w*f; nh=o.h*f;
              nx=(sx>0) ? ax : ax-nw; ny=(sy>0) ? ay : ay-nh;
            }
            var same=Math.abs(nx-o.x)<1e-9 && Math.abs(ny-o.y)<1e-9 && Math.abs(nw-o.w)<1e-9 && Math.abs(nh-o.h)<1e-9;
            if(same){
              // back where it started (or it had nowhere to go): as if never touched
              setBox(v, o.x, o.y, o.w, o.h);
              STATE.view_box=BOXD.was.box; STATE.scale_f=BOXD.was.scale_f;
              STATE.origin_x=BOXD.o0.x; STATE.origin_y=BOXD.o0.y;
              BOXD.moved=false;
            } else {
              setBox(v, nx, ny, nw, nh);
              STATE.view_box=[nx, ny, nw, nh];
              // the drawing grows with its box: a size set by hand, any number
              // (a side only cuts - the size of the drawing is not touched)
              if(BOXD.kind.length===2) STATE.scale_f=BOXD.s0*f;
              BOXD.moved=true;
            }
            render(true);
          }

          // The same pull on a box that is TURNED (2026-10-07, stage 5): the
          // corners and the sides are the box's own, so the pull is taken in
          // the box's frame (lx along it, ly up it), the corner across from
          // the one he holds stays put, a side cuts, and the box is held
          // inside the margins by the room it takes up turned - as a picture
          // is (dragPic). An unturned box goes the old road, to the digit.
          function dragBoxTurned(e){
            var v=planView(), a=boxArea();
            if(!v||!a||!VIEW) return;
            var o=BOXD.v0, k=VIEW.k, kind=BOXD.kind, rot=viewTurn().deg;
            var dx=(e.clientX-BOXD.mx)/k, dy=-(e.clientY-BOXD.my)/k;      // paper inches; up is up
            var t=rot*Math.PI/180, c=Math.cos(t), n=Math.sin(t);
            var lx=dx*c+dy*n, ly=-dx*n+dy*c;            // the same pull, in the box's own frame
            var cx0=o.x+o.w/2, cy0=o.y+o.h/2, r;
            // the box at w by h, its middle moved (ux, uy) in its own frame
            var made=function(w,h,ux,uy){
              var cx=cx0+ux*c-uy*n, cy=cy0+ux*n+uy*c;
              return {x:cx-w/2, y:cy-h/2, w:w, h:h, rot:rot, crop:[0,0,0,0]};
            };
            if(kind==='move'){
              var hf=picHalf({w:o.w, h:o.h, rot:rot});
              var mx=Math.min(Math.max(cx0+dx, a[0]+hf[0]), a[0]+a[2]-hf[0]);
              var my=Math.min(Math.max(cy0+dy, a[1]+hf[1]), a[1]+a[3]-hf[1]);
              r={x:mx-o.w/2, y:my-o.h/2, w:o.w, h:o.h, rot:rot, crop:[0,0,0,0]};
            } else {
              var build, amt;       // build(u) = the box when u of the pull is taken; amt = all of it
              if(kind.length===2){
                // A CORNER: the box and the drawing grow or shrink together,
                // the corner across from it stays put - never smaller than a box worth having
                var sx=(kind.indexOf('e')>=0) ? 1 : -1, sy=(kind.indexOf('n')>=0) ? 1 : -1;
                var f=1+((lx*sx)*o.w+(ly*sy)*o.h)/(o.w*o.w+o.h*o.h);
                f=Math.max(f, Math.max(BOX_MIN/o.w, BOX_MIN/o.h));
                amt=f-1;
                build=function(u){ return made(o.w*(1+u), o.h*(1+u), sx*o.w*u/2, sy*o.h*u/2); };
              } else {
                // A SIDE CUTS: only that side moves - never closer than an
                // inch to the side across from it
                var horiz=(kind==='e'||kind==='w'), sgn=(kind==='e'||kind==='n') ? 1 : -1;
                var len=horiz ? o.w : o.h;
                amt=Math.max((horiz ? lx : ly)*sgn, BOX_MIN-len);
                build=function(u){ return horiz ? made(o.w+u, o.h, sgn*u/2, 0) : made(o.w, o.h+u, 0, sgn*u/2); };
              }
              r=build(amt);
              if(amt>0 && !picIn(r,a)){
                // it would pass the margins: as far as it can go and no further
                var lo=0, hi=amt;
                for(var i=0;i<40;i++){ var md=(lo+hi)/2; if(picIn(build(md),a)) lo=md; else hi=md; }
                r=build(lo);
              }
            }
            var same=Math.abs(r.x-o.x)<1e-9 && Math.abs(r.y-o.y)<1e-9 && Math.abs(r.w-o.w)<1e-9 && Math.abs(r.h-o.h)<1e-9;
            if(same){
              // back where it started (or it had nowhere to go): as if never touched
              setBox(v, o.x, o.y, o.w, o.h);
              STATE.view_box=BOXD.was.box; STATE.scale_f=BOXD.was.scale_f;
              STATE.origin_x=BOXD.o0.x; STATE.origin_y=BOXD.o0.y;
              BOXD.moved=false;
            } else {
              setBox(v, r.x, r.y, r.w, r.h);
              STATE.view_box=[r.x, r.y, r.w, r.h];
              if(kind.length===2){
                // the drawing grows with its box: a size set by hand, any number
                STATE.scale_f=BOXD.s0*(r.w/o.w);
              } else if(kind.length===1){
                // a cut moved the middle of the box; the house hangs from the
                // middle, so it is moved back by the same amount and every
                // line stays on its spot of the paper (the same sum as dragBox)
                var mcx=(r.x+r.w/2)-cx0, mcy=(r.y+r.h/2)-cy0, csf=BOXD.s0/12;
                STATE.origin_x=BOXD.o0.x+(mcx*c+mcy*n)/csf;
                STATE.origin_y=BOXD.o0.y+(-mcx*n+mcy*c)/csf;
              }
              BOXD.moved=true;
            }
            render(true);
          }

          // Escape with the round arrow held: the angle goes back.
          function dropTurn(){
            var rr=ROT; ROT=null;
            if(!rr) return;
            if(rr.pic){ picPut(rr.pic, rr.s0); picsBack(rr.was); }
            else { STATE.rotation=rr.r0; if(rr.was && boxTurns()) restoreBox(rr.was); }
          }

          // Escape with a handle held: the box, the size and the place of the
          // drawing go back to what they were when he took hold.
          function dropBox(){
            var bd=BOXD; BOXD=null;
            if(!bd) return;
            if(bd.pic){ picPut(bd.pic, bd.s0); picsBack(bd.was); return; }
            restoreBox(bd.was);
            STATE.origin_x=bd.o0.x; STATE.origin_y=bd.o0.y;
          }

          // Put the box and the size back the way a step remembered them.
          function restoreBox(was){
            var v=planView(), a=boxArea();
            STATE.view_box = was.box ? was.box.slice() : null;
            STATE.scale_f = was.scale_f || null;
            // a cut moved the middle of the box, and the house with it: taken
            // back by the same amount, so a slide of the drawing made SINCE is kept
            if(typeof was.dox==='number' && typeof was.doy==='number'){ STATE.origin_x-=was.dox; STATE.origin_y-=was.doy; }
            if(v){
              var b = was.box || a;            // no box of his own = all the margins leave
              // a box that turns as a whole is shown held inside the margins at
              // its angle - what Ruby will answer with - not hanging off meanwhile
              if(b && a && boxTurns() && viewTurn().deg){ var hb=viewHold({x:b[0], y:b[1], w:b[2], h:b[3], rot:viewTurn().deg, crop:[0,0,0,0]}, a); b=[hb.x, hb.y, hb.w, hb.h]; }
              if(b) setBox(v, b[0], b[1], b[2], b[3]);
            }
            paintScale();
          }

          // The scale list says what the drawing is at: one of its scales, or
          // "any size" when he set the size by hand.
          var FREE_SCALE='scale';      // his name for a size set by hand (2026-10-07, "את גודל חופשי תקרא לו scale")
          function paintScale(){
            var free=BOXON && STATE && STATE.scale_f>0;
            fill('scale', free ? [FREE_SCALE].concat(SCALES) : SCALES, free ? FREE_SCALE : STATE.scale);
          }

          // Put the box's handles on its corners and sides, or put them away:
          // they are only there with the select arrow, on a sheet with a drawing.
          function paintBoxH(){
            var tg=(MODE==='hand' && !TBED) ? boxTarget() : null;
            var v=tg ? (tg.view||null) : null, pc=tg ? (tg.pic||null) : null;
            var on=!!((v && BOXON && VIEW) || (pc && PICON && LIVEK));
            var cls={boxmove:'', 'boxc-nw':'boxc', 'boxc-ne':'boxc', 'boxc-sw':'boxc', 'boxc-se':'boxc',
                     'boxe-n':'boxe', 'boxe-s':'boxe', 'boxe-w':'boxe', 'boxe-e':'boxe'};
            for(var id in cls){
              var h=$(id); if(!h||!h.style) return;
              h.className=(cls[id]+(on ? ' on' : '')).replace(/^ /,'');
            }
            if(!on) return;
            // the drawing's box, when it turns as a whole, is placed like a picture's
            var tv=(!pc && boxTurns() && viewTurn().deg) ? viewRect() : null;
            if(pc || tv){
              // A picture's box can be TURNED, so every handle is put by its
              // own middle, the turned way round, and turned with the box.
              var pr=pc ? picRect(pc) : tv, PW=pr.w*LIVEK, PH=pr.h*LIVEK, ptr=pr.rot ? ('rotate('+(-pr.rot)+'deg)') : '';
              var putp=function(id,u,vv,ww,hh){
                var q=picScreen(pr,u,vv), st=$(id).style;
                if(ww===undefined){ st.left=q[0].toFixed(1)+'px'; st.top=q[1].toFixed(1)+'px'; }
                else {
                  ww=Math.max(ww,0); hh=Math.max(hh,0);
                  st.left=(q[0]-ww/2).toFixed(1)+'px'; st.top=(q[1]-hh/2).toFixed(1)+'px';
                  st.width=ww.toFixed(1)+'px'; st.height=hh.toFixed(1)+'px';
                }
                st.transform=ptr;
              };
              putp('boxc-nw',-PW/2,-PH/2); putp('boxc-ne',PW/2,-PH/2); putp('boxc-sw',-PW/2,PH/2); putp('boxc-se',PW/2,PH/2);
              putp('boxmove',-PW/2-22,-PH/2-8);
              putp('boxe-n',0,-PH/2,PW-16,8); putp('boxe-s',0,PH/2,PW-16,8);
              putp('boxe-w',-PW/2,0,8,PH-16); putp('boxe-e',PW/2,0,8,PH-16);
              // a box of writing is as tall as its lines: no bar on its top or its bottom
              if(pc && pc.txt){ $('boxe-n').className='boxe'; $('boxe-s').className='boxe'; }
              return;
            }
            for(var id2 in cls){ $(id2).style.transform=''; }      // the drawing's box is never turned
            var wr=$('sheetWrap'), k=VIEW.k;
            var L=(wr.offsetLeft||0)+v.x*k, T=(wr.offsetTop||0)+(PAGE.height-v.y-v.h)*k, W=v.w*k, H=v.h*k;
            var put=function(id,x,y,ww,hh){
              var st=$(id).style;
              st.left=x.toFixed(1)+'px'; st.top=y.toFixed(1)+'px';
              if(ww!==undefined){ st.width=Math.max(ww,0).toFixed(1)+'px'; st.height=Math.max(hh,0).toFixed(1)+'px'; }
            };
            put('boxc-nw',L,T); put('boxc-ne',L+W,T); put('boxc-sw',L,T+H); put('boxc-se',L+W,T+H);
            put('boxmove',L-22,T-8);
            put('boxe-n',L+8,T-4,W-16,8); put('boxe-s',L+8,T+H-4,W-16,8);
            put('boxe-w',L-4,T+8,8,H-16); put('boxe-e',L+W-4,T+8,8,H-16);
          }

          // ---- pictures in boxes of their own (2026-10-07) ------------------
          //
          // "אני רוצה שתהיה אפשרות לסובב את השרטוט וגם את התמונות", "אני גם
          // יכול לבחור מה יראו מהתמונה... חיתוך", "שיהיה אפשרי להוסיף כמה
          // תמונות בדף, או תמונות גם בדף השרטוט". And: "הסקייל הוא רק לבחירה
          // של שרטוטים, התמונות לא צריכות סקייל."
          //
          // A picture is a box on its sheet, handled by the SAME squares, bars,
          // grip and round arrow as the drawing's box:
          //   a click on it      picks it: the handles go onto it
          //   dragging it        moves it (the grip does too)
          //   a corner           bigger or smaller, about the opposite corner
          //   a side             CUTS it: the picture stays where it is, less
          //                      of it (or more, up to its own edge) is seen
          //   the round arrow    turns the whole box about its middle
          //   Delete             takes a picture that was ADDED to a sheet off it
          //   the margins        it cannot leave what they leave (PAGE.pic_area)
          //
          // What is saved is three things a picture - box, crop, rot - see
          // PlanCanvas.place_pictures!, which lays them out for the PDF. While
          // he drags, the window changes the shape it was given; on letting go
          // the three go to Ruby with everything else and Ruby answers with the
          // sheet as it prints.
          //
          // The iron law: Escape in the middle puts it back; Ctrl+Z takes the
          // last step back; the zoom and the place do not change.
          var PICON=true;      // told by Ruby
          var BSEL=null;       // the picture he picked, by its name ('m:0', 'x:2'); null = none
          var LIVEK=0;         // pixels to the paper inch, on the sheet he is working on
          var PIC_MIN=0.5;     // paper inches, either way

          // Every picture on the open sheet that can be handled, bottom one first.
          function pagePics(){
            var out=[]; if(!PAGE||!PICON||!STATE) return out;
            var hid=STATE.hidden||[];
            (PAGE.layers||[]).forEach(function(l){
              if(hid.indexOf(l.name)>=0) return;
              (l.shapes||[]).forEach(function(s){
                if(s.type==='image' && s.pic && (s.placed || (s.iw>0 && s.ih>0))) out.push(s);
              });
            });
            // and every box of writing, handled the same way - last, so it is on top
            return out.concat(pageTexts());
          }

          // What the margins leave for a picture.
          function picArea(){
            if(!PAGE) return null;
            var a=PAGE.pic_area;
            if(a && a.length===4) return a;
            var m=(typeof PAGE.margin==='number') ? PAGE.margin : 0.5;
            return [m+0.25, m+1.1+0.25, PAGE.width-2*m-0.5, PAGE.height-2*m-1.1-0.5];
          }

          // Where a picture is on the paper: {x,y,w,h, rot, crop}. One that was
          // never touched sits in the middle of its space at its own
          // proportions - the same sum plan_pdf and the browser both do.
          function picRect(s){
            if(s.txt) return {x:s.x, y:s.y, w:s.w, h:s.h, rot:(+s.rot||0), crop:[0,0,0,0], txt:true, pt:s.pt, text:s.text, bold:!!s.bold, font:(s.font||null)};
            if(s.placed) return {x:s.x, y:s.y, w:s.w, h:s.h, rot:(+s.rot||0), crop:(s.crop||[0,0,0,0]).slice()};
            var w=s.w, h=s.h;
            if(!s.stretch && s.iw>0 && s.ih>0){
              if(s.iw/s.ih > s.w/s.h) h=s.w*s.ih/s.iw; else w=s.h*s.iw/s.ih;
            }
            return {x:s.x+(s.w-w)/2, y:s.y+(s.h-h)/2, w:w, h:h, rot:0, crop:[0,0,0,0]};
          }

          // The shape as it stands, and put back that way.
          function picKeep(s){ return {placed:s.placed, x:s.x, y:s.y, w:s.w, h:s.h, rot:s.rot, crop:(s.crop ? s.crop.slice() : s.crop)}; }
          function picPut(s,q){
            s.x=q.x; s.y=q.y; s.w=q.w; s.h=q.h;
            if(q.placed) s.placed=q.placed; else delete s.placed;
            if(q.rot===undefined) delete s.rot; else s.rot=q.rot;
            if(q.crop===undefined) delete s.crop; else s.crop=q.crop.slice();
          }

          // Where this picture's three things are kept: null if nowhere.
          function picName(s){
            var id=String(s.pic||''), n=parseInt(id.slice(2),10);
            return (id.charAt(1)===':' && n>=0) ? {main:id.charAt(0)==='m', txt:id.charAt(0)==='t', n:n} : null;
          }

          // The picture now lies at r: on the sheet here, and in what is saved.
          function setPic(s,r){
            if(s.txt){
              // a box of writing: what is saved changes, and its lines are laid again from that
              var tn=picName(s), tx=tn ? (STATE.texts||[])[tn.n] : null;
              if(!tx) return;
              tx.box=[r.x,r.y,r.w,r.h]; tx.rot=r.rot;
              if(r.pt>0) tx.pt=r.pt;
              tbRebuild();
              return;
            }
            s.placed=true; s.x=r.x; s.y=r.y; s.w=r.w; s.h=r.h; s.rot=r.rot; s.crop=r.crop.slice();
            var nm=picName(s); if(!nm) return;
            if(nm.main){
              if(!STATE.image_geo) STATE.image_geo={};
              STATE.image_geo[String(nm.n)]={box:[r.x,r.y,r.w,r.h], rot:r.rot, crop:r.crop.slice()};
            } else if(STATE.pics && STATE.pics[nm.n]){
              STATE.pics[nm.n].box=[r.x,r.y,r.w,r.h]; STATE.pics[nm.n].rot=r.rot; STATE.pics[nm.n].crop=r.crop.slice();
            }
          }

          // Everything saved about pictures, as one piece - a step for Ctrl+Z.
          // (the writing in boxes rides in the same piece: one kind of step for all three)
          function picsSnap(){ return JSON.stringify({pics:STATE.pics||[], geo:STATE.image_geo||{}, texts:STATE.texts||[]}); }
          function picsBack(snap){
            var o=JSON.parse(snap); STATE.pics=o.pics; STATE.image_geo=o.geo;
            if(o.texts!==undefined){ STATE.texts=o.texts; tbRebuild(); }
          }

          // After a step is taken back: the pictures on the open sheet go where
          // what is saved says. (One added or taken off comes with Ruby's answer.)
          function picsToShapes(){
            pagePics().forEach(function(s){
              var nm=picName(s); if(!nm||nm.txt) return;
              var g=nm.main ? (STATE.image_geo||{})[String(nm.n)] : (STATE.pics||[])[nm.n];
              if(g && g.box){
                s.placed=true; s.x=g.box[0]; s.y=g.box[1]; s.w=g.box[2]; s.h=g.box[3];
                s.rot=+g.rot||0; s.crop=(g.crop||[0,0,0,0]).slice();
              } else if(nm.main){
                var a=picArea();
                delete s.placed; s.x=a[0]; s.y=a[1]; s.w=a[2]; s.h=a[3]; s.rot=0; s.crop=[0,0,0,0];
              }
            });
          }

          // Half the room a picture takes up once it is turned: [across, up].
          function picHalf(r){
            var t=r.rot*Math.PI/180, c=Math.abs(Math.cos(t)), n=Math.abs(Math.sin(t));
            return [(r.w*c+r.h*n)/2, (r.w*n+r.h*c)/2];
          }

          function picIn(r,a){
            var hf=picHalf(r), cx=r.x+r.w/2, cy=r.y+r.h/2, e=1e-7;
            return cx-hf[0]>=a[0]-e && cx+hf[0]<=a[0]+a[2]+e && cy-hf[1]>=a[1]-e && cy+hf[1]<=a[1]+a[3]+e;
          }

          // Held on the sheet: first small enough, then in. The same sum as
          // PlanCanvas.pic_inside, so Ruby has nothing left to correct.
          function picHold(r,a,least){
            if(!(least>0)) least=PIC_MIN;
            var cx=r.x+r.w/2, cy=r.y+r.h/2, w=Math.max(r.w,least), h=Math.max(r.h,least);
            var hf=picHalf({w:w, h:h, rot:r.rot});
            var f=Math.min(a[2]/(2*hf[0]), a[3]/(2*hf[1]), 1);
            if(f<1){ w*=f; h*=f; hf=[hf[0]*f, hf[1]*f]; }
            cx=Math.min(Math.max(cx, a[0]+hf[0]), a[0]+a[2]-hf[0]);
            cy=Math.min(Math.max(cy, a[1]+hf[1]), a[1]+a[3]-hf[1]);
            return {x:cx-w/2, y:cy-h/2, w:w, h:h, rot:r.rot, crop:r.crop.slice()};
          }

          // A spot (u to the right, v down, in pixels from the picture's middle,
          // before turning) -> where it is in the stage.
          function picScreen(r,u,v){
            var wr=$('sheetWrap'), t=r.rot*Math.PI/180, c=Math.cos(t), n=Math.sin(t);
            return [(wr.offsetLeft||0)+(r.x+r.w/2)*LIVEK+u*c+v*n,
                    (wr.offsetTop||0)+(PAGE.height-(r.y+r.h/2))*LIVEK-u*n+v*c];
          }

          // The direction of the mouse from a point of the paper, in degrees,
          // anticlockwise.
          function angleAbout(e,cx,cy){
            var p=mouseAt(e); if(!p||!PAGE||!LIVEK) return null;
            return Math.atan2(-(p[1]-(PAGE.height-cy)*LIVEK), p[0]-cx*LIVEK)*180/Math.PI;
          }

          // The picture under the mouse - the one drawn on top wins.
          function hitPic(e){
            var p=mouseAt(e); if(!p||!PAGE||!LIVEK) return null;
            var px=p[0]/LIVEK, py=PAGE.height-p[1]/LIVEK, pics=pagePics();
            for(var i=pics.length-1;i>=0;i--){
              var r=picRect(pics[i]), t=r.rot*Math.PI/180, c=Math.cos(t), n=Math.sin(t);
              var dx=px-(r.x+r.w/2), dy=py-(r.y+r.h/2);
              if(Math.abs(dx*c+dy*n)<=r.w/2 && Math.abs(-dx*n+dy*c)<=r.h/2) return pics[i];
            }
            return null;
          }

          // What the handles are on: the picture he picked; or the drawing's
          // box; or, on a sheet with no drawing, the first picture.
          function boxTarget(){
            if(!PAGE) return null;
            var pics=pagePics();
            if(BSEL!==null) for(var i=0;i<pics.length;i++) if(pics[i].pic===BSEL) return {pic:pics[i]};
            var v=planView();
            if(v) return (BOXON && VIEW) ? {view:v} : null;
            for(var j=0;j<pics.length;j++) if(!pics[j].txt) return {pic:pics[j]};
            return null;
          }

          // The picture of that name on the sheet as it is NOW. Ruby's answer to
          // the last step swaps every shape for a new one; a pull begun a
          // moment before that answer must go on moving the one that is drawn.
          function picLive(s){
            var pics=pagePics();
            for(var i=0;i<pics.length;i++) if(pics[i].pic===s.pic) return pics[i];
            return s;
          }

          // He takes hold of a picture: by a corner, a side, or the whole of it.
          function startPic(s,kind,e){
            if(!PICON||!LIVEK||!picArea()) return;
            if(s.txt && (kind==='n'||kind==='s')) return;      // a box of writing is as tall as its lines
            if(s.txt){
              // Two presses on the same box of writing, close together, open
              // it - counted HERE, not left to the browser's double click
              // (2026-10-07, "זה עובד רק אם אני לוחץ על סימן ההזזה"). A press
              // on the words redraws the sheet, so the browser's second click
              // lands on a new element and its double click never comes.
              // The box opens on LETTING GO of the second press, if it did not
              // move - a quick press-and-drag stays a drag.
              var now=Date.now();
              var dbl=!!(TBLAST && TBLAST.pic===s.pic && now-TBLAST.t<450 && Math.hypot(e.clientX-TBLAST.x, e.clientY-TBLAST.y)<8);
              TBLAST=dbl ? null : {pic:s.pic, t:now, x:e.clientX, y:e.clientY};
            }
            if(TSEL) closeTextBar();
            BOXD={kind:kind, mx:e.clientX, my:e.clientY, pic:s, p0:picRect(s), s0:picKeep(s),
                  was:picsSnap(), moved:false, dbl:!!(s.txt && dbl)};
            if(e.preventDefault) e.preventDefault();
            if(e.stopPropagation) e.stopPropagation();
          }

          // The mouse has moved with a picture held.
          function dragPic(e){
            BOXD.pic=picLive(BOXD.pic);
            var s=BOXD.pic, o=BOXD.p0, a=picArea(), k=LIVEK, kind=BOXD.kind;
            if(!a||!k) return;
            var dx=(e.clientX-BOXD.mx)/k, dy=-(e.clientY-BOXD.my)/k;      // paper inches; up is up
            var t=o.rot*Math.PI/180, c=Math.cos(t), n=Math.sin(t);
            var lx=dx*c+dy*n, ly=-dx*n+dy*c;            // the same pull, in the picture's own frame
            var cx0=o.x+o.w/2, cy0=o.y+o.h/2, r;
            var txt=!!o.txt;
            // the picture at w by h, its middle moved (ux, uy) in its own frame
            var made=function(w,h,ux,uy,crop){
              var cx=cx0+ux*c-uy*n, cy=cy0+ux*n+uy*c;
              return {x:cx-w/2, y:cy-h/2, w:w, h:h, rot:o.rot, crop:crop};
            };
            if(kind==='move'){
              var hf=picHalf(o);
              var mx=Math.min(Math.max(cx0+dx, a[0]+hf[0]), a[0]+a[2]-hf[0]);
              var my=Math.min(Math.max(cy0+dy, a[1]+hf[1]), a[1]+a[3]-hf[1]);
              r={x:mx-o.w/2, y:my-o.h/2, w:o.w, h:o.h, rot:o.rot, crop:o.crop.slice()};
            } else {
              var build, amt;       // build(u) = the picture when u of the pull is taken; amt = all of it
              if(kind.length===2){
                // A CORNER: bigger or smaller, the corner across from it stays put
                var sx=(kind.indexOf('e')>=0) ? 1 : -1, sy=(kind.indexOf('n')>=0) ? 1 : -1;
                var f=1+((lx*sx)*o.w+(ly*sy)*o.h)/(o.w*o.w+o.h*o.h);
                if(txt) f=Math.min(Math.max(f, Math.min(1, TXR.pt_min/o.pt)), Math.max(1, TXR.pt_max/o.pt));
                else f=Math.max(f, Math.min(1, PIC_MIN/Math.min(o.w,o.h)));
                amt=f-1;
                // (writing: the letters grow by the same amount as the box, so
                // the lines break exactly where they did)
                build=function(u){
                  var q=made(o.w*(1+u), o.h*(1+u), sx*o.w*u/2, sy*o.h*u/2, o.crop.slice());
                  if(txt) q.pt=o.pt*(1+u);
                  return q;
                };
              } else if(txt){
                // A SIDE OF A BOX OF WRITING makes it wider or narrower, and
                // the lines are laid again to fit. The top of the box stays
                // where it is; it is never narrower than its longest word.
                var tsg=(kind==='e') ? 1 : -1, tpad=TXR.pad*o.pt/72, tmin=PIC_MIN;
                tbWrap(o.text, 0, o.pt, o.bold, o.font).forEach(function(wd){ tmin=Math.max(tmin, tbWidth(wd,o.pt,o.bold,o.font)+2*tpad); });
                amt=Math.max(Math.min(0, tmin-o.w), lx*tsg);
                build=function(u){
                  var nw=o.w+u, nh=tbHeight(tbWrap(o.text, nw-2*tpad, o.pt, o.bold, o.font).length, o.pt);
                  var q=made(nw, nh, tsg*u/2, -(nh-o.h)/2, o.crop.slice());
                  q.pt=o.pt;
                  return q;
                };
              } else {
                // A SIDE CUTS: the picture stays where it is and that side
                // moves over it - never past the picture's own edge.
                var horiz=(kind==='e'||kind==='w'), sgn=(kind==='e'||kind==='n') ? 1 : -1;
                var len=horiz ? o.w : o.h, ci={w:0, s:1, e:2, n:3}[kind];
                var seen=horiz ? (1-o.crop[0]-o.crop[2]) : (1-o.crop[1]-o.crop[3]);
                var full=len/Math.max(seen,0.01);       // the WHOLE picture that way, on the paper
                var d=(horiz ? lx : ly)*sgn;             // how far the side has gone OUT
                d=Math.max(Math.min(0, PIC_MIN-len), Math.min(d, o.crop[ci]*full));
                amt=d;
                build=function(u){
                  var cr=o.crop.slice(); cr[ci]=Math.max(0, o.crop[ci]-u/full);
                  return horiz ? made(o.w+u, o.h, sgn*u/2, 0, cr) : made(o.w, o.h+u, 0, sgn*u/2, cr);
                };
              }
              r=build(amt);
              if(amt>0 && !picIn(r,a)){
                // it would pass the margins: as far as it can go and no further
                var lo=0, hi=amt;
                for(var i=0;i<40;i++){ var md=(lo+hi)/2; if(picIn(build(md),a)) lo=md; else hi=md; }
                r=build(lo);
              }
            }
            if(txt){
              if(!(r.pt>0)) r.pt=o.pt;
              r.txt=true; r.text=o.text;
              if(!picIn(r,a)) r=tbHold(r,a);        // narrower is taller: held on the sheet
            }
            var same=Math.abs(r.x-o.x)<1e-9 && Math.abs(r.y-o.y)<1e-9 && Math.abs(r.w-o.w)<1e-9 && Math.abs(r.h-o.h)<1e-9;
            if(same){
              // back where it started (or it had nowhere to go): as if never touched
              picPut(s, BOXD.s0); picsBack(BOXD.was);
              BOXD.moved=false;
            } else {
              setPic(s, r);
              BOXD.moved=true;
            }
            render(true);
          }

          // Delete: a picture that was added to a sheet comes off it. The one a
          // picture sheet was made for goes with its sheet, by the x in the list.
          function dropPic(){
            var id=String(BSEL||'');
            if(id.charAt(0)==='t'){
              // a box of writing comes off its sheet; Ctrl+Z puts it back
              var tj=parseInt(id.slice(2),10);
              if(!STATE.texts||!STATE.texts[tj]) return;
              var twas=picsSnap();
              STATE.texts.splice(tj,1);
              BSEL=null;
              tbRebuild();
              if(UNDOON){ UNDO.push({g:++UGROUP, pics:twas}); if(UNDO.length>300) UNDO.shift(); }
              push(); render(); showMarks();
              return;
            }
            if(id.charAt(0)!=='x'){
              $('markinfo').textContent='התמונה הזאת היא הדף עצמו. כדי להוריד אותה, מחק את הדף ב-× ברשימת הדפים.';
              return;
            }
            var j=parseInt(id.slice(2),10);
            if(!STATE.pics||!STATE.pics[j]) return;
            var was=picsSnap();
            STATE.pics.splice(j,1);
            // off the sheet here at once; the ones after it move down one, as
            // they will be numbered when Ruby answers
            (DOC.pages||[]).forEach(function(pg){
              (pg.layers||[]).forEach(function(l){
                l.shapes=(l.shapes||[]).filter(function(q){ return q.pic!==id; });
                l.shapes.forEach(function(q){
                  var nm=q.pic ? picName(q) : null;
                  if(nm && !nm.main && nm.n>j) q.pic='x:'+(nm.n-1);
                });
              });
            });
            BSEL=null;
            if(UNDOON){ UNDO.push({g:++UGROUP, pics:was}); if(UNDO.length>300) UNDO.shift(); }
            push(); render(); showMarks();
          }

          // ---- writing in boxes of its own (2026-10-07) --------------------
          //
          // "אני רוצה להוסיף אופציה של קופסא עם כיתוב. כמובן שהקופסא צריכה
          // להתנהג כמו שאר הקופסאות, ובקופסא יהיה אפשר לכתוב ולקבוע את גודל
          // הכיתוב."
          //
          //   the T button, a click   a box of writing starts there; he types,
          //                           and the box grows with the words
          //   a click on it           picks it: the SAME squares, bars, grip
          //                           and round arrow a picture has go onto it
          //   dragging it             moves it about the sheet
          //   a corner                box and letters bigger or smaller together
          //   a side (left, right)    wider or narrower - the lines are laid again
          //   the round arrow         turns the whole box about its middle
          //   two clicks on it        opens its words and its size again
          //   Delete                  takes it off the sheet
          //   the margins             it cannot leave what they leave
          //
          // What is saved is STATE.texts - {text, on, box, rot, pt} - see
          // PlanCanvas.place_texts!, which lays it out for the PDF. The words
          // on the sheet are plain text shapes on the sheet's TEXT layer, one
          // a line. The window lays the same lines by the same sums (tbWrap,
          // tbShapes - Ruby's are text_wrap, text_line_shapes) so the words
          // move under his hand without a trip to Ruby; t75 and rt275 hold the
          // two to the same numbers. On letting go Ruby is told once, and
          // answers with the sheet as it prints.
          //
          // The iron law: Escape drops what is half done (typing, a pull);
          // Ctrl+Z takes the last step back; the zoom and the place stay.
          var TXTON=true;      // told by Ruby
          // the rules of a box of writing - Ruby's own numbers, sent with the sheet
          var TXR={pad:0.25, lead:1.25, ascent:0.8, pt:24, pt_min:4, pt_max:400, cap:0.717, w:null, bold:1.06};
          var TBED=null;       // the box whose words are open: {n, fresh, was, free}
          var TBLAST=null;     // the last press on a box of writing: {pic, t, x, y}

          function tbClean(t){
            return String(t===undefined||t===null ? '' : t).replace(/\r\n?/g,'\n').replace(/\t/g,' ');
          }

          // How wide a run of words is at pt points, in paper inches - the
          // Helvetica widths the PDF prints with.
          function tbWidth(str,pt,bold,font){
            var tot=0, W=TXR.w||[];
            // a lettering of its own, or letters Helvetica has not got: THE
            // TABLE RUBY MEASURES BY (text_rules.fonts, PlanPDF.width_table)
            var fam=fontFor(str,font), tab=fam ? TXR.fonts[fam] : null;
            Array.from(String(str)).forEach(function(ch){
              var c=ch.codePointAt(0);
              if(tab) tot += (tab.w[c]!==undefined) ? tab.w[c] : tab.dw;
              else tot += (c>=32 && c<=126 && W[c-32]) ? W[c-32] : 556;
            });
            // bold letters are wider, by the amount plan_pdf counts (BOLD_BUMP)
            return tot/1000*pt/72*(bold ? (TXR.bold||1.06) : 1);
          }

          // How one box of writing is lettered, checked: {bold, italic,
          // underline, color} - only what is set. THE SAME RULE AS
          // PlanCanvas.text_style.
          function tbStyle(tx){
            var o={};
            if(!TXSTYLE||!tx) return o;
            if(tx.bold===true) o.bold=true;
            if(tx.italic===true) o.italic=true;
            if(tx.underline===true) o.underline=true;
            var c=String(tx.color||'').toLowerCase();
            if(/^#[0-9a-f]{6}$/.test(c) && c!=='#000000') o.color=c;
            var f=String(tx.font||'').trim();
            if(TXFONT && f && f.length<=40) o.font=f;
            return o;
          }

          // The words, in lines no wider than avail. A line he broke himself
          // stays broken; a word wider than the box stays whole.
          function tbWrap(text,avail,pt,bold,font){
            var out=[];
            tbClean(text).split('\n').forEach(function(para){
              var words=para.split(/ +/).filter(function(w){ return w!==''; });
              if(!words.length){ out.push(''); return; }
              var cur='';
              words.forEach(function(w){
                var t=(cur==='') ? w : cur+' '+w;
                if(cur==='' || tbWidth(t,pt,bold,font)<=avail+1e-6) cur=t;
                else { out.push(cur); cur=w; }
              });
              out.push(cur);
            });
            return out.length ? out : [''];
          }

          function tbHeight(n,pt){ var fs=pt/72; return 2*TXR.pad*fs+(n-1)*TXR.lead*fs+fs; }

          // The width a box needs to hold the words with no line broken but his own.
          function tbNatural(text,pt,bold,font){
            var m=0;
            tbWrap(text,1e9,pt,bold,font).forEach(function(l){ m=Math.max(m, tbWidth(l,pt,bold,font)); });
            return m+2*TXR.pad*pt/72;
          }

          // One plain text shape a line. THE SAME SUMS AS PlanCanvas.text_line_shapes.
          function tbShapes(en){
            var fs=en.pt/72, pad=TXR.pad*fs, pitch=TXR.lead*fs, rot=(+en.rot||0);
            var t=rot*Math.PI/180, c=rot ? Math.cos(t) : 1, n=rot ? Math.sin(t) : 0;
            var cx=en.x+en.w/2, cy=en.y+en.h/2, out=[];
            (en.lines||[]).forEach(function(str,i){
              if(str==='') return;
              var lx=-en.w/2+pad, ly=en.h/2-(pad+TXR.ascent*fs+i*pitch);
              var sh={type:'text', text:str, x:cx+lx*c-ly*n, y:cy+lx*n+ly*c, h:fs*(TXR.cap||0.717),
                      align:'left', rotation:rot, tbox:en.pic, li:i};
              // lettered the way he set it at the side
              if(en.bold) sh.bold=true;
              if(en.italic) sh.italic=true;
              if(en.underline) sh.underline=true;
              if(en.color) sh.color=en.color;
              if(en.font) sh.font=en.font;
              out.push(sh);
            });
            return out;
          }

          // Every box of writing on the open sheet, as Ruby (or tbRebuild) laid it.
          function pageTexts(){
            if(!PAGE||!TXTON||!STATE) return [];
            if((STATE.hidden||[]).indexOf('TEXT')>=0) return [];
            return PAGE.text_boxes||[];
          }

          // The open sheet's writing, laid again from what is saved: the boxes
          // the handles go on, and the lines on the TEXT layer.
          function tbRebuild(){
            if(!PAGE||!STATE) return;
            var key=pageKey(PAGE), list=[], shapes=[];
            (STATE.texts||[]).forEach(function(tx,j){
              if(!tx || tx.on!==key || !tx.box || tx.box.length!==4) return;
              var pt=(+tx.pt>0) ? +tx.pt : TXR.pt;
              var en={pic:'t:'+j, txt:true, placed:true, x:tx.box[0], y:tx.box[1], w:tx.box[2], h:tx.box[3],
                      rot:(+tx.rot||0), crop:[0,0,0,0], pt:pt, text:tbClean(tx.text)};
              var sy=tbStyle(tx);
              for(var sk in sy) en[sk]=sy[sk];
              en.lines=tbWrap(en.text, en.w-2*TXR.pad*pt/72, pt, en.bold, en.font);
              list.push(en);
              shapes=shapes.concat(tbShapes(en));
            });
            PAGE.text_boxes=list;
            if(!PAGE.layers) PAGE.layers=[];
            var lay=null;
            PAGE.layers.forEach(function(l){ if(l.name==='TEXT') lay=l; });
            if(!lay){
              if(!shapes.length) return;
              lay={name:'TEXT', visible:true, locked:false, shapes:[]};
              PAGE.layers.push(lay);
            }
            lay.shapes=shapes;
          }

          // The words of one box laid again at width w (or the width it has).
          // The TOP LEFT corner of the box stays where it is, turned or not -
          // the same rule PlanCanvas.text_geo keeps.
          function tbFit(tx,w){
            var b=tx.box, rot=(+tx.rot||0), t=rot*Math.PI/180, c=rot ? Math.cos(t) : 1, n=rot ? Math.sin(t) : 0;
            if(w===undefined) w=b[2];
            var h=tbHeight(tbWrap(tx.text, w-2*TXR.pad*tx.pt/72, tx.pt, tbStyle(tx).bold, tbStyle(tx).font).length, tx.pt);
            var cx=b[0]+b[2]/2, cy=b[1]+b[3]/2;
            var tlx=cx+(-b[2]/2)*c-(b[3]/2)*n, tly=cy+(-b[2]/2)*n+(b[3]/2)*c;
            var ncx=tlx-((-w/2)*c-(h/2)*n), ncy=tly-((-w/2)*n+(h/2)*c);
            tx.box=[ncx-w/2, ncy-h/2, w, h];
          }

          // Held on the sheet: first small enough, then in - and the letters
          // are made smaller by the same amount. PlanCanvas.text_inside.
          function tbHold(r,a){
            var cx=r.x+r.w/2, cy=r.y+r.h/2, w=r.w, h=r.h, hf=picHalf({w:w, h:h, rot:r.rot});
            var f=Math.min(a[2]/(2*hf[0]), a[3]/(2*hf[1]), 1);
            if(f<1){ w*=f; h*=f; hf=[hf[0]*f, hf[1]*f]; }
            cx=Math.min(Math.max(cx, a[0]+hf[0]), a[0]+a[2]-hf[0]);
            cy=Math.min(Math.max(cy, a[1]+hf[1]), a[1]+a[3]-hf[1]);
            return {x:cx-w/2, y:cy-h/2, w:w, h:h, rot:r.rot, crop:[0,0,0,0], txt:true, text:r.text,
                    pt:(f<1 ? r.pt*f : r.pt)};
          }

          // The bar opens: on a box that is there (n), or on a new one whose
          // top left corner is at `at` (paper inches).
          function tbOpen(n,at){
            if(!TXTON||!PAGE||!LIVEK||TBED) return;
            hideNoteBar(); closeTextBar();
            var was=picsSnap(), fresh=(n===null||n===undefined);
            if(!STATE.texts) STATE.texts=[];
            if(fresh){
              var pt0=TXR.pt, h0=tbHeight(1,pt0);
              STATE.texts.push({text:'', on:pageKey(PAGE), pt:pt0, rot:0, box:[at[0], at[1]-h0, tbNatural('',pt0), h0]});
              n=STATE.texts.length-1;
            }
            var tx=STATE.texts[n];
            if(!tx){ return; }
            TBED={n:n, fresh:fresh, was:was, free:fresh};
            $('tbtext').value=tx.text||'';
            $('tbsize').value=Math.round((+tx.pt||TXR.pt)*10)/10;
            $('tbok').textContent = fresh ? 'הוסף' : 'סיים';
            $('tbbar').className='on';
            BSEL='t:'+n;
            tbRebuild(); render(); showMarks();
            tbEditShow('box');             // the words are typed over the box itself
          }

          // He typed, or changed the size: the box on the sheet follows at once.
          function tbLive(){
            if(!TBED) return;
            var tx=(STATE.texts||[])[TBED.n]; if(!tx) return;
            var a=picArea(), pt=parseFloat($('tbsize').value);
            if(!isFinite(pt)||pt<=0) pt=+tx.pt||TXR.pt;
            pt=Math.min(TXR.pt_max, Math.max(TXR.pt_min, pt));
            var w=tx.box[2], words=tbClean($('tbtext').value);
            if(TBED.free){
              // a new one is as wide as its words - as far as the margin, and
              // from there the lines break
              var room=a ? Math.max(a[0]+a[2]-tx.box[0], PIC_MIN) : 1e9;
              w=Math.min(tbNatural(words,pt,tbStyle(tx).bold,tbStyle(tx).font), room);
            } else if(pt!==tx.pt){
              w=w*pt/tx.pt;        // bigger letters, wider box: the lines break where they did
            }
            tx.text=words; tx.pt=pt;
            tbFit(tx,w);
            if(a){
              var r=tbHold({x:tx.box[0], y:tx.box[1], w:tx.box[2], h:tx.box[3], rot:(+tx.rot||0), pt:tx.pt}, a);
              tx.box=[r.x,r.y,r.w,r.h]; tx.pt=r.pt;
            }
            tbRebuild(); render(true);
          }

          // ---- typing ON the sheet (2026-10-07) -----------------------------
          //
          // "אני לא רוצה שייפתח חלון עריכה עם כתיבה לכל טקסט... אני רוצה שהחלון
          // ייפתח שהוא הכיתוב עצמו, יש את זה בלייאאוט." So the words are typed
          // in a box laid exactly over the writing on the sheet - same place,
          // same size, same turn - and the sheet follows every letter. The
          // hidden bar (#tbbar) still keeps the words and the size, so tbLive /
          // tbSave / tbCancel are the one road, whichever way the words came.
          //   a box of writing   the editor is the box: as wide, its lines wrap
          //                      the same way, Enter is a new line
          //   a label            one line over the label; Enter keeps, Escape drops
          var LED=null;        // {kind:'box'} | {kind:'label'} | {kind:'note'} while the editor is open
          // a NEW note being written on the sheet (2026-10-08): where its words
          // begin on the screen and which way the shoulder runs there
          var NOTEED=null;     // {ax, ay, sx, sy}
          var NOTEJUST=0;      // when a new note was just kept - the click that kept it starts nothing
          var NOTENEW=null;    // the number of the note just made, until the sheet comes back with it

          function tbEditEl(){ return $('tbedit'); }

          // Over a box of writing: its place, its size, its turn.
          function tbEditPlace(){
            var ed=tbEditEl(); if(!ed||!ed.style) return;
            if(!LED){ ed.className=''; return; }
            var wr=$('sheetWrap');
            if(LED.kind==='box'){
              if(!TBED||!PAGE||!LIVEK){ ed.className=''; return; }
              var en=null, want='t:'+TBED.n;
              pageTexts().forEach(function(q){ if(q.pic===want) en=q; });
              if(!en){ ed.className=''; return; }
              var fs=en.pt/72*LIVEK, pad=TXR.pad*fs;
              ed.style.left=((wr.offsetLeft||0)+en.x*LIVEK).toFixed(1)+'px';
              ed.style.top=((wr.offsetTop||0)+(PAGE.height-en.y-en.h)*LIVEK).toFixed(1)+'px';
              ed.style.width=Math.max(en.w*LIVEK, 12).toFixed(1)+'px';
              ed.style.height=Math.max(en.h*LIVEK, 8).toFixed(1)+'px';
              ed.style.fontSize=fs.toFixed(2)+'px';
              ed.style.lineHeight=(TXR.lead*fs).toFixed(2)+'px';
              ed.style.padding=pad.toFixed(2)+'px';
              ed.style.transform=en.rot ? ('rotate('+(-en.rot)+'deg)') : '';
              ed.style.textAlign='';
              // typed in the letters it will be drawn in
              ed.style.fontWeight=en.bold ? '700' : '';
              ed.style.fontStyle=en.italic ? 'italic' : '';
              ed.style.fontFamily=fontCss(en.text, en.font);
              ed.style.textDecoration=en.underline ? 'underline' : '';
              ed.style.color=en.color || '';
              ed.className='on';
              return;
            }
            // A NEW note: one line where its words will stand - just past the
            // end of the shoulder, running the way the shoulder runs, in the
            // letters a note gets (2026-10-08). Nothing is on the sheet yet
            // but the dashed leader; the words go onto a mark when he is done.
            if(LED.kind==='note'){
              if(!NOTEED||!VIEW||!PAGE){ ed.className=''; return; }
              var n=NOTEED, hpx=markTextH()*VIEW.sf*VIEW.k, npx=hpx/0.717;
              var nw=Math.max(npx*14, 160), nh=npx*1.3+4;
              var nleft = VROT ? (n.ax-nw/2) : (n.sx>0.3 ? n.ax : (n.sx<-0.3 ? n.ax-nw : n.ax-nw/2));
              ed.style.left=((wr.offsetLeft||0)+nleft).toFixed(1)+'px';
              ed.style.top=((wr.offsetTop||0)+n.ay-nh/2).toFixed(1)+'px';
              ed.style.width=nw.toFixed(1)+'px';
              ed.style.height=nh.toFixed(1)+'px';
              ed.style.fontSize=npx.toFixed(2)+'px';
              ed.style.lineHeight=(npx*1.3).toFixed(2)+'px';
              ed.style.padding='1px 2px';
              ed.style.textAlign = VROT ? 'center' : (n.sx>0.3 ? 'left' : (n.sx<-0.3 ? 'right' : 'center'));
              ed.style.fontWeight=''; ed.style.fontStyle=''; ed.style.textDecoration=''; ed.style.color='';
              ed.style.fontFamily=fontCss('', '');
              ed.style.transform=VROT ? ('rotate('+(-VROT)+'deg)') : '';
              ed.className='on one';
              return;
            }
            // A label: one line laid exactly over the label itself - the same
            // middle, the same turn, the same size of letters - so the words
            // are typed where they stand, not in a box beside them
            // (2026-10-07, "שהכיתוב ייפתח באותה הקופסה של הכיתוב עצמו ולא
            // בקופסה נפרדת").
            if(!TSEL||!(VIEW||(TSEL.paper&&LIVEK))||!PAGE){ ed.className=''; return; }
            var b=textBox(TSEL.shape, TSEL.paper);
            // upright writing (an elevation's height): the box is laid on its side
            var up=TSEL.paper && Math.abs(((+TSEL.shape.rotation||0) % 360 + 360) % 360 - 90) < 1;
            var fpx=(up ? b.w : b.h)/0.717;
            var ew=Math.max((up ? b.h : b.w)+4, fpx*6, 60), eh=fpx*1.3+4;
            if(up){
              ed.style.left=((wr.offsetLeft||0)+b.x+b.w/2-ew/2).toFixed(1)+'px';
              ed.style.textAlign='center';
            } else if(TSEL.paper){
              // writing put straight on the sheet starts at its left end
              ed.style.left=((wr.offsetLeft||0)+b.x-2).toFixed(1)+'px';
              ed.style.textAlign='left';
            } else {
              // writing on the plan is centred on its point, and so is this
              ed.style.left=((wr.offsetLeft||0)+b.x+b.w/2-ew/2).toFixed(1)+'px';
              ed.style.textAlign='center';
            }
            ed.style.top=((wr.offsetTop||0)+b.y+b.h/2-eh/2).toFixed(1)+'px';
            ed.style.width=ew.toFixed(1)+'px';
            ed.style.height=eh.toFixed(1)+'px';
            ed.style.fontSize=fpx.toFixed(2)+'px';
            ed.style.lineHeight=(fpx*1.3).toFixed(2)+'px';
            ed.style.padding='1px 2px';
            ed.style.fontWeight=TSEL.shape.bold ? '700' : '';
            ed.style.fontStyle=TSEL.shape.italic ? 'italic' : '';
            ed.style.fontFamily=fontCss(TSEL.shape.text, TSEL.shape.font);
            ed.style.textDecoration=TSEL.shape.underline ? 'underline' : '';
            ed.style.color=/^#[0-9a-f]{6}$/i.test(String(TSEL.shape.color||'')) ? TSEL.shape.color : '';
            var rd=(TSEL.shape.rotation||0)+(TSEL.paper ? 0 : VROT);
            ed.style.transform=rd ? ('rotate('+(-rd)+'deg)') : '';
            ed.className='on one';
          }

          function tbEditShow(kind){
            var ed=tbEditEl(); if(!ed) return;
            LED={kind:kind};
            if(kind==='box'){ ed.value=$('tbtext').value; }
            tbEditPlace();
            if(kind==='label') paintTextPick();     // the pick box steps aside: the editor IS the label now
            if(kind==='note' && ed.value==='' && ed.setSelectionRange){ try { ed.setSelectionRange(0,0); } catch(e){} }
            if(ed.focus) ed.focus();
            if(kind==='box' && ed.setSelectionRange && typeof ed.value==='string'){
              try { ed.setSelectionRange(ed.value.length, ed.value.length); } catch(e){}
            } else if(ed.select) { try { ed.select(); } catch(e){} }
          }

          function tbEditHide(){
            LED=null;
            var ed=tbEditEl(); if(ed) ed.className='';
          }

          // Every letter typed on the sheet goes to the hidden bar and the box follows.
          function tbEditInput(){
            var ed=tbEditEl(); if(!ed||!LED) return;
            if(LED.kind==='box'){ $('tbtext').value=ed.value; tbLive(); tbEditPlace(); }
          }

          // ---- two presses on a number (2026-10-07) -------------------------
          //
          // "לחיצה כפולה על מספר של מידה לא פותחת עריכה." Measured in a real
          // browser (tests/browser/dbltest.js): the first press picks the
          // dimension and draws the sheet again, the element that was pressed
          // is gone, and the browser sends no click and no double click at
          // all. So two quick presses on the same number are counted HERE,
          // the way TBLAST counts them for a box of writing, and the second
          // one opens the words. A note is left to the browser's own double
          // click, as it always was.
          var LBLAST=null;     // the last press on a dimension or a label: {id, t, x, y}
          var LBDONE=0;        // when two presses last opened a label

          // A note's words are a label on the NOTES layer like any other
          // (name_texts! keys them), so the box at the side and typing over
          // them on the sheet are the label's own roads - not a bar of their
          // own (2026-10-08, "הקופסא תהיה על הכיתוב עצמו וההגדרות יהיו
          // בהגדרות טקסט"). The words sit on the note's x/y (draw_mark_note
          // centres them there), which is how the two find each other.
          function noteWords(i){
            var m=marks()[i]; if(!m || m.t!=='note') return null;
            var best=null, bd=markTextH()*2;
            eachText(function(s,paper){
              if(paper || !s.key || !/^NOTES\|/.test(s.key)) return;
              var d=Math.hypot(s.x-m.x, s.y-m.y);
              if(d<bd){ bd=d; best={key:s.key, shape:s, paper:false}; }
            });
            if(best) best.note=i;
            return best;
          }
          function noteOfText(ht){
            if(!ht || ht.paper || !/^NOTES\|/.test(String(ht.key))) return null;
            var at=null, bd=markTextH()*2;
            marks().forEach(function(m,i){
              if(m.t!=='note') return;
              var d=Math.hypot(ht.shape.x-m.x, ht.shape.y-m.y);
              if(d<bd){ bd=d; at=i; }
            });
            return at;
          }
          // What is under the mouse, as a mark: a hand dimension or a note by
          // its line and its points (hitMark) - or a note by its WORDS, whose
          // far end is further from their middle than the grab reaches.
          function markUnder(e){
            var h=hitMark(e);
            if(h) return h;
            var ni=noteOfText(hitText(e));
            return ni===null ? null : {i:ni, part:'all'};
          }

          // The label two clicks at the mouse open: any writing with a key,
          // for a hand dimension its number - wherever on the dimension he
          // pressed - and for a note its words, wherever on the note. null on
          // empty paper.
          function labelUnder(e){
            var h=markUnder(e);
            if(h && marks()[h.i].t==='note') return noteWords(h.i);
            var ht=hitText(e);
            if(!ht && h && marks()[h.i].t==='dim'){
              // on a hand dimension's LINE, not its number: still its number
              var lp=dimLabelXY(marks()[h.i]), bd=1e9;
              eachText(function(s2,paper){
                if(paper || !s2.key || !/^NOTES\|/.test(s2.key)) return;
                var d=Math.hypot(s2.x-lp[0], s2.y-lp[1]);
                if(d<bd && d<markTextH()*2){ bd=d; ht={key:s2.key, shape:s2, paper:false}; }
              });
            }
            if(ht && h && marks()[h.i].t==='dim') ht.dim=h.i;     // the words go onto the mark
            return ht;
          }

          // What a press at the mouse takes hold of, by name: a hand
          // dimension or a label. null = neither (a picture, a note, paper).
          // The same order the press itself looks in.
          function pressName(e){
            if(PICON && hitPic(e)){ var hx=hitText(e); if(!(hx && elevKey(hx.key))) return null; }
            var h=markUnder(e);
            if(h) return marks()[h.i].t==='dim' ? ('m:'+h.i) :
                         (marks()[h.i].t==='note' ? ('n:'+h.i) : null);
            var ht=hitText(e);
            return ht ? ('k:'+ht.key) : null;
          }

          // Is this press the second of two quick ones on the same number?
          // Then its words open, typed over it, and the press does nothing
          // else. The first press picked the thing up; it is put back
          // exactly where it was.
          function pressTwice(e){
            var id=pressName(e), now=Date.now(), last=LBLAST;
            var twice=!!(id && last && last.id===id && now-last.t<450 &&
                         Math.hypot(e.clientX-last.x, e.clientY-last.y)<8);
            LBLAST=(twice || !id) ? null : {id:id, t:now, x:e.clientX, y:e.clientY};
            if(!twice) return false;
            // (a note's words come through labelUnder too, 2026-10-08: until
            // then a note was left to the browser's own double click, which
            // never comes - the first press draws the sheet again and the
            // thing he pressed is gone)
            var ht=labelUnder(e);
            if(!ht) return false;
            cancelCarry();
            TDRAG=null; MDRAG=null;
            hideNoteBar();
            LBDONE=now;
            if(TXWORDS) labelEditOpen(ht); else openTextBar(ht);
            ONE=elevKey(ht.key);           // two clicks on an elevation's number: this one alone
            return true;
          }

          // Two clicks on a label: its words, typed over it. Enter keeps them
          // (a hand dimension's go onto the mark, any other's to Ruby under
          // the label's key - sendTextWords); Escape drops them.
          function labelEditOpen(hit){
            if(!TXWORDS||!hit) return;
            hideNoteBar();
            openTextBar(hit, true);
            var ed=tbEditEl(); if(!ed) return;
            ed.value=String($('txwords').value||'');
            if(!ed.value){ ed.value=String(hit.shape.text||''); }
            tbEditShow('label');
          }

          // A new note (2026-10-08): the third click done, its words are typed
          // where they will stand - no bar. Enter or a press on the sheet keeps
          // them (a note is made, exactly as the bar made one); Escape drops
          // the half-drawn note.
          function noteEditOpen(){
            if(!PEND||!PEND2||!PEND3||!VIEW) return false;
            var sf=scaleFactor(STATE.scale);
            var e2=noteEnd(PEND2, PEND3);
            var ux=e2[0]-PEND2[0], uy=e2[1]-PEND2[1], L=Math.sqrt(ux*ux+uy*uy);
            if(L<1e-9){ ux=1; uy=0; } else { ux/=L; uy/=L; }
            var off=0.7/(sf||(1/96));
            var a=screenOf(e2[0]+ux*off*0.12, e2[1]+uy*off*0.12);     // where the words begin, on the screen
            var b=screenOf(e2[0]+ux*(off*0.12+10), e2[1]+uy*(off*0.12+10));
            var sx=b[0]-a[0], sy=b[1]-a[1], SL=Math.sqrt(sx*sx+sy*sy);
            if(SL<1e-9){ sx=1; sy=0; } else { sx/=SL; sy/=SL; }
            NOTEED={ax:a[0], ay:a[1], sx:sx, sy:sy};
            var ed=tbEditEl(); if(!ed) return false;
            hideNoteBar2();
            ed.value='';
            tbEditShow('note');
            return true;
          }
          // (the three clicks are kept: hideNoteBar forgets them)
          function hideNoteBar2(){ $('notebar').className=''; EDIT=null; }

          function noteEditKeep(){
            if(!LED||LED.kind!=='note') return;
            var ed=tbEditEl();
            var t=String(ed.value||'').replace(/\s+/g,' ').trim();
            var p1=PEND, p2=PEND2, p3=PEND3;
            tbEditHide(); NOTEED=null;
            hideNoteBar();                      // and the three clicks are forgotten
            HOVER=null;
            NOTEJUST=Date.now();
            if(t && p1 && p2 && p3){
              marks().push(noteMark(p1, p2, p3, t, STATE.note_arrow!==false, scaleFactor(STATE.scale)));
              SEL=marks().length-1;
              NOTENEW=SEL;                      // its settings go to the side when the sheet comes back
              push();
            }
            render(); showMarks();
          }

          function noteEditDrop(){
            if(!LED||LED.kind!=='note') return;
            tbEditHide(); NOTEED=null;
            hideNoteBar(); HOVER=null;
            render(); showMarks();
          }

          function labelEditKeep(){
            if(!LED||LED.kind!=='label'){ return; }
            var ed=tbEditEl();
            $('txwords').value=String(ed.value||'');
            tbEditHide();
            sendTextWords();
            closeTextBar();
          }

          // Done: one step for Ctrl+Z, and Ruby is told once. Emptied = thrown away.
          function tbSave(){
            if(!TBED) return;
            var ed=TBED, tx=(STATE.texts||[])[ed.n];
            if(tx){
              $('tbtext').value=String($('tbtext').value).replace(/\s+$/,'');
              tbLive();
            }
            var empty=!tx || tbClean(tx.text).replace(/\s+/g,'')==='';
            if(empty && ed.fresh){ tbCancel(); render(); showMarks(); return; }
            TBED=null;
            $('tbbar').className='';
            tbEditHide();
            var id='t:'+ed.n;
            if(empty){ STATE.texts.splice(ed.n,1); id=null; tbRebuild(); }
            if(picsSnap()===ed.was){ BSEL=id; render(); showMarks(); return; }     // nothing was changed
            if(UNDOON){ UNDO.push({g:++UGROUP, pics:ed.was}); if(UNDO.length>300) UNDO.shift(); }
            // the arrow is back in his hand with the box picked, so the very
            // next thing he does can be to move it
            if(MODE!=='hand') setMode('hand');
            BSEL=id;
            push(); render(); showMarks();
          }

          // Escape, or Cancel: as if the bar had never been opened.
          function tbCancel(){
            if(!TBED) return;
            var ed=TBED;
            TBED=null;
            $('tbbar').className='';
            tbEditHide();
            picsBack(ed.was);
            tbRebuild();
            if(ed.fresh) BSEL=null;
          }

          // A click with the T tool: on a box of writing it opens that box, on
          // empty paper it starts a new one there.
          function textClick(e){
            if(!TXTON||TBED) return;
            var p=mouseAt(e), a=picArea();
            if(!p||!PAGE||!LIVEK||!a) return;
            if((STATE.hidden||[]).indexOf('TEXT')>=0){
              $('markinfo').textContent='השכבה TEXT כבויה. הדלק אותה תחת "שכבות" כדי לכתוב.';
              return;
            }
            var hp=hitPic(e);
            if(hp && hp.txt){ tbOpen(parseInt(String(hp.pic).slice(2),10)); return; }
            var px=p[0]/LIVEK, py=PAGE.height-p[1]/LIVEK, h0=tbHeight(1,TXR.pt);
            // inside what the margins leave, with room for a line under it
            px=Math.min(Math.max(px, a[0]), a[0]+a[2]-PIC_MIN);
            py=Math.min(Math.max(py, a[1]+h0), a[1]+a[3]);
            tbOpen(null,[px,py]);
          }

          // The pointer over the handle: the same round arrow, so it says "turn".
          function turnCursor(){
            var s='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="-12 -12 24 24">'+
                  '<g fill="none" stroke-linecap="round" stroke-linejoin="round">'+
                  '<path d="M-6.5 4.2 A7.7 7.7 0 1 1 4.2 6.5 M4.2 6.5 L4.8 1.8 M4.2 6.5 L8.8 5.9" stroke="#fff" stroke-width="4.2"/>'+
                  '<path d="M-6.5 4.2 A7.7 7.7 0 1 1 4.2 6.5 M4.2 6.5 L4.8 1.8 M4.2 6.5 L8.8 5.9" stroke="#000" stroke-width="1.8"/>'+
                  '</g></svg>';
            return 'url("data:image/svg+xml;utf8,'+encodeURIComponent(s)+'") 12 12, pointer';
          }

          function $(id){ return document.getElementById(id); }

          // A size he set by hand (STATE.scale_f, paper inches to the foot) wins
          // over the scale named in the list - see the box, below.
          function scaleFactor(lbl){
            if(BOXON && STATE && STATE.scale_f>0) return STATE.scale_f/12;
            return SF[lbl] || 0.25/12;
          }

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
              // writing on the plan carries the sheet's turn as well as its own
              var rdeg = (s.rotation||0) + (s.__paper ? 0 : VROT);
              var rot = rdeg ? ' transform="rotate('+(-rdeg)+','+px.toFixed(1)+','+py.toFixed(1)+')"' : '';
              o.push('<text x="'+px.toFixed(1)+'" y="'+py.toFixed(1)+'" font-family="'+esc(fontCss(s.text, s.font))+'"'+
                     ' font-size="'+fs.toFixed(1)+'" text-anchor="'+anchor+'" dominant-baseline="'+base+
                     '" fill="'+(/^#[0-9a-f]{6}$/i.test(String(s.color||'')) ? s.color : '#000')+'"'+(s.bold?' font-weight="700"':'')+(s.italic?' font-style="italic"':'')+
                     (s.underline?' text-decoration="underline"':'')+rot+'>'+esc(s.text)+'</text>');
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
            } else if(s.type==='image' && s.placed){
              // A picture in a box of its own: the part of it that is seen
              // fills the box, and the box is turned about its middle. The
              // same numbers plan_pdf prints (draw_placed_image).
              var pa=tp(s.x,s.y), PX=pa[0]*k, PY=(ph-pa[1]-s.h)*k, PW=s.w*k, PH=s.h*k;
              var cr=s.crop||[0,0,0,0], piw=(s.iw>0 ? s.iw : 1000), pih=(s.ih>0 ? s.ih : 1000), prot=+s.rot||0;
              o.push(prot ? ('<g transform="rotate('+(-prot)+','+(PX+PW/2).toFixed(2)+','+(PY+PH/2).toFixed(2)+')">') : '<g>');
              var pu=URLS[s.path];
              if(pu){
                o.push('<svg x="'+PX.toFixed(2)+'" y="'+PY.toFixed(2)+'" width="'+PW.toFixed(2)+'" height="'+PH.toFixed(2)+
                       '" viewBox="'+(cr[0]*piw).toFixed(3)+' '+(cr[3]*pih).toFixed(3)+' '+
                       (piw*(1-cr[0]-cr[2])).toFixed(3)+' '+(pih*(1-cr[1]-cr[3])).toFixed(3)+
                       '" preserveAspectRatio="none"><image width="'+piw+'" height="'+pih+
                       '" preserveAspectRatio="none" href="'+pu+'"/></svg>');
              } else {
                o.push('<rect x="'+PX.toFixed(1)+'" y="'+PY.toFixed(1)+'" width="'+PW.toFixed(1)+'" height="'+PH.toFixed(1)+
                       '" fill="none" stroke="#bbb" stroke-dasharray="3 3"/>');
              }
              o.push('</g>');
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
            if(live){ VIEW=null; LIVEK=k; }
            // VROT is the turn of the sheet being DRAWN. A little sheet in the
            // page strip is drawn after the big one, and a picture sheet has no
            // turn - it used to leave 0 behind, and the words of a number on a
            // turned drawing then opened a quarter turn off (2026-10-07,
            // measured: tests/browser/edpos.js). A little sheet hands it back.
            var vkeep=VROT;
            VROT=0;
            if(v){
              var sf=scaleFactor(STATE.scale);
              var cx=v.x+v.w/2, cy=v.y+v.h/2;
              // an editor drawing's sheet (2026-10-07): seen whole, at the scale
              // and place Ruby gave ITS view - not the plan's (dOx/dOy); the
              // plan is drawn from STATE.origin, read as it is drawn
              var dOx=null, dOy=null;
              if(pg.kind==='drawing'){ sf=SF[v.scale]||(0.25/12); dOx=v.origin_x||0; dOy=v.origin_y||0; }
              var toPaper=function(mx,my){
                var ox=(dOx===null) ? STATE.origin_x : dOx, oy=(dOy===null) ? STATE.origin_y : dOy;
                return [cx+(mx-ox)*sf, cy+(my-oy)*sf];
              };
              // a turned drawing: the same, turned about the middle of the frame
              var vt=(pg.kind==='drawing') ? {deg:0, c:1, s:0} : viewTurn();
              VROT=vt.deg;
              if(vt.deg){
                var rc=vt.c, rs=vt.s;
                toPaper=function(mx,my){
                  var ox=(dOx===null) ? STATE.origin_x : dOx, oy=(dOy===null) ? STATE.origin_y : dOy;
                  var dx=(mx-ox)*sf, dy=(my-oy)*sf;
                  return [cx+dx*rc-dy*rs, cy+dx*rs+dy*rc];
                };
              }
              // remembered so a click on the screen can be turned back into a
              // place in the house
              if(live && pg.kind!=='drawing') VIEW={k:k, sf:sf, cx:cx, cy:cy, toPaper:toPaper, rot:vt.deg, rc:vt.c, rs:vt.s};
              var cid='vclip'+(live?'':'t'+(pg.name||'').replace(/[^A-Za-z0-9]/g,''));
              // a box that turns as a whole: the clip and the frame are the
              // rectangle turned about its middle (2026-10-07, stage 5)
              var vtr=(v.box_turn && ROTON && vt.deg) ? (' transform="rotate('+(-vt.deg)+','+(cx*k).toFixed(2)+','+((ph-cy)*k).toFixed(2)+')"') : '';
              o.push('<clipPath id="'+cid+'"><rect x="'+(v.x*k).toFixed(1)+'" y="'+((ph-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+'"'+vtr+'/></clipPath>');
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
                     '" fill="none" stroke="#bcd" stroke-width="1" stroke-dasharray="5 4"'+vtr+'/>');
            }

            (pg.layers||[]).forEach(function(l){
              if(STATE.hidden.indexOf(l.name)>=0) return;
              o.push(layerSVG(l.shapes,same,k,ph,true));
            });

            if(live){
              // The box of writing he picked, or is writing in: a thin frame,
              // so a box of two words is still a box he can see. On the screen
              // only - it is never on the paper.
              var tfid=TBED ? ('t:'+TBED.n) : ((BSEL!==null && String(BSEL).charAt(0)==='t') ? BSEL : null);
              if(tfid!==null) pageTexts().forEach(function(te){
                if(te.pic!==tfid) return;
                var fx=te.x*k, fy=(ph-te.y-te.h)*k, fw=Math.max(te.w*k,2), fh=Math.max(te.h*k,2);
                o.push('<rect id="tbframe" x="'+fx.toFixed(1)+'" y="'+fy.toFixed(1)+'" width="'+fw.toFixed(1)+
                       '" height="'+fh.toFixed(1)+'" fill="none" stroke="#1f6feb" stroke-width="1" stroke-dasharray="5 4"'+
                       (te.rot ? (' transform="rotate('+(-te.rot)+','+(fx+fw/2).toFixed(1)+','+(fy+fh/2).toFixed(1)+')"') : '')+'/>');
              });
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
                    if(ep){ var en=noteEnd(PEND2, ep); dash(SP(PEND2[0],PEND2[1]), SP(en[0],en[1]), 1.5); }
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
            if(!live) VROT=vkeep;
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
            paintDraw();
            paintRot();
            paintTextPick();
            tbEditPlace();
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
            // never smaller than the window (2026-10-07, "אין למה שתהיה אפשרות
            // להקטין את הדף"): "fits" is as far out as the wheel goes
            z = Math.min(Math.max(z, 1), ZMAX);
            if(z < 1 + 1e-6) z = 1;                    // 1.15 in and 1.15 out is "fits", not a hair over
            var stage = $('stage');
            // All the way out = the whole sheet, in the middle of the window
            // (2026-10-08). Shrinking towards the mouse down to "fits" left
            // the sheet wherever that put it - the top off the window in his
            // picture, with nothing to scroll because the sheet fits - so at
            // "fits" the place given to it is taken back and the layout
            // centres it, the way it opens.
            if(z===1 && FITCENTRE){
              setZoom(1);
              var w1=$('sheetWrap');
              if(w1 && w1.style){ w1.style.marginLeft=''; w1.style.marginTop=''; w1.style.marginRight=''; w1.style.marginBottom=''; }
              stage.scrollLeft = 0;
              stage.scrollTop  = 0;
              paintRot();
              return;
            }
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
              paintRot();
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
            paintRot();                              // the sheet has just been given a new place
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
            if(!VIEW.rot)
              return [(px-VIEW.cx)/VIEW.sf+STATE.origin_x,    // model inches
                      (py-VIEW.cy)/VIEW.sf+STATE.origin_y];
            // a turned drawing: the turn is taken back out
            var qx=(px-VIEW.cx)/VIEW.sf, qy=(py-VIEW.cy)/VIEW.sf;
            return [qx*VIEW.rc+qy*VIEW.rs+STATE.origin_x,
                    -qx*VIEW.rs+qy*VIEW.rc+STATE.origin_y];
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
            var v=pageView(); if(!v) return;
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
            var v=pageView(); if(!v) return null;
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

          // ---- drawing loose lines (2026-10-07) ----------------------------
          //
          // "הוספת קווים ע"י ציור." Asked which way, he said both:
          //   line    two clicks make one line; the next click starts a new one
          //   chain   every click carries on from the one before, the way the
          //           Line tool in SketchUp does. Escape ends the run, and so
          //           does coming back to the point it started from.
          //
          // A drawn line is a loose line like any other - a two-point shape on
          // the END of the SITE layer, the same number in Ruby's list - so the
          // eraser, the select arrow, Delete and Ctrl+Z reach it with nothing
          // written for them here.
          //
          // The iron law in CLAUDE.md, line by line:
          //   Escape    drops the half-drawn line, gives the arrow back (escapeAll)
          //   Ctrl+Z    takes the last drawn line off again, one a press (undoLast)
          //   the view  after a click: same zoom, same place, same tool in the hand
          //   at once   the rubber line and the ring are two elements of their
          //             own, painted without drawing the sheet again (paintDraw)
          //   locking   corners and ends of lines (green), middles (cyan),
          //             anywhere along a line (magenta) - and the click lands
          //             on exactly the point the ring showed
          var LINEDRAW=true;
          var DRAWSNAP=null;      // {p:[x,y], kind:'end'|'mid'|'edge'|null}: where a click would land now
          var CHAIN0=null;        // where the run being drawn started

          // The colours every tool in the plugin uses for where it locked.
          function snapColor(kind){
            return kind==='end' ? '#2fbf5f' : kind==='mid' ? '#00b8d4' : kind==='edge' ? '#d63fd6' : null;
          }

          // Every straight piece drawn on the plan right now - walls, loose
          // lines, anything on a layer that is switched on.
          function eachSeg(fn){
            if(!DOC||!STATE||!PAGE) return;
            var v=pageView(); if(!v) return;
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
            if(!cv) return;
            var hid=STATE.hidden||[];
            cv.layers.forEach(function(l){
              if(hid.indexOf(l.name)>=0) return;
              var sh=l.shapes||[];
              for(var i=0;i<sh.length;i++){
                var s=sh[i];
                if(s.type==='line'){ fn(s.x1,s.y1,s.x2,s.y2); continue; }
                var q=s.points; if(!q||q.length<2) continue;
                for(var j=0;j<q.length-1;j++) fn(q[j][0],q[j][1],q[j+1][0],q[j+1][1]);
                if((s.closed||s.type==='polygon')&&q.length>2)
                  fn(q[q.length-1][0],q[q.length-1][1],q[0][0],q[0][1]);
              }
            });
          }

          // p is where the mouse really is, in model inches. Returns the point
          // a click there lands on, and what it locked to. A corner or an end
          // wins over a middle, a middle over "somewhere along the line".
          //
          // Worked out in model inches, with the reach turned into inches from
          // SNAP_PX - so the pull is the same on the screen at any zoom, and
          // fifteen thousand lines are thrown out by four comparisons each
          // instead of being carried to the screen one point at a time.
          function drawSnap(p){
            if(!p||!VIEW) return {p:p||null, kind:null};
            var tol=SNAP_PX/(VIEW.sf*VIEW.k);
            var x=p[0], y=p[1];
            var e=null, ed=tol, m=null, md=tol, g=null, gd=tol*0.75;
            eachSeg(function(ax,ay,bx,by){
              if((ax<x-tol&&bx<x-tol)||(ax>x+tol&&bx>x+tol)||
                 (ay<y-tol&&by<y-tol)||(ay>y+tol&&by>y+tol)) return;
              var d=Math.hypot(ax-x,ay-y); if(d<ed){ ed=d; e=[ax,ay]; }
              d=Math.hypot(bx-x,by-y);     if(d<ed){ ed=d; e=[bx,by]; }
              var mx=(ax+bx)/2, my=(ay+by)/2;
              d=Math.hypot(mx-x,my-y);     if(d<md){ md=d; m=[mx,my]; }
              var vx=bx-ax, vy=by-ay, L=vx*vx+vy*vy;
              if(L>0){
                var t=((x-ax)*vx+(y-ay)*vy)/L;
                if(t>0&&t<1){
                  var fx=ax+vx*t, fy=ay+vy*t;
                  d=Math.hypot(fx-x,fy-y); if(d<gd){ gd=d; g=[fx,fy]; }
                }
              }
            });
            if(e) return {p:e, kind:'end'};
            if(m) return {p:m, kind:'mid'};
            if(g) return {p:g, kind:'edge'};
            return {p:p, kind:null};
          }

          // The ring on the point the next click will land on, and the line
          // being pulled out to it. Painted straight onto the drawing, like
          // the eraser's highlight: going through render() on every move of
          // the mouse would build every line on the sheet again.
          function paintDraw(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#drawhi');
            if(old) svg.removeChild(old);
            if((MODE!=='line'&&MODE!=='chain')||!VIEW||!DRAWSNAP||!DRAWSNAP.p) return;
            var NS='http://www.w3.org/2000/svg';
            var g=document.createElementNS(NS,'g');
            g.setAttribute('id','drawhi');
            g.setAttribute('pointer-events','none');
            var q=screenOf(DRAWSNAP.p[0],DRAWSNAP.p[1]);
            if(PEND){
              var a=screenOf(PEND[0],PEND[1]);
              var ln=document.createElementNS(NS,'line');
              ln.setAttribute('x1',a[0].toFixed(1)); ln.setAttribute('y1',a[1].toFixed(1));
              ln.setAttribute('x2',q[0].toFixed(1)); ln.setAttribute('y2',q[1].toFixed(1));
              ln.setAttribute('stroke','#1f6feb');
              ln.setAttribute('stroke-width','1.5');
              g.appendChild(ln);
            }
            var col=snapColor(DRAWSNAP.kind);
            if(col){
              var c=document.createElementNS(NS,'circle');
              c.setAttribute('cx',q[0].toFixed(1)); c.setAttribute('cy',q[1].toFixed(1));
              c.setAttribute('r','7');
              c.setAttribute('fill','none');
              c.setAttribute('stroke',col);
              c.setAttribute('stroke-width','2.5');
              g.appendChild(c);
            }
            svg.appendChild(g);
          }

          // One more loose line on the sheet, from a to b. On the sheet HERE
          // at once, and Ruby is told what it is and how many lines there
          // were, exactly as the eraser tells it what went. false = not added.
          function addSiteLine(a,b){
            if(a[0]===b[0]&&a[1]===b[1]) return false;
            var lay=siteLayer();
            if(!lay && rawSiteLayer()){
              $('markinfo').textContent='השכבה SITE כבויה. הדלק אותה תחת "שכבות" כדי לצייר.';
              return false;
            }
            var pts=[[a[0],a[1]],[b[0],b[1]]];
            var s={type:'polyline', points:pts, closed:false, weight:0.01};
            if(!lay){
              // No loose line on this sheet yet, so there is no layer to put
              // it on: Ruby makes one and sends the sheet. The step is still
              // written down, so Ctrl+Z takes this line off like any other.
              var n0=USITE_N||0;
              if(UNDOON){ UNDO.push({g:++UGROUP, added:[{i:n0, s:s}]}); if(UNDO.length>300) UNDO.shift(); }
              USITE_N=n0+1;
              sketchup.add_site_line(JSON.stringify({p:pts}));
              return true;
            }
            var n=lay.shapes.length;
            lay.shapes.push(s);
            if(UNDOON){ UNDO.push({g:++UGROUP, added:[{i:n, s:s}]}); if(UNDO.length>300) UNDO.shift(); }
            USITE_N=lay.shapes.length;
            STATE.site_count=lay.shapes.length;
            render();
            sketchup.add_site_line(JSON.stringify({p:pts, quiet:true, n:n}));
            return true;
          }

          // One click of either drawing tool. p = where the mouse is, in
          // model inches. The point used is the one the ring showed.
          function drawClick(p){
            if(!LINEDRAW) return;
            var ds=drawSnap(p);
            // a hundredth of an inch, like every other loose line
            var pt=[Math.round(ds.p[0]*100)/100, Math.round(ds.p[1]*100)/100];
            DRAWSNAP={p:pt, kind:ds.kind};
            if(!PEND){
              PEND=pt; CHAIN0=pt.slice();
              paintDraw(); showMarks();
              return;
            }
            // a second click on the very same spot is not a line
            var a=screenOf(PEND[0],PEND[1]), b=screenOf(pt[0],pt[1]);
            if(Math.hypot(a[0]-b[0],a[1]-b[1])<2) return;
            if(!addSiteLine(PEND,pt)) return;
            // line: done - the next click starts a new one.
            // chain: the next line starts where this one ended, unless it has
            // just come back to where the run began: the shape is closed.
            var closed = CHAIN0 && pt[0]===CHAIN0[0] && pt[1]===CHAIN0[1];
            if(MODE==='chain' && !closed){ PEND=pt; }
            else { PEND=null; CHAIN0=null; }
            paintDraw(); showMarks();
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
          // An elevation's number (2026-10-08, 13:26): ONE click = the look of all of them,
          // TWO clicks = this one alone, its size and its words. ONE is true while the panel
          // is on a number opened by two clicks; Ruby is told so with every setting.
          var ONE=false;
          function elevKey(k){ return String(k||'').indexOf('ELEV_DIMS|')===0; }
          var TXWORDS=true;  // told by Ruby: his own words may replace a label's
          // The words box: a hand dimension's go onto the mark, any other
          // label's go to Ruby under the label's key. Empty = back to its own.
          function sendTextWords(){
            if(!TSEL||!TXWORDS) return;
            var t=String($('txwords').value||'').replace(/\s+/g,' ').trim();
            if(TSEL.dim!==undefined && TSEL.dim!==null && marks()[TSEL.dim]){
              var m=marks()[TSEL.dim];
              if(t){ if(m.label===t) return; m.label=t; }
              else { if(m.label===undefined) return; delete m.label; }
              push(); render(); showMarks();
              return;
            }
            // a note's words live on the note (2026-10-08); emptied = thrown
            // away, as the note bar always had it
            if(TSEL.note!==undefined && TSEL.note!==null && marks()[TSEL.note] && marks()[TSEL.note].t==='note'){
              var nm=marks()[TSEL.note];
              if(t){ if(nm.text===t) return; nm.text=t; }
              else { marks().splice(TSEL.note,1); SEL=null; SELS=[]; closeTextBar(); }
              push(); render(); showMarks();
              return;
            }
            var cur=textMarks()[TSEL.key]||{};
            if((cur.text||'')===t) return;
            if(!cur.text && t===String(TSEL.shape.text||'')) return;   // its own words again: nothing to say
            sketchup.set_text_mark(JSON.stringify({key:TSEL.key, text:t}));
          }
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
            // a sheet with no drawing on it (a picture sheet) has no VIEW - its writing is
            // on the paper and LIVEK is the same pixels to the inch (13:19, measured: view null,
            // so nothing on an elevation's sheet could be hit)
            var K = VIEW ? VIEW.k : LIVEK;
            var h = s.h * (paper ? 1 : scaleFactor(STATE.scale));  // paper inches
            var w = Math.max(String(s.text||'').length * h * 0.55, h * 0.8);
            var p = paper ? [s.x, s.y] : VIEW.toPaper(s.x, s.y);
            var cx = p[0], cy = p[1];
            // Writing put straight on the sheet hangs off its start point;
            // writing on the plan is centred on it. Same rule as shapeSVG.
            if(paper){ cx = p[0] + w/2; cy = p[1] + h/2; }
            // standing upright (an elevation's height, 2026-10-08): it runs UP from its
            // start point and lies to the LEFT of it
            if(paper && Math.abs(((+s.rotation||0) % 360 + 360) % 360 - 90) < 1){
              cx = p[0] - h/2; cy = p[1] + w/2;
              return { x:(cx - h/2)*K, y:(PAGE.height - cy - w/2)*K, w:h*K, h:w*K };
            }
            return { x:(cx - w/2)*K, y:(PAGE.height - cy - h/2)*K,
                     w:w*K, h:h*K };
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
            var p=mouseAt(e); if(!p||!PAGE||!(VIEW||LIVEK)) return null;
            var X=p[0], Y=p[1], best=null, ba=Infinity;
            eachText(function(s,paper){
              if(!paper && !VIEW) return;
              var b=textBox(s,paper);
              if(X<b.x||X>b.x+b.w||Y<b.y||Y>b.y+b.h) return;
              var a=b.w*b.h;             // the tightest box wins, not the first
              if(a<ba){ ba=a; best={key:s.key, shape:s, paper:paper}; }
            });
            return best;
          }

          function textMarks(){ return STATE.text_marks||(STATE.text_marks={}); }

          // ---- the settings of a box of writing, at the side (2026-10-07) ----
          //
          // He sent a picture of himself typing in a box of writing with the
          // panel at the side greyed out: "כשאני רוצה להקליד פה זה לא נותן לי
          // לשחק עם ההגדרות של הכיתוב." So the SAME panel a label has - size,
          // B, I, U, colour - works on the box of writing he has picked or is
          // typing in:
          //   the size     in POINTS here (a label's is a percentage of its own)
          //   B I U        on the whole box
          //   the colour   of the whole box; black is "none"
          //   the words    are typed on the sheet, so their box is put away
          // While he is typing, a setting is part of that one piece of typing
          // (one step for Ctrl+Z, kept or dropped with the words) and the
          // keyboard goes straight back to the box. With a box only picked it
          // is a step of its own and Ruby is told once.
          var TXSTYLE=true;    // told by Ruby
          var PGORDER=true;    // told by Ruby: a sheet in the page list can be dragged up or down
          var DRAWNON=true;    // told by Ruby: an editor drawing can be put on a sheet of its own
          var TXFONT=true;     // told by Ruby: a lettering of its own on writing
          var DRAFTS=[];       // the editor's drawings on offer: [{i, name}]
          var PGDRAG=null, PGJUST=false;
          var TXB=null;        // the box of writing the panel is on, by its number; null = none

          // The box the panel belongs to now: the one being typed in, else the picked one.
          function boxBarWant(){
            if(!TXSTYLE||!TXTON||TSEL||!STATE) return null;
            var n=null;
            if(TBED) n=TBED.n;
            else if(BSEL!==null && String(BSEL).charAt(0)==='t') n=parseInt(String(BSEL).slice(2),10);
            return (n!==null && (STATE.texts||[])[n]) ? n : null;
          }

          // The size box counts in POINTS for every piece of writing - a box of
          // writing, a label of the plugin's own, a note - since 2026-10-08:
          // "למה הוא מראה לי כאן את גודל הכיתוב כ-100 אחוז ולא כמו הכיתוב בקופסא
          // שמראה לי במספרים... כל הכיתוב בתוכנה יהיה תחת אותם הגדרות". A
          // label's size is still KEPT as a percentage of its built height
          // (text_marks pct - Ruby's unit, and the group sizes' unit); the
          // window turns points into that and back (labelPt, sendTextMark).
          function boxBarUnits(box){
            var u=$('txunit'); if(u) u.textContent = 'pt';
            var sz=$('txsize');
            if(sz){
              sz.title = 'גודל האותיות, בנקודות';
              if(sz.setAttribute){
                sz.setAttribute('min', TXR.pt_min);
                sz.setAttribute('max', TXR.pt_max);
                sz.setAttribute('step', 1);
              }
            }
            var wb=$('txwords'); if(wb && wb.style) wb.style.display = (box || !TXWORDS) ? 'none' : '';
          }

          // A label's size in points: its cap height (model inches on the plan,
          // paper inches on a sheet) brought to the paper, then to the font
          // size plan_pdf sets it at (h / cap). built = at the height it was
          // built with, which is what 100% means.
          function labelPaperSf(paper){ return paper ? 1 : (VIEW ? VIEW.sf : scaleFactor(STATE.scale)); }
          function labelPt(shape, paper, built){
            var h = built ? ((shape.h0!==undefined && shape.h0!==null) ? +shape.h0 : +shape.h) : +shape.h;
            return h * labelPaperSf(paper) / TXR.cap * 72;
          }

          // Keeps the panel in step with what is picked. Called every time the
          // handles are painted, so it can never go on showing a box he let go.
          function paintBoxBar(){
            var bar=$('textbar'); if(!bar) return;
            var n=boxBarWant();
            if(n===null){
              if(TXB!==null){ TXB=null; boxBarUnits(false); if(!TSEL) bar.className=''; }
              return;
            }
            var tx=STATE.texts[n], sy=tbStyle(tx), first=(TXB!==n), act=document.activeElement;
            TXB=n;
            if(act!==$('txsize')) $('txsize').value=Math.round((+tx.pt||TXR.pt)*10)/10;
            $('txbold').className   = 'tool'+(sy.bold?' on':'');
            $('txitalic').className = 'tool'+(sy.italic?' on':'');
            $('txunder').className  = 'tool'+(sy.underline?' on':'');
            if(act!==$('txcolor')) $('txcolor').value = sy.color || '#000000';
            $('txwhat').textContent = tbClean(tx.text).split('\n')[0].slice(0,22);
            if($('txfont') && act!==$('txfont')) fontPick((sy.font && TXR.fonts && TXR.fonts[sy.font]) ? sy.font : '');
            boxBarUnits(true);
            bar.className='on';
            if(first) openSection('text', true);      // the box at the side opens on it
          }

          // One or more settings of that box: {pt, bold, italic, underline,
          // color}. false = the panel is not on a box of writing (a label's
          // own road is taken instead).
          function boxBarSet(what){
            var n=boxBarWant(); if(n===null) return false;
            var tx=STATE.texts[n], typing=!!TBED, was=typing ? null : picsSnap();
            ['bold','italic','underline'].forEach(function(k){
              if(what[k]!==undefined){ if(what[k]) tx[k]=true; else delete tx[k]; }
            });
            if(what.color!==undefined){
              var c=String(what.color||'').toLowerCase();
              if(/^#[0-9a-f]{6}$/.test(c) && c!=='#000000') tx.color=c; else delete tx.color;
            }
            if(what.font!==undefined){
              var fo=String(what.font||'').trim();
              if(TXFONT && fo && fo.length<=40) tx.font=fo; else delete tx.font;
            }
            var pt=null;
            if(what.pt!==undefined){
              pt=parseFloat(what.pt);
              if(!isFinite(pt)||pt<=0) pt=+tx.pt||TXR.pt;
              pt=Math.min(TXR.pt_max, Math.max(TXR.pt_min, pt));
            }
            if(typing){
              // part of the typing: the box follows at once (tbLive reads the
              // size from the hidden bar), and he goes on typing
              if(pt!==null) $('tbsize').value=pt;
              tbLive();
              tbEditPlace();
              paintBoxBar();
              var ed=tbEditEl();
              if(ed && ed.focus && what.pt===undefined) ed.focus();
              return true;
            }
            // bigger letters, wider box: the lines break where they did. And
            // bold letters are wider, so the lines are laid again either way.
            var w=tx.box[2];
            if(pt!==null && pt!==tx.pt){ w=w*pt/tx.pt; tx.pt=pt; }
            tbFit(tx,w);
            var a=picArea();
            if(a){
              var r=tbHold({x:tx.box[0], y:tx.box[1], w:tx.box[2], h:tx.box[3], rot:(+tx.rot||0), pt:tx.pt}, a);
              tx.box=[r.x,r.y,r.w,r.h]; tx.pt=r.pt;
            }
            tbRebuild();
            if(picsSnap()===was){ paintBoxBar(); return true; }      // nothing was changed
            if(UNDOON){ UNDO.push({g:++UGROUP, pics:was}); if(UNDO.length>300) UNDO.shift(); }
            push(); render(); showMarks();
            return true;
          }

          function openTextBar(hit, quiet){
            TSEL=hit;
            TXB=null; boxBarUnits(false);       // the panel is a LABEL'S now: its size is a percentage
            var m=textMarks()[hit.key]||{};
            // What it is RIGHT NOW, in points - so the number in the box is
            // the size on the sheet and he is never editing blind.
            var shown = Math.round(labelPt(hit.shape, hit.paper)*10)/10;
            $('txsize').value = isFinite(shown)&&shown>0 ? shown : TXR.pt;
            $('txbold').className   = 'tool'+(hit.shape.bold?' on':'');
            $('txitalic').className = 'tool'+(hit.shape.italic?' on':'');
            $('txunder').className  = 'tool'+(hit.shape.underline?' on':'');
            $('txcolor').value = /^#[0-9a-f]{6}$/i.test(String(hit.shape.color||'')) ? String(hit.shape.color).toLowerCase() : '#000000';
            if($('txfont')) fontPick((hit.shape.font && TXR.fonts && TXR.fonts[hit.shape.font]) ? hit.shape.font : '');
            $('txwhat').textContent = String(hit.shape.text||'').slice(0,22);
            // His own words for this label (2026-10-07). A hand dimension keeps
            // them on the MARK itself (label), so they survive the dimension
            // being stretched; every other label keeps them under its key.
            var wb=$('txwords');
            // a note (2026-10-08) keeps its words on the mark, like a hand dimension
            var nt=(hit.note!==undefined && hit.note!==null && marks()[hit.note] && marks()[hit.note].t==='note') ? marks()[hit.note] : null;
            if(wb){
              var hd=(hit.dim!==undefined && hit.dim!==null) ? marks()[hit.dim] : null;
              wb.value = hd ? (hd.label||'') : nt ? (nt.text||'') : (m.text||String(hit.shape.text||''));
              wb.placeholder = nt ? 'מה כתוב' : (hd || /^(DIMENSIONS|NOTES)\|/.test(String(hit.key))) ? String(hit.shape.text||'') : 'מה כתוב';
              if(wb.style) wb.style.display = TXWORDS ? '' : 'none';
            }
            // a note's own setting: the head on its leader
            var nr=$('txnote'); if(nr && nr.style) nr.style.display = nt ? '' : 'none';
            if(nt) $('txarrow').className = 'tool'+(nt.arrow===false ? '' : ' on');
            $('textbar').className='on';
            openSection('text', true);          // the box at the side opens on the label
            placeTextBar();
            paintTextPick();
            // from two clicks the size box is ready to type in; from ONE click
            // (quiet) the keyboard stays with the sheet, so the arrows still nudge
            if(!quiet){ $('txsize').focus(); $('txsize').select(); }
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
            TSEL=null; ONE=false;
            var nr=$('txnote'); if(nr && nr.style) nr.style.display='none';
            if(LED && (LED.kind==='label' || LED.kind==='note')){ tbEditHide(); NOTEED=null; }
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
            if(!TBAR){ el.style.transform=''; return; }     // it sits in the side panel now
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
            if(!TSEL||!(VIEW||(TSEL.paper&&LIVEK))||!PAGE) return;
            // The document is rebuilt from the model on every change, so the
            // shape object we are holding is a ghost the moment Ruby answers.
            // Find the label by its KEY again - that is what the key is for.
            if(!TDRAG && !TCARRY){
              var want=TSEL.key, found=null;
              eachText(function(s,paper){
                if(!found && s.key===want) found={key:s.key, shape:s, paper:paper};
              });
              if(found){ found.dim=TSEL.dim; found.note=TSEL.note; TSEL=found; }   // (the mark the words belong to rides along)
            }
            var b=textBox(TSEL.shape, TSEL.paper);
            // while it is being shoved, the box follows the mouse even though
            // the writing itself cannot move until Ruby redraws it
            var tc = TDRAG || TCARRY;
            if(tc){
              b.x += (tc.dx*VIEW.rc-tc.dy*VIEW.rs)*VIEW.sf*VIEW.k;
              b.y -= (tc.dx*VIEW.rs+tc.dy*VIEW.rc)*VIEW.sf*VIEW.k;      // paper y is up, screen y is down
            }
            // while its words are being typed over it there is ONE box, the editor
            if(LED && LED.kind==='label') return;
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
            // Typed in points; kept as a percentage of the built size. A zero,
            // a minus or nonsense means the normal size, not the 25% floor
            // (see t46), and the box then shows the size that was really set.
            var v=parseFloat($('txsize').value);
            var pt0=labelPt(TSEL.shape, TSEL.paper, true);
            var pct=(isFinite(v)&&v>0&&isFinite(pt0)&&pt0>0) ? Math.round(v/pt0*100) : 100;
            pct=Math.min(400,Math.max(25,pct));
            $('txsize').value=(isFinite(pt0)&&pt0>0) ? Math.round(pt0*pct/100*10)/10 : v;
            var out={ key:TSEL.key, pct:pct,
                      bold:$('txbold').className.indexOf('on')>=0,
                      italic:$('txitalic').className.indexOf('on')>=0,
                      underline:$('txunder').className.indexOf('on')>=0,
                      color:String($('txcolor').value||'#000000').toLowerCase(),
                      font:($('txfont') ? String($('txfont').value||'') : '') };
            if(extra) for(var k in extra) out[k]=extra[k];
            if(ONE) out.one=true;
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

          // What a hand dimension's number reads: his own words if he wrote
          // any, else the measured length the way Ruby prints it (feet and
          // inches to the nearest eighth, the sum fmt_feet does).
          function dimLabelText(m){
            if(TXWORDS && m.label) return String(m.label);
            // the same sum as PlanGenerator.fmt_feet: inches to a tenth
            var L=dimLine(m), len=L[6], ft=Math.floor(len/12), inch=Math.round((len-ft*12)*10)/10;
            if(inch>=12){ ft+=1; inch=0; }
            var is=(inch%1===0) ? String(inch) : inch.toFixed(1);
            return ft>0 ? (ft+"'-"+is+'"') : (is+'"');
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
          function probeClick(e, what){
            try {
              var p=mouseAt(e), am=atMouse(e);
              var h=null, ht=null, hs=null, hp=null;
              try { var pq=(PICON ? hitPic(e) : null); hp=pq ? pq.pic : null; } catch(err){ hp='ERROR '+String(err); }
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
                what:(what||'down'), mode:MODE, shift:!!e.shiftKey,
                hitPic:hp, BSEL:BSEL, TBED:!!TBED, LED:(LED?LED.kind:null), TXWORDS:TXWORDS, TXTON:TXTON, editor:($('tbedit')?$('tbedit').className:null), textbar:$('textbar').className,
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
          // Where the shoulder really ends (2026-10-08): where he clicked,
          // any way at all - but within NOTE_SNAP_DEG of level or upright it
          // locks there, the same right-angle-wins rule every tool has. With
          // the switch off it is level with the knee, as it always was.
          function noteEnd(knee, end){
            if(!NOTEANY) return [end[0], knee[1]];
            var dx=end[0]-knee[0], dy=end[1]-knee[1];
            var L=Math.sqrt(dx*dx+dy*dy);
            if(L<1e-9) return [end[0], end[1]];
            var a=Math.abs(Math.atan2(dy,dx))*180/Math.PI;     // 0..180
            if(a<NOTE_SNAP_DEG || a>180-NOTE_SNAP_DEG) return [end[0], knee[1]];
            if(Math.abs(a-90)<NOTE_SNAP_DEG) return [knee[0], end[1]];
            return [end[0], end[1]];
          }

          function noteMark(tip, knee, end, text, arrow, sf){
            var off = 0.7 / (sf || (1/96));
            if(NOTEANY){
              // The shoulder runs from the knee to where he clicked, any way.
              // The words sit past its end along the same line: their middle
              // is far enough out that the edge of their box meets the end of
              // the line plus the pad - half the words when it runs level
              // (exactly the old sum), half their height when it runs upright.
              var e2=noteEnd(knee, end);
              var ddx=e2[0]-knee[0], ddy=e2[1]-knee[1];
              var DL=Math.sqrt(ddx*ddx+ddy*ddy);
              if(DL>1e-9){
                var ux=ddx/DL, uy=ddy/DL;
                var th=markTextH();
                var hw=String(text || '').length * th * 0.6 / 2, hh=th/2;
                var along=Math.min(Math.abs(ux)>1e-9 ? hw/Math.abs(ux) : Infinity,
                                   Math.abs(uy)>1e-9 ? hh/Math.abs(uy) : Infinity);
                var go=along + off*0.12;
                return {t:'note',
                        x: e2[0] + ux*go, y: e2[1] + uy*go,
                        kx: knee[0], ky: knee[1],
                        lx: tip[0],  ly: tip[1],
                        text: text, arrow: !!arrow};
              }
            }
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
          var NOTEANY = true;          // told by Ruby: a note's shoulder goes any way
          var FITCENTRE = true;        // told by Ruby: all the way out = the whole sheet, in the middle
          var NOTEPLACE = true;        // told by Ruby: a new note's words are typed on the sheet, not in a bar
          var NOTE_SNAP_DEG = 12;      // near level or upright, it locks there
          function escapeAll(){
            if(!ESCEXITS){
              // switched off: exactly what Escape did before 2026-10-07
              tbCancel();
              cancelCarry();
              if(ROT){ dropTurn(); }
              if(BOXD){ dropBox(); }
              BSEL=null;
              BAND=null; SELS=[];
              PEND=null; PEND2=null; PEND3=null; HOVER=null; SEL=null; ERA=null;
              DRAWSNAP=null; CHAIN0=null;
              closeTextBar();
              render(); showMarks();
              return;
            }
            tbCancel();                          // words half written are dropped, never kept
            cancelCarry();                       // a mark in the hand goes home
            SSEL=[];                             // and the picked lines are let go
            TCARRY=null; TDRAG=null; MDRAG=null; // a label or a mark mid-drag stays put
            if(ROT){ dropTurn(); }                         // a drawing or a picture half turned goes back as it was
            BSEL=null;                                     // and a picked picture is let go
            if(BOXD){ dropBox(); }                         // and a box half moved, half sized or half cut
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
            DRAWSNAP=null; CHAIN0=null;          // a half-drawn line is dropped, never finished
            hideNoteBar();
            closeTextBar();
            if(MODE!=='hand'){ setMode('hand'); return; }   // setMode redraws
            render(); showMarks();
          }

          function setMode(m){
            if((m==='line'||m==='chain') && !LINEDRAW) m='hand';
            if(m==='text' && !TXTON) m='hand';
            tbCancel();                          // another tool: words half written are dropped
            DRAWSNAP=null; CHAIN0=null; ROT=null; BOXD=null; BSEL=null;
            cancelCarry();
            BAND=null; SELS=[];
            MODE=m; PEND=null; PEND2=null; PEND3=null; HOVER=null; ERA=null; ERASWEEP=null; ERADONE=false; SNAPPED=null;
            SSEL=[];
            if(m!=='hand') SEL=null;
            // (the first four are written as they always were: rt65 looks for that list)
            ['thand','tdim','tnote','terase'].concat(['tline','tchain']).concat(['ttext']).forEach(function(id){
              $(id).className='tool'+(($(id).id==='t'+m)?' on':'');
            });
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor = m==='hand' ? 'default' : (m==='text' ? 'text' : 'crosshair');
            showMarks();
            render();
          }

          function showMarks(){
            var n=marks().length;
            $('tundo').disabled = !n;
            // The line under the tools used to explain every tool and every
            // state ("1 לחץ בהתחלה · 2 לחץ בסוף · 3 משוך..."). All of it went
            // on 2026-10-08 - "תעיף את כל ההסברים הקטנים בלבן, זה סתם מעצבן
            // ולא הכרחי" - and the line says nothing now unless something is
            // wrong (the count is in the heading, see headings()).
            var tip='';
            paintDimOff();
            // No free geometry is no longer a dead end - the eraser still
            // takes dimensions and notes (2026-08-19).
            if(MODE==='erase'&&!siteLayer()&&!n)
              tip='אין מה למחוק על הדף הזה.';
            $('markinfo').textContent = tip;
            headings();
          }

          // ---- dragging the plan -----------------------------------------
          var DRAG=null;
          function hookDrag(){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return;
            svg.style.cursor = MODE==='hand' ? arrowCursor()
                             : MODE==='erase' ? eraserCursor() : (MODE==='text' ? 'text' : 'crosshair');

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
              if(MODE==='line'||MODE==='chain'){
                // the ring shows where a click would land BEFORE he clicks,
                // and the click uses that very point
                DRAWSNAP=drawSnap(atMouse(e));
                paintDraw();
                return;
              }
              if(MODE==='hand'&&!MDRAG&&!DRAG){
                svg.style.cursor = (hitMark(e) || (PICON && hitPic(e))) ? 'move' : arrowCursor();
              }
            };

            svg.onmousedown=function(e){
              // The probe goes first (2026-10-07): a press that hits something
              // leaves this handler early, and until today it was never written
              // down - the file said nothing about the clicks that mattered.
              if(MODE==='hand'||MODE==='erase') probeClick(e, 'down');
              // Words open in the bar: a press on the sheet is "I am done" - they
              // are kept, and the press does nothing else.
              if(TBED){ tbSave(); e.preventDefault(); return; }
              if(LED && LED.kind==='label'){ labelEditKeep(); }
              // a new note half written: this press keeps it, and does nothing else
              if(LED && LED.kind==='note'){ noteEditKeep(); e.preventDefault(); return; }
              // In the hand tool a mark under the mouse is picked up; empty
              // paper still drags the plan the way it always did. With Alt
              // held nothing is picked at all: Alt+drag moves the DRAWING
              // inside its box, whatever is under the mouse (2026-10-08,
              // stage 4 of the box - in a small box there is always something
              // under the mouse).
              if(MODE==='hand'&&!e.shiftKey&&!e.altKey){
                // The second of two quick presses on the same number opens its
                // words (pressTwice) - before anything else is done with it.
                if(pressTwice(e)){ e.preventDefault(); return; }
                // Carrying something? Then this click PUTS IT DOWN. Nothing
                // else gets to happen on it.
                if(CARRY){ dropCarry(); e.preventDefault(); return; }
                if(TCARRY){ dropTextCarry(); e.preventDefault(); return; }
                // A PICTURE under the mouse: it is picked - the handles go
                // onto it - and it moves with the mouse from this very press.
                var hpic=PICON ? hitPic(e) : null;
                // An elevation's dimension number lies ON its picture (2026-10-08, 13:15 -
                // "1": the press picked the picture and never reached the number). The
                // number wins, so its settings open like any label's.
                if(hpic){ var hx=hitText(e); if(hx && elevKey(hx.key)) hpic=null; }
                if(hpic){
                  if(TSEL) closeTextBar();
                  var had=(SEL!==null||SELS.length||SSEL.length);
                  SEL=null; SELS=[]; SSEL=[];
                  BSEL=hpic.pic;
                  startBox('move',e);
                  if(had) render(); else paintRot();
                  showMarks();
                  e.preventDefault();
                  return;
                }
                if(BSEL!==null){
                  // a press anywhere else lets the picture go (and a box of writing loses its frame)
                  var wasText=String(BSEL).charAt(0)==='t';
                  BSEL=null;
                  if(wasText) render(); else paintRot();
                }
                var h=markUnder(e);
                if(h){
                  if(TSEL) closeTextBar();
                  // clicking one thing picks that one thing, and drops
                  // whatever the band had picked before
                  SSEL=[];
                  if(SELS.indexOf(h.i)<0) SELS=[h.i];
                  SEL=h.i;
                  MDRAG={part:h.part, at:atMouse(e)};
                  svg.style.cursor='move';
                  // a note: its settings are in the box at the side at once,
                  // the way a label's are (2026-10-08). Quiet: the keyboard
                  // stays with the sheet.
                  if(marks()[h.i].t==='note'){ var nw=noteWords(h.i); if(nw) openTextBar(nw, true); }
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
                  TSEL=ht; ONE=false;
                  TDRAG={at:atMouse(e), dx:0, dy:0, moved:false};
                  TCARRY=null;
                  svg.style.cursor='move';
                  // ONE click: its settings are in the box at the side at once
                  // (2026-10-07, "אני לוחץ על טקסט מסוים ואז אני משנה את
                  // ההגדרות בחלון ההגדרות", like Word). Quiet: the keyboard
                  // stays with the sheet.
                  openTextBar(ht, true);
                  showMarks();
                  e.preventDefault();
                  return;
                }
                if(TSEL){ closeTextBar(); }
                if(SEL!==null||SELS.length){ SEL=null; SELS=[]; render(); showMarks(); }
              }
              // (the probe already ran, at the top of this handler)
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
                 pageView()){
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
              var pan = e.shiftKey || e.button===1 || !pageView();
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
              probeClick(e, 'dblclick');
              // while drawing, two quick clicks are two clicks of the drawing tool
              if(MODE==='line'||MODE==='chain'){ e.preventDefault(); return; }
              // two clicks on a box of writing open its words and its size again
              var hb=(MODE==='hand' && PICON && !TBED) ? hitPic(e) : null;
              if(hb && hb.txt){ BOXD=null; tbOpen(parseInt(String(hb.pic).slice(2),10)); e.preventDefault(); return; }
              // two quick presses have just opened this label or note
              // (pressTwice): this is the browser's own double click, coming
              // late, and it must not open it all over again
              if(LBDONE && Date.now()-LBDONE<700){ LBDONE=0; e.preventDefault(); return; }
              // Two clicks on a note have meant "change what it says" since
              // 2026-08-14; since 2026-10-08 its words open the way any
              // label's do - typed over themselves on the sheet (labelUnder
              // finds them), not in a bar of their own.
              var ht=labelUnder(e);
              if(ht){
                hideNoteBar();
                if(TXWORDS) labelEditOpen(ht); else openTextBar(ht);   // typed over the label itself
                e.preventDefault();
              }
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
              // a box of writing goes on ANY sheet, with a drawing on it or not
              if(MODE==='text'){ textClick(e); return; }
              var p=atMouse(e);
              if(!p){ $('markinfo').textContent='אין תוכנית בדף הזה'; return; }
              if(MODE==='line'||MODE==='chain'){ drawClick(p); return; }
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
                if(LED && LED.kind==='note') return;           // (typing on the sheet)
                if(NOTEJUST && Date.now()-NOTEJUST<400) return; // the click that kept the last one
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
                // the words are typed where they will stand (2026-10-08);
                // the bar at the top only with the switch off
                if(NOTEPLACE && noteEditOpen()) return;
                $('notebar').className='on';
                $('notetext').value='';
                paintArrow();
                $('notetext').focus();
              }
            };
          }

          function onMove(e){
            if(BOXD){ dragBox(e); return; }
            if(ROT && ROT.pic){
              var po=ROT.p0, pang=angleAbout(e, po.x+po.w/2, po.y+po.h/2);
              ROT.pic=picLive(ROT.pic);
              if(pang!==null && ROT.a0!==null){
                var pnr=snapTurn(ROT.r0+(pang-ROT.a0));
                if(pnr!==(ROT.moved ? (+ROT.pic.rot||0) : ROT.r0)){
                  if(pnr===ROT.r0){
                    picPut(ROT.pic, ROT.s0); picsBack(ROT.was); ROT.moved=false;
                  } else {
                    // turned, it takes up other room: it is held on the sheet
                    setPic(ROT.pic, (po.txt ? tbHold : picHold)({x:po.x, y:po.y, w:po.w, h:po.h, rot:pnr, crop:po.crop, pt:po.pt, text:po.text}, picArea()));
                    ROT.moved=true;
                  }
                  render(true);
                }
              }
              return;
            }
            if(ROT){
              var ra=rotAngleAt(e);
              if(ra!==null && ROT.a0!==null){
                var nr=snapTurn(ROT.r0+(ra-ROT.a0));
                if(nr!==viewTurn().deg){ STATE.rotation=nr; turnBoxTo(nr); ROT.moved=true; render(true); }
              }
              return;
            }
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
            var mvt=viewTurn();
            if(mvt.deg){
              // on a turned drawing the plan still goes the way the mouse goes
              var ex=(e.clientX-DRAG.x)/k/sf, ey=-(e.clientY-DRAG.y)/k/sf;
              STATE.origin_x=DRAG.ox-(ex*mvt.c+ey*mvt.s);
              STATE.origin_y=DRAG.oy-(-ex*mvt.s+ey*mvt.c);
              render(true);
              return;
            }
            STATE.origin_x=DRAG.ox-(e.clientX-DRAG.x)/k/sf;
            STATE.origin_y=DRAG.oy+(e.clientY-DRAG.y)/k/sf;
            render(true);
          }

          function onUp(){
            if(BOXD && BOXD.pic){
              var pb=BOXD;
              BOXD=null;
              if(pb.dbl && !pb.moved && pb.pic.txt){
                // the second of two quick presses on a box of writing, let go where it was: it opens
                tbOpen(parseInt(String(pb.pic.pic).slice(2),10));
                return;
              }
              if(pb.moved){
                TBLAST=null;
                // one pull is one step for Ctrl+Z, and Ruby is told once
                if(UNDOON){ UNDO.push({g:++UGROUP, pics:pb.was}); if(UNDO.length>300) UNDO.shift(); }
                push();
              }
              render(); showMarks();
              return;
            }
            if(ROT && ROT.pic){
              var pt=ROT;
              ROT=null;
              if(pt.moved){
                if(UNDOON){ UNDO.push({g:++UGROUP, pics:pt.was}); if(UNDO.length>300) UNDO.shift(); }
                push();
              }
              render(); showMarks();
              return;
            }
            if(BOXD){
              var bd=BOXD;
              BOXD=null;
              if(bd.moved){
                // how far a cut moved the drawing's own middle - Ctrl+Z takes exactly that back
                if(bd.kind.length===1){ bd.was.dox=STATE.origin_x-bd.o0.x; bd.was.doy=STATE.origin_y-bd.o0.y; }
                // one pull of a handle is one step for Ctrl+Z, and Ruby is told once
                if(UNDOON){ UNDO.push({g:++UGROUP, box:bd.was}); if(UNDO.length>300) UNDO.shift(); }
                paintScale();
                push();
              }
              render(); showMarks();
              return;
            }
            if(ROT){
              var rr=ROT;
              ROT=null;
              if(rr.moved && viewTurn().deg!==rr.r0){
                // one turn of the handle is one step for Ctrl+Z - the box it left goes back with the angle
                if(UNDOON){ UNDO.push({g:++UGROUP, rot:rr.r0, rbox:(boxTurns() ? rr.was : undefined)}); if(UNDO.length>300) UNDO.shift(); }
                sendTurn();
              }
              render();
              return;
            }
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
            var g=UNDO[UNDO.length-1].g, marksBack=null, siteBack=[], addBack=[], rotBack=null, boxBack=null, picBack=null, orderBack=null, rboxBack=null;
            while(UNDO.length && UNDO[UNDO.length-1].g===g){
              var u=UNDO.pop();
              if(u.marks!==undefined) marksBack=u.marks;   // popped newest first: the oldest wins
              if(u.site) siteBack=siteBack.concat(u.site);
              if(u.added) addBack=addBack.concat(u.added);
              if(u.rot!==undefined) rotBack=u.rot;
              if(u.rbox!==undefined) rboxBack=u.rbox;
              if(u.box!==undefined) boxBack=u.box;
              if(u.pics!==undefined) picBack=u.pics;
              if(u.order!==undefined) orderBack=u.order;
            }
            // nothing half done survives an undo - it was drawn on the sheet as it was
            SSEL=[];
            cancelCarry();
            TCARRY=null; TDRAG=null; MDRAG=null; BAND=null; SELS=[]; SEL=null;
            PEND=null; PEND2=null; PEND3=null; HOVER=null; ERA=null; ERASWEEP=null; SNAPPED=null;
            DRAWSNAP=null; CHAIN0=null; ROT=null; BOXD=null;
            if(picBack!==null){
              // the pictures go back to where they were, and Ruby lays the sheet out again
              picsBack(picBack);
              picsToShapes();
              BSEL=null;
              sketchup.set_state(JSON.stringify(STATE));
            }
            if(orderBack!==null){
              // the sheets go back to the order they had, and Ruby numbers them again
              STATE.page_order=orderBack.o;
              orderPages(orderBack.keys);
              fillPages(); showFit();
              sketchup.set_state(JSON.stringify(STATE));
            }
            if(boxBack!==null){
              // the box and the size go back to what they were, and Ruby lays the sheet out again
              restoreBox(boxBack);
              sketchup.set_state(JSON.stringify(STATE));
            }
            if(rotBack!==null){
              // the drawing goes back to the angle it had, and Ruby turns the writing back with it
              // (a box that turns as a whole goes back to the box it had before the turn, too)
              STATE.rotation=rotBack;
              if(rboxBack) restoreBox(rboxBack);
              sendTurn();
            }
            if(addBack.length){
              // lines he DREW come off again: highest number first, and only
              // if that number still holds that very line
              var al=rawSiteLayer();
              if(al && al.shapes){
                var an=al.shapes.length, offs=[];
                addBack.sort(function(a,b){ return b.i-a.i; }).forEach(function(x){
                  var cur=al.shapes[x.i];
                  if(cur && cur.points && JSON.stringify(cur.points)===JSON.stringify(x.s.points)){
                    al.shapes.splice(x.i,1);
                    offs.push({i:x.i, p:x.s.points});
                  }
                });
                STATE.site_count=al.shapes.length;
                USITE_N=al.shapes.length;
                if(offs.length) sketchup.undo_site_add(JSON.stringify({items:offs, n:an}));
              }
            }
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
            NOTEANY = (p.note_any!==false);
            FITCENTRE = (p.fit_centre!==false);
            NOTEPLACE = (p.note_in_place!==false);
            UNDOON = (p.undo!==false);
            LINEPICK = (p.line_pick!==false);
            LINEDRAW = (p.line_draw!==false);
            ROTON = (p.rotate!==false);
            BOXON = (p.view_box!==false);
            CROPON = (p.box_crop!==false);
            PICON = (p.pic_box!==false);
            TXTON = (p.text_box!==false) && PICON;
            TXWORDS = (p.text_words!==false);
            TXSTYLE = (p.text_style!==false);
            PGORDER = (p.page_order!==false);
            DRAWNON = (p.drawn!==false);
            TXFONT = (p.text_font!==false);
            DRAFTS = p.drafts || [];
            fillDrafts();
            if($('txwords') && $('txwords').style) $('txwords').style.display = TXWORDS ? '' : 'none';
            if(p.text_rules && p.text_rules.w) TXR=p.text_rules;
            fillFonts();           // the letterings on offer, from the rules just given
            // a sheet from Ruby while words were open: the bar is shut, what Ruby has is the truth
            if(TBED){ TBED=null; if($('tbbar')) $('tbbar').className=''; }
            if(!STATE.texts) STATE.texts=[];
            if($('ttext') && $('ttext').style) $('ttext').style.display = TXTON ? '' : 'none';
            BSEL=null;
            if($('pichererow') && $('pichererow').style) $('pichererow').style.display = PICON ? '' : 'none';
            BOXD=null;
            ROT=null;
            if(STATE.rotation===undefined||STATE.rotation===null) STATE.rotation=0;
            if($('tools2')) $('tools2').style.display = LINEDRAW ? '' : 'none';
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
            (p.pics||[]).forEach(function(im){ if(im.url) URLS[im.path]=im.url; });
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
            // The window ALWAYS opens on the whole sheet, as big as the window
            // allows - whatever zoom was saved on the model (2026-10-07, twice:
            // "הדף קטן מדי בחלון", "שוב שברת את גודל המסך"). The zoom he sets
            // with the wheel is kept only while the window is open (KEEPVIEW).
            else { ZOOM = null; }
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
            paintScale();
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
            if(NOTENEW!==null){
              // the note just written on the sheet is here now: it is picked,
              // and its settings are at the side, the way a press on it does
              var fresh=noteWords(NOTENEW); NOTENEW=null;
              if(fresh){ openTextBar(fresh, true); }
            } else if(TSEL && TSEL.note!==undefined && TSEL.note!==null){
              // a note's words: by the note, since new words make a new key
              var nw=noteWords(TSEL.note);
              if(nw) TSEL=nw; else closeTextBar();
            } else if(TSEL){
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
            if(USITE_N!==null && usn!==USITE_N) UNDO=UNDO.filter(function(u){ return !u.site && !u.added; });
            USITE_N=usn;
            if(STATE.strip){
              $('strip').className='on';
              $('stripbtn').textContent='הסתר את הדפים';
            }
            buildLayers();
            buildSections();
            showLogo(p.logo);
            fillPages();
            if(!LINEDRAW && (MODE==='line'||MODE==='chain')) setMode('hand');
            if(!TXTON && MODE==='text') setMode('hand');
            showMarks();
            if(first){ fitPlan(); return; }
            showFit();
            render();
          }

          function applyPages(pages, marksLayer){
            DOC.pages=pages;
            if(marksLayer) putLayer('MODEL', marksLayer);
            if(STATE.active>=pages.length) STATE.active=0;
            if(TBED){ PAGE=activePage(); tbRebuild(); }
            fillPages();
            buildLayers();
            showFit();
            render();
          }

          // The same, for several layers of the plan at once: after the
          // drawing is turned, the writing on it comes back from Ruby the way
          // it prints - turned with its line, or level on the page.
          function applyLayers(pages, layers){
            (layers||[]).forEach(function(l){ putLayer('MODEL', l); });
            applyPages(pages, null);
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
            tbCancel();
            STATE.active=Math.max(0, Math.min(DOC.pages.length-1, i));
            BSEL=null;                       // the picked picture was on the sheet he just left
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
              d.onclick=function(){ if(PGJUST){ PGJUST=false; return; } goToPage(i); };
              // the little sheets drag up and down like the rows of the list (2026-10-08)
              d.onmousedown=function(e){ pageDragStart(e, i, 'strip'); };
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
            if(k==='image') return 'image:'+p.ref;
            if(k==='drawing') return 'drawing:'+p.ref;     // an editor drawing on a sheet (2026-10-07)
            return k;
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
              row.onclick=function(){ if(PGJUST){ PGJUST=false; return; } $('pages').focus(); goToPage(i); };
              row.onmousedown=function(e){ pageDragStart(e, i); };
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

          // ---- the order of the sheets (2026-10-07) ------------------------
          //
          // He drags a row of the page list up or down: the sheet goes there,
          // in the window, the strip and the PDF, and the sheet numbers run in
          // the new order (Ruby numbers them - PlanCanvas.page_order). A press
          // that does not move is still a click. Escape drops the drag; Ctrl+Z
          // puts the old order back.
          // box: 'pages' (the list) or 'strip' (the little sheets, 2026-10-08) - the same drag
          function pageDragStart(e, i, box){
            if(!PGORDER || e.button!==0) return;
            if(e.target && (e.target.tagName==='BUTTON' || e.target.tagName==='INPUT')) return;      // the x, the tick
            e.preventDefault();                                     // no text picked while dragging
            $('pages').focus();
            PGDRAG={from:i, y0:e.clientY, on:false, box:box||'pages'};
          }
          function pageDragRows(box){
            var b=box || (PGDRAG ? PGDRAG.box : 'pages');
            return $(b).querySelectorAll(b==='strip' ? '.thumb' : '.pg');
          }
          // which gap the mouse is over: 0 = above the first row, n = below the last
          function pageGapAt(y){
            var rows=pageDragRows();
            for(var k=0;k<rows.length;k++){
              var r=rows[k].getBoundingClientRect();
              if(y<r.top+r.height/2) return k;
            }
            return rows.length;
          }
          function pageDragPaint(gap, box){
            var rows=pageDragRows(box);
            for(var k=0;k<rows.length;k++){
              var c=rows[k].className.replace(/ (dropb|dropa|drag)/g,'');
              if(PGDRAG && PGDRAG.on && k===PGDRAG.from) c+=' drag';
              if(gap!==null && gap!==undefined){
                if(k===gap) c+=' dropb';
                else if(gap===rows.length && k===rows.length-1) c+=' dropa';
              }
              rows[k].className=c;
            }
          }
          function pageDragMove(e){
            if(!PGDRAG) return false;
            if(!PGDRAG.on){
              if(Math.abs(e.clientY-PGDRAG.y0)<5) return true;
              PGDRAG.on=true;
            }
            pageDragPaint(pageGapAt(e.clientY));
            return true;
          }
          function pageDragEnd(e){
            if(!PGDRAG) return false;
            var d=PGDRAG;
            if(!d.on){ PGDRAG=null; return true; }                  // a plain click
            PGJUST=true; setTimeout(function(){ PGJUST=false; }, 0);  // the click the browser sends after
            var gap=pageGapAt(e.clientY);
            var to = gap>d.from ? gap-1 : gap;
            PGDRAG=null; pageDragPaint(null, d.box);
            if(to!==d.from) movePage(d.from, to);
            return true;
          }
          function pageDragCancel(){
            if(!PGDRAG) return false;
            var b=PGDRAG.box; PGDRAG=null; pageDragPaint(null, b);
            return true;
          }
          // DOC.pages in the order of these keys; the open sheet stays open
          function orderPages(keys){
            var cur=(DOC.pages||[])[STATE.active||0], ak=cur ? pageKey(cur) : null;
            var at={}, n=keys.length;
            keys.forEach(function(k,i){ at[k]=i; });
            DOC.pages=(DOC.pages||[]).map(function(p,i){ return {p:p, i:i}; }).sort(function(a,b){
              var x=at[pageKey(a.p)], y=at[pageKey(b.p)];
              if(x===undefined) x=n+a.i;
              if(y===undefined) y=n+b.i;
              return (x-y) || (a.i-b.i);
            }).map(function(o){ return o.p; });
            if(ak!==null) DOC.pages.forEach(function(p,i){ if(pageKey(p)===ak) STATE.active=i; });
          }
          function movePage(from, to){
            var was=(DOC.pages||[]).map(pageKey);
            var keys=was.slice();
            var k=keys.splice(from,1)[0];
            keys.splice(to,0,k);
            var wasOrder=STATE.page_order ? STATE.page_order.slice() : null;
            STATE.page_order=keys;
            orderPages(keys);
            if(UNDOON){ UNDO.push({g:++UGROUP, order:{o:wasOrder, keys:was}}); if(UNDO.length>300) UNDO.shift(); }
            fillPages(); showFit(); render(); push();
          }

          // ---- the editor's drawings, on sheets of their own (2026-10-07) ----
          // The list under the pages: which editor drawing ("שרטוט 1"...) to
          // put on a sheet of its own. Shown only when the editor has one.
          function fillDrafts(){
            var box=$('drawadd'), sel=$('drawsrc');
            if(!box||!sel) return;
            var on=DRAWNON && DRAFTS.length>0;
            if(box.style) box.style.display = on ? '' : 'none';
            if(!on) return;
            var cur=sel.value;
            sel.innerHTML='';
            DRAFTS.forEach(function(d){
              var o=document.createElement('option'); o.value='draft:'+d.i; o.textContent=d.name;
              if(o.value===cur) o.selected=true;
              sel.appendChild(o);
            });
          }
          function addDrawing(){
            var sel=$('drawsrc'); if(!sel||!sel.value) return;
            sketchup.add_drawing(JSON.stringify({src:sel.value}));
          }

          // ---- a lettering of its own (2026-10-07) -------------------------
          // The letterings on offer, as Ruby found them on this computer
          // (TXR.fonts); "" = the drawing's own (Helvetica; Hebrew in TXR.heb).
          function fontNames(){ return (TXFONT && TXR && TXR.fonts) ? Object.keys(TXR.fonts) : []; }
          function fillFonts(){
            var sel=$('txfont'), box=$('txfontbox'), menu=$('txfontmenu'); if(!sel) return;
            var names=fontNames();
            if(box && box.style) box.style.display = names.length ? '' : 'none';
            var cur=sel.value;
            sel.innerHTML='';
            [''].concat(names).forEach(function(nm){
              var o=document.createElement('option'); o.value=nm; o.textContent=nm||'כתב רגיל';
              if(nm===cur) o.selected=true;
              sel.appendChild(o);
            });
            // the letterings' own files, so the sheet draws the very letters the PDF prints
            fontFaces();
            // the list he picks from: every name in its own letters
            if(menu){
              menu.innerHTML='';
              [''].concat(names).forEach(function(nm){
                var d=document.createElement('div');
                d.textContent = nm || 'כתב רגיל';
                if(nm && d.style) d.style.fontFamily = fontCss('A', nm);
                d.setAttribute('data-font', nm);
                d.onclick=function(e){
                  if(e && e.stopPropagation) e.stopPropagation();
                  fontMenu(false);
                  if(sel.value!==nm){ sel.value=nm; if(sel.onchange) sel.onchange(); }
                  paintFontBtn();
                };
                menu.appendChild(d);
              });
            }
            paintFontBtn();
          }
          // @font-face for every lettering on offer, from the files beside the plugin
          function fontFaces(){
            if(!document.head || !document.createElement) return;
            var st=$('ipfonts');
            if(!st){ st=document.createElement('style'); st.id='ipfonts'; document.head.appendChild(st); }
            var css='';
            fontNames().forEach(function(f){
              var t=TXR.fonts[f]; if(!t||!t.url) return;
              css += '@font-face{font-family:"'+f+'";src:url("'+t.url+'");font-weight:400;font-style:normal;}\n';
              if(t.urlb) css += '@font-face{font-family:"'+f+'";src:url("'+t.urlb+'");font-weight:700;font-style:normal;}\n';
            });
            st.textContent=css;
          }
          // the button says which lettering is picked, in that lettering
          function paintFontBtn(){
            var sel=$('txfont'), b=$('txfontbtn'), menu=$('txfontmenu'); if(!sel||!b) return;
            var v=sel.value||'';
            b.textContent = v || 'כתב רגיל';
            if(b.style) b.style.fontFamily = v ? fontCss('A', v) : '';
            if(menu) Array.prototype.forEach.call(menu.children||[], function(d){ d.className = (d.getAttribute('data-font')===v) ? 'on' : ''; });
          }
          // the lettering picked for what is in the panel, shown on the button
          function fontPick(v){
            var sel=$('txfont'); if(!sel) return;
            sel.value = v || '';
            paintFontBtn();
          }
          function fontMenu(on){
            var m=$('txfontmenu'); if(!m) return false;
            var was = m.className==='on';
            m.className = on ? 'on' : '';
            return was;
          }
          // the family a run is measured and shown in: the one picked if it is
          // on offer, else the Hebrew one when the run needs it, else none
          function fontFor(str,font){
            if(!TXFONT||!TXR||!TXR.fonts) return null;
            if(font && TXR.fonts[font]) return font;
            return (TXR.heb && TXR.fonts[TXR.heb] && /[\u0590-\u05FF\uFB1D-\uFB4F]/.test(String(str))) ? TXR.heb : null;
          }
          function fontCss(str,font){ var f=fontFor(str,font); return f ? (f+',Arial,sans-serif') : 'Helvetica,Arial'; }

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
            tag('papertag', (STATE.size||'') + ' · ' + ((BOXON && STATE.scale_f>0) ? 'scale' : (STATE.scale||'')));
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
            var pg=activePage(), v=pg&&(pg.views||[])[0]&&pageView();
            if(!BOUNDS||!v) return;
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              var ts=turnedSize();
              if(ts[0]*SF[s]<=v.w&&ts[1]*SF[s]<=v.h) best=s;
            });
            if(best){ STATE.scale=best; STATE.scale_f=null; paintScale(); $('scale').value=best; }
            centerPlan(true);
            ZOOM=null; STATE.zoom=null;
            showFit(); render(); push();
          }

          // says what would fit. never changes the scale by itself.
          function showFit(){
            var pg=activePage();
            var v=pg&&(pg.views||[])[0]&&pageView();
            if(!BOUNDS||!v){ $('fit').textContent=''; return; }
            var sf=scaleFactor(STATE.scale);
            var tz=turnedSize();
            var mw=tz[0]*sf, mh=tz[1]*sf;
            if(mw<=v.w&&mh<=v.h){ $('fit').textContent='נכנס בדף ✓'; $('fit').style.color='#8fdf8f'; return; }
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              var f=SF[s];
              if(tz[0]*f<=v.w&&tz[1]*f<=v.h) best=s;
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
            // WHERE they land (2026-10-07): onto the sheet that is open, each
            // in a box of its own, when he ticked that - otherwise a sheet
            // each, as always. Remembered now, in case he turns the page
            // while they are being carried across.
            DROP.on=(PICON && PAGE && $('pichere') && $('pichere').checked===true) ? pageKey(PAGE) : null;
            DROP.snap=DROP.on ? picsSnap() : null;
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
              if(DROP.on) sketchup.drop_finish(JSON.stringify({on:DROP.on}));
              else sketchup.drop_finish();
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
              // the one that ships with the plugin: nothing was changed, and
              // there is nothing to go back to
              $('logoinfo').textContent = l.builtin ? ('הלוגו הקבוע: '+l.name) : l.name;
              tag('settag', l.builtin ? '' : 'לוגו');
              $('logoclear').style.display = l.builtin ? 'none' : '';
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
            var here=!!DROP.snap;
            if(here){
              // pictures put onto a sheet are a step like any other: Ctrl+Z takes them off again
              if(n && !err && UNDOON){ UNDO.push({g:++UGROUP, pics:DROP.snap}); if(UNDO.length>300) UNDO.shift(); }
              DROP.snap=null;
            }
            $('imginfo').textContent = err ? ('שגיאה: '+err)
              : (n ? ((n===1 ? 'נוספה תמונה אחת' : ('נוספו '+n+' תמונות'))+(here ? ' לדף הזה' : ''))
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
            // Picking a scale from the list puts the drawing on that EXACT scale:
            // a size set by hand is forgotten. ("Any size" itself is not a choice.)
            $('scale').onchange=function(){
              if(this.value===FREE_SCALE) return;
              STATE.scale=this.value; STATE.scale_f=null; paintScale();
              showFit(); render(); push();
            };
            $('ownpage').onchange=function(){ STATE.tables_own_page=this.checked; push(); };
            $('stage').addEventListener('wheel',function(e){
              e.preventDefault();
              zoomAt(e.clientX, e.clientY, (ZOOM||1)*(e.deltaY<0?1.15:1/1.15));
            },{passive:false});
            window.addEventListener('mousemove',onMove);
            window.addEventListener('mouseup',onUp);
            window.addEventListener('mousemove',function(e){ if(PGDRAG) pageDragMove(e); });
            window.addEventListener('mouseup',function(e){ if(PGDRAG) pageDragEnd(e); });
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
            $('tline').onclick=function(){ setMode('line'); };
            $('ttext').onclick=function(){ setMode('text'); };
            // the bar of a box of writing: what he types is on the sheet at once
            $('tbtext').oninput=function(){ tbLive(); };
            $('tbsize').oninput=function(){ tbLive(); };
            $('tbsize').onchange=function(){ tbLive(); };
            $('tbok').onclick=function(){ tbSave(); };
            // the editor on the sheet
            $('tbedit').oninput=function(){ tbEditInput(); };
            $('tbedit').onmousedown=function(e){ if(e.stopPropagation) e.stopPropagation(); };
            $('tbedit').onkeydown=function(e){
              if(!LED) return;
              if(LED.kind==='label'){
                if(e.key==='Enter'){ e.preventDefault(); labelEditKeep(); }
                else if(e.key==='Escape'){ e.preventDefault(); tbEditHide(); closeTextBar(); render(); showMarks(); }
                return;
              }
              if(LED.kind==='note'){
                if(e.key==='Enter'){ e.preventDefault(); noteEditKeep(); }
                else if(e.key==='Escape'){ e.preventDefault(); noteEditDrop(); }
                return;
              }
              if(e.key==='Enter' && (e.ctrlKey||e.metaKey)){ e.preventDefault(); tbSave(); }
              else if(e.key==='Escape'){ e.preventDefault(); tbCancel(); render(); showMarks(); }
            };
            $('tbcancel').onclick=function(){ tbCancel(); render(); showMarks(); };
            $('tbtext').onkeydown=function(e){
              // Enter is a NEW LINE - he asked: "אם אני לוחץ אנטר אז אוכל לרדת
              // שורה למטה ולהמשיך להקליד ולא שהריבוע יסגר לי". Ctrl+Enter, the
              // button, or a press on the sheet is "I am done".
              if(e.key==='Enter' && (e.ctrlKey||e.metaKey)){ e.preventDefault(); tbSave(); }
              else if(e.key==='Escape'){ e.preventDefault(); tbCancel(); render(); showMarks(); }
            };
            $('tbsize').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); tbSave(); }
              else if(e.key==='Escape'){ e.preventDefault(); tbCancel(); render(); showMarks(); }
            };
            ['nw','ne','sw','se'].forEach(function(c){
              var el=$('boxc-'+c);
              el.onmousedown=function(e){ startBox(c,e); };
              if(el.style) el.style.cursor=(c==='nw'||c==='se') ? 'nwse-resize' : 'nesw-resize';
            });
            $('boxmove').onmousedown=function(e){ startBox('move',e); };
            if($('boxmove').style) $('boxmove').style.cursor='move';
            // a side cuts the drawing from that side
            ['n','s','w','e'].forEach(function(d){
              var el=$('boxe-'+d);
              el.onmousedown=function(e){ startBox(d,e); };
              if(el.style) el.style.cursor=(d==='n'||d==='s') ? 'ns-resize' : 'ew-resize';
            });
            $('rothandle').onmousedown=function(e){ startTurn(e); };
            // Two clicks on a HANDLE of a box of writing open it too. A short
            // line of writing is a dozen pixels tall at the zoom that shows the
            // whole sheet, and the squares on its corners cover most of it: his
            // second click landed on a square, the square took it, and the
            // sheet never saw a double click (2026-10-07, "ניסיתי, לא נפתח").
            ['boxc-nw','boxc-ne','boxc-sw','boxc-se','boxe-n','boxe-s','boxe-w','boxe-e','boxmove'].forEach(function(id){
              $(id).ondblclick=function(e){
                var tg=(MODE==='hand' && !TBED) ? boxTarget() : null;
                if(!tg||!tg.pic||!tg.pic.txt) return;
                BOXD=null;
                tbOpen(parseInt(String(tg.pic.pic).slice(2),10));
                if(e.preventDefault) e.preventDefault();
                if(e.stopPropagation) e.stopPropagation();
              };
            });
            if($('rothandle').style) $('rothandle').style.cursor=turnCursor();
            $('tchain').onclick=function(){ setMode('chain'); };
            $('tundo').onclick=function(){ undoMark(); };
            $('undrop').onclick=function(){ sketchup.restore_site_lines(); };
            for(var tk in TS_FIELDS){
              // change, not input: typing "1" on the way to "130" would send a
              // sheet at 25% and a full redraw with it.
              $(TS_FIELDS[tk]).onchange=function(){ sendTextScale(); };
            }
            $('tsReset').onclick=function(){ resetTextScale(); };

            $('txsize').onchange=function(){ if(boxBarSet({pt:this.value})) return; sendTextMark(); };
            $('txwords').onchange=function(){ sendTextWords(); };
            $('txwords').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); sendTextWords(); closeTextBar(); }
              else if(e.key==='Escape'){ e.preventDefault(); closeTextBar(); }
            };
            $('txsize').onkeydown=function(e){
              if(e.key!=='Enter') return;
              e.preventDefault();
              if(boxBarSet({pt:this.value})){
                // a box of writing: the size is set, and he is back in the words
                var ed=tbEditEl(); if(TBED && ed && ed.focus) ed.focus();
                return;
              }
              sendTextMark();
            };
            $('txbold').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              if(boxBarSet({bold:this.className.indexOf('on')>=0})) return;
              sendTextMark();
            };
            $('txitalic').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              if(boxBarSet({italic:this.className.indexOf('on')>=0})) return;
              sendTextMark();
            };
            $('txunder').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              if(boxBarSet({underline:this.className.indexOf('on')>=0})) return;
              sendTextMark();
            };
            $('txcolor').onchange=function(){ if(boxBarSet({color:this.value})) return; sendTextMark(); };
            $('txfont').onchange=function(){ if(boxBarSet({font:this.value})) return; sendTextMark(); };
            $('txfontbtn').onclick=function(e){ if(e&&e.stopPropagation) e.stopPropagation(); fontMenu($('txfontmenu').className!=='on'); };
            // a press anywhere else shuts the list
            document.addEventListener('mousedown', function(e){ var m=$('txfontmenu'); if(m && m.className==='on' && !(e.target && (e.target===$('txfontbtn') || (e.target.parentNode===m)))) fontMenu(false); });
            $('drawbtn').onclick=function(){ addDrawing(); };
            // Back to whatever its group says, rather than back to 100 - the
            // group is the drawing's own standard and that is what "normal"
            // means for one label inside it.
            $('txreset').onclick=function(){
              // a box of writing: plain black letters again (its size is his)
              if(boxBarSet({bold:false, italic:false, underline:false, color:'#000000', font:''})) return;
              if(!TSEL) return;
              sketchup.set_text_mark(JSON.stringify({key:TSEL.key, clear:true}));
              closeTextBar();
            };
            $('txdone').onclick=function(){
              if(boxBarWant()!==null){
                // a box of writing: what is typed is kept, and the box is let go
                if(TBED) tbSave();
                BSEL=null; render(); showMarks();
                return;
              }
              closeTextBar();
            };
            // (the bar lives in the side panel now: nothing to drag)

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
              // a drag of a row dropped; Ctrl+Z from the list too (2026-10-07)
              else if(e.key==='Escape' && pageDragCancel()){ e.preventDefault(); }
              else if((e.ctrlKey||e.metaKey) && !e.shiftKey && !e.altKey &&
                      (e.code==='KeyZ'||e.key==='z'||e.key==='Z')){ e.preventDefault(); undoLast(); }
            };

            // Delete removes what is picked. Not while he is typing a note, and
            // not while the cursor is in the address or sheet-number boxes.
            window.addEventListener('keydown',function(e){
              if(e.key==='Escape' && pageDragCancel()){ e.preventDefault(); return; }
              if(e.key==='Escape' && fontMenu(false)){ e.preventDefault(); return; }       // the list of letterings shuts
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
                else if(BSEL!==null){ e.preventDefault(); dropPic(); }
              } else if(e.key==='Escape'){
                e.preventDefault();
                escapeAll();
              }
            });

            $('dimoff').onchange=function(){ setDimOff(parseFloat(this.value)); };
            $('dimoff').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); this.blur(); }
            };

            // the same head, for the note whose words are in the box at the side
            $('txarrow').onclick=function(){
              if(!TSEL || TSEL.note===undefined || TSEL.note===null) return;
              var nm=marks()[TSEL.note]; if(!nm || nm.t!=='note') return;
              nm.arrow=(nm.arrow===false);
              STATE.note_arrow=nm.arrow;          // and the next note starts the same way, as the bar had it
              this.className='tool'+(nm.arrow ? ' on' : '');
              paintArrow();
              push(); render(); showMarks();
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
              $('curtain').textContent = (PICON && $('pichere') && $('pichere').checked===true)
                ? 'שחרר כאן — התמונות יתווספו לדף הפתוח' : 'שחרר כאן — כל תמונה תקבל דף';
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

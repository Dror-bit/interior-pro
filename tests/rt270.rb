# encoding: utf-8
# rt270 - a big set of loose lines is kept beside the model (2026-10-07).
#
# 6 Bronco Ln: a yard of 14,710 lines is 1.3 MB, the model takes 60 KB, so the
# whole list lived in memory. He rubbed two thousand lines out and drew new
# ones, and every bit of it would have gone the moment SketchUp closed. He was
# told, and said to go on.
#
# THE RULE THIS SUITE PINS:
#   A list too big for the model is written to a file beside the model, and
#   read back when the sheet opens. Closing SketchUp loses nothing.
# and the edges of it:
#   - not once per sweep of the eraser: the newest list waits two seconds and
#     is written once; closing the window or exporting writes at once;
#   - a list that fits on the model lives on the model, and leaves no file;
#   - a model never saved has no folder: memory only, as before, said once;
#   - the same model under a NEW NAME still finds its lines;
#   - ANOTHER model opened in the same SketchUp never gets these lines, on
#     its sheet or in its file;
#   - a broken file is not a crash.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'tmpdir'
require 'fileutils'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map do |o|
        { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f }
      end
    end
  end
end
require './door_library'
require './plan_generator'
require './plan_doc'
require './plan_tables'
require './plan_geometry'
require './plan_canvas'
require './plan_pdf'
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PSD = InteriorPro::PlanSheetDialog
PG  = InteriorPro::PlanGeometry
TRACE = File.join(PSD.plugin_dir, 'sheet_erase_trace.txt')
File.delete(TRACE) if File.exist?(TRACE)
JOB = Dir.mktmpdir('ip_job')

def line(n); [[n * 10.0, 0.0], [n * 10.0, 50.0]]; end
BIG   = (1..3000).map { |n| line(n) }          # ~90 KB: too big for the model
SMALL = (1..9).map { |n| line(n) }
ok('the big list really is too big for the model', JSON.generate(BIG).bytesize > PSD.singleton_class::SITE_ATTR_MAX, JSON.generate(BIG).bytesize)

IVARS = %i[@site_lines @site_dropped @site_saved @site_owner @site_owner_path @site_file_job
           @site_file_timer @site_file_checked @site_file_warned @doc @dialog].freeze
# SketchUp closed and opened again: nothing in memory, the model as it is
def restart!
  IVARS.each { |v| PSD.instance_variable_set(v, nil) }
  UI.reset_timers!
end
# a new model in a new SketchUp
def new_model!(name)
  restart!
  Sketchup.reset_model!
  Sketchup.active_model.path = name ? File.join(JOB, name) : nil
  Sketchup.active_model
end
def wait!                                   # the two seconds go by
  UI.timers.keys.each { |id| UI.fire_timer!(id) }
end
def file_for(name); File.join(JOB, PSD::SITE_FILE_DIR, name.sub(/\.skp\z/, '') + PSD::SITE_FILE_EXT); end
def in_file(name)
  f = file_for(name)
  File.file?(f) ? JSON.parse(File.read(f, encoding: 'UTF-8')) : nil
end
def on_model; Sketchup.active_model.get_attribute('InteriorPro', 'sheet_site_lines'); end
def open_window!
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end

ok('there is a switch, and it is on', PSD.const_defined?(:USE_SITE_FILE, false) && PSD::USE_SITE_FILE == true)

# ---------------------------------------------------------------------------
# 1. his case: a big yard, SketchUp closed, opened again
# ---------------------------------------------------------------------------
new_model!('6 Bronco Ln.skp')
PSD.site_lines = BIG
ok('too big: the model does not hold the list', on_model.nil?)
ok('nothing is written on the spot - it waits', in_file('6 Bronco Ln.skp').nil? && UI.timers.length == 1, UI.timers.length)
wait!
f = in_file('6 Bronco Ln.skp')
ok('TWO SECONDS LATER THE LIST IS IN A FILE BESIDE THE MODEL  <<< THE RULE', f && f['lines'] == BIG && f['count'] == 3000, f && f['count'])
ok('in the plugin\'s own folder there, named after the model',
   File.file?(File.join(JOB, 'InteriorPro_sheet', '6 Bronco Ln.sheet_lines.json')), Dir.children(JOB))
ok('nothing is left half written', Dir.children(File.join(JOB, PSD::SITE_FILE_DIR)).none? { |n| n.end_with?('.tmp') })
ok('the window is told the lines will be kept', PSD.site_kept? == true)

restart!
ok('SKETCHUP CLOSED AND OPENED: THE LINES ARE BACK  <<< THE RULE', PSD.site_lines == BIG, PSD.site_lines.length)
ok('and they are drawn on the sheet', (open_window!; PSD.document.canvas('MODEL').layers.find { |l| l.name == PG::LAYER }.shapes.length == 3000))

# what he rubbed out and what he drew are what comes back
dlg = open_window!
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [0, 5, 7], 'quiet' => true, 'n' => 3000))
dlg.callbacks['add_site_line'].call(nil, JSON.generate('p' => [[-5.0, -5.0], [-9.0, -9.0]], 'quiet' => true, 'n' => 2997))
ok('twenty changes in a row are ONE write waiting, not twenty', UI.timers.length == 1, UI.timers.length)
ok('and the file is not touched until then', in_file('6 Bronco Ln.skp')['count'] == 3000)
wait!
restart!
back = PSD.site_lines
ok('after closing: the three rubbed-out lines are still gone', back.length == 2998 && !back.include?(line(1)) && !back.include?(line(6)) && !back.include?(line(8)), back.length)
ok('...and the line he drew is still there, last', back.last == [[-5.0, -5.0], [-9.0, -9.0]], back.last)

# closing the window does not wait for the two seconds
dlg = open_window!
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [0], 'quiet' => true, 'n' => 2998))
ok('the window knows what to do when it is closed', dlg.on_closed.respond_to?(:call))
dlg.on_closed.call
ok('CLOSING THE WINDOW WRITES AT ONCE', in_file('6 Bronco Ln.skp')['count'] == 2997, in_file('6 Bronco Ln.skp')['count'])
ok('and nothing is left waiting', UI.timers.empty? && PSD.instance_variable_get(:@site_file_job).nil?)

# so does exporting
dlg = open_window!
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [0], 'quiet' => true, 'n' => 2997))
dlg.callbacks['export_pdf'].call(nil, JSON.generate(PSD.load_state))
ok('exporting the PDF writes at once too', in_file('6 Bronco Ln.skp')['count'] == 2996, in_file('6 Bronco Ln.skp')['count'])

# ---------------------------------------------------------------------------
# 2. a list that fits on the model lives on the model
# ---------------------------------------------------------------------------
new_model!('small.skp')
PSD.site_lines = SMALL
wait!
ok('a small list is on the model, and no file is made', !on_model.nil? && in_file('small.skp').nil?)
restart!
ok('and it comes back from the model', PSD.site_lines == SMALL)

# big, then cleared: the file must not bring the yard back
new_model!('cleared.skp')
PSD.site_lines = BIG
wait!
dlg = open_window!
dlg.callbacks['clear_selection'].call(nil)
wait!
ok('"clear the free geometry" takes the file away with it', in_file('cleared.skp').nil?, Dir.children(File.join(JOB, PSD::SITE_FILE_DIR)))
restart!
ok('so a cleared sheet stays cleared after closing', PSD.site_lines.empty?, PSD.site_lines.length)

# ---------------------------------------------------------------------------
# 3. a model that was never saved
# ---------------------------------------------------------------------------
new_model!(nil)
before = Dir.children(File.join(JOB, PSD::SITE_FILE_DIR)).sort
PSD.site_lines = BIG
PSD.site_lines = BIG.first(2999)
wait!
ok('never saved: nothing is written anywhere', Dir.children(File.join(JOB, PSD::SITE_FILE_DIR)).sort == before && UI.timers.empty?)
ok('the lines are still on the sheet', PSD.site_lines.length == 2999)
ok('and the window says they will NOT be kept', PSD.site_kept? == false)
tr = File.read(TRACE, encoding: 'UTF-8').lines
ok('it is said in the trace, once', tr.count { |l| l.include?('never been saved') } == 1, tr.last(2))
# ...then he saves it
Sketchup.active_model.path = File.join(JOB, 'now saved.skp')
PSD.site_lines = BIG.first(2998)
wait!
ok('once the model is saved, the next change is written beside it', in_file('now saved.skp') && in_file('now saved.skp')['count'] == 2998)

# ---------------------------------------------------------------------------
# 4. the same model under a new name
# ---------------------------------------------------------------------------
new_model!('v5.skp')
PSD.site_lines = BIG
wait!
Sketchup.active_model.path = File.join(JOB, 'v6.skp')            # Save As
ok('SAVE AS: the lines stay on the sheet', PSD.site_lines == BIG, PSD.site_lines.length)
PSD.site_lines = BIG.first(2990)
wait!
ok('and the next change is written under the new name', in_file('v6.skp') && in_file('v6.skp')['count'] == 2990)
ok('the old name keeps what it had', in_file('v5.skp')['count'] == 3000)

# Save As, and SketchUp closed before anything else changed
new_model!('first.skp')
PSD.site_lines = BIG
wait!
Sketchup.active_model.path = File.join(JOB, 'second.skp')
restart!
ok('SAVE AS AND CLOSE: opened under the new name, the lines are found by the mark',
   PSD.site_lines == BIG && in_file('second.skp').nil?, PSD.site_lines.length)

# closed without saving the MODEL: its mark is gone, the file is still its own
new_model!('unsaved change.skp')
PSD.site_lines = BIG
wait!
Sketchup.active_model.delete_attribute('InteriorPro', PSD::SITE_ID_ATTR)
restart!
ok('the model lost its mark (closed without saving): the file with its name is still read', PSD.site_lines == BIG)
ok('and the model gets the same mark back', Sketchup.active_model.get_attribute('InteriorPro', PSD::SITE_ID_ATTR) == in_file('unsaved change.skp')['id'])

# an undo took the mark away in the middle of the work
new_model!('undo.skp')
PSD.site_lines = BIG
id0 = Sketchup.active_model.get_attribute('InteriorPro', PSD::SITE_ID_ATTR)
Sketchup.active_model.delete_attribute('InteriorPro', PSD::SITE_ID_ATTR)
ok('an undo that takes the mark away does not lose a line', PSD.site_lines == BIG)
ok('and the same mark is put back', Sketchup.active_model.get_attribute('InteriorPro', PSD::SITE_ID_ATTR) == id0 && !id0.to_s.empty?)
wait!

# ---------------------------------------------------------------------------
# 5. another model, opened in the same SketchUp
# ---------------------------------------------------------------------------
new_model!('house A.skp')
PSD.site_lines = BIG
PSD.site_dropped = [line(1)]
Sketchup.reset_model!                                           # File > Open, no restart; A's write is still waiting
Sketchup.active_model.path = File.join(JOB, 'house B.skp')
ok('ANOTHER MODEL DOES NOT GET THE LAST ONE\'S LINES  <<< THE RULE', PSD.site_lines.empty?, PSD.site_lines.length)
ok('nor its rubbed-out lines', PSD.site_dropped.empty?)
ok('what was waiting went to the FIRST model\'s file', in_file('house A.skp') && in_file('house A.skp')['count'] == 3000)
ok('and nothing was written beside the second', in_file('house B.skp').nil?)
PSD.site_lines = BIG.first(2500)
wait!
ok('each model has its own file', in_file('house B.skp')['count'] == 2500 && in_file('house A.skp')['count'] == 3000 &&
   in_file('house B.skp')['id'] != in_file('house A.skp')['id'])
# back to A
Sketchup.reset_model!
Sketchup.active_model.path = File.join(JOB, 'house A.skp')
ok('going back to the first model brings ITS lines', PSD.site_lines == BIG, PSD.site_lines.length)

# a file with this model's name that is another model's (copied over) is not read
new_model!('copy.skp')
PSD.site_lines = BIG
wait!
restart!
Sketchup.active_model.set_attribute('InteriorPro', PSD::SITE_ID_ATTR, 'ffffffffffffffff')
ok('a file with the right name but another model\'s mark is not this model\'s list', PSD.site_lines.empty?, PSD.site_lines.length)

# ---------------------------------------------------------------------------
# 6. a broken file, a list from before this code
# ---------------------------------------------------------------------------
new_model!('broken.skp')
FileUtils.mkdir_p(File.join(JOB, PSD::SITE_FILE_DIR))
File.write(file_for('broken.skp'), '{"id":"x","lines":[[1,2')
ok('a broken file is not a crash - the sheet opens with no loose lines', (PSD.site_lines == [] rescue false))

# lines taken before this code was loaded (reload!): in memory, no mark, no file
new_model!('before.skp')
PSD.instance_variable_set(:@site_lines, BIG.dup)
PSD.instance_variable_set(:@site_saved, false)
ok('lines from before the reload are kept as this model\'s', PSD.site_lines == BIG)
open_window!
ok('OPENING THE WINDOW WRITES THEM DOWN AT ONCE - not at the next change',
   in_file('before.skp') && in_file('before.skp')['count'] == 3000, Dir.children(File.join(JOB, PSD::SITE_FILE_DIR)))

# ---------------------------------------------------------------------------
# 7. it is written down
# ---------------------------------------------------------------------------
tr = File.read(TRACE, encoding: 'UTF-8').lines
ok('every write leaves a line: how many, how big, how long, which file',
   tr.any? { |l| l =~ /lines file: 3000 lines, \d+ KB, \d+ ms, read back and counted -> 6 Bronco Ln\.sheet_lines\.json/ }, tr.first(2))
ok('a write after the first in a folder is not read back again', tr.any? { |l| l =~ /lines file: 2998 lines, \d+ KB, \d+ ms -> / })
ok('and so does every read', tr.any? { |l| l =~ /lines file: 3000 lines read back from 6 Bronco Ln\.sheet_lines\.json/ })
ok('taking the file away is written down too', tr.any? { |l| l.include?('taken away') })

# a folder that cannot be written is not a crash, and says so
new_model!('nowhere.skp')
Sketchup.active_model.path = File.join(JOB, 'no such folder', 'deeper', 'nowhere.skp')
PSD.site_lines = BIG
wait!
ok('a folder that cannot be written: the lines stay on the sheet', PSD.site_lines == BIG)
ok('and the trace says FAILED', File.read(TRACE, encoding: 'UTF-8').include?('lines file: FAILED'))

# ---------------------------------------------------------------------------
# 8. the switch
# ---------------------------------------------------------------------------
PSD.send(:remove_const, :USE_SITE_FILE)
PSD.const_set(:USE_SITE_FILE, false)
new_model!('off.skp')
PSD.site_lines = BIG
wait!
ok('switched off: no file, no mark on the model, memory only - as before',
   in_file('off.skp').nil? && Sketchup.active_model.get_attribute('InteriorPro', PSD::SITE_ID_ATTR).nil? && PSD.site_kept? == false)
restart!
ok('switched off: closing SketchUp loses the list, as before', PSD.site_lines.empty?)
PSD.send(:remove_const, :USE_SITE_FILE)
PSD.const_set(:USE_SITE_FILE, true)

FileUtils.rm_rf(JOB)
File.delete(TRACE) if File.exist?(TRACE)
puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

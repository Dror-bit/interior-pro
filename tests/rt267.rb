# encoding: utf-8
# rt267 - Ctrl+Z on rubbed-out lines, the Ruby side (2026-10-07).
#
# The user: "אם מחקתי משהו ואני לוחץ קונטרול Z הוא צריך לחזור."
#
# t68 pins the window: one press, one sweep back, each line at the number it
# had. This pins what Ruby does with the message the window sends:
#
#   - the lines go back into the LIST at their numbers, and into the document
#     Ruby is holding at the same numbers - shape number i is line number i
#     again, exactly as before the sweep - and nothing is rebuilt or sent;
#   - they leave the waiting list, so "put back everything" does not bring
#     them back a second time;
#   - Ruby believes the window only if both count the same number of lines,
#     every number fits, and every line really is one that was rubbed out.
#     Anything else: nothing is changed and the whole sheet is sent, so the
#     window shows what Ruby actually has.
ENV['REAL_ROOMS'] = '1'
require 'json'
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

def line(n)
  [[n * 100.0, 0.0], [n * 100.0, 50.0]]
end
NINE = (1..9).map { |n| line(n) }

def open!(lines)
  Sketchup.reset_model!
  Sketchup.active_model.delete_attribute('InteriorPro', 'sheet_state')
  PSD.site_lines   = lines
  PSD.site_dropped = []
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end

def sheets_sent(dlg); dlg.scripts.count { |s| s.start_with?('loadSheet(') }; end
def site_layer; PSD.document.canvas('MODEL').layers.find { |l| l.name == PG::LAYER }; end
def layer_firsts
  lay = site_layer
  lay ? lay.shapes.map { |s| (s[:points] || s['points'])[0][0].to_f } : []
end
def list_firsts; PSD.site_lines.map { |l| l[0][0].to_f }; end
def drop!(dlg, is, n); dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => is, 'quiet' => true, 'n' => n)); end
# exactly what the window sends: each line with the number it had, through JSON
def undo!(dlg, items, n)
  dlg.callbacks['undo_site_drop'].call(nil, JSON.generate('items' => items.map { |i, l| { 'i' => i, 'p' => l } }, 'n' => n))
end

ok('there is a switch, and it is on', PSD.const_defined?(:USE_SHEET_UNDO, false) && PSD::USE_SHEET_UNDO == true)

dlg = open!(NINE)
ok('the window can ask for a rub-out to be taken back', dlg.callbacks.key?('undo_site_drop'), dlg.callbacks.keys)

# ---------------------------------------------------------------------------
# 1. two sweeps, taken back one at a time - newest first
# ---------------------------------------------------------------------------
doc0 = PSD.document
sent = sheets_sent(dlg)
drop!(dlg, [1, 6, 4], 9)                 # lines 200, 500, 700 go
drop!(dlg, [0], 6)                       # then line 100
ok('two sweeps took four lines', list_firsts == [300.0, 400.0, 600.0, 800.0, 900.0], list_firsts)

undo!(dlg, [[0, line(1)]], 5)
ok('THE LAST SWEEP IS BACK, AT THE NUMBER IT HAD  <<< THE RULE',
   list_firsts == [100.0, 300.0, 400.0, 600.0, 800.0, 900.0], list_firsts)
ok('in the document Ruby is holding too - shape i is line i again', layer_firsts == list_firsts, layer_firsts)
ok('nothing was built again and nothing was sent', PSD.document.equal?(doc0) && sheets_sent(dlg) == sent)
ok('the window is told the two numbers', dlg.scripts.last == 'siteDropped(6, 3)', dlg.scripts.last)

undo!(dlg, [[1, line(2)], [4, line(5)], [6, line(7)]], 6)
ok('THE SWEEP BEFORE IT IS BACK: all three, each in its own place',
   list_firsts == (1..9).map { |n| n * 100.0 }, list_firsts)
ok('and the document matches, line for line', layer_firsts == list_firsts, layer_firsts)
ok('still the same document, still nothing sent', PSD.document.equal?(doc0) && sheets_sent(dlg) == sent)
ok('nothing is left waiting - "put back everything" will not bring them a second time',
   PSD.site_dropped.empty? && dlg.scripts.last == 'siteDropped(9, 0)', [PSD.site_dropped.length, dlg.scripts.last])
dlg.callbacks['restore_site_lines'].call(nil)
ok('and it does not', PSD.site_lines.length == 9, PSD.site_lines.length)

# the shape that came back is written like every other one
sh = site_layer.shapes[1]
ok('a line that came back is the same kind of shape as one that never left',
   sh[:type] == site_layer.shapes[0][:type] && sh[:weight] == site_layer.shapes[0][:weight] && sh[:closed] == false, sh)

# rub out again after an undo: the numbers still mean the right lines
drop!(dlg, [4], 9)
ok('rubbing out again after an undo takes the right line', !list_firsts.include?(500.0) && layer_firsts == list_firsts, list_firsts)

# ---------------------------------------------------------------------------
# 2. the window sends the lines in any order
# ---------------------------------------------------------------------------
dlg = open!(NINE)
drop!(dlg, [2, 7], 9)
undo!(dlg, [[7, line(8)], [2, line(3)]], 7)
ok('the order they arrive in does not matter', list_firsts == (1..9).map { |n| n * 100.0 } && layer_firsts == list_firsts, list_firsts)

# the very last line, rubbed out and brought back
dlg = open!([line(1)])
drop!(dlg, [0], 1)
ok('the sheet is empty and has no loose-line layer', site_layer.nil?)
undo!(dlg, [[0, line(1)]], 0)
ok('the last line of all comes back onto an empty sheet', list_firsts == [100.0] && layer_firsts == [100.0], [list_firsts, layer_firsts])

# ---------------------------------------------------------------------------
# 3. Ruby does not believe a message that does not add up
# ---------------------------------------------------------------------------
dlg  = open!(NINE)
drop!(dlg, [3], 9)
sent = sheets_sent(dlg)
undo!(dlg, [[3, line(4)]], 5)                     # the window thinks there were 5; there are 8
ok('OUT OF STEP on the count: nothing is put back', list_firsts.length == 8, list_firsts.length)
ok('...and the whole sheet is sent, so the window shows what Ruby has', sheets_sent(dlg) == sent + 1)

sent = sheets_sent(dlg)
undo!(dlg, [[3, [[1.0, 2.0], [3.0, 4.0]]]], 8)    # a line nobody rubbed out
ok('a line that was never rubbed out is NOT put on the sheet', list_firsts.length == 8 && sheets_sent(dlg) == sent + 1,
   [list_firsts.length, sheets_sent(dlg) - sent])

sent = sheets_sent(dlg)
undo!(dlg, [[40, line(4)]], 8)                    # a number off the end
ok('a number that does not fit is refused', list_firsts.length == 8 && sheets_sent(dlg) == sent + 1)
ok('and after all that the line is still waiting, and still comes back properly',
   (undo!(dlg, [[3, line(4)]], 8); list_firsts == (1..9).map { |n| n * 100.0 }), list_firsts)

# the lines were read again (add what is selected): the waiting list is emptied there, so an old undo finds nothing
dlg = open!(NINE)
drop!(dlg, [3], 9)
PSD.site_lines = NINE.first(8)
PSD.site_dropped = []
PSD.instance_variable_set(:@doc, nil)
undo!(dlg, [[3, line(4)]], 8)
ok('after the lines are read again an old rub-out cannot be put back on top of them', PSD.site_lines.length == 8)

# ---------------------------------------------------------------------------
# 4. it is written down
# ---------------------------------------------------------------------------
tr = File.exist?(TRACE) ? File.read(TRACE, encoding: 'UTF-8').lines : []
ok('an undo leaves a line in sheet_erase_trace.txt', tr.any? { |l| l =~ /undo: 1 back, \d+ on the sheet, quick, \d+ ms/ }, tr.first(3))
ok('and a refused one says REFUSED', tr.any? { |l| l.include?('REFUSED') })

# ---------------------------------------------------------------------------
# 5. the switch
# ---------------------------------------------------------------------------
PSD.send(:remove_const, :USE_SHEET_UNDO)
PSD.const_set(:USE_SHEET_UNDO, false)
dlg = open!(NINE)
drop!(dlg, [3], 9)
undo!(dlg, [[3, line(4)]], 8)
ok('switched off: nothing is put back', PSD.site_lines.length == 8)
PSD.send(:remove_const, :USE_SHEET_UNDO)
PSD.const_set(:USE_SHEET_UNDO, true)
File.delete(TRACE) if File.exist?(TRACE)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

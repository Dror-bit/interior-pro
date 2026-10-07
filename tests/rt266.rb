# encoding: utf-8
# rt266 - rubbing a line out does not build the sheet again (2026-10-07).
#
# The user, rubbing lines out of a yard of 15,000: "לוקח לו קצת זמן עד שהוא מוחק
# וצריך שזה יהיה יותר מהיר".
#
# What one sweep of the eraser used to cost: the window sent the numbers, Ruby
# threw its document away, read the WHOLE model again (every wall, door and
# window of the house, wherever they sit), wrote every one of the 15,000 lines
# back into a new document, turned it into a megabyte and a half of JSON, and
# the window drew all of it from nothing. To take away one line.
#
# THE RULE THIS SUITE PINS, on the Ruby side (t66 pins the window's):
#   The window takes the lines off its own sheet and says which ones went.
#   Ruby takes the same ones out of its list AND out of the document it is
#   holding - shape number i still IS line number i, on both - and answers
#   with two numbers. Nothing is rebuilt and nothing is sent.
#   If the two sides disagree about how many lines there were, Ruby builds the
#   sheet and sends all of it, which puts the window right.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'tmpdir'
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

# the trace is written beside the plugin; in a suite that is this folder
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

def sheets_sent(dlg)
  dlg.scripts.count { |s| s.start_with?('loadSheet(') }
end

def site_layer
  PSD.document.canvas('MODEL').layers.find { |l| l.name == PG::LAYER }
end

def firsts_of_layer
  lay = site_layer
  lay ? lay.shapes.map { |s| (s[:points] || s['points'])[0][0].to_f } : []
end

def firsts_of_list
  PSD.site_lines.map { |l| l[0][0].to_f }
end

ok('there is a switch, and it is on', PSD.const_defined?(:USE_FAST_ERASE, false) && PSD::USE_FAST_ERASE == true)

# ---------------------------------------------------------------------------
# 1. his case: a sweep across three lines, the window already took them off
# ---------------------------------------------------------------------------
dlg  = open!(NINE)
doc0 = PSD.document
sent = sheets_sent(dlg)
ok('the sheet opened with all nine lines on it', firsts_of_layer.length == 9, firsts_of_layer)

dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [1, 6, 4], 'quiet' => true, 'n' => 9))

ok('the three lines are out of the list', firsts_of_list == [100.0, 300.0, 400.0, 600.0, 800.0, 900.0], firsts_of_list)
ok('NOTHING WAS BUILT AGAIN: Ruby is holding the very same document  <<< THE RULE',
   PSD.document.equal?(doc0))
ok('NOTHING WAS SENT AGAIN: no new sheet went to the window', sheets_sent(dlg) == sent, sheets_sent(dlg) - sent)
ok('the same three lines are out of that document', firsts_of_layer == firsts_of_list, firsts_of_layer)
ok('shape number i is STILL line number i - the next rub-out takes the right line',
   firsts_of_layer.each_with_index.all? { |v, i| v == PSD.site_lines[i][0][0].to_f })
ok('the window is told how many are left and how many can come back',
   dlg.scripts.last == 'siteDropped(6, 3)', dlg.scripts.last)
ok('the three are kept, ready to come back', PSD.site_dropped.length == 3, PSD.site_dropped.length)

# and again, on the shortened sheet
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [0], 'quiet' => true, 'n' => 6))
ok('a second sweep reads the shortened sheet', firsts_of_list == [300.0, 400.0, 600.0, 800.0, 900.0] &&
   firsts_of_layer == firsts_of_list, [firsts_of_list, firsts_of_layer])
ok('still the same document, still nothing sent', PSD.document.equal?(doc0) && sheets_sent(dlg) == sent)

# what he prints is what he sees
pdf_doc = PSD.document
ok('the document that would be printed has exactly the lines left on the screen',
   pdf_doc.canvas('MODEL').layers.find { |l| l.name == PG::LAYER }.shapes.length == 5)

# ---------------------------------------------------------------------------
# 2. out of step: the window counted a different number of lines
# ---------------------------------------------------------------------------
dlg  = open!(NINE)
sent = sheets_sent(dlg)
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [2], 'quiet' => true, 'n' => 7))
ok('the line still goes', firsts_of_list.length == 8 && !firsts_of_list.include?(300.0), firsts_of_list)
ok('OUT OF STEP: the whole sheet is built and sent, which puts the window right',
   sheets_sent(dlg) == sent + 1, sheets_sent(dlg) - sent)
ok('and what was sent has the eight lines', firsts_of_layer == firsts_of_list)

# ---------------------------------------------------------------------------
# 3. the last line of all
# ---------------------------------------------------------------------------
dlg = open!([line(1)])
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [0], 'quiet' => true, 'n' => 1))
ok('rubbing out the last line leaves no empty layer behind', site_layer.nil?,
   PSD.document.canvas('MODEL').layers.map(&:name))
ok('and the window is told there is nothing left', dlg.scripts.last == 'siteDropped(0, 1)', dlg.scripts.last)

# ---------------------------------------------------------------------------
# 4. the old message still works - a window that never heard of the quick road
# ---------------------------------------------------------------------------
dlg  = open!(NINE)
sent = sheets_sent(dlg)
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('i' => 4))
ok('an old-style message takes the line and sends the sheet, as it always did',
   firsts_of_list.length == 8 && sheets_sent(dlg) == sent + 1, [firsts_of_list.length, sheets_sent(dlg) - sent])

# numbers that are not on the sheet change nothing
dlg  = open!(NINE)
sent = sheets_sent(dlg)
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [-1, 9, 99], 'quiet' => true, 'n' => 9))
ok('numbers that are not on the sheet take nothing', firsts_of_list.length == 9 && sheets_sent(dlg) == sent)

# ---------------------------------------------------------------------------
# 5. it writes down what it did and how long it took
# ---------------------------------------------------------------------------
tr = File.exist?(TRACE) ? File.read(TRACE, encoding: 'UTF-8').lines : []
ok('every sweep leaves a line in sheet_erase_trace.txt', tr.length >= 5, tr.length)
ok('saying how many went, how many are left, which road, and how long',
   tr.first.to_s =~ /3 gone, 6 left, quick, \d+ ms/, tr.first)
ok('and the out-of-step one says so', tr.any? { |l| l.include?('full') }, tr)

# ---------------------------------------------------------------------------
# 6. the switch
# ---------------------------------------------------------------------------
PSD.send(:remove_const, :USE_FAST_ERASE)
PSD.const_set(:USE_FAST_ERASE, false)
dlg  = open!(NINE)
sent = sheets_sent(dlg)
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [1], 'quiet' => true, 'n' => 9))
ok('switched off: every rub-out builds and sends the whole sheet, as before',
   sheets_sent(dlg) == sent + 1 && firsts_of_list.length == 8)
PSD.send(:remove_const, :USE_FAST_ERASE)
PSD.const_set(:USE_FAST_ERASE, true)
File.delete(TRACE) if File.exist?(TRACE)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

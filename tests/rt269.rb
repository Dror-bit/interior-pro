# encoding: utf-8
# rt269 - drawing a line onto the sheet, the Ruby side (2026-10-07).
#
# The user: "הוספת קווים ע"י ציור" - and, asked which way: "תעשה את שני האופציות,
# 1 קו אחד עם שני קליקים ואחת עם קו מתמשך."
#
# t70 pins the window: the two tools, the locking, Escape, Ctrl+Z. To Ruby both
# tools are the same thing - one line of two points at a time - and this pins
# what Ruby does with it:
#
#   - the line goes on the END of the list of loose lines and on the end of
#     the same layer in the document Ruby is holding, written like every other
#     one. Shape number i is still line number i, so the eraser, the select
#     arrow and Delete reach it with nothing written for them;
#   - nothing is rebuilt and nothing is sent when the window and Ruby agree on
#     how many lines there were. When they do not - or the sheet had no loose
#     lines yet, so there is no layer - the sheet is built and sent;
#   - what is printed is what is on the screen: a document built from nothing
#     afterwards has the drawn line, in the same place in the list;
#   - Ctrl+Z takes a drawn line off again, and it does NOT join the rubbed-out
#     lines that "put back everything" brings back;
#   - a message that does not add up changes nothing.
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
NEW1 = [[-350.0, 200.0], [-250.0, 230.0]].freeze
NEW2 = [[-250.0, 230.0], [-150.0, 200.0]].freeze

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
def layer_lines
  lay = site_layer
  lay ? lay.shapes.map { |s| s[:points] } : []
end
# exactly what the window sends, through JSON
def draw!(dlg, pts, n = nil)
  h = { 'p' => pts }
  h.merge!('quiet' => true, 'n' => n) unless n.nil?
  dlg.callbacks['add_site_line'].call(nil, JSON.generate(h))
end
def undraw!(dlg, items, n)
  dlg.callbacks['undo_site_add'].call(nil, JSON.generate('items' => items.map { |i, l| { 'i' => i, 'p' => l } }, 'n' => n))
end

ok('there is a switch, and it is on', PSD.const_defined?(:USE_LINE_DRAW, false) && PSD::USE_LINE_DRAW == true)

dlg = open!(NINE)
ok('the window can send a drawn line, and take one back',
   dlg.callbacks.key?('add_site_line') && dlg.callbacks.key?('undo_site_add'), dlg.callbacks.keys)
ok('the sheet tells the window that drawing is on', dlg.scripts.last(3).join =~ /"line_draw":true/ ||
   dlg.scripts.any? { |s| s.start_with?('loadSheet(') && s.include?('"line_draw":true') })

# ---------------------------------------------------------------------------
# 1. one line, the window already has it on its sheet
# ---------------------------------------------------------------------------
doc0 = PSD.document
sent = sheets_sent(dlg)
draw!(dlg, NEW1, 9)
ok('THE LINE IS ON THE END OF THE LIST  <<< THE RULE', PSD.site_lines.length == 10 && PSD.site_lines.last == NEW1, PSD.site_lines.last)
ok('the nine that were there are untouched, in their places', PSD.site_lines.first(9) == NINE)
ok('NOTHING WAS BUILT AGAIN: Ruby is holding the very same document', PSD.document.equal?(doc0))
ok('NOTHING WAS SENT AGAIN: no new sheet went to the window', sheets_sent(dlg) == sent, sheets_sent(dlg) - sent)
ok('the same line is on the end of the layer in that document', layer_lines.length == 10 && layer_lines.last == NEW1, layer_lines.last)
ok('shape number i is STILL line number i', layer_lines == PSD.site_lines)
sh = site_layer.shapes.last
ok('it is written like every other loose line',
   sh[:type] == site_layer.shapes[0][:type] && sh[:weight] == site_layer.shapes[0][:weight] && sh[:closed] == false, sh)
ok('the window is told how many lines there are now', dlg.scripts.last == 'siteDropped(10, 0)', dlg.scripts.last)

# the running line: the next one, with the count as it grew
draw!(dlg, NEW2, 10)
ok('the next line of a run goes on after it', PSD.site_lines.last(2) == [NEW1, NEW2] && layer_lines == PSD.site_lines &&
   PSD.document.equal?(doc0) && sheets_sent(dlg) == sent, PSD.site_lines.last(2))

# the eraser reaches a drawn line by its number, like any other
dlg.callbacks['drop_site_line'].call(nil, JSON.generate('is' => [9], 'quiet' => true, 'n' => 11))
ok('the eraser takes a drawn line by its number, like any other',
   PSD.site_lines.length == 10 && PSD.site_lines.last == NEW2 && layer_lines == PSD.site_lines, PSD.site_lines.last(2))

# what he prints is what he sees: build the document from nothing
PSD.instance_variable_set(:@doc, nil)
ok('A DOCUMENT BUILT FROM NOTHING HAS THE DRAWN LINE - what is printed is what is on the screen',
   layer_lines.length == 10 && layer_lines.last == NEW2 && layer_lines == PSD.site_lines, layer_lines.last)

# numbers are kept to a hundredth of an inch, like every loose line read off the model
dlg = open!(NINE)
draw!(dlg, [[1.23456, 2.0], [3.999, 4.004]], 9)
ok('a drawn line is kept to a hundredth of an inch', PSD.site_lines.last == [[1.23, 2.0], [4.0, 4.0]], PSD.site_lines.last)

# ---------------------------------------------------------------------------
# 2. out of step, and the sheet with no loose lines
# ---------------------------------------------------------------------------
dlg  = open!(NINE)
sent = sheets_sent(dlg)
draw!(dlg, NEW1, 7)                                  # the window thinks there were 7; there are 9
ok('OUT OF STEP on the count: the line is still added', PSD.site_lines.length == 10 && PSD.site_lines.last == NEW1)
ok('...and the whole sheet is sent, which puts the window right', sheets_sent(dlg) == sent + 1 && layer_lines == PSD.site_lines)

dlg  = open!([])
sent = sheets_sent(dlg)
ok('a sheet with no loose lines has no layer for them', site_layer.nil?)
draw!(dlg, NEW1)                                     # the window could not add it itself: no quiet, no count
ok('THE FIRST LINE EVER DRAWN: Ruby makes the layer and sends the sheet',
   PSD.site_lines == [NEW1] && layer_lines == [NEW1] && sheets_sent(dlg) == sent + 1, [PSD.site_lines, sheets_sent(dlg) - sent])
sent = sheets_sent(dlg)
draw!(dlg, NEW2, 1)
ok('and the one after it takes the quick road', PSD.site_lines == [NEW1, NEW2] && layer_lines == PSD.site_lines && sheets_sent(dlg) == sent)

# ---------------------------------------------------------------------------
# 3. what is not a line is not added
# ---------------------------------------------------------------------------
dlg = open!(NINE)
[[[1.0, 2.0], [1.0, 2.0]],              # both ends in the same place
 [[1.0, 2.0]],                          # one point
 [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]],  # three
 [[1.0, 'x'], [3.0, 4.0]],              # not a number
 [[1.0, 2.0], [3.0]],                   # half a point
 nil, 'line', 7].each do |bad|
  sent = sheets_sent(dlg)
  draw!(dlg, bad, PSD.site_lines.length)
  ok("not a line, not added: #{bad.inspect[0, 40]}", PSD.site_lines == NINE && sheets_sent(dlg) == sent + 1,
     [PSD.site_lines.length, sheets_sent(dlg) - sent])
end
ok('a point that rounds onto the other is not a line either',
   (draw!(dlg, [[1.001, 2.0], [1.004, 2.0]], 9); PSD.site_lines == NINE))

# ---------------------------------------------------------------------------
# 4. Ctrl+Z on a drawn line
# ---------------------------------------------------------------------------
dlg  = open!(NINE)
draw!(dlg, NEW1, 9)
draw!(dlg, NEW2, 10)
doc0 = PSD.document
sent = sheets_sent(dlg)
undraw!(dlg, [[10, NEW2]], 11)
ok('CTRL+Z TAKES THE LAST DRAWN LINE OFF  <<< THE RULE', PSD.site_lines.length == 10 && PSD.site_lines.last == NEW1, PSD.site_lines.last)
ok('off the document Ruby is holding too', layer_lines == PSD.site_lines)
ok('nothing was built again and nothing was sent', PSD.document.equal?(doc0) && sheets_sent(dlg) == sent)
ok('the window is told the two numbers', dlg.scripts.last == 'siteDropped(10, 0)', dlg.scripts.last)
ok('IT IS NOT WAITING TO BE PUT BACK - "put back everything" must not bring a line he took back', PSD.site_dropped.empty?)
undraw!(dlg, [[9, NEW1]], 10)
ok('the one before it comes off next, and the yard is as it was', PSD.site_lines == NINE && layer_lines == NINE)

# Ruby does not believe a message that does not add up
dlg  = open!(NINE)
draw!(dlg, NEW1, 9)
sent = sheets_sent(dlg)
undraw!(dlg, [[9, NEW1]], 7)                         # wrong count
ok('OUT OF STEP on the count: nothing comes off, the sheet is sent', PSD.site_lines.length == 10 && sheets_sent(dlg) == sent + 1)
sent = sheets_sent(dlg)
undraw!(dlg, [[3, NEW1]], 10)                        # that number holds a line of the yard
ok('A NUMBER THAT HOLDS ANOTHER LINE IS REFUSED - a line of the yard is never taken off by an undo',
   PSD.site_lines.length == 10 && PSD.site_lines[3] == line(4) && sheets_sent(dlg) == sent + 1, PSD.site_lines[3])
sent = sheets_sent(dlg)
undraw!(dlg, [[40, NEW1]], 10)                       # off the end
ok('a number off the end is refused', PSD.site_lines.length == 10 && sheets_sent(dlg) == sent + 1)
ok('and after all that the right message still works', (undraw!(dlg, [[9, NEW1]], 10); PSD.site_lines == NINE))

# the last line of all: drawn on an empty sheet, taken back
dlg = open!([])
draw!(dlg, NEW1)
undraw!(dlg, [[0, NEW1]], 1)
ok('the only line on the sheet, taken back, leaves no empty layer behind', PSD.site_lines.empty? && site_layer.nil?,
   [PSD.site_lines, PSD.document.canvas('MODEL').layers.map(&:name)])

# ---------------------------------------------------------------------------
# 5. it is written down
# ---------------------------------------------------------------------------
tr = File.exist?(TRACE) ? File.read(TRACE, encoding: 'UTF-8').lines : []
ok('every drawn line leaves a line in sheet_erase_trace.txt', tr.any? { |l| l =~ /draw: 1 added, 10 on the sheet, quick, \d+ ms/ }, tr.first(3))
ok('the long road says so', tr.any? { |l| l =~ /draw: 1 added, \d+ on the sheet, full/ })
ok('taking one back is written down too', tr.any? { |l| l =~ /undo draw: 1 off, \d+ on the sheet, quick, \d+ ms/ })
ok('and a refused one says REFUSED', tr.any? { |l| l.include?('draw: REFUSED') } && tr.any? { |l| l =~ /undo draw: 0 off.*REFUSED/ })

# ---------------------------------------------------------------------------
# 6. the switch
# ---------------------------------------------------------------------------
PSD.send(:remove_const, :USE_LINE_DRAW)
PSD.const_set(:USE_LINE_DRAW, false)
dlg = open!(NINE)
ok('switched off: the window is told', dlg.scripts.any? { |s| s.start_with?('loadSheet(') && s.include?('"line_draw":false') })
draw!(dlg, NEW1, 9)
ok('switched off: Ruby takes no drawn line', PSD.site_lines == NINE)
PSD.send(:remove_const, :USE_LINE_DRAW)
PSD.const_set(:USE_LINE_DRAW, true)
File.delete(TRACE) if File.exist?(TRACE)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt276 - the number of a dimension can be written over by hand (2026-10-07).
#
# The user: "אני רוצה שיהיה אפשרי לערוך את המידות - את המספרים שלהם בתוך." Asked
# whether his words replace the number for good or sit beside a number that
# keeps counting, he answered 1: THEY REPLACE IT, and stay whatever the
# dimension is stretched to.
#
#   a hand dimension   keeps the words on the mark itself ('label')
#   any other label    keeps them under its key in text_marks ('text'), the
#                      way its size and weight are kept
#   empty = the label's own words again
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map { |o| { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f } }
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
PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PSD = InteriorPro::PlanSheetDialog
SRC = File.read('plan_sheet_dialog.rb', encoding: 'UTF-8')

def lay_with(marks, text_marks = {})
  doc = PD::Document.new('t')
  doc.canvas('MODEL').layer('DIMENSIONS').text("12'-0\"", 0, 0, h: 5.0)
  doc.canvas('MODEL').layer('ROOMS').text('ROOM 2', 0, 0, h: 7.0)
  st = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
         'marks' => marks, 'text_marks' => text_marks }
  PC.layout_pages!(doc, st)
  doc
end
def texts(doc, layer)
  l = doc.canvas('MODEL').layers.find { |x| x.name == layer }
  l ? l.shapes.select { |s| s[:type] == :text } : []
end
DIM = { 't' => 'dim', 'x1' => 0.0, 'y1' => 0.0, 'x2' => 144.0, 'y2' => 0.0, 'off' => 20.0 }.freeze

ok('there is a switch, and it is on', PC.const_defined?(:USE_TEXT_WORDS, false) && PC::USE_TEXT_WORDS == true)

# ---- a hand dimension
d0 = lay_with([DIM])
ok("NOTHING WRITTEN: a hand dimension reads its measured length, as always", texts(d0, 'NOTES').map { |s| s[:text] } == ["12'-0\""], texts(d0, 'NOTES'))
d1 = lay_with([DIM.merge('label' => "12'-0\" V.I.F.")])
t1 = texts(d1, 'NOTES')
ok("HIS WORDS REPLACE THE NUMBER  <<< THE RULE (he chose 1)", t1.length == 1 && t1[0][:text] == "12'-0\" V.I.F.", t1)
ok('at the same place, the same size, turned with the line, as the number was',
   t1[0][:x] == texts(d0, 'NOTES')[0][:x] && t1[0][:y] == texts(d0, 'NOTES')[0][:y] && t1[0][:h] == 5.0 && t1[0][:follow] == true, t1[0])
d2 = lay_with([DIM.merge('label' => 'HOLD', 'x2' => 240.0)])
ok('STRETCHED TO TWENTY FEET, THE WORDS STAY  <<< THE RULE', texts(d2, 'NOTES')[0][:text] == 'HOLD')
d3 = lay_with([DIM.merge('label' => '   ')])
ok('blank words = the number again', texts(d3, 'NOTES')[0][:text] == "12'-0\"")

# ---- any other label, under its key
key = "DIMENSIONS|12'-0\"|1"
d4 = lay_with([], key => { 'text' => "12'-0\" +/-" })
ok("THE PLUGIN'S OWN DIMENSION NUMBER WRITTEN OVER, under its key", texts(d4, 'DIMENSIONS')[0][:text] == "12'-0\" +/-", texts(d4, 'DIMENSIONS'))
ok('the key stays the one made from the words as BUILT, so the choice finds its label again', texts(d4, 'DIMENSIONS')[0][:key] == key, texts(d4, 'DIMENSIONS')[0][:key])
PC.layout_pages!(d4, { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [], 'marks' => [], 'text_marks' => { key => { 'text' => "12'-0\" +/-" } } })
ok('laid out twice: the same, not doubled', texts(d4, 'DIMENSIONS')[0][:text] == "12'-0\" +/-" && texts(d4, 'DIMENSIONS')[0][:key] == key)
PC.layout_pages!(d4, { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [], 'marks' => [], 'text_marks' => {} })
ok('the choice taken away: the words as built come back, on the same document', texts(d4, 'DIMENSIONS')[0][:text] == "12'-0\"" && texts(d4, 'DIMENSIONS')[0][:key] == key, texts(d4, 'DIMENSIONS')[0])
d5 = lay_with([], 'ROOMS|ROOM 2|1' => { 'text' => 'MASTER', 'pct' => 150 })
ok('a room renamed on the sheet, and its size kept with it', texts(d5, 'ROOMS')[0][:text] == 'MASTER' && texts(d5, 'ROOMS')[0][:h] == 10.5, texts(d5, 'ROOMS')[0])
d6 = lay_with([], key => { 'text' => 7 })
ok('words that are not words are ignored', texts(d6, 'DIMENSIONS')[0][:text] == "12'-0\"")

begin
  PC.send(:remove_const, :USE_TEXT_WORDS); PC.const_set(:USE_TEXT_WORDS, false)
  d7 = lay_with([DIM.merge('label' => 'HOLD')], key => { 'text' => 'X' })
  ok('SWITCHED OFF: both are ignored', texts(d7, 'NOTES')[0][:text] == "12'-0\"" && texts(d7, 'DIMENSIONS')[0][:text] == "12'-0\"")
ensure
  PC.send(:remove_const, :USE_TEXT_WORDS); PC.const_set(:USE_TEXT_WORDS, true)
end

# ---- the way in from the window
ok('the switch goes with the sheet', SRC.include?('text_words: InteriorPro::PlanCanvas::USE_TEXT_WORDS'))
ok('set_text_mark takes the words, and an empty box takes them away',
   SRC.include?("if r.key?('text')") && SRC.include?("cur.delete('text')") && SRC.include?("cur['text'] = t"))
ok('the bar has a box for the words', SRC.include?('id="txwords"'))
ok('and the window writes a hand dimension\'s onto the mark', SRC.include?('m.label=t') && SRC.include?('function dimLabelText'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

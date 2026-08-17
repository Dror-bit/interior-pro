# encoding: utf-8
# rt67 - one label at a time, and the space bar (2026-08-17).
#
# The user: "יש כיתוב ואני לוחץ עליו פעמיים ואז נפתחת לי עמודה קטנה עם אפציות
# של גודל הכיתוב ובחירת סוג עיצוב". And: the space bar should put him back in
# select mode, the way it does in SketchUp.
#
# THE PROBLEM THIS SUITE IS REALLY ABOUT.
#
# rt66 gave every GROUP a size. This is the other half: one label. But the
# automatic labels - ROOM 2, W101, the dimension numbers - are thrown away and
# rebuilt out of the model every time the sheet is laid out. Point at one with
# a position or an array index and the choice lands on a different label the
# moment anything changes, or on nothing at all. So every text is NAMED, and
# the name is what the choice hangs on.
#
# The name is: layer | the words | which one of those words, down the layer.
# It costs plan_generator nothing, which is the whole reason it was chosen -
# the generator does not know the sheet exists and it stays that way.
#
# Its two known weaknesses are pinned below as tests rather than left to be
# discovered: rename the thing and the formatting is orphaned; two labels
# reading the same are told apart only by their order.
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

PC  = InteriorPro::PlanCanvas
PD  = InteriorPro::PlanDoc
PSD = InteriorPro::PlanSheetDialog

SRC = File.read('./plan_sheet_dialog.rb', encoding: 'UTF-8')

ROOMS = PC::LAYERS[:rooms]
DIMS  = PC::LAYERS[:dimensions]

def doc_with(texts)
  doc = PD::Document.new('t')
  cv  = doc.canvas('MODEL')
  texts.each { |layer, str, h| cv.layer(layer).text(str, 0, 0, h: h) }
  doc
end

def texts_on(doc, layer)
  lay = doc.canvas('MODEL').layers.find { |l| l.name == layer }
  lay ? lay.shapes.select { |s| s[:type] == :text } : []
end

def basic_doc
  doc_with([[ROOMS, 'ROOM 2', 7.0], [ROOMS, '42 SF', 4.5],
            [DIMS, "12'-0\"", 5.0], [DIMS, "12'-0\"", 5.0],
            [DIMS, "17'-4.4\"", 5.0]])
end

# ---------------------------------------------------------------------------
# 1. every text gets a name, and the same name every time
# ---------------------------------------------------------------------------
doc = basic_doc
PC.apply_text_scale!(doc, {})
keys = texts_on(doc, ROOMS).map { |s| s[:key] } + texts_on(doc, DIMS).map { |s| s[:key] }

ok('every text is named', keys.none? { |k| k.nil? || k.empty? }, keys)
ok('no two labels share a name', keys.uniq.length == keys.length, keys)
ok('the name says which layer it is on',
   texts_on(doc, ROOMS).first[:key].start_with?(ROOMS), texts_on(doc, ROOMS).first[:key])
ok('and what it says',
   texts_on(doc, ROOMS).first[:key].include?('ROOM 2'), texts_on(doc, ROOMS).first[:key])

# Two dimensions that read the same are told apart by their order.
same = texts_on(doc, DIMS).select { |s| s[:text] == "12'-0\"" }.map { |s| s[:key] }
ok('two labels reading the same still get different names', same.uniq.length == 2, same)
ok('and they are numbered in the order they are drawn',
   same == [PC.text_key(DIMS, "12'-0\"", 1), PC.text_key(DIMS, "12'-0\"", 2)], same)

# THE POINT OF ALL OF IT: build the sheet again and the names are the same,
# so a choice made before the rebuild still finds its label.
again = basic_doc
PC.apply_text_scale!(again, {})
ok('REBUILDING THE SHEET GIVES THE SAME NAMES  <<< the whole point',
   (texts_on(again, ROOMS) + texts_on(again, DIMS)).map { |s| s[:key] } == keys)

# ---------------------------------------------------------------------------
# 2. one label, its own size
# ---------------------------------------------------------------------------
room_key = PC.text_key(ROOMS, 'ROOM 2', 1)

doc = basic_doc
PC.apply_text_scale!(doc, {})
PC.apply_text_overrides!(doc, 'text_marks' => { room_key => { 'pct' => 200 } })
ok('the chosen label changes', texts_on(doc, ROOMS)[0][:h] == 14.0,
   texts_on(doc, ROOMS)[0][:h])
ok('the one beside it does not', texts_on(doc, ROOMS)[1][:h] == 4.5,
   texts_on(doc, ROOMS)[1][:h])
ok('and neither does another layer', texts_on(doc, DIMS)[0][:h] == 5.0)

# ---------------------------------------------------------------------------
# 3. one label beats its group, and is measured from the ORIGINAL
# ---------------------------------------------------------------------------
# The user typed 150 on this label. He means 150 - not 150 of whatever the
# room group happened to be set to that morning.
doc = basic_doc
st  = { 'text_scale' => { 'rooms' => 50 },
        'text_marks' => { room_key => { 'pct' => 150 } } }
PC.apply_text_scale!(doc, st)
PC.apply_text_overrides!(doc, st)
ok('a label with its own size ignores its group', texts_on(doc, ROOMS)[0][:h] == 10.5,
   texts_on(doc, ROOMS)[0][:h])
ok('its neighbour still follows the group', texts_on(doc, ROOMS)[1][:h] == 2.25,
   texts_on(doc, ROOMS)[1][:h])

# ---------------------------------------------------------------------------
# 4. the compounding trap, again - this pass also runs on every click
# ---------------------------------------------------------------------------
doc = basic_doc
6.times do
  PC.apply_text_scale!(doc, st)
  PC.apply_text_overrides!(doc, st)
end
ok('six passes leave it exactly where one pass did',
   texts_on(doc, ROOMS)[0][:h] == 10.5, texts_on(doc, ROOMS)[0][:h])

# Clearing it puts the label back under its group, not back to 100.
st2 = { 'text_scale' => { 'rooms' => 50 }, 'text_marks' => {} }
PC.apply_text_scale!(doc, st2)
PC.apply_text_overrides!(doc, st2)
ok('taking the override away drops it back to its GROUP',
   texts_on(doc, ROOMS)[0][:h] == 3.5, texts_on(doc, ROOMS)[0][:h])

# ---------------------------------------------------------------------------
# 5. bold and italic
# ---------------------------------------------------------------------------
doc = basic_doc
PC.apply_text_scale!(doc, {})
PC.apply_text_overrides!(doc, 'text_marks' =>
  { room_key => { 'bold' => true, 'italic' => true } })
ok('a label can be made bold', texts_on(doc, ROOMS)[0][:bold] == true)
ok('and italic', texts_on(doc, ROOMS)[0][:italic] == true)
ok('weight alone does not change the size', texts_on(doc, ROOMS)[0][:h] == 7.0,
   texts_on(doc, ROOMS)[0][:h])
ok('and leaves its neighbour plain', !texts_on(doc, ROOMS)[1][:bold])

doc = basic_doc
PC.apply_text_scale!(doc, {})
PC.apply_text_overrides!(doc, 'text_marks' => { room_key => { 'bold' => false } })
ok('bold can be taken off again', texts_on(doc, ROOMS)[0][:bold] == false)

# Only what was said is changed. A hash with just a size must not quietly
# un-bold a label the PDF was already drawing bold.
doc = basic_doc
doc.canvas('MODEL').layers.find { |l| l.name == ROOMS }.shapes[0][:bold] = true
PC.apply_text_scale!(doc, {})
PC.apply_text_overrides!(doc, 'text_marks' => { room_key => { 'pct' => 120 } })
ok('setting only the size leaves the weight alone',
   texts_on(doc, ROOMS)[0][:bold] == true)

# ---------------------------------------------------------------------------
# 6. nonsense in, nothing broken
# ---------------------------------------------------------------------------
doc = basic_doc
PC.apply_text_scale!(doc, {})
before = texts_on(doc, ROOMS)[0][:h]

[nil, {}, 'not a hash', [], { 'no such label' => { 'pct' => 300 } }].each do |m|
  raised = begin
    PC.apply_text_overrides!(doc, 'text_marks' => m)
    nil
  rescue StandardError => e
    e
  end
  ok("text_marks = #{m.inspect} does not raise", raised.nil?, raised)
end
ok('and none of it moved anything', texts_on(doc, ROOMS)[0][:h] == before)

doc = basic_doc
PC.apply_text_scale!(doc, {})
PC.apply_text_overrides!(doc, 'text_marks' => { room_key => { 'pct' => 0 } })
ok('a zero cannot make a label vanish', texts_on(doc, ROOMS)[0][:h] == 7.0,
   texts_on(doc, ROOMS)[0][:h])

doc = basic_doc
PC.apply_text_scale!(doc, {})
PC.apply_text_overrides!(doc, 'text_marks' => { room_key => { 'pct' => 99_999 } })
ok('and a huge number is held to the same ceiling as the groups',
   texts_on(doc, ROOMS)[0][:h] == 7.0 * PC::TEXT_PCT_MAX / 100.0,
   texts_on(doc, ROOMS)[0][:h])

# ---------------------------------------------------------------------------
# 7. the weakness, pinned on purpose
# ---------------------------------------------------------------------------
# Rename the room and the formatting is orphaned. This is not a bug report -
# it is the known price of naming a label by what it says, and the day someone
# builds real ids this test says what should change.
renamed = doc_with([[ROOMS, 'KITCHEN', 7.0]])
PC.apply_text_scale!(renamed, {})
PC.apply_text_overrides!(renamed, 'text_marks' => { room_key => { 'pct' => 200 } })
ok('renaming the room leaves its formatting behind (known, accepted)',
   texts_on(renamed, ROOMS)[0][:h] == 7.0, texts_on(renamed, ROOMS)[0][:h])
ok('and nothing else is harmed by the orphan',
   texts_on(renamed, ROOMS)[0][:key] == PC.text_key(ROOMS, 'KITCHEN', 1))

# ---------------------------------------------------------------------------
# 8. the whole way through, and it is written down
# ---------------------------------------------------------------------------
doc = basic_doc
full = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
         'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN', 'hidden' => [],
         'tables_own_page' => true, 'marks' => [],
         'text_marks' => { room_key => { 'pct' => 180, 'bold' => true } } }
PC.layout_pages!(doc, full)
PC.layout_pages!(doc, full)
ok('the whole layout honours one label', texts_on(doc, ROOMS)[0][:h] == 12.6,
   texts_on(doc, ROOMS)[0][:h])
ok('twice through and it is still 180%', texts_on(doc, ROOMS)[0][:bold] == true)

# The title block is built AFTER pages are cleared. If the naming pass ran at
# the top of layout_pages! it would never see it.
tb = doc.pages.first.layers.flat_map { |l| l.shapes.select { |s| s[:type] == :text } }
ok('the writing on the page itself is named too, not just the plan',
   !tb.empty? && tb.all? { |s| s[:key] }, tb.map { |s| s[:key] }.first(3))

ok('the default state carries an empty list of labels',
   PSD.default_state['text_marks'] == {}, PSD.default_state['text_marks'])

stx = PSD.default_state.merge('text_marks' => { room_key => { 'pct' => 175 } })
PSD.save_state(stx)
ok('a label choice survives being written to the model',
   PSD.load_state['text_marks'][room_key]['pct'].to_f == 175.0,
   PSD.load_state['text_marks'])

# ---------------------------------------------------------------------------
# 9. the window
# ---------------------------------------------------------------------------
ok('there is a bar for one label', SRC.include?('id="textbar"'))
%w[txsize txbold txitalic txreset txdone].each do |id|
  ok("it has #{id}", SRC.include?("id=\"#{id}\""))
end
ok('two clicks on writing open it', SRC.include?('openTextBar(ht)'))
ok('the choice reaches Ruby', SRC.include?('sketchup.set_text_mark('))
ok('and Ruby is listening', SRC.include?("add_action_callback('set_text_mark')"))

cb = SRC[/add_action_callback\('set_text_mark'\).*?\n        end\n/m].to_s
ok('the callback is there', !cb.empty?)
ok('it answers with a full push, like set_text_scale',
   cb.include?('push_all(dlg)') && !cb.include?('push_pages'))
ok('a label with no name is refused rather than stored under ""',
   cb.include?('if key.empty?'))
ok('"reset" really removes it instead of writing 100',
   cb.include?("m.delete(key)"))
ok('and one field at a time can be sent',
   cb.include?("r.key?('bold')") && cb.include?("r.key?('pct')"))

# Two clicks on a note still edit its words - that behaviour is older and was
# not to be taken away.
dbl = SRC[/svg\.ondblclick=function\(e\)\{.*?\n            \};/m].to_s
ok('a note still opens its own words first',
   dbl.include?("marks()[h.i].t!=='note'") && dbl.include?("$('notetext').value"), dbl[0, 200])
ok('and anything else falls through to the writing under the mouse',
   dbl.include?('hitText(e)'))

# The panel points at a shape from the document. A new document arrives on
# every push, so it has to be re-found or the blue box lands on thin air.
ld = SRC[/function loadSheet\(p\)\{.*?\n          \}/m].to_s
ok('the open panel is re-pointed when a new sheet arrives',
   ld.include?('if(again) TSEL.shape=again; else closeTextBar();'), ld[-300..-1])

# ---- the space bar ----
key = SRC[/window\.addEventListener\('keydown'.*?\n            \}\);/m].to_s
ok('the space bar is listened for', key.include?("e.key===' '"), key[0, 200])
ok('it puts him back in select mode', key.include?("setMode('hand')"))
ok('and it does not type a space into the drawing', key.include?('e.preventDefault()'))
ok('typing in a box is still typing, not a tool change',
   key.include?("if(t==='INPUT'||t==='SELECT'||t==='TEXTAREA') return;"))
ok('Escape closes the label panel too', key.include?('closeTextBar()'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

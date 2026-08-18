# encoding: utf-8
# rt66 - choosing how big the writing is (2026-08-17).
#
# The user asked to pick the size of the text on the sheet, and picked four
# groups over one global number: dimensions, room names, door/window tags,
# schedules. From his own plan: the tags and the dimensions clearly want
# different sizes.
#
# WHY THIS COST ALMOST NOTHING, and why it must stay that way: every text on
# the sheet ALREADY carries its own height - PlanCanvas::Recorder takes it off
# add_3d_text - and ALREADY sits on a named layer, because build sets
# rec.layer_name before each group. So the sizes are changed in one pass over
# the finished document and plan_generator is never touched. If a later change
# starts writing text without a height, or onto the wrong layer, this suite is
# where it shows up.
#
# THE TRAP THIS SUITE EXISTS FOR: layout_pages! runs on EVERY click in the
# window. If the percentage were multiplied into :h each time it ran, the user
# would type 110 once and then watch the writing swell every time he touched
# any control, with no way back. That is why the original height is kept in
# :h0 and every size is derived from it. Running the pass twice must be the
# same as running it once.
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
PT  = InteriorPro::PlanTables
PSD = InteriorPro::PlanSheetDialog

SRC = File.read('./plan_sheet_dialog.rb', encoding: 'UTF-8')

# A document with one text on each of the layers that carry writing, plus a
# line, so "did anything else move" has something to answer with.
def fresh_doc
  doc = PD::Document.new('t')
  cv  = doc.canvas('MODEL')
  cv.layer(PC::LAYERS[:dimensions]).text("17'-4.4\"", 0, 0, h: 5.0)
  cv.layer(PC::LAYERS[:rooms]).text('ROOM 2', 0, 0, h: 7.0)
  cv.layer(PC::LAYERS[:rooms]).text('42 SF', 0, 0, h: 4.5)
  cv.layer(PC::LAYERS[:doors]).text('D103', 0, 0, h: 4.2)
  cv.layer(PC::LAYERS[:windows]).text('W101', 0, 0, h: 4.2)
  cv.layer(PC::MARK_LAYER).text("12'-0\"", 0, 0, h: 5.0)
  cv.layer(PC::LAYERS[:walls]).line(0, 0, 100, 0, weight: 0.02)
  cv.layer(PC::LAYERS[:dimensions]).line(0, 0, 100, 0, weight: 0.01)
  doc
end

def h_of(doc, layer, i = 0)
  lay = doc.canvas('MODEL').layers.find { |l| l.name == layer }
  return nil unless lay
  t = lay.shapes.select { |s| s[:type] == :text }[i]
  t && t[:h]
end

def pct(dims: 100, rooms: 100, tags: 100, tables: 100)
  { 'text_scale' => { 'dims' => dims, 'rooms' => rooms,
                      'tags' => tags, 'tables' => tables } }
end

# ---------------------------------------------------------------------------
# 1. an old model opens exactly as it always did
# ---------------------------------------------------------------------------
# Nothing in the wild has a text_scale. If the default did anything at all,
# every drawing the user has ever made would come back a different size.
doc = fresh_doc
before = doc.canvas('MODEL').layers.map { |l| l.shapes.map { |s| s[:h] } }
PC.apply_text_scale!(doc, {})
after = doc.canvas('MODEL').layers.map { |l| l.shapes.map { |s| s[:h] } }
ok('a state with no sizes in it changes nothing at all', before == after,
   [before, after])

PC.apply_text_scale!(doc, pct)
ok('and 100% is the same as nothing', before ==
   doc.canvas('MODEL').layers.map { |l| l.shapes.map { |s| s[:h] } })

ok('the default state ships all four at 100',
   PSD.default_state['text_scale'].values.uniq == [100],
   PSD.default_state['text_scale'])

# ---------------------------------------------------------------------------
# 2. each group moves on its own
# ---------------------------------------------------------------------------
doc = fresh_doc
PC.apply_text_scale!(doc, pct(dims: 200))
ok('dimensions follow their own number',
   h_of(doc, PC::LAYERS[:dimensions]) == 10.0, h_of(doc, PC::LAYERS[:dimensions]))
ok('the hand-drawn ones go with them, so the drawing stays one drawing',
   h_of(doc, PC::MARK_LAYER) == 10.0, h_of(doc, PC::MARK_LAYER))
ok('room names are left alone', h_of(doc, PC::LAYERS[:rooms]) == 7.0)
ok('and so are the tags', h_of(doc, PC::LAYERS[:doors]) == 4.2)

doc = fresh_doc
PC.apply_text_scale!(doc, pct(rooms: 50))
ok('the room name follows its own number',
   h_of(doc, PC::LAYERS[:rooms], 0) == 3.5, h_of(doc, PC::LAYERS[:rooms], 0))
ok('and the square footage under it goes with the name',
   h_of(doc, PC::LAYERS[:rooms], 1) == 2.25, h_of(doc, PC::LAYERS[:rooms], 1))
ok('dimensions untouched', h_of(doc, PC::LAYERS[:dimensions]) == 5.0)

doc = fresh_doc
PC.apply_text_scale!(doc, pct(tags: 150))
ok('door tags follow the tag number',
   (h_of(doc, PC::LAYERS[:doors]) - 6.3).abs < 1e-9, h_of(doc, PC::LAYERS[:doors]))
ok('window tags are the same group as door tags',
   (h_of(doc, PC::LAYERS[:windows]) - 6.3).abs < 1e-9, h_of(doc, PC::LAYERS[:windows]))

# ---------------------------------------------------------------------------
# 3. only the WRITING changes
# ---------------------------------------------------------------------------
doc = fresh_doc
PC.apply_text_scale!(doc, pct(dims: 300, rooms: 300, tags: 300))
lines = doc.canvas('MODEL').layers.flat_map { |l| l.shapes.select { |s| s[:type] == :line } }
ok('the lines are still there', lines.length == 2, lines.length)
ok('a line on a resized layer keeps its weight',
   lines.map { |s| s[:weight] }.sort == [0.01, 0.02], lines.map { |s| s[:weight] })
ok('and a wall is never a text, so the plan itself cannot be resized by this',
   h_of(doc, PC::LAYERS[:walls]).nil?)

# ---------------------------------------------------------------------------
# 4. THE TRAP - running it again must not compound
# ---------------------------------------------------------------------------
doc = fresh_doc
5.times { PC.apply_text_scale!(doc, pct(dims: 130)) }
ok('five passes at 130% are still 130%, not 130% five times over',
   (h_of(doc, PC::LAYERS[:dimensions]) - 6.5).abs < 1e-9,
   h_of(doc, PC::LAYERS[:dimensions]))

PC.apply_text_scale!(doc, pct(dims: 100))
ok('and going back to 100 lands exactly on the original height',
   h_of(doc, PC::LAYERS[:dimensions]) == 5.0, h_of(doc, PC::LAYERS[:dimensions]))

PC.apply_text_scale!(doc, pct(dims: 200))
PC.apply_text_scale!(doc, pct(dims: 50))
ok('changing your mind measures from the original, not from the last look',
   h_of(doc, PC::LAYERS[:dimensions]) == 2.5, h_of(doc, PC::LAYERS[:dimensions]))

ok('the original height is kept, which is how any of that is possible',
   doc.canvas('MODEL').layers.find { |l| l.name == PC::LAYERS[:dimensions] }
      .shapes.find { |s| s[:type] == :text }[:h0] == 5.0)

# ---------------------------------------------------------------------------
# 5. numbers that are not numbers
# ---------------------------------------------------------------------------
{ 0 => 100.0, -50 => 100.0, nil => 100.0, '' => 100.0, 'abc' => 100.0,
  1 => PC::TEXT_PCT_MIN, 99_999 => PC::TEXT_PCT_MAX,
  '130' => 130.0, 130.0 => 130.0 }.each do |given, want|
  got = PC.text_pct({ 'text_scale' => { 'dims' => given } }, 'dims')
  ok("#{given.inspect} is read as #{want}", got == want, got)
end
ok('a missing group is 100, not zero',
   PC.text_pct({ 'text_scale' => {} }, 'rooms') == 100.0)
ok('a missing text_scale altogether is 100', PC.text_pct({}, 'dims') == 100.0)

doc = fresh_doc
PC.apply_text_scale!(doc, 'text_scale' => { 'dims' => 0 })
ok('a zero cannot make the writing vanish',
   h_of(doc, PC::LAYERS[:dimensions]) == 5.0, h_of(doc, PC::LAYERS[:dimensions]))

# ---------------------------------------------------------------------------
# 6. the schedules - letters, rows and columns move together
# ---------------------------------------------------------------------------
# A table is not a paragraph. Bigger letters in rows that stayed the same
# height would be written straight over the gridlines.
def table_of(page)
  lay = page.layers.find { |l| l.name == PT::LAYER }
  lay && lay.shapes.find { |s| s[:type] == :table }
end

rows = { 'windows' => [%w[W101 3-0 5-0 CASEMENT VINYL]], 'doors' => [] }

d1 = PD::Document.new('t'); d1.schedules = rows
p1 = PD.new_sheet(d1, 'PLAN', size: 'ARCH D', orientation: :landscape,
                  scale: '1/4"', canvas: 'MODEL')
PT.place!(p1, d1)
base = table_of(p1)

d2 = PD::Document.new('t'); d2.schedules = rows
p2 = PD.new_sheet(d2, 'PLAN', size: 'ARCH D', orientation: :landscape,
                  scale: '1/4"', canvas: 'MODEL')
PT.place!(p2, d2, zoom: 2.0)
big = table_of(p2)

ok('a table is drawn at all', !base.nil? && !big.nil?)
ok('the letters get bigger', (big[:h] - base[:h] * 2.0).abs < 1e-9, [base[:h], big[:h]])
ok('THE ROWS GET TALLER WITH THEM, or the text sits on the gridlines',
   (big[:row_h] - base[:row_h] * 2.0).abs < 1e-9, [base[:row_h], big[:row_h]])
ok('and the columns get wider too',
   big[:col_widths].first > base[:col_widths].first,
   [base[:col_widths].first, big[:col_widths].first])
ok('the same number of rows, just bigger', big[:rows].length == base[:rows].length)
ok('a zoom of 1 is exactly what it always was',
   begin
     d3 = PD::Document.new('t'); d3.schedules = rows
     p3 = PD.new_sheet(d3, 'PLAN', size: 'ARCH D', orientation: :landscape,
                       scale: '1/4"', canvas: 'MODEL')
     PT.place!(p3, d3, zoom: 1.0)
     t3 = table_of(p3)
     t3[:h] == base[:h] && t3[:row_h] == base[:row_h] &&
       t3[:col_widths] == base[:col_widths]
   end)

# The plan has to give the wider table its room, or they overlap.
wide = PT.reserved_width(d1, [], 2.0)
norm = PT.reserved_width(d1, [], 1.0)
ok('a bigger table reserves more of the sheet', wide > norm, [norm, wide])
ok('and the old two-argument call still answers the same',
   PT.reserved_width(d1, []) == norm, [PT.reserved_width(d1, []), norm])
ok('a hidden schedule layer still reserves nothing, whatever the size',
   PT.reserved_width(d1, [PT::LAYER], 2.0) == 0.0)

# ---------------------------------------------------------------------------
# 7. the whole way through, twice - the real path the window takes
# ---------------------------------------------------------------------------
doc = fresh_doc
doc.schedules = rows
st = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
       'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN', 'hidden' => [],
       'tables_own_page' => true, 'marks' => [] }.merge(pct(dims: 150, tables: 150))

PC.layout_pages!(doc, st)
once = h_of(doc, PC::LAYERS[:dimensions])
PC.layout_pages!(doc, st)
PC.layout_pages!(doc, st)
ok('three trips through the window leave the dimensions where they were',
   h_of(doc, PC::LAYERS[:dimensions]) == once, [once, h_of(doc, PC::LAYERS[:dimensions])])
ok('and that is 150% of the original', (once - 7.5).abs < 1e-9, once)

sched = doc.pages.find { |p| p.kind == 'schedules' }
ok('the schedules sheet is still built', !sched.nil?, doc.pages.map(&:kind))

# ---------------------------------------------------------------------------
# 8. the window
# ---------------------------------------------------------------------------
%w[tsDims tsRooms tsTags tsTables].each do |id|
  ok("there is a box for #{id}", SRC.include?("id=\"#{id}\""))
end
ok('they are per-cent boxes, bounded', SRC.include?('min="25" max="400"'))
ok('there is a way back to normal', SRC.include?('id="tsReset"'))
ok('the sizes reach Ruby', SRC.include?('sketchup.set_text_scale('))
ok('and Ruby is listening', SRC.include?("add_action_callback('set_text_scale')"))
ok('the boxes are filled in when the window opens', SRC.include?('showTextScale()'))

# Typing "1" on the way to "130" must not send a sheet at 25% and redraw it.
wiring = SRC[/for\(var tk in TS_FIELDS\).*?\n            \}/m].to_s
ok('the boxes answer on change, not on every keystroke',
   wiring.include?('.onchange=') && !wiring.include?('.oninput='), wiring)

# The dimension numbers, the room names and the tags live on the MODEL canvas.
# push_pages ships the PAGES and the hand-drawn marks and nothing else, so
# answering with it would change the PDF and leave the window looking the same.
cb = SRC[/add_action_callback\('set_text_scale'\).*?\n        end\n/m].to_s
ok('the callback exists in the source', !cb.empty?)
ok('IT ANSWERS WITH A FULL PUSH, or the window would not change',
   cb.include?('push_all(dlg)') && !cb.include?('push_pages'), cb[-200..-1])
ok('and it saves the choice onto the model', cb.include?('save_state(st)'))
ok('one group at a time can be sent without wiping the others',
   cb.include?("(st['text_scale'] || {}).merge("))

# The sizes have to survive being written down.
st2 = PSD.default_state.merge('text_scale' => { 'dims' => 140, 'rooms' => 100,
                                                'tags' => 100, 'tables' => 100 })
PSD.save_state(st2)
ok('the chosen sizes are kept on the model',
   PSD.load_state['text_scale']['dims'].to_f == 140.0,
   PSD.load_state['text_scale'])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt281 - the editor's drawings on sheets of their own (2026-10-07), the Ruby side.
#
# The user: "לבחור איזה שרטוט נכנס לאיזה דף". The 2D editor has pages beside
# the house ("שרטוט 1", "שרטוט 2" - blue walls that never go to 3D, lines,
# dimension tags), saved on the model in plan_draft. So:
#   - PlanCanvas.draft_pages reads them; a page with no name is "שרטוט N";
#   - st['drawn'] = [{'src' => 'draft:0'}] puts one on a sheet of kind
#     'drawing' (page key 'drawing:j'), after the schedules and before the
#     pictures, named after the drawing, numbered on from the plan, seen whole
#     at the biggest scale from the list that holds it;
#   - its canvas DRAWN:i has the walls as bands (bandQuad's sums), the lines,
#     and the dimensions drawn by the plan's own routine;
#   - add_drawing / delete_page (kind 'drawing') keep the list, the ticks, the
#     order and the pictures on those sheets in step; the window is told the
#     editor's pages (drafts);
#   - nothing asked for = not one page more than before; the switch off = the same.
# t81 pins the window's side.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
require 'zlib'
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
def near(a, b, tol = 1.0e-9); (a.to_f - b.to_f).abs < tol; end
def near4(p, q, tol = 1.0e-9); p.each_with_index.all? { |v, i| near(v, q[i], tol) }; end

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt281_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

ok('there is a switch for it, and it is on', PC.const_defined?(:USE_DRAWN_SHEETS, false) && PC::USE_DRAWN_SHEETS == true)
ok('a new model starts with no drawing sheets', PSD.default_state['drawn'] == [])

DRAFT = { 'pending' => [], 'sketches' => [], 'pages' => [
  { 'name' => 'שרטוט 1',
    'pending' => [{ 'sx' => 0, 'sy' => 0, 'ex' => 240, 'ey' => 0, 'th' => 6, 'ha' => 'left', 'cat' => 'exterior' },
                  { 'sx' => 240, 'sy' => 0, 'ex' => 240, 'ey' => 120, 'th' => 4, 'ha' => 'center', 'cat' => 'interior' },
                  { 'sx' => 0, 'sy' => 0, 'ex' => 0, 'ey' => 0, 'th' => 6 }],
    'sketches' => [{ 'pts' => [0, 0, 100, 50, 200, 0], 'closed' => true, 'weight' => 2 }, { 'pts' => [1, 2] }],
    'dims' => [{ 'x1' => 0, 'y1' => -20, 'x2' => 240, 'y2' => -20, 'off' => 10 }] },
  { 'name' => '  ', 'pending' => [], 'sketches' => [{ 'pts' => [0, 0, 50, 50] }], 'dims' => [] },
  'junk' ] }.freeze

def model_with(draft)
  Sketchup.reset_model!
  Sketchup.active_model.set_attribute('InteriorPro', 'plan_draft', draft.nil? ? nil : JSON.generate(draft))
  Sketchup.active_model
end

# ---------------------------------------------------------------------------
# 1. the editor's pages, read
# ---------------------------------------------------------------------------
pages = PC.draft_pages(model_with(DRAFT))
ok('THE EDITOR\'S PAGES ARE READ: two of them, the nameless one named by its place, the junk one skipped',
   pages.length == 2 && pages[0][:name] == 'שרטוט 1' && pages[0][:i] == 0 && pages[1][:name] == 'שרטוט 2' && pages[1][:i] == 1, pages.map { |p| [p[:i], p[:name]] })
ok('what the window is told', PC.draft_names(Sketchup.active_model) == [{ 'i' => 0, 'name' => 'שרטוט 1' }, { 'i' => 1, 'name' => 'שרטוט 2' }])
ok('no draft, an empty draft, a broken draft: no pages, nothing blows up',
   PC.draft_pages(model_with(nil)) == [] && PC.draft_pages(model_with('pending' => [])) == [] &&
   (Sketchup.active_model.set_attribute('InteriorPro', 'plan_draft', '{not json'); PC.draft_pages(Sketchup.active_model) == []))

# ---------------------------------------------------------------------------
# 2. the canvas of a drawing
# ---------------------------------------------------------------------------
model_with(DRAFT)
doc = PD::Document.new('t')
PC.build_drawn!(doc, PC.draft_pages(Sketchup.active_model))
ok('a canvas for each page, named after it', doc.canvas?('DRAWN:0') && doc.canvas?('DRAWN:1') && doc.canvas('DRAWN:0').drawn_name == 'שרטוט 1')
cv = doc.canvas('DRAWN:0')
walls = cv.layer(PC::LAYERS[:walls]).shapes
ok('THE BLUE WALLS ARE BANDS: two of them (the one with no length is skipped), filled like the plan\'s',
   walls.length == 2 && walls.all? { |w| w[:type] == :polygon && w[:points].length == 4 } && walls[0][:fill] == [64, 64, 64] && walls[1][:fill] == [205, 205, 205], walls.map { |w| w[:fill] })
ok('a wall anchored LEFT: the band lies to the left of start -> end, as bandQuad lays it (y 0..6 for a wall along x)',
   walls[0][:points].map { |p| p[1] }.minmax == [0.0, 6.0] && walls[0][:points].map { |p| p[0] }.minmax == [0.0, 240.0], walls[0][:points])
ok('a wall anchored CENTER: half each side', walls[1][:points].map { |p| p[0] }.minmax == [238.0, 242.0], walls[1][:points])
lines = cv.layer(PC::LAYERS[:sketch]).shapes
ok('the lines: one closed polyline of three points (the one-point one skipped), its weight from the editor\'s',
   lines.length == 1 && lines[0][:type] == :polyline && lines[0][:points].length == 3 && lines[0][:closed] == true && near(lines[0][:weight], 0.012), lines)
dims = cv.layer(PC::LAYERS[:dimensions]).shapes
ok('the dimension tag is drawn by the plan\'s own routine: a line, witnesses and the number 20\'-0"',
   dims.any? { |s| s[:type] == :text && s[:text] == %q(20'-0") } && dims.count { |s| s[:type] == :line } >= 3, dims.map { |s| [s[:type], s[:text]] })
doc2 = PD::Document.new('t')
PC.build_drawn!(doc2, PC.draft_pages(Sketchup.active_model), [{ 'src' => 'draft:1' }])
ok('asked for one page only: only its canvas is built', !doc2.canvas?('DRAWN:0') && doc2.canvas?('DRAWN:1'))

# ---------------------------------------------------------------------------
# 3. laid out on sheets
# ---------------------------------------------------------------------------
def build_doc(drawn = nil)
  d = PD::Document.new('t')
  d.canvas('MODEL').layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  PC.build_drawn!(d, PC.draft_pages(Sketchup.active_model), drawn)
  d
end
def state(extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
    'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => [], 'images' => [] }.merge(extra)
end
def laid(st); d = build_doc(st['drawn']); PC.layout_pages!(d, st); d; end
def keys(d); d.pages.map { |pg| PSD.page_key(pg) }; end
def nums(d); d.pages.map(&:sheet_number); end
def words(pg); pg.layers.flat_map(&:shapes).select { |s| s[:type] == :text }.map { |s| s[:text].to_s }; end

d0 = laid(state)
ok('NOTHING ASKED FOR: the plan sheet alone, as before', keys(d0) == ['plan'] && nums(d0) == ['A-101'])
d1 = laid(state('drawn' => [{ 'src' => 'draft:0' }, { 'src' => 'draft:1' }], 'images' => ['x.jpg']))
ok('TWO DRAWINGS ASKED FOR: after the plan, before the picture, numbered on', keys(d1) == %w[plan drawing:0 drawing:1 image:0] && nums(d1) == %w[A-101 A-102 A-103 A-104], [keys(d1), nums(d1)])
pg = d1.pages[1]
ok('the sheet is named after the drawing, kind drawing, ref its place in the list', pg.name == 'שרטוט 1' && pg.kind == 'drawing' && pg.ref == 0 && d1.pages[2].name == 'שרטוט 2' && d1.pages[2].ref == 1)
ok('its title block says so', words(pg).include?('A-102  שרטוט 1'), words(pg).grep(/A-10/))
v = pg.views.first
b = d1.canvas('DRAWN:0').bounds
ok('ITS VIEW SHOWS ITS OWN CANVAS, WHOLE: the biggest scale from the list that holds it, the drawing in the middle',
   v.canvas == 'DRAWN:0' && v.scale == v.fit_scale(b) && v.fits?(b) && near(v.origin_x, (b[0] + b[2]) / 2) && near(v.origin_y, (b[1] + b[3]) / 2) && v.scale != '1/4"', [v.canvas, v.scale, v.fit_scale(b)])
ok('the plan sheet is untouched by it', d1.pages[0].views.first.canvas == 'MODEL' && d1.pages[0].views.first.scale == '1/4"' && near(d1.pages[0].views.first.origin_x, 120.0))
ok('the frame of a drawing sheet does not turn, and there is no box of his on it', !v.box_turn && v.rotation == 0.0)
d2 = laid(state('drawn' => [{ 'src' => 'draft:7' }, { 'src' => 'nonsense' }, 'junk', { 'src' => 'draft:1' }]))
ok('a drawing that is not there (deleted in the editor), and junk: no sheet; the one that is there keeps its place in the list as its ref',
   keys(d2) == %w[plan drawing:3], keys(d2))
d3 = laid(state('drawn' => [{ 'src' => 'draft:0' }], 'page_order' => %w[drawing:0 plan]))
ok('the order he dragged holds for it, and so does the numbering', keys(d3) == %w[drawing:0 plan] && nums(d3) == %w[A-101 A-102] && words(d3.pages[0]).include?('A-101  שרטוט 1'), [keys(d3), nums(d3)])
d4 = laid(state('drawn' => [{ 'src' => 'draft:0' }], 'pdf_skip' => ['drawing:0'], 'pics' => [{ 'path' => 'p.jpg', 'on' => 'drawing:0', 'box' => [3.0, 3.0, 4.0, 2.0] }],
                'texts' => [{ 'text' => 'Hi', 'on' => 'drawing:0', 'box' => [5.0, 5.0, 3.0, 1.0], 'pt' => 24 }]))
ok('a picture and a box of writing put ON a drawing sheet land on it', d4.pages[1].layers.flat_map(&:shapes).any? { |s| s[:type] == :image && s[:placed] } && d4.pages[1].text_boxes.length == 1)
ok('and the tick keeps it out of the print', PSD.pages_for_pdf(d4, 'pdf_skip' => ['drawing:0']).map { |p| PSD.page_key(p) } == ['plan'])
snap = ->(d) { JSON.generate(d.pages.map(&:to_h)) }
one = snap.call(d1)
3.times { PC.layout_pages!(d1, state('drawn' => [{ 'src' => 'draft:0' }, { 'src' => 'draft:1' }], 'images' => ['x.jpg'])) }
ok('laid out again and again, nothing creeps', snap.call(d1) == one)

# ---------------------------------------------------------------------------
# 4. the sheet window
# ---------------------------------------------------------------------------
def open!
  %i[@site_lines @site_owner @site_owner_path @doc].each { |iv| PSD.instance_variable_set(iv, nil) }
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end
def sheet(dlg); JSON.parse(dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1]); end
model_with(DRAFT)
dlg = open!
first = sheet(dlg)
ok('THE WINDOW IS TOLD THE EDITOR\'S PAGES, and the switch', first['drafts'] == [{ 'i' => 0, 'name' => 'שרטוט 1' }, { 'i' => 1, 'name' => 'שרטוט 2' }] && first['drawn'] == true)
ok('and opens with the plan alone', first['doc']['pages'].length == 1 && first['doc']['canvases'].map { |c| c['name'] } == ['MODEL'])
trace = File.join(PSD.plugin_dir, 'sheet_erase_trace.txt')
tsize = File.exist?(trace) ? File.size(trace) : 0
dlg.callbacks['add_drawing'].call(nil, JSON.generate('src' => 'draft:1'))
st = PSD.load_state
ok('ADD A DRAWING: saved on the model, and the new sheet is the open one', st['drawn'] == [{ 'src' => 'draft:1' }] && st['active'] == 1, st.values_at('drawn', 'active'))
pay = sheet(dlg)
ok('the window gets the sheet, with the drawing\'s canvas', pay['doc']['pages'].map { |p| p['kind'] } == %w[plan drawing] && pay['doc']['canvases'].map { |c| c['name'] } == %w[MODEL DRAWN:1] && pay['doc']['pages'][1]['views'][0]['canvas'] == 'DRAWN:1')
ok('a trace line', File.read(trace, encoding: 'UTF-8')[tsize..-1].to_s.include?('drawing sheet: draft:1 added, 2 pages'))
dlg.callbacks['add_drawing'].call(nil, JSON.generate('src' => 'draft:0'))
ok('a second one: after the first', PSD.document.pages.map { |p| PSD.page_key(p) } == %w[plan drawing:0 drawing:1] && PSD.document.pages[2].name == 'שרטוט 1')
n0 = PSD.load_state['drawn'].length
dlg.callbacks['add_drawing'].call(nil, JSON.generate('src' => 'draft:9'))
ok('a drawing the editor has not got: refused', PSD.load_state['drawn'].length == n0 && dlg.scripts.last.start_with?('imageReport('))
# the ticks, the order and the pictures on a drawing sheet that is thrown away
st = PSD.load_state
st['pdf_skip'] = ['drawing:1']
st['page_order'] = %w[drawing:1 drawing:0 plan]
st['pics'] = [{ 'path' => 'p.jpg', 'on' => 'drawing:1', 'box' => [3.0, 3.0, 4.0, 2.0] }, { 'path' => 'q.jpg', 'on' => 'drawing:0', 'box' => [3.0, 3.0, 4.0, 2.0] }]
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
dlg.callbacks['delete_page'].call(nil, JSON.generate('kind' => 'drawing', 'ref' => 0))
st = PSD.load_state
ok('A DRAWING SHEET THROWN AWAY: off the list, and the one after it moves down - with its tick, its place in the order and its picture',
   st['drawn'] == [{ 'src' => 'draft:0' }] && st['pdf_skip'] == ['drawing:0'] && st['page_order'] == %w[drawing:0 plan] && st['pics'].map { |q| q['on'] } == ['drawing:0'],
   st.values_at('drawn', 'pdf_skip', 'page_order', 'pics'))
ok('the sheet it leaves', PSD.document.pages.map { |p| PSD.page_key(p) } == %w[drawing:0 plan] && PSD.document.pages[0].name == 'שרטוט 1')

# ---------------------------------------------------------------------------
# 5. the switch
# ---------------------------------------------------------------------------
PC.send(:remove_const, :USE_DRAWN_SHEETS)
PC.const_set(:USE_DRAWN_SHEETS, false)
off = laid(state('drawn' => [{ 'src' => 'draft:0' }]))
ok('SWITCHED OFF: no drawing sheets, whatever was saved', keys(off) == ['plan'])
dlg = open!
ok('switched off: the window is told, and offered no drawings', sheet(dlg)['drawn'] == false && sheet(dlg)['drafts'] == [] && sheet(dlg)['doc']['canvases'].length == 1)
PC.send(:remove_const, :USE_DRAWN_SHEETS)
PC.const_set(:USE_DRAWN_SHEETS, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

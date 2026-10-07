# encoding: utf-8
# rt271 - the drawing can be turned on its sheet (2026-10-07), the Ruby side.
#
# The user: "אני רוצה שתהיה אפשרות לסובב את השרטוט... כמו בתמונה שיש סימון על
# הפינה למטה של סיבוב." Shown his own house turned 35 degrees two ways, he said:
# "הכל צריך להסתובב" and then "רגע, הכל מסתובב התכוונתי למידות, אבל הכל חייב
# להישאר קריא."
#
# THE RULE THIS SUITE PINS, for a drawing turned by R degrees:
#   - every line turns about the middle of the frame;
#   - a dimension's number turns with its line - and so does writing laid
#     along something, and a hand-written note with its box - and none of it
#     is ever upside down;
#   - a room name, the area under it and a door/window tag stay LEVEL on the
#     page, and a name and its area stay one above the other;
#   - the PDF follows one simple rule (each piece of writing: its own angle
#     plus the sheet's), so it prints what the window shows;
#   - 0 degrees is every drawing as it always was, to the last digit, and
#     turning back to 0 leaves no trace.
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
def near(a, b, tol = 1.0e-6); (a.to_f - b.to_f).abs < tol; end
def near2(p, q, tol = 1.0e-6); near(p[0], q[0], tol) && near(p[1], q[1], tol); end

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog
PG  = InteriorPro::PlanGeometry

ok('there is a switch, and it is on', PC.const_defined?(:USE_VIEW_ROTATION, false) && PC::USE_VIEW_ROTATION == true)

# ---------------------------------------------------------------------------
# 1. the window on the sheet
# ---------------------------------------------------------------------------
v = PD::View.new('PLAN', 2.0, 3.0, 30.0, 20.0, 'MODEL', '1/4"')
v.origin_x = 100.0
v.origin_y = 50.0
s = v.scale_factor
ok('a new window is not turned', v.rotation == 0.0)
old = ->(mx, my) { [17.0 + (mx - 100.0) * s, 13.0 + (my - 50.0) * s] }
ok('NOT TURNED: every point lands exactly where it always did - not nearly, exactly',
   [[100.0, 50.0], [137.25, -12.5], [-400.0, 921.0]].all? { |x, y| v.model_to_paper(x, y) == old.call(x, y) })
ok('...and comes back exactly', v.paper_to_model(17.0 + 48.0 * s, 13.0) == [100.0 + 48.0, 50.0])

v.rotation = 90
ok('A QUARTER TURN: what was to the right of the middle is now above it',
   near2(v.model_to_paper(148.0, 50.0), [17.0, 13.0 + 48.0 * s]), v.model_to_paper(148.0, 50.0))
ok('the middle of the frame does not move - the drawing turns about it', near2(v.model_to_paper(100.0, 50.0), [17.0, 13.0]))
v.rotation = 35
ok('at any angle, paper -> model undoes model -> paper',
   [[100.0, 50.0], [137.25, -12.5], [-400.0, 921.0]].all? { |x, y| near2(v.paper_to_model(*v.model_to_paper(x, y)), [x, y], 1.0e-7) })
w = v.model_window
ok('the slice of the model it can show covers all four corners of the turned frame',
   [[2.0, 3.0], [32.0, 3.0], [32.0, 23.0], [2.0, 23.0]].all? { |px, py| m = v.paper_to_model(px, py); m[0] >= w[0] - 1e-6 && m[0] <= w[2] + 1e-6 && m[1] >= w[1] - 1e-6 && m[1] <= w[3] + 1e-6 })
v.rotation = 370
ok('370 degrees is 10', near(v.rotation, 10.0), v.rotation)
v.rotation = -180
ok('-180 is 180', near(v.rotation, 180.0), v.rotation)
ok('the angle travels with the window to whoever draws it', (v.rotation = 35; v.to_h[:rotation] == 35.0))

# a long thin drawing in a tall thin frame: does not fit lying down, fits stood up
tall = PD::View.new('T', 0, 0, 5.0, 30.0, 'MODEL', '1/4"')
long = [0.0, 0.0, 1200.0, 100.0]                    # 100 ft by 8 ft: 25" by 2" on paper
ok('a long drawing does not fit a tall frame lying down', !tall.fits?(long))
tall.rotation = 90
ok('...and does once it is turned a quarter turn', tall.fits?(long))
ok('the scale that would fit is worked out for the drawing AS TURNED', tall.fit_scale(long) == '1/4"', tall.fit_scale(long))

# ---------------------------------------------------------------------------
# 2. a sheet with every kind of writing on it
# ---------------------------------------------------------------------------
def build_doc
  doc = PD::Document.new('t')
  cv  = doc.canvas('MODEL')
  cv.layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  d = cv.layer('DIMENSIONS')
  d.text("20'-0\"", 120.0, -10.0, h: 5.0, align: :center, rotation: 0.0)      # along a level wall
  d.text("10'-0\"", 250.0, 60.0, h: 5.0, align: :center, rotation: 90.0)      # along an upright wall
  r = cv.layer('ROOMS')
  r.text('ROOM 1', 100.0, 65.0, h: 7.0, align: :center, rotation: 0.0)
  r.text('2372 SF', 100.0, 53.0, h: 4.5, align: :center, rotation: 0.0)
  r.text('ROOM 2', 200.0, 35.0, h: 7.0, align: :center, rotation: 0.0)
  r.text('42 SF', 200.0, 23.0, h: 4.5, align: :center, rotation: 0.0)
  t = cv.layer('DOORS')
  t.text('D101', 60.0, 4.0, h: 4.2, align: :center, rotation: 0.0)            # a tag in its badge
  t.text('3068', 80.0, 6.0, h: 3.0, align: :center, rotation: 40.0)           # writing laid along something
  doc
end
MARKS = [{ 't' => 'dim', 'x1' => 0.0, 'y1' => 150.0, 'x2' => 100.0, 'y2' => 150.0, 'off' => 20.0 },
         { 't' => 'note', 'x' => 180.0, 'y' => 90.0, 'kx' => 150.0, 'ky' => 90.0, 'lx' => 130.0, 'ly' => 70.0, 'text' => 'TILE' }].freeze
def state(rot, extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
    'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => JSON.parse(JSON.generate(MARKS)), 'rotation' => rot }.merge(extra)
end
def texts(doc)
  out = {}
  doc.canvas('MODEL').layers.each { |l| l.shapes.each { |sh| out[sh[:text]] = sh if sh[:type] == :text } }
  out
end
def view(doc); doc.pages.find { |pg| pg.kind == 'plan' }.views.first; end
# where a piece of writing ends up on the paper, and at what angle - by the ONE
# rule the window and the PDF both follow
def on_paper(doc, name)
  sh = texts(doc)[name]
  vw = view(doc)
  [vw.model_to_paper(sh[:x], sh[:y]), sh[:rotation].to_f + vw.rotation]
end

flat = build_doc
PC.layout_pages!(flat, state(0))
ok('NOT TURNED: nothing about the writing is changed, and nothing is left on it',
   texts(flat).values.none? { |sh| sh.key?(:rk) } && texts(flat)['ROOM 1'][:x] == 100.0 && texts(flat)["10'-0\""][:rotation] == 90.0)
ok('the hand-drawn dimension and the note are on the sheet', texts(flat).key?("8'-4\"") && texts(flat).key?('TILE'), texts(flat).keys)
SF0 = view(flat).scale_factor

doc = build_doc
PC.layout_pages!(doc, state(35))
ok('the window on the plan sheet is turned by the angle he chose', view(doc).rotation == 35.0, view(doc).rotation)

ok("A DIMENSION'S NUMBER TURNS WITH ITS LINE  <<< THE RULE", near(on_paper(doc, "20'-0\"")[1], 35.0), on_paper(doc, "20'-0\"")[1])
ok('...and stays ON its line: it goes where the drawing took its point',
   near2(on_paper(doc, "20'-0\"")[0], view(doc).model_to_paper(120.0, -10.0)))
ok('a number that would end up past vertical is read from the other side - never upside down',
   near(on_paper(doc, "10'-0\"")[1], -55.0), on_paper(doc, "10'-0\"")[1])        # 90 + 35 = 125 -> -55
ok('writing that was laid along something turns with it', near(on_paper(doc, '3068')[1], 75.0), on_paper(doc, '3068')[1])
ok('the hand-drawn dimension turns with its line', near(on_paper(doc, "8'-4\"")[1], 35.0), on_paper(doc, "8'-4\"")[1])
ok('a hand-written note turns with its box', near(on_paper(doc, 'TILE')[1], 35.0), on_paper(doc, 'TILE')[1])

ok('A ROOM NAME STAYS LEVEL ON THE PAGE  <<< THE RULE', near(on_paper(doc, 'ROOM 1')[1], 0.0), on_paper(doc, 'ROOM 1')[1])
ok('so does the area under it', near(on_paper(doc, '2372 SF')[1], 0.0))
ok('and a door tag', near(on_paper(doc, 'D101')[1], 0.0) && near2(on_paper(doc, 'D101')[0], view(doc).model_to_paper(60.0, 4.0)))
name_p = on_paper(doc, 'ROOM 1')[0]
area_p = on_paper(doc, '2372 SF')[0]
ok('THE AREA IS STILL STRAIGHT UNDER THE NAME - not beside it',
   near(name_p[0], area_p[0]) && near(name_p[1] - area_p[1], 12.0 * SF0), [name_p, area_p])
mid = view(doc).model_to_paper(100.0, 59.0)
ok('and the pair sits where the room went', near2([(name_p[0] + area_p[0]) / 2.0, (name_p[1] + area_p[1]) / 2.0], mid), [name_p, area_p, mid])
n2 = on_paper(doc, 'ROOM 2')[0]
a2 = on_paper(doc, '42 SF')[0]
ok('every room, not only the first', near(n2[0], a2[0]) && near(n2[1] - a2[1], 12.0 * SF0))

# upside down is the real test of "readable"
half = build_doc
PC.layout_pages!(half, state(180))
ok('TURNED HALF WAY ROUND, NOTHING IS UPSIDE DOWN: numbers, names, tags, notes',
   ["20'-0\"", "10'-0\"", '3068', "8'-4\"", 'TILE', 'ROOM 1', '2372 SF', 'D101'].all? { |k| a = on_paper(half, k)[1]; a >= -90.0001 && a <= 90.0001 },
   ["20'-0\"", "10'-0\"", '3068', "8'-4\"", 'TILE', 'ROOM 1'].map { |k| on_paper(half, k)[1].round(1) })
hn = on_paper(half, 'ROOM 1')[0]
ha = on_paper(half, '2372 SF')[0]
ok('and the area is still UNDER the name', near(hn[0], ha[0]) && hn[1] > ha[1], [hn, ha])

# ---------------------------------------------------------------------------
# 3. layout runs on every click, on the same shapes
# ---------------------------------------------------------------------------
snap = ->(d) { JSON.generate(d.canvas('MODEL').to_h) }
one = snap.call(doc)
PC.layout_pages!(doc, state(35))
PC.layout_pages!(doc, state(35))
ok('LAID OUT AGAIN AND AGAIN AT THE SAME ANGLE, NOTHING CREEPS', snap.call(doc) == one)
PC.layout_pages!(doc, state(-70))
ok('a new angle is worked out from the writing as BUILT, not from the last angle',
   near(on_paper(doc, "20'-0\"")[1], -70.0) && near(on_paper(doc, 'ROOM 1')[1], 0.0) &&
   near2(on_paper(doc, "20'-0\"")[0], view(doc).model_to_paper(120.0, -10.0)))
PC.layout_pages!(doc, state(0))
ok('TURNED BACK TO ZERO, THE DRAWING IS EXACTLY THE ONE THAT WAS NEVER TURNED', snap.call(doc) == snap.call(flat))

# a label he shoved, on a turned sheet
shove = { 'text_marks' => { 'ROOMS|2372 SF|1' => { 'dx' => 10.0, 'dy' => 0.0 } } }
d0 = build_doc
PC.layout_pages!(d0, state(35))
d1 = build_doc
PC.layout_pages!(d1, state(35, shove))
p0 = on_paper(d0, '2372 SF')[0]
p1 = on_paper(d1, '2372 SF')[0]
c35 = Math.cos(35 * Math::PI / 180.0)
s35 = Math.sin(35 * Math::PI / 180.0)
ok('a label he shoved goes the way the turned drawing takes that shove, and stays level',
   near2([p1[0] - p0[0], p1[1] - p0[1]], [10.0 * SF0 * c35, 10.0 * SF0 * s35]) && near(on_paper(d1, '2372 SF')[1], 0.0),
   [p1[0] - p0[0], p1[1] - p0[1]])
PC.layout_pages!(d1, state(35, shove))
ok('and laying it out again does not shove it twice', near2(on_paper(d1, '2372 SF')[0], p1))

# ---------------------------------------------------------------------------
# 4. the PDF prints what the window shows
# ---------------------------------------------------------------------------
q = build_doc
PC.layout_pages!(q, state(90))
pg = q.pages.find { |x| x.kind == 'plan' }
stream = PP.page_stream(pg, q)
vq = view(q)
num = ->(x) { format('%.3f', x.to_f) }
a  = vq.model_to_paper(0.0, 0.0)
b  = vq.model_to_paper(240.0, 0.0)
ok('IN THE PDF THE WALL IS TURNED: its first stroke runs straight up the sheet',
   stream.include?("#{num.call(a[0] * 72)} #{num.call(a[1] * 72)} m") && stream.include?("#{num.call(b[0] * 72)} #{num.call(b[1] * 72)} l") &&
   near(a[0], b[0]) && b[1] > a[1], [a, b])
ok('the frame it is clipped to is NOT turned',
   stream.include?("#{num.call(vq.x * 72)} #{num.call(vq.y * 72)} #{num.call(vq.w * 72)} #{num.call(vq.h * 72)} re W n"))
tm = ->(word) { stream[/BT(?:(?!ET).)*?\(#{Regexp.escape(word)}\) Tj/m].to_s[/^.* Tm$/] }
ok('in the PDF the room name is level', tm.call('ROOM 1').to_s.start_with?('1 0 0 1 '), tm.call('ROOM 1'))
ok('in the PDF the number along the level wall now runs up the sheet with it',
   tm.call("20'-0\"").to_s.start_with?('0.000 1.000 -1.000 0.000 '), tm.call("20'-0\""))
ok('in the PDF the number that was upright now reads level - turned 180 it would be upside down',
   tm.call("10'-0\"").to_s.start_with?('1 0 0 1 '), tm.call("10'-0\""))
# writing put straight on the paper (the title block) has nothing to do with the turn
ok('the title block is not turned', stream =~ /1 0 0 1 [0-9.]+ [0-9.]+ Tm\n(?:[^\n]*\n)?\(Job address :\) Tj/)

# ---------------------------------------------------------------------------
# 5. the sheet window's side
# ---------------------------------------------------------------------------
def open!
  Sketchup.reset_model!
  PSD.instance_variable_set(:@site_lines, nil)
  PSD.instance_variable_set(:@site_owner, nil)
  PSD.instance_variable_set(:@site_owner_path, nil)
  PSD.site_lines = [[[0.0, 0.0], [10.0, 0.0]], [[0.0, 5.0], [10.0, 5.0]]]
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end
dlg = open!
first = JSON.parse(dlg.scripts.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1])
ok('the window is told that turning is on', first['rotate'] == true)
ok('a sheet never turned opens at 0', first['state']['rotation'] == 0 && first['doc']['pages'][0]['views'][0]['rotation'] == 0.0, first['state']['rotation'])
ok('the window can send a turn', dlg.callbacks.key?('set_rotation'))
doc0  = PSD.document
sheets = dlg.scripts.count { |x| x.start_with?('loadSheet(') }
dlg.callbacks['set_rotation'].call(nil, JSON.generate('rotation' => 35))
ok('THE TURN IS SAVED ON THE MODEL', PSD.load_state['rotation'] == 35.0, PSD.load_state['rotation'])
ok('the document Ruby is holding is turned - the PDF will be too', PSD.document.equal?(doc0) && PSD.document.pages[0].views.first.rotation == 35.0)
ans = dlg.scripts.last
ok('the answer is the pages and the layers of the plan - not the whole sheet again',
   ans.start_with?('applyLayers(') && dlg.scripts.count { |x| x.start_with?('loadSheet(') } == sheets, ans[0, 40])
lays = JSON.parse('[' + ans[/\AapplyLayers\((.*)\)\z/m, 1] + ']')
ok('the loose lines are NOT sent again - they carry no writing and are a megabyte on a real yard',
   lays[1].is_a?(Array) && lays[1].none? { |l| l['name'] == PG::LAYER } && PSD.document.canvas('MODEL').layers.any? { |l| l.name == PG::LAYER },
   lays[1].map { |l| l['name'] })
ok('the pages that go back carry the angle', lays[0][0]['views'][0]['rotation'] == 35.0)
dlg.callbacks['set_rotation'].call(nil, JSON.generate('rotation' => 400))
ok('400 degrees is saved as 40', PSD.load_state['rotation'] == 40.0, PSD.load_state['rotation'])
# anything else the window saves afterwards must not lose the turn
st = PSD.load_state
dlg.callbacks['set_state'].call(nil, JSON.generate(st.merge('address' => '6 Bronco Ln')))
ok('saving something else afterwards keeps the turn', PSD.load_state['rotation'] == 40.0 && PSD.document.pages[0].views.first.rotation == 40.0)
# and a sheet opened later opens turned
dlg = open_again = (PSD.show; d2 = PSD.instance_variable_get(:@dialog); d2.callbacks['sheet_ready'].call(nil); d2)
again = JSON.parse(dlg.scripts.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1])
ok('the window opened again opens turned', again['state']['rotation'] == 40.0 && again['doc']['pages'][0]['views'][0]['rotation'] == 40.0)

# ---------------------------------------------------------------------------
# 6. the switch
# ---------------------------------------------------------------------------
PC.send(:remove_const, :USE_VIEW_ROTATION)
PC.const_set(:USE_VIEW_ROTATION, false)
off = build_doc
PC.layout_pages!(off, state(35))
ok('switched off: the angle is ignored and the drawing is laid square, exactly as before',
   view(off).rotation == 0.0 && snap.call(off) == snap.call(flat))
PC.send(:remove_const, :USE_VIEW_ROTATION)
PC.const_set(:USE_VIEW_ROTATION, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt272 - the drawing sits in a box of its own (2026-10-07), the Ruby side.
#
# The user, on what he likes in Rayon: "השרטוט... נמצא בתוך כמו קופסה משל עצמו.
# את הקופסה אני יכול להגדיל ולהקטין בעיקר מהפינות... ולהזיז אותה על הדף." And:
# "כן טוב לקבוע שוליים לדף שהקופסה לא תוכל לצאת מהם. לא רוצה שקנה המידה יקפוץ -
# אני רוצה שתהיה אופציה להגדיל ידנית, ושלהגדיר בגדלים נכונים."
#
# t72 pins the window: the handles, the dragging, Escape, Ctrl+Z. This pins what
# Ruby does with the two things the window saves:
#   st['view_box'] = [x, y, w, h]   where the box is on the sheet
#   st['scale_f']  = a number       a size set by hand, paper inches to the foot
#
#   - the window on the plan sheet IS that box, and the drawing is that size:
#     the PDF is clipped to the box and drawn at the size, like the window;
#   - the box is held inside the margins here, whatever was saved;
#   - a size set by hand is not a scale with a name: the title block says so;
#   - nothing saved = the whole sheet at the scale from the list, exactly as
#     before - and the sheet says which part the margins leave, so the window
#     can hold the box in while he drags.
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
def near(a, b, tol = 1.0e-9); (a.to_f - b.to_f).abs < tol; end
def near4(p, q, tol = 1.0e-9); p.each_with_index.all? { |v, i| near(v, q[i], tol) }; end

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog

ok('there is a switch, and it is on', PC.const_defined?(:USE_VIEW_BOX, false) && PC::USE_VIEW_BOX == true)

def build_doc
  doc = PD::Document.new('t')
  cv  = doc.canvas('MODEL')
  cv.layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  cv.layer('ROOMS').text('ROOM 1', 100.0, 65.0, h: 7.0, align: :center, rotation: 0.0)
  doc
end
def state(extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
    'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => [] }.merge(extra)
end
def plan(doc); doc.pages.find { |pg| pg.kind == 'plan' }; end
def view(doc); plan(doc).views.first; end
def rect(v); [v.x, v.y, v.w, v.h]; end
def title_scale(doc)
  sh = plan(doc).layers.find { |l| l.name == PD::TITLE_LAYER }.shapes
  i  = sh.index { |s| s[:type] == :text && s[:text] == 'Scale :' }
  sh[i + 1][:text]
end

# ---------------------------------------------------------------------------
# 1. nothing saved: the sheet as it always was
# ---------------------------------------------------------------------------
old = build_doc
PC.layout_pages!(old, state)
AREA = rect(view(old))
ok('NOTHING SAVED: the box is the whole of what the margins leave, as it always was', near4(AREA, [0.75, 1.85, 34.5, 21.4]), AREA)
ok('and the drawing is at the scale from the list', view(old).scale_free.nil? && near(view(old).scale_factor, 0.25 / 12.0))
ok('the title block names that scale', title_scale(old) == "1/4\" = 1'-0\"", title_scale(old))
ok('THE SHEET SAYS WHICH PART THE MARGINS LEAVE - the window holds the box inside it',
   near4(plan(old).view_area, AREA) && near4(plan(old).to_h[:view_area], AREA), plan(old).view_area)
ok('a sheet with no drawing on it has no such part', (d = build_doc; PC.layout_pages!(d, state('images' => ['C:/x/a.jpg'])); d.pages.find { |pg| pg.kind == 'image' }.view_area.nil?))

# ---------------------------------------------------------------------------
# 2. the box, and a size set by hand
# ---------------------------------------------------------------------------
doc = build_doc
PC.layout_pages!(doc, state('view_box' => [10.0, 8.0, 12.0, 9.0], 'scale_f' => 0.1037))
v = view(doc)
ok('THE WINDOW ON THE PLAN SHEET IS THE BOX HE LEFT  <<< THE RULE', near4(rect(v), [10.0, 8.0, 12.0, 9.0]), rect(v))
ok('THE DRAWING IS THE SIZE HE PULLED IT TO - not the nearest scale in the list', near(v.scale_free, 0.1037) && near(v.scale_factor, 0.1037 / 12.0), v.scale_factor * 12)
ok('the middle of the box is where the drawing is hung from', near4(v.model_to_paper(120.0, 60.0) + [0, 0], [16.0, 12.5, 0, 0]), v.model_to_paper(120.0, 60.0))
ok('a foot of wall is that many paper inches', near(v.model_to_paper(132.0, 60.0)[0] - v.model_to_paper(120.0, 60.0)[0], 0.1037))
ok('A SIZE SET BY HAND IS NOT A SCALE WITH A NAME: the title block says N.T.S.', title_scale(doc) == 'N.T.S.', title_scale(doc))
ok('what the margins leave is still the whole of it, whatever the box', near4(plan(doc).view_area, AREA))
h = v.to_h
ok('the box and the size travel with the window to whoever draws it', near4([h[:x], h[:y], h[:w], h[:h]], [10.0, 8.0, 12.0, 9.0]) && near(h[:scale_free], 0.1037))

# the PDF is clipped to the box and drawn at that size
stream = PP.page_stream(plan(doc), doc)
num = ->(x) { format('%.3f', x.to_f) }
ok('THE PDF IS CLIPPED TO THE BOX', stream.include?("#{num.call(10.0 * 72)} #{num.call(8.0 * 72)} #{num.call(12.0 * 72)} #{num.call(9.0 * 72)} re W n"), stream[0, 200])
a = v.model_to_paper(0.0, 0.0)
b = v.model_to_paper(240.0, 0.0)
ok('and the wall in it is the size he set', stream.include?("#{num.call(a[0] * 72)} #{num.call(a[1] * 72)} m") && near(b[0] - a[0], 240.0 * 0.1037 / 12.0), [a, b])
tm = stream[/BT(?:(?!ET).)*?\(ROOM 1\) Tj/m].to_s[/^\/F\d [0-9.]+ Tf$/]
ok('the writing on the plan is that size too', near(tm.to_s.split[1].to_f, 7.0 * (0.1037 / 12.0) * 72.0 / PP::CAP_RATIO, 0.001), tm)

# the box alone, at a scale from the list: an exact scale in a small box
ex = build_doc
PC.layout_pages!(ex, state('view_box' => [10.0, 8.0, 12.0, 9.0], 'scale' => '1/8"'))
ok('A BOX WITH A SCALE FROM THE LIST: the box is his, the scale is exact, and it has its name',
   near4(rect(view(ex)), [10.0, 8.0, 12.0, 9.0]) && view(ex).scale_free.nil? && near(view(ex).scale_factor, 0.125 / 12.0) && title_scale(ex) == "1/8\" = 1'-0\"", title_scale(ex))

# turned, in its box: it turns about the middle of the box
tr = build_doc
PC.layout_pages!(tr, state('view_box' => [10.0, 8.0, 12.0, 9.0], 'rotation' => 90))
ok('a turned drawing turns about the middle of its box', near4(view(tr).model_to_paper(120.0, 60.0) + [0, 0], [16.0, 12.5, 0, 0]) && view(tr).rotation == 90.0)

# ---------------------------------------------------------------------------
# 3. the margins
# ---------------------------------------------------------------------------
[[[-5.0, -5.0, 12.0, 9.0],   [0.75, 1.85, 12.0, 9.0],            'off the bottom left'],
 [[30.0, 20.0, 12.0, 9.0],   [23.25, 14.25, 12.0, 9.0],          'off the top right'],
 [[10.0, 8.0, 80.0, 9.0],    [0.75, 8.0, 34.5, 9.0],             'wider than the sheet'],
 [[10.0, 8.0, 12.0, 80.0],   [10.0, 1.85, 12.0, 21.4],           'taller than the sheet'],
 [[10.0, 8.0, 0.2, 0.1],     [10.0, 8.0, 1.0, 1.0],              'too small to be a box']].each do |saved, want, why|
  d = build_doc
  PC.layout_pages!(d, state('view_box' => saved))
  ok("A BOX SAVED #{why.upcase} IS HELD INSIDE THE MARGINS", near4(rect(view(d)), want), rect(view(d)))
end
# a smaller sheet of paper: the box that fitted the big one is held inside the small one
small = build_doc
PC.layout_pages!(small, state('size' => 'LETTER', 'view_box' => [10.0, 8.0, 12.0, 9.0]))
sa = plan(small).view_area
sv = rect(view(small))
ok('on a smaller sheet of paper the same box is held inside ITS margins',
   sv[0] >= sa[0] - 1e-9 && sv[1] >= sa[1] - 1e-9 && sv[0] + sv[2] <= sa[0] + sa[2] + 1e-9 && sv[1] + sv[3] <= sa[1] + sa[3] + 1e-9, [sv, sa])

# what is not a box is not used
[[1.0, 2.0, 3.0], 'box', [1.0, 2.0, 'x', 4.0], [1.0, 2.0, 0.0, 4.0], [1.0, 2.0, 3.0, -4.0], nil].each do |bad|
  d = build_doc
  PC.layout_pages!(d, state('view_box' => bad))
  ok("not a box, not used: #{bad.inspect[0, 30]}", near4(rect(view(d)), AREA), rect(view(d)))
end
[0, -1.0, 'big', 4000.0, nil].each do |bad|
  d = build_doc
  PC.layout_pages!(d, state('scale_f' => bad))
  ok("not a size, not used: #{bad.inspect}", view(d).scale_free.nil? && near(view(d).scale_factor, 0.25 / 12.0) && title_scale(d) == "1/4\" = 1'-0\"")
end

# laid out again and again, nothing creeps
snap = ->(d) { JSON.generate(d.pages.map(&:to_h)) }
one = snap.call(doc)
3.times { PC.layout_pages!(doc, state('view_box' => [10.0, 8.0, 12.0, 9.0], 'scale_f' => 0.1037)) }
ok('laid out again and again, nothing creeps', snap.call(doc) == one)

# ---------------------------------------------------------------------------
# 4. the sheet window's side
# ---------------------------------------------------------------------------
def open!
  Sketchup.reset_model!
  %i[@site_lines @site_owner @site_owner_path].each { |iv| PSD.instance_variable_set(iv, nil) }
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end
def sheet(dlg); JSON.parse(dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1]); end
dlg = open!
first = sheet(dlg)
ok('the window is told that the box is on', first['view_box'] == true)
ok('a sheet that never heard of the box opens with none saved', !first['state'].key?('view_box') && !first['state'].key?('scale_f'), first['state'].keys)
ok('and is told which part the margins leave', near4(first['doc']['pages'][0]['view_area'], AREA), first['doc']['pages'][0]['view_area'])
st = PSD.load_state.merge('view_box' => [10.0, 8.0, 12.0, 9.0], 'scale_f' => 0.1037)
dlg.callbacks['set_state'].call(nil, JSON.generate(st))
ok('THE BOX AND THE SIZE ARE SAVED ON THE MODEL', PSD.load_state['view_box'] == [10.0, 8.0, 12.0, 9.0] && near(PSD.load_state['scale_f'], 0.1037), PSD.load_state.select { |k, _| %w[view_box scale_f].include?(k) })
ok('the document Ruby is holding has the box - the PDF will too', near4(rect(PSD.document.pages[0].views.first), [10.0, 8.0, 12.0, 9.0]))
ans = dlg.scripts.last
pages = JSON.parse('[' + ans[/\AapplyPages\((.*)\)\z/m, 1].to_s + ']')[0]
ok('the answer is the pages, with the box as Ruby holds it', ans.start_with?('applyPages(') && near4(pages[0]['views'][0].values_at('x', 'y', 'w', 'h'), [10.0, 8.0, 12.0, 9.0]), ans[0, 30])
# back to an exact scale: the window sends null for the size
dlg.callbacks['set_state'].call(nil, JSON.generate(PSD.load_state.merge('scale' => '1/8"', 'scale_f' => nil)))
ok('picking a scale from the list forgets the size set by hand, and keeps the box',
   PSD.load_state['scale_f'].nil? && PSD.load_state['view_box'] == [10.0, 8.0, 12.0, 9.0] && PSD.document.pages[0].views.first.scale_free.nil?)
# the window opened again opens with the box
d2 = (PSD.show; x = PSD.instance_variable_get(:@dialog); x.callbacks['sheet_ready'].call(nil); x)
again = sheet(d2)
ok('the window opened again opens with the box', again['state']['view_box'] == [10.0, 8.0, 12.0, 9.0] && near4(again['doc']['pages'][0]['views'][0].values_at('x', 'y', 'w', 'h'), [10.0, 8.0, 12.0, 9.0]))

# ---------------------------------------------------------------------------
# 5. the switch
# ---------------------------------------------------------------------------
PC.send(:remove_const, :USE_VIEW_BOX)
PC.const_set(:USE_VIEW_BOX, false)
off = build_doc
PC.layout_pages!(off, state('view_box' => [10.0, 8.0, 12.0, 9.0], 'scale_f' => 0.1037))
ok('switched off: the box and the size are ignored - the whole sheet, the scale from the list',
   near4(rect(view(off)), AREA) && view(off).scale_free.nil? && title_scale(off) == "1/4\" = 1'-0\"", [rect(view(off)), title_scale(off)])
PC.send(:remove_const, :USE_VIEW_BOX)
PC.const_set(:USE_VIEW_BOX, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

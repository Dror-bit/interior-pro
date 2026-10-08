# encoding: utf-8
# rt280 - the drawing's box turns AS A WHOLE (2026-10-07, stage 5 of the box), the Ruby side.
#
# The user, on Rayon: "השרטוט הוא כאילו חצי תמונה - הוא נמצא בתוך כמו קופסה
# משל עצמו... וכמובן אני גם יכול לסובב אותה ולהזיז אותה על הדף." Until now the
# lines turned inside a frame that stayed square to the paper. Now:
#   - the window carries box_turn, and the PDF clips to the four turned corners;
#   - a turned box is held inside the margins by the room it takes up turned -
#     made smaller as a whole (the scale is not touched), then pushed in - the
#     box he saved and the whole-of-the-margins box alike;
#   - the lines turn about the middle of the box, as they did, so what the
#     window shows and what the PDF prints are the same points of the paper;
#   - a cut on a side of a turned box (the window's sum) leaves every line on
#     its spot;
#   - not turned: everything to the digit as before; the switch off: as before.
# t80 pins the window's side.
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

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt280_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

ok('there is a switch for it, and it is on', PC.const_defined?(:USE_BOX_TURN, false) && PC::USE_BOX_TURN == true)

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
def laid(st); d = build_doc; PC.layout_pages!(d, st); d; end
SPOTS = [[0.0, 0.0], [240.0, 0.0], [240.0, 120.0], [100.0, 65.0], [-300.0, 410.5]].freeze
def where(doc); SPOTS.map { |x, y| view(doc).model_to_paper(x, y) }; end
def stayed(a, b, tol = 1.0e-9); a.each_with_index.all? { |p, i| near(p[0], b[i][0], tol) && near(p[1], b[i][1], tol) }; end
# the room a turned box takes up on the paper: [min x, min y, max x, max y]
def hull(v)
  pts = v.frame_corners
  [pts.map(&:first).min, pts.map(&:last).min, pts.map(&:first).max, pts.map(&:last).max]
end
def inside?(v, a)
  h = hull(v)
  h[0] >= a[0] - 1e-9 && h[1] >= a[1] - 1e-9 && h[2] <= a[0] + a[2] + 1e-9 && h[3] <= a[1] + a[3] + 1e-9
end
def stream(doc)
  out = File.join(TMP, 'x.pdf')
  PP.export(doc, out)
  File.binread(out).scan(/stream\r?\n(.*?)endstream/m).map { |m| (Zlib::Inflate.inflate(m[0]) rescue m[0]) }.join("\n")
end
num = ->(x) { format('%.3f', x.to_f) }
clip_of = ->(v) { v.frame_corners.each_with_index.map { |(px, py), i| "#{num.call(px * 72)} #{num.call(py * 72)} #{i.zero? ? 'm' : 'l'}" }.join(' ') + ' h W n' }
square_of = ->(v) { "#{num.call(v.x * 72)} #{num.call(v.y * 72)} #{num.call(v.w * 72)} #{num.call(v.h * 72)} re W n" }

# ---------------------------------------------------------------------------
# 1. the window itself
# ---------------------------------------------------------------------------
v = PD::View.new('v', 2.0, 3.0, 10.0, 6.0, 'MODEL')
ok('a new window does not turn its frame, and says so to whoever draws it', !v.box_turn && v.to_h[:box_turn] == false)
ok('not turned: the four corners are the square ones', v.frame_corners == [[2.0, 3.0], [12.0, 3.0], [12.0, 9.0], [2.0, 9.0]])
v.rotation = 90
ok('turned, but the frame not: still the square ones', v.frame_corners == [[2.0, 3.0], [12.0, 3.0], [12.0, 9.0], [2.0, 9.0]])
v.box_turn = true
fc = v.frame_corners
ok('THE FRAME TURNS: a quarter turn about the middle (7, 6) puts the bottom left corner at (10, 1)',
   near4(fc[0], [10.0, 1.0]) && near4(fc[1], [10.0, 11.0]) && near4(fc[2], [4.0, 11.0]) && near4(fc[3], [4.0, 1.0]) && v.to_h[:box_turn] == true, fc)
ok('a corner of the frame and the point of the house under it turn together',
   near4(v.model_to_paper(*v.paper_to_model(2.0, 3.0)), [2.0, 3.0]) &&
   near4(v.frame_corners[0], v.model_to_paper(*PD::View.new('q', 2.0, 3.0, 10.0, 6.0, 'MODEL').tap { |q| q.rotation = 0 }.paper_to_model(2.0, 3.0))), v.frame_corners[0])

# ---------------------------------------------------------------------------
# 2. laid out: not turned = as before, to the digit
# ---------------------------------------------------------------------------
d0 = laid(state)
area = plan(d0).view_area
ok('NOT TURNED: the box is all the margins leave, the frame set to turn with it', near4(rect(view(d0)), area) && view(d0).box_turn == true && view(d0).rotation == 0.0, rect(view(d0)))
ok('and the PDF clips it with a square, as it always did', stream(d0).include?(square_of.call(view(d0))))
d1 = laid(state('view_box' => [4.0, 4.0, 16.0, 12.0]))
ok('a saved box, not turned: as before', near4(rect(view(d1)), [4.0, 4.0, 16.0, 12.0]))
d2 = laid(state('view_box' => [-5.0, -5.0, 60.0, 40.0]))
ok('a saved box too big, not turned: made to fit each way on its own, as before (box_inside)', near4(rect(view(d2)), area), rect(view(d2)))

# ---------------------------------------------------------------------------
# 3. turned: the frame, the clip, the hold
# ---------------------------------------------------------------------------
t1 = laid(state('view_box' => [8.0, 5.0, 12.0, 8.0], 'rotation' => 30.0))
v1 = view(t1)
ok('A TURNED BOX THAT FITS: left exactly where it was saved, turned 30', near4(rect(v1), [8.0, 5.0, 12.0, 8.0]) && near(v1.rotation, 30.0) && v1.box_turn == true, rect(v1))
s1 = stream(t1)
ok('THE PDF CLIPS TO THE FOUR TURNED CORNERS, not a square', s1.include?(clip_of.call(v1)) && !s1.include?(square_of.call(v1)))
ok('the lines are turned about the middle of the box, as they were', near4(v1.model_to_paper(120.0, 60.0), [14.0, 9.0]) && near4(where(t1)[1], [14.0 + 2.5 * Math.cos(Math::PI / 6) + 1.25 * Math.sin(Math::PI / 6), 9.0 + 2.5 * Math.sin(Math::PI / 6) - 1.25 * Math.cos(Math::PI / 6)]), where(t1)[1])

t2 = laid(state('rotation' => 90.0))
v2 = view(t2)
ok('THE WHOLE-OF-THE-MARGINS BOX TURNED A QUARTER: made smaller as a whole to fit, in the middle of the space, the scale untouched',
   inside?(v2, area) && near(v2.w / v2.h, area[2] / area[3]) && near(v2.w, area[3]) && near(v2.x + v2.w / 2, area[0] + area[2] / 2) && near(v2.y + v2.h / 2, area[1] + area[3] / 2) &&
   near(v2.scale_factor, 0.25 / 12, 1e-12) && v2.scale_free.nil?, [rect(v2), area])
ok('the house hangs from the middle still', near4(v2.model_to_paper(120.0, 60.0), [v2.x + v2.w / 2, v2.y + v2.h / 2]))
t3 = laid(state('view_box' => [area[0] + area[2] - 10.0, area[1] + area[3] - 6.0, 10.0, 6.0], 'rotation' => 45.0))
v3 = view(t3)
ok('A SAVED BOX IN THE CORNER, TURNED 45: it would hang off, so it is pushed in - same size, inside', inside?(v3, area) && near(v3.w, 10.0) && near(v3.h, 6.0), rect(v3))
t4 = laid(state('view_box' => [0.0, 0.0, 30.0, 4.0], 'rotation' => 90.0))
v4 = view(t4)
ok('a long box standing up: made smaller as a whole, never thinner than an inch', inside?(v4, area) && near(v4.w / v4.h, 7.5) && v4.h >= 1.0 - 1e-9, rect(v4))
snap = ->(d) { JSON.generate(d.pages.map(&:to_h)) }
one = snap.call(t2)
3.times { PC.layout_pages!(t2, state('rotation' => 90.0)) }
ok('laid out again and again, nothing creeps', snap.call(t2) == one)

# a side of a TURNED box cut, the window's way: the lines stay on their spot
def cut_turned(st, box, side, d)
  x, y, w, h = box
  r = st['rotation'].to_f * Math::PI / 180.0
  c = Math.cos(r); n = Math.sin(r)
  cx0 = x + w / 2.0; cy0 = y + h / 2.0
  nw, nh, ux, uy = w, h, 0.0, 0.0
  case side
  when :e then nw = w + d; ux = d / 2.0
  when :w then nw = w + d; ux = -d / 2.0
  when :n then nh = h + d; uy = d / 2.0
  when :s then nh = h + d; uy = -d / 2.0
  end
  cx = cx0 + ux * c - uy * n; cy = cy0 + ux * n + uy * c
  mx = cx - cx0; my = cy - cy0
  sf = PD::SCALES.assoc(st['scale'])[1] / 12.0
  st.merge('view_box' => [cx - nw / 2.0, cy - nh / 2.0, nw, nh],
           'origin_x' => st['origin_x'] + (mx * c + my * n) / sf,
           'origin_y' => st['origin_y'] + (-mx * n + my * c) / sf)
end
p1 = where(t1)
t5 = laid(cut_turned(cut_turned(state('view_box' => [8.0, 5.0, 12.0, 8.0], 'rotation' => 30.0), [8.0, 5.0, 12.0, 8.0], :e, -3.0), [8.0, 5.0, 12.0, 8.0], :n, -2.0))
# (the second cut is worked from the first box, so do it by hand)
b5 = cut_turned(state('view_box' => [8.0, 5.0, 12.0, 8.0], 'rotation' => 30.0), [8.0, 5.0, 12.0, 8.0], :e, -3.0)
t5 = laid(cut_turned(b5, b5['view_box'], :n, -2.0))
ok('A SIDE OF A TURNED BOX CUT (the window\'s sum): the box is 9 by 6, still turned 30', near(view(t5).w, 9.0) && near(view(t5).h, 6.0) && near(view(t5).rotation, 30.0), rect(view(t5)))
ok('AND EVERY LINE IS STILL ON ITS SPOT OF THE PAPER', stayed(where(t5), p1), [where(t5), p1])

# ---------------------------------------------------------------------------
# 4. the sheet window: set_rotation takes the box the turn left, and traces
# ---------------------------------------------------------------------------
def open!
  Sketchup.reset_model!
  %i[@site_lines @site_owner @site_owner_path @doc].each { |iv| PSD.instance_variable_set(iv, nil) }
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end
dlg = open!
trace = File.join(PSD.plugin_dir, 'sheet_erase_trace.txt')
tsize = File.exist?(trace) ? File.size(trace) : 0
dlg.callbacks['set_rotation'].call(nil, JSON.generate('rotation' => 30.0, 'view_box' => [8.0, 5.0, 12.0, 8.0]))
st = PSD.load_state
ok('THE WINDOW SENDS THE BOX WITH THE TURN: both are saved', st['rotation'] == 30.0 && st['view_box'] == [8.0, 5.0, 12.0, 8.0], st.values_at('rotation', 'view_box'))
pv = PSD.document.pages.first.views.first
ok('and the sheet Ruby holds has the turned box', near4(rect(pv), [8.0, 5.0, 12.0, 8.0]) && near(pv.rotation, 30.0) && pv.box_turn == true)
tl = File.exist?(trace) ? File.read(trace, encoding: 'UTF-8')[tsize..-1].to_s : ''
ok('a trace line says the angle and the box', tl.include?('turn: 30.0 deg, box [8.000, 5.000, 12.000, 8.000] (the box turns as a whole)'), tl)
ans = dlg.scripts.last
ok('the answer is the pages, turned, with the box', ans.start_with?('applyLayers(') && JSON.parse('[' + ans[/\AapplyLayers\((.*)\)\z/m, 1] + ']')[0][0]['views'][0]['box_turn'] == true)
dlg.callbacks['set_rotation'].call(nil, JSON.generate('rotation' => 0.0, 'view_box' => nil))
ok('null = the box is all the margins leave again', PSD.load_state['view_box'].nil? && near4(rect(PSD.document.pages.first.views.first), area))
dlg.callbacks['set_rotation'].call(nil, JSON.generate('rotation' => 15.0))
ok('a turn without a box (the old message) leaves the box as it is', PSD.load_state['view_box'].nil? && PSD.load_state['rotation'] == 15.0)

# ---------------------------------------------------------------------------
# 5. the switch
# ---------------------------------------------------------------------------
PC.send(:remove_const, :USE_BOX_TURN)
PC.const_set(:USE_BOX_TURN, false)
f1 = laid(state('rotation' => 90.0))
ok('SWITCHED OFF: the frame stays square to the paper, all the margins leave, and the PDF clips with the square - as before',
   near4(rect(view(f1)), area) && view(f1).box_turn == false && near(view(f1).rotation, 90.0) && stream(f1).include?(square_of.call(view(f1))), rect(view(f1)))
f2 = laid(state('view_box' => [8.0, 5.0, 12.0, 8.0], 'rotation' => 30.0))
ok('switched off, a saved box: held each way on its own, no turned clip', near4(rect(view(f2)), [8.0, 5.0, 12.0, 8.0]) && !stream(f2).include?('h W n'))
dlg = open!
dlg.callbacks['set_rotation'].call(nil, JSON.generate('rotation' => 30.0, 'view_box' => [8.0, 5.0, 12.0, 8.0]))
ok('switched off: the window is told the frame does not turn', JSON.parse('[' + dlg.scripts.last[/\AapplyLayers\((.*)\)\z/m, 1] + ']')[0][0]['views'][0]['box_turn'] == false)
PC.send(:remove_const, :USE_BOX_TURN)
PC.const_set(:USE_BOX_TURN, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

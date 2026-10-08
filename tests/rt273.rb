# encoding: utf-8
# rt273 - a side of the drawing's box CUTS the drawing (2026-10-07), the Ruby side.
#
# The user: "את הקופסה אני יכול להגדיל ולהקטין בעיקר מהפינות, אני יכול לחתוך
# מהצלעות" - and earlier, with two pictures: "אני גם יכול לבחור מה יראו מהתמונה
# או מהשרטוט - חיתוך."
#
# t73 pins the window: a side is pulled, only it moves, and the drawing stays on
# the spot of the paper it was on. The window does that by saving two things it
# already saved - the box, and which point of the house sits in the middle of
# it. Nothing new is stored. This pins that RUBY, laying the sheet out from
# those two for the PDF, puts every line on the very same spot of the paper:
#   - a cut box + the point the window worked out = the drawing where it was;
#   - the same for a turned drawing, and for one at a size set by hand;
#   - the PDF is clipped to the cut box, so what is outside it is not printed;
#   - a cut does not change the scale: the title block still names it.
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

ok('there is a switch, and it is on', PSD.const_defined?(:USE_BOX_CROP, false) && PSD::USE_BOX_CROP == true)

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
def laid(st)
  d = build_doc
  PC.layout_pages!(d, st)
  d
end
SPOTS = [[0.0, 0.0], [240.0, 0.0], [240.0, 120.0], [100.0, 65.0], [-300.0, 410.5]].freeze
def where(doc); SPOTS.map { |x, y| view(doc).model_to_paper(x, y) }; end
def stayed(a, b, tol = 1.0e-9)
  a.each_with_index.all? { |p, i| near(p[0], b[i][0], tol) && near(p[1], b[i][1], tol) }
end
def title_scale(doc)
  sh = plan(doc).layers.find { |l| l.name == PD::TITLE_LAYER }.shapes
  i  = sh.index { |s| s[:type] == :text && s[:text] == 'Scale :' }
  sh[i + 1][:text]
end

# What the window saves after a side is pulled: the new box, and the point of
# the house that is now in the middle of it. Written out here in full, from the
# rule and not from the window's code: the middle of the box moved by (mx, my)
# on the paper, so the point in the middle moves by the same, taken back
# through the turn and the size.
def cut(st, area, side, d)
  x, y, w, h = st['view_box'] || area
  nx, ny, nw, nh = x, y, w, h
  case side
  when :e then nw = w + d
  when :w then nx = x + d; nw = w - d
  when :n then nh = h + d
  when :s then ny = y + d; nh = h - d
  end
  mx = (nx + nw / 2.0) - (x + w / 2.0)
  my = (ny + nh / 2.0) - (y + h / 2.0)
  r  = st['rotation'].to_f * Math::PI / 180.0
  sf = (st['scale_f'] ? st['scale_f'].to_f : PD::SCALES.assoc(st['scale'])[1]) / 12.0
  st.merge('view_box' => [nx, ny, nw, nh],
           'origin_x' => st['origin_x'] + (mx * Math.cos(r) + my * Math.sin(r)) / sf,
           'origin_y' => st['origin_y'] + (-mx * Math.sin(r) + my * Math.cos(r)) / sf)
end

# ---------------------------------------------------------------------------
# 1. the sheet as it was, and the same sheet with its right side pulled in
# ---------------------------------------------------------------------------
st0  = state
d0   = laid(st0)
area = plan(d0).view_area
p0   = where(d0)
ok('the sheet says which part the margins leave', near4(area, [0.75, 1.85, 34.5, 21.4]), area)

st1 = cut(st0, area, :e, -10.0)
d1  = laid(st1)
ok('THE BOX IS THE CUT BOX: only its right side moved', near4(rect(view(d1)), [0.75, 1.85, 24.5, 21.4]), rect(view(d1)))
ok('RUBY PUTS EVERY LINE ON THE SPOT OF THE PAPER IT WAS ON  <<< THE RULE', stayed(where(d1), p0), [where(d1), p0])
ok('the drawing is still at its scale, and the title block still names it',
   view(d1).scale_free.nil? && near(view(d1).scale_factor, 0.25 / 12.0, 1.0e-12) && title_scale(d1) == "1/4\" = 1'-0\"", title_scale(d1))

# all four sides, one after another
st4 = cut(cut(cut(st1, area, :w, 3.0), area, :n, -2.0), area, :s, 1.5)
d4  = laid(st4)
ok('cut on all four sides: the box', near4(rect(view(d4)), [3.75, 3.35, 21.5, 17.9]), rect(view(d4)))
ok('CUT ON ALL FOUR SIDES: every line still on its spot', stayed(where(d4), p0), [where(d4), p0])

# ---------------------------------------------------------------------------
# 2. the PDF: clipped to the cut box, the lines where they were
# ---------------------------------------------------------------------------
n3 = ->(v) { format('%.3f', v.to_f) }
s0 = PP.page_stream(plan(d0), d0)
s4 = PP.page_stream(plan(d4), d4)
v4 = view(d4)
clip = "#{n3.(v4.x * 72)} #{n3.(v4.y * 72)} #{n3.(v4.w * 72)} #{n3.(v4.h * 72)} re W n"
ok('THE PDF IS CLIPPED TO THE CUT BOX: what is outside it is not printed', s4.include?(clip), clip)
wall = ->(s) { s.lines.map(&:strip).select { |l| l =~ / [ml]\z/ }.first(3) }
ok('THE WALL IS DRAWN AT THE VERY SAME POINTS OF THE PAPER IN BOTH PDFS', wall.(s0) == wall.(s4) && wall.(s0).length == 3, [wall.(s0), wall.(s4)])
room = ->(s) { ls = s.lines.map(&:strip); i = ls.index { |l| l.include?('(ROOM 1) Tj') }; ls[0...i].reverse.find { |l| l =~ /Tm\z/ } }
ok('and the room name is written at the very same point', room.(s0) == room.(s4) && !room.(s0).nil?, [room.(s0), room.(s4)])

# ---------------------------------------------------------------------------
# 3. a turned drawing, and a drawing at a size set by hand
# ---------------------------------------------------------------------------
# (the frame square to the paper, the lines turned inside it - the day this was
# built. Since stage 5 the box turns as a whole and is held by its turned room;
# that road is rt280's. Here the old road, with the switch off.)
PC.send(:remove_const, :USE_BOX_TURN)
PC.const_set(:USE_BOX_TURN, false)
t0  = state('rotation' => 30.0)
dt0 = laid(t0)
pt0 = where(dt0)
t3  = cut(cut(cut(t0, area, :e, -7.0), area, :n, -3.0), area, :w, 2.0)
dt3 = laid(t3)
ok('A TURNED DRAWING, cut on three sides: the box', near4(rect(view(dt3)), [2.75, 1.85, 25.5, 18.4]) && near(view(dt3).rotation, 30.0), rect(view(dt3)))
ok('A TURNED DRAWING: every line still on its spot', stayed(where(dt3), pt0), [where(dt3), pt0])
PC.send(:remove_const, :USE_BOX_TURN)
PC.const_set(:USE_BOX_TURN, true)

h0  = state('view_box' => [2.0, 4.0, 16.0, 12.0], 'scale_f' => 0.11)
dh0 = laid(h0)
ph0 = where(dh0)
h2  = cut(cut(h0, area, :e, -4.0), area, :s, 2.5)
dh2 = laid(h2)
ok('A SIZE SET BY HAND, cut on two sides: the size is what it was', near(view(dh2).scale_free, 0.11) && near4(rect(view(dh2)), [2.0, 6.5, 12.0, 9.5]), [view(dh2).scale_free, rect(view(dh2))])
ok('A SIZE SET BY HAND: every line still on its spot', stayed(where(dh2), ph0), [where(dh2), ph0])

# opened up again as far as the margins: the same sheet as at the start
back = cut(cut(st1, area, :e, 10.0), area, :e, 0.0)
db   = laid(back)
ok('a side pulled back out to the margin gives the sheet he started with', near4(rect(view(db)), area) && stayed(where(db), p0) && near(back['origin_x'], 120.0) && near(back['origin_y'], 60.0), [rect(view(db)), back['origin_x']])

# ---------------------------------------------------------------------------
# 4. what the window is told
# ---------------------------------------------------------------------------
src = File.read('plan_sheet_dialog.rb', encoding: 'UTF-8')
ok('the sheet tells the window that a side cuts', src.include?('box_crop: USE_BOX_CROP'))
ok('the box and the place of the drawing are both kept with the sheet',
   PSD.extra_state_keys.include?('view_box') && PSD.extra_state_keys.include?('origin_x') && PSD.extra_state_keys.include?('origin_y'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

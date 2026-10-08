# encoding: utf-8
# rt275 - a piece of writing sits in a box of its own (2026-10-07), the Ruby side.
#
# The user: "אני רוצה להוסיף אופציה של קופסא עם כיתוב. כמובן שהקופסא צריכה להתנהג
# כמו שאר הקופסאות, ובקופסא יהיה אפשר לכתוב ולקבוע את גודל הכיתוב."
#
# t75 pins the window: the T tool, typing, picking, dragging, a corner, a side,
# the round arrow, two clicks, Delete, Escape, Ctrl+Z. This pins what Ruby does
# with what the window saves:
#   st['texts'] = [ {text, on, box, rot, pt} ]
#
#   - nothing saved = every sheet exactly as before;
#   - the words are laid in lines that fit the WIDTH of the box, at the size
#     in points; the HEIGHT is however many lines that took, and the top left
#     corner of the box stays where it was;
#   - they go on the sheet as plain text shapes, one a line, turned about the
#     middle of the box - so the PDF prints them with the code it already had;
#   - the window is told the box (Page#text_boxes) and lays the same lines by
#     the same sums: THE NUMBERS IN SECTION 2 ARE THE NUMBERS IN t75;
#   - every box is held on the sheet, whatever was saved;
#   - throwing a picture sheet away takes its writing with it.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
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

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt275_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

def build_doc
  doc = PD::Document.new('t')
  cv  = doc.canvas('MODEL')
  cv.layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  doc
end
def state(extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
    'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => [], 'images' => [] }.merge(extra)
end
def laid(st)
  d = build_doc
  PC.layout_pages!(d, st)
  d
end
def plan(doc); doc.pages.find { |pg| pg.kind == 'plan' }; end
def sheet_of(doc, i); doc.pages.find { |pg| pg.kind == 'image' && pg.ref == i }; end
def words(pg); l = pg.layers.find { |x| x.name == PC::TEXT_LAYER }; l ? l.shapes.select { |s| s[:type] == :text } : []; end
def boxes(pg); Array(pg.text_boxes); end
def rect(e); [e[:x], e[:y], e[:w], e[:h]]; end
AREA = [0.75, 1.85, 34.5, 21.4].freeze
def hull(e)
  r = e[:rot].to_f * Math::PI / 180.0
  hw = (e[:w] * Math.cos(r).abs + e[:h] * Math.sin(r).abs) / 2.0
  hh = (e[:w] * Math.sin(r).abs + e[:h] * Math.cos(r).abs) / 2.0
  cx = e[:x] + e[:w] / 2.0
  cy = e[:y] + e[:h] / 2.0
  [cx - hw, cy - hh, cx + hw, cy + hh]
end
def on_sheet?(e)
  a = hull(e)
  a[0] >= AREA[0] - 1e-9 && a[1] >= AREA[1] - 1e-9 && a[2] <= AREA[0] + AREA[2] + 1e-9 && a[3] <= AREA[1] + AREA[3] + 1e-9
end
# the top left corner of a box as it is turned, on the paper
def top_left(e)
  r = e[:rot].to_f * Math::PI / 180.0
  c = Math.cos(r); s = Math.sin(r)
  cx = e[:x] + e[:w] / 2.0
  cy = e[:y] + e[:h] / 2.0
  [cx + (-e[:w] / 2.0) * c - (e[:h] / 2.0) * s, cy + (-e[:w] / 2.0) * s + (e[:h] / 2.0) * c]
end

ok('there is a switch, and it is on', PC.const_defined?(:USE_TEXT_BOX, false) && PC::USE_TEXT_BOX == true)
ok("the settings know about it, so it is not thrown away on the way to the model  <<< the 'images' trap of 2026-08-14",
   PSD.default_state.key?('texts') && PSD.default_state['texts'] == [])

# ---------------------------------------------------------------------------
# 1. nothing saved: every sheet exactly as before
# ---------------------------------------------------------------------------
d0 = laid(state)
ok('NOTHING SAVED: no sheet has a layer of writing, and no box', d0.pages.all? { |pg| words(pg).empty? && boxes(pg).empty? && pg.layers.none? { |l| l.name == PC::TEXT_LAYER } })
ok('an empty list is the same as nothing', laid(state('texts' => [])).pages.all? { |pg| pg.layers.none? { |l| l.name == PC::TEXT_LAYER } })
ok('the window is always told: an empty list, not nil', d0.pages.all? { |pg| pg.to_h[:text_boxes] == [] })

# ---------------------------------------------------------------------------
# 2. the sums - THE SAME NUMBERS t75 HOLDS THE WINDOW TO
# ---------------------------------------------------------------------------
# Helvetica: 'Pool' = 667 + 556 + 556 + 222 = 2001; a space = 278; 'deck' = 556 + 556 + 500 + 500 = 2112
ok("'Pool' at 72 points is 2.001 inches wide - plan_pdf's own widths", near(PC.text_width_in('Pool', 72), 2.001), PC.text_width_in('Pool', 72))
ok("'Pool deck' at 36 points is 2.1955", near(PC.text_width_in('Pool deck', 36), (2001 + 278 + 2112) / 1000.0 * 0.5), PC.text_width_in('Pool deck', 36))
ok('the words fit: one line', PC.text_wrap('Pool deck', 2.3, 36) == ['Pool deck'])
ok('a hair too narrow: two lines', PC.text_wrap('Pool deck', 2.19, 36) == %w[Pool deck])
ok('exactly as wide as the words is wide enough', PC.text_wrap('Pool deck', 2.1955, 36) == ['Pool deck'])
ok('a line he broke himself stays broken, and an empty line stays a line',
   PC.text_wrap("A\n\nB C", 100, 12) == ['A', '', 'B C'], PC.text_wrap("A\n\nB C", 100, 12))
ok('a word wider than the box stays whole', PC.text_wrap('Supercalifragilistic pool', 0.5, 36) == %w[Supercalifragilistic pool])
ok('runs of spaces, tabs and Windows line ends are tidied', PC.text_wrap("A   B\tC\r\nD", 100, 12) == ['A B C', 'D'], PC.text_wrap("A   B\tC\r\nD", 100, 12))
ok('one line at 72 points is 1.5 inches tall, two are 2.75', near(PC.text_height(1, 72), 1.5) && near(PC.text_height(2, 72), 2.75), [PC.text_height(1, 72), PC.text_height(2, 72)])
ok("'Pool deck' at 36 points needs a box 2.4455 wide", near(PC.text_natural_width('Pool deck', 36), 2.1955 + 0.25), PC.text_natural_width('Pool deck', 36))

T1 = { 'text' => 'Pool deck', 'on' => 'plan', 'box' => [10.0, 8.0, 3.0, 0.75], 'rot' => 0, 'pt' => 36 }.freeze
d1 = laid(state('texts' => [T1]))
b1 = boxes(plan(d1))
w1 = words(plan(d1))
ok('ONE BOX OF WRITING ON THE PLAN SHEET: the window is told its box', b1.length == 1 && near4(rect(b1[0]), [10.0, 8.0, 3.0, 0.75]) && b1[0][:pic] == 't:0' && b1[0][:txt] == true && b1[0][:pt] == 36.0 && b1[0][:rot] == 0.0 && b1[0][:lines] == ['Pool deck'] && b1[0][:text] == 'Pool deck', b1)
ok('the words are ONE plain text shape on the TEXT layer of the sheet  <<< the PDF needs nothing new',
   w1.length == 1 && w1[0][:type] == :text && w1[0][:text] == 'Pool deck' && w1[0][:align] == :left && w1[0][:tbox] == 't:0', w1)
# pad = 0.125; the baseline is 0.125 + 0.8 * 0.5 = 0.525 under the top (8.75)
ok('hung from the left end of its baseline: x = 10.125, y = 8.225', near(w1[0][:x], 10.125) && near(w1[0][:y], 8.225), [w1[0][:x], w1[0][:y]])
ok('36 points tall: the height the PDF and the window both turn back into 36 points', near(w1[0][:h] / PP::CAP_RATIO * 72.0, 36.0), w1[0][:h])
ok('it is not one of the labels that are picked one at a time: no key', w1.none? { |s| s.key?(:key) })

# narrower: two lines, and the box is as tall as two lines - its TOP stays put
d2 = laid(state('texts' => [T1.merge('box' => [10.0, 8.0, 2.0, 0.75])]))
b2 = boxes(plan(d2))[0]
w2 = words(plan(d2))
ok('NARROWER THAN ITS WORDS: two lines', b2[:lines] == %w[Pool deck] && w2.map { |s| s[:text] } == %w[Pool deck])
ok('THE BOX IS AS TALL AS ITS LINES, AND ITS TOP STAYS WHERE IT WAS  <<< THE RULE', near4(rect(b2), [10.0, 8.75 - 1.375, 2.0, 1.375]), rect(b2))
ok('the second line is one line lower: 0.625', near(w2[0][:y], 8.225) && near(w2[1][:y], 8.225 - 0.625) && near(w2[1][:x], 10.125), w2.map { |s| [s[:x], s[:y]] })

# turned a quarter turn about its middle
d3 = laid(state('texts' => [T1.merge('rot' => 90)]))
b3 = boxes(plan(d3))[0]
w3 = words(plan(d3))
ok('TURNED: the box is where it was, the angle is told', near4(rect(b3), [10.0, 8.0, 3.0, 0.75]) && b3[:rot] == 90.0, b3)
# local (-1.375, -0.15) turned 90 = (0.15, -1.375) from the middle (11.5, 8.375)
ok('the line is turned about the MIDDLE of the box and carries the angle', near(w3[0][:x], 11.65) && near(w3[0][:y], 7.0) && w3[0][:rotation] == 90.0, w3[0])
d3b = laid(state('texts' => [T1.merge('rot' => 30, 'box' => [10.0, 8.0, 2.0, 0.75])]))
b3b = boxes(plan(d3b))[0]
ok('turned AND laid again taller: the top left corner as it is turned stays put',
   near4(top_left(b3b), top_left(x: 10.0, y: 8.0, w: 2.0, h: 0.75, rot: 30.0), 1e-9), [top_left(b3b), top_left(x: 10.0, y: 8.0, w: 2.0, h: 0.75, rot: 30.0)])

# twice the size and twice the width: the same lines, twice as big - a corner of the box
d4 = laid(state('texts' => [T1.merge('box' => [10.0, 8.0, 4.0, 2.75], 'pt' => 72)]))
b4 = boxes(plan(d4))[0]
ok('A CORNER: twice the letters and twice the width breaks the lines in the same places', b4[:lines] == %w[Pool deck] && near4(rect(b4), [10.0, 8.0, 4.0, 2.75]), b4)

# ---------------------------------------------------------------------------
# 3. what is refused, and what is put right
# ---------------------------------------------------------------------------
ok('no words, or only spaces: nothing is drawn', boxes(plan(laid(state('texts' => [T1.merge('text' => "  \n ")])))).empty?)
junk = [nil, 7, 'x', { 'text' => 'A', 'on' => 'nowhere' }, T1.merge('box' => ['a', 1, 2, 3]), T1.merge('pt' => 'big'), T1.merge('pt' => 100_000), T1.merge('pt' => -3), T1.merge('rot' => Float::NAN)]
dj = laid(state('texts' => junk))
bj = boxes(plan(dj))
ok('RUBBISH IN THE LIST BLOWS NOTHING UP, and every box that is drawn is on the sheet', bj.all? { |e| on_sheet?(e) } && bj.length == 5, bj.map { |e| [e[:pic], rect(e), e[:pt]] })
ok('each keeps its place in the list as its name, so the window and Ruby mean the same one', bj.map { |e| e[:pic] } == %w[t:4 t:5 t:6 t:7 t:8], bj.map { |e| e[:pic] })
ok('no place saved: it is put in the middle of the sheet, as wide as its words', near(bj[0][:w], PC.text_natural_width('Pool deck', 36)) && near(bj[0][:x] + bj[0][:w] / 2.0, AREA[0] + AREA[2] / 2.0, 1e-9), rect(bj[0]))
ok('a size that is not a number is the size a new one starts at; a silly one is held', bj[1][:pt] == PC::TEXT_PT && bj[2][:pt] <= PC::TEXT_PT_MAX && bj[3][:pt] == PC::TEXT_PT, bj.map { |e| e[:pt] })
off = boxes(plan(laid(state('texts' => [T1.merge('box' => [40.0, -5.0, 3.0, 0.75])]))))[0]
ok('A BOX HANGING OFF THE SHEET IS PUSHED BACK IN', on_sheet?(off) && near(off[:w], 3.0) && off[:pt] == 36.0, rect(off))
big = boxes(plan(laid(state('texts' => [T1.merge('box' => [1.0, 1.0, 69.0, 0.75], 'pt' => 72)]))))[0]
ok('A BOX WIDER THAN THE SHEET IS MADE SMALLER, AND ITS LETTERS WITH IT', on_sheet?(big) && near(big[:w], 34.5) && near(big[:pt], 36.0) && big[:lines] == ['Pool deck'], [rect(big), big[:pt]])
small = boxes(plan(laid(state('texts' => [T1.merge('box' => [10.0, 8.0, 1.0, 0.2], 'pt' => 8)]))))[0]
ok('one line of small writing is under half an inch tall and STAYS that tall (a picture would be made half an inch)', near(small[:h], PC.text_height(1, 8)) && small[:h] < 0.5, small[:h])
again = boxes(plan(laid(state('texts' => [T1.merge('box' => rect(small), 'pt' => 8)]))))[0]
ok('LAID OUT AGAIN FROM ITS OWN ANSWER IT DOES NOT MOVE  <<< or it would creep down the sheet on every click', near4(rect(again), rect(small), 1e-12), [rect(again), rect(small)])

# ---------------------------------------------------------------------------
# 4. any sheet, several to a sheet, the switch, the layer
# ---------------------------------------------------------------------------
JPG = File.join(TMP, 'r.jpg').tr('\\', '/')
File.binwrite(JPG, "\xFF\xD8".b + "\xFF\xC0".b + [17].pack('n') + [8, 1000, 2000, 3].pack('CnnC') + ("\x01\x11\x00".b * 3) + "\xFF\xD9".b)
many = state('images' => [JPG, JPG], 'texts' => [
  T1, T1.merge('text' => 'Second', 'box' => [20.0, 12.0, 4.0, 0.75]),
  T1.merge('text' => 'On the render', 'on' => 'image:1', 'box' => [5.0, 5.0, 6.0, 0.75]),
  T1.merge('text' => 'On the schedules', 'on' => 'schedules')])
dm = laid(many)
ok('TWO ON THE PLAN SHEET, one on the second picture sheet, none on the first', boxes(plan(dm)).map { |e| e[:pic] } == %w[t:0 t:1] && boxes(sheet_of(dm, 1)).map { |e| e[:pic] } == %w[t:2] && boxes(sheet_of(dm, 0)).empty?, dm.pages.map { |pg| [pg.kind, pg.ref, boxes(pg).map { |e| e[:pic] }] })
ok('the writing is drawn OVER the picture: its layer comes after the pictures', sheet_of(dm, 1).layers.map(&:name).index(PC::TEXT_LAYER) > sheet_of(dm, 1).layers.map(&:name).index(PD::IMAGE_LAYER), sheet_of(dm, 1).layers.map(&:name))
dh = laid(many.merge('hidden' => [PC::TEXT_LAYER]))
ok('the TEXT layer switched off: the writing is not printed', plan(dh).layers.find { |l| l.name == PC::TEXT_LAYER }.visible == false)

begin
  PC.send(:remove_const, :USE_TEXT_BOX)
  PC.const_set(:USE_TEXT_BOX, false)
  dx = laid(many)
  ok('SWITCHED OFF: the list is ignored, no sheet carries any', dx.pages.all? { |pg| words(pg).empty? && boxes(pg).empty? })
ensure
  PC.send(:remove_const, :USE_TEXT_BOX)
  PC.const_set(:USE_TEXT_BOX, true)
end

# ---------------------------------------------------------------------------
# 5. the PDF prints it with the code it already had
# ---------------------------------------------------------------------------
pdf = File.join(TMP, 'out.pdf')
dp = laid(state('texts' => [T1, T1.merge('text' => "Turned\nwriting", 'rot' => 30, 'box' => [20.0, 12.0, 4.0, 1.375])]))
PP.export(dp, pdf, pages: [plan(dp)])
raw = File.binread(pdf)
ok('THE WORDS ARE IN THE PDF, at 36 points, at 10.125 by 8.225 inches', raw.include?("/F1 36.000 Tf\n1 0 0 1 729.000 592.200 Tm\n(Pool deck) Tj"), raw[/\/F1 36[^)]*\)/])
c30 = format('%.3f', Math.cos(30 * Math::PI / 180)); s30 = format('%.3f', Math.sin(30 * Math::PI / 180))
ok('the turned box is printed turned: both its lines carry the angle', raw.scan(/#{c30} #{s30} -#{s30} #{c30} [\d.]+ [\d.]+ Tm\n\((Turned|writing)\) Tj/).flatten == %w[Turned writing], raw.scan(/Tm\n\([A-Za-z]+\) Tj/))
heb = PP.esc('קירות פנים')
ok('KNOWN LIMIT, pinned so nobody is surprised: the PDF has three Latin fonts and no Hebrew letters - they print as blanks', heb.strip.empty?, heb)

# ---------------------------------------------------------------------------
# 6. the sheet window's own roads
# ---------------------------------------------------------------------------
st = PSD.default_state.merge('images' => %w[a.jpg b.jpg c.jpg], 'texts' => [
  { 'text' => 'plan', 'on' => 'plan' }, { 'text' => 'zero', 'on' => 'image:0' },
  { 'text' => 'one', 'on' => 'image:1' }, { 'text' => 'two', 'on' => 'image:2' }])
PSD.shift_pics!(st, 1)
ok('A PICTURE SHEET THROWN AWAY TAKES ITS WRITING WITH IT, and the sheets after it move down one',
   st['texts'].map { |t| [t['text'], t['on']] } == [%w[plan plan], %w[zero image:0], %w[two image:1]], st['texts'])
rules = PC.text_rules
ok('the window is sent the rules and the letter widths - it lays the lines by Ruby\'s own numbers',
   rules['pad'] == PC::TEXT_PAD && rules['lead'] == PC::TEXT_LEAD && rules['ascent'] == PC::TEXT_ASCENT && rules['pt'] == PC::TEXT_PT && rules['w'].length == 95 && rules['cap'] == PP::CAP_RATIO, rules.reject { |k, _| k == 'w' })
src = File.read('plan_sheet_dialog.rb', encoding: 'UTF-8')
ok('and they go with every sheet', src.include?('text_rules: text_rules_for_window') && src =~ /def text_rules_for_window.{0,200}InteriorPro::PlanCanvas\.text_rules/m && src.include?('text_box: InteriorPro::PlanCanvas::USE_TEXT_BOX && InteriorPro::PlanCanvas::USE_PIC_BOX'))

# the trace: one line a change, read instead of asking him
trace = File.join(PSD.plugin_dir, 'sheet_erase_trace.txt')
kept  = File.file?(trace) ? File.binread(trace) : nil
begin
  File.delete(trace) if File.file?(trace)
  PSD.instance_variable_set(:@doc, laid(state('texts' => [T1])))
  PSD.text_seen!(state('texts' => []))
  PSD.text_trace(state('texts' => [T1]), Time.now)
  PSD.text_trace(state('texts' => [T1]), Time.now)                       # nothing changed: no line
  PSD.instance_variable_set(:@doc, laid(state('texts' => [T1.merge('pt' => 48)])))
  PSD.text_trace(state('texts' => [T1.merge('pt' => 48)]), Time.now)
  PSD.instance_variable_set(:@doc, laid(state('texts' => [])))
  PSD.text_trace(state('texts' => []), Time.now)
  got = File.file?(trace) ? File.read(trace, encoding: 'UTF-8').lines.map(&:strip) : []
  ok('EVERY CHANGE TO THE WRITING LEAVES ONE LINE IN sheet_erase_trace.txt: added, changed, taken off',
     got.length == 3 && got[0] =~ /text box: 1 added, laid at \[10\.00, 8\.00, 3\.00, 0\.75\] 36\.0 pt turned 0\.0, 1 lines; 1 saved, 1 on the sheets, \d+ ms/ &&
     got[1] =~ /text box: one changed \(size\), laid at .* 48\.0 pt/ && got[2] =~ /text box: 1 taken off; 0 saved, 0 on the sheets/, got)
ensure
  PSD.instance_variable_set(:@doc, nil)
  File.delete(trace) if File.file?(trace)
  File.binwrite(trace, kept) if kept
end

# ---------------------------------------------------------------------------
# lettered: bold, italic, underlined, a colour - set at the side of the sheet
# window, on the box he picked or is typing in (2026-10-07)
# ---------------------------------------------------------------------------
PP = InteriorPro::PlanPDF unless defined?(PP)
ok('there is a switch for it, and it is on', PC.const_defined?(:USE_TEXT_STYLE, false) && PC::USE_TEXT_STYLE == true)
ok('text_style keeps only what is set: true is true, anything else is not, black is no colour',
   PC.text_style('bold' => true, 'italic' => false, 'underline' => 'yes', 'color' => '#000000') == { bold: true } &&
   PC.text_style('color' => '#C0392B') == { color: '#c0392b' } && PC.text_style('color' => 'red') == {} && PC.text_style(nil) == {},
   [PC.text_style('bold' => true, 'italic' => false, 'underline' => 'yes', 'color' => '#000000'), PC.text_style('color' => '#C0392B')])
ok("bold letters are wider by plan_pdf's own amount - THE SAME NUMBER t78 HOLDS THE WINDOW TO",
   near(PC.text_width_in('Pool', 72, true), 2.001 * 1.06) && PP::BOLD_BUMP == 1.06 && PC.text_rules['bold'] == PP::BOLD_BUMP, [PC.text_width_in('Pool', 72, true), PC.text_rules['bold']])
ok('so a width that holds the plain words breaks the bold ones',
   PC.text_wrap('Pool deck', 2.1955, 36) == ['Pool deck'] && PC.text_wrap('Pool deck', 2.1955, 36, true) == %w[Pool deck])
ds = laid(state('texts' => [T1.merge('bold' => true, 'underline' => true, 'color' => '#C0392B')]))
ws = words(plan(ds))
bs = boxes(plan(ds))[0]
ok('THE LINES ON THE SHEET CARRY IT - plan_pdf and the window draw from these',
   !ws.empty? && ws.all? { |q| q[:bold] == true && q[:underline] == true && q[:color] == '#c0392b' && !q.key?(:italic) }, ws)
ok('and so does the box the window is told of', bs && bs[:bold] == true && bs[:underline] == true && bs[:color] == '#c0392b' && !bs.key?(:italic), bs)
plain = words(plan(laid(state('texts' => [T1]))))
ok('nothing set: not one key more than before', !plain.empty? && plain.all? { |q| !q.key?(:bold) && !q.key?(:italic) && !q.key?(:underline) && !q.key?(:color) }, plain)
begin
  require 'stringio'
  out = File.join(TMP, 'style.pdf')
  PP.export(ds, out, pages: [plan(ds)])
  raw = File.binread(out)
  body = raw.scan(/stream\r?\n(.*?)endstream/m).map { |mm| (Zlib::Inflate.inflate(mm[0]) rescue mm[0]) }.join("\n")
  ok('THE PDF PRINTS IT: the bold font, the colour, and a line under the words',
     body =~ %r{0\.753 0\.224 0\.169 rg\s+/F2 [\d.]+ Tf[^E]*\(Pool deck\) Tj}m && body =~ /0\.753 0\.224 0\.169 RG/, body[/BT[^E]*\(Pool deck\) Tj.{0,200}/m])
rescue StandardError => e
  ok('THE PDF PRINTS IT', false, "#{e.class}: #{e.message}")
end
src = File.read(File.join(File.dirname(File.expand_path(__FILE__)), 'plan_sheet_dialog.rb'), encoding: 'UTF-8')
ok('the window is told the switch, and the trace names a change of lettering', src.include?('text_style: InteriorPro::PlanCanvas::USE_TEXT_STYLE') && src.include?("kinds << 'style'"))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

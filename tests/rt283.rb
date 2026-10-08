# encoding: utf-8
# rt283 - a note's box follows its words (2026-10-08).
#
# The user: "כל הכיתוב בתוכנה יהיה תחת אותם הגדרות" - a note's words are a
# label like any other and take a size (in points, kept as a percentage),
# bold, and a lettering from the panel at the side. The box around them and
# the leader out of it were drawn with the marks, before any of that: a note
# made bigger spilled out of its box. Now PlanCanvas.fit_notes! draws the box
# and the leader again around the words as they finally are (USE_NOTE_FIT).
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'tmpdir'
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
require './plan_canvas'
require './plan_pdf'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PC = InteriorPro::PlanCanvas
PP = InteriorPro::PlanPDF

ok('the switch is there and on', PC.const_defined?(:USE_NOTE_FIT) && PC::USE_NOTE_FIT == true)

Sketchup.reset_model!
mo = Sketchup.active_model
[[0, 0, 240, 0], [240, 0, 240, 180], [240, 180, 0, 180], [0, 180, 0, 0]]
  .each_with_index do |(a, b, c, d), i|
  g = mo.entities.add_group
  { 'type' => 'wall', 'id' => "w#{i}", 'start_x' => a, 'start_y' => b,
    'end_x' => c, 'end_y' => d, 'thickness' => 5.0, 'anchor' => 'bottom-left',
    'wall_category' => 'exterior' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
end

NOTE = { 't' => 'note', 'x' => 120, 'y' => 90, 'kx' => 60, 'ky' => 90, 'lx' => 20, 'ly' => 40,
         'text' => 'LIVING', 'arrow' => true }
def marks_of(doc)
  cv = doc.canvas('MODEL')
  cv.layer?(PC::MARK_LAYER) ? cv.layer(PC::MARK_LAYER).shapes : []
end
def words(doc);  marks_of(doc).find { |s| s[:type] == :text && s[:text] == 'LIVING' }; end
def box(doc);    marks_of(doc).find { |s| s[:type] == :polygon }; end
def lines(doc);  marks_of(doc).select { |s| s[:type] == :line }; end
def box_w(doc);  pts = box(doc)[:points]; pts.map { |p| p[0] }.max - pts.map { |p| p[0] }.min; end
def box_h(doc);  pts = box(doc)[:points]; pts.map { |p| p[1] }.max - pts.map { |p| p[1] }.min; end
def state(extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
    'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN', 'hidden' => [],
    'tables_own_page' => true, 'images' => [], 'marks' => [NOTE],
    'text_scale' => { 'dims' => 100, 'rooms' => 100, 'tags' => 100, 'tables' => 100 },
    'text_marks' => {} }.merge(extra)
end

doc = PC.build_document(mo, size: 'ARCH D', scale: '1/4"', marks: [NOTE])
PC.layout_pages!(doc, state)
ok('the note is drawn: words, one box, a leader of two lines and a head of two', !!words(doc) && !!box(doc) && lines(doc).length == 4, [!!words(doc), !!box(doc), lines(doc).length])
w1 = box_w(doc); h1 = box_h(doc); n1 = marks_of(doc).length
key = words(doc)[:key]
ok('the words carry a key like any label', key.to_s.start_with?('NOTES|LIVING|'), key)
ok('and the words and every shape of the frame carry the note\'s number',
   marks_of(doc).all? { |s| s[:note] == 0 }, marks_of(doc).map { |s| [s[:type], s[:note]] })
first = marks_of(doc).map { |s| s.dup }
PC.layout_pages!(doc, state)
ok('with nothing done to the words, a second pass leaves the frame exactly as drawn with the marks (nothing redrawn)',
   marks_of(doc).map { |s| s.dup } == first)

# --- twice the size, from the panel (text_marks pct, the label's road)
PC.layout_pages!(doc, state('text_marks' => { key => { 'pct' => 200 } }))
ok('the words are twice as tall', (words(doc)[:h] - 2 * words(doc)[:h0]).abs < 1e-9, [words(doc)[:h], words(doc)[:h0]])
ok('THE BOX FOLLOWS THEM: twice as tall...', (box_h(doc) - 2 * h1).abs < 1e-6, [box_h(doc), h1])
ok('...and twice as wide', (box_w(doc) - 2 * w1).abs < 1e-6, [box_w(doc), w1])
ok('still one box, still the whole leader', marks_of(doc).count { |s| s[:type] == :polygon } == 1 && lines(doc).length == 4, marks_of(doc).map { |s| s[:type] })
ok('the leader leaves the BIGGER box, so it does not cross the words',
   (function = lambda do
     sh = lines(doc).find { |l| (l[:x2] - 60).abs < 1e-6 && (l[:y2] - 90).abs < 1e-6 }   # the shoulder ends at the knee
     sh && (sh[:x1] - (120 - box_w(doc) / 2)).abs < 1e-6
   end).call, lines(doc))
ok('the words themselves were not moved', (words(doc)[:x] - 120).abs < 1e-9 && (words(doc)[:y] - 90).abs < 1e-9)
ok('the arrow head grew with the words too',
   (lambda do
     heads = lines(doc).select { |l| (l[:x1] - 20).abs < 1e-6 && (l[:y1] - 40).abs < 1e-6 }
     heads.length == 2 && heads.all? { |l| (Math.hypot(l[:x2] - l[:x1], l[:y2] - l[:y1]) - (words(doc)[:h] * PC::MARK_ARROW * Math.hypot(1, 0.38))).abs < 1e-6 }
   end).call, lines(doc))

# --- back to normal: the frame is the first one again, to the number
PC.layout_pages!(doc, state)
ok('back at 100% the frame is the first one again', (box_w(doc) - w1).abs < 1e-9 && (box_h(doc) - h1).abs < 1e-9 && marks_of(doc).length == n1)

# --- bold: wider words, wider box, same height
PC.layout_pages!(doc, state('text_marks' => { key => { 'bold' => true } }))
ok('bold words get a wider box', box_w(doc) > w1 * 1.02 && (box_h(doc) - h1).abs < 1e-9, [box_w(doc), w1, box_h(doc), h1])
ok('as wide as plan_pdf measures them in bold',
   (box_w(doc) - (PP.text_width('LIVING', words(doc)[:h] / PP::CAP_RATIO, true) + 2 * words(doc)[:h] * PC::MARK_PAD)).abs < 1e-6)

# --- a lettering of its own (a folder of the test's own, with DejaVu Sans as if it shipped - as rt282 does)
FDIR = File.join(Dir.tmpdir, 'rt283_FONTS')
FileUtils.mkdir_p(FDIR)
Dir.glob('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').each { |f| FileUtils.cp(f, FDIR) }
PP.font_dir = FDIR if PP.respond_to?(:font_dir=)
PP.forget_fonts! if PP.respond_to?(:forget_fonts!)
fam = (PP.families_present.first rescue nil)
if fam && PC::USE_TEXT_FONT
  PC.layout_pages!(doc, state('text_marks' => { key => { 'font' => fam } }))
  want = PP.text_width('LIVING', words(doc)[:h] / PP::CAP_RATIO, false, fam) + 2 * words(doc)[:h] * PC::MARK_PAD
  ok("in #{fam} the box is as wide as the words measure in it", (box_w(doc) - want).abs < 1e-6, [box_w(doc), want])
else
  puts '(no shipped font found - the lettering case is not run)'
end

# --- the group size (the dims group) moves the words too, and the box with them
PC.layout_pages!(doc, state('text_scale' => { 'dims' => 150, 'rooms' => 100, 'tags' => 100, 'tables' => 100 }))
if (words(doc)[:h] - 1.5 * words(doc)[:h0]).abs < 1e-9
  ok('the group size: the box follows as well', (box_h(doc) - 1.5 * h1).abs < 1e-6 && (box_w(doc) - 1.5 * w1).abs < 1e-6, [box_h(doc), h1])
else
  puts '(the NOTES layer is not in the dims group - the group case does not apply)'
end

# --- the PDF draws the bigger box (it only draws the shapes it is given)
PC.layout_pages!(doc, state('text_marks' => { key => { 'pct' => 200 } }))
out = File.join(Dir.tmpdir, 'rt283.pdf')
File.delete(out) if File.exist?(out)
PP.export(doc, out)
ok('and it all goes to paper', File.exist?(out) && File.size(out) > 1000)

# --- switched off
InteriorPro::PlanCanvas.send(:remove_const, :USE_NOTE_FIT)
InteriorPro::PlanCanvas.const_set(:USE_NOTE_FIT, false)
PC.layout_pages!(doc, state('text_marks' => { key => { 'pct' => 200 } }))
ok('SWITCHED OFF: the words are still twice as tall...', (words(doc)[:h] - 2 * words(doc)[:h0]).abs < 1e-9)
ok('...but the box is the one drawn with the marks, at the built size, as before', (box_w(doc) - w1).abs < 1e-9 && (box_h(doc) - h1).abs < 1e-9, [box_w(doc), w1])
InteriorPro::PlanCanvas.send(:remove_const, :USE_NOTE_FIT)
InteriorPro::PlanCanvas.const_set(:USE_NOTE_FIT, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

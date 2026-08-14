# encoding: utf-8
# rt52 - dimensions and notes drawn by hand (2026-08-14).
#
# The plan dimensions itself. This is the other half the user asked for: a line
# he stretches between two points he chose, and a word written where he wants
# it. Without them the free geometry he traces is only a picture.
#
# The decision this suite pins: a hand-drawn mark lives in MODEL inches on the
# canvas, NOT on the paper. Put it on the paper and it would slide off the wall
# it measures the moment he changes the scale, the page size, or drags the plan
# an inch to the left. On the canvas it stays where he put it, and the number
# it prints is the real distance in the house.
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
require './plan_canvas'
require './plan_pdf'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PD = InteriorPro::PlanDoc
PC = InteriorPro::PlanCanvas
PP = InteriorPro::PlanPDF

def notes_of(doc)
  cv = doc.canvas('MODEL')
  cv.layer?(PC::MARK_LAYER) ? cv.layer(PC::MARK_LAYER).shapes : []
end

def texts_of(doc)
  notes_of(doc).select { |s| s[:type] == :text }
end

# --------------------------------------------------------------- one dimension
doc = PD::Document.new('t')
PC.apply_marks!(doc, 'marks' => [{ 't' => 'dim', 'x1' => 0, 'y1' => 0,
                                   'x2' => 120, 'y2' => 0 }])
s = notes_of(doc)
ok('a dimension reaches the drawing', !s.empty?)
ok('it is on the plan, not on the paper',
   doc.canvas('MODEL').layer?(PC::MARK_LAYER) &&
   doc.pages.empty?, 'it went onto a page')
ok('it draws a line and a tick at each end',
   s.count { |x| x[:type] == :line } == 3, s.map { |x| x[:type] })
ok('and writes what it measured, in feet and inches',
   texts_of(doc).map { |t| t[:text] } == ["10'-0\""], texts_of(doc).map { |t| t[:text] })
ok('the number sits in the middle of the line',
   (texts_of(doc)[0][:x] - 60.0).abs < 0.01, texts_of(doc)[0][:x])
ok('and just off it, not on top of it',
   texts_of(doc)[0][:y].abs > 0.5, texts_of(doc)[0][:y])
ok('the number is centred on its point, like every other label on the plan',
   texts_of(doc)[0][:align] == :center, texts_of(doc)[0][:align])
# Not PlanGenerator::DIM_TEXT_H - it is declared inside `class << self`, so it
# lives on the singleton class and the obvious spelling raises. plan_canvas had
# that exact mistake, hidden behind a rescue that returned the same number.
DIM_H = InteriorPro::PlanGenerator.singleton_class.const_get(:DIM_TEXT_H)
ok('it is the same size as the dimensions the plan draws itself',
   (texts_of(doc)[0][:h] - DIM_H).abs < 0.01, texts_of(doc)[0][:h])
ok('and it is really read from there, not a copy that can drift',
   PC.mark_text_h == DIM_H, [PC.mark_text_h, DIM_H])

# --------------------------------------------------- odd lengths and odd angles
def one_dim(x1, y1, x2, y2)
  d = PD::Document.new('t')
  PC.apply_marks!(d, 'marks' => [{ 't' => 'dim', 'x1' => x1, 'y1' => y1,
                                   'x2' => x2, 'y2' => y2 }])
  d
end

ok('a part-inch length is written the way a builder reads it',
   texts_of(one_dim(0, 0, 0, 137.5)).first[:text] == "11'-5.5\"",
   texts_of(one_dim(0, 0, 0, 137.5)).first[:text])
ok('under a foot it drops the feet',
   texts_of(one_dim(0, 0, 7, 0)).first[:text] == '7"',
   texts_of(one_dim(0, 0, 7, 0)).first[:text])
ok('a diagonal measures the diagonal, not the sides',
   texts_of(one_dim(0, 0, 36, 48)).first[:text] == "5'-0\"",
   texts_of(one_dim(0, 0, 36, 48)).first[:text])

# Text upside down is unreadable. Past vertical it must be read from the
# other side, exactly like the automatic dimensions do it.
[[0, 0, -120, 0], [0, 0, -100, -100], [0, 0, 0, -120]].each do |x1, y1, x2, y2|
  r = texts_of(one_dim(x1, y1, x2, y2)).first[:rotation]
  ok("a line drawn back towards #{x2},#{y2} still reads the right way up",
     r >= -90.01 && r <= 90.01, r)
end

ok('a double click in the same place makes nothing at all',
   notes_of(one_dim(10, 10, 10, 10)).empty?,
   notes_of(one_dim(10, 10, 10, 10)).length)

# --------------------------------------------------------------------- a note
doc2 = PD::Document.new('t')
PC.apply_marks!(doc2, 'marks' => [{ 't' => 'note', 'x' => 50, 'y' => 60,
                                    'text' => 'NEW BEAM ABOVE' }])
ok('a note reaches the drawing', texts_of(doc2).length == 1)
ok('with the words the user typed',
   texts_of(doc2)[0][:text] == 'NEW BEAM ABOVE', texts_of(doc2)[0][:text])
ok('exactly where he clicked',
   texts_of(doc2)[0][:x] == 50.0 && texts_of(doc2)[0][:y] == 60.0)

PC.apply_marks!(doc2, 'marks' => [{ 't' => 'note', 'x' => 1, 'y' => 1, 'text' => '   ' }])
ok('an empty note is not written at all', notes_of(doc2).empty?)

# ------------------------------------------------- a note with a leader
# The user sent a picture of SketchUp's Text tool - "insert text or add
# leader-based details" - instead of describing it, which is the right way
# round for anything that has to LOOK like something. Words in a box, a line
# from the box to the thing, an arrow on the end.
doc5 = PD::Document.new('t')
PC.apply_marks!(doc5, 'marks' => [{ 't' => 'note', 'x' => 100, 'y' => 100,
                                    'lx' => 40, 'ly' => 40,
                                    'text' => 'NEW BEAM' }])
sh = notes_of(doc5)
ok('a note with a leader draws words, a box, a line and an arrow',
   sh.count { |s2| s2[:type] == :text } == 1 &&
   sh.count { |s2| s2[:type] == :polygon } == 1 &&
   sh.count { |s2| s2[:type] == :line } == 3,
   sh.map { |s2| s2[:type] })

box = sh.find { |s2| s2[:type] == :polygon }[:points]
bx = box.map { |p| p[0] }
by = box.map { |p| p[1] }
ok('the box is around the words, not beside them',
   bx.min < 100 && bx.max > 100 && by.min < 100 && by.max > 100, box)
ok('the box is wider than it is tall, like a line of text',
   (bx.max - bx.min) > (by.max - by.min), [bx.max - bx.min, by.max - by.min])

wide = PD::Document.new('t')
PC.apply_marks!(wide, 'marks' => [{ 't' => 'note', 'x' => 0, 'y' => 0,
                                    'text' => 'A MUCH LONGER NOTE THAN THAT ONE' }])
w2 = notes_of(wide).find { |s2| s2[:type] == :polygon }[:points].map { |p| p[0] }
ok('a longer note gets a wider box - the letters are measured, not counted',
   (w2.max - w2.min) > (bx.max - bx.min), [w2.max - w2.min, bx.max - bx.min])

lead = sh.select { |s2| s2[:type] == :line }
         .find { |s2| (s2[:x2] - 40.0).abs < 0.01 && (s2[:y2] - 40.0).abs < 0.01 }
ok('the leader ends exactly on the thing it points at', !lead.nil?,
   sh.select { |s2| s2[:type] == :line }.map { |s2| [s2[:x1], s2[:y1], s2[:x2], s2[:y2]] })
ok('and it starts at the edge of the box, not through the words',
   lead && Math.hypot(lead[:x1] - 100, lead[:y1] - 100) > 3.0,
   lead && [lead[:x1], lead[:y1]])
ok('it leaves the box on the side the thing is on',
   lead && lead[:x1] < 100 && lead[:y1] < 100, lead && [lead[:x1], lead[:y1]])
ok('and it does not start outside the box either',
   lead && lead[:x1] >= bx.min - 0.01 && lead[:y1] >= by.min - 0.01,
   lead && [[lead[:x1], bx.min], [lead[:y1], by.min]])

plain_note = PD::Document.new('t')
PC.apply_marks!(plain_note, 'marks' => [{ 't' => 'note', 'x' => 5, 'y' => 5,
                                          'text' => 'NO LEADER' }])
ok('a note with nothing to point at gets no leader',
   notes_of(plain_note).count { |s2| s2[:type] == :line } == 0,
   notes_of(plain_note).map { |s2| s2[:type] })
ok('but it still gets its box',
   notes_of(plain_note).count { |s2| s2[:type] == :polygon } == 1)

# -------------------------------------- a bare leader, the way SketchUp draws it
# Second picture from the user: a label reading 11' with a plain thin line down
# to the corner it belongs to. No head on the end. So the head is an option, and
# a note written before the option existed keeps the head it already had.
bare = PD::Document.new('t')
PC.apply_marks!(bare, 'marks' => [{ 't' => 'note', 'x' => 100, 'y' => 100,
                                    'lx' => 40, 'ly' => 40, 'arrow' => false,
                                    'text' => "11'" }])
ok('a bare leader is one line, not three',
   notes_of(bare).count { |s2| s2[:type] == :line } == 1,
   notes_of(bare).map { |s2| s2[:type] })
ok('it still gets its box and its words',
   notes_of(bare).count { |s2| s2[:type] == :polygon } == 1 &&
   texts_of(bare).first[:text] == "11'")
ok('and it still reaches the thing it points at',
   notes_of(bare).find { |s2| s2[:type] == :line }
                 .values_at(:x2, :y2).map(&:round) == [40, 40],
   notes_of(bare).find { |s2| s2[:type] == :line })

headed = PD::Document.new('t')
PC.apply_marks!(headed, 'marks' => [{ 't' => 'note', 'x' => 100, 'y' => 100,
                                      'lx' => 40, 'ly' => 40, 'arrow' => true,
                                      'text' => "11'" }])
ok('asking for a head gives a head',
   notes_of(headed).count { |s2| s2[:type] == :line } == 3,
   notes_of(headed).map { |s2| s2[:type] })
ok('a note from before the option existed keeps its head',
   sh.count { |s2| s2[:type] == :line } == 3, sh.map { |s2| s2[:type] })

# ------------------------------------------------ a leader with a knee in it
# Third picture from the user: the label A1 with a short level shoulder coming
# out of it, a knee, and then a slant down to the corner. Three things to take
# hold of, which is why the knee is stored and not worked out each time.
knee = PD::Document.new('t')
PC.apply_marks!(knee, 'marks' => [{ 't' => 'note', 'x' => 200, 'y' => 200,
                                    'kx' => 140, 'ky' => 200,
                                    'lx' => 40, 'ly' => 40,
                                    'arrow' => false, 'text' => 'A1' }])
kl = notes_of(knee).select { |s2| s2[:type] == :line }
ok('a leader with a knee is two lines', kl.length == 2, kl.length)

shoulder = kl.find { |s2| (s2[:y1] - 200).abs < 0.01 && (s2[:y2] - 200).abs < 0.01 }
ok('the shoulder comes out of the label dead level', !shoulder.nil?,
   kl.map { |s2| [s2[:y1], s2[:y2]] })
ok('and it stops at the knee',
   shoulder && (shoulder[:x2] - 140).abs < 0.01, shoulder && shoulder[:x2])
ok('the shoulder leaves the box, it does not start inside the words',
   shoulder && shoulder[:x1] < 200 && shoulder[:x1] > 140,
   shoulder && shoulder[:x1])

slant = kl.find { |s2| s2 != shoulder }
ok('the slant runs from the knee to the thing itself',
   slant && (slant[:x1] - 140).abs < 0.01 && (slant[:y1] - 200).abs < 0.01 &&
   (slant[:x2] - 40).abs < 0.01 && (slant[:y2] - 40).abs < 0.01,
   slant)

kneed_arrow = PD::Document.new('t')
PC.apply_marks!(kneed_arrow, 'marks' => [{ 't' => 'note', 'x' => 200, 'y' => 200,
                                           'kx' => 140, 'ky' => 200,
                                           'lx' => 40, 'ly' => 40,
                                           'arrow' => true, 'text' => 'A1' }])
ok('with a head it is four lines: shoulder, slant and two for the head',
   notes_of(kneed_arrow).count { |s2| s2[:type] == :line } == 4,
   notes_of(kneed_arrow).count { |s2| s2[:type] == :line })

ok('a note from before the knee existed still draws its single line',
   notes_of(bare).count { |s2| s2[:type] == :line } == 1,
   notes_of(bare).map { |s2| s2[:type] })

flat = PD::Document.new('t')
PC.apply_marks!(flat, 'marks' => [{ 't' => 'note', 'x' => 200, 'y' => 200,
                                    'kx' => 200, 'ky' => 200,
                                    'lx' => 40, 'ly' => 40, 'text' => 'A1' }])
ok('a knee sitting inside the label draws no shoulder, only the slant',
   notes_of(flat).count { |s2| s2[:type] == :line } == 3,
   notes_of(flat).map { |s2| s2[:type] })

zero = PD::Document.new('t')
PC.apply_marks!(zero, 'marks' => [{ 't' => 'note', 'x' => 5, 'y' => 5,
                                    'lx' => 5, 'ly' => 5, 'text' => 'ON ITSELF' }])
ok('a leader pointing at its own box is left off, not drawn as a speck',
   notes_of(zero).count { |s2| s2[:type] == :line } == 0,
   notes_of(zero).map { |s2| s2[:type] })

PC.apply_marks!(doc2, 'marks' => [{ 't' => 'wat', 'x' => 1, 'y' => 1 }])
ok('something we do not recognise is skipped, not crashed on', notes_of(doc2).empty?)

# ----------------------------------------------------- redrawing, not stacking
doc3 = PD::Document.new('t')
m = [{ 't' => 'dim', 'x1' => 0, 'y1' => 0, 'x2' => 120, 'y2' => 0 },
     { 't' => 'note', 'x' => 5, 'y' => 5, 'text' => 'A' }]
3.times { PC.apply_marks!(doc3, 'marks' => m) }
ok('drawing them again replaces them, never doubles them',
   notes_of(doc3).length == 6, notes_of(doc3).length)   # 4 for the dimension, 2 for the note (words + box)
PC.apply_marks!(doc3, 'marks' => [])
ok('and removing them all leaves nothing behind', notes_of(doc3).empty?)

# --------------------------------------- through the whole job, and onto paper
Sketchup.reset_model!
mo = Sketchup.active_model
[[0, 0, 240, 0], [240, 0, 240, 180], [240, 180, 0, 180], [0, 180, 0, 0]]
  .each_with_index do |(a, b, c, d), i|
  g = mo.entities.add_group
  { 'type' => 'wall', 'id' => "w#{i}", 'start_x' => a, 'start_y' => b,
    'end_x' => c, 'end_y' => d, 'thickness' => 5.0, 'anchor' => 'bottom-left',
    'wall_category' => 'exterior' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
end

marks = [{ 't' => 'dim', 'x1' => 0, 'y1' => -30, 'x2' => 240, 'y2' => -30 },
         { 't' => 'note', 'x' => 120, 'y' => 90, 'text' => 'LIVING' }]
d4 = PC.build_document(mo, size: 'ARCH D', scale: '1/4"', marks: marks)
ok('the marks survive the whole build', notes_of(d4).length == 6, notes_of(d4).length)
ok('and they can be switched off like any other layer',
   d4.canvas('MODEL').layers.map(&:name).include?(PC::MARK_LAYER),
   d4.canvas('MODEL').layers.map(&:name))

st = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
       'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
       'hidden' => [], 'tables_own_page' => true, 'images' => [], 'marks' => marks }
PC.layout_pages!(d4, st)
ok('changing the sheet redraws them without a trip to SketchUp',
   notes_of(d4).length == 6, notes_of(d4).length)

# the whole point: they do NOT move when the paper changes
before = notes_of(d4).map { |s2| [s2[:x1], s2[:y1], s2[:x], s2[:y]] }
st['size'] = 'ARCH C'
st['scale'] = '1/8"'
PC.layout_pages!(d4, st)
ok('a smaller sheet at a smaller scale does not move them on the house',
   notes_of(d4).map { |s2| [s2[:x1], s2[:y1], s2[:x], s2[:y]] } == before)

st['hidden'] = [PC::MARK_LAYER]
PC.layout_pages!(d4, st)
ok('turning the layer off hides them',
   d4.canvas('MODEL').layer(PC::MARK_LAYER).visible == false)

st['hidden'] = []
PC.layout_pages!(d4, st)
PP.forget_images!
out = File.join(File.dirname(File.expand_path(__FILE__)), 'rt52.pdf')
PP.export(d4, out)
raw = File.binread(out)
ok('the PDF was written', File.size(out) > 0)
ok("and the words the user typed are on it", raw.include?('(LIVING) Tj'))
ok('so is the length he measured',
   raw.include?("(20'-0\") Tj"), raw.scan(/\(\d+'[^)]*\) Tj/).first)
File.delete(out) if File.exist?(out)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

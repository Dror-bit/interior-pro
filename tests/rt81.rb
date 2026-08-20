# encoding: utf-8
# rt81 - moving a dimension's NUMBER out of the way (2026-08-19), Ruby half.
#
# The user, after drawing dimensions on a real plan:
#   "אני רוצה שיהיה לי אפשרות להזיז אותן ימינה ושמאלה ולמטה ולמעלה,
#    תלוי איך אני מצייר אותן לאיזה כיוון"
#
# That last clause is the design. The offset is NOT screen right/left/up/down;
# it is measured in the LINE'S OWN frame:
#   oa  along the line, start -> end   (his right/left)
#   oc  across it, on the normal       (his up/down)
# so the number keeps its place relative to the dimension however the line was
# drawn, and it stays put when he later drags an end somewhere else. A screen
# offset would need re-aiming every time the line moved, which is exactly the
# fiddling he is trying to get rid of.
#
# WHAT THIS SUITE IS REALLY GUARDING
# There are two copies of this formula - here, where the number is DRAWN (and
# therefore what the PDF prints), and dimLabelXY() in the sheet window, which
# needs to know where the number is before it can let him grab it. Two copies
# of one formula drift; that is the whole reason plan_canvas draws the marks
# for both the preview and the paper in the first place.
#
# So neither side owns the answer: dim_label_cases.json does. This suite reads
# it, t50 reads the same file, and if either implementation moves one of them
# goes red. Do not inline these numbers into either suite.
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

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def close(a, b, tol = 1e-6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

PC = InteriorPro::PlanCanvas
PD = InteriorPro::PlanDoc

CASES = JSON.parse(File.read(File.join(File.dirname(File.expand_path(__FILE__)),
                                       'dim_label_cases.json')))

# The shared file says what the defaults are. If the code stops agreeing with
# it, every case below would shift together and the failures would look like a
# maths bug instead of a changed constant - so it is checked on its own first.
ok('the default text height is the one the shared cases assume',
   close(PC.mark_text_h, CASES['_default_text_h']),
   [PC.mark_text_h, CASES['_default_text_h']])
ok('and so is the default offset',
   close(PC::DIM_LABEL_OFF, CASES['_default_off']),
   [PC::DIM_LABEL_OFF, CASES['_default_off']])

CASES['cases'].each do |c|
  got = PC.dim_label_xy(c['m'])
  want = c['xy']
  ok(c['why'], close(got[0], want[0]) && close(got[1], want[1]), [got, want])
end

# ------------------------------------------------- old drawings are untouched
#
# The single most important thing here. Every dimension made before today has
# no oa and no oc, and must come out in EXACTLY the place it always did -
# h * 0.8 across the line, nothing along it.
old = { 't' => 'dim', 'x1' => 10.0, 'y1' => 20.0, 'x2' => 130.0, 'y2' => 20.0 }
h = PC.mark_text_h
ok('a dimension from before today has not moved a thousandth of an inch',
   PC.dim_label_xy(old) == [70.0, 20.0 + h * 0.8],
   [PC.dim_label_xy(old), [70.0, 20.0 + h * 0.8]])
ok('and writing oc = the old default changes nothing at all',
   PC.dim_label_xy(old.merge('oc' => h * 0.8)) == PC.dim_label_xy(old))

# symbol keys reach the same answer as string keys - the marks arrive as JSON
# from the window, but a suite or a script may hand over symbols.
ok('symbol keys and string keys agree',
   PC.dim_label_xy(t: 'dim', x1: 10.0, y1: 20.0, x2: 130.0, y2: 20.0) ==
     PC.dim_label_xy(old))

# ---------------------------------------------- it reaches the drawn sheet
#
# dim_label_xy being right is no use if draw_mark_dim stopped calling it.
doc = PD::Document.new('t')
cv  = doc.canvas('MODEL')

place = lambda do |mark|
  lay = cv.layer(PC::MARK_LAYER)
  lay.shapes.clear
  PC.draw_mark_dim(lay, mark)
  lay.shapes.find { |s| s[:type] == :text }
end

plain = place.call('t' => 'dim', 'x1' => 0.0, 'y1' => 0.0,
                   'x2' => 100.0, 'y2' => 0.0)
ok('the drawn sheet has the number on it', !plain.nil?)
ok('and it is where dim_label_xy says',
   plain && close(plain[:x], 50.0) && close(plain[:y], h * 0.8),
   plain && [plain[:x], plain[:y]])

moved = place.call('t' => 'dim', 'x1' => 0.0, 'y1' => 0.0,
                   'x2' => 100.0, 'y2' => 0.0, 'oc' => -9.0, 'oa' => 4.0)
ok('shoving it really moves it on the sheet',
   moved && close(moved[:x], 54.0) && close(moved[:y], -9.0),
   moved && [moved[:x], moved[:y]])
ok('and it is still the same number - only the position changed',
   moved && moved[:text] == plain[:text], moved && [moved[:text], plain[:text]])
ok('the line itself did NOT move with it',
   cv.layer(PC::MARK_LAYER).shapes.any? do |s|
     s[:type] == :line && close(s[:x1].to_f, 0.0) && close(s[:x2].to_f, 100.0)
   end)

# and the number never turns upside down, whatever he does to the offset
up = place.call('t' => 'dim', 'x1' => 100.0, 'y1' => 0.0,
                'x2' => 0.0, 'y2' => 0.0, 'oc' => 20.0)
ok('a dimension drawn right-to-left still reads the right way up',
   up && up[:rotation].to_f.abs <= 90.0, up && up[:rotation])

# ------------------------------------------------------- through the marks
#
# The window sends whole marks back through st['marks']; apply_marks! is the
# door they come in by, and it must carry the new fields with them.
st = { 'marks' => [{ 't' => 'dim', 'x1' => 0.0, 'y1' => 0.0,
                     'x2' => 100.0, 'y2' => 0.0, 'oc' => 15.0, 'oa' => -20.0 }] }
PC.apply_marks!(doc, st)
txt = doc.canvas('MODEL').layer(PC::MARK_LAYER).shapes.find { |s| s[:type] == :text }
ok('a shoved dimension survives the trip from the window',
   txt && close(txt[:x], 30.0) && close(txt[:y], 15.0),
   txt && [txt[:x], txt[:y]])

st['marks'][0].delete('oc')
st['marks'][0].delete('oa')
PC.apply_marks!(doc, st)
txt = doc.canvas('MODEL').layer(PC::MARK_LAYER).shapes.find { |s| s[:type] == :text }
ok('and taking the shove away puts it back where it started',
   txt && close(txt[:x], 50.0) && close(txt[:y], h * 0.8),
   txt && [txt[:x], txt[:y]])

# ------------------------------------- standing the dimension off the wall
#
# The user's actual blocker, in his words: "המידה יושבת על האובייקט" - it is
# drawn straight onto the wall, so there is nothing to read and nothing to
# grab. `off` pushes the dimension LINE away from the two clicked points; the
# points themselves never move, because they are what is being measured.

flat = { 't' => 'dim', 'x1' => 0.0, 'y1' => 0.0, 'x2' => 100.0, 'y2' => 0.0 }
ok('with no off the dimension line IS the two clicked points',
   PC.dim_line(flat)[0, 4] == [0.0, 0.0, 100.0, 0.0], PC.dim_line(flat)[0, 4])
ok('off pushes the line across, and only across',
   PC.dim_line(flat.merge('off' => 12.0))[0, 4] == [0.0, 12.0, 100.0, 12.0],
   PC.dim_line(flat.merge('off' => 12.0))[0, 4])
ok('a negative off goes to the other side',
   PC.dim_line(flat.merge('off' => -12.0))[0, 4] == [0.0, -12.0, 100.0, -12.0])
ok('and which side that is follows the direction he drew',
   PC.dim_line({ 'x1' => 100.0, 'y1' => 0.0, 'x2' => 0.0, 'y2' => 0.0,
                 'off' => 12.0 })[0, 4] == [100.0, -12.0, 0.0, -12.0],
   PC.dim_line('x1' => 100.0, 'y1' => 0.0, 'x2' => 0.0, 'y2' => 0.0, 'off' => 12.0))
ok('a zero length dimension does not divide by zero',
   PC.dim_line('x1' => 5.0, 'y1' => 5.0, 'x2' => 5.0, 'y2' => 5.0,
               'off' => 9.0)[0, 4] == [5.0, 5.0, 5.0, 5.0])

# on the sheet: the line moved, the measured points did not, and the number
# still says the distance between the POINTS - not between the line's ends
lay = cv.layer(PC::MARK_LAYER)
lay.shapes.clear
PC.draw_mark_dim(lay, flat.merge('off' => 24.0))
lines = lay.shapes.select { |s| s[:type] == :line }
txt2  = lay.shapes.find { |s| s[:type] == :text }

ok('the dimension line is drawn 24" off the wall',
   lines.any? { |s| close(s[:y1].to_f, 24.0) && close(s[:y2].to_f, 24.0) &&
                    close(s[:x1].to_f, 0.0) && close(s[:x2].to_f, 100.0) },
   lines.map { |s| [s[:x1], s[:y1], s[:x2], s[:y2]] })
ok('the number went with it', txt2 && close(txt2[:y], 24.0 + h * 0.8),
   txt2 && txt2[:y])
ok('and it still reads the distance between the points he clicked',
   txt2 && txt2[:text] == InteriorPro::PlanGenerator.send(:fmt_feet, 100.0),
   txt2 && txt2[:text])

# the witness lines - the pair running from the wall out to the dimension
wit = lines.select do |s|
  ys = [s[:y1].to_f, s[:y2].to_f].sort
  ys[0] < 5.0 && ys[1] > 20.0
end
ok('two witness lines run from the wall out to the dimension', wit.length == 2,
   wit.length)
ok('one from each point he clicked',
   wit.map { |s| s[:x1].to_f.round(2) }.sort == [0.0, 100.0],
   wit.map { |s| s[:x1] })
ok('they start off the object, not touching it',
   wit.all? { |s| [s[:y1].to_f, s[:y2].to_f].min > 0.001 },
   wit.map { |s| [s[:y1], s[:y2]].min })
ok('and they carry a little past the dimension line',
   wit.all? { |s| [s[:y1].to_f, s[:y2].to_f].max > 24.0 },
   wit.map { |s| [s[:y1], s[:y2]].max })

lay.shapes.clear
PC.draw_mark_dim(lay, flat)
flat_lines = lay.shapes.count { |s| s[:type] == :line }
lay.shapes.clear
PC.draw_mark_dim(lay, flat.merge('off' => 24.0))
off_lines = lay.shapes.count { |s| s[:type] == :line }
ok('a dimension sitting ON the object gets NO witness lines - they would be '\
   'zero long, and that is every drawing made before today',
   flat_lines == 3, flat_lines)
ok('exactly two more lines appear once it stands off', off_lines - flat_lines == 2,
   [flat_lines, off_lines])

# ------------------------------- shoving ANY label, the plugin's own included
#
# The other half of what he asked for, and the half that was actually blocking
# him: the dimensions the plugin draws on the walls by itself are not marks, so
# there was nothing to select and nothing to move. They ARE reachable - every
# text on the sheet carries a key from name_texts!, and st['text_marks'] has
# been able to change one label's size since 2026-08-17. It just could not move
# one. Now it can, and that works for a room name and a tag too.
#
# THE TRAP, and it has its own checks: the plan is rebuilt from the model on
# every single change. An offset applied to wherever the label happens to be
# would add itself again on every pass and the label would walk off the sheet.
# So the BUILT position is remembered as x0/y0, exactly the way h0 already
# remembers the built height.

lay2 = doc.canvas('MODEL').layer('DIMENSIONS')
lay2.shapes.clear
lay2.text('12\' 6"', 100.0, 200.0, h: 5.0)
lay2.text('ROOM 2', 40.0, 60.0, h: 6.0)
PC.name_texts!(lay2)
keys = lay2.shapes.map { |s| s[:key] }
ok('every label on the sheet carries a key', keys.none?(&:nil?), keys)

kd = lay2.shapes[0][:key]
st2 = { 'text_marks' => { kd => { 'dx' => 15.0, 'dy' => -8.0 } } }
PC.apply_text_overrides!(doc, st2)
moved2 = lay2.shapes[0]
ok('a shoved label really moves',
   close(moved2[:x], 115.0) && close(moved2[:y], 192.0), [moved2[:x], moved2[:y]])
ok('and the label next to it does not',
   close(lay2.shapes[1][:x], 40.0) && close(lay2.shapes[1][:y], 60.0),
   [lay2.shapes[1][:x], lay2.shapes[1][:y]])
ok('the built position is remembered, the way h0 already is',
   close(moved2[:x0], 100.0) && close(moved2[:y0], 200.0),
   [moved2[:x0], moved2[:y0]])

# THE TRAP: run it again, and again. The plan is rebuilt on every change.
3.times { PC.apply_text_overrides!(doc, st2) }
ok('applying it four times over lands in the SAME place - the label does not '\
   'walk across the sheet on every redraw',
   close(lay2.shapes[0][:x], 115.0) && close(lay2.shapes[0][:y], 192.0),
   [lay2.shapes[0][:x], lay2.shapes[0][:y]])

# and changing the shove moves it from the BUILT place, not from where it was
st2['text_marks'][kd] = { 'dx' => -20.0, 'dy' => 5.0 }
PC.apply_text_overrides!(doc, st2)
ok('a new distance is measured from where the label was built',
   close(lay2.shapes[0][:x], 80.0) && close(lay2.shapes[0][:y], 205.0),
   [lay2.shapes[0][:x], lay2.shapes[0][:y]])

# a shove and a size live together - one must not wipe the other
st2['text_marks'][kd] = { 'dx' => 10.0, 'dy' => 0.0, 'pct' => 150.0 }
PC.apply_text_overrides!(doc, st2)
ok('a label can be both moved and resized',
   close(lay2.shapes[0][:x], 110.0) && lay2.shapes[0][:h] > 5.0,
   [lay2.shapes[0][:x], lay2.shapes[0][:h]])

# size only, no shove: the position must be left completely alone
lay2.shapes.clear
lay2.text('TAG A', 70.0, 90.0, h: 4.0)
PC.name_texts!(lay2)
kt = lay2.shapes[0][:key]
PC.apply_text_overrides!(doc, 'text_marks' => { kt => { 'pct' => 200.0 } })
ok('changing only the SIZE does not move a label a thousandth of an inch',
   close(lay2.shapes[0][:x], 70.0) && close(lay2.shapes[0][:y], 90.0),
   [lay2.shapes[0][:x], lay2.shapes[0][:y]])
ok('and it does not invent a built position it did not need',
   !lay2.shapes[0].key?(:x0), lay2.shapes[0][:x0])

# no overrides at all: byte for byte what it always was
lay2.shapes.clear
lay2.text('UNTOUCHED', 11.0, 22.0, h: 4.0)
PC.name_texts!(lay2)
PC.apply_text_overrides!(doc, 'text_marks' => {})
ok('a sheet with no overrides comes out exactly as it was built',
   close(lay2.shapes[0][:x], 11.0) && close(lay2.shapes[0][:y], 22.0))

puts($fails.zero? ? 'rt81 ALL PASS' : "rt81 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

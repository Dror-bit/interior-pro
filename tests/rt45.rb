# encoding: utf-8
# rt45 - a Length must never reach the sheet window (2026-08-12).
#
# The bug it exists for: SketchUp does not hand back plain numbers. Point3d#x
# and get_attribute give back Length objects. A Length behaves like a Float in
# Ruby, so everything looked right in the tests - but JSON.generate turns it
# into the STRING "~ -60' 1 13/16\"", and the window then did sums on words.
# Every scale said "does not fit", the position came out NaN, and the user got
# a blank sheet.
#
# So this suite feeds the recorder Lengths on purpose and demands numbers back.
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
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PD = InteriorPro::PlanDoc
PC = InteriorPro::PlanCanvas

# ---------------------------------------------------- a stand-in for Length
# Behaves like a number in Ruby, prints like a measurement - exactly the trap.
class FakeLength < Numeric
  def initialize(v); @v = v.to_f; end
  def to_f; @v; end
  def to_s; format('~ %d\' %d"', (@v / 12).to_i, (@v % 12).to_i); end
  def inspect; to_s; end
  def to_json(*_a); "\"#{to_s}\""; end
  def coerce(o); [FakeLength.new(o), self]; end
  def +(o); FakeLength.new(@v + o.to_f); end
  def -(o); FakeLength.new(@v - o.to_f); end
  def *(o); FakeLength.new(@v * o.to_f); end
  def /(o); FakeLength.new(@v / o.to_f); end
  def <=>(o); @v <=> o.to_f; end
end

def json_numbers?(v)
  case v
  when Hash  then v.values.all? { |x| json_numbers?(x) }
  when Array then v.all? { |x| json_numbers?(x) }
  when String then !(v =~ /^~?\s*-?\d+' /)
  else true
  end
end

# --------------------------------------------- the trap, on a bare document
doc = PD::Document.new('t')
lay = doc.canvas('MODEL').layer('WALLS')
lay.line(FakeLength.new(12), FakeLength.new(24), FakeLength.new(36), FakeLength.new(48))
lay.polygon([[FakeLength.new(0), FakeLength.new(0)], [FakeLength.new(120), FakeLength.new(0)],
             [FakeLength.new(120), FakeLength.new(96)]])
lay.text('KITCHEN', FakeLength.new(60), FakeLength.new(48), h: FakeLength.new(6))

s0 = lay.shapes[0]
ok('a line comes out as plain numbers',
   [s0[:x1], s0[:y1], s0[:x2], s0[:y2]].all? { |v| v.instance_of?(Float) },
   [s0[:x1].class, s0[:y1].class])
ok('polygon points come out as plain numbers',
   lay.shapes[1][:points].flatten.all? { |v| v.instance_of?(Float) },
   lay.shapes[1][:points].first.map(&:class))
ok('a text position and height come out as plain numbers',
   [lay.shapes[2][:x], lay.shapes[2][:y], lay.shapes[2][:h]].all? { |v| v.instance_of?(Float) },
   [lay.shapes[2][:x].class, lay.shapes[2][:h].class])

b = doc.canvas('MODEL').bounds
ok('the bounds are plain numbers', b.all? { |v| v.instance_of?(Float) }, b.map(&:class))
ok('and they survive the trip through JSON as NUMBERS',
   JSON.parse(JSON.generate(bounds: b))['bounds'].all? { |v| v.is_a?(Numeric) },
   JSON.parse(JSON.generate(bounds: b))['bounds'])

# ------------------------------------------ and now through the real recorder
rec = PC::Recorder.new
rec.layer_name = 'WALLS'
class LenPoint
  def initialize(x, y); @x = FakeLength.new(x); @y = FakeLength.new(y); end
  attr_reader :x, :y
end
rec.add_edges([LenPoint.new(0, 0), LenPoint.new(120, 0), LenPoint.new(120, 96)])
rec.add_face([LenPoint.new(0, 0), LenPoint.new(60, 0), LenPoint.new(60, 60)])
rec.add_circle(LenPoint.new(48, 48), nil, FakeLength.new(8), 8)

cv2 = PD::Canvas.new('MODEL')
rec.flush_into(cv2)
pts = cv2.layer('WALLS').shapes.flat_map { |s| (s[:points] || []).flatten }
ok('every point the recorder writes is a plain number',
   !pts.empty? && pts.all? { |v| v.instance_of?(Float) },
   pts.map(&:class).uniq)
ok('a circle drawn from a Length centre is numbers too',
   cv2.layer('WALLS').shapes.last[:points].flatten.all? { |v| v.instance_of?(Float) })

# ----------------------------------------------- the whole payload, end to end
Sketchup.reset_model!
m = Sketchup.active_model
def wall(m, id, sx, sy, ex, ey, op = nil)
  g = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex,
    'end_y' => ey, 'thickness' => 5.0, 'anchor' => 'bottom-left',
    'wall_category' => 'exterior' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g.set_attribute('InteriorPro', 'door_openings', op) if op
  g
end
# the user's own house, from sheet_report.txt: negative coordinates, taller
# than it is wide, so it does NOT fit at 1/4" on a landscape Arch D
[[0, 0, 0, 424.8], [0, 424.8, -691.2, 424.8], [-691.2, 424.8, -691.2, -638.4],
 [-691.2, -638.4, -386.4, -638.4], [-386.4, -638.4, -386.4, 0],
 [-386.4, 0, 0, 0]].each_with_index do |(a, b2, c, d2), i|
  wall(m, "w#{i}", a, b2, c, d2)
end

doc2 = PC.build_document(m, size: 'ARCH D', scale: '1/4"')
payload = { doc: doc2.to_h, bounds: doc2.canvas('MODEL').bounds }
back = JSON.parse(JSON.generate(payload))
ok('nothing in the payload came out as a measurement in words',
   json_numbers?(back), 'a "~ 12\' 3\"" string got through')
ok('the bounds arrive as four numbers',
   back['bounds'].all? { |v| v.is_a?(Numeric) }, back['bounds'])

# and the sums the window does really work out
w_ft = (back['bounds'][2] - back['bounds'][0]) / 12.0
h_ft = (back['bounds'][3] - back['bounds'][1]) / 12.0
ok('the window can measure the house: about 62 by 93 feet',
   w_ft.round == 63 && h_ft.round == 94, [w_ft.round(1), h_ft.round(1)])

v = doc2.pages.first.views.first
ok('it does not fit at a quarter inch - that part was true all along',
   !v.fits?(doc2.canvas('MODEL').bounds))
ok('but 3/16 does, and now the window can work that out too',
   v.fit_scale(doc2.canvas('MODEL').bounds) == '3/16"',
   v.fit_scale(doc2.canvas('MODEL').bounds))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

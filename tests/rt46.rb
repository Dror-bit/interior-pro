# encoding: utf-8
# rt46 - hand-drawn SketchUp geometry onto the sheet (plan_geometry.rb),
# 2026-08-13.
#
# The user has a back yard he modelled by hand, and he wants it on a drawing
# now - long before there are proper tools for benches and paving. The rule
# that makes that safe: it goes into a LAYER OF ITS OWN, it reads the model
# and never writes to it, and the plugin's own walls and doors must not come
# in twice as raw edges.
ENV['REAL_ROOMS'] = '1'
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
require './plan_geometry'
require './plan_tables'
require './plan_canvas'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PD = InteriorPro::PlanDoc
PG = InteriorPro::PlanGeometry
PC = InteriorPro::PlanCanvas

def p3(x, y, z = 0); Geom::Point3d.new(x, y, z); end

# --------------------------------------------------------- flattening, pure
edges = [
  [[0, 0, 0], [120, 0, 0]],
  [[120, 0, 0], [120, 96, 0]],
  [[0, 0, 40], [120, 0, 40]],      # the SAME line, one storey up
  [[0, 0, 0], [0.1, 0, 0]],        # too short to matter
  [[0, 300, 500], [120, 300, 500]] # a roof ridge, far above any cut
]
f = PG.flatten(edges, {})
ok('a wall and its top rail become ONE line on paper', f.length == 3, f.length)
ok('a whisker of a line is dropped', f.none? { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) < PG::MIN_LEN })
ok('the flattened line keeps its real length',
   f.first == [[0.0, 0.0], [120.0, 0.0]], f.first)

f2 = PG.flatten(edges, z_max: 100.0)
ok('a cut height leaves out what is above it', f2.length == 2, f2.length)
f3 = PG.flatten(edges, z_min: 300.0)
ok('and a floor height leaves out what is below it', f3.length == 1, f3.length)

ok('a line and the same line drawn backwards are one line',
   PG.flatten([[[0, 0, 0], [50, 0, 0]], [[50, 0, 0], [0, 0, 0]]], {}).length == 1)
ok('two lines a hair apart are still two lines',
   PG.flatten([[[0, 0, 0], [50, 0, 0]], [[0, 1, 0], [50, 1, 0]]], {}).length == 2)
ok('nothing in, nothing out', PG.flatten([], {}).empty?)

# ----------------------------------------------------- reading a real model
Sketchup.reset_model!
m = Sketchup.active_model

# a wall the plugin owns - it must NOT arrive as raw edges
w = m.entities.add_group
{ 'type' => 'wall', 'id' => 'w1', 'start_x' => 0, 'start_y' => 0, 'end_x' => 240,
  'end_y' => 0, 'thickness' => 6, 'anchor' => 'bottom-left',
  'wall_category' => 'exterior' }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
w.entities.add_line(p3(0, 0, 0), p3(240, 0, 0))

# the back yard, drawn by hand: a patio and a bench on top of it
yard = m.entities.add_group
yard.name = 'Back yard'
[[0, -200], [300, -200], [300, -20], [0, -20], [0, -200]].each_cons(2) do |(a, b), (c, d)|
  yard.entities.add_line(p3(a, b, 0), p3(c, d, 0))
end
bench = yard.entities.add_group
[[40, -180], [120, -180], [120, -150], [40, -150], [40, -180]].each_cons(2) do |(a, b), (c, d)|
  bench.entities.add_line(p3(a, b, 18), p3(c, d, 18))
end
soft = yard.entities.add_line(p3(10, -100, 0), p3(90, -100, 0))
soft.soft = true

doc = PD::Document.new('yard')
cv  = doc.canvas('MODEL')

# nothing chosen yet -> nothing drawn. It never guesses for him.
PG.build!(m, cv, {})
ok('with nothing selected the layer stays empty', PG.count(cv).zero?, PG.count(cv))

pids = PG.pids_from([yard])
ok('the yard has an id we can remember', pids.length == 1, pids)

PG.build!(m, cv, pids: pids)
n = PG.count(cv)
ok('the yard is on the sheet', n.positive?, n)
ok('the patio outline came through - four sides', n >= 4, n)
ok('and the bench inside the group came too, one level down', n >= 8, n)
ok('a softened edge is left out by default', n == 8, n)

PG.build!(m, cv, pids: pids, hide_soft: false)
ok('unless you ask for it', PG.count(cv) == 9, PG.count(cv))

# the bench is at 18" - it must land in plan at its real x/y, flat
lay = cv.layer(PG::LAYER)
xs = lay.shapes.flat_map { |s| s[:points].map { |p| p[0] } }
ys = lay.shapes.flat_map { |s| s[:points].map { |p| p[1] } }
ok('everything landed inside the yard, in feet not inches',
   xs.min.round == 0 && xs.max.round == 300 && ys.min.round == -200 && ys.max.round == -20,
   [xs.min, xs.max, ys.min, ys.max])
ok('every point is a plain number, not a SketchUp Length',
   (xs + ys).all? { |v| v.instance_of?(Float) }, (xs + ys).map(&:class).uniq)

# the wall the plugin owns stays out
PG.build!(m, cv, pids: PG.pids_from([w, yard]))
wall_line = cv.layer(PG::LAYER).shapes.any? do |s|
  s[:points].any? { |p| p[1].abs < 0.01 && p[0] > 200 }
end
ok('the plugin\'s own wall does not come in a second time as raw lines', !wall_line)

# --------------------------------------------------- it only ever reads
before_ops = m.ops.length
before_ents = m.entities.length
PG.build!(m, cv, pids: pids)
ok('drawing the yard opens no undo step', m.ops.length == before_ops)
ok('and adds nothing to the model', m.entities.length == before_ents)

# --------------------------------------------- and it lands on the sheet
doc2 = PC.build_document(m, size: 'ARCH D', scale: '1/4"',
                         site: { pids: pids })
ok('the whole pipeline carries it through', PG.count(doc2.canvas('MODEL')).positive?)
ok('on a layer of its own, next to the walls',
   doc2.canvas('MODEL').layer?(PG::LAYER) && doc2.canvas('MODEL').layer?('WALLS'))
b = doc2.canvas('MODEL').bounds
ok('the yard is inside the measured drawing, so the sheet frames it too',
   b[1] <= -200.0 + 1e-6, b)
ok('turning that layer off leaves the rest alone',
   begin
     PC.apply_visibility!(doc2, [PG::LAYER])
     doc2.canvas('MODEL').layer(PG::LAYER).visible == false &&
       doc2.canvas('MODEL').layer('WALLS').visible == true
   end)
ok('and then the drawing measures the house only',
   doc2.canvas('MODEL').bounds[1] > -200.0, doc2.canvas('MODEL').bounds)
PC.apply_visibility!(doc2, [])

# and the sheet window knows how to ask for it
h = InteriorPro::PlanSheetDialog.html rescue ''
if h.empty?
  require './plan_sheet_dialog'
  h = InteriorPro::PlanSheetDialog.html
end
ok('the window has a button to add what is selected', h.include?('sketchup.add_selection()'))
ok('and one to clear it', h.include?('sketchup.clear_selection()'))
src = File.read(File.join(File.dirname(__FILE__), 'plan_sheet_dialog.rb'), encoding: 'UTF-8')
ok('the window keeps the lines itself, not inside the state',
   src.include?('self.site_lines =') && !src.include?("'site_lines' => []"))
# thousands of lines in a model attribute are swallowed without a word, so a
# big site is held in memory and only a small one is written down (2026-08-13)
ok('a size limit guards the model attribute', src.include?('SITE_ATTR_MAX'))
ok('and the user is told when it will not survive a restart',
   src.include?('גדול מדי לשמירה'))
ok('an empty selection is told, not silently ignored', src.include?('nothing selected'))

# ------------------------------------------------- it says where it got to
PG.build!(m, cv, pids: PG.pids_from([w, yard]))
r = PG.last_report
ok('the report counts what was asked for', r[:asked] == 2, r)
ok('and how many of them it could actually find', r[:found] == 2, r)
PG.build!(m, cv, pids: pids)
r = PG.last_report
ok('and what it found', r[:found] == 1, r)
ok('and how many lines were in the model', r[:edges] >= 8, r)
ok('and how many made it onto the paper', r[:lines] == 8, r)
PG.build!(m, cv, pids: [999_999_999])
r = PG.last_report
ok("an id that is nowhere shows up as found: 0", r[:found].zero? && r[:asked] == 1, r)
ok("and then there is no layer at all", PG.count(cv).zero?)

# ------------------------- the snapshot road: take the lines there and then
# (2026-08-13: looking entities up again by persistent id found 0 of 4632 on
# the user real model, so the button now harvests while it holds them.)
# A loose line lying straight in the model, not inside any group. This is what
# the user's site plan is full of, and it crashed with
# "no implicit conversion to Transformation" because there is no transform to
# apply at the top level (2026-08-13).
loose = m.entities.add_line(p3(-40, -40, 0), p3(-40, 260, 0))
lsnap = PG.snapshot([loose])
ok('a loose line at the top level does not blow up', lsnap.length == 1, lsnap)
ok('and it keeps its place', lsnap.first == [[-40.0, -40.0], [-40.0, 260.0]], lsnap.first)
ok('a loose line and a group together are fine',
   PG.snapshot([loose, yard]).length == 9, PG.snapshot([loose, yard]).length)

snap = PG.snapshot([yard])
ok("a snapshot comes back as flat line pairs",
   snap.is_a?(Array) && snap.first.is_a?(Array) && snap.first.first.length == 2, snap.first)
ok("it has the same lines the lookup road produced", snap.length == 8, snap.length)
ok("the numbers are rounded, not endless", snap.flatten.all? { |v| (v * 100).round == (v * 100) }, snap.first)
ok("every number is plain", snap.flatten.all? { |v| v.instance_of?(Float) })

cv3 = PD::Canvas.new("MODEL")
PG.build!(m, cv3, lines: snap)
ok("the sheet draws a snapshot without touching the model again", PG.count(cv3) == 8, PG.count(cv3))

# a snapshot of one of our own walls brings nothing - it is drawn from
# attributes, not from raw lines
ok("our own wall gives an empty snapshot", PG.snapshot([w]).empty?, PG.snapshot([w]))

# and a snapshot survives being written down and read back as plain data
require "json"
back = JSON.parse(JSON.generate(snap))
cv4 = PD::Canvas.new("MODEL")
PG.build!(m, cv4, lines: back)
ok("it survives being saved and reopened", PG.count(cv4) == 8, PG.count(cv4))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

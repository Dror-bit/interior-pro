# encoding: utf-8
# rt265 - the plan recognises our own things INSIDE a plain group (2026-10-07).
#
# 6 Bronco Ln: the house is built from our walls, doors, windows and roof, but
# two months ago all of it was put inside one ordinary group. The plan only
# ever looked at the top level of the model, so the sheet found no walls at
# all, and "add what is selected" took the house as raw lines - roof and all.
#
# The user, three times in a row: "התוסף צריך לזהות את הקירות גם אם הם בתוך
# קבוצה" - and - "בעתיד אני אבנה הכל רק עם התוסף".
#
# THE RULE THIS SUITE PINS:
#   1. One of ours is ours wherever it sits. A wall inside a plain group is
#      drawn as a wall - poche, door swing, window, mark - in the place the
#      group really puts it in the world.
#   2. And it is NOT also taken as loose lines. What the plan draws from its
#      attributes never comes in a second time through "add what is selected";
#      that is how the roof stops landing on the floor plan.
#   3. A model whose walls sit at the top level draws EXACTLY as it did.
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

PG  = InteriorPro::PlanGenerator
PC  = InteriorPro::PlanCanvas
PD  = InteriorPro::PlanDoc
PGE = InteriorPro::PlanGeometry
PSD = InteriorPro::PlanSheetDialog

def tag!(g, h)
  h.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end

# The same small house every time: four walls, a door in one, a window in
# another, a room, a roof over it and one thing drawn by hand.
def house_into(ents)
  wall = lambda do |id, sx, sy, ex, ey, op = nil|
    g = tag!(ents.add_group, 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy,
                             'end_x' => ex, 'end_y' => ey, 'thickness' => 6.0,
                             'anchor' => 'bottom-left', 'wall_category' => 'exterior')
    g.set_attribute('InteriorPro', 'door_openings', op) if op
    # the wall's own body: lines that must never reach the sheet as loose lines
    g.entities.add_line(Geom::Point3d.new(sx, sy, 0), Geom::Point3d.new(ex, ey, 0))
    g.entities.add_line(Geom::Point3d.new(sx, sy, 96), Geom::Point3d.new(ex, ey, 96))
    g
  end
  wall.call('w1',   0.0,   0.0, 360.0,   0.0, [[120.0, 36.0, 84.0]])
  wall.call('w2', 360.0,   0.0, 360.0, 240.0, [[100.0, 48.0, 48.0]])
  wall.call('w3', 360.0, 240.0,   0.0, 240.0)
  wall.call('w4',   0.0, 240.0,   0.0,   0.0)
  tag!(ents.add_group, 'type' => 'door', 'host_wall_id' => 'w1', 'position_along_wall_in' => 120.0,
                       'width_in' => 36.0, 'height_in' => 84.0, 'door_type' => 'Single',
                       'door_category' => 'exterior', 'swing_direction' => 'left', 'clicked_side' => 1)
  tag!(ents.add_group, 'type' => 'window', 'host_wall_id' => 'w2', 'position_along_wall_in' => 100.0,
                       'width_in' => 48.0, 'height_in' => 48.0, 'window_type' => 'Casement',
                       'header_height_in' => 84.0, 'clicked_side' => 1)
  tag!(ents.add_group, 'type' => 'room', 'name' => 'Room 1', 'area_sqft' => 600.0,
                       'boundary_xy' => [6.0, 6.0, 354.0, 6.0, 354.0, 234.0, 6.0, 234.0])
  roof = tag!(ents.add_group, 'type' => 'roof')
  roof.entities.add_line(Geom::Point3d.new(-12, -12, 120), Geom::Point3d.new(372, 252, 180))   # a hip
  roof.entities.add_line(Geom::Point3d.new(-12, 252, 120), Geom::Point3d.new(372, -12, 180))
  # a wall hiding inside the roof: what is inside one of ours is its body
  tag!(roof.entities.add_group, 'type' => 'wall', 'id' => 'ghost', 'start_x' => 0.0, 'start_y' => 500.0,
                                'end_x' => 100.0, 'end_y' => 500.0, 'thickness' => 6.0)
  hand = ents.add_group                                   # a planter he drew himself
  hand.entities.add_line(Geom::Point3d.new(400, 0, 0), Geom::Point3d.new(400, 50, 0))
  hand.entities.add_line(Geom::Point3d.new(400, 50, 0), Geom::Point3d.new(450, 50, 0))
  hand
end

def layers_of(model)
  doc = PD::Document.new('t')
  PC.build(model, doc, 'MODEL')
  doc.canvas('MODEL').layers.each_with_object({}) { |l, h| h[l.name] = l.shapes.map { |s| s.dup } }
end

def pts_of(shape)
  if shape[:points] then shape[:points].map { |p| [p[0].to_f, p[1].to_f] }
  elsif shape[:x1]  then [[shape[:x1].to_f, shape[:y1].to_f], [shape[:x2].to_f, shape[:y2].to_f]]
  else [[shape[:x].to_f, shape[:y].to_f]]
  end
end

# every point of every shape on a layer, moved by a placement, compared
def same_after?(a_shapes, b_shapes, xf, tol = 0.02)
  return false unless a_shapes && b_shapes && a_shapes.length == b_shapes.length
  a_shapes.zip(b_shapes).all? do |a, b|
    pa = pts_of(a).map { |x, y| q = Geom::Point3d.new(x, y, 0).transform(xf); [q.x.to_f, q.y.to_f] }
    pb = pts_of(b)
    pa.length == pb.length && pa.zip(pb).all? { |p, q| (p[0] - q[0]).abs < tol && (p[1] - q[1]).abs < tol }
  end
end

# A mark's circle or hexagon is drawn square to the page whichever way the
# house is turned, so its corners do not turn with the group - its MIDDLE does.
def middle(shape)
  pts = pts_of(shape)
  pts = pts[0...-1] if pts.length > 2 && pts.first == pts.last
  [pts.map(&:first).sum / pts.length, pts.map(&:last).sum / pts.length]
end

def same_middles?(a_shapes, b_shapes, xf, tol = 0.05)
  return false unless a_shapes && b_shapes && a_shapes.length == b_shapes.length
  a_shapes.zip(b_shapes).all? do |a, b|
    ma = middle(a)
    q  = Geom::Point3d.new(ma[0], ma[1], 0).transform(xf)
    mb = middle(b)
    (q.x.to_f - mb[0]).abs < tol && (q.y.to_f - mb[1]).abs < tol
  end
end

def switch(v)
  PG.send(:remove_const, :USE_NESTED_OWN) if PG.const_defined?(:USE_NESTED_OWN, false)
  PG.const_set(:USE_NESTED_OWN, v)
end

ok('there is a switch, and it is on', PG.const_defined?(:USE_NESTED_OWN, false) && PG::USE_NESTED_OWN == true)

# ---------------------------------------------------------------------------
# 0. the house at the top level - the drawing everything else is held against
# ---------------------------------------------------------------------------
Sketchup.reset_model!
house_into(Sketchup.active_model.entities)
TOP = layers_of(Sketchup.active_model)
ok('at the top level the walls are drawn', TOP['WALLS'].to_a.length >= 4, TOP.keys)
ok('and the door, and the window', !TOP['DOORS'].to_a.empty? && !TOP['WINDOWS'].to_a.empty?, TOP.keys)
ok('and the room is named', TOP['ROOMS'].to_a.any? { |s| s[:text] == 'ROOM 1' }, TOP['ROOMS'])

switch(false)
TOP_OFF = layers_of(Sketchup.active_model)
switch(true)
ok('A MODEL WITH ITS WALLS AT THE TOP LEVEL DRAWS EXACTLY AS BEFORE  <<< nothing broken',
   JSON.generate(TOP) == JSON.generate(TOP_OFF))

# ---------------------------------------------------------------------------
# 1. the same house inside a plain group, slid across the site
# ---------------------------------------------------------------------------
SLIDE = Geom::Transformation.translation(Geom::Vector3d.new(400.0, -1889.0, 0.0))
Sketchup.reset_model!
box = Sketchup.active_model.entities.add_group
box.transformation = SLIDE
house_into(box.entities)
IN = layers_of(Sketchup.active_model)

ok('INSIDE A GROUP THE WALLS ARE STILL WALLS  <<< THE RULE',
   IN['WALLS'].to_a.length == TOP['WALLS'].length, [IN.keys, IN['WALLS'].to_a.length])
ok('drawn where the group really puts them in the world',
   same_after?(TOP['WALLS'], IN['WALLS'], SLIDE))
ok('the door swing comes with its wall', same_after?(TOP['DOORS'], IN['DOORS'], SLIDE),
   [TOP['DOORS'].to_a.length, IN['DOORS'].to_a.length])
ok('and the window', same_after?(TOP['WINDOWS'], IN['WINDOWS'], SLIDE),
   [TOP['WINDOWS'].to_a.length, IN['WINDOWS'].to_a.length])
ok('and the room name sits in the room', same_after?(TOP['ROOMS'], IN['ROOMS'], SLIDE), IN['ROOMS'])
ok('and the dimensions go round the house where it stands',
   same_after?(TOP['DIMENSIONS'], IN['DIMENSIONS'], SLIDE),
   [TOP['DIMENSIONS'].to_a.length, IN['DIMENSIONS'].to_a.length])
ok('the wall hidden inside the roof is not a wall of the house',
   IN['WALLS'].to_a.length == TOP['WALLS'].length)

doc = PD::Document.new('t')
PC.build(Sketchup.active_model, doc, 'MODEL')
ok('the door and the window are in the schedules',
   doc.schedules && JSON.generate(doc.schedules).include?('D101') && JSON.generate(doc.schedules).include?('W101'),
   doc.schedules)

# ---------------------------------------------------------------------------
# 2. turned as well as slid - a house is rarely square to the axes of a site
# ---------------------------------------------------------------------------
TURN = SLIDE * Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), 0.5)
Sketchup.reset_model!
box = Sketchup.active_model.entities.add_group
box.transformation = TURN
house_into(box.entities)
ROT = layers_of(Sketchup.active_model)
ok('a turned house: the walls turn with the group', same_after?(TOP['WALLS'], ROT['WALLS'], TURN))
ok('and the door, and the window - every piece of each symbol',
   same_middles?(TOP['DOORS'], ROT['DOORS'], TURN) && same_middles?(TOP['WINDOWS'], ROT['WINDOWS'], TURN),
   [TOP['DOORS'].length, ROT['DOORS'].to_a.length, TOP['WINDOWS'].length, ROT['WINDOWS'].to_a.length])
swing = TOP['DOORS'].index { |x| x[:type] == :polyline && pts_of(x).length > 7 && pts_of(x).first != pts_of(x).last }
ok('the swing arc itself turns point for point',
   swing && same_after?([TOP['DOORS'][swing]], [ROT['DOORS'][swing]], TURN), swing)

# ---------------------------------------------------------------------------
# 3. a group inside a group, and the same house placed twice as a component
# ---------------------------------------------------------------------------
Sketchup.reset_model!
outer = Sketchup.active_model.entities.add_group
outer.transformation = Geom::Transformation.translation(Geom::Vector3d.new(400.0, 0.0, 0.0))
inner = outer.entities.add_group
inner.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0.0, -1889.0, 0.0))
house_into(inner.entities)
DEEP = layers_of(Sketchup.active_model)
ok('two groups deep: both placements are applied', same_after?(TOP['WALLS'], DEEP['WALLS'], SLIDE))

Sketchup.reset_model!
defn = Sketchup::ComponentDefinition.new('House')
house_into(defn.entities)
Sketchup.active_model.entities.add_instance(defn, SLIDE)
Sketchup.active_model.entities.add_instance(defn, Geom::Transformation.translation(Geom::Vector3d.new(5000.0, 0.0, 0.0)))
TWICE = layers_of(Sketchup.active_model)
ok('one house placed twice as a component is drawn twice',
   TWICE['WALLS'].to_a.length == TOP['WALLS'].length * 2, TWICE['WALLS'].to_a.length)

# ---------------------------------------------------------------------------
# 4. a group that is switched off is set aside - its walls are not on the plan
# ---------------------------------------------------------------------------
Sketchup.reset_model!
box = Sketchup.active_model.entities.add_group
box.transformation = SLIDE
house_into(box.entities)
def box.hidden?; true; end
ok('walls inside a HIDDEN group are left off the plan', layers_of(Sketchup.active_model)['WALLS'].to_a.empty?)

# ---------------------------------------------------------------------------
# 5. and they are not taken a second time as loose lines - the roof goes too
# ---------------------------------------------------------------------------
Sketchup.reset_model!
box = Sketchup.active_model.entities.add_group
box.transformation = SLIDE
house_into(box.entities)
lines = PGE.snapshot([box])
ok('"add what is selected" on the house: only what he drew by hand comes in as lines',
   lines.length == 2, lines)
ok('and it comes in where it stands in the world',
   lines.all? { |a, b| a[0] >= 799.9 && b[0] <= 850.1 && a[1] <= -1838.9 && b[1] >= -1889.1 }, lines)
far = lines.flatten(1).map { |p| p[0] }.max
ok('THE ROOF IS NOT ON THE FLOOR PLAN', far < 760.0 + 400.0 && lines.none? { |a, b| (a[0] - 388.0).abs < 0.1 || (b[0] - 772.0).abs < 0.1 })

# ---------------------------------------------------------------------------
# 6. the switch puts all of it back the way it was
# ---------------------------------------------------------------------------
switch(false)
OFF = layers_of(Sketchup.active_model)
off_lines = PGE.snapshot([box])
switch(true)
ok('switched off: a house inside a group has no walls on the plan, as before', OFF['WALLS'].to_a.empty?, OFF.keys)
ok('switched off: and the whole house comes in as loose lines, roof included, as before',
   off_lines.length > 2, off_lines.length)

# ---------------------------------------------------------------------------
# 7. the real road: the sheet window, opened on his kind of model
# ---------------------------------------------------------------------------
Sketchup.reset_model!
box = Sketchup.active_model.entities.add_group
box.transformation = SLIDE
house_into(box.entities)
Sketchup.active_model.delete_attribute('InteriorPro', 'sheet_state')
PSD.site_lines = []
PSD.show
dlg = PSD.instance_variable_get(:@dialog)
dlg.callbacks['sheet_ready'].call(nil)
s = dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }
sheet = JSON.parse(s[/\AloadSheet\((.*)\)\z/m, 1])
cv = sheet['doc']['canvases'].find { |c| c['name'] == 'MODEL' }
names = cv['layers'].map { |l| l['name'] }
ok('THE SHEET WINDOW OPENS WITH THE HOUSE DRAWN AS WALLS, BY ITSELF',
   names.include?('WALLS') && names.include?('DOORS') && names.include?('WINDOWS'), names)
b = sheet['bounds']
ok('and the sheet is centred on where the house really stands',
   b && b[0] > 300.0 && b[2] < 900.0 && b[1] > -2000.0 && b[3] < -1500.0, b)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

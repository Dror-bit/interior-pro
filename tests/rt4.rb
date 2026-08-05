# encoding: utf-8
require './sketchup_stub'
require './plan_editor'
require 'json'
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
PE = InteriorPro::PlanEditor
PE.show
dlg = PE.instance_variable_get(:@dialog)
ok('rename_room registered', dlg.callbacks.key?('rename_room'))
ok('set_sketch_area registered', dlg.callbacks.key?('set_sketch_area'))
ok('rename_sketch_area registered', dlg.callbacks.key?('rename_sketch_area'))

# ---- rooms_payload ------------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
r = m.entities.add_group
r.set_attribute('InteriorPro', 'type', 'room')
r.set_attribute('InteriorPro', 'id', 'r1')
r.set_attribute('InteriorPro', 'name', 'Kitchen')
r.set_attribute('InteriorPro', 'number', 104)
r.set_attribute('InteriorPro', 'area_sqft', 180.4444)
r.set_attribute('InteriorPro', 'boundary_xy', [0, 0, 120, 0, 120, 120, 0, 120])
pl = PE.send(:rooms_payload)
ok('one room in the payload', pl.length == 1, pl)
ok('name, number and area carried', pl[0]['name'] == 'Kitchen' && pl[0]['number'] == 104 &&
                                    (pl[0]['area'] - 180.4444).abs < 1e-6, pl[0])
ok('boundary carried', pl[0]['pts'].length == 8, pl[0]['pts'])

# a room with a broken boundary is skipped, not crashed on
bad = m.entities.add_group
bad.set_attribute('InteriorPro', 'type', 'room')
bad.set_attribute('InteriorPro', 'boundary_xy', [1, 2])
ok('a bad boundary is skipped', PE.send(:rooms_payload).length == 1, PE.send(:rooms_payload))

# ---- rename_room --------------------------------------------------------
dlg.callbacks['rename_room'].call(nil, JSON.generate({ 'id' => 'r1', 'name' => 'Master Bedroom' }))
ok('name written to the model', r.get_attribute('InteriorPro', 'name') == 'Master Bedroom',
   r.get_attribute('InteriorPro', 'name'))
ok('the 3D label was rebuilt', InteriorPro::RoomManager.label_calls > 0)
dlg.callbacks['rename_room'].call(nil, JSON.generate({ 'id' => 'r1', 'name' => '   ' }))
ok('a blank name is ignored', r.get_attribute('InteriorPro', 'name') == 'Master Bedroom')
dlg.callbacks['rename_room'].call(nil, JSON.generate({ 'id' => 'nope', 'name' => 'X' }))
ok('an unknown room id is a no-op', r.get_attribute('InteriorPro', 'name') == 'Master Bedroom')

# ---- area tag on a shape ------------------------------------------------
Sketchup.reset_model!
m2 = Sketchup.active_model
g = PE.send(:build_sketch_group, [0, 0, 120, 0, 120, 60, 0, 60], true, m2, shape: 'rect')
id = g.get_attribute('InteriorPro', 'id')
ok('area is off to begin with', g.get_attribute('InteriorPro', 'area_on').nil?)
dlg.callbacks['set_sketch_area'].call(nil, JSON.generate({ 'ids' => [id], 'on' => true }))
ok('area tag switched on', g.get_attribute('InteriorPro', 'area_on') == true)
ok('the payload reports it', PE.send(:sketches_payload)[0]['area_on'] == true, PE.send(:sketches_payload)[0])
dlg.callbacks['rename_sketch_area'].call(nil, JSON.generate({ 'id' => id, 'name' => 'Patio' }))
ok('area name saved', g.get_attribute('InteriorPro', 'area_name') == 'Patio')
ok('and reported', PE.send(:sketches_payload)[0]['area_name'] == 'Patio')
dlg.callbacks['rename_sketch_area'].call(nil, JSON.generate({ 'id' => id, 'name' => '' }))
ok('a blank name clears it', g.get_attribute('InteriorPro', 'area_name').nil?)
dlg.callbacks['set_sketch_area'].call(nil, JSON.generate({ 'ids' => [id], 'on' => false }))
ok('area tag switched off', g.get_attribute('InteriorPro', 'area_on').nil?)

# ---- the tag survives a rotate / flip (update_sketches) ------------------
dlg.callbacks['set_sketch_area'].call(nil, JSON.generate({ 'ids' => [id], 'on' => true }))
dlg.callbacks['rename_sketch_area'].call(nil, JSON.generate({ 'id' => id, 'name' => 'Deck' }))
dlg.callbacks['update_sketches'].call(nil, JSON.generate(
  { 'shapes' => [{ 'id' => id, 'pts' => [0, 0, 60, 0, 60, 120, 0, 120] }] }))
ng = PE.send(:sketches_in_model).find { |x| x.valid? && x.get_attribute('InteriorPro', 'id') == id }
ok('the shape survived the transform', !ng.nil?)
ok('area tag carried through', ng && ng.get_attribute('InteriorPro', 'area_on') == true,
   ng && ng.get_attribute('InteriorPro', 'area_on'))
ok('area name carried through', ng && ng.get_attribute('InteriorPro', 'area_name') == 'Deck',
   ng && ng.get_attribute('InteriorPro', 'area_name'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

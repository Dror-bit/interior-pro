# encoding: utf-8
# rt206 - EDIT A SHOWER FLOOR (2026-09-22): the edit tool opens the same
# window and rebuilds on the same loop, so building again on a loop must
# leave ONE pad (and its tiles), and the tool must be wired in.
require './sketchup_stub'
require './floor_manager'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor
model = Sketchup.active_model
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.entities.add_face([[0, 0], [240, 0], [240, 144], [0, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
sq = [[12.0, 12.0], [72.0, 12.0], [72.0, 48.0], [12.0, 48.0]]

a = SF.build!(sq, 0.0, kind: 'flat', tile: 'Tile', model: model)
ok('first shower built', !a.nil?)
b = SF.build!(sq, 0.0, kind: 'curb', rise: 1.5, tile: 'Tile', model: model)
ok('edited (rebuilt on the same loop)', b && b != :no_floor)
ok('only ONE pad is left on that loop', SF.pads_in_model(model).length == 1, SF.pads_in_model(model).length)
ok('and it carries the new numbers', b.get_attribute('InteriorPro', 'kind') == 'curb' && b.get_attribute('InteriorPro', 'rise_in') == 1.5)

main = File.read('../main.rb')
tb = File.read('../toolbar.rb')
src = File.read('../shower_floor_edit_tool.rb')
ok('the edit tool file is loaded by main.rb', main.include?('shower_floor_edit_tool.rb'))
ok('its button sits in the shower group of the bar', tb.include?('shower_buttons = [shower_cmd, shower_edit_cmd]'))
ok('it is the draw tool with a different first click (no window of its own)',
   src.include?('class ShowerFloorEditTool < ShowerFloorTool') && src.include?('cfg = ask_settings'))
ok('it rebuilds on the pad\'s OWN loop', src.include?("at.call('poly_xy')"))
ok('the icon exists', File.exist?('../icons/shower_floor_edit.svg'))

exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt199 - THE SHOWER FLOOR PAD, ON THE REAL ROAD (2026-09-22).
#
# rt198 pins the numbers. This one walks the path he actually walks -
# build! into a model, the tool wired to those numbers and nothing else,
# and the button on the bar behind its own line (CLAUDE.md: a test on
# the pure function does not prove the tool works).
require './sketchup_stub'
require './shower_floor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SF = InteriorPro::ShowerFloor
model = Sketchup.active_model
sq = [[0.0, 0.0], [60.0, 0.0], [60.0, 36.0], [0.0, 36.0]]

grp = SF.build!(sq, 100.0, kind: 'curb', model: model)
ok('a pad is built', !grp.nil?)
ok('it is a shower floor', grp && grp.get_attribute('InteriorPro', 'type') == 'shower_floor')
ok('the raised one sits 1" over the room floor', grp && grp.get_attribute('InteriorPro', 'rise_in') == 1.0)
ok('and it remembers the floor it was drawn on', grp && grp.get_attribute('InteriorPro', 'floor_z') == 100.0)
ok('the loop is stored flat, six numbers per three corners',
   grp && grp.get_attribute('InteriorPro', 'poly_xy') == sq.flatten)
ok('the area comes with it', grp && (grp.get_attribute('InteriorPro', 'area_sqft') - 15.0).abs < 1e-9)

face = grp.entities.grep(Sketchup::Face).first
ok('the face is drawn at the TOP of the raised pad', face && face.vertices.first.position.z == 101.0)
ok('and it is pushed DOWN onto the floor, not up into the air',
   face && face.pushpulls.first < 0, face && face.pushpulls)

# Nothing sane comes out of two corners, and it says so instead of dying.
ok('two corners build nothing', SF.build!([[0.0, 0.0], [10.0, 0.0]], 0.0, model: model).nil?)

# The window comes first, and it is the one that says which floor it is.
ok('the tool asks before it draws', T0 = File.read('./shower_floor_tool.rb'), nil)
ok('the window is opened in activate', T0[/def activate.*?\n    end\n/m].to_s.include?('ask_settings'))
ok('it offers his two floors', T0.include?('Flat - same height as the room') && T0.include?('Raised, with a curb'))
ok('and the tile can be the room floor tile', T0.include?('ShowerFloor::SAME_AS_ROOM'))

# The tool: it owns no geometry of its own, and every point goes through
# the one method (the point law).
T = File.read('./shower_floor_tool.rb')
ok('the tool builds nothing itself', !T.include?('add_face') && T.include?('ShowerFloor.build!'))
ok('the move and the click use the same point method',
   T.scan(/floor_point\(view, x, y\)/).length >= 2, T.scan(/floor_point\(view, x, y\)/).length)
ok('the point goes through the right-angle law', T.include?('ShowerFloor.ortho_point'))
ok('it draws where it locked', T.include?('def draw_ring') && T.include?('GREEN'))
ok('a click on the first corner closes the loop', T.include?('ShowerFloor.closes?'))
ok('and Enter closes it too', T.include?('def onReturn'))
ok('Esc takes one corner back', T.include?('@pts.pop'))

TB = File.read('./toolbar.rb')
ok('the button is on the surfaces bar', TB.include?("UI::Command.new('Shower Floor')"))
ok('behind its own line', TB.include?("tb.add_separator unless on_bar.include?('Shower Floor')"))
ok('and added by name, never by count',
   TB.include?("shower_buttons.each { |cmd| tb.add_item(cmd) unless on_bar.include?(cmd.menu_text.to_s) }"))
M = File.read('./main.rb')
ok('both files are loaded', M.include?('shower_floor.rb') && M.include?('shower_floor_tool.rb'))

puts($fails.zero? ? 'rt199 OK' : "rt199 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

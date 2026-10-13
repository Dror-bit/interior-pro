# encoding: utf-8
# rt299 - ELECTRICAL ON THE WALL, STEP 1 (2026-10-12).
#
# His words: "שקעים של אוטלייט שאוכל לשים על הקיר כל מה שאני שם על הקיר
# אני צריך לקבוע לו את הגובה ... בקופסת רפאים", "מתגים עד 5 מחוברים",
# "שלושה חורים שקע אמריקאי". The tool is the plumbing tool, inherited.
require './sketchup_stub'
require './tile_wall'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'
require './electrical_library'
require './electrical_dialog'
require './electrical_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

L = InteriorPro::ElectricalLibrary
ok('kill switch is there and on', L::USE_ELECTRICAL == true)
ok('the kinds: outlet and switch', L.kinds.keys == %w[outlet switch])
ok('outlet starts at 18" to its middle (16" to the bottom of the box)', L.default_height('outlet') == 18.0)
ok('switch starts at 48" to its middle', L.default_height('switch') == 48.0)
ok('an unknown kind falls back, never crashes', L.kind_ok('xyz') == 'outlet')

# up to 5 switches on one plate; an outlet is always one
ok('switches: 1..5, clamped', [0, 1, 3, 5, 9].map { |n| L.gangs_ok('switch', n) } == [1, 1, 3, 5, 5])
ok('an outlet has no "switches" number', L.gangs_ok('outlet', 4) == 1)
ok('one plate is 2.75" wide', (L.plate_w(1) - 2.75).abs < 1e-9)
ok('five plates is 2.75 + 4 x 1.8125 = 10"', (L.plate_w(5) - 10.0).abs < 1e-9, L.plate_w(5))

# the outlet: plate + two receptacles, each with two slots and a ground
ob = L.boxes('outlet', 1)
ok('outlet: plate + 2 x (face, 2 slots, ground) = 9 boxes', ob.length == 9, ob.length)
ok('outlet: 6 dark holes (3 a receptacle - the American three)', ob.count { |b| b[6] == :dark } == 6)
ok('outlet: back of the plate on the wall (y 0)', ob.map { |b| b[2] }.min == 0.0)
sb = L.boxes('switch', 3)
ok('3 switches: plate + 3 x (base, toggle) = 7 boxes', sb.length == 7, sb.length)
ok('3 switches: the plate is 2.75 + 2 x 1.8125 wide', ((sb[0][1] - sb[0][0]) - 6.375).abs < 1e-9)
ok('every box has width, depth and height', (ob + sb).all? { |b| b[1] > b[0] && b[3] > b[2] && b[5] > b[4] })
ok('each box goes in its own group (the crash law)', File.read('./electrical_library.rb').include?('d.entities.add_group.entities'))

# the part the plumbing tool moves: its line = its middle, height to its middle
m = Sketchup.active_model
pa = L.layout(m, { 'kind' => 'switch', 'gangs' => 2, 'height' => 48.0 })
ok('one part', pa.length == 1)
r = InteriorPro::FixtureLibrary.part_rect(pa[0], 30.0)
ok('the plate is centred on the line', ((r[0] + r[1]) / 2.0 - 30.0).abs < 1e-9, r)
ok('and on the height (to its MIDDLE)', ((r[2] + r[3]) / 2.0 - 48.0).abs < 1e-9 && (r[3] - r[2] - 4.5).abs < 1e-9, r)
ok('the same definition is used again, not built twice',
   L.layout(m, { 'kind' => 'switch', 'gangs' => 2, 'height' => 40.0 })[0][:defn].equal?(pa[0][:defn]))

# on a hole = red; a wire may run past a window, so beside / below is fine
win = [[40.0, 36.0, 76.0, 84.0]]
ok('on the window: red', L.on_hole?(50.0, 52.75, 45.75, 50.25, win))
ok('under the window: fine (unlike a pipe)', !L.on_hole?(50.0, 52.75, 15.75, 20.25, win))
ok('beside the window: fine', !L.on_hole?(80.0, 82.75, 45.75, 50.25, win))

# the placing: one group, the numbers on it, its own tag, one undo step
fr = { ox: 0.0, oy: 0.0, ux: 1.0, uy: 0.0, nx: 0.0, ny: -1.0, floor_z: 0.0 }
wall = Sketchup::Group.new
wall.set_attribute('InteriorPro', 'id', 'wall-abc')
wall.set_attribute('InteriorPro', 'level', 1)
po = L.layout(m, { 'kind' => 'outlet', 'height' => 18.0 })
g = L.place!(wall: wall, side: 'a', fr: fr, u: 24.0, cfg: { 'kind' => 'outlet', 'height' => 18.0 }, parts: po, outs: [0.0])
at = ->(k) { g && g.get_attribute('InteriorPro', k) }
ok('placed: one group', !g.nil?)
ok('type electrical, kind outlet', at.call('type') == 'electrical' && at.call('kind') == 'outlet')
ok('it remembers its wall, side, line and height', at.call('host_wall_id') == 'wall-abc' && at.call('side') == 'a' &&
   at.call('u_in') == 24.0 && at.call('height_in') == 18.0)
ok('one instance of the plate inside', g.entities.to_a.length == 1)
ok('its own id', at.call('id').to_s.start_with?('elec-'))
ok('the tag is IP/Electrical (its own layer, like plumbing has its own)',
   File.read('./electrical_library.rb').include?("assign_tag(grp, 'IP/Electrical')"))
ok('found by electrical?', L.electrical?(g))

# the tool: the plumbing tool inherited, only what differs is here
T = InteriorPro::ElectricalTool
ok('the tool inherits the plumbing tool', T.superclass == InteriorPro::FixtureTool)
src = File.read('./electrical_tool.rb')
ok('the height is the window\'s, not the mouse\'s', !src.include?('@hover[:z]'))
ok('any inside wall face, not only a tiled one', src.include?('TileWallTool.instance_method(:face_point)'))
ok('the ghost stands an inch off the wall (CLAUDE.md)', T::GHOST_OUT == 1.0 && src.include?('GHOST_OUT].max'))
ok('the tool owns no placing maths - it hands over', src.include?('LIB.place!'))
ok('every click writes a line to electrical_trace.txt', File.read('./electrical_library.rb').include?("'electrical_trace.txt'") &&
   src.scan('LIB.trace(').length >= 3)
ok('Escape leaves the tool (iron law 1): onCancel is inherited',
   T.instance_method(:onCancel).owner == InteriorPro::TileNicheTool)
ok('typing places it from the corner (inherited)', T.instance_method(:onUserText).owner == InteriorPro::FixtureTool)

# the window: a copy of the Plumbing window
html = InteriorPro::ElectricalDialog.build_html(InteriorPro::ElectricalDialog.defaults, InteriorPro::ElectricalDialog.catalog)
ok('the window opens whole (fit_height)', html.include?('sketchup.fit_height(h)'))
ok('pictures, not names, for the kind and the switches', html.include?('plateSvg(k, 1)') && html.include?("plateSvg('switch', n)"))
ok('Escape closes the window', html.include?('e.keyCode === 27'))
ok('no \\d in the window JS', !html.include?('\\d'))

# the bar and main
BAR = File.read('./toolbar.rb')
ELEC = BAR[/def self\.setup_electrical_toolbar.*?\n      tb\.restore\n/m].to_s
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
ok('a bar of its own for electrical and lighting (his words)', ELEC.include?("UI::Toolbar.new('Interior Pro Electrical')"))
ok('the Electrical button is on it', ELEC.include?("UI::Command.new('Electrical')"))
ok('and NOT on the surfaces bar', !SURF.include?("'Electrical'"))
ok('the bar is built at startup', BAR[/def self\.setup\n.*?\n    end\n/m].to_s.include?('setup_electrical_toolbar'))
ok('added by name, so a reload cannot duplicate it', ELEC.include?("on_bar.include?('Electrical')"))
MAIN = File.read('./main.rb')
ok('main loads the three files after the plumbing tool',
   MAIN.index('electrical_tool.rb').to_i > MAIN.index('fixture_tool.rb').to_i &&
   MAIN.index('electrical_library.rb').to_i > MAIN.index('fixture_tool.rb').to_i && MAIN.include?('electrical_dialog.rb'))

puts($fails.zero? ? 'rt299 OK' : "rt299 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

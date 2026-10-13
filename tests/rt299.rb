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

InteriorPro.const_set(:PLUGIN_DIR, Dir.pwd) unless InteriorPro.const_defined?(:PLUGIN_DIR)
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

# THE LOOK (his picks): flat rocker switches, a smooth plate with no screws,
# the real US outlet (short slot, long slot, D-shaped ground)
ob = L.pieces('outlet', 1)
ok('outlet: plate + 2 x (face, short slot, long slot, ground) + one screw = 11 pieces', ob.length == 11, ob.length)
ok('outlet: 6 dark holes (3 a receptacle - the American three)', ob.count { |p| p.last == :dark } == 6)
ok('outlet: the plate is a loft - round corners, a curved edge (his words)', ob[0][0] == :loft && ob[0][1].length == 5 && ob[0][1].first[1].length == 20)
ok('outlet: the rings get smaller off the wall', ob[0][1].first[1].map(&:first).max > ob[0][1].last[1].map(&:first).max)
ok('outlet: back of the plate on the wall (y 0)', ob[0][1].first[0] == 0.0)
sl = ob.select { |p| p.last == :dark && p[1].length == 4 }.map { |p| p[1].map(&:last).max - p[1].map(&:last).min }
ok('outlet: one short slot and one long slot', sl.length == 4 && sl.map { |v| v.round(3) }.uniq.sort == [0.27, 0.33], sl)
ok('outlet: the ground is round on top (more than 4 points)', ob.select { |p| p.last == :dark }.any? { |p| p[1].length > 4 })
sb = L.pieces('switch', 3)
ok('3 switches: plate + 3 x (frame, rocker, 2 screws) = 19 pieces', sb.length == 19, sb.length)
pw = sb[0][1].first[1].map(&:first); ok('3 switches: the plate is 2.75 + 2 x 1.8125 wide', ((pw.max - pw.min) - 6.375).abs < 1e-9, pw.max - pw.min)
rk = sb.select { |p| p[0] == :slab && p[8] == :face }
ok('rockers are flat paddles, 1.2" x 2.5" (Decora)', rk.length == 3 && rk.all? { |p| ((p[2] - p[1]) - 1.2).abs < 1e-9 && ((p[4] - p[3]) - 2.5).abs < 1e-9 }, rk.length)
ok('the rocker is TILTED as in his photo: bottom out, top in', rk.all? { |p| p[9] && p[6] > p[9] + 0.1 })
src_lib = File.read('./electrical_library.rb')
ok('the curved edge is softened, not stepped', src_lib.include?('e.soft = true') && src_lib.include?('e.smooth = true'))
ok('screws as in his photo: two a switch, one on the outlet', sb.count { |p| p[0] == :prism && p[1].length == 12 } == 6 && ob.count { |p| p[0] == :prism && p[1].length == 12 } == 1)
ok('a new name for the new look, so the old plates in his model do not win', L.def_name('outlet', 1) == 'InteriorPro_Elec4_outlet')
ok('each piece goes in its own group (the crash law)', src_lib.include?('ents = d.entities.add_group.entities'))
ok('both sides painted, never the default blue', src_lib.include?('fc.back_material = mat'))
ok('the round corner outline closes right', L.round_rect(0, 0, 1.24, 1.32, 0.5).length == 20)

# HIS OWN FILES (his words: "תפתח תיקיה שאליה אני יעלה את המוצרים")
ok('a folder a kind: assets/ELECTRICAL/OUTLETS and SWITCHES', L.dir_for('outlet').end_with?(File.join('ELECTRICAL', 'OUTLETS')) && L.dir_for('switch').end_with?(File.join('ELECTRICAL', 'SWITCHES')))
ok('an empty folder shows the stand-in, so the window is never empty', L.products('outlet') == [L::SIMPLE])
ok('a file gets its own definition name, the stand-in keeps the look name', L.def_name('outlet', 1, 'Leviton') == 'InteriorPro_Elec_outlet_Leviton' && L.def_name('outlet', 1, L::SIMPLE) == L.def_name('outlet', 1))
ok('Add new and Save selected go through the plumbing helpers (clean name, hidden things left out)', File.read('./electrical_library.rb').include?('FixtureLibrary.clean_name') && File.read('./electrical_library.rb').include?('FixtureLibrary.strip_hidden!'))
ok('his file: back on the wall, middle of width on the line, middle of height at the height', File.read('./electrical_library.rb').include?('ax = (minx + maxx) / 2.0') && File.read('./electrical_library.rb').include?('az = (minz + maxz) / 2.0'))

# the part the plumbing tool moves: its line = its middle, height to its middle
m = Sketchup.active_model
pa = L.layout(m, { 'kind' => 'switch', 'gangs' => 2, 'height' => 48.0, 'product' => L::SIMPLE })
ok('one part', pa.length == 1)
r = InteriorPro::FixtureLibrary.part_rect(pa[0], 30.0)
ok('the plate is centred on the line', ((r[0] + r[1]) / 2.0 - 30.0).abs < 1e-9, r)
ok('and on the height (to its MIDDLE)', ((r[2] + r[3]) / 2.0 - 48.0).abs < 1e-9 && (r[3] - r[2] - 4.5).abs < 1e-9, r)
ok('the same definition is used again, not built twice',
   L.layout(m, { 'kind' => 'switch', 'gangs' => 2, 'height' => 40.0, 'product' => L::SIMPLE })[0][:defn].equal?(pa[0][:defn]))

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
po = L.layout(m, { 'kind' => 'outlet', 'height' => 18.0, 'product' => L::SIMPLE })
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
ok('his products with pictures, Add new and Save selected (the plumbing window, copied)', html.include?('prodGrid') && html.include?('sketchup.add_new') && html.include?('sketchup.save_selected'))
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

# THE PICTURE STRAIGHT FROM THE FRONT (his words: "למה התמונות שלהם מופיעות באלכסון?")
ok('front picture: kill switch on, the picture is an .svg', L::USE_FRONT_THUMB == true && L.thumb_path('switch', 'Rocker 1').end_with?('thumbs/Rocker 1.svg'))
sq = [[[-1.0, -2.0], [1.0, -2.0]], [[1.0, -2.0], [1.0, 2.0]], [[1.0, 2.0], [-1.0, 2.0]], [[-1.0, 2.0], [-1.0, -2.0]]]
sv = L.front_svg(sq + [[[1.0, -2.0], [-1.0, -2.0]], [[0.5, 0.5], [0.5, 0.5]]])
ok('front picture: the same line twice is drawn once, a line seen end-on is dropped', sv.scan('M').length == 4, sv.scan('M').length)
ok('front picture: up is up (blue +2 is at the top: svg y -2)', sv.include?('L1.0 -2.0') || sv.include?('M1.0 -2.0'), sv)
ok('front picture: the frame holds the whole plate', sv.include?('viewBox="-1.2 -2.2 2.4 4.4"'), sv[/viewBox="[^"]*"/])
SRC2 = File.read('./electrical_library.rb')
ok('front picture: soft / smooth / hidden edges are left out', SRC2.include?('next if e.soft? || e.smooth?') && SRC2[/def self\.front_segments.*?\n    end\n/m].to_s.include?('hidden?'))
ok('front picture: drawn again when his .skp is newer', SRC2.include?('File.mtime(tp) >= File.mtime(src)'))

# LYING DOWN (his list "לרוחב", his pick "2": an arrow key turns the ghost)
ok('turn: kill switch on', L::USE_TURN == true)
ok('turn: only an outlet turns', L.turn_of({ 'kind' => 'outlet', 'turn' => 90 }) == 90 && L.turn_of({ 'kind' => 'switch', 'turn' => 90 }) == 0)
ok('turn: anything but 90 is standing', L.turn_of({ 'kind' => 'outlet', 'turn' => 45 }) == 0 && L.turn_of({ 'kind' => 'outlet' }) == 0)
pt90 = L.layout(m, { 'kind' => 'outlet', 'height' => 18.0, 'product' => L::SIMPLE, 'turn' => 90 })
rt = InteriorPro::FixtureLibrary.part_rect(pt90[0], 30.0)
ok('turn: lying, the plate is 4.5" along the wall and 2.75" up', ((rt[1] - rt[0]) - 4.5).abs < 1e-9 && ((rt[3] - rt[2]) - 2.75).abs < 1e-9, rt)
ok('turn: still centred on the line and on the height', ((rt[0] + rt[1]) / 2.0 - 30.0).abs < 1e-9 && ((rt[2] + rt[3]) / 2.0 - 18.0).abs < 1e-9, rt)
ok('turn: placed with a quarter turn about the line out of the wall', File.read('./electrical_library.rb').include?('rotation(ORIGIN, Y_AXIS, 90.degrees) * shift if p[:turn].to_i == 90'))
ok('turn: saved on what is placed (0 when standing)', at.call('turn') == 0)
DS = File.read('./electrical_dialog.rb')
ok('turn: chosen in the window, Vertical / Horizontal, outlet only', DS.include?("'Vertical', 'pickTurn(0)'") && DS.include?("'Horizontal', 'pickTurn(90)'") && DS.include?("kind === 'outlet' ? '' : 'none'"))
ok('turn: the window starts Vertical and sends 0 or 90 only', InteriorPro::ElectricalDialog.defaults['turn'] == 0 && DS.include?("cfg['turn'] = cfg['turn'].to_i == 90 ? 90 : 0"))
ok('turn: one way only - no arrow keys in the tool', !File.read('./electrical_tool.rb').include?('def onKeyDown'))
tl = InteriorPro::ElectricalTool.new({ 'kind' => 'outlet', 'height' => 18.0, 'product' => L::SIMPLE, 'turn' => 90 })
tl.setup_size!
pp1 = tl.instance_variable_get(:@parts)[0]
ok('turn: Horizontal from the window = the ghost lies (4.5" along the wall)', ((pp1[:maxx] - pp1[:minx]) - 4.5).abs < 1e-9, pp1[:maxx] - pp1[:minx])

puts($fails.zero? ? 'rt299 OK' : "rt299 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

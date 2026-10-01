# encoding: utf-8
# rt222 - PLUMBING, STEP 1 (2026-09-25).
#
# His words: "המקלחת תופיע בגובה שיקבע מראש ... היא תזוז רק על הגובה
# שאני אגדיר ... שאפשרי לקבוע לה כמה היא תהיה רחוקה מהפינה". And the
# products are .skp files in a folder, with "Add new" for his own.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

L = InteriorPro::FixtureLibrary
ok('kill switch is there and on', L::USE_FIXTURES == true)
ok('the kinds: shower SET, toilet, vanity, tub', L.kinds.keys == %w[shower_set toilet vanity tub])
ok('shower head starts at 80"', L.default_height('shower_set') == 80.0)
ok('toilet sits on the floor', L.default_height('toilet') == 0.0)
ok('an unknown kind falls back, never crashes', L.kind_ok('xyz') == 'shower_set')

# typed distance: from the NEARER corner to the MIDDLE
ok('mouse near the start: 18" from the start corner', L.u_from_corner(18, 2.0, 70.0, 10.0) == 20.0)
ok('mouse near the far end: 18" from the far corner', L.u_from_corner(18, 2.0, 70.0, 60.0) == 52.0)
ok('the tooltip reads the nearer corner', L.corner_dist(20.0, 2.0, 70.0) == 18.0)
ok('and from the other side too', L.corner_dist(52.0, 2.0, 70.0) == 18.0)

# his own files: a safe name, never over an existing one
ok('odd characters are dropped', L.clean_name('Kohler "Rain" #3') == 'Kohler Rain 3')
ok('a clash gets a number', L.clean_name('Toto', %w[Toto]) == 'Toto 2')
ok('the stand-in name is never taken', L.clean_name('Simple', [L::SIMPLE]) == 'Simple 2')

# the tool is the niche tool, inherited - the point law comes with it
T = InteriorPro::FixtureTool
ok('the tool inherits the niche tool', T.superclass == InteriorPro::TileNicheTool)
src = File.read('./fixture_tool.rb')
ok('the height is the window\'s, not the mouse\'s', !src.include?('@hover[:z]'))
ok('every point comes through face_point', src.scan('= face_point(view, x, y)').length == 2)
ok('typing places it from the corner', src.include?('FixtureLibrary.u_from_corner'))
ok('the tool owns no placing maths - it hands over', src.include?('FixtureLibrary.place!'))
lib = File.read('./fixture_library.rb')
ok('each stand-in box in its own group (the crash law)', lib.include?('d.entities.add_group.entities'))
ok('back on the wall, height to the anchor point', lib.include?('Geom::Vector3d.new(-p[:ax], -p[:miny], -p[:az])'))

# the bar
BAR = File.read('./toolbar.rb')
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
ok('Plumbing is on the surfaces bar', SURF.include?("UI::Command.new('Plumbing')"))
ok('on the END, after Split Tile', SURF.index("'Plumbing'").to_i > SURF.index("tb.add_item(tile_split_cmd)").to_i)
ok('added by name, so a reload cannot duplicate it', SURF.include?("on_bar.include?('Plumbing')") && SURF.include?('on_bar.include?(cmd.menu_text.to_s)'))
MAIN = File.read('./main.rb')
ok('main loads the three files after the niche tool',
   MAIN.index('fixture_tool.rb').to_i > MAIN.index('tile_niche_tool.rb').to_i && MAIN.include?('fixture_dialog.rb'))

puts($fails.zero? ? 'rt222 OK' : "rt222 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

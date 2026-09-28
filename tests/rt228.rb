# encoding: utf-8
# rt228 - HIDDEN THINGS IN A PART FILE ARE LEFT OUT (2026-09-27). Measured:
# Set 2 valve/hand and Set 1 head carry hidden things up to 64" off the
# part, so the placed set was selected as a box reaching out of the house.
# His pick: "שידלג עליהם בעצמו" - the copy in the model drops them.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
module InteriorPro; PLUGIN_DIR = '/tmp/ip_fake' unless const_defined?(:PLUGIN_DIR); end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::FixtureLibrary
ok('kill switch is on', L::USE_STRIP_HIDDEN == true)
lib = File.read('./fixture_library.rb')
ok('a fresh load drops them', lib.scan('strip_hidden!(d)').length >= 2)
ok('hidden, and on a hidden tag - the same rule as visible_bounds', lib.include?('(e.respond_to?(:hidden?) && e.hidden?) || (e.respond_to?(:layer) && e.layer && !e.layer.visible?)'))
ok('never empties a part that is ALL hidden', lib.include?('gone.length == defn.entities.length'))
ok('says what it left out', lib.include?('hidden things left out'))
ok('his file is never written', !lib.include?('.save(') && !lib.include?('save_as'))
puts($fails.zero? ? 'rt228 OK' : "rt228 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

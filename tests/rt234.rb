# encoding: utf-8
# rt234 - A TOILET FACES THE ROOM (2026-09-30). His words: "האסלה הפוכה
# והכיוון של הפנים שלה פונה כרגע לקיר". All three of his toilet files are
# drawn with the tank at +green; they are turned half a turn before placing.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'
module InteriorPro; PLUGIN_DIR = '/tmp/ip_fake' unless const_defined?(:PLUGIN_DIR); end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

L = InteriorPro::FixtureLibrary
ok('a toilet file is turned', L.turn_front?('toilet', 'TOTO-Nexus'))
ok('the stand-in is not turned', !L.turn_front?('toilet', L::SIMPLE))
%w[tub vanity shower_set].each { |k| ok("#{k} is not turned", !L.turn_front?(k, 'X')) }
# TOTO measured: x -9.09..8.43, y -29.37..0 (tank at y 0)
t = L.turned_box(-9.09, 8.43, -29.37, 0.0, -0.33)
ok('after the turn the tank is the back (lowest green)', t[2] == -0.0 && t[3] == 29.37, t)
ok('the width stays the same', (t[1] - t[0] - 17.52).abs < 1e-9, t)
ok('the middle turns with it', t[4] == 0.33, t)
L.send(:remove_const, :USE_TURN_FRONT)
L.const_set(:USE_TURN_FRONT, false)
ok('switch off = not turned', !L.turn_front?('toilet', 'TOTO-Nexus'))
exit($fails.zero? ? 0 : 1)

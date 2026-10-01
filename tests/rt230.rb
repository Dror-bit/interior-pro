# encoding: utf-8
# rt230 - VANITY AND TUB (2026-09-29). His words: "אני רוצה את הוונטי
# בנפרד ואז לשמור אותו ולהכניס אותו ... ספרייה של וונטיס ואמבטיות".
# Two new single-file kinds, placed exactly like a toilet.
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
%w[vanity tub].each do |k|
  ok("#{k} is a kind", L.kinds.key?(k))
  ok("#{k} stands on the floor", L.default_height(k) == 0.0)
  ok("#{k} is one file, not a set", !L.set_kind?(k))
  ok("#{k} is not tied to tile", !L.on_tile?(k))
  ok("#{k} has a stand-in", !L.simple_boxes(k, nil).empty?)
end
ok('a vanity file lives in VANITIES', L.file_for('vanity', 'Oak 36').end_with?('VANITIES/Oak 36.skp'))
ok('a tub file lives in TUBS', L.file_for('tub', 'Alcove 60').end_with?('TUBS/Alcove 60.skp'))
ok('a vanity sits on its bottom middle', L.anchor_xz(-15, 15, 0, 34, false) == [0.0, 0.0])
ok('the toilet did not change', L.simple_boxes('toilet', nil).length == 2)
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt238 - NO 'Simple' NEXT TO HIS OWN PRODUCTS (2026-10-01). His words:
# "תוריד את הסאמפלים מכל האופציות". Only while a kind has no file yet.
require 'fileutils'
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
module InteriorPro; PLUGIN_DIR = '/tmp/ip_fake238' unless const_defined?(:PLUGIN_DIR); end
$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::FixtureLibrary
FileUtils.rm_rf(InteriorPro::PLUGIN_DIR)
ok('an empty kind still shows Simple', L.products('vanity') == [L::SIMPLE], L.products('vanity'))
FileUtils.mkdir_p(L.dir_for('tub'))
File.write(File.join(L.dir_for('tub'), 'Alcove tub.skp'), 'x')
ok('a kind with his own file: no Simple', L.products('tub') == ['Alcove tub'], L.products('tub'))
FileUtils.rm_rf(InteriorPro::PLUGIN_DIR)
exit($fails.zero? ? 0 : 1)

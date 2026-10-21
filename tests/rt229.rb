# encoding: utf-8
# rt229 - A SET WITH COLOURS (2026-09-28). His words: "אני לא רוצה שיהיו
# סטים לכל צבע אלא אני בוחר את הסט ואז אני יכול לבחור את הצבע של הסט".
# SHOWER SETS/<set>/<colour>/head.skp ... ; a flat set folder still works.
require 'fileutils'
require 'tmpdir'
require 'json'
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_dialog'
module InteriorPro; PLUGIN_DIR = Dir.mktmpdir('interior-pro-rt229-') unless const_defined?(:PLUGIN_DIR); end
raise 'Unexpected temporary fixture root' unless File.expand_path(InteriorPro::PLUGIN_DIR).start_with?(File.expand_path(Dir.tmpdir) + File::SEPARATOR)

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::FixtureLibrary
dir = L.dir_for('shower_set')
FileUtils.rm_rf(dir)
{ 'Set 1/Black' => %w[head valve hand], 'Set 1/Brushed Nickel' => %w[head hand], 'Old Flat' => %w[head],
  'Empty/Nothing' => [] }.each do |path, parts|
  FileUtils.mkdir_p(File.join(dir, path))
  parts.each { |p| File.write(File.join(dir, path, "#{p}.skp"), 'x') }
end
n = L.names('shower_set')
ok('a colour folder is "set/colour"; a flat set is as before; an empty one is not listed',
   n == ['Old Flat', 'Set 1/Black', 'Set 1/Brushed Nickel'], n)
ok('a colour part file lives at <set>/<colour>/<part>.skp',
   L.file_for('shower_set', 'Set 1/Black', 'hand').end_with?('SHOWER SETS/Set 1/Black/hand.skp'))
ok('each colour knows its own parts', L.parts_available('shower_set', 'Set 1/Brushed Nickel') == %w[head hand])
ok('the picture is the colour\'s own', L.thumb_path('shower_set', 'Set 1/Black').end_with?('Set 1/Black/thumb.png'))
dn = L.def_name('shower_set', 'Set 1/Black', 'hand')
ok('a definition name has no slash', dn == 'InteriorPro_Fixture_shower_set_Set 1 - Black_hand', dn)
ok('an old flat name keeps its old definition name (placed sets still edit)',
   L.def_name('shower_set', 'Set 2 Black Light', 'hand') == 'InteriorPro_Fixture_shower_set_Set 2 Black Light_hand')
ok('a set with colours has its own picture next to them', L.set_thumb_path('shower_set', 'Set 1/Black').end_with?('SHOWER SETS/Set 1/thumb.png'))
ok('a flat set has no separate set picture', L.set_thumb_path('shower_set', 'Old Flat').nil?)
FileUtils.rm_rf(dir)

dl = File.read('./fixture_dialog.rb')
ok('the window has a Color row', dl.include?('id="colorGrid"'))
ok('the sets show once each', dl.include?('function setNames()'))
ok('the set card shows the set picture when there is one', dl.include?('shown.set_img ?'))
ok('another colour of the same set keeps his heights', dl.include?('if (setOf(n) !== setOf(product)) parts = null;'))
ok('no \\d in the window JS (the heredoc law)', !dl.include?('\\d'))
html = InteriorPro::FixtureDialog.build_html({ 'kind' => 'shower_set', 'product' => 'Set 1/Black', 'height' => 80 },
                                             { 'shower_set' => { 'label' => 'Shower set', 'height' => 80, 'set' => true, 'dir' => '',
                                                                 'products' => [] } })
js = html.scan(%r{<script>(.*?)</script>}m).map(&:first).join("\n")
js_path = File.join(InteriorPro::PLUGIN_DIR, 'rt229.js')
File.write(js_path, js)
ok('the window JS parses', system('node', '--check', js_path))
FileUtils.remove_entry(InteriorPro::PLUGIN_DIR)
puts($fails.zero? ? 'rt229 OK' : "rt229 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

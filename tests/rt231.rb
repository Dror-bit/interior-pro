# encoding: utf-8
# rt231 - THE TUB SPOUT STARTS OFF (2026-09-29). A set that HAS a spout
# file still opens with it unticked; the other parts it has are on.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'
require 'tmpdir'
require 'fileutils'
$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
root = Dir.mktmpdir
module InteriorPro; end
InteriorPro.send(:remove_const, :PLUGIN_DIR) if InteriorPro.const_defined?(:PLUGIN_DIR)
InteriorPro.const_set(:PLUGIN_DIR, root)
L = InteriorPro::FixtureLibrary
dir = File.join(root, 'assets', 'PLUMBING', 'SHOWER SETS', 'Tub Set', 'Black')
FileUtils.mkdir_p(dir)
%w[head valve spout].each { |p| File.write(File.join(dir, "#{p}.skp"), 'x') }
n = 'Tub Set/Black'
ok('the set is found with its colour', L.names('shower_set').include?(n), L.names('shower_set'))
ok('it has a spout file', L.parts_available('shower_set', n).include?('spout'))
d = L.default_parts('shower_set', n)
ok('the spout starts OFF', d['spout']['on'] == false, d)
ok('head and valve start on', d['head']['on'] && d['valve']['on'], d)
ok('no hand file = hand off', d['hand']['on'] == false, d)
ok('the stand-in still starts with the spout off', L.default_parts('shower_set', L::SIMPLE)['spout']['on'] == false)
FileUtils.rm_rf(root)
puts($fails.zero? ? 'rt231 OK' : "rt231 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

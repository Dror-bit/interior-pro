# encoding: utf-8
# rt225 - SHOWER SETS (2026-09-25). His words: "אני רוצה שיהיו לי סטים ...
# אם אני פותח את הסט אני יכול להגדיר בו את הגובה של כל אחד מהאלמנטים ...
# כל השער בקו אחד". Heights are to the pipe point = the file's ORIGIN
# (his pick "2"), the box middle when the origin is nowhere near.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'
require './fixture_dialog'
module InteriorPro; PLUGIN_DIR = '/tmp/ip_fake' unless const_defined?(:PLUGIN_DIR); end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::FixtureLibrary
ok('four parts with fixed file names', L.part_keys == %w[head valve hand spout])
sp = L.parts_spec.to_h { |k, _l, h, s| [k, [h, s]] }
ok('head 80, valve 48, hand 60 and 12" to the side, spout 22',
   sp == { 'head' => [80.0, 0.0], 'valve' => [48.0, 0.0], 'hand' => [60.0, 12.0], 'spout' => [22.0, 0.0] }, sp)
ok('the stand-in set has all four', L.parts_available('shower_set', 'Simple') == L.part_keys)
d = L.default_parts('shower_set', 'Simple')
ok('the stand-in starts with the tub spout off', d['spout']['on'] == false && d['head']['on'])
ok('a part file lives at <set>/<part>.skp', L.file_for('shower_set', 'Delta', 'head').end_with?('SHOWER SETS/Delta/head.skp'))
ok('a toilet is still one file', L.file_for('toilet', 'Toto').end_with?('TOILETS/Toto.skp'))

# the anchor
ok('prepared file: the origin is the pipe point', L.anchor_xz(-3, 3, -2, 5, true) == [0.0, 0.0])
ok('origin a hair off the part still counts', L.anchor_xz(0.5, 6, 0.5, 5, true) == [0.0, 0.0])
ok('origin far away: the middle of the box', L.anchor_xz(20, 26, 40, 50, true) == [23.0, 45.0])
ok('a toilet sits on its bottom middle', L.anchor_xz(-9, 9, 0, 30, false) == [0.0, 0.0])

# one line, each part its own height and sideways
p = { du: 12.0, h: 60.0, ax: 0.0, az: 0.0, minx: -1.5, maxx: 1.5, minz: -12.0, maxz: 12.0 }
ok('a part sits on the line + its sideways, at its height', L.part_rect(p, 40.0) == [50.5, 53.5, 48.0, 72.0])

src = File.read('./fixture_tool.rb')
ok('the ghost draws every part', src.include?('@parts.each_with_index'))
ok('the line of the set is drawn', src.include?('the one line the whole set stands on'))
lib = File.read('./fixture_library.rb')
ok('ONE group per placed set, one instance per part', lib.include?('grp.entities.add_instance(p[:defn], face * shift)'))
ok('the window numbers are kept on it for the edit', lib.include?("'cfg_json' => keep.to_json"))
ok('each stand-in box in its own group (the crash law)', lib.include?('d.entities.add_group.entities'))
dl = File.read('./fixture_dialog.rb')
ok('a new set = the folder opens, he fills it himself', dl.include?('UI.openURL'))
ok('a part with no file cannot be ticked', dl.include?("(no file)"))
ok('a new set starts from its own defaults', dl.include?('if (n !== product) parts = null;'))
ok('no \\d in the window JS (the heredoc law)', !dl.include?('\\d'))

ok('hidden specks do not make the box (his head.skp, measured)', lib.include?('b = visible_bounds(d)') && lib.include?('e.hidden?'))
puts($fails.zero? ? 'rt225 OK' : "rt225 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

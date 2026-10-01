# encoding: utf-8
# rt237 - THE DECK OF A DROP-IN TUB (2026-10-01). His words: tile on the
# front and on top, level with the tub; front 3" past the tub, the other
# sides 0, each typed by hand. Tile like the wall's.
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
ok('the drop-in tub gets a deck', L.deck?('tub', "Drop‑in tub") && L.deck?('tub', 'Drop-in tub'))
ok('free standing does not', !L.deck?('tub', 'Free standing Woodbridge'))
ok('alcove gets sides only: no front, both sides 0', L.deck?('tub', 'Alcove tub') && !L.deck_front?('Alcove tub') &&
   L.deck_sides({ 'product' => 'Alcove tub', 'deck_front' => 5 }) == [0.0, 0.0, 0.0])
ok('alcove sides typed', L.deck_sides({ 'product' => 'Alcove tub', 'deck_left' => 4 }) == [0.0, 4.0, 0.0])
ok('a toilet never does', !L.deck?('toilet', 'Drop'))
ok('drop-in starts on the wall (the back of the deck = From the wall)', L.wall_gap('tub', { 'product' => 'Drop-in tub' }) == 0.0)
ok('defaults: front 3, left 0, right 0', L.deck_sides({}) == [3.0, 0.0, 0.0])
ok('typed numbers win, never below 0', L.deck_sides({ 'deck_front' => 5, 'deck_left' => 2, 'deck_right' => -1 }) == [5.0, 2.0, 0.0])
ok('side a: left is +u (hi)', L.deck_lo_hi('a', 2.0, 7.0) == [7.0, 2.0])
ok('side b: left is -u (lo)', L.deck_lo_hi('b', 2.0, 7.0) == [2.0, 7.0])
# his Drop-in tub measured: 60 x 30 x 17.95, on the wall, line at u 100, 0.625 tile
p = { du: 0.0, h: 0.0, ax: 0.0, az: 0.0, minx: -30.0, maxx: 30.0, miny: -15.0, maxy: 15.0, minz: 0.0, maxz: 17.95 }
d = L.deck_box(p, 100.0, 0.0, 3.0, 0.0, 0.0, 0.625)
ok('the deck is the tub wide (sides 0)', d[:u0] == 70.0 && d[:u1] == 130.0, d)
ok('from the wall to 3" in front of the tub', d[:o0] == 0.0 && d[:o1] == 33.0, d)
ok('the body under the tile, so the tile is level with the tub', (d[:h] + 0.625 - 17.95).abs < 1e-9, d)
ok('the hole is the tub', d[:tub] == [70.0, 130.0, 0.0, 30.0], d)
st = L.deck_strips(d)
ok('only the front strip is built when the other sides are 0', st == [[70.0, 130.0, 30.0, 33.0]], st)
d2 = L.deck_box(p, 100.0, 4.0, 3.0, 2.0, 1.0)
ok('back, both ends and front when all are set', L.deck_strips(d2).length == 4, L.deck_strips(d2))
ok('the deck joints run on from the wall', L.grid_phase(1.5, -2.25, 67.0) == [-65.5, -2.25])
src = File.read('./fixture_library.rb')
ok('the front and the top both tiled', src.include?('build_deck_front_tile!(gf.entities') && src.include?('build_deck_top_tile!(gt.entities'))
ok('the top runs over the front tile edge', src.include?("d[:o1] + (nf > 0 ? sp[:dp] : 0.0)"))
ok('the front edge is cut at 45 degrees', src.include?('miter_deck_edge!(gf, gt, fr, d, sp[:dp])') && src.include?('ht = d[:h] + (miter_on?(sp) ? sp[:dp] : 0.0)'))
dc = L.clamp_deck(L.deck_box(p, 100.0, 0.0, 3.0, 20.0, 20.0), 66.4, 131.0)
ok('typed 20" past each end stops at the side walls\' tile', dc[:u0] == 66.4 && dc[:u1] == 131.0, dc)
ok('the strips follow the clipped ends', L.deck_strips(dc).map { |x| x[0..1] }.include?([66.4, 70.0]), L.deck_strips(dc))
ok('the deck is clipped before it is built', src.include?('dk = clamp_deck(dk, lim_lo, lim_hi)'))
da = L.deck_box(p, 100.0, 0.0, 0.0, 4.0, 0.0)
ok('alcove with a left side: its front face is just that side', L.deck_front_spans(da) == [[66.0, 70.0]], L.deck_front_spans(da))
ok('drop-in: one front face the deck wide', L.deck_front_spans(d) == [[70.0, 130.0]], L.deck_front_spans(d))
ok('no front strip: the top never runs out over the tub', src.include?('d[:front] > 0.01 ? to1 : [to1, o_end].max'))
ok('0 on the low side: the tub goes to the low wall', L.snap_deck_u(184.52, 154.52, 214.52, 150.04, 230.0, 0.0, 20.0) == 180.04)
ok('0 on the high side: the tub goes to the high wall', L.snap_deck_u(184.52, 154.52, 214.52, 150.04, 230.0, 20.0, 0.0) == 200.0)
ok('both 0 or both set: it stays where clicked', L.snap_deck_u(184.52, 154.52, 214.52, 150.04, 230.0, 0.0, 0.0) == 184.52 &&
   L.snap_deck_u(184.52, 154.52, 214.52, 150.04, 230.0, 3.0, 3.0) == 184.52)
ok('placing snaps before the tub is put down', src.include?('u = snap_to_side_wall(wall, side, fr, u, cfg, parts, outs)'))
L.send(:remove_const, :USE_DECK)
L.const_set(:USE_DECK, false)
ok('switch off = no deck', !L.deck?('tub', 'Drop-in tub'))
exit($fails.zero? ? 0 : 1)

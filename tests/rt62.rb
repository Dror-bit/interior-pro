# encoding: utf-8
# rt62 - fence_math: rails, caps, and the four ways to fill a bay.
#
# Added 2026-08-16, when six real fences were measured and every single one of
# them turned out to have a rail along the bottom and a rail along the top with
# the infill between. Everything checked here is pure arithmetic, so it is
# proved in the cloud before a line of it goes near the model.
#
# The claim this suite exists to defend, above all the others:
#
#   WITH RAILS OFF, THE NUMBERS ARE BIT FOR BIT WHAT THEY WERE BEFORE.
#
# That is what lets rt56 and rt57 stay honest instead of being rewritten to
# agree with whatever the new code happens to do.
require './sketchup_stub'
require './fence_math'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

FM = InteriorPro::Landscape::FenceMath

def flat_bay(len = 240.0, height = 72.0)
  FM.layout(0, 0, len, 0, height: height, max_spacing: 96.0)[:bays].first
end

# ------------------------------------------------------------ nothing changed

lay = FM.layout(0, 0, 240, 0, height: 72.0)
bay = lay[:bays].first
ok('with no rails asked for, there are none', FM.bay_rails(bay, {}).empty?)
zone = FM.infill_zone(bay, {})
ok('with no rails, the infill is the WHOLE bay',
   close(zone[:z0], bay[:z_bottom0]) && close(zone[:z0_top], bay[:z_top0]),
   [zone[:z0], zone[:z0_top]])
ok('with no rails, the zone is the full height', close(zone[:height], 72.0), zone[:height])

old = FM.board_runs(bay, 5.5, 0.0, 4.0)
new_pieces = FM.bay_infill(bay, infill: 'boards', board_width: 5.5,
                                board_gap: 0.0, post_size: 4.0)
ok('with no rails, the boards land exactly where they always did',
   new_pieces.map { |p| [p[:t0].round(9), p[:t1].round(9)] } ==
     old.map { |(a, b)| [a.round(9), b.round(9)] },
   [new_pieces.length, old.length])
ok('and they still reach the top of the fence',
   new_pieces.all? { |p| close(p[:z0_top], 72.0) },
   new_pieces.map { |p| p[:z0_top] }.uniq)

# ------------------------------------------------------------------- fill vs gap

# fill_runs shaves the board so the gap stays. Right for a privacy fence.
runs = FM.fill_runs(68.0, 5.5, 0.0)
ok('fill_runs covers the whole span', close(runs.last[1] - runs.first[0], 68.0),
   runs.last[1] - runs.first[0])
ok('fill_runs never makes a board wider than asked',
   runs.all? { |(a, b)| (b - a) <= 5.5 + 1e-9 },
   runs.map { |(a, b)| (b - a).round(4) }.uniq)

# gap_runs keeps the board and shares out the gap. Right for anything you can
# see through. Measured on the real iron fence: 1/2" bar, never 0.31".
runs = FM.gap_runs(70.5, 0.5, 3.38)
ok('gap_runs keeps the bar at exactly the width asked for',
   runs.all? { |(a, b)| close(b - a, 0.5) },
   runs.map { |(a, b)| (b - a).round(4) }.uniq)
gaps = (1...runs.length).map { |i| (runs[i][0] - runs[i - 1][1]).round(6) }
ok('gap_runs spaces them evenly', gaps.uniq.length == 1, gaps.uniq)
ok('gap_runs leaves a gap at each end too',
   runs.first[0] > 0 && close(runs.first[0], gaps.first, 1e-6),
   [runs.first[0], gaps.first])
ok('the real iron fence comes out near its measured 3.88 pitch',
   (runs[1][0] - runs[0][0]) > 3.5 && (runs[1][0] - runs[0][0]) < 4.3,
   runs[1][0] - runs[0][0])
ok('a bar too wide for the span builds nothing', FM.gap_runs(2.0, 5.0, 1.0).empty?)
ok('one bar that just fits still builds', FM.gap_runs(5.0, 5.0, 1.0).length == 1)

# The bug that fill_runs would have caused, kept as a test: a 3/4" bar at a 4"
# gap divided down to 0.43" and was thrown away as a splinter, so an iron
# fence came out as bare posts. gap_runs cannot do that.
ok('a thin bar at a wide gap is NOT thrown away',
   FM.gap_runs(58.0, 0.75, 4.0).length > 8, FM.gap_runs(58.0, 0.75, 4.0).length)

# ----------------------------------------------------------------- the rails

opts = { rail_count: 2, rail_height: 3.5, rail_bottom_z: 2.0, post_extra: 2.0 }
rails = FM.bay_rails(bay, opts)
ok('two rails asked for, two rails given', rails.length == 2, rails.length)
bot = rails.find { |r| r[:kind] == 'bottom' }
top = rails.find { |r| r[:kind] == 'top' }
ok('the bottom rail starts where it was told to', close(bot[:z0], 2.0), bot[:z0])
ok('the bottom rail is as tall as it was told to be',
   close(bot[:z0_top] - bot[:z0], 3.5), bot[:z0_top] - bot[:z0])
ok('the top rail stops below the top of the post',
   close(top[:z0_top], 70.0), top[:z0_top])
ok('the top rail is the same size as the bottom one',
   close(top[:z0_top] - top[:z0], 3.5))
ok('both rails run the full bay',
   close(bot[:t0], bay[:t0]) && close(bot[:t1], bay[:t1]))

ok('one rail asked for is the bottom one only',
   FM.bay_rails(bay, rail_count: 1).map { |r| r[:kind] } == ['bottom'])
mid = FM.bay_rails(bay, opts.merge(rail_count: 3))
ok('three rails puts one in the middle', mid.length == 3, mid.length)
m = mid.find { |r| r[:kind] == 'mid' }
ok('and the middle one really is in the middle',
   m[:z0] > bot[:z0_top] && m[:z0_top] < top[:z0],
   [bot[:z0_top], m[:z0], m[:z0_top], top[:z0]])
ok('a rail with no height is no rail',
   FM.bay_rails(bay, rail_count: 2, rail_height: 0).empty?)

# ------------------------------------------------------ the zone between them

zone = FM.infill_zone(bay, opts)
ok('the infill starts on top of the bottom rail', close(zone[:z0], 5.5), zone[:z0])
ok('the infill stops under the top rail', close(zone[:z0_top], 66.5), zone[:z0_top])
ok('nothing overlaps a rail',
   zone[:z0] >= bot[:z0_top] - 1e-9 && zone[:z0_top] <= top[:z0] + 1e-9)

pieces = FM.bay_infill(bay, opts.merge(infill: 'boards', board_width: 5.5,
                                       board_gap: 0.0, post_size: 4.0))
ok('the boards now sit BETWEEN the rails, not floating',
   pieces.all? { |p| close(p[:z0], 5.5) && close(p[:z0_top], 66.5) },
   pieces.map { |p| [p[:z0].round(2), p[:z0_top].round(2)] }.uniq)

# A type whose rails eat the whole fence must give nothing rather than
# something inside out.
tall = FM.bay_infill(bay, rail_count: 2, rail_height: 40.0, infill: 'boards')
ok('rails taller than the fence build no infill at all', tall.empty?, tall.length)

# ------------------------------------------------------------- the four kinds

base = { rail_count: 2, rail_height: 3.5, rail_bottom_z: 2.0, post_size: 4.0 }

g = FM.bay_infill(bay, base.merge(infill: 'glass'))
ok('glass is ONE panel for the bay', g.length == 1, g.length)
ok('and it fills the bay between the posts',
   close(g[0][:t1] - g[0][:t0], 76.0), g[0][:t1] - g[0][:t0])

s = FM.bay_infill(bay, base.merge(infill: 'spaced', board_width: 0.5, board_gap: 3.38))
ok('spaced gives many pieces', s.length > 10, s.length)
ok('and every one is exactly the width asked for',
   s.all? { |p| close(p[:t1] - p[:t0], 0.5) },
   s.map { |p| (p[:t1] - p[:t0]).round(4) }.uniq)

ok('"bars" still means "spaced" for a type saved yesterday',
   FM.bay_infill(bay, base.merge(infill: 'bars', board_width: 0.5, board_gap: 3.38)).length ==
     s.length)

h = FM.bay_infill(bay, base.merge(infill: 'horizontal', board_width: 5.75, board_gap: 0.25))
ok('horizontal gives slats', h.length > 3, h.length)
ok('every slat spans the whole bay',
   h.all? { |p| close(p[:t1] - p[:t0], 76.0) },
   h.map { |p| (p[:t1] - p[:t0]).round(3) }.uniq)
ok('every slat is exactly as deep as asked',
   h.all? { |p| close(p[:z0_top] - p[:z0], 5.75) },
   h.map { |p| (p[:z0_top] - p[:z0]).round(3) }.uniq)
ok('the slats are stacked, not on top of each other',
   h.map { |p| p[:z0].round(4) }.uniq.length == h.length,
   h.map { |p| p[:z0].round(2) })
hz = FM.infill_zone(bay, base)
ok('and they stay inside the rails',
   h.all? { |p| p[:z0] >= hz[:z0] - 1e-9 && p[:z0_top] <= hz[:z0_top] + 1e-9 },
   [hz[:z0], hz[:z0_top], h.map { |p| [p[:z0].round(2), p[:z0_top].round(2)] }])

ok('"none" builds nothing between the rails',
   FM.bay_infill(bay, base.merge(infill: 'none')).empty?)
ok('a made-up infill name falls back to boards, it does not blow up',
   FM.bay_infill(bay, base.merge(infill: 'candyfloss')).length ==
     FM.bay_infill(bay, base.merge(infill: 'boards')).length)

# ------------------------------------------------------------ post and cap

post = lay[:posts].first
ok('with no cap the post keeps its whole height',
   close(FM.post_shaft(post, {})[:z1], 72.0), FM.post_shaft(post, {})[:z1])
ok('with no cap there is no cap', FM.post_cap(post, {}).nil?)

capped = { cap_size: 6.0, cap_height: 1.5 }
ok('a cap takes its slice off the TOP of the post, it does not sit above it',
   close(FM.post_shaft(post, capped)[:z1], 70.5),
   FM.post_shaft(post, capped)[:z1])
cap = FM.post_cap(post, capped)
ok('the cap picks up exactly where the post stops',
   close(cap[:z0], FM.post_shaft(post, capped)[:z1]), [cap[:z0], cap[:z1]])
ok('and the top of the cap is the height on the label',
   close(cap[:z1], 72.0), cap[:z1])
ok('the cap is wider than the post it sits on', cap[:size] > 4.0, cap[:size])
ok('half a cap is no cap', FM.post_cap(post, cap_size: 6.0, cap_height: 0).nil?)
ok('the cap pushes the rails down with it',
   close(FM.bay_rails(bay, rail_count: 2, rail_height: 2.0,
                      cap_height: 1.5).find { |r| r[:kind] == 'top' }[:z0_top], 70.5))

# ------------------------------------------------------------------ on a slope

slay = FM.layout(0, 0, 240, 0, height: 72.0, z1: -24.0, mode: :rake)
sbay = slay[:bays].first
srails = FM.bay_rails(sbay, opts)
sb = srails.find { |r| r[:kind] == 'bottom' }
ok('a raked rail is not level - it follows the ground',
   (sb[:z0] - sb[:z1]).abs > 1.0, [sb[:z0], sb[:z1]])
ok('and it keeps its thickness all the way along',
   close(sb[:z0_top] - sb[:z0], sb[:z1_top] - sb[:z1]))

sp = FM.bay_infill(sbay, opts.merge(infill: 'boards', board_width: 5.5,
                                    board_gap: 0.0, post_size: 4.0))
tops = sp.map { |p| p[:z0_top].round(4) }
ok('on a rake the boards are all different heights', tops.uniq.length > 1, tops.uniq.length)
ok('and none of them pokes through the top rail',
   sp.all? { |p| p[:z0_top] <= FM.top_at(sbay, p[:t0]) - 2.0 - 3.5 + 1e-6 },
   sp.map { |p| p[:z0_top].round(3) }.first(3))

# A stepped bay is level, so its rails must be level too.
tlay = FM.layout(0, 0, 240, 0, height: 72.0, z1: -24.0, mode: :step)
tbay = tlay[:bays].first
tb = FM.bay_rails(tbay, opts).find { |r| r[:kind] == 'top' }
ok('a stepped rail is dead level', close(tb[:z0], tb[:z1]), [tb[:z0], tb[:z1]])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

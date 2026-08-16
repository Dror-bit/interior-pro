# encoding: utf-8
# rt56 - landscape/fence_math.rb: the pure fence maths.
#
# No SketchUp, no model, no geometry: plain numbers in, plain numbers out.
# If this suite is green the fence layout is trustworthy BEFORE anything is
# built in the model. Same contract as rt19 for arc_math.rb.
require './fence_math'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

FM = InteriorPro::Landscape::FenceMath

# ------------------------------------------------------------------ basics

ok('length of a 10ft run', close(FM.length_xy(0, 0, 120, 0), 120.0), FM.length_xy(0, 0, 120, 0))
ok('length is plan-only (3-4-5)', close(FM.length_xy(0, 0, 30, 40), 50.0), FM.length_xy(0, 0, 30, 40))
ok('zero-length run', close(FM.length_xy(7, 7, 7, 7), 0.0))

ok('a 96" run is one bay',   FM.bay_count(96.0, 96.0) == 1, FM.bay_count(96.0, 96.0))
ok('a 97" run is two bays',  FM.bay_count(97.0, 96.0) == 2, FM.bay_count(97.0, 96.0))
ok('a 3" run is still one bay', FM.bay_count(3.0, 96.0) == 1, FM.bay_count(3.0, 96.0))
ok('never zero bays', FM.bay_count(0.0, 96.0) == 1)
ok('a silly spacing does not divide by zero', FM.bay_count(100.0, 0.0) == 1)

# ----------------------------------------------------------- post stations

st = FM.post_stations(240.0, 96.0)   # 20ft, 8ft max -> 3 bays of 80"
ok('20ft / 8ft max -> 4 posts', st.length == 4, st)
ok('first post at 0',   close(st.first, 0.0), st)
ok('last post at the end', close(st.last, 240.0), st)
ok('bays are all equal', close(st[1] - st[0], 80.0) && close(st[2] - st[1], 80.0) &&
                         close(st[3] - st[2], 80.0), st)
ok('no bay longer than the max', st.each_cons(2).all? { |a, b| (b - a) <= 96.0 + 1e-9 }, st)

st2 = FM.post_stations(96.0, 96.0)
ok('exactly one bay -> 2 posts', st2.length == 2, st2)

st3 = FM.post_stations(0.5, 96.0)
ok('a mis-click is not a fence', st3 == [0.0], st3)

# The last station must land EXACTLY on the end, not on a float that drifted.
st4 = FM.post_stations(1000.0 / 3.0, 96.0)
ok('last station is exact', st4.last == 1000.0 / 3.0, st4.last)

# ----------------------------------------------------------------- ground

ok('ground at the start', close(FM.ground_z(0, 100, 10, 30), 10.0))
ok('ground at the end',   close(FM.ground_z(100, 100, 10, 30), 30.0))
ok('ground in the middle', close(FM.ground_z(50, 100, 10, 30), 20.0))
ok('before the start is clamped', close(FM.ground_z(-50, 100, 10, 30), 10.0))
ok('past the end is clamped',     close(FM.ground_z(500, 100, 10, 30), 30.0))
ok('zero length does not divide by zero', close(FM.ground_z(5, 0, 10, 30), 10.0))

ok('flat? on equal ends', FM.flat?(0.0, 0.0))
ok('flat? on float noise', FM.flat?(0.0, 1e-9))
ok('not flat on a real drop', !FM.flat?(0.0, -12.0))

ok('slope of a level run is 0', close(FM.slope_deg(100, 5, 5), 0.0))
ok('climbing is positive', FM.slope_deg(100, 0, 10) > 0)
ok('falling is negative',  FM.slope_deg(100, 0, -10) < 0)
ok('45 degrees', close(FM.slope_deg(100, 0, 100), 45.0), FM.slope_deg(100, 0, 100))

# ------------------------------------------------------- point along the run

x, y = FM.point_at(0, 0, 100, 0, 25)
ok('point along a red-axis run', close(x, 25.0) && close(y, 0.0), [x, y])
x, y = FM.point_at(0, 0, 30, 40, 25)   # half of a 50" run
ok('point along a diagonal run', close(x, 15.0) && close(y, 20.0), [x, y])
x, y = FM.point_at(5, 5, 5, 5, 3)
ok('zero-length run returns the start', close(x, 5.0) && close(y, 5.0), [x, y])

# ------------------------------------------------------------ flat fence

lay = FM.layout(0, 0, 240, 0, height: 72.0, max_spacing: 96.0)
ok('flat: layout is built', !lay.nil?)
ok('flat: 4 posts', lay[:posts].length == 4, lay[:posts].length)
ok('flat: 3 bays',  lay[:bays].length == 3, lay[:bays].length)
ok('flat: marked flat', lay[:flat] == true)
ok('flat: every post top is 72', lay[:posts].all? { |p| close(p[:z_top], 72.0) },
   lay[:posts].map { |p| p[:z_top] })
ok('flat: every post base is 0', lay[:posts].all? { |p| close(p[:z_base], 0.0) })
ok('flat: every bay is level', lay[:bays].all? { |b| b[:level] })
ok('flat: bays span the whole run',
   close(lay[:bays].map { |b| b[:span] }.inject(:+), 240.0),
   lay[:bays].map { |b| b[:span] })
ok('flat: posts sit on the line', lay[:posts].all? { |p| close(p[:y], 0.0) })
ok('flat: last post at the end', close(lay[:posts].last[:x], 240.0), lay[:posts].last[:x])

# A step fence on level ground MUST equal a rake fence on level ground -
# otherwise the mode quietly changes a flat fence nobody meant to change.
lay_r = FM.layout(0, 0, 240, 0, height: 72.0, mode: :rake)
lay_s = FM.layout(0, 0, 240, 0, height: 72.0, mode: :step)
ok('flat: step collapses to rake', lay_s[:mode] == :rake, lay_s[:mode])
ok('flat: both modes give the same tops',
   lay_r[:posts].map { |p| p[:z_top] } == lay_s[:posts].map { |p| p[:z_top] })

# ------------------------------------------------------------ raked fence
# 20ft run dropping 24" from start to end, 3 bays of 80".

rk = FM.layout(0, 0, 240, 0, height: 72.0, max_spacing: 96.0, z0: 0.0, z1: -24.0, mode: :rake)
ok('rake: built', !rk.nil?)
ok('rake: mode kept', rk[:mode] == :rake, rk[:mode])
ok('rake: not flat', rk[:flat] == false)
ok('rake: slope is negative', rk[:slope_deg] < 0, rk[:slope_deg])

ok('rake: first post top is 72',  close(rk[:posts][0][:z_top], 72.0), rk[:posts][0][:z_top])
ok('rake: last post top is 48',   close(rk[:posts][3][:z_top], 48.0), rk[:posts][3][:z_top])
ok('rake: middle posts drop evenly',
   close(rk[:posts][1][:z_top], 64.0) && close(rk[:posts][2][:z_top], 56.0),
   rk[:posts].map { |p| p[:z_top] })
ok('rake: post base follows the ground',
   close(rk[:posts][3][:z_base], -24.0), rk[:posts][3][:z_base])
ok('rake: every post is exactly height above its own ground',
   rk[:posts].all? { |p| close(p[:z_top] - p[:ground_z], 72.0) },
   rk[:posts].map { |p| [p[:ground_z], p[:z_top]] })
ok('rake: no bay is level', rk[:bays].none? { |b| b[:level] })
ok('rake: a bay top matches its two posts',
   close(rk[:bays][0][:z_top0], 72.0) && close(rk[:bays][0][:z_top1], 64.0),
   [rk[:bays][0][:z_top0], rk[:bays][0][:z_top1]])

# ---------------------------------------------------------- stepped fence

sp = FM.layout(0, 0, 240, 0, height: 72.0, max_spacing: 96.0, z0: 0.0, z1: -24.0, mode: :step)
ok('step: built', !sp.nil?)
ok('step: mode kept', sp[:mode] == :step, sp[:mode])
ok('step: every bay is level', sp[:bays].all? { |b| b[:level] },
   sp[:bays].map { |b| [b[:z_top0], b[:z_top1]] })
ok('step: bays step DOWN along the run',
   sp[:bays].each_cons(2).all? { |a, b| b[:z_top0] < a[:z_top0] },
   sp[:bays].map { |b| b[:z_top0] })
ok('step: a panel sits at the higher end + height',
   close(sp[:bays][0][:z_top0], 72.0), sp[:bays][0][:z_top0])

# The one that actually matters visually: no post may be shorter than the
# panel it carries, or the panel floats above its own post.
sp[:posts].each do |p|
  mine = sp[:bays].select { |b| b[:i] == p[:i] || b[:i] == p[:i] - 1 }
  worst = mine.map { |b| [b[:z_top0], b[:z_top1]].max }.max
  ok("step: post #{p[:i]} reaches its panels", p[:z_top] >= worst - 1e-9,
     [p[:z_top], worst])
end
ok('step: an inner post reaches the UPHILL panel',
   close(sp[:posts][1][:z_top], 72.0), sp[:posts][1][:z_top])
ok('step: the last post carries only the last panel',
   close(sp[:posts][3][:z_top], 56.0), sp[:posts][3][:z_top])

# A stepped fence must never dip below the ground on the uphill side.
ok('step: no panel top is under its own ground',
   sp[:bays].all? { |b|
     g0 = FM.ground_z(b[:t0], sp[:length], sp[:z0], sp[:z1])
     g1 = FM.ground_z(b[:t1], sp[:length], sp[:z0], sp[:z1])
     b[:z_top0] > g0 && b[:z_top1] > g1
   })

# ---------------------------------------------------------------- climbing
# The mirror case: the run goes UP. Nothing may be special-cased for down.

up = FM.layout(0, 0, 240, 0, height: 72.0, max_spacing: 96.0, z0: -24.0, z1: 0.0, mode: :rake)
ok('uphill: slope is positive', up[:slope_deg] > 0, up[:slope_deg])
ok('uphill: first post top is 48', close(up[:posts][0][:z_top], 48.0), up[:posts][0][:z_top])
ok('uphill: last post top is 72',  close(up[:posts][3][:z_top], 72.0), up[:posts][3][:z_top])

ups = FM.layout(0, 0, 240, 0, height: 72.0, max_spacing: 96.0, z0: -24.0, z1: 0.0, mode: :step)
ok('uphill step: bays step UP',
   ups[:bays].each_cons(2).all? { |a, b| b[:z_top0] > a[:z_top0] },
   ups[:bays].map { |b| b[:z_top0] })

# ------------------------------------------------------------- embed / gap

em = FM.layout(0, 0, 120, 0, height: 72.0, embed: 24.0, gap_below: 2.0)
ok('embed sinks the post base', close(em[:posts][0][:z_base], -24.0), em[:posts][0][:z_base])
ok('embed does NOT change the post top', close(em[:posts][0][:z_top], 72.0), em[:posts][0][:z_top])
ok('gap lifts the panel bottom', close(em[:bays][0][:z_bottom0], 2.0), em[:bays][0][:z_bottom0])

# ------------------------------------------------------------------ refusals

ok('a mis-click makes no fence', FM.layout(0, 0, 0.5, 0).nil?)
ok('same point makes no fence',  FM.layout(5, 5, 5, 5).nil?)
ok('zero height makes no fence', FM.layout(0, 0, 240, 0, height: 0.0).nil?)
ok('a nonsense mode falls back to rake',
   FM.layout(0, 0, 240, 0, z0: 0, z1: -24, mode: :banana)[:mode] == :rake)

# ------------------------------------------------------------------ defaults

d = FM.layout(0, 0, 240, 0)
ok('default height is 72', close(d[:height], 72.0), d[:height])
ok('default spacing gives 3 bays', d[:bays].length == 3, d[:bays].length)
ok('default ground is level', d[:flat] == true)

# ------------------------------------------------------------------ describe

ok('describe a flat fence', FM.describe(d) == "20.0' | 3 bays | 4 posts", FM.describe(d))
ok('describe says the mode on a slope', FM.describe(rk).include?('rake'), FM.describe(rk))
ok('describe survives nil', FM.describe(nil) == 'no fence')

# ------------------------------------------------ a diagonal run, end to end
# Everything above ran along the red axis. A fence drawn at an angle must be
# no different - the plan length drives the spacing, and the posts sit on the
# line between the two clicks.

dg = FM.layout(0, 0, 180, 240, height: 72.0, max_spacing: 96.0, z0: 0.0, z1: -30.0)
ok('diagonal: plan length is 300', close(dg[:length], 300.0), dg[:length])
ok('diagonal: 300" / 96" max -> 4 bays, 5 posts',
   dg[:bays].length == 4 && dg[:posts].length == 5,
   [dg[:bays].length, dg[:posts].length])
ok('diagonal: bays are 75" each', dg[:bays].all? { |b| close(b[:span], 75.0) },
   dg[:bays].map { |b| b[:span] })
ok('diagonal: last post is the second click',
   close(dg[:posts].last[:x], 180.0) && close(dg[:posts].last[:y], 240.0),
   [dg[:posts].last[:x], dg[:posts].last[:y]])
ok('diagonal: posts are on the line',
   dg[:posts].all? { |p| close(p[:y] * 180.0 - p[:x] * 240.0, 0.0, 1e-6) },
   dg[:posts].map { |p| [p[:x], p[:y]] })
ok('diagonal: ground drops to -30 at the end',
   close(dg[:posts].last[:ground_z], -30.0), dg[:posts].last[:ground_z])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

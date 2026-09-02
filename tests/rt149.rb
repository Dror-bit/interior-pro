# encoding: utf-8
# rt149 - SKYLIGHT, STEP 1: THE OPENING (2026-09-14).
#
# "משהו שהוא כמו חלון תמונה רק להחליף צבעים... צריך שיהיה אפשר לבחור לו
# צבע אבל החלון עצמו פשוט". Step 1 is the roof only - the hole through the
# slab and the curb standing in it. The hole through the CEILING is step 2.
#
# WHAT IS PINNED HERE: the opening is centred on the click, square to the
# slope, refuses to be smaller than the minimum, and the colour is read
# back safely.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
require './skylight_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SM = InteriorPro::SkylightManager

ok('there is a kill switch', SM.const_defined?(:USE_SKYLIGHTS), nil)

r = SM.plan_rect(100.0, 30.0, 46.0)
ok('the opening has four corners', r && r.length == 4, r)
ok('it is centred on the click up the slope',
   r && ((r.map(&:first).min + r.map(&:first).max) / 2.0 - 100.0).abs < 1e-9,
   r && r.map(&:first))
ok('...and centred across it too',
   r && ((r.map(&:last).min + r.map(&:last).max) / 2.0).abs < 1e-9,
   r && r.map(&:last))
ok('it is as long as the height asked for',
   r && (r.map(&:first).max - r.map(&:first).min - 46.0).abs < 1e-9,
   r && (r.map(&:first).max - r.map(&:first).min))
ok('and as wide as the width asked for',
   r && (r.map(&:last).max - r.map(&:last).min - 30.0).abs < 1e-9,
   r && (r.map(&:last).max - r.map(&:last).min))
ok('the corners walk round, they do not cross',
   r == [[77.0, -15.0], [77.0, 15.0], [123.0, 15.0], [123.0, -15.0]], r)

ok('a skylight smaller than the minimum is refused',
   SM.plan_rect(100.0, SM.min_size - 1.0, 46.0).nil?, nil)
ok('...in either direction',
   SM.plan_rect(100.0, 30.0, SM.min_size - 1.0).nil?, nil)
ok('a zero is refused too', SM.plan_rect(100.0, 0.0, 0.0).nil?, nil)

ok('a colour is taken as typed', SM.color_of(color: '#3366ff') == '#3366ff',
   SM.color_of(color: '#3366ff'))
ok('...and rubbish falls back to the default',
   SM.color_of(color: 'blue') == SM.default_color, SM.color_of(color: 'blue'))
ok('...and so does nothing at all',
   SM.color_of({}) == SM.default_color, SM.color_of({}))

ok('the curb stands off the roof', SM.curb_height > 0.0, SM.curb_height)
ok('the frame is narrower than the smallest skylight',
   SM.frame_width * 2.0 < SM.min_size, [SM.frame_width, SM.min_size])

# ---- step 2 + 3: the panel's numbers, the shaft, surviving a rebuild ----
ok('there is a kill switch for the shaft too', SM.const_defined?(:USE_SKYLIGHT_SHAFT), nil)

c = SM.clean_spec(width: 500.0, height: 3.0, color: '#ABCDEF')
ok('a huge width is pulled back to the maximum', c[:width] == SM.max_size, c)
ok('a tiny height is pulled up to the minimum', c[:height] == SM.min_size, c)
ok('the colour is kept, lower-cased', c[:color] == '#abcdef', c)
d = SM.clean_spec({})
ok('nothing typed gives the defaults',
   d == { width: SM.default_width, height: SM.default_height, color: SM.default_color }, d)
ok('the panel settings round-trip',
   SM.save_settings!(width: 24, height: 36, color: '#112233') ==
     SM.settings && SM.settings[:width] == 24.0, SM.settings)
SM.save_settings!({})

at = lambda { |s, w, z| Geom::Point3d.new(100.0 + s, 50.0 + w, z) }
plan = SM.plan_rect(20.0, 30.0, 46.0)
low = SM.ring_at_z(plan, at, 96.0)
ok('the ceiling ring is the same rectangle, dead level at the ceiling',
   low.length == 4 && low.all? { |p| (p.z - 96.0).abs < 1e-9 } &&
   low.map(&:x).minmax == [97.0, 143.0] && low.map(&:y).minmax == [35.0, 65.0], low)
high = plan.map { |s, w| q = at.call(s, w, 0.0); Geom::Point3d.new(q.x, q.y, 140.0 + s * 0.4) }
quads = SM.shaft_quads(low, high)
ok('the shaft has four walls', quads.length == 4, quads.length)
ok('each wall stands on one ceiling edge and reaches its own roof edge',
   quads.each_with_index.all? do |q, i|
     j = (i + 1) % 4
     q[0] == low[i] && q[1] == low[j] && q[2] == high[j] && q[3] == high[i]
   end, quads.first)
ok('every shaft wall is vertical',
   quads.all? { |q| (q[0].x - q[3].x).abs < 1e-9 && (q[0].y - q[3].y).abs < 1e-9 }, nil)
ok('a mismatched pair of rings gives no shaft', SM.shaft_quads(low, high.first(3)).empty?, nil)

# surviving a roof rebuild: harvest reads the numbers off the group
Sketchup.reset_model! if Sketchup.respond_to?(:reset_model!)
roof = Sketchup.active_model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
sk = roof.entities.add_group
sk.set_attribute('InteriorPro', 'type', 'skylight')
sk.set_attribute('InteriorPro', 'width', 24.0)
sk.set_attribute('InteriorPro', 'height', 36.0)
sk.set_attribute('InteriorPro', 'color', '#3366ff')
sk.set_attribute('InteriorPro', 'at_xy', [412.5, 380.25])
saved = SM.harvest([roof])
ok('harvest finds the skylight on the roof', saved.length == 1, saved)
ok('...at the plan point it was clicked',
   saved[0] && saved[0][:x] == 412.5 && saved[0][:y] == 380.25, saved)
ok('...with its own size and colour',
   saved[0] && saved[0][:spec] == { width: 24.0, height: 36.0, color: '#3366ff' }, saved)
ok('a roof with none gives an empty list',
   SM.harvest([Sketchup.active_model.entities.add_group]).empty?, nil)

src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('build_roof! harvests the skylights before the old roof goes',
   src.include?('InteriorPro::SkylightManager.harvest(doomed)'), nil)
ok('...and puts them back on the new one',
   src.include?('InteriorPro::SkylightManager.replant!(grp, kept_skylights)'), nil)
ok('...AFTER the dormers, so the roof faces already exist',
   src.index('InteriorPro::SkylightManager.replant!') >
   src.index('InteriorPro::DormerManager.replant!(grp, kept_dormers)'), nil)
ok('the harvest is guarded, so a build without the file still runs',
   src.include?("defined?(InteriorPro::SkylightManager) &&\n                          InteriorPro::SkylightManager.respond_to?(:harvest)"), nil)

# the glass border is the same width all round, on a long narrow pane too
ring = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(30, 0, 0),
        Geom::Point3d.new(30, 46, 0), Geom::Point3d.new(0, 46, 0)]
ins = SM.inset_ring(ring, 2.0)
ok('the pane is inset by the frame width on every side',
   ins && ins.map(&:x).minmax == [2.0, 28.0] && ins.map(&:y).minmax == [2.0, 44.0], ins)
ok('a ring too small to inset gives nil',
   SM.inset_ring([Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(3, 0, 0),
                  Geom::Point3d.new(3, 3, 0), Geom::Point3d.new(0, 3, 0)], 2.0).nil?, nil)

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

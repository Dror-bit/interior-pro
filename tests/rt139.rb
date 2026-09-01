# encoding: utf-8
# rt139 - THE NUMBER IN THE REFUSAL HAS TO BE A NUMBER THAT BUILDS
# (2026-09-13).
#
# He typed a front wall of 25" into Edit Dormer and got back: "too long
# for this roof - it would reach the ridge. The tallest front wall that
# fits here is 32"". Both sentences were true at the same time, which is
# not a message, and he said so.
#
# MEASURED: a typed height is not the height that gets built. frame()
# adds the raised heel - the gablet's own fascia depth - to the length,
# and that lifts the ridge by exactly `heel` for every style. His fascia
# was 8", so 25 built as 33 and really did hit the ridge, while
# ridge_cap_check computed its ceiling without the heel and offered 32.
#
# WHAT IS PINNED HERE: the height the refusal names is accepted, and one
# inch more is refused. Nothing about geometry - just that the number is
# honest.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
Z0 = 100.0
SLOPE = 5.0 / 12.0

# z_top is the house ridge - low enough that a tall gablet is refused.
BASE = { z0: Z0, slope: SLOPE, setback: 50.0, width: 60.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         fascia_depth: 8.0, z_top: Z0 + 90.0,
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0],
         no_tiles: true }.freeze

def h_offered(sp)
  DM.frame(sp.merge(height: 400.0))
  m = DM.last_reason.to_s[/fits here is (-?[\d.]+)"/, 1]
  m && m.to_f
end

%w[gable shed flat].each do |style|
  sp = BASE.merge(style: style)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'

  h = h_offered(sp)
  ok("#{style}: the refusal names a height", !h.nil?, DM.last_reason)
  next if h.nil?
  ok("#{style}: and it is a positive one", h > 0.0, h)

  # the number it offered must build...
  fr = DM.frame(sp.merge(height: h))
  ok("#{style}: the height it offered (#{h.round(1)}\") really builds",
     !fr.nil?, DM.last_reason)

  # ...and one inch more must not.
  over = DM.frame(sp.merge(height: h + 1.0))
  ok("#{style}: one inch more is still refused", over.nil?, 'it built')
end

# the heel is what was missing: with the heel switched off the two
# numbers agree on their own, so this cannot pass by accident.
ok('the heel is a real, non-zero number here',
   DM.dormer_heel(6.0, 'gable', SLOPE, SLOPE, BASE) > 0.0,
   DM.dormer_heel(6.0, 'gable', SLOPE, SLOPE, BASE))

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

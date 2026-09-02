# encoding: utf-8
# rt119 - THE GABLET GETS THE SAME RAISED HEEL (2026-09-06).
#
# He asked for it in one line: "תתקן את זה גם בגגון". Same complaint as
# the house roof - the eave hung below the top of the wall it stood on and
# swallowed its corner - and the same two parts to the lift:
#   overhang x ITS OWN pitch   (the falling tail)
# + its own fascia depth       (what hangs below the deck at the tip)
#
# WHAT THE PANEL'S NUMBER MEANS. He was asked and he chose: "העקב נוסף
# למספר" - a typed 33" front wall comes out 33 + the heel. That replaces
# the older rule that a typed height came back untouched and that the
# overhang never moved z_eave (rt97/rt99/rt100/rt101/rt102/rt103), which
# now switch the heel off and keep testing their own subjects.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'
# 2026-09-13B: this suite pins the RAW gablet formulas, so the 6" the roof
# now rides above the window is switched off here - exactly the way the
# raised heel is kept out of these same formulas. rt148 pins the headroom.
InteriorPro::DormerManager.send(:remove_const, :USE_DORMER_HEADROOM)
InteriorPro::DormerManager.const_set(:USE_DORMER_HEADROOM, false)


$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, t = 0.01); a && b && (a - b).abs < t; end

DM = InteriorPro::DormerManager
SLOPE = 5.0 / 12.0
OH = 6.0
BASE = { z0: 100.0, slope: SLOPE, setback: 50.0, width: 60.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: OH,
         fascia_depth: 8.0 }.freeze

# ---- 1. the number ---------------------------------------------------
# ITS OWN FASCIA DEPTH, AND ONLY THAT - the same rule the house roof got.
# The gablet's eave hangs that far under its deck, so standing the roof
# that far over its walls lands the eave's underside ON them.
%w[gable hip shed flat].each do |st|
  ok("1. a #{st} gablet's heel is its own fascia depth",
     close(DM.dormer_heel(OH, st, SLOPE, SLOPE,
                          pitch: SLOPE / 2.0, fascia_depth: 8.0), 8.0),
     DM.dormer_heel(OH, st, SLOPE, SLOPE, pitch: SLOPE / 2.0, fascia_depth: 8.0))
end
ok('1b. neither the overhang nor the pitch is in it',
   close(DM.dormer_heel(90.0, 'gable', 1.0, 1.0, fascia_depth: 8.0),
         DM.dormer_heel(0.0, 'gable', SLOPE, SLOPE, fascia_depth: 8.0)),
   [DM.dormer_heel(90.0, 'gable', 1.0, 1.0, fascia_depth: 8.0),
    DM.dormer_heel(0.0, 'gable', SLOPE, SLOPE, fascia_depth: 8.0)])

# ---- 2. the typed height carries it ----------------------------------
%w[gable hip shed flat].each do |style|
  sp = BASE.merge(style: style, height: 33.0)
  sp[:pitch] = SLOPE / 2.0 if style == 'shed'
  fr = DM.frame(sp)
  next ok("2. a #{style} gablet builds", false, DM.last_reason) if fr.nil?
  heel = DM.dormer_heel(OH, style, sp[:pitch] || SLOPE, SLOPE, sp)
  ok("2. a typed 33\" #{style} front wall comes out 33 + its heel (#{heel.round(2)})",
     close(fr[:height], 33.0 + heel, 0.02), [fr[:height], 33.0 + heel])
end

# ---- 3. it is the ROOF that rides up, not the wall that grew alone ----
# the gablet still dies into the main roof: the deck at s_ridge is exactly
# the main roof's own surface there. That is what makes the heel a lift
# rather than a taller box sitting proud of the slope.
fr = DM.frame(BASE.merge(style: 'gable', height: 33.0))
ok('3. the gablet still dies into the main roof',
   close(DM.deck_z(fr, fr[:s_ridge], 0.0),
         BASE[:z0] + fr[:s_ridge] * SLOPE, 0.001),
   [DM.deck_z(fr, fr[:s_ridge], 0.0), BASE[:z0] + fr[:s_ridge] * SLOPE])
plain = DM.frame(BASE.merge(style: 'gable', height: 33.0, overhang: 0.0,
                            fascia_depth: 0.0))
ok('3b. and with no overhang and no fascia it is exactly where it was',
   close(plain[:height], 33.0, 0.02), plain[:height])
ok('3c. the heel makes it reach FURTHER into the roof',
   fr[:length] > plain[:length], [fr[:length], plain[:length]])

# ---- 4. the kill switch ----------------------------------------------
ok('4. there is a kill switch', DM.const_defined?(:USE_DORMER_HEEL))

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

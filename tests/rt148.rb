# encoding: utf-8
# rt148 - THE ROOF RIDES 6" HIGHER OVER THE WINDOW (2026-09-13B).
#
# "תרים את הגג 6 בערך אינץ כדי שהוא לא ישב על החלון", and asked which of
# the two should move: "להעלות את הגג למעלה".
#
# FIRST CUT, REVERTED: the headroom came off the window's SIZE as well as
# its position, and his window came back 10" shorter - "הורדת את החלון
# ואני ביקשתי להעלות את הגג". So the size is measured off the REAL wall
# top exactly as it always was, and only the centre is measured off the
# wall top less the headroom.
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
HR = DM.dormer_headroom

BASE = { z0: 205.5, slope: 5.0 / 12.0, setback: 20.0, width: 50.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         fascia_depth: 8.0, height: 16.0,
         base: [0.0, 0.0], along: [1.0, 0.0], into: [0.0, 1.0],
         no_tiles: true }.freeze

ok('the headroom is six inches', (HR - 6.0).abs < 1e-9, HR)

def with_hr(on)
  had = DM::USE_DORMER_HEADROOM
  DM.send(:remove_const, :USE_DORMER_HEADROOM)
  DM.const_set(:USE_DORMER_HEADROOM, on)
  yield
ensure
  DM.send(:remove_const, :USE_DORMER_HEADROOM)
  DM.const_set(:USE_DORMER_HEADROOM, had)
end

off = with_hr(false) { DM.frame(BASE) }
on  = with_hr(true)  { DM.frame(BASE) }
ok('both frames build', !off.nil? && !on.nil?, [off.nil?, on.nil?])

if off && on
  ok('the frame carries the headroom', (on[:headroom] - HR).abs < 1e-9, on[:headroom])
  ok('...and none when it is switched off', off[:headroom].to_f == 0.0, off[:headroom])
  ok('THE ROOF RIDES UP BY THE HEADROOM',
     (on[:z_eave] - off[:z_eave] - HR).abs < 0.01, [off[:z_eave], on[:z_eave]])
  ok('the front wall grows by exactly the same',
     (on[:height] - off[:height] - HR).abs < 0.01, [off[:height], on[:height]])
  ok('the wall foot has not moved',
     (on[:z_front] - off[:z_front]).abs < 1e-9, [off[:z_front], on[:z_front]])

  woff = DM.window_rect(off)
  won  = DM.window_rect(on)
  ok('a window fits either way', !woff.nil? && !won.nil?, [woff, won])
  if woff && won
    ok('THE WINDOW IS NEVER MADE SMALLER BY THE HEADROOM',
       won[:height] >= woff[:height] - 1e-6, [woff[:height], won[:height]])
    ok('...and it is not pushed up either',
       won[:z] <= woff[:z] + 1e-6, [woff[:z], won[:z]])
    head_off = DM.wall_top_over(off, woff[:width] / 2.0) - (woff[:z] + woff[:height] / 2.0)
    head_on  = DM.wall_top_over(on,  won[:width]  / 2.0) - (won[:z]  + won[:height]  / 2.0)
    ok('THERE IS MORE WALL ABOVE THE WINDOW THAN THERE WAS',
       head_on > head_off + 1.0, [head_off, head_on])
  end
end

typed = with_hr(true) { DM.frame(BASE.merge(height: 30.0)) }
ok('a typed height is still remembered as typed',
   typed && (typed[:height_asked] - 30.0).abs < 1e-9,
   typed && typed[:height_asked])

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

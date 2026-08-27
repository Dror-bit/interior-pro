# encoding: utf-8
# rt99 - THE DORMER'S PANEL AND ITS GHOST (2026-09-02, step 3+4).
#
# WHY
# The user: "בוא נעשה את הגגות אבל שזה יבוא כבר עם הכפתור" - the roof
# styles, but arriving with the button, the panel and the ghost square,
# not as a console call. This pins the two halves that have no SketchUp
# window in them: what the panel REMEMBERS, and what the ghost DRAWS.
#
# THE CLAIMS PINNED HERE
# 1. THE PANEL REMEMBERS, on the model, so the next dormer starts from
#    the last one's numbers.
# 2. TWO ZEROES MEAN "FOLLOW THE HOUSE" and they are zeroes, not blanks:
#    pitch 0 leaves :pitch out of the spec entirely, so frame() falls
#    back to the main roof's own slope; fascia depth 0 leaves the fascia
#    to the house's own setting.
# 3. THE GHOST IS THE BUILD. Every point the tool draws comes from the
#    same frame() the build reads - the two roof planes, the front wall
#    and the hole - so the ghost cannot drift from what lands.
# 4. NO GHOST WHERE NO DORMER FITS, and NO CONSOLE SPAM while the mouse
#    is out there finding that out.
#
# Against the old code all four fail - there was no panel and no ghost.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

DM = InteriorPro::DormerManager

# ---- 1. THE PANEL REMEMBERS ------------------------------------------
Sketchup.reset_model!
d = DM.settings
ok('a fresh model starts on the defaults',
   close(d[:width], DM::DEFAULT_WIDTH) && close(d[:length], DM::DEFAULT_LENGTH) &&
   close(d[:setback], DM::DEFAULT_SETBACK) && close(d[:overhang], DM::DEFAULT_OVERHANG),
   d)
ok('...following the roof pitch, and the house fascia',
   close(d[:pitch12], 0.0) && close(d[:fascia_depth], 0.0), d)
ok('...gable', d[:style] == 'gable', d[:style])

DM.save_settings!(width: 60.0, length: 144.0, setback: 24.0, overhang: 8.0,
                  pitch12: 8.0, fascia_depth: 6.0, style: 'gable')
d2 = DM.settings
ok('what the panel saved is what it reads back',
   close(d2[:width], 60.0) && close(d2[:length], 144.0) &&
   close(d2[:setback], 24.0) && close(d2[:overhang], 8.0) &&
   close(d2[:pitch12], 8.0) && close(d2[:fascia_depth], 6.0), d2)

# ---- 2. THE TWO ZEROES ------------------------------------------------
sp = DM.spec_from_settings(d2)
ok('a typed pitch becomes rise per 1 of run',
   close(sp[:pitch], 8.0 / 12.0), sp[:pitch])
ok('a typed fascia depth is passed on', close(sp[:fascia_depth], 6.0))
sp0 = DM.spec_from_settings(DM.settings.merge(pitch12: 0.0, fascia_depth: 0.0))
ok('pitch 0 leaves :pitch OUT, so frame() falls back to the roof',
   !sp0.key?(:pitch), sp0)
ok('fascia 0 leaves :fascia_depth OUT, so the house decides',
   !sp0.key?(:fascia_depth), sp0)
fr = DM.frame(sp0.merge(z0: 100.0, slope: 8.0 / 12.0))
ok('...and that fallback really is the roof pitch',
   close(fr[:pitch], 8.0 / 12.0), fr && fr[:pitch])

# ---- 3. THE GHOST IS THE BUILD ---------------------------------------
# a roof group the stub can answer questions about: one sloping face
Sketchup.reset_model!
m = Sketchup.active_model
Z0 = 100.0
SLOPE = 8.0 / 12.0
roof = m.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
tp = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
roof.entities.add_face([tp.call(-200, 0), tp.call(200, 0),
                        tp.call(200, 400), tp.call(-200, 400)])
DM.save_settings!(width: 48.0, length: 96.0, setback: 36.0, overhang: 6.0,
                  pitch12: 0.0, fascia_depth: 0.0, style: 'gable')
spec = DM.spec_from_settings
loops = DM.preview(roof, 0.0, 120.0, spec)
ok('there is a ghost over the roof', !loops.nil? && loops.length == 4,
   loops && loops.length)

if loops
  rf = DM.roof_frame(roof, 0.0, 120.0)
  fr2 = DM.frame(spec.merge(rf))
  at = DM.at_lambda(spec.merge(rf))
  planes = loops[0, 2]
  wall = loops[2]
  hole = loops[3]
  ok('the ghost roof planes ARE roof_plan, corner for corner',
     planes[0].map { |p| [p.x.round(3), p.y.round(3), p.z.round(3)] } ==
     DM.roof_plan(fr2, 1.0).map do |ss, w|
       q = at.call(ss, w, DM.top_z(fr2, w))
       [q.x.round(3), q.y.round(3), q.z.round(3)]
     end)
  ok('the ghost front wall is the gable pentagon', wall.length == 5, wall.length)
  ok('...standing on the roof surface at the setback',
     close(wall.map(&:z).min, fr2[:z_front], 0.01), wall.map(&:z).min)
  ok('...and reaching the slab underside at the ridge',
     close(wall.map(&:z).max, fr2[:z_ridge] - fr2[:roof_thickness], 0.01),
     wall.map(&:z).max)
  ok('the ghost hole IS opening_plan, drawn on the roof surface',
     hole.length == DM.opening_plan(fr2).length &&
     hole.all? { |p| close(p.z, Z0 + p.y * SLOPE, 0.02) },
     hole.map { |p| p.z.round(2) })
end

# ---- 4. NO GHOST WHERE NOTHING FITS, AND NO SPAM ----------------------
far = m.entities.add_group
far.set_attribute('InteriorPro', 'type', 'roof')
far.entities.add_face([Geom::Point3d.new(5000, 5000, 0),
                       Geom::Point3d.new(5100, 5000, 0),
                       Geom::Point3d.new(5100, 5100, 0)])
ok('no ghost off the roof', DM.preview(far, 0.0, 0.0, spec).nil?)
huge = DM.spec_from_settings(DM.settings.merge(width: 48.0, length: 20.0))
ok('no ghost for a size that cannot make a dormer',
   DM.preview(roof, 0.0, 120.0, huge).nil?)

# the quiet flag is what keeps the console clean while the mouse moves
noisy = false
begin
  require 'stringio'
  buf = StringIO.new
  old = $stdout
  $stdout = buf
  5.times { DM.preview(far, 0.0, 0.0, spec) }
  $stdout = old
  noisy = !buf.string.strip.empty?
rescue StandardError
  $stdout = STDOUT
end
ok('a mouse wandering off the roof says nothing in the console', !noisy)

# ---- 5. THE HEIGHT DRIVES THE LENGTH, AND THE RIDGE IS THE CEILING ---
# (2026-09-02, the user: "האורך לתוך הגג לא רלוונטי לי... הוא צריך
# לעצור אותי נגיד פוט אחד לפני הגובה של הגג")
base = { z0: Z0, slope: SLOPE, setback: 36.0, width: 48.0, thickness: 5.0,
         roof_thickness: 0.5, overhang: 6.0 }
h = 30.0
fh = DM.frame(base.merge(height: h))
ok('a typed height comes out as that height',
   close(fh[:height], h, 0.01), fh && fh[:height])
ok('...and the length is whatever produced it',
   close(fh[:length], (h + 24.0 * fh[:pitch]) / SLOPE, 0.01), fh[:length])
ok('a taller wall needs a longer reach',
   DM.frame(base.merge(height: h * 2))[:length] > fh[:length])
fs = DM.frame(base.merge(height: h, style: 'shed'))
ok('a shed height works off its own formula',
   close(fs[:height], h, 0.01) &&
   close(fs[:length], h / (SLOPE - fs[:pitch]), 0.01), fs && fs[:length])

# the ceiling: the roof face's own top, one foot of clearance
ceiling_z = Z0 + (36.0 + fh[:length]) * SLOPE
ok('with a foot to spare it still builds',
   !DM.frame(base.merge(height: h, z_top: ceiling_z + DM::RIDGE_CLEARANCE)).nil?)
ok('...and one inch short of that it is refused, not squeezed',
   DM.frame(base.merge(height: h,
                       z_top: ceiling_z + DM::RIDGE_CLEARANCE - 1.0)).nil?)
ok('...with a reason that names the tallest wall that WOULD fit',
   DM.last_reason.to_s.include?('tallest front wall'), DM.last_reason)
ok('a roof with no top given is not capped at all',
   !DM.frame(base.merge(height: h)).nil?)

# ---- 6. IT HAS TO FIT ON THIS SLOPE, SIDEWAYS TOO --------------------
# (2026-09-02, the user: "אני לא רוצה שיהיה אפשר להניח את הגגון אם הוא
# נוגע ברידג גם של הצדדים לא רק של הגובה... חייבת להיות מגבלה")
Sketchup.reset_model!
m6 = Sketchup.active_model
slope6 = m6.entities.add_group
slope6.set_attribute('InteriorPro', 'type', 'roof')
tp6 = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
# a narrow slope: 120" wide, 400" up the fall
slope6.entities.add_face([tp6.call(-60, 0), tp6.call(60, 0),
                          tp6.call(60, 400), tp6.call(-60, 400)])
DM.save_settings!(width: 48.0, length: 96.0, setback: 36.0, overhang: 6.0,
                  pitch12: 0.0, fascia_depth: 0.0, height: 0.0, style: 'gable')
sp6 = DM.spec_from_settings
ok('in the middle of the slope it fits', !DM.preview(slope6, 0.0, 120.0, sp6).nil?)
ok('pushed up against the hip on the right it is refused',
   DM.preview(slope6, 45.0, 120.0, sp6).nil?)
ok('...and against the one on the left too',
   DM.preview(slope6, -45.0, 120.0, sp6).nil?)
ok('...with a reason that says which edge it ran into',
   DM.last_reason.to_s.include?('edge of this roof slope'), DM.last_reason)
ok('a wider dormer stops fitting where a narrow one did',
   DM.preview(slope6, 30.0, 120.0,
              DM.spec_from_settings(DM.settings.merge(width: 96.0))).nil?)
ok('the build refuses it too, not just the ghost',
   DM.place_on_roof!(slope6, 45.0, 120.0, sp6).nil?)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

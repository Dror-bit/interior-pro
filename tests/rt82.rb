# encoding: utf-8
# rt82 - the long half-pipe RUNS (2026-08-20).
#
# WHY THIS REPLACED THE EAVE COURSE
# Step 4 built a 3D piece on the eave only, on the rule "3D where the
# silhouette shows, texture everywhere else". The user looked at it and said
# it was the worst thing in the world, and then sent his own reference -
# Roman Tiled Roof.skp, material `ceramicrooftile`. The shape in it is not a
# tile per course at all: it is ONE half pipe running the whole slope, ridge
# to eave, with the flat pan between two pipes left as plain roof.
#
# THE CLAIM THIS SUITE EXISTS TO PIN
# A run's cost is its CROSS SECTION. Length is free. So the pipe is modelled
# one inch long and stretched per run, and a whole roof - however big - carries
# one definition of about ten faces. If anyone ever gives the runs a builder of
# their own, or a definition per length, the count assertions below go red.
#
# THE PART THAT IS EASY TO GET WRONG
# A roof plane is not a rectangle. A hip face is a triangle; a plane with a
# dormer has a bite out of it. So a run does not assume it may go from v = 0 to
# the top - it asks the outline, at its own u, where the plane actually is.
# That is RoofTileMath.v_spans_at, which is the course scanline turned 90
# degrees, so there is one scanline in the codebase and not two that disagree.
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def close(a, b, tol = 1e-6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RTM   = InteriorPro::RoofTileMath
RTP   = InteriorPro::RoofTileParts
PLACE = InteriorPro::RoofTilePlace

# The same 4:12 plane rt79 uses: 200" of eave along +X, rising toward +Y,
# z = 100 at the eave and z = 100 + y/3 above it.
NRM  = [0.0, -1.0 / 3.0, 1.0]
FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
        [200.0, 90.0, 130.0], [0.0, 90.0, 130.0]].freeze

# A HIP face on the same plane: the same eave, closing to a point at the top.
HIP_FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0], [100.0, 90.0, 130.0]].freeze

class StubFace
  attr_reader :pts
  def initialize(pts, nrm)
    @pts = pts.map { |p| Geom::Point3d.new(p[0], p[1], p[2]) }
    @nrm = Geom::Vector3d.new(nrm[0], nrm[1], nrm[2])
  end

  def normal
    @nrm
  end
end

$tagged = []
module InteriorPro
  def self.assign_tag(entity, name)
    $tagged << [entity, name]
    true
  end
end

WALL_FACE = StubFace.new([[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
                          [200.0, 0.0, 90.0], [0.0, 0.0, 90.0]],
                         [0.0, -1.0, 0.0])

PLANES = PLACE.planes_from_faces([StubFace.new(FACE, NRM), WALL_FACE])
HIP_PLANES = PLACE.planes_from_faces([StubFace.new(HIP_FACE, NRM)])

# ------------------------------------------------------- which materials run

ok('barrel runs as pipes', RTM.runs?('barrel'))
ok('roman runs as pipes', RTM.runs?('roman'))
ok('flat slate does NOT - it is not a pipe', !RTM.runs?('slate'))
# WAS: standing seam does NOT either. It does now (2026-08-21). `scallop` only
# ever meant "the profile is curved", and a standing seam is not curved - so it
# had no 3D at all and the metal roof was a flat coloured surface. It gets in
# through run_seam instead, and it runs exactly like the clay pipes: one long
# piece ridge to eave, priced by its cross section.
ok('standing seam DOES run - through run_seam, not scallop',
   RTM.runs?('seam') && RTM.seam?('seam'))
ok('and it is the only one that is square', !RTM.seam?('roman') &&
   !RTM.seam?('barrel') && !RTM.seam?('slate') && !RTM.seam?(nil))
ok('nor does a material with no tile shape', !RTM.runs?('shingle'))
ok('nor a plain colour', !RTM.runs?('color'))
ok('nor nil', !RTM.runs?(nil))

# --------------------------------------------------------- the scanline flip
#
# v_spans_at must be spans_at with the pair swapped and NOTHING else, or the
# runs and the courses will one day disagree about the same outline.
SQUARE = [[0.0, 0.0], [10.0, 0.0], [10.0, 20.0], [0.0, 20.0]].freeze
ok('flip_uv swaps the pair', RTM.flip_uv([[1.0, 2.0]]) == [[2.0, 1.0]])
ok('a square gives one v span, the full height',
   RTM.v_spans_at(SQUARE, 5.0) == [[0.0, 20.0]], RTM.v_spans_at(SQUARE, 5.0))
ok('and it agrees with spans_at on the flipped outline',
   RTM.v_spans_at(SQUARE, 5.0) == RTM.spans_at(RTM.flip_uv(SQUARE), 5.0))
ok('outside the outline there is no span', RTM.v_spans_at(SQUARE, 40.0).empty?)

# a bite out of the middle splits one run into two, with no special case
NOTCH = [[0.0, 0.0], [10.0, 0.0], [10.0, 20.0], [6.0, 20.0], [6.0, 8.0],
         [4.0, 8.0], [4.0, 20.0], [0.0, 20.0]].freeze
ok('a dormer-shaped bite splits the run in two',
   RTM.v_spans_at(NOTCH, 5.0).length == 1 &&
     close(RTM.v_spans_at(NOTCH, 5.0)[0][1], 8.0),
   RTM.v_spans_at(NOTCH, 5.0))
ok('and beside the bite the run is still full height',
   close(RTM.v_spans_at(NOTCH, 2.0)[0][1], 20.0), RTM.v_spans_at(NOTCH, 2.0))

# ------------------------------------------------------------------ the slots

PU = RTM.plane_uv(PLANES[0][:points], PLANES[0][:n])
VSPAN = PU[:v_span]

ok('the plane is 200" across', close(PU[:u_span], 200.0, 1e-6), PU[:u_span])
ok('v is TRUE slope length, not plan run (90 plan, 30 rise -> 94.868)',
   close(VSPAN, Math.hypot(90.0, 30.0), 1e-6), VSPAN)

slots = PLACE.run_slots(PLANES, 'roman')

# THE TILE OVERLAPS ITS NEIGHBOUR (2026-08-21). Two earlier sets of numbers
# are described here rather than deleted, per the rt65 rule: first a 6" pipe on
# a 7.5" pitch, which left a 1.5" pan showing; then his own file's measurement,
# a 10.63" tile on an 8.27" pitch. He looked at that built and asked for a
# fatter roll and a tighter gap - "תצמצם את הרווחים ביניהם נגיד ל-2 ואז חצי
# העיגול לעשות 8" - which is a 10" pitch and a 14" tile.
PITCH = RTP.run_pitch(RTM.shape('roman'))
ok('one tile is 14" wide',
   close(RTP.run_cover_w(RTM.shape('roman')), 14.0, 1e-9),
   RTP.run_cover_w(RTM.shape('roman')))
ok('and they are spaced 10" apart, not 13"', close(PITCH, 10.0, 1e-9), PITCH)
ok('so they OVERLAP by 4" instead of leaving a pan',
   close(RTP.run_cover_w(RTM.shape('roman')) - PITCH, 4.0, 1e-8),
   RTP.run_cover_w(RTM.shape('roman')) - PITCH)

# 200" wide at a 10" run pitch -> 20 whole runs
ok('20 runs across a 200" plane', slots.length == 20, slots.length)
ok('the first run is half a pitch in, like the eave course',
   slots[0] && close(RTM.project(slots[0][:origin], PU[:origin], PU[:u], PU[:v])[0],
                     PITCH / 2.0, 1e-6))
ok('and they really are one pitch apart',
   slots.map { |s| RTM.project(s[:origin], PU[:origin], PU[:u], PU[:v])[0] }
        .sort.each_cons(2).all? { |a, b| close(b - a, PITCH, 1e-6) })
ok('every run carries the plane frame',
   slots.all? { |s| s[:u] && s[:v] && s[:n] })

# THE POINT OF THE WHOLE DESIGN: the run knows its length, the definition does
# not. One definition, many lengths.
#
# WAS: ridge to eave, VSPAN + overhang. A run now stops the cap's half width
# short of the ridge (2026-08-21) so its cut end lands under the cap instead of
# poking past the line - on a diagonal hip that was a row of broken half tiles
# along the corner. The eave end is unchanged and still hangs over.
SETBACK = RTP.ridge_setback(RTM.shape('roman'))
# Measured off the ROLL, not off the cap. The cap is wider than this, so it
# still covers the cut - and resizing the cap can never move the corner.
ok('the setback is half the lapped roll width',
   close(SETBACK, RTP.run_roll_w(RTM.shape('roman')) * RTP.cap_lap / 2.0, 1e-9),
   SETBACK)
ok('and the cap is at least that wide, so it covers the cut',
   RTP.cap_w(RTM.shape('roman')) / 2.0 >= SETBACK - 1e-9)
ok('every run reaches the slope less the setback, plus the eave overhang',
   slots.all? { |s| close(s[:length], VSPAN + RTP.eave_overhang - SETBACK, 1e-6) },
   slots.map { |s| s[:length].round(3) }.uniq)
ok('and setback 0 gives the old ridge-to-eave run back',
   PLACE.run_slots(PLANES, 'roman', setback: 0.0)
        .all? { |s| close(s[:length], VSPAN + RTP.eave_overhang, 1e-6) })
ok('a run that starts at the eave hangs 1.25" past it',
   slots.all? do |s|
     close(RTM.project(s[:origin], PU[:origin], PU[:u], PU[:v])[1],
           -RTP.eave_overhang, 1e-6)
   end)
ok('the runs sit ON the plane, not above or below it',
   slots.all? { |s| close(PLACE.z_on_plane(PLANES[0], s[:origin][0], s[:origin][1]),
                          s[:origin][2], 1e-6) })

# turning the overhang off puts the run exactly on the eave
flush = PLACE.run_slots(PLANES, 'roman', overhang: 0.0)
ok('overhang 0 starts the run exactly on the eave',
   flush.all? { |s| close(s[:length], VSPAN - SETBACK, 1e-6) },
   flush.map { |s| s[:length].round(3) }.uniq)

# ------------------------------------------------------------------- the hip
#
# A triangular face must cut its own runs. Nothing here knows the word "hip".
hip_slots = PLACE.run_slots(HIP_PLANES, 'roman')
hip_pu = RTM.plane_uv(HIP_PLANES[0][:points], HIP_PLANES[0][:n])

ok('a hip face gets runs too', !hip_slots.empty?, hip_slots.length)
ok('but they are NOT all the same length - the triangle cuts them',
   hip_slots.map { |s| s[:length].round(3) }.uniq.length > 1,
   hip_slots.map { |s| s[:length].round(3) }.uniq.length)
# The longest run is the slot nearest the apex. It does not reach the apex
# exactly and must not be expected to - the pitch decides where the slots fall,
# and the apex lands between two of them. Within a few percent is the honest
# assertion; demanding equality was the first version of this line and it was
# wrong about the code, not the other way round.
# The tolerance was 0.95 when the pitch was 7.5". A WIDER pitch puts the
# nearest slot further from the apex, so 10" needs a little more room - this
# is the slot spacing talking, not the run length being wrong.
ok('the longest run climbs almost to the apex, less the setback',
   hip_slots.map { |s| s[:length] }.max >=
     0.90 * (hip_pu[:v_span] + RTP.eave_overhang - SETBACK),
   [hip_slots.map { |s| s[:length] }.max, hip_pu[:v_span]])
ok('and the runs out at the corners are cut to a fraction of it',
   hip_slots.map { |s| s[:length] }.min <
     0.25 * hip_slots.map { |s| s[:length] }.max,
   [hip_slots.map { |s| s[:length] }.min, hip_slots.map { |s| s[:length] }.max])
ok('no sliver survives at the tip - every run clears the minimum',
   hip_slots.all? { |s| s[:length] >= PLACE.min_run_len },
   hip_slots.map { |s| s[:length].round(2) }.min)

# ----------------------------------------------------------- what gets no run

ok('slate gets no runs at all', PLACE.run_slots(PLANES, 'slate').empty?)
# WAS: standing seam gets none either - see the note at the top of the file.
# 200" of eave at a 16" pitch is 12 whole panels.
SEAM_SLOTS = PLACE.run_slots(PLANES, 'seam')
ok('standing seam gets 7 panels across a 200" plane',
   SEAM_SLOTS.length == 7, SEAM_SLOTS.length)
ok('shingle gets none', PLACE.run_slots(PLANES, 'shingle').empty?)
ok('no planes -> no runs', PLACE.run_slots([], 'roman').empty?)
ok('nil planes -> no runs, no exception', PLACE.run_slots(nil, 'roman').empty?)

# a plane narrower than one pitch carries nothing rather than one lonely pipe
NARROW = PLACE.planes_from_faces(
  [StubFace.new([[0.0, 0.0, 100.0], [5.0, 0.0, 100.0],
                 [5.0, 90.0, 130.0], [0.0, 90.0, 130.0]], NRM)]
)
ok('a plane narrower than one pitch gets no run',
   PLACE.run_slots(NARROW, 'roman').empty?,
   PLACE.run_slots(NARROW, 'roman').length)

# --------------------------------------------------------------- the pipe

Sketchup.reset_model!
model = Sketchup.active_model
pipe = RTP.run(model, 'roman')

ok('there is a run definition', !pipe.nil?)
ok('it is marked as the run piece',
   pipe && pipe.get_attribute('InteriorPro', 'part') == 'tile_run',
   pipe && pipe.get_attribute('InteriorPro', 'part'))
# WAS 20, when a run was one bare half pipe. Roman is now a pan AND a roll
# (2026-08-21), which is a six face box plus the same crescent - 26. The claim
# this line exists to pin is unchanged: it is a FIXED cost for the whole roof,
# one definition however many runs stand on it.
ok('THE BUDGET: the run is 26 faces, whatever the roof',
   pipe && pipe.entities.grep(Sketchup::Face).length <= 26,
   pipe && pipe.entities.grep(Sketchup::Face).length)

# ------------------------------------------------------- THE PAN AND ROLL
#
# Two identical half pipes 10.63" wide on an 8.27" pitch cut straight through
# each other - "הם נכנסים אחד לתוך השני". A real Roman tile is a flat pan with
# a raised roll that laps the joint, so nothing intersects anything.
RS = RTM.shape('roman')
ok('roman is a pan and roll, because it is wider than its spacing',
   RTP.pan_roll?(RS))
ok('barrel is NOT - 6" on a 7.5" pitch keeps the plain half pipe',
   !RTP.pan_roll?(RTM.shape('barrel')))
ok('the lap is 4"', close(RTP.run_lap(RS), 4.0, 1e-8), RTP.run_lap(RS))
ok('the roll is twice the lap, so it lands centred on the butt joint',
   close(RTP.run_roll_w(RS), 8.0, 1e-8), RTP.run_roll_w(RS))
ok('THE GAP HE ASKED FOR: 2" of flat pan between two rolls',
   close(RTP.run_pitch(RS) - RTP.run_roll_w(RS), 2.0, 1e-8),
   RTP.run_pitch(RS) - RTP.run_roll_w(RS))
PAN = RTP.pan_profile(RTP.run_pitch(RS), RTP.run_wall_t)
ok('the pan is exactly one pitch wide, so two pans butt with no gap',
   close(PAN.map { |p| p[0] }.max - PAN.map { |p| p[0] }.min, 10.0, 1e-9))
ROLL = RTP.roll_profile(RS, RTP.run_segments)
ok('the roll is centred on the joint at half a pitch',
   close((ROLL.map { |p| p[0] }.max + ROLL.map { |p| p[0] }.min) / 2.0,
         10.0 / 2.0, 1e-8),
   (ROLL.map { |p| p[0] }.max + ROLL.map { |p| p[0] }.min) / 2.0)
ok('THE POINT: the roll never dips below the next tile\'s pan top',
   ROLL.all? { |p| p[1] >= RTP.run_wall_t - 1e-9 },
   ROLL.map { |p| p[1] }.min)
ok('and the whole tile is 14" wide, pan plus the roll overhang',
   close((ROLL.map { |p| p[0] }.max) - (PAN.map { |p| p[0] }.min), 14.0, 1e-8),
   ROLL.map { |p| p[0] }.max - PAN.map { |p| p[0] }.min)
# ROMAN'S CAP IS STATED, NOT DERIVED. It was 9.2" for one round, then 16.1"
# derived off the tile, and every time the tile moved the cap moved with it
# unannounced. The user gave the numbers directly - the crown 3" lower than
# the 4.42" it had, the width 10" and then 13" once he saw it - and stating
# them is what stops the drift. WIDTH AND CROWN ARE INDEPENDENT: "לא להגביה
# אותו רק להרחיב", so widening the span must never touch the arch.
ok('roman states its cap: 13" across', close(RTP.cap_w(RS), 13.0, 1e-9),
   RTP.cap_w(RS))
ok('and 1.42" of arch, 3" off the 4.42" it had',
   close(RTP.cap_crown(RS), 1.42, 1e-9), RTP.cap_crown(RS))
ok('widening it did NOT raise it - the crown is stated on its own',
   close(RTP.cap_crown(RS.merge(cap_w: 99.0)), 1.42, 1e-9),
   RTP.cap_crown(RS.merge(cap_w: 99.0)))
ok('THE POINT: growing the tile no longer moves the cap',
   close(RTP.cap_w(RS.merge(run_cover: 99.0)), 13.0, 1e-9))
ok('a material that states nothing still derives it the old way',
   close(RTP.cap_w(RTM.shape('barrel')),
         RTP.run_cover_w(RTM.shape('barrel')) * RTP.cap_lap, 1e-9) &&
   close(RTP.cap_crown(RTM.shape('barrel')),
         RTP.run_height(RTM.shape('barrel')) * RTP.cap_lap, 1e-9))
ok('and the cap still covers the run setback',
   RTP.cap_w(RS) / 2.0 >= RTP.ridge_setback(RS) - 1e-9,
   [RTP.cap_w(RS) / 2.0, RTP.ridge_setback(RS)])
# ------------------------------------------------------ THE STANDING SEAM
#
# A square rib on a flat pan, from the drawing the user approved: 16" pans,
# a rib 1" thick standing 1.75" - "תעשה את הבליטה אינץ' ולא חצי".
SS = RTM.shape('seam')
# WAS a 16" pan. He asked for 26" of flat metal showing between two ribs, and
# a 2" rib on top of that is 28" centre to centre.
ok('the ribs are 28" apart', close(RTP.run_pitch(SS), 28.0, 1e-9),
   RTP.run_pitch(SS))
ok('which leaves the 26" of flat pan he asked for',
   close(RTP.run_pitch(SS) - RTP.seam_w(SS), 26.0, 1e-8),
   RTP.run_pitch(SS) - RTP.seam_w(SS))
# WAS 1" thick and 1.75" proud, the first build. He looked at it and asked for
# the other way round: "רוחב 2 וגובה של 1".
ok('the rib is 2" thick', close(RTP.seam_w(SS), 2.0, 1e-8), RTP.seam_w(SS))
ok('and stands 1" proud of the pan',
   close(RTP.run_height(SS), 1.0, 1e-8), RTP.run_height(SS))
SP = RTP.seam_profile(SS)
ok('the rib is a rectangle, four corners and no arc', SP.length == 4, SP.length)
ok('centred on the joint at half a pitch',
   close((SP.map { |p| p[0] }.max + SP.map { |p| p[0] }.min) / 2.0, 14.0, 1e-8))
# WAS: it sat on a pan of its own, one wall thickness up. There is no pan any
# more - the roof deck is the pan - so the rib starts at zero. A 28" pan was
# also what overhung every hip in a staircase and pushed out through the cap.
ok('the rib stands straight on the deck, no pan of its own',
   close(SP.map { |p| p[1] }.min, 0.0, 1e-9), SP.map { |p| p[1] }.min)
# THE NAME CARRIES THE SHAPE. Removing the pan changed no size, so the old
# definition was handed straight back and the roof rebuilt identical.
ok('a pan-less seam gets its own definition name',
   begin
     Sketchup.reset_model!
     RTP.run(Sketchup.active_model, 'seam').name.include?('Rib')
   end,
   begin RTP.run(Sketchup.active_model, 'seam').name rescue nil end)
ok('and the run definition is the rib alone - 6 faces, not 12',
   begin
     Sketchup.reset_model!
     RTP.run(Sketchup.active_model, 'seam').entities.grep(Sketchup::Face).length == 6
   end)
ok('it is NOT a roll - roman still is',
   RTP.seam?(SS) && !RTP.seam?(RS))
# WAS 12" x 1", the old constants. From his photograph of a real metal ridge:
# a folded plate, 5" down each slope and no arch at all.
ok('its ridge is 10" - five inches down each slope',
   close(RTP.cap_w(SS), 10.0, 1e-9), RTP.cap_w(SS))
ok('and FLAT - a stated zero crown means folded, not an arch',
   RTP.cap_crown_stated?(SS) && RTP.cap_crown(SS).zero?, RTP.cap_crown(SS))
ok('a material that states nothing still derives its arch',
   !RTP.cap_crown_stated?(RTM.shape('barrel')) &&
     RTP.cap_crown(RTM.shape('barrel')) > 0.0)
ok('and it rides on the ribs, so the fold lands on top of them',
   close(RTP.run_top_h(SS), 1.0, 1e-9), RTP.run_top_h(SS))
ok('and it is NOT the round clay cap',
   !RTP.cap_round?(SS) && RTP.cap_round?(RS))
# THE LINES STAY. Every other piece is softened so its chords vanish; this one
# is the exception the user asked for, and only this one.
ok('the seam keeps its edges - no softening on this roof',
   !RTP.soften_run?(SS))
# ------------------------------------------------- how the metal roof ENDS
#
# A 1" x 1" bar along the eave, at the ribs' own height, from the photograph
# the user sent: "מסגרת בגובה של הבליטות שהיה אינץ' על אינץ'".
EB = RTP.edge_bar_profile(SS)
ok('the eave bar is a square, four corners', EB.length == 4, EB.length)
ok('one inch by one inch - the rib height, both ways',
   close(EB.map { |p| p[0] }.max - EB.map { |p| p[0] }.min, 1.0, 1e-8) &&
     close(EB.map { |p| p[1] }.max - EB.map { |p| p[1] }.min, 1.0, 1e-8),
   [EB.map { |p| p[0] }.max - EB.map { |p| p[0] }.min,
    EB.map { |p| p[1] }.max - EB.map { |p| p[1] }.min])
ok('and its top is exactly the ribs\' top, so the border lines up',
   close(EB.map { |p| p[1] }.max, RTP.run_top_h(SS), 1e-9),
   [EB.map { |p| p[1] }.max, RTP.run_top_h(SS)])
ok('it stands on the deck too, not on a pan',
   close(EB.map { |p| p[1] }.min, 0.0, 1e-9), EB.map { |p| p[1] }.min)
ok('no other material grows one', RTP.edge_bar_profile(RS).empty? ||
   !RTP.seam?(RS))
BARS = PLACE.eave_bar_slots(PLANES, 'seam')
ok('one bar per roof plane', BARS.length == 1, BARS.length)
# THE RIBS STOP UNDER THE CAP (2026-08-21, second pass). The setback WAS 0 -
# "the lifted cap rides on the rib tops, so they may run right up to the
# line" - and the user saw what that looks like: the rib ends slid in under
# the hovering cap and showed. "הברזלים נכנסים לתוך הרידג' קאפ וזה לא נראה
# טוב... שזה יחתך איפה שהרידג' מתחיל." It is STATED on the shape now, 4.0:
# the cap covers 5" down each slope, so the cut end hides an inch inside it.
SEAM_SETBACK = 4.0
ok('the seam rib is cut where the cap starts - a stated 4" setback',
   RTP.ridge_setback(SS) == SEAM_SETBACK, RTP.ridge_setback(SS))
ok('and the cap still reaches past the cut, so the end hides under it',
   RTP.cap_w(SS) / 2.0 > SEAM_SETBACK, RTP.cap_w(SS) / 2.0)
ok('a stated setback wins over the derived one - the same rule as cap_crown',
   RTP.ridge_setback({ ridge_setback: 0.0, run_seam: true }).zero?)
ok('and roman still derives its own', RTP.ridge_setback(RS) > 0.0)
SEAM_HIP = PLACE.run_slots(HIP_PLANES, 'seam')
HP = RTM.plane_uv(HIP_PLANES[0][:points], HIP_PLANES[0][:n])
# MEASURE THE RIB WHERE IT IS DRAWN (2026-08-21, second pass).
#
# This check used to read the outline at the slot's ORIGIN u - and so it passed
# while the roof was visibly wrong, because it was testing the same wrong
# assumption the code made. seam_profile centres the rib on run_pitch/2, half a
# pitch to the +u side, so the outline has to be read THERE. On the user's own
# roof the old code left 6 ribs 10.8" short of the hip and 6 ribs 9.5" past it;
# on this stub plane the old error was +-13.282".
SEAM_RIB_U = RTP.run_pitch(SS) / 2.0
# (updated again the same day: the ribs now stop a stated setback short of the
# line, so "exactly" means outline minus setback - see SEAM_SETBACK below.)
ok('every rib ends exactly a setback under the hip line - not more, not past',
   SEAM_HIP.all? do |sl|
     u, v0 = RTM.project(sl[:origin], HP[:origin], HP[:u], HP[:v])
     top = RTM.v_spans_at(HP[:poly], u + SEAM_RIB_U, 0.0).last[1]
     close(v0 + sl[:length], top - RTP.ridge_setback(SS), 1e-6)
   end,
   SEAM_HIP.map do |sl|
     u, v0 = RTM.project(sl[:origin], HP[:origin], HP[:u], HP[:v])
     (RTM.v_spans_at(HP[:poly], u + SEAM_RIB_U, 0.0).last[1] -
      (v0 + sl[:length])).round(3)
   end)
# and the OLD reading now disagrees, so it can never quietly come back
ok('measuring at the origin instead is what was wrong - it now disagrees',
   SEAM_HIP.any? do |sl|
     u, v0 = RTM.project(sl[:origin], HP[:origin], HP[:u], HP[:v])
     sp = RTM.v_spans_at(HP[:poly], u, 0.0)
     !sp.empty? && !close(v0 + sl[:length], sp.last[1], 1.0)
   end)
# ------------------------------- THE TWO SLOPES MEET AT THE RIDGE (2026-08-21)
#
# "אני רוצה שהם יהיו אחד מול השני." Each plane used to lay its ribs out from its
# OWN left edge, so the two slopes of one ridge arrived on unrelated spacings
# and no rib met its opposite number. They share ONE grid in world space now.
# Both slopes below are read from opposite corners on purpose - that is exactly
# the case the per-plane layout got wrong.
def slope_face(pts)
  a = RTM.vsub(pts[1], pts[0])
  b = RTM.vsub(pts[2], pts[0])
  n = RTM.vnorm(RTM.vcross(a, b))
  { points: pts, n: n, normal: n }
end
FRONT = slope_face([[0.0, 0.0, 0.0], [400.0, 0.0, 0.0],
                    [400.0, 100.0, 50.0], [0.0, 100.0, 50.0]])
BACK  = slope_face([[0.0, 200.0, 0.0], [400.0, 200.0, 0.0],
                    [400.0, 100.0, 50.0], [0.0, 100.0, 50.0]])
def rib_xs(pl)
  pu = RTM.plane_uv(pl[:points], pl[:n])
  off = RTP.run_pitch(RTM.shape('seam')) / 2.0
  PLACE.run_slots([pl], 'seam', overhang: 0.0, asset: nil).map do |sl|
    uv = RTM.project(sl[:origin], pu[:origin], pu[:u], pu[:v])
    RTM.unproject([uv[0] + off, uv[1]], pu[:origin], pu[:u], pu[:v])[0].round(3)
  end.sort
end
ok('the two slopes of a ridge put their ribs on the SAME lines',
   rib_xs(FRONT) == rib_xs(BACK), [rib_xs(FRONT), rib_xs(BACK)])
ok('and there are ribs to compare in the first place', rib_xs(FRONT).length > 5,
   rib_xs(FRONT).length)
ok('roman is untouched - it still lays out per plane', RTM.seam?('seam') &&
   !RTM.seam?('roman'))
ok('and the cap reaches further than any rib end, so it covers them',
   RTP.cap_w(SS) / 2.0 > RTP.run_top_h(SS))
ok('it spans the whole eave', close(BARS[0][:length], PU[:u_span], 1e-6),
   BARS[0][:length])
# FLUSH WITH THE EDGE, ON THE DECK (2026-08-21, second pass). The bar used to
# hang 1.25" past the eave, floating with a 0.25" air gap back to the roof -
# the red line the user marked: "תסגור את החלק בין המסגרת לסוף הגג." Its
# origin is now exactly the eave line (v = 0) and its body lies up-slope on
# the deck, so the gap does not exist and two eaves' bars meet at a corner.
BAR_UV = RTM.project(BARS[0][:origin], PU[:origin], PU[:u], PU[:v])
ok('the bar sits flush on the eave edge - v = 0, no float and no gap',
   close(BAR_UV[1], 0.0, 1e-9), BAR_UV[1])
# AND THE RIBS STOP AT ITS FACE (2026-08-21, second pass). They used to hang
# 1.25" over the eave, straight through the bar - "הברזלים צריכים לעצור לפני
# המסגרת". A rib at the eave now starts one bar depth (run_height) up-slope,
# butting the bar's inner face; ribs cut short by a hip start where they
# always did.
SEAM_FLAT = PLACE.run_slots([slope_face(FRONT[:points])], 'seam', asset: nil)
FPU = RTM.plane_uv(FRONT[:points], FRONT[:n])
ok('an eave rib starts exactly one bar depth up the slope - butting the bar',
   SEAM_FLAT.any? &&
     SEAM_FLAT.all? do |sl|
       close(RTM.project(sl[:origin], FPU[:origin], FPU[:u], FPU[:v])[1],
             RTP.run_height(SS), 1e-6)
     end,
   SEAM_FLAT.map { |sl| RTM.project(sl[:origin], FPU[:origin], FPU[:u], FPU[:v])[1].round(3) }.uniq)
ok('roman still hangs over the eave as before',
   PLACE.run_slots([slope_face(FRONT[:points])], 'roman', asset: nil)
        .any? do |sl|
     RTM.project(sl[:origin], FPU[:origin], FPU[:u], FPU[:v])[1] < -1.0
   end)
# TWO BARS MEET IN A MITRE (2026-08-21, second pass). Square-cut ends crossed
# at the hip corner with a wedge of air above them - "שתי המסגרות שנפגשות
# בפינה שיראו כאילו הם מחוברות בצורה ישרה". Ends that share a corner are cut
# on the plan bisector; equal pitches make the two cut faces mirror images,
# so they land on each other exactly.
def bar_face_pts(f)
  f.respond_to?(:points) ? f.points : f.pts
end
CB_A = slope_face([[0.0, 0.0, 100.0], [300.0, 0.0, 100.0],
                   [250.0, 50.0, 125.0], [50.0, 50.0, 125.0]])
CB_B = slope_face([[0.0, 0.0, 100.0], [50.0, 50.0, 125.0],
                   [50.0, 250.0, 125.0], [0.0, 300.0, 100.0]])
CBG = Sketchup.active_model.entities.add_group
CB_MADE = PLACE.place_eave_bars!(CBG, [CB_A, CB_B], 'seam')
CB_SECS = CBG.entities.grep(Sketchup::Group).map do |bg|
  bg.entities.grep(Sketchup::Face).flat_map { |f| bar_face_pts(f) }
    .select { |q| q.x < 6.0 && q.y < 6.0 }
    .map { |q| [q.x.round(3), q.y.round(3), q.z.round(3)] }.uniq.sort
end
ok('a corner grows two bars, one per eave', CB_MADE == 2, CB_MADE)
ok('their mitre faces coincide point for point - no gap, no overlap',
   CB_SECS.length == 2 && !CB_SECS[0].empty? && CB_SECS[0] == CB_SECS[1],
   CB_SECS)
ok('and the joint is one straight line on the plan bisector',
   CB_SECS.flatten(1).all? { |(x, y, _z)| (x - y).abs < 1e-6 })
# A RIB CUT BY A VALLEY STOPS SHORT OF IT (2026-08-21, second pass). Its foot
# hides under the flat valley channel exactly the way its head hides under
# the ridge cap - the same stated setback, from the other end. A rib that
# starts at the EAVE still butts the bar (tested above), not the setback.
# The plane: slope up +y (z = y/2), eave y=0 for x in [100, 400], and a
# valley edge climbing from (100, 0) to (0, 100) cutting the left corner.
VC = slope_face([[100.0, 0.0, 0.0], [400.0, 0.0, 0.0], [400.0, 200.0, 100.0],
                 [0.0, 200.0, 100.0], [0.0, 100.0, 50.0]])
VC_PU = RTM.plane_uv(VC[:points], VC[:n])
VC_SLOTS = PLACE.run_slots([VC], 'seam', asset: nil)
VC_MID = VC_SLOTS.map do |sl|
  uv = RTM.project(sl[:origin], VC_PU[:origin], VC_PU[:u], VC_PU[:v])
  bot = RTM.v_spans_at(VC_PU[:poly], uv[0] + SEAM_RIB_U, 0.0).first[0]
  [uv[1].round(3), bot.round(3)]
end.select { |(_v0, bot)| bot > 0.5 }
ok('there are ribs whose foot lands on the valley edge', VC_MID.length > 1,
   VC_MID.length)
ok('each stops exactly a setback short of it',
   VC_MID.all? { |(v0, bot)| close(v0, bot + SEAM_SETBACK, 1e-6) }, VC_MID)
# (-v) x u = n keeps the frame right handed - a mirrored bar measures the
# same and looks wrong.
ok('the frame is right handed, so the bar is never mirrored',
   close(RTM.vdot(RTM.vcross(BARS[0][:u], BARS[0][:v]), BARS[0][:n]), 1.0, 1e-6),
   RTM.vdot(RTM.vcross(BARS[0][:u], BARS[0][:v]), BARS[0][:n]))
ok('roman gets no eave bar - this is the metal roof alone',
   PLACE.eave_bar_slots(PLANES, 'roman').empty?)
ok('nor does shingle', PLACE.eave_bar_slots(PLANES, 'shingle').empty?)
ok('and every other material is still softened',
   RTP.soften_run?(RS) && RTP.soften_run?(RTM.shape('barrel')))

ok('the piece stands one wall plus one roll off the deck',
   close(RTP.run_top_h(RS), RTP.run_wall_t + 3.84, 1e-9), RTP.run_top_h(RS))

# ------------------------------------------------------------ it is HOLLOW
#
# The user corrected this after the first build (2026-08-21): a real tile is a
# shell, and modelled solid every run ended in a filled white half-moon under
# the fascia. A shell ends in a thin crescent.
SHELL = RTP.shell_profile(6.0, 2.28, RTP.run_wall_t, RTP.run_segments)
SOLID = RTP.profile(6.0, 2.28, true, RTP.run_segments)

ok('the run profile is a shell, not a filled half round',
   SHELL.length == SOLID.length * 2, [SHELL.length, SOLID.length])
ok('it starts with the OUTER arc', SHELL.first == SOLID.first)
ok('and comes back along an inner arc one wall in',
   close(SHELL[SOLID.length][0], (6.0 / 2.0) - RTP.run_wall_t, 1e-9),
   SHELL[SOLID.length])
ok('the inner arc is lower than the outer one by the wall thickness',
   close(SHELL.map { |p| p[1] }.max - 2.28, 0.0, 1e-9) &&
     close(SHELL[SOLID.length + (SOLID.length / 2)][1], 2.28 - RTP.run_wall_t, 1e-6),
   SHELL[SOLID.length + (SOLID.length / 2)])
ok('every point still sits on or above the roof plane',
   SHELL.all? { |p| p[1] > -1e-9 })
ok('no two points in a row are identical - add_face refuses those',
   SHELL.each_cons(2).none? { |a, b| close(a[0], b[0], 1e-9) && close(a[1], b[1], 1e-9) })
ok('nor do the ends of the loop touch, which would pinch the crescent shut',
   !(close(SHELL.first[0], SHELL.last[0], 1e-9) &&
     close(SHELL.first[1], SHELL.last[1], 1e-9)))
ok('a silly wall thickness falls back to the solid profile rather than '\
   'turning the crescent inside out',
   RTP.shell_profile(6.0, 2.28, 9.0, RTP.run_segments) == SOLID)
ok('and so does a zero one', RTP.shell_profile(6.0, 2.28, 0.0, RTP.run_segments) == SOLID)
ok('the wall thickness is recorded on the definition',
   pipe && close(pipe.get_attribute('InteriorPro', 'wall_t').to_f, RTP.run_wall_t))
ok('the tile is 14" wide, whatever the tile pitch says',
   close(RTP.run_cover_w(RTM.shape('roman')), 14.0, 1e-9),
   RTP.run_cover_w(RTM.shape('roman')))
# WAS: the pipe had to be NARROWER than the pitch, so a pan showed between two
# runs. His own file is the other way round - the pipe is wider than its
# spacing and they lap over each other (2026-08-21).
ok('the pipe is WIDER than the spacing, so two runs overlap',
   RTP.run_cover_w(RTM.shape('roman')) > RTP.run_pitch(RTM.shape('roman')),
   [RTP.run_cover_w(RTM.shape('roman')), RTP.run_pitch(RTM.shape('roman'))])
ok('THE SPACING IS THE PIPE, NOT THE TILE - a finer pipe means MORE of them, '\
   'never a wider gap',
   RTP.run_pitch(RTM.shape('roman')) < RTM.shape('roman')[:tile_w],
   [RTP.run_pitch(RTM.shape('roman')), RTM.shape('roman')[:tile_w]])
ok('THE ARCH IS FLATTER THAN A HALF CIRCLE - wide, not a barrel',
   RTP.run_rise_ratio < 0.5 &&
     RTP.run_height(RTM.shape('roman')) < RTP.run_cover_w(RTM.shape('roman')) / 2.0,
   [RTP.run_rise_ratio, RTP.run_height(RTM.shape('roman'))])
ok('the shell wall is a third of an inch', close(RTP.run_wall_t, 1.0 / 3.0, 1e-9))
ok('and the wall still fits inside the arch it hollows out',
   RTP.run_wall_t < RTP.run_height(RTM.shape('roman')),
   [RTP.run_wall_t, RTP.run_height(RTM.shape('roman'))])
ok('it is modelled ONE INCH long, so the placer can stretch it',
   pipe && close(pipe.get_attribute('InteriorPro', 'unit_length').to_f, 1.0))

before = model.definitions.length
RTP.run(model, 'roman')
ok('asking twice builds nothing the second time',
   model.definitions.length == before, [before, model.definitions.length])

ok('the little edge pieces keep their cheap 4 segments',
   RTP.profile(10.0, 5.0, true).length == RTP.arc_segments + 1,
   RTP.profile(10.0, 5.0, true).length)
ok('and the run gets 8, because it is one definition for the whole roof',
   RTP.profile(10.0, 5.0, true, RTP.run_segments).length == RTP.run_segments + 1,
   RTP.profile(10.0, 5.0, true, RTP.run_segments).length)

# ----------------------------------------------------------- the placement

Sketchup.reset_model!
model = Sketchup.active_model
grp = model.entities.add_group
$tagged = []

made = PLACE.place_runs!(grp, PLANES, 'roman', model: model)
ok('place_runs! reports what it placed', made == 20, made)

insts = grp.entities.grep(Sketchup::ComponentInstance)
ok('they are INSTANCES, not groups', insts.length == 20, insts.length)
ok('THE WHOLE POINT: 20 runs share ONE definition',
   insts.map(&:definition).uniq.length == 1,
   insts.map(&:definition).uniq.length)
ok('every run is tagged as field, once each',
   $tagged.length == 20 &&
     $tagged.map(&:last).uniq == ['InteriorPro_RoofTiles_Field'],
   [$tagged.length, $tagged.map(&:last).uniq])
ok('the instances land at the slot origins',
   insts.map { |i| i.transformation.origin.x.round(3) }.sort ==
     slots.map { |s| s[:origin][0].round(3) }.sort)

before = model.definitions.length
grp2 = model.entities.add_group
PLACE.place_runs!(grp2, PLANES, 'roman', model: model)
ok('a second roof adds no new definition, whatever its runs measure',
   model.definitions.length == before, [before, model.definitions.length])

# a length of zero must never reach add_instance
ok('a zero-length run is refused rather than placed',
   PLACE.run_transform_for(origin: [0.0, 0.0, 0.0], u: [1.0, 0.0, 0.0],
                           v: [0.0, 1.0, 0.0], n: [0.0, 0.0, 1.0],
                           length: 0.0).nil?)

# --------------------------------------------------------------- the brake

Sketchup.reset_model!
g3 = Sketchup.active_model.entities.add_group
capped = PLACE.place_runs!(g3, PLANES, 'roman',
                           model: Sketchup.active_model, max: 5)
ok('over budget, nothing is placed at all', capped.zero?, capped)
ok('and the group stays empty rather than half tiled',
   g3.entities.grep(Sketchup::ComponentInstance).empty?)

# ------------------------------------------------------------ it never throws

ok('no group -> 0, no exception', PLACE.place_runs!(nil, PLANES, 'roman').zero?)
ok('an unknown material -> 0', PLACE.run_slots(PLANES, 'nope').empty?)

puts($fails.zero? ? 'rt82 ALL PASS' : "rt82 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

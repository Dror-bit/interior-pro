# encoding: utf-8
# rt79 - roof_tile_place.rb: the eave course (2026-08-19,
# ROOF_TILES_PROPOSAL.md §6 step 4).
#
# WHAT THE FILE UNDER TEST IS FOR
# Instant Roof's whole 63x59ft roof carries 408 instances of ONE single-face
# definition, va_BirdStop, along the eave and nothing above it
# (valiroof_report.txt). rt77 already pinned that our four pieces are cheap and
# built once. This suite pins the other half: that we PLACE them as instances,
# in the right places, at the right height, and that we stop instead of
# flooding the model when a roof is absurdly big.
#
# THE ONE THING THAT IS EASY TO GET WRONG, and it has its own block below:
# RoofManager.roof_edges reads its z from `zmap`, which is the UNDERSIDE of
# the slab - deliberately, because that is what the fascia hangs from. A tile
# sitting at that height is buried inside the roof. So the height of a slot is
# solved on the PLANE, and the edge only supplies x and y.
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

RTP  = InteriorPro::RoofTileParts
RTM  = InteriorPro::RoofTileMath
PLACE = InteriorPro::RoofTilePlace

# A 4:12 plane, 200" of eave along +X, rising toward +Y, sitting at z = 100 at
# the eave. z = 100 + y/3.
#   normal proportional to (0, -1/3, 1) -> normalised below by plane_frame.
NRM  = [0.0, -1.0 / 3.0, 1.0]
FACE = [[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
        [200.0, 90.0, 130.0], [0.0, 90.0, 130.0]].freeze

# A stub face is anything that answers `pts` and `normal`; that is exactly what
# planes_from_faces reads. Building one by hand keeps this suite independent of
# the whole roof builder.
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

# The shared stub makes InteriorPro.assign_tag a no-op, so tagging cannot be
# read back off the model - and the 2D contract says every piece must carry
# its tag. So record the calls instead. Reopened HERE, in this suite, rather
# than in sketchup_stub.rb, so no other suite changes behaviour (rt36 reopens
# Face the same way and for the same reason).
$tagged = []
module InteriorPro
  def self.assign_tag(entity, name)
    $tagged << [entity, name]
    true
  end
end

# A VERTICAL face - the slab edge. It must never be offered a tile.
WALL_FACE = StubFace.new([[0.0, 0.0, 100.0], [200.0, 0.0, 100.0],
                          [200.0, 0.0, 90.0], [0.0, 0.0, 90.0]],
                         [0.0, -1.0, 0.0])

PLANES = PLACE.planes_from_faces([StubFace.new(FACE, NRM), WALL_FACE])

# ---------------------------------------------------------------- the planes

ok('the sloped face becomes a plane', PLANES.length == 1, PLANES.length)
ok('the VERTICAL slab-edge face is refused', PLANES.length == 1)
ok('u runs across the slope, dead horizontal',
   PLANES[0] && close(PLANES[0][:u][2], 0.0, 1e-9), PLANES[0] && PLANES[0][:u])
ok('v climbs', PLANES[0] && PLANES[0][:v][2] > 0.0, PLANES[0] && PLANES[0][:v])
ok('n points up', PLANES[0] && PLANES[0][:n][2] > 0.0)

# -------------------------------------------------------------- the geometry

ok('z_on_plane at the eave', close(PLACE.z_on_plane(PLANES[0], 50.0, 0.0), 100.0, 1e-6))
ok('z_on_plane 30" up the plan run climbs 10"',
   close(PLACE.z_on_plane(PLANES[0], 50.0, 30.0), 110.0, 1e-6),
   PLACE.z_on_plane(PLANES[0], 50.0, 30.0))

ok('plan_dist_to_segment measures ACROSS, not along',
   close(PLACE.plan_dist_to_segment([0.0, 0.0], [100.0, 0.0], [50.0, 7.0]), 7.0, 1e-9))
ok('and clamps past the end',
   close(PLACE.plan_dist_to_segment([0.0, 0.0], [100.0, 0.0], [130.0, 0.0]), 30.0, 1e-9))

# ------------------------------------------------------------------ the slots
#
# THE HEIGHT TRAP. The eave segment is handed in at z = 96 - four inches BELOW
# the roof plane, exactly the way roof_edges hands over the slab underside.
# Every slot must still come out at 100, the height of the plane.
EAVE = { eave: [{ kind: :eave, edge: 0, wall_id: 'w0',
                  a: [0.0, 0.0, 96.0], b: [200.0, 0.0, 96.0] }],
         rake: [], ridge: [], hip: [] }.freeze

slots = PLACE.eave_slots(PLANES, EAVE, 'barrel')

# 200" of eave, 13" barrel tile -> 15 whole tiles (195"), the 16th does not fit
ok('only WHOLE tiles are placed (15 of 13" in 200")', slots.length == 15,
   slots.length)
ok('the first slot is half a tile in',
   slots[0] && close(slots[0][:origin][0], 6.5, 1e-6), slots[0] && slots[0][:origin][0])
ok('slots are one tile width apart',
   slots.each_cons(2).all? { |a, b| close(b[:origin][0] - a[:origin][0], 13.0, 1e-6) })
ok('THE HEIGHT TRAP: slots sit on the PLANE (100), not on the '\
   'slab underside the edge carried (96)',
   slots.all? { |s| close(s[:origin][2], 100.0, 1e-6) },
   slots.map { |s| s[:origin][2] }.uniq)
ok('no tile is centred outside the run',
   slots.all? { |s| s[:origin][0] > 0.0 && s[:origin][0] < 200.0 })
ok('every slot carries the plane frame',
   slots.all? { |s| s[:u] && s[:v] && s[:n] })
ok('every slot remembers which wall it is on',
   slots.all? { |s| s[:wall_id] == 'w0' && s[:edge] == 0 })

# an eave shorter than one tile gets nothing at all
SHORT = { eave: [{ kind: :eave, edge: 0, a: [0.0, 0.0, 96.0],
                   b: [10.0, 0.0, 96.0] }] }.freeze
ok('an eave shorter than one tile gets no piece',
   PLACE.eave_slots(PLANES, SHORT, 'barrel').empty?)

# an eave that belongs to no plane gets nothing - never a guessed slope
ORPHAN = { eave: [{ kind: :eave, edge: 0, a: [0.0, 900.0, 96.0],
                    b: [200.0, 900.0, 96.0] }] }.freeze
ok('an eave on no plane is skipped, not guessed at',
   PLACE.eave_slots(PLANES, ORPHAN, 'barrel').empty?)

# only the RAKE/RIDGE/HIP buckets are ignored at this step
ONLY_RAKE = { eave: [], rake: [{ a: [0.0, 0.0, 96.0], b: [200.0, 0.0, 96.0] }] }.freeze
ok('step 4 places the EAVE only - a rake gets nothing yet',
   PLACE.eave_slots(PLANES, ONLY_RAKE, 'barrel').empty?)

# a material with no tile shape is left alone
ok('shingle has no tile shape, so no pieces',
   PLACE.eave_slots(PLANES, EAVE, 'shingle').empty?)
ok('nor does a plain colour', PLACE.eave_slots(PLANES, EAVE, 'color').empty?)

# The spacing follows the material's own tile width, and nothing else.
# WAS: slate at 12" gives 16 where barrel's 13" gives 15. Slate went to 13" on
# 2026-08-21c, so the pair that proves the point is now slate against Spanish
# Tile, which is 7".
sl = PLACE.eave_slots(PLANES, EAVE, 'slate')
ok('slate (13") gives 15 pieces, the same as barrel\'s 13"',
   sl.length == 15, sl.length)
mt = PLACE.eave_slots(PLANES, EAVE, 'metaltile')
ok('Spanish Tile (7") is narrower, so it gives more of them',
   mt.length > sl.length, [mt.length, sl.length])

# ------------------------------------------------------------- the placement

Sketchup.reset_model!
model = Sketchup.active_model
grp = model.entities.add_group

$tagged = []
made = PLACE.place_eaves!(grp, PLANES, EAVE, 'barrel', model: model)
ok('place_eaves! reports what it placed', made == 15, made)

insts = grp.entities.grep(Sketchup::ComponentInstance)
ok('and they really are INSTANCES, not groups', insts.length == 15, insts.length)
ok('every one of them is a plain Group-free instance',
   grp.entities.grep(Sketchup::Group).length == insts.length,
   grp.entities.grep(Sketchup::Group).length)

defs = insts.map { |i| i.definition }.uniq
ok('THE WHOLE POINT: 15 instances share ONE definition', defs.length == 1,
   defs.length)
ok('and it is the eave piece', defs[0] &&
   defs[0].get_attribute('InteriorPro', 'part') == 'tile_eave',
   defs[0] && defs[0].get_attribute('InteriorPro', 'part'))
ok('the definition stays cheap - rt77 budget, <= 8 faces',
   defs[0] && defs[0].entities.grep(Sketchup::Face).length <= 8,
   defs[0] && defs[0].entities.grep(Sketchup::Face).length)

ok('every instance is tagged, one tag call each', $tagged.length == 15,
   $tagged.length)
ok('and the tag is the one the proposal names',
   $tagged.map(&:last).uniq == ['InteriorPro_RoofTiles_Edge'],
   $tagged.map(&:last).uniq)
ok('the things tagged ARE the instances',
   $tagged.map(&:first).sort_by(&:object_id) == insts.sort_by(&:object_id))

ok('the instances land at the slot origins',
   insts.map { |i| i.transformation.origin.x.round(3) }.sort ==
     slots.map { |s| s[:origin][0].round(3) }.sort)

# placing a SECOND roof reuses the same definition - no new geometry
before = model.definitions.length
grp2 = model.entities.add_group
PLACE.place_eaves!(grp2, PLANES, EAVE, 'barrel', model: model)
ok('a second roof adds no new definition', model.definitions.length == before,
   [before, model.definitions.length])

# --------------------------------------------------------------- the brake

Sketchup.reset_model!
g3 = Sketchup.active_model.entities.add_group
capped = PLACE.place_eaves!(g3, PLANES, EAVE, 'barrel',
                            model: Sketchup.active_model, max: 5)
ok('over budget, nothing is placed at all', capped.zero?, capped)
ok('and the group stays empty rather than half tiled',
   g3.entities.grep(Sketchup::ComponentInstance).empty?)

# ------------------------------------------------------------- it never throws

ok('no group -> 0, no exception', PLACE.place_eaves!(nil, PLANES, EAVE, 'barrel').zero?)
ok('no edges -> 0', PLACE.eave_slots(PLANES, nil, 'barrel').empty?)
ok('no planes -> 0', PLACE.eave_slots([], EAVE, 'barrel').empty?)
ok('an unknown material -> 0', PLACE.eave_slots(PLANES, EAVE, 'nope').empty?)

puts($fails.zero? ? 'rt79 ALL PASS' : "rt79 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

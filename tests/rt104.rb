# encoding: utf-8
# rt104 - HEALING A HOLE ONLY TOUCHES THE SLOPE THE HOLE IS IN
#         (2026-09-02B, found in the user's own model).
#
# He deleted two dormers off a HIP roof and got two things he should not
# have: the holes stayed open, and "כל מיני שכבות צפות באוויר מעל" -
# slabs hanging in mid-air over the house.
#
# THE CAUSE: heal_roof! collected a plane from EVERY sloping face in the
# roof group, without asking whether that face is over the hole at all.
# A hip roof has four slopes, so healing one dormer laid a patch on each
# of them - three of those in thin air.
#
# THE CLAIM PINNED HERE: heal_roof! puts back one skin per plane that is
# ACTUALLY over the hole, and nothing anywhere else. cut_roof! has always
# tested covers_point?; its inverse has to test the same thing.
#
# Against the old code both checks fail: made == 2, and a face is left
# floating on the far slope's plane above the hole.
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

Z0    = 100.0
SLOPE = 8.0 / 12.0

spec = { z0: Z0, slope: SLOPE, setback: 36.0, width: 48.0, length: 96.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         style: 'gable', base: [0.0, 0.0], along: [1.0, 0.0],
         into: [0.0, 1.0] }
fr = DM.frame(spec)
at = DM.at_lambda(spec)
ok('the frame is computed', !fr.nil?)

# TWO SLOPES OFF ONE RIDGE LINE AT y = 0: the near one climbs with +y,
# the far one climbs with -y. Only the near one is under the dormer.
Sketchup.reset_model!
model = Sketchup.active_model
roof = model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
near = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
far  = lambda { |x, y| Geom::Point3d.new(x, y, Z0 - y * SLOPE) }
roof.entities.add_face([near.call(-200, 0), near.call(200, 0),
                        near.call(200, 300), near.call(-200, 300)])
roof.entities.add_face([far.call(-200, 0), far.call(200, 0),
                        far.call(200, -300), far.call(-200, -300)])
base_faces = roof.entities.grep(Sketchup::Face).length
ok('the stub roof has two slopes', base_faces == 2, base_faces)

plan = DM.opening_plan(fr)
flat = plan.map { |ss, w| at.call(ss, w, 0.0) }
CX = flat.map(&:x).inject(:+) / flat.length
CY = flat.map(&:y).inject(:+) / flat.length
ok('the hole sits on the near slope, not the far one',
   CY > 1.0 && DM.covers_point?(roof.entities.grep(Sketchup::Face).first, CX, CY))

cut = DM.cut_roof!(roof.entities, fr, at)
ok('the cut opened the near skin', cut >= 1, cut)

made = DM.heal_roof!(roof.entities, fr, at)
ok('one hole in one slope puts back ONE skin, not one per slope',
   made == 1, made)

# and nothing is left hanging on any other plane over that spot
z_near = Z0 + CY * SLOPE
strays = roof.entities.grep(Sketchup::Face).select do |f|
  next false unless DM.covers_point?(f, CX, CY)
  zf = DM.plane_z_lambda(f)
  zf && (zf.call(CX, CY) - z_near).abs > 0.01
end
ok('no slab is left floating on another slope plane above the hole',
   strays.empty?, strays.map { |f| DM.plane_z_lambda(f).call(CX, CY).round(2) })

# and the hole it was asked to close really is closed
covered = roof.entities.grep(Sketchup::Face).any? do |f|
  zf = DM.plane_z_lambda(f)
  zf && DM.covers_point?(f, CX, CY) && (zf.call(CX, CY) - z_near).abs < 0.01
end
ok('the hole itself is skinned again', covered)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

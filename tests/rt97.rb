# encoding: utf-8
# rt97 - THE DORMER'S OVERHANG AND ITS MATERIALS (2026-09-02).
#
# WHY
# The user looked at the finished body on his roof and said: "אני לא
# רואה בכלל אוברהנג???? צריך לבנות דורמר עם קירות כמו הבית". Until
# today the dormer's roof slab stopped dead on the outside face of its
# own walls, so there was nothing for a fascia to hang off and nothing
# a real dormer looks like.
#
# THE CLAIMS PINNED HERE
# 1. THE SLAB HANGS OUT on all three open sides: past each cheek by the
#    overhang (the eaves), and forward past the front wall (the rake).
# 2. THE SLAB STAYS ON ITS OWN PLANE. Hanging it out does not tilt it -
#    the outer edge is simply lower, by overhang * pitch.
# 3. THE EAVE STILL DIES ON THE MAIN ROOF. Because the outer edge is
#    lower, it meets the climbing main roof EARLIER than the wall line
#    does. Both back corners still sit exactly on the roof surface, so
#    the cut in step 2 still has a straight line to follow.
# 4. THE WALLS DO NOT MOVE. Width is still outside face to outside face,
#    the cheeks still stop under the slab, the hole in the roof is
#    unchanged - the overhang is roof only.
# 5. OVERHANG 0 REBUILDS THE OLD FLUSH SLAB exactly.
# 6. AN OVERHANG TOO BIG TO LEAVE THE ROOF IS REFUSED, not built.
# 7. THE DORMER WEARS THE HOUSE: the walls take the exterior material
#    most of the house's walls wear, with no number typed in.
#
# Against the old code claims 1-3 and 7 fail (the slab ended on the wall
# face and nothing read the house's materials).
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
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

Z0    = 100.0
SLOPE = 8.0 / 12.0
SET   = 36.0
WID   = 48.0
LEN   = 96.0
RT    = 0.5
TH    = 5.0
OH    = 6.0

base = { z0: Z0, slope: SLOPE, setback: SET, width: WID, length: LEN,
         thickness: TH, roof_thickness: RT }
fr = DM.frame(base.merge(overhang: OH))
ok('the frame is computed', !fr.nil?)
ok('the overhang is remembered', close(fr[:overhang], OH), fr && fr[:overhang])

# ---- 1 + 2. THE SLAB HANGS OUT, ON ITS OWN PLANE ----------------------
ok('the slab reaches one overhang past the cheek',
   close(fr[:w_edge], WID / 2.0 + OH), fr[:w_edge])
ok('the slab starts one overhang in front of the wall',
   close(fr[:s_rake], SET - OH), fr[:s_rake])
ok('the outer edge is lower by overhang * pitch, not tilted',
   close(fr[:z_edge], fr[:z_eave] - OH * SLOPE), fr[:z_edge])

# ---- 3. THE EAVE STILL DIES ON THE MAIN ROOF --------------------------
ok('the outer edge dies on the roof surface',
   close(Z0 + fr[:s_valley] * SLOPE, fr[:z_edge], 0.001),
   [fr[:s_valley], fr[:z_edge]])
ok('...earlier than the wall line does',
   fr[:s_valley] < fr[:s_eave] - 0.5, [fr[:s_valley], fr[:s_eave]])

Sketchup.reset_model!
m = Sketchup.active_model
grp = DM.build_dormer!(m.entities, base.merge(overhang: OH,
                                              base: [0.0, 0.0],
                                              along: [1.0, 0.0],
                                              into: [0.0, 1.0]))
ok('the dormer builds', !grp.nil?)

parts = grp.entities.to_a.select { |e| e.respond_to?(:entities) }
kind = lambda { |k| parts.select { |g| g.get_attribute('InteriorPro', 'part') == k } }
def pts_of(g)
  g.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map(&:position) }
end
walls = kind.call('dormer_front') + kind.call('dormer_cheek')
roofs = kind.call('dormer_roof')
wall_pts = walls.flat_map { |g| pts_of(g) }
roof_pts = roofs.flat_map { |g| pts_of(g) }

# The overhang is measured to the FASCIA line. The deck then runs the
# little bit further that finishes it on the metal edge's outer face
# instead of short of it - deck_side at an eave, deck_front at the
# gable, RoofManager's own rake_out (2026-09-02, rt98).
ok('built: the slab is one overhang wider on each side',
   close(roof_pts.map(&:x).max - wall_pts.map(&:x).max, OH + fr[:deck_side], 0.02) &&
   close(wall_pts.map(&:x).min - roof_pts.map(&:x).min, OH + fr[:deck_side], 0.02),
   [roof_pts.map(&:x).max, wall_pts.map(&:x).max])
ok('built: the slab starts one overhang in front of the wall',
   close(wall_pts.map(&:y).min - roof_pts.map(&:y).min, OH + fr[:deck_front], 0.02),
   [wall_pts.map(&:y).min, roof_pts.map(&:y).min])
ok('built: every slab TOP point is on the dormer roof plane',
   roofs.all? do |g|
     pts_of(g).select { |p| p.z > DM.top_z(fr, p.x) - RT + 0.001 }
              .all? { |p| close(p.z, DM.top_z(fr, p.x), 0.01) }
   end)
ok('built: the two back corners sit on the MAIN roof',
   roofs.all? do |g|
     back = pts_of(g).select { |p| p.y > SET + 0.5 && close(p.z, DM.top_z(fr, p.x), 0.01) }
     !back.empty? && back.all? { |p| close(p.z, Z0 + p.y * SLOPE, 0.02) }
   end)

# ---- 4. THE WALLS DO NOT MOVE ----------------------------------------
flush = DM.frame(base.merge(overhang: 0.0))
%i[z_front z_eave z_ridge height s_front s_ridge s_eave s_cheek half].each do |k|
  ok("the overhang leaves #{k} alone", close(fr[k], flush[k], 0.0001),
     [fr[k], flush[k]])
end
ok('width is still outside face to outside face',
   close(wall_pts.map(&:x).max - wall_pts.map(&:x).min, WID, 0.05),
   wall_pts.map(&:x).max - wall_pts.map(&:x).min)
ok('the hole in the roof is unchanged',
   DM.opening_plan(fr) == DM.opening_plan(flush))

# ---- 5. OVERHANG 0 IS THE OLD SLAB -----------------------------------
ok('overhang 0: the FASCIA line is the wall face',
   close(flush[:w_edge], WID / 2.0) && close(flush[:s_rake], SET),
   [flush[:w_edge], flush[:s_rake]])
ok('overhang 0: the deck still finishes on its own metal edge',
   close(flush[:w_deck], WID / 2.0 + flush[:deck_side]) &&
   close(flush[:s_deck], SET - flush[:deck_front]),
   [flush[:w_deck], flush[:s_deck]])

# ---- 6. TOO BIG IS REFUSED -------------------------------------------
ok('an overhang wider than the dormer itself is refused',
   DM.frame(base.merge(overhang: 400.0)).nil?)
ok('a sane overhang is not refused', !DM.frame(base.merge(overhang: 12.0)).nil?)

# ---- 7. THE DORMER WEARS THE HOUSE ------------------------------------
Sketchup.reset_model!
m2 = Sketchup.active_model
mk = lambda do |name|
  w = m2.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'exterior_material', name)
  w
end
3.times { mk.call('Stucco') }
mk.call('Brick')
ok('the walls take the house material most of the house wears',
   DM.house_wall_material(m2) == 'Stucco', DM.house_wall_material(m2))

Sketchup.reset_model!
ok('a house with no walls asks for nothing',
   DM.house_wall_material(Sketchup.active_model).nil?,
   DM.house_wall_material(Sketchup.active_model))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

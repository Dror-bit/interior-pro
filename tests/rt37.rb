# encoding: utf-8
# rt37 — a door (or window) FOLLOWS its wall when the wall is bowed
# (2026-08-12).
#
# The bug: set_wall_sag! rebuilds the wall, so the HOLE moves onto the new
# arc, but the door body is a separate group and nothing moved it. Measured
# on a 200" wall bowed 48": the door stayed 47.840" behind its own hole.
# A plain door_regen! would not have helped either - opening_context prefers
# the face_x/face_y the door stored while the wall was still straight, so it
# would have put the door back in exactly the same wrong place.
#
# This suite calls the REAL DoorManager.opening_seat / seat_transform /
# reseat_hosted_openings! - it does not carry a copy of the rule it checks.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'
require './door_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

D  = 'InteriorPro'
DM = InteriorPro::DoorManager
WT = InteriorPro::WallTool

T = 100.0
W = 36.0

def mkwall(model, anchor, sag)
  g = model.entities.add_group
  g.set_attribute(D, 'type', 'wall'); g.set_attribute(D, 'id', 'w1')
  g.set_attribute(D, 'start_x', 0.0);   g.set_attribute(D, 'start_y', 0.0)
  g.set_attribute(D, 'end_x', 200.0);   g.set_attribute(D, 'end_y', 0.0)
  g.set_attribute(D, 'thickness', 6.0); g.set_attribute(D, 'height', 96.0)
  g.set_attribute(D, 'anchor', anchor)
  g.set_attribute(D, 'wall_category', 'exterior')
  g.set_attribute(D, 'arc_sag', sag) if sag
  g
end

def mkdoor(model, type, t, width)
  d = model.entities.add_group
  d.set_attribute(D, 'type', type)
  d.set_attribute(D, 'host_wall_id', 'w1')
  d.set_attribute(D, 'position_along_wall_in', t)
  d.set_attribute(D, 'width_in', width)
  d.set_attribute(D, 'height_in', 80.0)
  d.set_attribute(D, 'floor_offset_in', 0.0)
  d.set_attribute(D, 'clicked_side', 1)
  d
end

# ---------------- the seat itself ---------------------------------------
Sketchup.reset_model!
model = Sketchup.active_model

%w[bottom-center bottom-left bottom-right].each do |anc|
  s_straight = DM.opening_seat(DM.wall_geometry(mkwall(model, anc, nil)), T, W)
  s_bowed    = DM.opening_seat(DM.wall_geometry(mkwall(model, anc, 48.0)), T, W)
  ok("#{anc}: bowing the wall moves the seat (it used to stay put)",
     s_straight && s_bowed &&
       Math.hypot(s_bowed[0] - s_straight[0], s_bowed[1] - s_straight[1]) > 40.0,
     [s_straight, s_bowed])
  # At the MIDDLE of a symmetric wall the panel still runs almost parallel to
  # the chord - that is geometry, not a bug. Ask a door near the start, where
  # the tangent really does swing round.
  near_start = DM.opening_seat(DM.wall_geometry(mkwall(model, anc, 48.0)), 40.0, W)
  ok("#{anc}: a door near the start turns with the arc",
     near_start && near_start[2].y.abs > 0.4, near_start && [near_start[2].x, near_start[2].y])
end

# a hair of bow must move the seat a hair, never jump (the rt34 invariant,
# now for the seat the body is actually placed on)
s0 = DM.opening_seat(DM.wall_geometry(mkwall(model, 'bottom-left', nil)), T, W)
s1 = DM.opening_seat(DM.wall_geometry(mkwall(model, 'bottom-left', 0.08)), T, W)
ok('a hair of bow moves the seat a hair', Math.hypot(s1[0] - s0[0], s1[1] - s0[1]) < 0.2,
   Math.hypot(s1[0] - s0[0], s1[1] - s0[1]))

# ---------------- the move ----------------------------------------------
straight = DM.wall_geometry(mkwall(model, 'bottom-center', nil))
bowed    = DM.wall_geometry(mkwall(model, 'bottom-center', 48.0))
a = DM.opening_seat(straight, T, W)
b = DM.opening_seat(bowed, T, W)
tr = DM.seat_transform(a, b)

moved = Geom::Point3d.new(a[0], a[1], 0).transform(tr)
ok('the move lands the old seat exactly on the new one',
   (moved.x - b[0]).abs < 1e-6 && (moved.y - b[1]).abs < 1e-6, [moved.x, moved.y, b])

# the body must TURN with the panel, not just slide: a point one inch along
# the old panel has to end up one inch along the new one.
tip_old = Geom::Point3d.new(a[0] + a[2].x, a[1] + a[2].y, 0).transform(tr)
ok('the body turns to the new panel direction',
   (tip_old.x - (b[0] + b[2].x)).abs < 1e-6 && (tip_old.y - (b[1] + b[2].y)).abs < 1e-6,
   [tip_old.x, tip_old.y])

ok('no shape change -> no move at all',
   DM.seat_transform(a, a).identity?)

# height is never touched - the door does not rise or sink when the wall bends
tip_z = Geom::Point3d.new(a[0], a[1], 42.0).transform(tr)
ok('the move never changes height', (tip_z.z - 42.0).abs < 1e-9, tip_z.z)

# ---------------- end to end, through the real walker -------------------
Sketchup.reset_model!
model = Sketchup.active_model
wall = mkwall(model, 'bottom-center', nil)
door = mkdoor(model, 'door', T, W)
win  = mkdoor(model, 'window', 40.0, 24.0)
stranger = mkdoor(model, 'door', 60.0, 30.0)
stranger.set_attribute(D, 'host_wall_id', 'someone-else')

old_geo = DM.wall_geometry(wall)
seat_before = DM.opening_seat(old_geo, T, W)
door.set_attribute(D, 'face_x', seat_before[0])
door.set_attribute(D, 'face_y', seat_before[1])

wall.set_attribute(D, 'arc_sag', 48.0)          # what set_wall_sag! writes
n = DM.reseat_hosted_openings!(wall, old_geo)

ok('both the door and the window followed the wall', n == 2, n)

seat_after = DM.opening_seat(DM.wall_geometry(wall), T, W)
ok('the stored face point moved with the body',
   (door.get_attribute(D, 'face_x').to_f - seat_after[0]).abs < 1e-6 &&
   (door.get_attribute(D, 'face_y').to_f - seat_after[1]).abs < 1e-6,
   [door.get_attribute(D, 'face_x'), door.get_attribute(D, 'face_y'), seat_after])

ok('a door on ANOTHER wall was not touched',
   stranger.transformation.origin.x.abs < 1e-9 &&
   stranger.transformation.origin.y.abs < 1e-9,
   stranger.transformation.origin.to_a)

# straightening it again brings them back
back_geo = DM.wall_geometry(wall)
wall.delete_attribute(D, 'arc_sag')
DM.reseat_hosted_openings!(wall, back_geo)
ok('straightening the wall brings the door back to where it started',
   (door.get_attribute(D, 'face_x').to_f - seat_before[0]).abs < 1e-4 &&
   (door.get_attribute(D, 'face_y').to_f - seat_before[1]).abs < 1e-4,
   [door.get_attribute(D, 'face_x'), door.get_attribute(D, 'face_y'), seat_before])

# ---------------- the STRAIGHT wall case (user 2026-08-12) --------------
# swap_wall_side! moves a wall's body a full thickness to the other side of
# the drawn line. align_curve_lanes! calls it on a straight NEIGHBOUR when a
# curve needs to weld onto it - and the doors on that straight wall were
# left behind, exactly one thickness into the house. Measured: 6.000" on a
# 6" wall. The wall never bent; only its body moved.
Sketchup.reset_model!
model = Sketchup.active_model

left  = mkwall(model, 'bottom-left', nil)
seat_left = DM.opening_seat(DM.wall_geometry(left), T, W)
right = mkwall(model, 'bottom-right', nil)
seat_right = DM.opening_seat(DM.wall_geometry(right), T, W)
shift = Math.hypot(seat_right[0] - seat_left[0], seat_right[1] - seat_left[1])
ok('swapping the body side moves the seat by one wall thickness',
   (shift - 6.0).abs < 1e-6, shift)

wall2 = mkwall(model, 'bottom-left', nil)
door2 = mkdoor(model, 'door', T, W)
before = DM.opening_seat(DM.wall_geometry(wall2), T, W)
door2.set_attribute(D, 'face_x', before[0])
door2.set_attribute(D, 'face_y', before[1])
old_geo2 = DM.wall_geometry(wall2)
wall2.set_attribute(D, 'anchor', 'bottom-right')      # what swap_wall_side! writes
DM.reseat_hosted_openings!(wall2, old_geo2)
after = DM.opening_seat(DM.wall_geometry(wall2), T, W)
ok('a door on a STRAIGHT wall follows the body to the other side',
   (door2.get_attribute(D, 'face_x').to_f - after[0]).abs < 1e-6 &&
   (door2.get_attribute(D, 'face_y').to_f - after[1]).abs < 1e-6,
   [door2.get_attribute(D, 'face_x'), door2.get_attribute(D, 'face_y'), after])
ok('and it really did move - it is not still on the old side',
   Math.hypot(door2.get_attribute(D, 'face_x').to_f - before[0],
              door2.get_attribute(D, 'face_y').to_f - before[1]) > 5.9)

# doing it twice must NOT move it twice - this is why the bend reseats
# before align_curve_lanes! runs, and swap_wall_side! reseats for itself
same_geo = DM.wall_geometry(wall2)
DM.reseat_hosted_openings!(wall2, same_geo)
ok('reseating again with nothing changed moves nothing',
   (door2.get_attribute(D, 'face_x').to_f - after[0]).abs < 1e-6,
   door2.get_attribute(D, 'face_x'))

# ---------------- the kill switch is still there ------------------------
src = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('the kill switch exists', WT.const_defined?(:RESEAT_OPENINGS_ON_CURVE, false))
ok('set_wall_sag! actually calls the walker', src =~ /reseat_hosted_openings!/)
ok('swap_wall_side! calls it too',
   src[/def self\.swap_wall_side!.*?\n    end/m].to_s.include?('reseat_hosted_openings!'))
# order matters: the bend must reseat BEFORE align_curve_lanes! can move a
# body again, or the doors get carried twice.
sag_code = src[/def self\.set_wall_sag!.*?\n    end/m].to_s
             .lines.reject { |l| l.strip.start_with?('#') }.join
i_reseat = sag_code.index('reseat_hosted_openings!')
i_align  = sag_code.index('align_curve_lanes!')
ok('the bend reseats before align_curve_lanes! runs',
   i_reseat && i_align && i_reseat < i_align, [i_reseat, i_align])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

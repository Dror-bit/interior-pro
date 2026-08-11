# encoding: utf-8
# rt27 — HORIZONTAL SIDING as real 3D lap boards (2026-08-11).
#
# The user asked for the horizontal siding to stop being a picture of wood.
# It is now a stack of boards up the wall, each sticking out at its bottom
# edge and tucking back at its top - that taper is the shadow line. Boards
# stop either side of a window instead of running across the glass.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

# ---------------------------------------------- the board really is 3D

ok('a course shows a sensible amount of board', WT::HSIDING_EXPOSURE.between?(3.0, 12.0), WT::HSIDING_EXPOSURE)
ok('the bottom edge really sticks out', WT::HSIDING_DEPTH_BOTTOM > 0.25, WT::HSIDING_DEPTH_BOTTOM)
ok('the top edge tucks back in', WT::HSIDING_DEPTH_TOP < WT::HSIDING_DEPTH_BOTTOM, WT::HSIDING_DEPTH_TOP)
ok('so every board is a wedge, not a flat strip',
   WT::HSIDING_DEPTH_BOTTOM - WT::HSIDING_DEPTH_TOP > 0.25)

src = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('the board is pushed into 3D, not painted on', src.include?('face.pushpull(len * sign)'))
ok('horizontal siding is wired to the material name',
   src =~ /when 'Horizontal Siding' then add_horizontal_siding\(group\)/)
ok('board and batten still works too',
   src =~ /when 'Board and Batten' then add_board_and_batten\(group\)/)
ok('the flat-texture materials fall straight through and build nothing',
   !src.include?("when 'Stucco'") && !src.include?("when 'Brick'"))
ok('every build path goes through the one door',
   src.scan(/add_exterior_siding\(/).length >= 4)

# ------------------------------------------------- the stack of courses

c = WT.siding_courses(0.0, 96.0, 6.0)
ok('a 96" wall gets 16 courses of 6"', c.length == 16, c.length)
ok('the first course sits on the floor', close(c.first[0], 0.0))
ok('the last course reaches the top', close(c.last[1], 96.0))
ok('every course is exactly the exposure tall',
   c.all? { |z0, z1| close(z1 - z0, 6.0) })
ok('the courses stack without gaps or overlaps',
   c.each_cons(2).all? { |a, b| close(a[1], b[0]) })

# A wall that does not divide evenly: the top course is trimmed, not overshot.
c2 = WT.siding_courses(0.0, 100.0, 6.0)
ok('an odd wall height still stops exactly at the top', close(c2.last[1], 100.0), c2.last)
ok('and never pokes out above it', c2.all? { |_z0, z1| z1 <= 100.0 + 1e-9 })
ok('a leftover sliver is dropped rather than left as a splinter',
   WT.siding_courses(0.0, 96.1, 6.0).length == 16, WT.siding_courses(0.0, 96.1, 6.0).length)

# A wall lifted to the second level starts its courses up there.
c3 = WT.siding_courses(106.0, 202.0, 6.0)
ok('a wall on the second level starts its boards up there', close(c3.first[0], 106.0))
ok('and finishes at its own top', close(c3.last[1], 202.0))

ok('a silly exposure gives no courses at all', WT.siding_courses(0.0, 96.0, 0.0).empty?)
ok('a wall with no height gives no courses', WT.siding_courses(0.0, 0.0, 6.0).empty?)

# ------------------------------------- boards stop either side of a window

WIN  = [{ t: 100.0, width: 48.0, height: 36.0, floor_offset: 40.0 }]
DOOR = [{ t: 40.0,  width: 36.0, height: 80.0, floor_offset: 0.0 }]
TOTAL = 200.0

# A course below the window runs the whole wall.
ok('a board below the window runs the full wall',
   WT.clear_t_intervals(TOTAL, WIN, 0.0, 6.0, 0.0) == [[0.0, 200.0]])
# A course above it too.
ok('a board above the window runs the full wall',
   WT.clear_t_intervals(TOTAL, WIN, 90.0, 96.0, 0.0) == [[0.0, 200.0]])
# A course level with it stops at each jamb.
iv = WT.clear_t_intervals(TOTAL, WIN, 48.0, 54.0, 0.0)
ok('a board level with the window comes in two pieces', iv.length == 2, iv)
ok('the first piece stops at the left jamb', close(iv[0][1], 76.0), iv[0])
ok('the second piece starts at the right jamb', close(iv[1][0], 124.0), iv[1])
ok('nothing runs across the glass',
   iv.none? { |a, b| a < 124.0 - 1e-9 && b > 76.0 + 1e-9 }, iv)
ok('the pieces still reach both ends of the wall',
   close(iv.first[0], 0.0) && close(iv.last[1], 200.0))

# Right at the window's edges: just inside is cut, just outside is not.
ok('a board just below the sill is whole',
   WT.clear_t_intervals(TOTAL, WIN, 33.0, 39.9, 0.0) == [[0.0, 200.0]])
ok('a board just above the head is whole',
   WT.clear_t_intervals(TOTAL, WIN, 76.1, 82.0, 0.0) == [[0.0, 200.0]])
ok('a board straddling the sill is cut',
   WT.clear_t_intervals(TOTAL, WIN, 38.0, 44.0, 0.0).length == 2)

# A door reaching the floor: the bottom courses are cut too.
iv2 = WT.clear_t_intervals(TOTAL, DOOR, 0.0, 6.0, 0.0)
ok('the bottom board is cut by a door that reaches the floor', iv2.length == 2, iv2)
ok('and it stops at the door jambs',
   close(iv2[0][1], 22.0) && close(iv2[1][0], 58.0), iv2)

# Two openings at the same height: three pieces.
both = DOOR + WIN
iv3 = WT.clear_t_intervals(TOTAL, both, 48.0, 54.0, 0.0)
ok('a board past a door AND a window comes in three pieces', iv3.length == 3, iv3)
ok('openings given out of order still work',
   WT.clear_t_intervals(TOTAL, both.reverse, 48.0, 54.0, 0.0) == iv3)

# Overlapping openings must not produce a backwards piece.
overlap = [{ t: 100.0, width: 48.0, height: 60.0, floor_offset: 20.0 },
           { t: 120.0, width: 48.0, height: 60.0, floor_offset: 20.0 }]
iv4 = WT.clear_t_intervals(TOTAL, overlap, 30.0, 36.0, 0.0)
ok('overlapping openings never make a backwards piece',
   iv4.all? { |a, b| b > a }, iv4)

ok('no openings -> one full run', WT.clear_t_intervals(TOTAL, [], 0.0, 6.0, 0.0) == [[0.0, 200.0]])
ok('nil openings -> one full run', WT.clear_t_intervals(TOTAL, nil, 0.0, 6.0, 0.0) == [[0.0, 200.0]])
ok('string keys work too',
   WT.clear_t_intervals(TOTAL, [{ 't' => 100.0, 'width' => 48.0, 'height' => 36.0, 'floor_offset' => 40.0 }],
                        48.0, 54.0, 0.0).length == 2)

# ---------------------------------------- cutting a board to length

POLY = [[0.0, 0.0, 0.0], [50.0, 0.0, 50.0], [100.0, 0.0, 100.0]]
r = WT.polyline_between(POLY, 20.0, 80.0)
ok('a board cut to length starts exactly where asked', close(r.first[0], 20.0), r.first)
ok('and ends exactly where asked', close(r.last[0], 80.0), r.last)
ok('and keeps the corners in between', r.length == 3, r)
ok('the whole run comes back whole',
   WT.polyline_between(POLY, 0.0, 100.0).length == 3)
ok('a run of nothing comes back as nothing', WT.polyline_between(POLY, 40.0, 40.0).nil?)
ok('a backwards run comes back as nothing', WT.polyline_between(POLY, 60.0, 40.0).nil?)
ok('a run inside one straight stretch is just two points',
   WT.polyline_between(POLY, 10.0, 30.0).length == 2)
ok('a point past the end is pulled back to the end',
   close(WT.point_on_polyline(POLY, 500.0)[0], 100.0))
ok('a point before the start is pulled up to the start',
   close(WT.point_on_polyline(POLY, -50.0)[0], 0.0))
ok('a point halfway lands halfway', close(WT.point_on_polyline(POLY, 75.0)[0], 75.0))

# On a real curve the cut points must still sit ON the curve.
ARC = AM.from_chord_and_sag(0, 0, 240, 0, 30.0)
cpoly = (0..12).map { |i| d = AM.length(ARC) * i / 12.0; p = AM.point_at_distance(ARC, d); [p[0], p[1], d] }
cut = WT.polyline_between(cpoly, 30.0, 90.0)
ok('a board on a curve is cut to length too', cut.length >= 2, cut&.length)
ok('and its ends land close to the curve',
   cut.all? { |p| (AM.dist(p[0], p[1], ARC[:cx], ARC[:cy]) - ARC[:r]).abs < 1.0 },
   cut.map { |p| (AM.dist(p[0], p[1], ARC[:cx], ARC[:cy]) - ARC[:r]).round(3) })

# ------------------------------------------- the wall's outside face

def sid_wall(sag, ext = 'Horizontal Siding')
  g = Sketchup.active_model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', "hs#{sag}")
  g.set_attribute('InteriorPro', 'start_x', 0.0); g.set_attribute('InteriorPro', 'start_y', 0.0)
  g.set_attribute('InteriorPro', 'end_x', 240.0); g.set_attribute('InteriorPro', 'end_y', 0.0)
  g.set_attribute('InteriorPro', 'thickness', 6.0)
  g.set_attribute('InteriorPro', 'height', 96.0)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  g.set_attribute('InteriorPro', 'exterior_material', ext)
  g.set_attribute('InteriorPro', 'corners_xy', [0.0, 3.0, 240.0, 3.0, 240.0, -3.0, 0.0, -3.0])
  g.set_attribute('InteriorPro', 'arc_sag', sag) unless sag.zero?
  g
end

Sketchup.reset_model!
sw = sid_wall(0.0)
sp = WT.exterior_face_polyline(sw)
ok('a straight wall gives a two point face', sp.length == 2, sp)
ok('it starts at the wall start', close(sp.first[2], 0.0))
ok('it ends at the wall length', close(sp.last[2], 240.0), sp.last)
ok('and it is the OUTSIDE face, not the inside',
   close(sp.first[1], -3.0) && close(sp.last[1], -3.0), sp)

cw = sid_wall(30.0)
cp = WT.exterior_face_polyline(cw)
ok('a curved wall gives a face that follows the curve', cp.length > 4, cp&.length)
ok('its distances march forwards', cp.map { |p| p[2] }.each_cons(2).all? { |a, b| b > a })
ok('it starts at zero', close(cp.first[2], 0.0, 1e-6))
ok('it ends at the length OF THE CURVE',
   close(cp.last[2], AM.length(AM.from_chord_and_sag(0, 0, 240, 0, 30.0)), 1e-6), cp.last[2])

# ------------------------------------ the boards keep the wood, not paint

ok('lap boards are painted white by default',
   src.include?("board_mat = load_or_create_material('#ffffff')"))
ok('and the wall behind them is white too', src.include?('f.material = board_mat'))
ok('board and batten is white as well',
   src.include?("white_mat = load_or_create_material('#ffffff')"))

# ------------------------------------------------ corner boards

ok('a corner board is 3 inches on each face', close(WT::SIDING_TRIM_WIDTH, 3.0), WT::SIDING_TRIM_WIDTH)
ok('and it stands proud of the siding',
   WT::SIDING_TRIM_DEPTH > WT::HSIDING_DEPTH_BOTTOM, [WT::SIDING_TRIM_DEPTH, WT::HSIDING_DEPTH_BOTTOM])
ok('a normal wall gets its corner boards', close(WT.trim_inset(240.0), 3.0))
ok('a wall too short for two of them gets none', close(WT.trim_inset(8.0), 0.0), WT.trim_inset(8.0))
ok('a wall just long enough does get them', WT.trim_inset(13.0) > 0.0, WT.trim_inset(13.0))
ok('lap siding builds its corner boards', src.include?('corner_trim_runs(poly, total_t, trim_w, ext0, ext1)'))
ok('board and batten builds them too',
   src.include?('InteriorPro::WallTool.corner_trim_runs(poly, total_t).each do |run|'))
ok('a corner board runs the full height of the wall',
   src.include?('build_siding_board!(sub, a, b, z_min, z_max,'))
ok('a corner board is square, not tapered like a lap board',
   src.include?('SIDING_TRIM_DEPTH, SIDING_TRIM_DEPTH)'))
ok('battens keep clear of the corner boards',
   src.include?('next if inset > 0.0 && (t < inset + half_width || t > total_t - inset - half_width)'))

# The field boards must start and finish at the corner boards, not past them.
iv = WT.clear_t_intervals(240.0, [], 0.0, 6.0, 0.0, 3.0)
ok('a full-length board starts at the corner board', close(iv.first[0], 3.0), iv)
ok('and finishes at the other one', close(iv.last[1], 237.0), iv)
ok('with no inset it still runs end to end',
   WT.clear_t_intervals(240.0, [], 0.0, 6.0, 0.0) == [[0.0, 240.0]])
iv2 = WT.clear_t_intervals(200.0, [{ t: 100.0, width: 48.0, height: 36.0, floor_offset: 40.0 }], 48.0, 54.0, 0.0, 3.0)
ok('a board past a window still respects both corner boards',
   close(iv2.first[0], 3.0) && close(iv2.last[1], 197.0), iv2)
ok('and still stops at the window', iv2.length == 2, iv2)
ok('a wall shorter than its own trim gets no boards at all',
   WT.clear_t_intervals(4.0, [], 0.0, 6.0, 0.0, 3.0).empty?)
ok('an opening running past the corner never makes a backwards piece',
   WT.clear_t_intervals(60.0, [{ t: 55.0, width: 20.0, height: 90.0, floor_offset: 0.0 }],
                        0.0, 6.0, 0.0, 3.0).all? { |a, b| b > a })
ok('the shadow line is deep enough to read as separate boards',
   WT::HSIDING_DEPTH_BOTTOM - WT::HSIDING_DEPTH_TOP >= 0.5,
   WT::HSIDING_DEPTH_BOTTOM - WT::HSIDING_DEPTH_TOP)

# ------------------------------- it must never take SketchUp down with it

# 2026-08-11: SketchUp crashed. Two reasons, both fixed here.
#   1. every board scanned the whole face list twice, before and after -
#      O(boards x faces), which on a curved wall is millions of objects
#   2. a curved wall was faceted for siding as finely as the wall itself,
#      so one wall wanted hundreds of little solids
ok('there is a kill switch for all 3D siding', WT::USE_3D_SIDING == true)
ok('and it is checked before anything is built',
   src =~ /def add_exterior_siding\(group, ext_mat\)\s*\n\s*return unless USE_3D_SIDING/)
ok('no board scans the whole face list any more',
   !src.include?('grep(Sketchup::Face).to_a'))
ok('painting is one call on the whole sub-group', src.include?('sub.material = board_mat'))
ok('battens are painted the same way', src.include?('sub.material = white_mat'))

# ---------------- the siding lives in its own group, away from the wall

# THE crash fix. A board drawn straight into the wall group puts its back
# edge on the wall's own face and splits it. A few hundred of those inside
# one operation is what took SketchUp down. Its own group touches nothing.
ok('the siding has a group of its own', src.include?("SIDING_GROUP_NAME = 'InteriorPro_Siding'"))
ok('a fresh one is made for every rebuild', src.include?('sub = siding_group(group)'))
ok('and the old one is thrown away first', src =~ /g\.erase! if g\.valid\? && g\.name == SIDING_GROUP_NAME/)
ok('boards are drawn into that group, not into the wall',
   src.include?('holder.entities.add_face(profile)'))
ok('battens too', src.include?('sub.entities.add_face(p1, p2, p3, p4)'))
ok('nothing is drawn into the wall group any more',
   !src.include?('group.entities.add_face(profile)'))
ok('an empty siding group is cleaned up rather than left behind',
   src.include?('sub.entities.length.zero?'))
ok('and a failed build removes itself instead of leaving wreckage',
   src.include?('siding build failed, removing it'))

ok('there is a hard ceiling on how many boards one wall may have',
   WT::MAX_SIDING_PIECES.between?(50, 2000), WT::MAX_SIDING_PIECES)
ok('lap siding counts the cost BEFORE it builds anything',
   src =~ /if pieces > MAX_SIDING_PIECES/)
ok('battens count it too', src =~ /if planned > MAX_SIDING_PIECES/)
ok('and a wall over the limit keeps its flat face instead of crashing',
   src.include?('The flat face is kept.'))

ok('siding on a curve is faceted far more coarsely than the wall body',
   WT::SIDING_CURVE_TOL > WT::CURVE_TOL * 4, [WT::SIDING_CURVE_TOL, WT::CURVE_TOL])
ok('and the siding asks for that coarser facet count',
   src.include?('exterior_face_polyline(group, SIDING_CURVE_TOL)'))

# The coarse tolerance has to actually cut the piece count down hard.
Sketchup.reset_model!
cw2 = sid_wall(30.0)
fine = WT.exterior_face_polyline(cw2, WT::CURVE_TOL)
coarse = WT.exterior_face_polyline(cw2, WT::SIDING_CURVE_TOL)
ok('the coarse face really is coarser', coarse.length < fine.length, [coarse.length, fine.length])
ok('and it costs less than half as much', coarse.length * 2 <= fine.length,
   [fine.length, coarse.length])
ok('but it still spans the whole wall',
   close(coarse.first[2], 0.0, 1e-6) && close(coarse.last[2], fine.last[2], 1e-6))

# A 20ft wall must land comfortably under the ceiling.
courses = WT.siding_courses(0.0, 96.0, WT::HSIDING_EXPOSURE).length
ok('a plain 20ft straight wall is nowhere near the ceiling',
   courses + 2 < WT::MAX_SIDING_PIECES, courses)
ok('a 20ft CURVED wall is under it too',
   (courses * (coarse.length - 1)) + 2 <= WT::MAX_SIDING_PIECES,
   courses * (coarse.length - 1))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

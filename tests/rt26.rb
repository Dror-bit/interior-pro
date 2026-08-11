# encoding: utf-8
# rt26 — Board and Batten STAYS 3D, and the wall dialogs open big enough.
#
# Two things the user reported:
#   1. the siding went flat - a picture of wood instead of real strips
#   2. the Edit Wall window opened showing only half its contents
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

# ------------------------------------------- the strips are real, and 3D

ok('a batten has a real width',  WT::BATTEN_WIDTH > 0.5, WT::BATTEN_WIDTH)
ok('a batten really sticks out', WT::BATTEN_DEPTH > 0.25, WT::BATTEN_DEPTH)
ok('battens are spaced like real siding', WT::BATTEN_SPACING.between?(8.0, 24.0), WT::BATTEN_SPACING)

src = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('battens are pushed into 3D, not painted on', src =~ /face\.pushpull\(band_h \* sign\)/)
ok('a CURVED wall gets its siding too',
   src =~ /smooth_curved_wall_edges!\(group\)\s*\n\s*add_exterior_siding\(group, ext_mat\)/)
ok('a straight wall still gets its siding',
   src.scan(/add_exterior_siding\(group, ext_mat\)/).length >= 2)
ok('battens are reached through the one siding door',
   src =~ /when 'Board and Batten' then add_board_and_batten\(group\)/)
ok('the old "battens are left off curves" note is gone',
   !src.include?('board-and-batten strips are not bent yet'))

# ------------------------------------ on a curve every strip stands square

SX = 0.0; SY = 0.0; EX = 240.0; EY = 0.0
SAG = 30.0
TH = 6.0

def batten_wall(sag, thickness = TH, anchor = 'bottom-center')
  g = Sketchup.active_model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', "bb#{sag}#{anchor}")
  g.set_attribute('InteriorPro', 'start_x', SX); g.set_attribute('InteriorPro', 'start_y', SY)
  g.set_attribute('InteriorPro', 'end_x', EX);   g.set_attribute('InteriorPro', 'end_y', EY)
  g.set_attribute('InteriorPro', 'thickness', thickness)
  g.set_attribute('InteriorPro', 'height', 96.0)
  g.set_attribute('InteriorPro', 'anchor', anchor)
  g.set_attribute('InteriorPro', 'arc_sag', sag) unless sag.zero?
  g
end

Sketchup.reset_model!
w = batten_wall(SAG)
st = WT.curved_batten_stations(w)
ok('a curved wall gets a row of battens', st.length > 5, st.length)

arc = AM.from_chord_and_sag(SX, SY, EX, EY, SAG)
_op, on = WT.anchor_side_offsets(TH, 'center')
face = AM.offset(arc, on)
r_face = face[:r]

st.each_with_index do |(c, u, r), i|
  next unless i < 4 || i == st.length - 1
  ok("batten #{i}: sits on the outside face of the wall",
     close(AM.dist(c[0], c[1], arc[:cx], arc[:cy]), r_face, 1e-6),
     AM.dist(c[0], c[1], arc[:cx], arc[:cy]))
  ok("batten #{i}: its direction is a unit vector",
     close(Math.sqrt(u[0]**2 + u[1]**2), 1.0, 1e-9), u)
  ok("batten #{i}: it sticks out square to the wall",
     close((u[0] * r[0]) + (u[1] * r[1]), 0.0, 1e-9), [u, r])
  ok("batten #{i}: it sticks OUTWARD, away from the wall body",
     AM.dist(c[0] + r[0] * WT::BATTEN_DEPTH, c[1] + r[1] * WT::BATTEN_DEPTH,
             arc[:cx], arc[:cy]) > AM.dist(c[0], c[1], arc[:cx], arc[:cy]) ==
     (AM.center_side(arc) > 0),
     nil)
end

# Each batten must point a DIFFERENT way - that is what makes it follow the
# curve instead of all of them standing parallel like a straight wall.
dirs = st.map { |(_c, u, _r)| u }
ok('the strips fan round the curve instead of standing parallel',
   (dirs.first[0] - dirs.last[0]).abs > 0.05 || (dirs.first[1] - dirs.last[1]).abs > 0.05,
   [dirs.first, dirs.last])

# Evenly spaced along the face, at the spacing that was asked for.
gaps = st.each_cons(2).map { |(a, _, _), (b, _, _)| AM.dist(a[0], a[1], b[0], b[1]) }
ok('the strips are evenly spaced', (gaps.max - gaps.min).abs < 0.05, [gaps.min, gaps.max])
ok('and spaced about every 16 inches',
   (gaps.first - WT::BATTEN_SPACING).abs < 0.2, gaps.first)

# None of them may hang off either end of the wall.
total = AM.length(face)
d0 = AM.dist(st.first[0][0], st.first[0][1], *AM.point_at_distance(face, 0.0))
ok('the first strip clears the start of the wall', d0 >= WT::BATTEN_WIDTH / 2.0 - 1e-9, d0)
dl = AM.dist(st.last[0][0], st.last[0][1], *AM.point_at_distance(face, total))
ok('the last strip clears the end of the wall', dl >= WT::BATTEN_WIDTH / 2.0 - 1e-9, dl)

# It has to work for the other anchors too.
%w[bottom-left bottom-right].each do |anchor|
  ww = batten_wall(SAG, TH, anchor)
  sts = WT.curved_batten_stations(ww)
  ok("anchor #{anchor}: still gets battens", sts.length > 5, sts.length)
  ok("anchor #{anchor}: they all stand square to the wall",
     sts.all? { |(_c, u, r)| close((u[0] * r[0]) + (u[1] * r[1]), 0.0, 1e-9) })
end

# A straight wall must not go anywhere near the curved path.
straight = batten_wall(0.0)
ok('a straight wall is not curved', WT.curved_wall?(straight) == false)
ok('and asking for its curved stations gives nothing', WT.curved_batten_stations(straight).empty?)

# ---------------------------------------- the dialogs open big and scroll

ui = File.read('ui_dialogs.rb', encoding: 'UTF-8')
ok('every wall dialog can be resized', !ui.include?('resizable: false'))
ok('every wall dialog has a floor on its size', ui.scan(/min_height:/).length >= 4)
ok('every wall dialog forces its size on open, beating the remembered one',
   ui.scan(/force_dialog_size\(dialog,/).length >= 8)
ok('and it does so on BOTH sides of show - SketchUp restores a size on the way up',
   ui =~ /force_dialog_size\(dialog, \d+, \d+\)\s*\n\s*dialog\.show\s*\n\s*force_dialog_size\(dialog, \d+, \d+\)/)
ok('nothing is remembered any more, so nothing can come back short',
   !ui.include?("preferences_key: 'InteriorPro_Wall"))
ok('the Edit Wall window opens tall enough to show everything',
   ui =~ /force_dialog_size\(dialog, 360, 760\)/)
ok('the multi-edit window opens tall enough too', ui =~ /force_dialog_size\(dialog, 380, 780\)/)
ok('every wall dialog has a ceiling on its size too', ui.scan(/max_height:/).length >= 4)
ok('the page scrolls instead of cutting content off',
   ui.scan(/overflow-y:auto/).length >= 3)
ok('and it never scrolls sideways', ui.scan(/overflow-x:hidden/).length >= 3)
ok('there is room at the bottom so the last button is reachable',
   ui.include?('padding:16px 16px 24px'))

# ------------------------ a window must not strip a wall of its siding

# The bug in the photo: putting a window in a Board and Batten wall rebuilt
# the wall through the openings path, which wipes everything inside the group
# - including the 3D strips - and then painted the bare slab with an empty
# "Board and Batten" material. The wall went black and flat.
ok('the openings rebuild puts the siding back',
   src =~ /paint_wall_long_faces!\(wall, ext_mat, int_mat\)[\s\S]{0,500}?add_exterior_siding\(wall, ext_mat\)/,
   nil)
ok('and a flat-texture wall builds nothing there',
   src.include?('def add_exterior_siding(group, ext_mat)'))

# ------------------------------- windows are ordinary openings, like doors

wsrc = File.read('window_tool.rb', encoding: 'UTF-8')
ok('a window is recorded on the wall, exactly like a door',
   wsrc.include?('InteriorPro::WallTool.append_door_opening!'))
ok('so a wall rebuild puts the window hole back',
   wsrc.include?('InteriorPro::WallTool.rebuild_wall_native!'))
ok('a window on a curved wall is measured along the curve',
   wsrc.include?('InteriorPro::WallTool.t_from_point_xy'))
ok('and it is turned to face its flat panel',
   wsrc.include?('InteriorPro::WallTool.opening_pocket'))
ok('a curved wall reports its real length to the window tool',
   wsrc.include?('wall_length = InteriorPro::ArcMath.length(arc)'))

# Because windows ARE recorded, a curved wall no longer has to refuse them.
ok('curving a wall with a window is no longer blocked',
   !src.include?('windows are not wired to curves yet'))
cursrc = File.read('wall_curve_tool.rb', encoding: 'UTF-8')
ok('and neither tool blocks it either',
   !cursrc.include?('Windows on curved walls are the next step'))

# --------------------------- a batten must not run across a window

# The photo: the strips ran straight over the glass. A batten in front of an
# opening has to break into the stub above it and the stub below it.
FLOOR = 0.0
TOP = 96.0
WIN = [{ t: 100.0, width: 48.0, height: 36.0, floor_offset: 40.0 }]     # a window
DOOR = [{ t: 40.0, width: 36.0, height: 80.0, floor_offset: 0.0 }]      # a door

# Well clear of the window: one full-height strip, untouched.
b = WT.batten_z_bands(20.0, 0.75, FLOOR, TOP, WIN, FLOOR)
ok('a batten away from the window is one full strip', b == [[0.0, 96.0]], b)

# Right in front of the window: a stub below the sill, a stub above the head.
b = WT.batten_z_bands(100.0, 0.75, FLOOR, TOP, WIN, FLOOR)
ok('a batten in front of the window breaks into two stubs', b.length == 2, b)
ok('the lower stub stops at the sill', close(b[0][1], 40.0), b[0])
ok('the upper stub starts at the head', close(b[1][0], 76.0), b[1])
ok('the lower stub starts at the floor', close(b[0][0], 0.0))
ok('the upper stub reaches the top of the wall', close(b[1][1], 96.0))
ok('nothing is left in front of the glass',
   b.none? { |z0, z1| z0 < 76.0 - 1e-9 && z1 > 40.0 + 1e-9 }, b)

# In front of a DOOR, which reaches the floor: only the stub above it.
b = WT.batten_z_bands(40.0, 0.75, FLOOR, TOP, DOOR, FLOOR)
ok('a batten in front of a door is only the piece above it', b.length == 1, b)
ok('and it starts at the door head', close(b[0][0], 80.0), b[0])

# The very edge cases: a batten just touching the opening either side.
ok('a batten just outside the opening survives whole',
   WT.batten_z_bands(100.0 - 24.0 - 0.75 - 0.01, 0.75, FLOOR, TOP, WIN, FLOOR) == [[0.0, 96.0]])
ok('a batten just inside the opening gets cut',
   WT.batten_z_bands(100.0 - 24.0 + 0.01, 0.75, FLOOR, TOP, WIN, FLOOR).length == 2)
ok('the batten width is taken into account, not just its centre',
   WT.batten_z_bands(100.0 - 24.0 - 0.5, 0.75, FLOOR, TOP, WIN, FLOOR).length == 2)

# Two openings on one wall, and a strip crossing both.
both = [{ t: 40.0, width: 36.0, height: 80.0, floor_offset: 0.0 },
        { t: 100.0, width: 48.0, height: 36.0, floor_offset: 40.0 }]
ok('a strip in front of the door is still cut when a window also exists',
   WT.batten_z_bands(40.0, 0.75, FLOOR, TOP, both, FLOOR) == [[80.0, 96.0]])
ok('and one in front of the window too',
   WT.batten_z_bands(100.0, 0.75, FLOOR, TOP, both, FLOOR).length == 2)
ok('a strip clear of both stays whole',
   WT.batten_z_bands(70.0, 0.75, FLOOR, TOP, both, FLOOR) == [[0.0, 96.0]])

# A stub too small to be worth building is dropped rather than left as a sliver.
tall = [{ t: 50.0, width: 36.0, height: 95.9, floor_offset: 0.0 }]
ok('a sliver of a stub is dropped, not left as a splinter',
   WT.batten_z_bands(50.0, 0.75, FLOOR, TOP, tall, FLOOR).empty?,
   WT.batten_z_bands(50.0, 0.75, FLOOR, TOP, tall, FLOOR))

# No openings, junk openings: the strip is untouched.
ok('no openings -> one full strip', WT.batten_z_bands(50.0, 0.75, FLOOR, TOP, [], FLOOR) == [[0.0, 96.0]])
ok('nil openings -> one full strip', WT.batten_z_bands(50.0, 0.75, FLOOR, TOP, nil, FLOOR) == [[0.0, 96.0]])
ok('a zero-width opening is ignored',
   WT.batten_z_bands(50.0, 0.75, FLOOR, TOP, [{ t: 50.0, width: 0.0, height: 40.0, floor_offset: 0.0 }], FLOOR) ==
   [[0.0, 96.0]])
ok('string keys work too',
   WT.batten_z_bands(100.0, 0.75, FLOOR, TOP,
                     [{ 't' => 100.0, 'width' => 48.0, 'height' => 36.0, 'floor_offset' => 40.0 }],
                     FLOOR).length == 2)

# A wall lifted off the ground still cuts in the right place.
b = WT.batten_z_bands(100.0, 0.75, 106.0, 202.0, WIN, 106.0)
ok('a wall on the second level cuts at the right height',
   close(b[0][1], 146.0) && close(b[1][0], 182.0), b)

# The plain band arithmetic, on its own.
ok('cutting a chunk out of the middle leaves two pieces',
   WT.subtract_z_band(0.0, 10.0, 3.0, 6.0) == [[0.0, 3.0], [6.0, 10.0]])
ok('cutting the bottom off leaves the top', WT.subtract_z_band(0.0, 10.0, -1.0, 4.0) == [[4.0, 10.0]])
ok('cutting the top off leaves the bottom', WT.subtract_z_band(0.0, 10.0, 7.0, 20.0) == [[0.0, 7.0]])
ok('cutting the whole thing leaves nothing', WT.subtract_z_band(0.0, 10.0, -1.0, 20.0) == [])
ok('a cut that misses changes nothing', WT.subtract_z_band(0.0, 10.0, 20.0, 30.0) == [[0.0, 10.0]])

# And the stations still carry the position needed to do all of that.
Sketchup.reset_model!
cw = batten_wall(SAG)
st2 = WT.curved_batten_stations(cw)
ok('every batten knows how far along the wall it stands',
   st2.all? { |s| s.length == 4 && s[3].is_a?(Float) }, st2.first)
ok('and those distances march forwards along the wall',
   st2.map { |s| s[3] }.each_cons(2).all? { |a, bb| bb > a })
ok('the last batten is still inside the wall',
   st2.last[3] <= AM.length(AM.from_chord_and_sag(SX, SY, EX, EY, SAG)) + 1.0,
   st2.last[3])

# ------------------- the window and wall library windows open in full too

[['window_library_dialog.rb', 'the window dialogs'],
 ['wall_library_dialog.rb', 'the wall library']].each do |file, label|
  d = File.read("../#{file}", encoding: 'UTF-8')
  ok("#{label}: opens at a real height", d =~ /height: 7\d\d/, nil)
  ok("#{label}: has a floor on its size", d.include?('min_height:'))
  ok("#{label}: forces its size on open, beating the remembered one",
     d.include?('dialog.set_size('))
  ok("#{label}: scrolls instead of cutting content off", d.include?('overflow-y: auto'))
  ok("#{label}: never scrolls sideways", d.include?('overflow-x: hidden'))
  ok("#{label}: leaves room under the last button", d.include?('padding-bottom: 24px'))
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

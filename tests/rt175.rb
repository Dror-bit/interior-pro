# encoding: utf-8
# rt175 - TILE ON A WALL (2026-09-17).
#
# Three things have to be true, and only the first one is "the maths":
#   1. the wall face plane is the right plane (side a vs side b, the
#      anchor, the wall's own floor),
#   2. an OPENING is taken out of the area - he asked for that in the
#      same breath as the tool: "צריך לוודא שהקיר של ה-TILE לוקח בחשבון
#      גם את החלון על הקיר במידה ויש",
#   3. the layout comes from tile_grid.rb and the count from
#      tile_count.rb - not from a second grid written here.
require './tile_wall'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TW = InteriorPro::TileWall

# ---- 1. the plane -----------------------------------------------------
# A wall along +x, 6" thick, centre anchored, floor at z = 100 (a second
# storey - CLAUDE.md: never measure this on the ground floor only).
fa = TW.frame(0.0, 0.0, 96.0, 0.0, 6.0, 'center', 'a', 100.0)
fb = TW.frame(0.0, 0.0, 96.0, 0.0, 6.0, 'center', 'b', 100.0)
ok('a wall with length gives a frame', fa && fb)
ok('side a sits on +y, half the thickness out', (fa[:oy] - 3.0).abs < 1e-9, fa[:oy])
ok('side b sits on -y', (fb[:oy] + 3.0).abs < 1e-9, fb[:oy])
ok('u runs from the start along the wall', TW.world(fa, 24.0, 0.0)[0].round(6) == 24.0)
ok('z counts up from the wall floor, not from zero',
   TW.world(fa, 0.0, 12.0)[2].round(6) == 112.0, TW.world(fa, 0.0, 12.0))
ok('the outward push leaves the wall on side a',
   TW.world(fa, 0.0, 0.0, 1.0)[1].round(6) == 4.0, TW.world(fa, 0.0, 0.0, 1.0))
ok('and the other way on side b',
   TW.world(fb, 0.0, 0.0, 1.0)[1].round(6) == -4.0, TW.world(fb, 0.0, 0.0, 1.0))
ok('a wall with no length is refused', TW.frame(5.0, 5.0, 5.0, 5.0, 6.0, 'center', 'a').nil?)

la = TW.frame(0.0, 0.0, 96.0, 0.0, 6.0, 'left', 'a')
ok('a left-anchored wall puts side a a whole thickness out',
   (la[:oy] - 6.0).abs < 1e-9, la[:oy])

# ---- 2. the area, and the opening --------------------------------------
TC = InteriorPro::TileCount
plain = TW.area_polys(0.0, 0.0, 60.0, 36.0)
ok('a plain area is one rectangle', plain.length == 1, plain.length)
ok('and it measures 15 sqft', (TW.area_sqft(plain) - 15.0).abs < 1e-6, TW.area_sqft(plain))

# a window in the middle of it: 24 wide, from 12 to 30 up
holed = TW.area_polys(0.0, 0.0, 60.0, 36.0, [[18.0, 12.0, 42.0, 30.0]])
ok('the window splits the area into four pieces', holed.length == 4, holed.length)
ok('the window area is gone',
   (TW.area_sqft(holed) - (60 * 36 - 24 * 18) / 144.0).abs < 1e-6, TW.area_sqft(holed))
ok('no piece of the area is inside the window',
   holed.none? { |p|
     cx = p.sum { |q| q[0] } / p.length
     cz = p.sum { |q| q[1] } / p.length
     cx > 18.01 && cx < 41.99 && cz > 12.01 && cz < 29.99
   }, holed)

# an opening that only overlaps a corner still bites
corner = TW.area_polys(0.0, 0.0, 60.0, 36.0, [[-10.0, -10.0, 12.0, 12.0]])
ok('an opening hanging off the edge takes what it covers',
   (TW.area_sqft(corner) - (60 * 36 - 12 * 12) / 144.0).abs < 1e-6, TW.area_sqft(corner))

# a door taller than the area, right across it, leaves nothing
ok('an opening over the whole area leaves nothing',
   TW.area_polys(0.0, 0.0, 60.0, 36.0, [[-1.0, -1.0, 61.0, 37.0]]).empty?)

# ---- 3. the tiles come from the ONE grid --------------------------------
area = TW.area_polys(0.0, 0.0, 48.0, 24.0)
ps = TW.pieces(area, u_size: 12.0, v_size: 12.0)
ok('a 48x24 area takes 8 whole 12" tiles',
   ps.count { |p| p[:full] } == 8, ps.map { |p| p[:full] })
ok('and nothing is cut', ps.none? { |p| p[:cut] }, ps.select { |p| p[:cut] })

odd = TW.pieces(TW.area_polys(0.0, 0.0, 30.0, 12.0), u_size: 12.0, v_size: 12.0)
ok('a 30" run is two whole tiles and one 6" cut',
   odd.count { |p| p[:full] } == 2 && odd.count { |p| !p[:full] } == 1,
   odd.map { |p| p[:full] })
ok('the cut is measured in the tile own frame',
   odd.find { |p| !p[:full] }[:cut] == [6.0, 12.0],
   odd.find { |p| !p[:full] }[:cut])

# the grid is ONE grid: two pieces split by an opening keep the same
# joint lines, they do not each start their own layout
split = TW.area_polys(0.0, 0.0, 48.0, 12.0, [[18.0, -1.0, 30.0, 13.0]])
sp = TW.pieces(split, u_size: 12.0, v_size: 12.0)
starts = sp.map { |p| p[:u0].round(4) }.uniq.sort
ok('an opening does not restart the layout on its far side',
   starts == [0.0, 12.0, 24.0, 36.0], starts)

# the joint is ADDED next to the tile, the same law as the floor
g = TW.pieces(TW.area_polys(0.0, 0.0, 24.5, 12.0), u_size: 12.0, v_size: 12.0, grout: 0.5)
ok('with a 1/2" joint two 12" tiles fit in 24.5"',
   g.count { |p| p[:full] } == 2, g.count { |p| p[:full] })

# stagger reaches the wall too (the floor's rt174 lesson)
bond = TW.pieces(TW.area_polys(0.0, 0.0, 48.0, 24.0), u_size: 12.0, v_size: 12.0,
                 stagger: 0.5)
row1 = bond.select { |p| (p[:v0] - 12.0).abs < 0.001 }.map { |p| p[:u0].round(4) }.sort
ok('the second course is pushed half a tile', row1.include?(-6.0) && row1.include?(6.0), row1)

# too small a tile is refused, not built
ok('a tile too small for the area is refused, not silently huge',
   TW.pieces(TW.area_polys(0.0, 0.0, 480.0, 120.0), u_size: 0.5, v_size: 0.5).nil?)

# the count is the floor's count - whole, cut, paired, buy
res = TW.plan(TW.area_polys(0.0, 0.0, 30.0, 24.0), u_size: 12.0, v_size: 12.0)
ok('the plan answers with the buy line', res && res[:tiles].to_i > 0, res)
ok('two 6" cuts are paired into one tile bought',
   res[:full] == 4 && res[:cut_pieces] == 2 && res[:tiles] == 5, res)

# ---- 3b. ONE tile is one piece, notch and all ---------------------------
# He counted them: "יש שם יותר מידי חיתוכים". A tile reaching over AND
# beside an opening was coming back as two pieces - two solids side by
# side, a seam he could see, and two tiles in the count.
r = TW.cut(0.0, 0.0, 24.0, 24.0, [])
ok('a tile with nothing in its way is one ring of four corners',
   r.length == 1 && r.first.length == 4, r)

notch = TW.cut(0.0, 0.0, 24.0, 24.0, [[12.0, 12.0, 40.0, 40.0]])
ok('a tile with a corner bitten out is ONE ring, not two',
   notch.length == 1, notch)
ok('and that ring has six corners - an L',
   notch.first.length == 6, notch.first.length)
ok('its area is the tile minus the bite',
   (TC.area(notch.first) - (24 * 24 - 12 * 12)).abs < 1e-6, TC.area(notch.first))

thru = TW.cut(0.0, 0.0, 24.0, 24.0, [[8.0, -5.0, 16.0, 30.0]])
ok('an opening straight through a tile really does leave two pieces',
   thru.length == 2, thru.map { |x| TC.area(x) })
ok('and they measure right',
   thru.map { |x| TC.area(x).round(4) }.sort == [8 * 24.0, 8 * 24.0].sort,
   thru.map { |x| TC.area(x) })

ok('a tile completely covered is gone',
   TW.cut(0.0, 0.0, 24.0, 24.0, [[-1.0, -1.0, 25.0, 25.0]]).empty?)

# the whole path: the same window as before, now through pieces_rect
before = TW.pieces(TW.area_polys(0.0, 0.0, 96.0, 96.0, [[36.0, 36.0, 60.0, 60.0]]),
                   u_size: 48.0, v_size: 48.0)
after = TW.pieces_rect(0.0, 0.0, 96.0, 96.0, [[36.0, 36.0, 60.0, 60.0]],
                       u_size: 48.0, v_size: 48.0)
ok('the old convex way splits four tiles into twelve pieces',
   before.length > after.length, [before.length, after.length])
ok('one tile is one piece now - four tiles, four pieces',
   after.length == 4, after.length)
ok('and every one of them is a cut tile, none is whole',
   after.none? { |x| x[:full] }, after.map { |x| x[:full] })
ok('so the count asks for four tiles, not twelve',
   TW.plan(nil, u_size: 1, v_size: 1).nil? ||
   InteriorPro::TileCount.count(0, after.map { |x| x[:cut] }, 48.0, 48.0)[:tiles] == 4,
   InteriorPro::TileCount.count(0, after.map { |x| x[:cut] }, 48.0, 48.0))

ok('with no openings at all nothing changed',
   TW.pieces_rect(0.0, 0.0, 48.0, 24.0, [], u_size: 12.0, v_size: 12.0).length == 8)

# ---- 4. the real path, not just the maths -------------------------------
# CLAUDE.md: a test on the pure function does not prove the tool works.
SRC = File.read('./tile_wall.rb')
ok('the layout comes from tile_grid', SRC.include?('InteriorPro::TileGrid.cells('))
ok('there is no second grid in here', SRC.scan(/while .*pitch/).empty?)
ok('the count comes from tile_count', SRC.include?('InteriorPro::TileCount.count('))
ok('the doors are read from the wall', SRC.include?('read_door_openings'))
ok('the windows are read from their own groups - they are not on the wall',
   SRC.include?("'host_wall_id'") && SRC.include?("'position_along_wall_in'"))
ok('build! subtracts the openings before laying anything',
   SRC =~ /holes = .*openings_for.*\n.*area = area_polys\(u0, z0, w, h, holes\)/)
ok('a curved wall is refused out loud, not skipped', SRC.include?('curved_wall?'))
ok('the wall floor is measured, not rebuilt from the anchor',
   SRC.include?('wall.bounds.min.z'))
ok('it is registered in main.rb', File.read('./main.rb').include?('tile_wall.rb'))

# ---- 5. the tile STANDS OFF the wall (2026-09-17, his 5/8") -------------
ok('5/8 is the default, in inches',
   (TW::DEFAULT_DEPTH - 0.625).abs < 1e-9, TW::DEFAULT_DEPTH)
ok('a solid tile is really pushed out, not painted on', SRC.include?('f.pushpull(dist)'))
ok('it is pushed TOWARDS the wall, off the outer face',
   SRC.include?('f.normal.dot(outward) > 0 ? -depth : depth'))
ok('every tile is its own group - the law that crashed SketchUp',
   SRC =~ /pieces\.each do \|p\|\s*\n\s*sub = ge\.add_group/)
ok('the sides get the material too, so a cut edge is not white',
   SRC =~ /sub\.entities\.grep\(Sketchup::Face\)\.each do \|q\|\s*\n\s*q\.material = mat/)
ok('the grout is FLUSH with the tile face, not recessed',
   SRC.include?('back = solid ? [dp - GROUT_BACK, GROUT_OFF].max : GROUT_OFF') &&
   TW::GROUT_BACK < 0.01 && TW::GROUT_BACK > 0.0, TW::GROUT_BACK)
ok('build! lays the notched tiles, not the convex pieces',
   SRC =~ /ps = pieces_rect\(u0, z0, w, h, holes/)
ok('too many tiles falls back to flat instead of hanging',
   SRC.include?('ps.length > MAX_SOLID'))
ok('there is a kill switch', SRC.include?('USE_SOLID_TILES'))
ok('the depth survives a rebuild', SRC.include?("'tile_depth'") &&
   SRC.include?("depth: a.call('tile_depth')"))

# ---- 6. the photo-as-pattern way (his idea, for star-and-cross etc) ----
ok('there are two ways to lay it', SRC.include?("md = mode.to_s == 'image' ? 'image' : 'tiles'"))
ok('the image way lays ONE slab per ring, not a tile at a time',
   SRC.include?('emit_slab_solids!(ge, fr, rings, mat'))
ok('and the openings are still notched out of it',
   SRC.include?('cut(u0, z0, u0 + w, z0 + h, holes)'))
ok('the photo is anchored to the area corner at its TRUE size, so it repeats',
   SRC.include?('def self.map_photo!') && SRC.include?('fr[:ux] * tex_u'))
ok('the way he chose survives a rebuild',
   SRC.include?("'tile_mode'") && SRC.include?("mode: a.call('tile_mode')"))
ok('the QUANTITIES are still counted tile by tile either way',
   SRC =~ /ps = pieces_rect/ && SRC =~ /res = InteriorPro::TileCount\.count/)

# ---- 7. a window that MOVES drags the tile with it ----------------------
# His words: "אם אני ציירתי טיל על חלון ואני מזיז את החלון הטיל צריך
# להשתנות בהתאם."
ok('this file requires no SketchUp to be read - the observer is guarded',
   SRC.include?('if defined?(Sketchup::ModelObserver)'))
ok('it watches the model instead of hooking one tool',
   SRC.include?('def onTransactionCommit'))
ok('undo and redo count as changes too',
   SRC.include?('def onTransactionUndo') && SRC.include?('def onTransactionRedo'))
ok('nothing is rebuilt unless the openings really moved',
   SRC.include?('changed = now.keys.select { |k| old[k] != now[k] }'))
ok('only the wall that changed is re-laid, not the whole model',
   SRC.include?('def self.refresh_wall!'))
ok('the rebuild is deferred - building inside the callback crashes SketchUp',
   SRC.include?('UI.start_timer(0.1, false)'))
ok('the watcher cannot trigger itself in a loop', SRC.include?('@busy'))
ok('the signature includes the wall floor, so raising a wall counts',
   SRC.include?('wall.bounds.min.to_a'))

TOOL = File.read('./tile_wall_tool.rb')
ok('the tool asks for the stand-off and sends it',
   TOOL.include?('DEPTH_IN') && TOOL.include?('depth: @cfg[:depth]'))
ok('5/8 is the first choice he sees', TOOL.include?("DEPTHS   = ['5/8\"'"))

puts($fails.zero? ? 'rt175 all green' : "rt175 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

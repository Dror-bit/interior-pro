# encoding: utf-8
# rt179 - SET THE HEIGHT FIRST, DRAW ONLY THE WIDTH (2026-09-18).
#
# His words: "אני רוצה לסרטט את הקיר ולקבוע רק את הרוחב והגובה יהיה
# בהגדרות שלפני שאני מסרטט", and when asked where that height starts,
# "תמיד מהרצפה למעלה". So a height chosen in the dialog always sits on
# the wall's own floor, and the two clicks only say how wide.
#
# The old way has to survive untouched: 'Drag it' is still the first
# choice, so nothing changes for him until he picks a height.
require './tile_wall'
require './tile_wall_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

T = InteriorPro::TileWallTool

ok('every height on the list has a number behind it',
   T::HEIGHTS.length == T::HEIGHT_V.length, [T::HEIGHTS.length, T::HEIGHT_V.length])
ok('dragging it is still ON the list', T::HEIGHTS.first == 'Drag it' && T::HEIGHT_V.first.nil?)
ok('but the height the dialog opens on is 96 - his default (2026-09-18)',
   File.read('./tile_wall_tool.rb').include?("height: 96.0, run: true, wrap: false, tile_txt: '',"))
ok('a whole wall is on the list without him having to know its height',
   T::HEIGHT_V.include?(:full))
ok('and the heights a tiler asks for are there',
   [96.0, 84.0, 72.0, 60.0, 48.0, 36.0].all? { |v| T::HEIGHT_V.include?(v) })

t = T.new
t.instance_variable_set(:@hgt, 90.5)

t.instance_variable_set(:@cfg, { height: nil })
ok('no height set means the old two-corner way', t.fixed_height.nil?)

t.instance_variable_set(:@cfg, { height: 72.0 })
ok('a height of 72 is 72', t.fixed_height == 72.0)

t.instance_variable_set(:@cfg, { height: :full })
ok('a whole wall is however tall THIS wall is', t.fixed_height == 90.5, t.fixed_height)

t.instance_variable_set(:@hgt, 0.0)
ok('and before a wall is under the mouse it is simply not set yet',
   t.fixed_height.nil?)

t.instance_variable_set(:@cfg, { height: 0.0 })
ok('a nonsense height is ignored rather than building nothing', t.fixed_height.nil?)

# ---- the real path -----------------------------------------------------
SRC = File.read('./tile_wall_tool.rb')
ok('the dialog asks for the height', SRC.include?("'Layout', 'Height'"))
ok('and remembers what he picked last time', SRC.include?('height: HEIGHT_V[HEIGHTS.index(res[5].to_s) || 0]'))
ok('A SET HEIGHT ALWAYS STARTS AT THE FLOOR - his words',
   SRC =~ /fh = fixed_height\n      if fh\n        z0 = 0\.0\n        h = fh\n      end/)
ok('the ghost rectangle shows that height, not wherever the mouse is',
   SRC.include?('rect_pts(@first[:u], 0.0, @hover[:u], fh)'))
ok('with a height set the box asks for ONE number, the width',
   SRC.include?("Sketchup.vcb_label = fh ? 'Width' : 'Width , Height'"))
ok('and one typed number is taken as the width',
   SRC.include?('b = fh if b.nil? && fh'))
ok('the status line says what the second click does now',
   SRC.include?('The height comes from the dialog'))
ok('the old two-number way still works when nothing is set',
   SRC.include?("Type width and height, e.g.  60,96"))


# ---- WALL AFTER WALL ----------------------------------------------------
# "בדיוק כמו ציור הקירות - אני מצייר קיר אחד, מסיים לסרטט אותו ומיד ממשיך
# לקיר השני". On by default, off in the same dialog.
ok('carrying on is a choice with two answers', T::RUNS.length == 2 && T::RUN_V == [true, false])
ok('and it is ON by default, as he asked', SRC.include?("run: true, wrap: false, tile_txt: '',"))
ok('the dialog has the off switch', SRC.include?("'Height', 'Carry on'"))
ok('and remembers it', SRC.include?('run: RUN_V[RUNS.index(res[6].to_s) || 0]'))
ok('a finished area hops round the corner instead of starting over',
   SRC.include?('hop_to_next!(lead) ? nil : reset_area'))
ok('the hop is refused when he switched it off', SRC.include?('return false unless @cfg && @cfg[:run]'))
ok('it hops only from the END he was drawing towards',
   SRC.include?('lead = b[:u] >= a[:u] ? u0 + w : u0'))
ok('it asks TileWall which wall is round that corner',
   SRC.include?('InteriorPro::TileWall.neighbour_at(@wall, @frame, lead_u)'))
ok('stopping halfway along a wall simply ends the run - there is no corner there',
   SRC.include?('return false if nb.nil?'))
ok('the next wall becomes the live one, with its own openings and height',
   SRC.include?('@holes = InteriorPro::TileWall.openings_for(nb[:wall], fr)') &&
   SRC.include?('@hgt = InteriorPro::TileWall.wall_height(nb[:wall])'))
ok('and the run starts at the corner, so one click says how far',
   SRC.include?('@first = { u: nb[:u_from], z: 0.0, kind: :corner'))
ok('a next wall with no room left says so instead of going quiet',
   SRC.include?('has no room left - the run ends here'))
ok('Esc still ends everything', SRC.include?('def onCancel'))


# ---- THE PATTERN AT THE CORNER ------------------------------------------
# "צריך להיות שתי האופציות, ברירת המחדל צריכה להיות 2 אבל יש גם אופציה
# לאחד אם רוצים": every wall starts fresh by default, one wrapping run on
# request.
TWc = InteriorPro::TileWall
ok('the corner has two answers', T::CORNERS.length == 2 && T::CORNER_V == [false, true])
ok('and starting fresh is the default, as he asked',
   T::CORNERS.first == 'Start fresh' && SRC.include?("run: true, wrap: false, tile_txt: '',"))
ok('the dialog asks', SRC.include?("'Carry on', 'Corner'"))
ok('and remembers it', SRC.include?('wrap: CORNER_V[CORNERS.index(res[7].to_s) || 0]'))

# a 12" tile, no joint: 40" used leaves a 4" cut, so 8" of it carries on
ok('a run that ends mid-tile hands the rest of that tile to the next wall',
   (TWc.carry_ox(40.0, 12.0, 0.0) - 8.0).abs < 1e-9, TWc.carry_ox(40.0, 12.0))
ok('a run that ends exactly on a joint starts the next wall on a whole tile',
   TWc.carry_ox(48.0, 12.0, 0.0) == 0.0)
# with a joint the pitch is 12.125, so 40" leaves 3.625 cut and 8.5 carries
ok('the joint is counted in the pitch, not forgotten',
   (TWc.carry_ox(40.0, 12.0, 0.125) - 8.5).abs < 1e-9, TWc.carry_ox(40.0, 12.0, 0.125))
ok('nonsense in gives no shift rather than a broken layout',
   TWc.carry_ox(40.0, 0.0, 0.0) == 0.0)

ok('the phase is worked out from what was REALLY built, after the corner square',
   SRC.include?("get_attribute('InteriorPro', 'built_w')"))
ok('and it is handed to the build as the layout offset',
   SRC.include?('ox: @carry_ox.to_f'))
ok('starting over clears it, so a new run never inherits an old phase',
   SRC =~ /def reset\n      @carry_ox = 0\.0/)
ok('what was really built is stored on the area',
   File.read('./tile_wall.rb').include?("set_attribute('InteriorPro', 'built_w', bw)"))


# ---- THE CORNER SQUARE SURVIVES A RUN (2026-09-18, caught twice) --------
# An area laid BEFORE its neighbour existed has nothing to pull back from.
# So after every build the drawing tool lays the corner neighbours again.
ok('after a build, the corner neighbours are laid again',
   SRC.include?('InteriorPro::TileWall.refresh_corner_neighbours!(grp) if grp'))
TWSRC = File.read('./tile_wall.rb')
# 2026-09-20: it now finds a corner by world-space proximity of the two
# areas' ends (corner_neighbour_wall_ids), not neighbour_at - the old path
# missed the corner where the last tile met only the previous TILE, 5/8"
# in front of the wall. See rt189.
ok('the helper lays the walls that share a corner, via corner_neighbour_wall_ids',
   TWSRC.include?('corner_neighbour_wall_ids(grp, model).each { |wid| n += refresh_wall!(wid) }'))
ok('the corner is judged by world-space proximity within a tile depth, not a fixed 0.51',
   TWSRC.include?('reach = dp + 0.6') &&
   TWSRC.include?('Math.hypot(mp[0] - tp[0], mp[1] - tp[1]) <= reach'))
ok('and says how many it laid, never silent',
   TWSRC.include?('neighbouring area(s) laid again for the corner square'))


# ---- THE TILE SIZE, TYPED (2026-09-18) ----------------------------------
# "יש אותו הצבע גם בגדלים אחרים - אני רוצה שתהיה האפשרות לקבוע בנפרד את
# גודל האריח." '48x24' - along the wall first, then up. One number is a
# square. Empty or 'From material' keeps the card's own size.
P = T.method(:parse_tile)
ok('empty keeps the card size', P.call('').nil? && P.call('  ').nil?)
ok("'From material' keeps the card size too", P.call('From material').nil?)
ok('48x24 is 48 along and 24 up', P.call('48x24') == [48.0, 24.0], P.call('48x24'))
ok('a capital X, a star and a comma all work',
   P.call('48X24') == [48.0, 24.0] && P.call('48*24') == [48.0, 24.0] &&
   P.call('48,24') == [48.0, 24.0])
ok('spaces do not matter', P.call(' 48 x 24 ') == [48.0, 24.0])
ok('one number is a square tile', P.call('24') == [24.0, 24.0])
ok('nonsense keeps the card size instead of a broken layout', P.call('abc').nil?)

SRC2 = File.read('./tile_wall_tool.rb')
ok('the dialog has the typed size box, and it is a TEXT box',
   SRC2.include?("'Vertical', 'Tile size'") && SRC2.include?("YESNO.join('|'), '']"))
ok('what he typed is remembered for next time',
   SRC2.include?("tile_txt: res[11].to_s =~ /material/i ? '' : res[11].to_s"))
ok('the typed size is handed to the build and BEATS the card',
   SRC2.include?('tile_w: @cfg[:tile] && @cfg[:tile][0], tile_l: @cfg[:tile] && @cfg[:tile][1]'))

puts($fails.zero? ? 'rt179 all green' : "rt179 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

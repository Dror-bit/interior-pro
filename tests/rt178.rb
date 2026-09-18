# encoding: utf-8
# rt178 - STRETCH A TILED AREA (2026-09-18).
#
# He asked for FOUR handles, the middle of each side, each one moving that
# side only - and for a typed size: "אפשרי גם להזין מידה שלוחצים על
# הידית?". So the two things that have to be true are: the side he grabs
# is the ONLY side that moves, and a typed number means the new SIZE of
# the area, not the raw position.
#
# And the CLAUDE.md rule that the maths alone proves nothing: the new
# numbers have to reach the model - written onto the area and rebuilt
# through TileWall.rebuild_area!, not drawn by this tool.
require './tile_wall'
require './tile_wall_stretch_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

T = InteriorPro::TileWallStretchTool

ok('there are exactly four handles, as he chose', T::EDGES.length == 4, T::EDGES)
ok('one per side', T::EDGES.sort == %i[u0 u1 z0 z1].sort, T::EDGES)
ok('the feature has a kill switch', T.const_defined?(:USE_STRETCH_TOOL))

t = T.new
t.instance_variable_set(:@u0, 10.0)
t.instance_variable_set(:@z0, 0.0)
t.instance_variable_set(:@w, 60.0)
t.instance_variable_set(:@h, 96.0)

ok('the side handles run across the wall', t.across?(:u0) && t.across?(:u1))
ok('the top and bottom ones do not', !t.across?(:z0) && !t.across?(:z1))

# ---- 1. the handles sit in the middle of each side ---------------------
ok('the left handle is halfway up the left side', t.handle_uz(:u0) == [10.0, 48.0], t.handle_uz(:u0))
ok('the right handle is halfway up the right side', t.handle_uz(:u1) == [70.0, 48.0], t.handle_uz(:u1))
ok('the bottom handle is halfway along the bottom', t.handle_uz(:z0) == [40.0, 0.0], t.handle_uz(:z0))
ok('the top handle is halfway along the top', t.handle_uz(:z1) == [40.0, 96.0], t.handle_uz(:z1))

# ---- 2. ONE side moves, the opposite side stays put --------------------
ok('dragging the right side to 90 makes the area 80 wide', t.size_for(:u1, 90.0) == 80.0)
ok('dragging the left side to 20 makes it 50 wide, the right edge untouched',
   t.size_for(:u0, 20.0) == 50.0)
ok('dragging the top to 60 makes it 60 tall', t.size_for(:z1, 60.0) == 60.0)
ok('dragging the bottom to 36 makes it 60 tall, the top untouched',
   t.size_for(:z0, 36.0) == 60.0)

# ---- 3. a typed size lands on the same place ---------------------------
T::EDGES.each do |e|
  v = t.value_for_size(e, 42.0)
  ok("typing 42 on the #{e} handle is the same as dragging it there",
     (t.size_for(e, v) - 42.0).abs < 1e-9, [e, v, t.size_for(e, v)])
end
ok('typing on the left handle keeps the right edge where it was',
   (t.value_for_size(:u0, 50.0) - 20.0).abs < 1e-9)
ok('typing on the bottom handle keeps the top where it was',
   (t.value_for_size(:z0, 60.0) - 36.0).abs < 1e-9)

# ---- 3b. it cannot walk THROUGH the wall at the corner -----------------
# His words: "הטיל לא יכול לעבור דרך קירות", and when it still ran past:
# the stored length of a wall goes centre line to centre line, but the
# FACE stops where the wall at the corner blocks it. Here the face runs
# from 0 to 96 and the wall is 100 high.
t.instance_variable_set(:@len, 101.5)
t.instance_variable_set(:@u_lo, 0.0)
t.instance_variable_set(:@u_hi, 96.0)
t.instance_variable_set(:@hgt, 100.0)
ok('a side inside the face is left where he put it', t.clamp_value(:u1, 70.0) == 70.0)
ok('typing past the corner stops at the face, not at the centre line',
   t.clamp_value(:u1, 200.0) == 96.0, t.clamp_value(:u1, 200.0))
ok('the stored wall length is NOT the limit - the blocked face is',
   t.clamp_value(:u1, 200.0) != 101.5)
ok('and the same going the other way', t.clamp_value(:u0, -20.0) == 0.0)
ok('the top cannot go over the wall either', t.clamp_value(:z1, 400.0) == 100.0)
ok('nor the bottom under the floor', t.clamp_value(:z0, -3.0) == 0.0)
ok('the width and the height have their OWN limit, not a shared one',
   t.clamp_value(:u1, 99.0) == 96.0 && t.clamp_value(:z1, 99.0) == 99.0)

# ---- 4. it locks onto points, and says which kind ----------------------
lines = [[0.0, :corner], [96.0, :corner], [48.0, :mid], [36.0, :edge]]
ok('a point well inside nothing is left alone', t.snap(70.0, lines, 1.0) == [70.0, nil])
ok('a point near a corner locks onto the corner', t.snap(95.6, lines, 1.0) == [96.0, :corner])
ok('a point near a middle locks onto the middle', t.snap(47.7, lines, 1.0) == [48.0, :mid])
ok('the nearest one wins', t.snap(40.0, lines, 10.0) == [36.0, :edge], t.snap(40.0, lines, 10.0))

# ---- 5. THE REAL PATH --------------------------------------------------
SRC = File.read('./tile_wall_stretch_tool.rb')
ok('the move and the click go through the SAME point method',
   SRC.scan(/edge_value\(view, x, y\)/).length >= 2)
ok('the ring is drawn where it locked, not on the raw cursor',
   SRC.include?('draw_ring(view, @hover)'))
ok('all four numbers are written back onto the area',
   %w[u0 z0 area_w area_h].all? { |k| SRC.include?("set_attribute('InteriorPro', '#{k}'") })
ok('the rebuild is handed to TileWall, this tool builds nothing itself',
   SRC.include?('InteriorPro::TileWall.rebuild_area!(@area, false)') &&
   !SRC.include?('add_face'))
ok('the write and the rebuild are ONE undo step',
   SRC.include?("start_operation('Interior Pro - Stretch Tile Area', true)"))
ok('a failed rebuild aborts instead of leaving half a change',
   SRC.include?('model.abort_operation'))
ok('the area is found again after the rebuild - build! erases the old group',
   SRC.include?('areas_in_model.find'))
ok('a stretch that leaves nothing is refused out loud',
   SRC.include?('that would leave nothing to tile'))
ok('a DRAGGED side is stopped at the wall too, not only a typed one',
   SRC.include?('stop = clamp_value(@grab, val)'))
ok('a height past the top of the wall or under the floor says so, not silently',
   SRC.include?('is past the top or the floor'))
ok('the limits come from the measured face, not from the stored wall length',
   SRC.include?('InteriorPro::TileWall.face_limits(wall, fr, @u0 + @w / 2.0)'))
ok('and the handles lock onto the real ends of the face',
   SRC.include?('out = [[@u_lo, :corner], [@u_hi, :corner]'))

# ---- 6. where the face really ends, on his own two walls ---------------
# Measured off his model (tile_corner_report.txt): a wall running north
# from (-438, 183) to (-438, 407.5), 5" thick, left anchored, tiled on
# side a - and the wall that closes the corner at its far end.
TWL = InteriorPro::TileWall
fb = TWL.frame(-438.0, 183.0, -438.0, 407.5, 5.0, 'left', 'a')
fa_a = TWL.frame(-438.0, 407.5, -702.0, 407.5, 5.0, 'left', 'a')
fa_b = TWL.frame(-438.0, 407.5, -702.0, 407.5, 5.0, 'left', 'b')
ok('the near face of the wall at the corner cuts this one at 219.5',
   (TWL.cross_u(fb, fa_a) - 219.5).abs < 1e-9, TWL.cross_u(fb, fa_a))
ok('its far face cuts it at the centre line, 224.5',
   (TWL.cross_u(fb, fa_b) - 224.5).abs < 1e-9, TWL.cross_u(fb, fa_b))
ok('the nearer of the two is the limit - 5 inches short of the stored length',
   [TWL.cross_u(fb, fa_a), TWL.cross_u(fb, fa_b)].min == 219.5)
ok('a wall parallel to this one can never cut it',
   TWL.cross_u(fb, TWL.frame(-500.0, 183.0, -500.0, 407.5, 5.0, 'left', 'a')).nil?)

# ---- 7. THE ONE THAT GOT THROUGH: a wall running INTO the middle -------
# "הקיר עדיין חוצה את קיר הפנים" - the shower wall Ts into the middle of
# the tiled wall, so the stored length says nothing about it. Measured off
# his model: (-534.599, 327.918) -> (-443, 327.918), 4.5" thick, left.
span = TWL.blocked_span(fb, -534.599, 327.918, -443.0, 327.918, 4.5, 'left')
ok('a wall running into the middle of this one blocks a stretch of it',
   !span.nil?, span)
ok('and the stretch it blocks is its own thickness, measured',
   span && (span[0] - 144.918).abs < 1e-3 && (span[1] - 149.418).abs < 1e-3, span)

# the wall that closes the corner blocks the far end, same method
corner = TWL.blocked_span(fb, -438.0, 407.5, -702.0, 407.5, 5.0, 'left')
ok('the wall at the corner is caught by the same rule',
   corner && (corner[0] - 219.5).abs < 1e-9 && (corner[1] - 224.5).abs < 1e-9, corner)

# a wall sitting behind this face, or standing free, is not in the way
behind = TWL.blocked_span(fb, -430.0, 300.0, -430.0, 350.0, 5.0, 'left')
ok('a wall parallel behind this face does not block it', behind.nil?, behind)
free = TWL.blocked_span(fb, -600.0, 300.0, -560.0, 300.0, 5.0, 'left')
ok('a wall standing free in the room, not touching this face, does not block it',
   free.nil?, free)
# THE BUG HE HIT (2026-09-18): "אני לא יכול להכניס מידה אלא אם אני מחזיק
# בלחיצה רצופה את הריבוע הקטן". SketchUp asks enableVCB? ONCE, when the
# tool is picked up - a conditional answer turns the box off for good.
ok('the measurement box is on for the whole tool, not only while a handle is held',
   SRC =~ /def enableVCB\?\n      true\n    end/)
ok('and a size typed with no handle held is just ignored',
   SRC.include?('return if @grab.nil?'))

ok('rebuild_area! can be told not to open its own operation',
   File.read('./tile_wall.rb').include?('def self.rebuild_area!(g, wrap_operation = true)'))

BAR = File.read('./toolbar.rb')
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
ok('the button is on the surfaces bar', SURF.include?("UI::Command.new('Stretch Tile')"))
ok('and it is in the button list, which is what the bar is built from',
   SURF.include?('buttons = [floors_cmd, tile_wall_cmd, tile_stretch_cmd]'))
ok('the plugin loads the new file', File.read('./main.rb').include?('tile_wall_stretch_tool.rb'))


# ---- 8. ROUND THE CORNER ------------------------------------------------
# "אני רוצה גם שתהיה אופציה למתוח כמה קירות של טיל אחד אחרי השני והם
# יתחברו". His face stops at 219.5; the run picks up on the next wall's
# face, and the same two measurements say where.
fa = TWL.frame(-438.0, 407.5, -702.0, 407.5, 5.0, 'left', 'a')
back = TWL.blocked_span(fa, -438.0, 183.0, -438.0, 407.5, 5.0, 'left')
ok('the tiled wall blocks the next face from 0 to 5', 
   back && back[0].abs < 1e-9 && (back[1] - 5.0).abs < 1e-9, back)
ok('so the run picks up at 5 on the next wall and grows away from the corner',
   back && back[1] < fa[:len] - 1.0)
ok('and the side it picks up on is the one facing the same room',
   (TWL.cross_u(fb, fa) - 219.5).abs < 1e-9)

ok('the tool asks TileWall which wall is round the corner',
   SRC.include?('InteriorPro::TileWall.neighbour_at(@wall, @frame, lim)'))
ok('only what he asked for BEYOND the wall is carried on',
   SRC.include?('over = across?(edge) ? (value.to_f - stop).abs : 0.0'))
ok('and only when there is something worth carrying',
   SRC.include?('if built && over > MIN_SIDE && carry_on!(edge, over, cfg)'))
ok('once the run has carried on, THIS area is laid again so the corner square comes back',
   SRC.include?('InteriorPro::TileWall.rebuild_area!(mine, false) if mine'))
ok('the settings are read BEFORE the rebuild, or the group handle is stale',
   SRC.index('cfg = settings_of(@area)') < SRC.index('rebuild_area!(@area, false)'))
ok('a run already round that corner is grown, not stacked on top of',
   SRC.include?("(near - nb[:u_from]).abs < 1.5"))
ok('it cannot spill past the end of the next wall either',
   SRC.include?('w = over > room ? room : over'))
ok('the whole thing is still ONE undo step',
   SRC.scan(/start_operation/).length == 1 && SRC.include?('carry_on!'))
ok('every wall starts its own layout - his default',
   !SRC.include?('pattern_ox'))
ok('no wall round the corner is said out loud, not skipped in silence',
   SRC.include?('there is no wall round that corner to carry on to'))


# ---- a real point anywhere in the model wins (CLAUDE.md, 2026-09-18) ----
# "אני רוצה שיהיה אפשר לדקור פינה או סוף של קו והקיר יימתח אוטומטית לשם."
ok('SketchUp own inference is asked whether it locked on a real point',
   SRC.include?('def locked_point?'))
ok('a vertex counts, and so does a point with no freedom left',
   SRC.include?('ip.respond_to?(:vertex) && ip.vertex') &&
   SRC.include?('ip.respond_to?(:degrees_of_freedom) && ip.degrees_of_freedom.zero?'))
ok('and such a point BEATS the tool own lines, it is not averaged with them',
   SRC.include?('if locked_point?(ip)'))
ok('the InputPoint lives as long as the tool - a fresh one never catches a corner',
   SRC.include?('@ip ||= Sketchup::InputPoint.new') && SRC.include?('ip.pick(view, x, y)'))
ok('and what it locked onto is DRAWN, the way SketchUp draws it',
   SRC.include?('@ip.draw(view)'))

puts($fails.zero? ? 'rt178 all green' : "rt178 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

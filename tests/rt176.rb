# encoding: utf-8
# rt176 - THE TILE WALL TOOL takes its point the way CLAUDE.md says
# (2026-09-17).
#
# His law, in his words: "אבל למה הוא שוב לא ננעל על פינה, סוף קו וכו'?
# תרשום את זה בחוק." The exact way it broke last time was a tool that
# locked on the click but DREW the raw cursor - the lock worked and was
# invisible. So this suite pins the shape of the tool, not only maths:
# one point method, used by both the move and the click, and a ring drawn
# from that same point.
require './tile_wall'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SRC = File.read('./tile_wall_tool.rb')

# ---- the point law -----------------------------------------------------
ok('the move asks face_point', SRC =~ /def onMouseMove.*?face_point\(view, x, y\)/m)
ok('the click asks the SAME face_point', SRC =~ /def onLButtonDown.*?face_point\(view, x, y\)/m)
ok('there is exactly one place the point is worked out',
   SRC.scan(/def face_point/).length == 1)
ok('the raw cursor is never used as the point',
   !SRC.include?('ip.position.x') && SRC.scan(/inputpoint/).length == 1)
ok('the ring is drawn from the same hash the click uses',
   SRC.include?('draw_ring(view, p)') && SRC =~ /def draw_ring.*p\[:u\], p\[:z\]/m)
ok('the three colours are the plugin colours, by kind',
   SRC =~ /when :corner then GREEN/ && SRC =~ /when :mid    then CYAN/ &&
   SRC =~ /when :edge   then MAGENTA/)
ok('corners and ends lock', SRC.include?('[0.0, :corner]') && SRC.include?('[@len, :corner]'))
ok('middles lock', SRC.include?(':mid'))
ok('an opening edge locks - a shower wall stops at the window',
   SRC =~ /def u_lines.*@holes.*h\[0\].*h\[2\]/m && SRC =~ /def z_lines.*@holes.*h\[1\].*h\[3\]/m)
ok('the lock window is in PIXELS, so it works zoomed out too',
   SRC.include?('pixels_to_model(SNAP_PX'))

# ---- the face is locked once the first corner is down -------------------
ok('hovering another wall cannot move a half-drawn area',
   SRC.include?('wall = @first ? @wall : (pick_wall(view, x, y) || @wall)'))
ok('the side is MEASURED off the click, not taken from the anchor',
   SRC =~ /def side_of.*side_offsets/m)

# ---- the tool owns no layout -------------------------------------------
ok('the tool hands the four numbers to TileWall.build!',
   SRC =~ /InteriorPro::TileWall\.build!\(\s*\n?\s*wall: @wall, side: @side, u0: u0, z0: z0, w: w, h: h/)
ok('no grid is computed in the tool', !SRC.include?('TileGrid.cells'))
ok('a failed build says so instead of leaving him guessing',
   SRC.include?('see the Ruby Console'))
ok('a too-small area is refused out loud', SRC.include?('too small'))

# ---- typed size, his other way in ---------------------------------------
ok('width,height can be typed', SRC.include?('def onUserText') && SRC.include?("split(/[,;xX]/)"))
ok('the VCB is on', SRC.include?('def enableVCB?'))
ok('hebrew geresh in a typed length is handled',
   SRC.include?("tr('׳', \"'\")"))

# ---- it is wired up -----------------------------------------------------
MAIN = File.read('./main.rb')
ok('registered in main.rb', MAIN.include?('tile_wall_tool.rb'))
ok('loaded AFTER the module it calls',
   MAIN.index('tile_wall.rb') < MAIN.index('tile_wall_tool.rb'))
TB = File.read('./toolbar.rb')
ok('there is a button', TB.include?('InteriorPro::TileWallTool.new'))
# The bar was rebuilt under a new name on 2026-09-18 - he was seeing its
# buttons twice, and SketchUp cannot take a button off a bar (rt170).
ok('the button lives on the Surfaces bar, next to the floors - his layout',
   TB.include?('UI::Toolbar.new(SURFACES_TOOLBAR_NAME)') &&
   TB[/def self\.setup_surfaces_toolbar.*?tb\.restore/m].to_s.include?('tile_wall_cmd'))
ok('there is only one Tile Wall button in the whole file',
   TB.scan(/InteriorPro::TileWallTool\.new/).length == 1)
ok('setup builds that bar', TB.include?('      setup_surfaces_toolbar'))
ok('and reload! refreshes it', MAIN.include?('setup_surfaces_toolbar'))

# ---- the side offsets the tool measures against are the wall's own ------
TW = InteriorPro::TileWall
ok('center anchor: the two faces are half a thickness either way',
   TW.side_offsets(6.0, 'center') == [3.0, -3.0], TW.side_offsets(6.0, 'center'))
ok('left anchor', TW.side_offsets(6.0, 'left') == [6.0, 0.0], TW.side_offsets(6.0, 'left'))
ok('right anchor', TW.side_offsets(6.0, 'right') == [0.0, -6.0], TW.side_offsets(6.0, 'right'))

puts($fails.zero? ? 'rt176 all green' : "rt176 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

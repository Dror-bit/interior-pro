# encoding: utf-8
# rt190 - THE DIRECTION HE DRAGS PICKS THE WALL AT A CORNER (2026-09-20).
#
# His words: "הוא נותן לי לצייר את קיר הטיל רק לכיוון החץ האדום ולא לחץ
# הכחול ... זה קורה כמעט בכל הפינות." Two walls meet at the corner he
# clicked. The old test asked which face the mouse was within 1" of, which
# breaks the moment he drags out into the room. drag_prefers_alt? asks the
# question he is really answering: which wall does the drag run ALONG.
require './sketchup_stub'
require './tile_wall_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

T = InteriorPro::TileWallTool
# current wall runs UP (axis 0,1 - the blue arrow). alt wall runs sideways
# (axis 1,0 - the red arrow).
CUR = [0.0, 1.0]
ALT = [1.0, 0.0]

# Drag straight up the current wall -> keep it (draw blue).
ok('dragging up the current wall keeps it', !T.drag_prefers_alt?(0.0, 40.0, *CUR, *ALT))
# Drag sideways along the alt wall -> switch to it (draw red).
ok('dragging along the other wall switches to it', T.drag_prefers_alt?(40.0, 0.0, *CUR, *ALT))
# Down the current wall is still the current wall (sign does not matter).
ok('down the current wall keeps it too', !T.drag_prefers_alt?(0.0, -40.0, *CUR, *ALT))
# Sideways the other direction still switches.
ok('the other way along the alt wall switches too', T.drag_prefers_alt?(-40.0, 0.0, *CUR, *ALT))
# A tiny drag has no clear direction yet - keep the first pick, no flicker.
ok('a tiny drag keeps the first pick (no flicker)', !T.drag_prefers_alt?(1.0, 0.5, *CUR, *ALT))
# A 45-degree drag that leans toward alt switches; leaning toward cur keeps.
ok('leaning toward the alt wall switches', T.drag_prefers_alt?(40.0, 30.0, *CUR, *ALT))
ok('leaning toward the current wall keeps', !T.drag_prefers_alt?(30.0, 40.0, *CUR, *ALT))
# Exactly diagonal does not switch (needs to clearly beat current).
ok('a dead-diagonal drag does not switch', !T.drag_prefers_alt?(30.0, 30.0, *CUR, *ALT))

# The real path: swap_to_alt! uses the drag, not a 1-inch face test.
SRC = File.read('./tile_wall_tool.rb')
sw = SRC[/def swap_to_alt!.*?\n    end\n/m]
ok('swap_to_alt! decides by drag direction', sw.include?('drag_prefers_alt?'))
ok('...and no longer by the 1-inch face-proximity test',
   !sw.include?('d.abs <= 1.0'))
ok('the drag vector is measured from the first corner',
   sw.include?('pos.x - fp.x, pos.y - fp.y'))

puts($fails.zero? ? 'rt190 all green' : "rt190 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt193 - THE NICHE IS PLACED LIKE A WINDOW (2026-09-22).
#
# His words: "זה צריך להיות כמו החלונות - פותחים את הכפתור ואז יש תפריט
# לאורך לגובה ולעומק, גובה הניצ מהריצפה, ואז ממקמים את הניץ עם ריבוע
# רפאים". The ghost is held by its MIDDLE, and it is green only where it
# really fits: on the clear run of the face and under the top of the wall.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

T = InteriorPro::TileNicheTool
ok('his first sizes: 36 x 18, 4" deep, 42" up',
   T.last == { w: 36.0, h: 18.0, depth: 4.0, sill: 42.0 }, T.last)
ok('the mouse holds the MIDDLE of the niche', T.ghost_u0(30.0, 12.0) == 24.0)
ok('fits in the middle of a clear wall', T.fits?(24.0, 12.0, 48.0, 24.0, 0.0, 96.0, 96.0))
ok('red when it runs into the wall at the start', !T.fits?(-1.0, 12.0, 48.0, 24.0, 0.0, 96.0, 96.0))
ok('red when it runs into the wall at the far end', !T.fits?(85.0, 12.0, 48.0, 24.0, 0.0, 96.0, 96.0))
ok('red when a wall standing on the face is in the way',
   !T.fits?(40.0, 12.0, 48.0, 24.0, 0.0, 45.0, 96.0))
ok('dead tight against the wall still fits', T.fits?(84.0, 12.0, 48.0, 24.0, 0.0, 96.0, 96.0))
ok('red when it goes out of the top of the wall', !T.fits?(24.0, 12.0, 80.0, 24.0, 0.0, 96.0, 96.0))
ok('the tool owns no niche maths - it hands over to TileNiche',
   File.read('./tile_niche_tool.rb').include?('InteriorPro::TileNiche.add!'))
ok('the drag is gone - it is placed, not dragged',
   !File.read('./tile_niche_tool.rb').include?('@first = p'))

# ---- the bar (his words: "קו בין הכפתורים לכפתורים האחרים באותו הסרגל")
BAR = File.read('./toolbar.rb')
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
ok('the niche is on the surfaces bar', SURF.include?("UI::Command.new('Niche')"))
ok('after a separator line', SURF.index('tb.add_separator').to_i > SURF.index('tile_edit_cmd]').to_i)
ok('and AFTER the old buttons, never in the middle of their list',
   SURF.include?('buttons = [floors_cmd, tile_wall_cmd, tile_stretch_cmd, tile_split_cmd, tile_edit_cmd]'))
ok('added by name, so a reload cannot duplicate it', SURF.include?('on_bar.include?'))
ok('the one-day separate bar is hidden', BAR[/def self\.hide_old_bars!.*?\n    end\n/m].to_s.include?("'Interior Pro Niche'"))

puts($fails.zero? ? 'rt193 OK' : "rt193 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

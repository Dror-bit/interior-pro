# encoding: utf-8
# rt170 - THE TILES BUTTON (2026-09-06, changed 2026-09-07).
#
# The drawing worked from the Ruby Console; he asked for a button.
# SketchUp's toolbar API cannot be exercised in the cloud, so this reads
# toolbar.rb the way rt43/rt44/rt136/rt149 do - what it registers, on
# which bar, with which icon - plus the one thing that actually breaks
# in practice: the floors toolbar refuses to rebuild itself once it
# already holds as many buttons as the guard expects.
require './tile_sheet'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

BAR = File.read('./toolbar.rb')
FLOORS = BAR[/def self\.setup_floors_toolbar.*?\n    end\n/m].to_s
ok('the floors toolbar section was found', !FLOORS.empty?)

# ---- 1. the button is registered -------------------------------------
ok('there is a Tiles command', FLOORS.include?("UI::Command.new('Tiles')"))
ok('it is on the floors toolbar, not the wall one', FLOORS.include?('tb.add_item(tile_count_cmd)'))
ok('it opens the window', FLOORS =~ /InteriorPro::TileCountDialog\.show/)
ok('it has its own icon', FLOORS.include?("icon_path('tile_sheet')"))
ok('it has a tooltip and a status line',
   FLOORS.include?('tile_count_cmd.tooltip') && FLOORS.include?('tile_count_cmd.status_bar_text'))

# ---- 2. THE GUARD - this is what would have hidden it -----------------
# setup_floors_toolbar returns early when the bar already holds its full
# set. Adding a fifth button without moving that number means the button
# never appears for anyone who already has the toolbar.
n = FLOORS[/return if tb\.length >= (\d+)/, 1].to_i
adds = FLOORS.scan(/tb\.add_item\(/).length
ok('the toolbar adds five buttons', adds == 5, adds)
ok('...and the guard was moved to match, or the new one never shows up',
   n == adds, [n, adds])

# ---- 3. the four that were already there are untouched ---------------
['Room Names', 'Build Floors', 'Foundation', 'Ceilings'].each do |name|
  ok("#{name} is still on the bar", FLOORS.include?("UI::Command.new('#{name}')"))
end

# ---- 4. the icon exists ----------------------------------------------
icon = ['../icons/tile_sheet.svg', 'icons/tile_sheet.svg'].find { |p| File.exist?(p) }
ok('the icon file is there', !icon.nil?, Dir.glob('../icons/tile*'))
if icon
  svg = File.read(icon)
  ok('it is an svg on the 24px grid', svg.include?('viewBox="0 0 24 24"'))
  ok('it uses the same grey base as the other icons', svg.include?('#e8e8e8') && svg.include?('#555555'))
end

# ---- 5. the button cannot damage the model ---------------------------
ok('the command starts no model operation - the window only reads',
   !FLOORS[/UI::Command\.new\('Tiles'\).*?\n      \}/m].to_s.include?('start_operation'))

# ---- 6. IT WRITES NOTHING (changed 2026-09-07) -----------------------
# It used to write two .svg files and open them in Chrome. He stopped
# that himself: the quantities are for him while he designs, so they
# are a window. tile_sheet.rb stays in the plugin for the plans, but
# NO button may call it.
ok('no button writes a file any more', !FLOORS.include?('TileSheet.write_all!'))
ok('no button opens a browser any more', !FLOORS.include?('UI.openURL'))
ok('and it does not nag with a message box', !FLOORS.include?('UI.messagebox'))

puts($fails.zero? ? 'rt170 OK' : "rt170 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

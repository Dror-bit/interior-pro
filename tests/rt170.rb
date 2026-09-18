# encoding: utf-8
# rt170 - THE BARS (2026-09-06, rewritten 2026-09-17).
#
# It used to pin the "Interior Pro Floors" bar and its Tiles button, and
# it had been red for days over a button count on a bar that no longer
# exists. He reorganised the bars by WHAT HE IS DOING: "כל כפתורי
# הנתונים החומרים ושייוך הפרוייקטים... צריכים להיות ביחד, והתוכניות
# והסירטוט לחוד." So this suite pins the new arrangement, and the one
# thing that actually breaks in practice: a bar whose length guard does
# not match its own buttons never shows the new one.
require './tile_sheet'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

BAR = File.read('./toolbar.rb')

def section(name)
  BAR[/def self\.#{name}.*?\n      tb\.restore\n    end\n/m].to_s
end

BUILD = BAR[/def self\.setup_build_toolbar.*?\n      toolbar\.restore\n    end\n/m].to_s
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
DATA = section('setup_data_toolbar')
PLANS = section('setup_2d_toolbar')

ok('the build bar is there', !BUILD.empty?)
ok('the surfaces bar is there', !SURF.empty?)
ok('the data bar is there', !DATA.empty?)
ok('the drawing bar is still its own', !PLANS.empty?)
ok('the old floors bar is not built any more', !BAR.include?('setup_floors_toolbar'))
ok('and neither is the one-button tile bar', !BAR.include?('setup_tile_toolbar'))
ok('both new bars are built at startup',
   BAR =~ /setup_surfaces_toolbar\n      setup_data_toolbar/)

# ---- what is on which bar ---------------------------------------------
{ 'Wall Tool' => BUILD, 'Window Tool' => BUILD, 'Door Tool' => BUILD,
  'Molding' => BUILD, 'Ceilings' => BUILD, 'Foundation' => BUILD,
  'Build Floors' => SURF, 'Tile Wall' => SURF, 'Materials' => DATA,
  'Room Names' => DATA, 'Tiles' => DATA, '2D Editor' => PLANS,
  'Sheet' => PLANS }.each do |name, sec|
  ok("#{name} is on its bar", sec.include?("UI::Command.new('#{name}')"), name)
end

ok('the quantities are NOT on the drawing bar', !PLANS.include?("UI::Command.new('Tiles')"))
ok('the materials are not mixed in with the surfaces',
   !SURF.include?("UI::Command.new('Materials')"))
ok('the surfaces bar is only the surfaces now',
   !SURF.include?("UI::Command.new('Ceilings')") &&
   !SURF.include?("UI::Command.new('Foundation')"))

# ---- the lines he asked for, between every family ----------------------
ok('there are four separators on the build bar - walls | windows | doors | molding | structure',
   BUILD.scan(/toolbar\.add_separator/).length == 4,
   BUILD.scan(/toolbar\.add_separator/).length)
ok('a line sits before the windows',
   BUILD =~ /toolbar\.add_separator.*?\n\n      # Window Tool Button/m)
ok('a line sits before the doors',
   BUILD =~ /toolbar\.add_separator.*?\n\n      # Door Tool Button/m)
ok('a line sits before the molding',
   BUILD =~ /toolbar\.add_separator.*?\n\n      # Molding \(baseboard/m)
ok('ceilings and foundation are last, behind their own line',
   BUILD.index('toolbar.add_item(ceilings_cmd)') > BUILD.index('toolbar.add_item(molding_refresh_cmd)'))
ok('the old bars are hidden instead of leaving him duplicates',
   BAR.include?('def self.hide_old_bars!') && BAR.include?("'Interior Pro Floors'"))
ok('an EMPTY old bar is hidden too - it shows as one blank button',
   BAR[/def self\.hide_old_bars!.*?\n    end\n/m].to_s !~ /tb\.hide if tb\.length/)
ok('every button is on exactly one bar - nothing is duplicated',
   ['Ceilings', 'Foundation', 'Tile Wall', 'Tiles', 'Materials'].all? do |n|
     BAR.scan(/UI::Command\.new\('#{n}'\)/).length == 1
   end)

# ---- THE GUARD - this is what hides a new button ----------------------
# The surfaces bar does NOT use a count guard any more (2026-09-18). He saw
# its buttons twice: raising the guard from 2 to 3 made a bar that already
# had 2 buttons run the whole method again and end up with 5. It now adds
# only the buttons past what the bar already holds, so a new button is one
# more line in the list and nothing else to remember.
ok('the surfaces bar adds only the buttons it is missing',
   SURF.include?('buttons.each_with_index { |cmd, i| tb.add_item(cmd) if i >= have }'))
ok('and it has no count guard left to fall out of step with',
   SURF !~ /return if tb\.length >= \d+/)
ok('the bar it builds is a NEW one, the old one cannot be cleaned up',
   BAR.include?("SURFACES_TOOLBAR_NAME = 'Interior Pro Surface Tools'"))
ok('and the old surfaces bar is hidden, or he keeps seeing both',
   BAR[/def self\.hide_old_bars!.*?\n    end\n/m].to_s.include?("'Interior Pro Surfaces'"))

[['data', DATA], ['plans', PLANS]].each do |label, sec|
  n = sec[/return if tb\.length >= (\d+)/, 1].to_i
  adds = sec.scan(/tb\.add_item\(/).length
  ok("the #{label} bar guard matches its own buttons", n == adds, [label, n, adds])
end
bn = BAR[/BUILD_TOOLBAR_ITEM_COUNT = (\d+)/, 1].to_i
badds = BUILD.scan(/toolbar\.add_item\(/).length
ok('the build bar guard matches its own buttons', bn == badds, [bn, badds])
ok('and the guard is the one the method actually reads',
   BUILD.include?('return if toolbar.length >= BUILD_TOOLBAR_ITEM_COUNT'))

# ---- the roofs bar was left alone, he asked for that ------------------
ok('the roofs bar still exists on its own', BAR.include?("UI::Toolbar.new('Interior Pro Roofs')"))
ok('and the roof buttons were not moved',
   BAR.include?("UI::Command.new('Roof')") && BAR.include?("UI::Command.new('Dormer')"))

# ---- the Tiles button still only reads --------------------------------
ok('the command starts no model operation - the window only reads',
   !DATA[/UI::Command\.new\('Tiles'\).*?\n      \}/m].to_s.include?('start_operation'))
ok('no button writes a file', !DATA.include?('TileSheet.write_all!'))
ok('no button opens a browser', !DATA.include?('UI.openURL'))

# ---- the icons exist ---------------------------------------------------
%w[tile_sheet tile_wall floor_tool ceiling_tool foundation_tool
   material_library room_names].each do |name|
  path = ["../icons/#{name}.svg", "icons/#{name}.svg"].find { |q| File.exist?(q) }
  ok("the #{name} icon file is there", !path.nil?)
end

# ---- reload! rebuilds the new bars, or he has to restart every time ---
MAIN = File.read('./main.rb')
ok('reload! refreshes the build bar', MAIN.include?('setup_build_toolbar'))
ok('reload! refreshes the surfaces bar', MAIN.include?('setup_surfaces_toolbar'))
ok('reload! refreshes the data bar', MAIN.include?('setup_data_toolbar'))
ok('reload! does not call a bar that is gone', !MAIN.include?('setup_floors_toolbar'))

puts($fails.zero? ? 'rt170 OK' : "rt170 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

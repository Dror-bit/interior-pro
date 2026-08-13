# encoding: utf-8
# rt44 - reload without restarting SketchUp (2026-08-12).
#
# The user asked why every change needed a restart. Two reasons, both fixed:
#   1. reload! only re-ran the file LIST it already had, so a brand new file
#      was never loaded.
#   2. the small toolbars were only ever built once.
#
# This suite runs the real reload! against a stand-in SketchUp, and adds a
# file to the list in between - exactly the case that used to need a restart.
require './sketchup_stub'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

require 'tmpdir'
require 'fileutils'

# ------------------------------------------------- a plugin folder of our own
dir = File.join(Dir.tmpdir, "rt44_#{Process.pid}")
FileUtils.rm_rf(dir)
FileUtils.mkdir_p(dir)
real_main = File.read(File.join(File.dirname(__FILE__), 'main.rb'), encoding: 'UTF-8')

# the same main.rb, but listing only one little file to begin with
main = real_main.sub(/def self\.plugin_files\s*\n\s*%w\[.*?\]\s*\n\s*end/m,
                     "def self.plugin_files\n      %w[\n        one.rb\n      ]\n    end")
File.write(File.join(dir, 'main.rb'), main)
File.write(File.join(dir, 'one.rb'), "module InteriorPro; ONE_LOADED = true; end\n")
File.write(File.join(dir, 'two.rb'), "module InteriorPro; TWO_LOADED = true; end\n")

# UI setup is not what we are testing here
module InteriorPro
  def self.setup_ui!; @ui_setup_complete = true; end
end
def file_loaded?(_f); true; end
def file_loaded(_f); true; end

load File.join(dir, 'main.rb')
ok('the first file loaded', InteriorPro.const_defined?(:ONE_LOADED, false))
ok('the second one has not', !InteriorPro.const_defined?(:TWO_LOADED, false))

# now a new file joins the list, exactly like plan_doc.rb or plan_tables.rb did
File.write(File.join(dir, 'main.rb'),
           main.sub("        one.rb\n", "        one.rb\n        two.rb\n"))

InteriorPro.reload!
ok('reload! picked up the brand new file - no restart needed',
   InteriorPro.const_defined?(:TWO_LOADED, false))

# and it says so out loud rather than pretending everything is live
ok('it warns that a new MENU item still needs a restart',
   real_main.include?('New menu ITEMS still need a restart'))

# ----------------------------------------------------- the toolbars come back
calls = []
module InteriorPro
  module Toolbar
    def self.setup_2d_toolbar; $rt44_calls << :two_d; end
    def self.setup_floors_toolbar; $rt44_calls << :floors; end
    def self.setup_roofs_toolbar; $rt44_calls << :roofs; end
  end
end
$rt44_calls = calls
InteriorPro.refresh_toolbars!
ok('the 2D toolbar is rebuilt, so a new button appears without a restart',
   calls.include?(:two_d), calls)
ok('the floors and roofs bars too', calls.include?(:floors) && calls.include?(:roofs), calls)

# a broken toolbar must not stop the others
module InteriorPro
  module Toolbar
    def self.setup_floors_toolbar; raise 'boom'; end
  end
end
calls.clear
InteriorPro.refresh_toolbars!
ok('one broken bar does not take the rest down', calls.include?(:roofs), calls)

# --------------------------------------------------------- the wiring is real
tb = File.read(File.join(File.dirname(__FILE__), 'toolbar.rb'), encoding: 'UTF-8')
ok('there is a Reload item in the menu', tb.include?("menu.add_item('Reload Interior Pro')"))
ok('and it calls reload!', tb =~ /Reload Interior Pro'\)\s*\{\s*InteriorPro\.reload!/m)
ok('reload! reloads main.rb itself, not just the old list',
   real_main =~ /def self\.reload!.*?load File\.join\(PLUGIN_DIR, 'main\.rb'\)/m)
ok('the menu is deliberately NOT re-run', !real_main.include?('Menu.setup') ||
   real_main[/def self\.refresh_toolbars!.*?\n  end/m].to_s !~ /Menu/)

FileUtils.rm_rf(dir)
puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt232 - "SAVE SELECTED" (2026-09-29). He builds a vanity in the model,
# selects it, and it is saved into VANITIES as its own .skp - a new
# product. Only one group/component, only a single-file kind.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_dialog'
require 'tmpdir'
require 'fileutils'
$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
root = Dir.mktmpdir
module InteriorPro; end
InteriorPro.send(:remove_const, :PLUGIN_DIR) if InteriorPro.const_defined?(:PLUGIN_DIR)
InteriorPro.const_set(:PLUGIN_DIR, root)
L = InteriorPro::FixtureLibrary

defn = Sketchup::ComponentDefinition.new('Oak vanity')
def defn.save_as(path); File.write(path, 'skp'); true; end
inst = Sketchup::ComponentInstance.new(defn)

n = L.save_selected!('vanity', inst, 'Oak 36"')
ok('saved under a clean name', n == 'Oak 36', n)
ok('the file is in VANITIES', File.exist?(File.join(root, 'assets', 'PLUMBING', 'VANITIES', 'Oak 36.skp')))
ok('it is now a product', L.products('vanity').include?('Oak 36'), L.products('vanity'))
n2 = L.save_selected!('vanity', inst, 'Oak 36')
ok('the same name again gets a number, never overwrites', n2 == 'Oak 36 2', n2)
ok('a tub goes to TUBS', L.save_selected!('tub', inst, 'Alcove') == 'Alcove' &&
   File.exist?(File.join(root, 'assets', 'PLUMBING', 'TUBS', 'Alcove.skp')))
ok('a shower SET is a folder - not saved', L.save_selected!('shower_set', inst, 'X').nil?)
ok('not a group or component - not saved', L.save_selected!('vanity', Object.new, 'X').nil?)
bad = Sketchup::ComponentDefinition.new('bad')
def bad.save_as(_p); false; end
ok('SketchUp did not write it - nil, no product', L.save_selected!('vanity', Sketchup::ComponentInstance.new(bad), 'Bad').nil? &&
   !L.products('vanity').include?('Bad'))

html = InteriorPro::FixtureDialog.build_html(InteriorPro::FixtureDialog.defaults, {}, 'Place')
ok('the window has the Save selected card', html.include?('saveSel()') && html.include?('Save selected'))
ok('...but not for a set', html.include?("if (!CAT[kind].set) html += '<div class=\"design-card add\" onclick=\"saveSel()\""))
FileUtils.rm_rf(root)
puts($fails.zero? ? 'rt232 OK' : "rt232 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

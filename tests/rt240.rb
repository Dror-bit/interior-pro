# encoding: utf-8
# rt240 - A NEW ROOF STARTS ON SHINGLES (2026-10-01, his words: "כל פעם
# שאני מציב גג חדש ברירת המחדל צריכה להיות שינגלס... לא רוצה שתשנה
# פרוייקטים קיימים"). Measured on his model first (roof_default_report.txt):
# the model had roof_material "color" saved and no roof standing, so the
# plain panel opened on Solid color. Only the plain panel changes: Edit Roof
# opens on the roof's own material, and nothing saved is rewritten.
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './roof_manager'
require './roof_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager
RD = InteriorPro::RoofDialog
model = Sketchup.active_model

# HIS model: Solid color saved, no roof.
model.set_attribute('InteriorPro', 'roof_material', 'color')
s = RD.new_roof_settings(RF.settings)
ok('the plain panel opens on Shingles', s[:roof_material] == 'shingle', s[:roof_material])
ok('nothing else in the settings moves', s.reject { |k, _| k == :roof_material } == RF.settings.reject { |k, _| k == :roof_material })
ok('the saved value in the model is not rewritten', model.get_attribute('InteriorPro', 'roof_material') == 'color')
html = RD.build_html(s)
ok('Shingles is the selected line in the list', html.include?('<option value="shingle" selected>Shingles</option>'))
ok('...and Solid color is not', !html.include?('<option value="color" selected>'))
ok('the swatch shows the shingle grey', html.include?('id="roofColor" value="#7f8385"'), html[/id="roofColor" value="[^"]*"/])

# the real path: show() hands the plain panel the new settings, and Edit Roof its own
src = File.read('./roof_dialog.rb', encoding: 'utf-8')
ok('show() uses it for the plain panel only',
   src.include?("@target ? RoofManager.roof_settings(@target)\n                                      : new_roof_settings(RoofManager.settings)"))

# EDIT ROOF: a standing Spanish roof still opens on Spanish.
roof = Sketchup::Group.new
roof.set_attribute('InteriorPro', 'type', 'roof')
roof.set_attribute('InteriorPro', 'set_roof_material', 'metaltile')
eh = RD.build_html(RF.roof_settings(roof), edit: true)
ok('Edit Roof opens on the roof\'s own material', eh.include?('<option value="metaltile" selected>Spanish Tile</option>'))

# kill switch
RD.send(:remove_const, :USE_SHINGLE_DEFAULT)
RD.const_set(:USE_SHINGLE_DEFAULT, false)
ok('kill switch: the panel opens on the saved material', RD.new_roof_settings(RF.settings)[:roof_material] == 'color')

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

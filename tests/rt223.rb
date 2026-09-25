# encoding: utf-8
# rt223 - PLUMBING EDIT (2026-09-25). His ask: "עריכה". And no delete
# tool - "אפשר פשוט לסמן ולעשות דליט", it cuts no hole in anything.
require './sketchup_stub'
require './tile_wall_tool'
require './tile_niche'
require './tile_niche_tool'
require './fixture_library'
require './fixture_tool'
require './fixture_edit_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

lib = File.read('./fixture_library.rb')
ed  = File.read('./fixture_edit_tool.rb')
dlg = File.read('./fixture_dialog.rb')
ok('no delete tool and no remove! - SketchUp Delete is the delete',
   !lib.include?('def self.remove!') && !File.exist?('./fixture_delete_tool.rb'))
ok('edit opens the SAME window, with its own numbers',
   ed.include?('FixtureLibrary.settings_of(hit)') && ed.include?("FixtureDialog.show(prefill, button: 'Apply')"))
ok('the tool owns no geometry - update! does it', ed.include?('FixtureLibrary.update!(hit, cfg)'))
ok('one undo step: place! inside the edit runs without its own operation',
   lib.include?("model.start_operation('Edit Fixture', true)") && lib.include?('op: false'))
ok('the edit keeps the id', lib.include?("made.set_attribute('InteriorPro', 'id', old_id)"))
ok('a typed corner distance is measured from the SAME nearer corner',
   lib.include?("u = u_from_corner(cfg['corner'].to_f, lo, hi, u)"))
ok('the corner field shows only in the edit window', dlg.include?('cornerRow') && dlg.include?("D.corner !== undefined"))
ok('the corner is not remembered for the next placing', dlg.include?("@last = cfg.reject { |k, _| k == 'corner' }"))
L = InteriorPro::FixtureLibrary
ok('only a fixture instance counts', !L.fixture?(nil) && !L.fixture?(Object.new))

BAR = File.read('./toolbar.rb')
SURF = BAR[/def self\.setup_surfaces_toolbar.*?\n      tb\.restore\n    end\n/m].to_s
ok('Edit Plumbing is on the bar, after Plumbing, by name',
   SURF.include?("UI::Command.new('Edit Plumbing')") && SURF.include?('[fixture_cmd, fixture_edit_cmd].each'))
ok('no Delete Plumbing button', !SURF.include?('Delete Plumbing'))
ok('main loads the edit tool', File.read('./main.rb').include?('fixture_edit_tool.rb'))

puts($fails.zero? ? 'rt223 OK' : "rt223 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

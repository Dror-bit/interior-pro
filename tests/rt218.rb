# encoding: utf-8
# rt218 - NO MATERIAL CHOSEN = WHITE (2026-09-23, his ask: the default floor
# was wood, "עץ משונה", and he prefers white). A floor with no texture
# picked is plain White; the type still sets the thickness; a picked
# texture is untouched; the kill switch brings the wood back.
require './sketchup_stub'
require './floor_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
FM = InteriorPro::FloorManager
model = Sketchup.active_model

m = FM.plain_material(model, 'Hardwood')
ok('no texture picked - the floor is White', m && m.name == 'InteriorPro_FloorTex_White', m && m.name)
ok('White is really white', FM::SOLID_COLORS['White'] == [255, 255, 255])
ok('the Hardwood type still sets the thickness', FM::FLOOR_TYPES['Hardwood'][:thickness] == 0.75)
src = File.read('./floor_manager.rb')
ok('the room floor and the patch both use it when no texture is picked',
   src.scan('mat = tex ? texture_material(model, tex) : plain_material(model, type_name)').length == 2)
ok('a missing texture file falls back to White too', src.include?('return plain_material(model, DEFAULT_TYPE) unless f'))
ok('the shower floor with nothing to copy is White too',
   File.read('./shower_floor.rb').include?('FloorManager.plain_material(model, InteriorPro::FloorManager::DEFAULT_TYPE)'))
FM.send(:remove_const, :USE_WHITE_DEFAULT)
FM.const_set(:USE_WHITE_DEFAULT, false)
w = FM.plain_material(model, 'Hardwood')
ok('kill switch: the old wood comes back', w && w.name == 'InteriorPro_Floor_Hardwood', w && w.name)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

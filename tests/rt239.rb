# encoding: utf-8
# rt239 - THE FLOORS WINDOW, 2026-10-01. Two things he hit on the garage:
#
# 1. "Drop walls" did nothing. The Apply callback also asked for a texture,
#    and since 2026-09-23 the texture field is hidden and always empty - so
#    the walls never dropped, in any room, with any material.
# 2. Concrete in the Pattern list (his words: "הפטרן הוא הקובע, זה הסוג
#    ריצפה, החומר זה רק נוסף"). Stored as pattern 'None' + floor_texture
#    'concrete', so nothing else in the plugin meets a new word.
#
# Pinned on the pure helpers, then on the real path: apply_selections builds
# the floor, and what the window reads back is "Concrete" again.
require './sketchup_stub'
require './floor_manager'

$room = Sketchup::Group.new
$room.set_attribute('InteriorPro', 'id', 'R2')
$room.set_attribute('InteriorPro', 'name', 'Room 2')
$room.set_attribute('InteriorPro', 'boundary_xy', [0.0, 0.0, 240.0, 0.0, 240.0, 240.0, 0.0, 240.0])
module InteriorPro
  module RoomManager
    def self.rooms_in_model; [$room]; end
  end
  def self.assign_tag(*); end unless respond_to?(:assign_tag)
end
require './floor_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
FD = InteriorPro::FloorDialog
FM = InteriorPro::FloorManager
src = File.read('./floor_dialog.rb', encoding: 'utf-8')

# ---- 1. Drop walls no longer waits for a texture ---------------------------
ok('Drop walls is decided by its own checkbox alone', src.include?("next unless cfg['drop_walls']\n"))
ok('...and never by the hidden texture field', !src.include?("cfg['drop_walls'] && !cfg['texture']"))

# ---- 2. the pure helpers ----------------------------------------------------
ok('Concrete is stored as None + the concrete picture', FD.stored_pattern('Concrete', '') == %w[None concrete], FD.stored_pattern('Concrete', ''))
ok('Tile is stored as it always was', FD.stored_pattern('Tile', '') == ['Tile', ''], FD.stored_pattern('Tile', ''))
ok('nothing chosen is None', FD.stored_pattern(nil, nil) == ['None', ''], FD.stored_pattern(nil, nil))
ok('None + concrete reads back as Concrete', FD.shown_pattern('None', 'concrete') == 'Concrete')
ok('None alone stays None', FD.shown_pattern('None', nil) == 'None')
ok('a tile floor is never renamed', FD.shown_pattern('Tile', 'concrete') == 'Tile')
ok('Concrete is the LAST word in the Pattern list', src.include?("'Herringbone', 'Chevron', 'Concrete'].map"))

# ---- 3. the real path: Apply ------------------------------------------------
class << FM
  def texture_files; ['/x/textures/floors/concrete.jpg', '/x/textures/floors/oak_light.jpg']; end
  def build_door_patches!; 0; end
end
cfg = { 'type' => 'Hardwood', 'thickness' => 0.75, 'pattern' => 'Concrete', 'texture' => '',
        'material_card_id' => '', 'level' => -18, 'drop_walls' => true, 'center' => true }
FD.apply_selections('R2' => cfg)
fl = FM.floors_in_model.first
ok('Apply built the floor', !fl.nil?)
if fl
  ok('the slab wears the concrete picture', fl.get_attribute('InteriorPro', 'floor_texture') == 'concrete',
     fl.get_attribute('InteriorPro', 'floor_texture'))
  ok('the stored pattern is a word every other file knows', fl.get_attribute('InteriorPro', 'pattern') == 'None',
     fl.get_attribute('InteriorPro', 'pattern'))
  mats = fl.entities.grep(Sketchup::Face).map { |f| f.material && f.material.name }.uniq
  ok('every face is painted with it', mats == ['InteriorPro_FloorTex_concrete'], mats)
  ok('the floor sits at the typed level', fl.get_attribute('InteriorPro', 'floor_level').to_f == -18.0,
     fl.get_attribute('InteriorPro', 'floor_level'))
  ok('the window shows Concrete again when it reopens',
     FD.shown_pattern(fl.get_attribute('InteriorPro', 'pattern'), fl.get_attribute('InteriorPro', 'floor_texture')) == 'Concrete')
end

# back to None: the concrete goes away, the floor is white again
FD.apply_selections('R2' => cfg.merge('pattern' => 'None'))
fl = FM.floors_in_model.first
ok('None takes the concrete off', fl && fl.get_attribute('InteriorPro', 'floor_texture').nil?,
   fl && fl.get_attribute('InteriorPro', 'floor_texture'))

# ---- 4. the kill switch ------------------------------------------------------
FD.send(:remove_const, :USE_CONCRETE)
FD.const_set(:USE_CONCRETE, false)
ok('kill switch: Concrete stores nothing new', FD.stored_pattern('Concrete', '') == ['None', ''], FD.stored_pattern('Concrete', ''))
ok('kill switch: the window shows None', FD.shown_pattern('None', 'concrete') == 'None')

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

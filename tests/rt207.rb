# encoding: utf-8
# rt207 - THE SHOWER'S OWN TILE (2026-09-22, his words: "פשוט תשתמש
# בקודים הקיימים ותעתיק אותם לאחד חדש").
#
# The shower window is the Floors row copied field for field; its numbers
# land on the pad under the SAME names a floor uses, and FloorPattern lays
# the shower's own grid over the shower's loop with the same code.
require './sketchup_stub'
require './tile_grid'
require './floor_manager'
require './floor_pattern'
require './shower_floor'
require './shower_floor_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

module InteriorPro
  module RoomManager
    def self.rooms_in_model; []; end
  end
end
SF = InteriorPro::ShowerFloor
SD = InteriorPro::ShowerFloorDialog
model = Sketchup.active_model
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.entities.add_face([[0, 0], [240, 0], [240, 144], [0, 144]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
sq = [[12.0, 12.0], [72.0, 12.0], [72.0, 48.0], [12.0, 48.0]]

# the window's fields are the Floors row's fields
floor_src = File.read('./floor_dialog.rb')
dlg_src = File.read('./shower_floor_dialog.rb')
%w[patternOptions textureOptions groutOptions staggerOptions groutColorOptions cardOptions].each do |fn|
  ok("the window has #{fn} like the Floors window", dlg_src.include?("function #{fn}(") && floor_src.include?("function #{fn}("))
end
ok('it has the shower fields too', dlg_src.include?('id="rise"') && dlg_src.include?('id="curb_h"') && dlg_src.include?('id="same_room"'))

cfg = SD.defaults.merge('same_room' => false, 'pattern' => 'Tile', 'unit_w' => 12.0, 'unit_l' => 12.0,
                        'grout' => 0.125, 'kind' => 'curb', 'rise' => 1.0, 'curb_h' => 4.0, 'spec' => 'Daltile 12x12')
pad = SF.build!(sq, 0.0, settings: cfg, model: model)
ok('a shower with its own tile is built', pad.respond_to?(:entities), pad)
ok('kind and rise come from the window', pad.get_attribute('InteriorPro', 'kind') == 'curb' && pad.get_attribute('InteriorPro', 'rise_in') == 1.0)
ok('its numbers are stored under the floor names', pad.get_attribute('InteriorPro', 'pattern') == 'Tile' &&
   pad.get_attribute('InteriorPro', 'unit_w') == 12.0 && pad.get_attribute('InteriorPro', 'floor_spec') == 'Daltile 12x12')
tiles = SF.tiles_of(pad.get_attribute('InteriorPro', 'id'), model)
ok('a tile layout of its own is laid on it', tiles.length == 1, tiles.length)
pts = tiles.first ? tiles.first.entities.grep(Sketchup::Edge).flat_map { |e| [e.a, e.b] } : []
ok('every joint lies inside the shower', pts.any? && pts.all? { |p| p.x >= 11.99 && p.x <= 72.01 && p.y >= 11.99 && p.y <= 48.01 })
xs = pts.map { |p| p.x.round(3) }.uniq.sort
ok('the grid is the shower\'s own: a joint about 12" in from ITS corner', xs.any? { |x| x > 23.5 && x < 24.5 }, xs.first(5))
ok('the tile top sits at the room top + the rise', pts.any? && pts.all? { |p| (p.z - 1.0).abs < 1.0e-6 }, pts.first && pts.first.z)

# the window reads a pad back the way it was set
back = SD.from_pad(pad)
ok('the window opens on the pad\'s own numbers', back['kind'] == 'curb' && back['same_room'] == false && back['unit_w'] == 12.0 && back['spec'] == 'Daltile 12x12')

# "Same as the room floor" still lays the room's tile (rt205 path), no own numbers
cfg2 = SD.defaults.merge('same_room' => true)
pad2 = SF.build!(sq, 0.0, settings: cfg2, model: model)
ok('same-as-room is remembered as such', pad2.get_attribute('InteriorPro', 'tile') == SF::SAME_AS_ROOM)
ok('and the old pad and its tiles are gone', SF.pads_in_model(model) == [pad2] && SF.tiles_of(pad.get_attribute('InteriorPro', 'id'), model).empty?)

# HIS ROOM 2: a tile layout with no slab. "Same as the room floor" measures
# the room's tile and lays it as the shower's own - tiles, not one face.
m2 = model # FloorPattern always builds into the active model
pat = m2.entities.add_group
pat.set_attribute('InteriorPro', 'type', 'floor_pattern')
pat.set_attribute('InteriorPro', 'room_id', 'room-2')
tex = m2.materials.add('InteriorPro_FloorTex_stone')
# a full row of tiles along y = 72 (the shower sits under it, at y 10..58)
[[0, 72.375], [24.125, 72.375], [48.25, 72.375], [72.375, 72.375]].each do |ox, oy|
  f = pat.entities.add_face([[ox, oy], [ox + 24, oy], [ox + 24, oy + 24], [ox, oy + 24]].map { |x, y| Geom::Point3d.new(x, y, 0.05) })
  f.material = tex
end
# and one big uncut face under the shower's spot (the layout he really had)
big = pat.entities.add_face([[0, 0], [72, 0], [72, 72], [0, 72]].map { |x, y| Geom::Point3d.new(x, y, 0.05) })
big.material = tex
got = SF.room_settings(nil, pat, m2)
ok('the room tile is measured off the layout: size', got['unit_w'] == 24.0 && got['unit_l'] == 24.0, got)
ok('joint', (got['grout'].to_f - 0.125).abs < 0.01, got['grout'])
ok('and the texture it wears', got['texture'] == 'stone', got['texture'])
loop2 = [[10.0, 10.0], [58.0, 10.0], [58.0, 58.0], [10.0, 58.0]]
pad3 = SF.build!(loop2, 0.0, settings: SD.defaults.merge('same_room' => true), model: m2)
ok('same-as-room in that room still builds', pad3.respond_to?(:entities), pad3)
ok('and it is TILES, not one face', pad3.respond_to?(:entities) && SF.tiles_of(pad3.get_attribute('InteriorPro', 'id'), m2).length == 1)
ok('with the measured numbers on the pad', pad3.respond_to?(:entities) && pad3.get_attribute('InteriorPro', 'unit_w') == 24.0)
# THE ROOM'S JOINTS RUN ON: the room's tiles start at x = 0, 24.125, 48.25 -
# so inside the shower (x 10..58) a joint must sit at 24 / 24.125 and 48.25.
t3 = SF.tiles_of(pad3.get_attribute('InteriorPro', 'id'), m2).first
xs3 = t3 ? t3.entities.grep(Sketchup::Edge).flat_map { |e| [e.a.x, e.b.x] }.map { |v| v.round(3) }.uniq.sort : []
ok('the shower joints continue the room joints', xs3.any? { |x| (x - 24.0).abs < 0.2 } && xs3.any? { |x| (x - 48.25).abs < 0.2 }, xs3)

exit($fails.zero? ? 0 : 1)

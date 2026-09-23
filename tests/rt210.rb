# encoding: utf-8
# rt210 - THE SHOWER FLOOR FOLLOWS THE WALL JOINTS (2026-09-22, his ask:
# with a curb, the shower floor's grout lines can run on from the WALLS
# round it instead of the bathroom floor - an option that only comes with
# a curb).
#
# Measured on his walls: 48x48 tiles, 1/8" grout, one joint in the middle
# of each wall. The joint is read off the tiles of each shower's own walls.
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
  def self.assign_tag(*); end unless respond_to?(:assign_tag)
end
SF = InteriorPro::ShowerFloor
SD = InteriorPro::ShowerFloorDialog
BoxPt = Struct.new(:x, :y)
Box = Struct.new(:min, :max)
model = Sketchup.active_model
P = lambda { |x, y, z| Geom::Point3d.new(x, y, z) }

# ---- pure --------------------------------------------------------------
# his east wall, measured: tile edges and niche edges along y
east = [333.043, 349.276, 349.521, 350.146, 367.396, 367.521, 384.896, 385.276, 385.521, 401.875]
js = SF.joints_from_edges(east, 0.125)
ok('his east wall has one joint, at 367.459', js.length == 1 && (js.first - 367.4585).abs < 1e-6, js)
ok('his north wall: the joint at -465.119',
   (SF.joints_from_edges([-486.612, -465.181, -465.056, -443.625], 0.125).first.to_f - -465.1185).abs < 1e-6)
ok('no grout, no joint', SF.joints_from_edges(east, 0.0).empty?)

sh = [[0.0, 0.0], [43.0, 0.0], [43.0, 69.0], [0.0, 69.0]]
an = SF.pick_anchors(sh, [nil, [10.0, 34.5, 60.0], [21.5], nil])
ok('each direction takes the joint nearest the middle of its wall', an['x'] == 21.5 && an['y'] == 34.5, an)
ok('no tile wall on a direction - nothing picked there', SF.pick_anchors(sh, [nil, [34.5], nil, nil])['x'].nil?)

# ---- in the model ------------------------------------------------------
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.entities.add_face([[-60, -10], [60, -10], [60, 80], [-60, 80]].map { |x, y| P.call(x, y, 0.0) })

def skin!(model, box, grout)
  g = model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'tile_wall')
  g.set_attribute('InteriorPro', 'pattern_grout', grout)
  b = Box.new(BoxPt.new(box[0], box[1]), BoxPt.new(box[2], box[3]))
  g.define_singleton_method(:bounds) { b }
  g
end
grout_mat = model.materials.add('InteriorPro_Grout_Light')
# north skin (runs along x), two 48" tiles cut, the joint at x = 21.5
north = skin!(model, [0.0, 69.0, 43.0, 69.6], 0.125)
[[0.0, 21.4375], [21.5625, 43.0]].each do |a, b|
  north.entities.add_face([P.call(a, 69.0, 0), P.call(b, 69.0, 0), P.call(b, 69.0, 96), P.call(a, 69.0, 96)])
end
north.entities.add_face([P.call(0, 69.3, 0), P.call(43, 69.3, 0), P.call(43, 69.3, 96), P.call(0, 69.3, 96)]).material = grout_mat
# east skin (runs along y), the joint at y = 34.5
east_skin = skin!(model, [43.0, 0.0, 43.6, 69.0], 0.125)
[[0.0, 34.4375], [34.5625, 69.0]].each do |a, b|
  east_skin.entities.add_face([P.call(43.0, a, 0), P.call(43.0, b, 0), P.call(43.0, b, 96), P.call(43.0, a, 96)])
end
# the bare walls behind (the curb test needs them)
[[43.6, -5.0, 48.6, 74.0], [-60.0, 69.6, 48.6, 74.0], [-60.0, -5.0, 48.6, 0.0]].each do |bx|
  g = model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  b = Box.new(BoxPt.new(bx[0], bx[1]), BoxPt.new(bx[2], bx[3]))
  g.define_singleton_method(:bounds) { b }
end

by_side = SF.wall_joints_by_side(sh, model)
ok('the joints are read off the wall tiles themselves',
   by_side[1].length == 1 && (by_side[1][0] - 34.5).abs < 1e-3 && by_side[2].length == 1 &&
   (by_side[2][0] - 21.5).abs < 1e-3 && by_side[0].nil? && by_side[3].nil?, by_side)

cfg = SD.defaults.merge('kind' => 'curb', 'rise' => 1.0, 'curb_h' => 4.0, 'same_room' => false,
                        'pattern' => 'Tile', 'unit_w' => 12.0, 'unit_l' => 12.0, 'grout' => 0.125,
                        'center' => true, 'wall_joints' => true)
pad = SF.build!(sh, 0.0, settings: cfg, model: model)
ok('ticked: the grid starts half a grout past the wall joint (x)',
   (pad.get_attribute('InteriorPro', 'pattern_ox').to_f - 21.5625).abs < 1e-3, pad.get_attribute('InteriorPro', 'pattern_ox'))
ok('and on y', (pad.get_attribute('InteriorPro', 'pattern_oy').to_f - 34.5625).abs < 1e-3, pad.get_attribute('InteriorPro', 'pattern_oy'))
ok('it is no longer centred', pad.get_attribute('InteriorPro', 'pattern_center') == false)
tl = SF.tiles_of(pad.get_attribute('InteriorPro', 'id'), model).first
ex = tl ? tl.entities.grep(Sketchup::Edge).flat_map { |e| [e.a.x, e.b.x] } : []
ok('a floor joint lands on the wall joint (tile edges at 21.4375 and 21.5625)',
   ex.any? { |x| (x - 21.4375).abs < 1e-3 } && ex.any? { |x| (x - 21.5625).abs < 1e-3 }, ex.uniq.sort.first(8))
ok('the window reads the tick back', SD.from_pad(pad)['wall_joints'] == true)
ok('the numbers handed in are not changed', cfg['center'] == true && cfg['ox'].to_f == 0.0, cfg.values_at('center', 'ox'))

pad2 = SF.build!(sh, 0.0, settings: cfg.merge('wall_joints' => false), model: model)
ok('not ticked: the grid is laid as before (centred, ox 0)',
   pad2.get_attribute('InteriorPro', 'pattern_center') == true && pad2.get_attribute('InteriorPro', 'pattern_ox').to_f == 0.0)
pad3 = SF.build!(sh, 0.0, settings: cfg.merge('kind' => 'flat'), model: model)
ok('flat: the option does nothing (it comes only with a curb)',
   pad3.get_attribute('InteriorPro', 'pattern_center') == true && pad3.get_attribute('InteriorPro', 'wall_joints') == false)

dsrc = File.read('./shower_floor_dialog.rb')
ok('the window has the checkbox and sends it', dsrc.include?('id="wall_joints"') && dsrc.include?("wall_joints: g('wall_joints').checked"))
ok('the curb options open only with a curb', dsrc.include?('function kindChanged()') && dsrc.include?('onchange="kindChanged()"'))
ok('the key is not in a guarded constant', SD.all_keys.include?('wall_joints') && SD.all_keys.include?('curb_room'))

SF.send(:remove_const, :USE_WALL_JOINTS)
SF.const_set(:USE_WALL_JOINTS, false)
pad4 = SF.build!(sh, 0.0, settings: cfg, model: model)
ok('USE_WALL_JOINTS off: ticked or not, the grid is laid as before',
   pad4.get_attribute('InteriorPro', 'pattern_center') == true && pad4.get_attribute('InteriorPro', 'pattern_ox').to_f == 0.0)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt209 - THE SHOWER CURB (2026-09-22, his choice "1": 4" wide, INSIDE the
# line he drew, only on the sides with no wall behind them).
#
# His shower: 43" x 69", walls (with a tile skin) on three sides, the long
# side open to the bathroom. One curb on the open side, the pad and its
# tiles inside it, and nothing where the walls are.
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

def wall!(model, type, x0, y0, x1, y1)
  g = model.entities.add_group
  g.set_attribute('InteriorPro', 'type', type)
  b = Box.new(BoxPt.new(x0, y0), BoxPt.new(x1, y1))
  g.define_singleton_method(:bounds) { b }
  g
end

# ---- pure --------------------------------------------------------------
sh = [[0.0, 0.0], [43.0, 0.0], [43.0, 69.0], [0.0, 69.0]]
boxes = [[43.0, -5.0, 48.0, 74.0],   # east wall
         [-10.0, 69.0, 48.0, 74.0],  # north wall
         [-10.0, -5.0, 48.0, 0.0]]   # south wall
w = SF.wall_sides(sh, boxes)
ok('south, east and north have a wall, west is open', w == [true, true, true, false], w)
ok('drawn the other way round, the same side is open',
   SF.wall_sides(sh.reverse, boxes) == [true, true, true, false], SF.wall_sides(sh.reverse, boxes))
# (reversed: north, east, south, then west - the open side is still the last)
ok('a wall a few inches away is NOT behind the side', SF.wall_sides(sh, [[43.8, -5.0, 48.0, 74.0]]) == [false, false, false, false])

inner = SF.inset_loop(sh, w.map { |x| x ? 0.0 : 4.0 })
ok('the floor inside the curb is 39" wide, full 69" long',
   inner.map { |x, y| [x.round(6), y.round(6)] } == [[4.0, 0.0], [43.0, 0.0], [43.0, 69.0], [4.0, 69.0]], inner)
pcs = SF.curb_pieces(sh, w)
ok('one curb piece', pcs.length == 1, pcs.length)
ok('it runs wall to wall on the open side, 4" in from his line',
   pcs.first.map { |x, y| [x.round(6), y.round(6)] }.sort == [[0.0, 0.0], [0.0, 69.0], [4.0, 0.0], [4.0, 69.0]], pcs.first)

# all four sides open: four pieces, the corners share one 45 degree cut
all4 = SF.curb_pieces(sh, [false, false, false, false])
ok('an island shower gets four curbs', all4.length == 4)
ok('two curbs meet on the diagonal (4,4)',
   all4[0].any? { |x, y| (x - 4.0).abs < 1e-6 && (y - 4.0).abs < 1e-6 } &&
   all4[3].any? { |x, y| (x - 4.0).abs < 1e-6 && (y - 4.0).abs < 1e-6 })
# an L-shaped (6 side) loop: the inset stays a proper loop
ll = [[0, 0], [60, 0], [60, 30], [30, 30], [30, 60], [0, 60]]
li = SF.inset_loop(ll, [4, 4, 4, 4, 4, 4])
ok('an L shower insets to a smaller L, every corner inside the old one',
   li.length == 6 && SF.area_sqft(li) < SF.area_sqft(ll) && li.all? { |x, y| SF.point_in?(ll, x, y) }, li)

# ---- in the model ------------------------------------------------------
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
bath_face = floor.entities.add_face([[-60, -10], [60, -10], [60, 80], [-60, 80]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
bath = model.materials.add('BathTile')
bath_face.material = bath
wall!(model, 'wall', 43.6, -5.0, 48.6, 74.0)
wall!(model, 'tile_wall', 43.0, 0.0, 43.6, 69.0)
wall!(model, 'wall', -60.0, 69.6, 48.6, 74.0)
wall!(model, 'tile_wall', 0.0, 69.0, 43.0, 69.6)
wall!(model, 'wall', -60.0, -5.0, 48.6, -0.6)
wall!(model, 'tile_wall', 0.0, -0.6, 43.0, 0.0)

cfg = SD.defaults.merge('kind' => 'curb', 'rise' => 1.0, 'curb_h' => 4.0, 'same_room' => false,
                        'pattern' => 'Tile', 'unit_w' => 12.0, 'unit_l' => 12.0, 'grout' => 0.125)
pad = SF.build!(sh, 0.0, settings: cfg, model: model)
ok('the raised shower is built', pad.respond_to?(:entities), pad)
sid = pad.get_attribute('InteriorPro', 'id')
curbs = SF.curbs_of(sid, model)
ok('one curb, in a group of its own', curbs.length == 1, curbs.length)
cf = curbs.first && curbs.first.entities.grep(Sketchup::Face).first
cpts = cf ? cf.points : []
ok('the curb stands inside his line, on the open side (x 0..4)',
   cpts.any? && cpts.all? { |p| p.x >= -1e-6 && p.x <= 4.0 + 1e-6 }, cpts.map { |p| [p.x, p.y] })
ok('it stands on the bathroom floor', cpts.any? && cpts.all? { |p| p.z.abs < 1e-6 }, cpts.map(&:z))
ok('it is pushed UP by the curb height', cf && cf.pushpulls.length == 1 &&
   (cf.pushpulls.first * (cf.normal.z > 0 ? 1 : -1) - 4.0).abs < 1e-6, cf && cf.pushpulls)
ok('the curb wears the shower\'s tile', cf && cf.material && cf.material == pad.entities.grep(Sketchup::Face).first.material)
pf = pad.entities.grep(Sketchup::Face).first
ok('the shower floor starts where the curb ends (x 4..43)',
   pf && (pf.points.map(&:x).min - 4.0).abs < 1e-6 && (pf.points.map(&:x).max - 43.0).abs < 1e-6, pf && pf.points.map(&:x))
ok('his drawn line is still what is remembered', pad.get_attribute('InteriorPro', 'poly_xy') == sh.flatten)
ok('the shower\'s area is still his whole loop (43 x 69), as before',
   (pad.get_attribute('InteriorPro', 'area_sqft').to_f - 43.0 * 69.0 / 144.0).abs < 0.01, pad.get_attribute('InteriorPro', 'area_sqft'))
tiles = SF.tiles_of(sid, model)
tp = tiles.first ? tiles.first.entities.grep(Sketchup::Edge).flat_map { |e| [e.a, e.b] } : []
ok('no tile runs under the curb', tp.any? && tp.all? { |p| p.x >= 4.0 - 1e-6 }, tp.map(&:x).min)

# the same loop again replaces the curb too
pad2 = SF.build!(sh, 0.0, settings: cfg, model: model)
ok('drawn again: the old curb is gone', SF.curbs_of(sid, model).empty? &&
   SF.curbs_of(pad2.get_attribute('InteriorPro', 'id'), model).length == 1)

# flat: no curb at all
cfg_flat = cfg.merge('kind' => 'flat')
pad3 = SF.build!(sh, 0.0, settings: cfg_flat, model: model)
ok('a flat shower gets no curb', SF.curbs_of(pad3.get_attribute('InteriorPro', 'id'), model).empty? &&
   model.entities.grep(Sketchup::Group).none? { |g| g.valid? && g.get_attribute('InteriorPro', 'type') == 'shower_curb' })

# "Curb same as the bathroom floor" (2026-09-22, his ask)
pad5 = SF.build!(sh, 0.0, settings: cfg.merge('curb_room' => true), model: model)
c5 = SF.curbs_of(pad5.get_attribute('InteriorPro', 'id'), model).first
f5 = c5 && c5.entities.grep(Sketchup::Face).first
ok('ticked: the curb wears the bathroom tile', f5 && f5.material == bath, f5 && f5.material && f5.material.name)
ok('while the shower floor keeps its own', pad5.entities.grep(Sketchup::Face).first.material != bath)
ok('the window reads the tick back', SD.from_pad(pad5)['curb_room'] == true)
ok('not ticked reads back as not ticked', SD.from_pad(pad2)['curb_room'] == false)
dsrc = File.read('./shower_floor_dialog.rb')
ok('the window has the checkbox and sends it', dsrc.include?('id="curb_room"') && dsrc.include?("curb_room: g('curb_room').checked"))

# the kill switch
SF.send(:remove_const, :USE_CURB)
SF.const_set(:USE_CURB, false)
pad4 = SF.build!(sh, 0.0, settings: cfg, model: model)
pf4 = pad4.entities.grep(Sketchup::Face).first
ok('USE_CURB off: no curb, the pad keeps his whole loop',
   SF.curbs_of(pad4.get_attribute('InteriorPro', 'id'), model).empty? && (pf4.points.map(&:x).min).abs < 1e-6)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

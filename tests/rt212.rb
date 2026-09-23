# encoding: utf-8
# rt212 - THE SQUARE DRAIN WITH A TILE INSIDE (after rt211, the grate) (2026-09-22, his spec: 5" x 5" by default, in the
# middle, size his to set; the floor stays flat). The shower tiles are laid
# with a hole for it. This one has no grate: a thin steel frame, and the
# shower's own tile in the middle, flush (his picture).
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
model = Sketchup.active_model

floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.entities.add_face([[-60, -10], [60, -10], [60, 80], [-60, 80]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
sh = [[0.0, 0.0], [40.0, 0.0], [40.0, 60.0], [0.0, 60.0]]
cfg = SD.defaults.merge('kind' => 'flat', 'same_room' => false, 'pattern' => 'Tile',
                        'unit_w' => 12.0, 'unit_l' => 12.0, 'grout' => 0.125, 'drain' => 'square_tile')
pad = SF.build!(sh, 0.0, settings: cfg, model: model)
d = SF.drains_of(pad.get_attribute('InteriorPro', 'id'), model).first
ok('a tile-insert drain is built, 5x5 in the middle',
   d && d.get_attribute('InteriorPro', 'poly_xy') == [17.5, 27.5, 22.5, 27.5, 22.5, 32.5, 17.5, 32.5], d && d.get_attribute('InteriorPro', 'poly_xy'))
fs = d ? d.entities.grep(Sketchup::Face) : []
ok('no grate holes', fs.none? { |f| f.pushpulls == [-SF::GRATE_DEPTH] })
pad_mat = pad.entities.grep(Sketchup::Face).first.material
ins = fs.find { |f| f.material == pad_mat && f.material.name != 'InteriorPro_Drain_Steel' }
ok('the middle wears the shower\'s own tile', !ins.nil?, fs.map { |f| f.material && f.material.name })
ok('inside the lip (1/8") and the channel (3/16")', ins && ins.points.map(&:x).min == 17.8125 && ins.points.map(&:x).max == 22.1875 &&
   ins.points.map(&:y).min == 27.8125 && ins.points.map(&:y).max == 32.1875, ins && ins.points.map { |q| [q.x, q.y] })
ch = fs.find { |f| f.pushpulls == [-SF::TILE_CHANNEL_DEPTH] }
ok('a steel channel round the tile, pushed down 1/2" (not a flat strip)',
   ch && ch.points.map(&:x).min == 17.625 && ch.material && ch.material.name == 'InteriorPro_Drain_Steel', ch && ch.points.map { |q| [q.x, q.y] })
top = pad.get_attribute('InteriorPro', 'floor_level').to_f + InteriorPro::FloorPattern::LINE_Z
ok('the tile is flush with the floor tiles', ins && ins.points.all? { |q| (q.z - top).abs < 1e-6 })
ok('the rest is steel', fs.count { |f| f.material && f.material.name == 'InteriorPro_Drain_Steel' } >= 1)
pf = pad.entities.grep(Sketchup::Face)
ok('the floor has its hole, like the grate', pf.length == 1)
ok('the window offers it', File.read('./shower_floor_dialog.rb').include?('<option value="square_tile">'))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

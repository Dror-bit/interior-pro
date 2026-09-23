# encoding: utf-8
# rt215 - THE LONG DRAIN BY A WALL (2026-09-23, his choices: the wall from a
# list - top / bottom / left / right seen from above - 2" off the wall,
# 3" x 24" by default, from the middle of that side, Shift moves it along).
# Two kinds: a grate, and a tile with a channel (like square_tile).
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

# ---- pure --------------------------------------------------------------
sh = [[0.0, 0.0], [40.0, 0.0], [40.0, 60.0], [0.0, 60.0]]
ok('right: 2" off the wall, 3 across, 24 along, from the middle',
   SF.wall_drain_rect(sh, 'right', 3, 24) == [[35.0, 18.0], [38.0, 18.0], [38.0, 42.0], [35.0, 42.0]], SF.wall_drain_rect(sh, 'right', 3, 24))
ok('left', SF.wall_drain_rect(sh, 'left', 3, 24) == [[2.0, 18.0], [5.0, 18.0], [5.0, 42.0], [2.0, 42.0]])
ok('top runs along x', SF.wall_drain_rect(sh, 'top', 3, 24) == [[8.0, 55.0], [32.0, 55.0], [32.0, 58.0], [8.0, 58.0]])
ok('bottom', SF.wall_drain_rect(sh, 'bottom', 3, 24) == [[8.0, 2.0], [32.0, 2.0], [32.0, 5.0], [8.0, 5.0]])
ok('shift moves it up along a side wall', SF.wall_drain_rect(sh, 'right', 3, 24, 10) == [[35.0, 28.0], [38.0, 28.0], [38.0, 52.0], [35.0, 52.0]])
ok('shift moves it right along the top wall', SF.wall_drain_rect(sh, 'top', 3, 24, -5)[0] == [3.0, 55.0])
ok('an unknown side - nothing', SF.wall_drain_rect(sh, 'north', 3, 24).nil?)

# ---- in the model (the real path: window numbers -> build!) -----------
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.entities.add_face([[-60, -10], [60, -10], [60, 80], [-60, 80]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
$holes_seen = :not_called
module InteriorPro
  module FloorPattern
    class << self
      alias_method :__rt215_build, :build_for_floor!
      def build_for_floor!(floor, **kw)
        $holes_seen = kw[:holes] if kw[:clip]
        __rt215_build(floor, **kw)
      end
    end
  end
end
cfg = SD.defaults.merge('kind' => 'flat', 'same_room' => false, 'pattern' => 'Tile',
                        'unit_w' => 12.0, 'unit_l' => 12.0, 'grout' => 0.125,
                        'drain' => 'linear', 'drain_w' => 3.0, 'drain_l' => 24.0,
                        'drain_side' => 'right', 'drain_shift' => 5.0)
pad = SF.build!(sh, 0.0, settings: cfg, model: model)
sid = pad.get_attribute('InteriorPro', 'id')
d = SF.drains_of(sid, model).first
want = [35.0, 23.0, 38.0, 23.0, 38.0, 47.0, 35.0, 47.0]
ok('the long grate drain is built by the right wall, shifted 5" up', d && d.get_attribute('InteriorPro', 'poly_xy') == want, d && d.get_attribute('InteriorPro', 'poly_xy'))
ok('the tiles are laid with its hole', $holes_seen.is_a?(Array) && $holes_seen.first.flatten == want, $holes_seen)
pushed = d ? d.entities.grep(Sketchup::Face).select { |f| f.pushpulls == [-SF::GRATE_DEPTH] } : []
ok('it has grate holes', pushed.length == SF.grate_holes(3.0, 24.0).length && pushed.length > 10, pushed.length)
ok('the pad remembers the wall and the shift', pad.get_attribute('InteriorPro', 'drain_side') == 'right' && pad.get_attribute('InteriorPro', 'drain_shift') == 5.0)
back = SD.from_pad(pad)
ok('the edit window gets them back', back['drain'] == 'linear' && back['drain_side'] == 'right' && back['drain_shift'] == 5.0 && back['drain_l'] == 24.0, back.select { |k, _| k.start_with?('drain') })

cfg2 = cfg.merge('drain' => 'linear_tile', 'drain_side' => 'top', 'drain_shift' => 0.0)
sh2 = [[100.0, 0.0], [140.0, 0.0], [140.0, 60.0], [100.0, 60.0]]
floor.entities.add_face([[90, -10], [150, -10], [150, 80], [90, 80]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
pad2 = SF.build!(sh2, 0.0, settings: cfg2, model: model)
d2 = SF.drains_of(pad2.get_attribute('InteriorPro', 'id'), model).first
ok('the tile kind by the top wall', d2 && d2.get_attribute('InteriorPro', 'poly_xy') == [108.0, 55.0, 132.0, 55.0, 132.0, 58.0, 108.0, 58.0], d2 && d2.get_attribute('InteriorPro', 'poly_xy'))
fs = d2 ? d2.entities.grep(Sketchup::Face) : []
ok('no grate holes on the tile kind', fs.none? { |f| f.pushpulls == [-SF::GRATE_DEPTH] })
ok('a shallow channel round the tile', fs.any? { |f| f.pushpulls == [-SF::TILE_CHANNEL_DEPTH] })
pm = pad2.entities.grep(Sketchup::Face).first.material
ok('the middle wears the shower tile', fs.any? { |f| f.material == pm && f.material.name != 'InteriorPro_Drain_Steel' })

cfg3 = cfg.merge('drain_shift' => 30.0)
sh3 = [[-50.0, 0.0], [-10.0, 0.0], [-10.0, 60.0], [-50.0, 60.0]]
pad3 = SF.build!(sh3, 0.0, settings: cfg3, model: model)
ok('shifted off the end - not built, and the floor is still built', pad3 && SF.drains_of(pad3.get_attribute('InteriorPro', 'id'), model).empty?)

src = File.read('./shower_floor_dialog.rb')
ok('the window offers both long drains', src.include?('<option value="linear">') && src.include?('<option value="linear_tile">'))
ok('the window has the wall list and Shift', src.include?('id="drain_side"') && src.include?('id="drain_shift"'))
ok('the new keys go through OK', SD.all_keys.include?('drain_side') && SD.all_keys.include?('drain_shift'))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

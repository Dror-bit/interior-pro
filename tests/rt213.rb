# encoding: utf-8
# rt213 - THE ROUND DRAIN (his picture: a round grate with square holes) (2026-09-22, his spec: 5" x 5" by default, in the
# middle, size his to set; the floor stays flat). The shower tiles are laid
# with a hole for it - here a round one, W across, 5" by default.
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
c = SF.drain_circle(20.0, 30.0, 5.0)
ok('a circle of 24 sides', c.length == 24)
ok('every corner 2.5" from the middle', c.all? { |x, y| (Math.hypot(x - 20.0, y - 30.0) - 2.5).abs < 1e-9 })
rh = SF.round_grate_holes(5.0)
ok('the round grate keeps only holes inside its rim', rh.any? && rh.length < SF.grate_holes(5.0, 5.0).length, [rh.length, SF.grate_holes(5.0, 5.0).length])
ok('no hole crosses the rim', rh.all? { |a, b, c2, d| [[a, b], [c2, b], [c2, d], [a, d]].all? { |x, y| Math.hypot(x - 2.5, y - 2.5) <= 2.5 - SF::GRATE_FRAME + 1e-9 } })

# ---- in the model ------------------------------------------------------
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
      alias_method :__rt213_build, :build_for_floor!
      def build_for_floor!(floor, **kw)
        $holes_seen = kw[:holes] if kw[:clip]
        __rt213_build(floor, **kw)
      end
    end
  end
end
sh = [[0.0, 0.0], [40.0, 0.0], [40.0, 60.0], [0.0, 60.0]]
cfg = SD.defaults.merge('kind' => 'flat', 'same_room' => false, 'pattern' => 'Tile',
                        'unit_w' => 12.0, 'unit_l' => 12.0, 'grout' => 0.125, 'drain' => 'round')
pad = SF.build!(sh, 0.0, settings: cfg, model: model)
d = SF.drains_of(pad.get_attribute('InteriorPro', 'id'), model).first
pts = d ? d.get_attribute('InteriorPro', 'poly_xy').each_slice(2).to_a : []
ok('a round drain, 5" across, in the middle', pts.length == 24 && pts.all? { |x, y| (Math.hypot(x - 20.0, y - 30.0) - 2.5).abs < 1e-6 }, pts.length)
ok('the tiles get the same round hole', $holes_seen.is_a?(Array) && $holes_seen.first == pts, $holes_seen.class)
fs = d ? d.entities.grep(Sketchup::Face) : []
ok('its grate holes are pushed down', fs.count { |f| f.pushpulls == [-SF::GRATE_DEPTH] } == rh.length)
ok('the floor is built with the hole', pad.entities.grep(Sketchup::Face).length == 1)
pad2 = SF.build!(sh, 0.0, settings: cfg.merge('drain_w' => 4.25), model: model)
d2 = SF.drains_of(pad2.get_attribute('InteriorPro', 'id'), model).first
ok('his size: 4 1/4" across', d2 && d2.get_attribute('InteriorPro', 'poly_xy').each_slice(2).all? { |x, y| (Math.hypot(x - 20.0, y - 30.0) - 2.125).abs < 1e-6 })
ok('the window offers it', File.read('./shower_floor_dialog.rb').include?('<option value="round">'))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt211 - THE SQUARE DRAIN (2026-09-22, his spec: 5" x 5" by default, in the
# middle, size his to set; the floor stays flat). The shower tiles are laid
# with a hole for it and the drain sits in the hole, flush with the tile top.
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
ok('the middle of a rectangle', SF.area_centroid([[0, 0], [40, 0], [40, 60], [0, 60]]) == [20.0, 30.0])
l = [[0, 0], [60, 0], [60, 20], [20, 20], [20, 60], [0, 60]]
c = SF.area_centroid(l)
# 60x20 (middle 30,10) + 20x40 (middle 10,40): by area 22,22 (corners alone give 26.7,26.7)
ok('an L: the middle by area, not by corners', (c[0] - 22.0).abs < 1e-6 && (c[1] - 22.0).abs < 1e-6, c)
ok('the drain outline, 5x5 round its middle',
   SF.drain_rect(20, 30, 5, 5) == [[17.5, 27.5], [22.5, 27.5], [22.5, 32.5], [17.5, 32.5]])
h = SF.grate_holes(5.0, 5.0)
ok('a 5" grate has 7 x 7 holes', h.length == 49, h.length)
ok('every hole stays inside the rim', h.all? { |a, b, c2, d| a >= 0.375 - 1e-9 && b >= 0.375 - 1e-9 && c2 <= 4.625 + 1e-9 && d <= 4.625 + 1e-9 })
ok('the holes are centred', (h.map { |a, _b, _c, _d| a }.min - (5.0 - h.map { |_a, _b, c2, _d| c2 }.max)).abs < 1e-9)
ok('too small for a hole - none', SF.grate_holes(0.5, 0.5).empty?)

# ---- in the model ------------------------------------------------------
floor = model.entities.add_group
floor.set_attribute('InteriorPro', 'type', 'floor')
floor.set_attribute('InteriorPro', 'id', 'floor-1')
floor.set_attribute('InteriorPro', 'room_id', 'room-1')
floor.set_attribute('InteriorPro', 'floor_level', 0.0)
floor.set_attribute('InteriorPro', 'thickness_in', 0.75)
floor.entities.add_face([[-60, -10], [60, -10], [60, 80], [-60, 80]].map { |x, y| Geom::Point3d.new(x, y, 0.0) })
sh = [[0.0, 0.0], [40.0, 0.0], [40.0, 60.0], [0.0, 60.0]]
cfg = SD.defaults.merge('kind' => 'flat', 'same_room' => false, 'pattern' => 'Tile',
                        'unit_w' => 12.0, 'unit_l' => 12.0, 'grout' => 0.125, 'drain' => 'square')
# spy: what the tile layout is asked to leave out
$holes_seen = :not_called
module InteriorPro
  module FloorPattern
    class << self
      alias_method :__rt211_build, :build_for_floor!
      def build_for_floor!(floor, **kw)
        $holes_seen = kw[:holes] if kw[:clip]
        __rt211_build(floor, **kw)
      end
    end
  end
end
pad = SF.build!(sh, 0.0, settings: cfg, model: model)
sid = pad.get_attribute('InteriorPro', 'id')
dr = SF.drains_of(sid, model)
ok('one drain, in a group of its own', dr.length == 1, dr.length)
d = dr.first
ok('5x5 in the middle of the shower',
   d && d.get_attribute('InteriorPro', 'poly_xy') == [17.5, 27.5, 22.5, 27.5, 22.5, 32.5, 17.5, 32.5], d && d.get_attribute('InteriorPro', 'poly_xy'))
top = pad.get_attribute('InteriorPro', 'floor_level').to_f + InteriorPro::FloorPattern::LINE_Z
ok('flush with the tile top', d && (d.get_attribute('InteriorPro', 'top_z').to_f - top).abs < 1e-6, [d && d.get_attribute('InteriorPro', 'top_z'), top])
pushed = d ? d.entities.grep(Sketchup::Face).select { |f| f.pushpulls == [-SF::GRATE_DEPTH] } : []
ok('its 49 grate holes are pushed down', pushed.length == 49, pushed.length)
# like a window in a wall: the drain fills its hole down to the pad's bottom
th = pad.get_attribute('InteriorPro', 'thickness_in').to_f
body = d ? d.entities.grep(Sketchup::Face).find { |f| f.pushpulls.any? && f.pushpulls != [-SF::GRATE_DEPTH] } : nil
ok('the drain body goes down through the whole floor', body && (body.pushpulls.first + (th + InteriorPro::FloorPattern::LINE_Z)).abs < 1e-6,
   [body && body.pushpulls, th])
pf = pad.entities.grep(Sketchup::Face)
ok('the pad is built with a hole: the drain square was drawn and taken away',
   pf.length == 1 && pf.none? { |f| f.points.map(&:x).min == 17.5 && f.points.map(&:x).max == 22.5 }, pf.map { |f| f.points.map { |q| [q.x, q.y] } })
ok('it is steel', d && d.entities.grep(Sketchup::Face).all? { |f| f.material && f.material.name == 'InteriorPro_Drain_Steel' })
ok('the shower tiles are laid with a hole exactly where the drain is (cut by pieces_minus_holes, rt203)',
   $holes_seen == [[[17.5, 27.5], [22.5, 27.5], [22.5, 32.5], [17.5, 32.5]]], $holes_seen)
ok('the pad remembers the drain', pad.get_attribute('InteriorPro', 'drain') == 'square')
ok('the window reads it back', SD.from_pad(pad)['drain'] == 'square' && SD.from_pad(pad)['drain_w'] == 5.0)

# his own size
pad2 = SF.build!(sh, 0.0, settings: cfg.merge('drain_w' => 6.0, 'drain_l' => 4.0), model: model)
d2 = SF.drains_of(pad2.get_attribute('InteriorPro', 'id'), model).first
ok('his size: 6 x 4', d2 && d2.get_attribute('InteriorPro', 'poly_xy') == [17.0, 28.0, 23.0, 28.0, 23.0, 32.0, 17.0, 32.0])
ok('drawn again: the old drain is gone', SF.drains_of(sid, model).empty?)

# none: no drain, tiles whole
pad3 = SF.build!(sh, 0.0, settings: cfg.merge('drain' => 'none'), model: model)
ok('None: the tiles get no hole', $holes_seen.nil?, $holes_seen)
pf3 = pad3.entities.grep(Sketchup::Face)
ok('None: the pad is whole', pf3.length == 1 && pf3.first.points.length == 4)
ok('None: no drain', SF.drains_of(pad3.get_attribute('InteriorPro', 'id'), model).empty? &&
   model.entities.grep(Sketchup::Group).none? { |g| g.valid? && g.get_attribute('InteriorPro', 'type') == 'shower_drain' })

dsrc = File.read('./shower_floor_dialog.rb')
ok('the window has the drain row and sends it', dsrc.include?('id="drain"') && dsrc.include?("drain: g('drain').value") &&
   dsrc.include?("drain_w: parseFloat(g('drain_w').value)"))
ok('the keys are not in a guarded constant', (%w[drain drain_w drain_l] - SD.all_keys).empty?)

SF.send(:remove_const, :USE_DRAIN)
SF.const_set(:USE_DRAIN, false)
pad4 = SF.build!(sh, 0.0, settings: cfg, model: model)
ok('USE_DRAIN off: no drain', SF.drains_of(pad4.get_attribute('InteriorPro', 'id'), model).empty?)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

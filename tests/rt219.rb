# encoding: utf-8
# rt219 - THE FLOOR STOPS AT THE WALL TILE (2026-09-23, his words: "רצפת
# השירותים ממשיכה מתחת לאריחי הקירות... הרצפה יכולה להיגמר בקו שבו רצפת
# האריחים נגמרת"). Every tiled wall area standing on the floor leaves its
# strip - wall face to tile face - out of the floor tiles. Pinned on the
# maths, then on the real path: build_for_floor! hands the strips to the
# tile faces, and the kill switch takes them away.
require './sketchup_stub'
require './tile_grid'
require './tile_wall'
require './floor_manager'
require './floor_pattern'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
FP = InteriorPro::FloorPattern
TW = InteriorPro::TileWall

# A wall along x from (0,0) to (100,0), its face on y = 0 looking +y
# (into the room), floor at z 0.
FR = { ox: 0.0, oy: 0.0, ux: 1.0, uy: 0.0, nx: 0.0, ny: 1.0, len: 100.0, floor_z: 0.0, side: 'a' }
fp = FP.wall_tile_footprint(FR, 10.0, 40.0, 0.625)
ok('the strip: along the wall, from behind the face out to the tile face',
   fp == [[10.0, -0.5], [50.0, -0.5], [50.0, 0.625], [10.0, 0.625]], fp)
ok('inside a room', FP.inside_poly?([[0, 0], [100, 0], [100, 80], [0, 80]], 30.0, 0.3))
ok('not inside', !FP.inside_poly?([[0, 0], [100, 0], [100, 80], [0, 80]], 30.0, -0.3))

# ---- which areas count ---------------------------------------------------
def area(id, z0, h, dp, u0 = 10.0, w = 40.0)
  g = Sketchup::Group.new
  { 'type' => 'tile_wall', 'id' => id, 'wall_id' => 'W', 'side' => 'a', 'u0' => u0, 'z0' => z0,
    'area_w' => w, 'area_h' => h, 'built_u0' => u0, 'built_w' => w, 'tile_depth' => dp }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
$areas = [area('ON', 0.0, 96.0, 0.625), area('HIGH', 40.0, 20.0, 0.625), area('FLAT', 0.0, 96.0, 0.0)]
class << TW
  def areas_in_model(_m = nil); $areas; end
  def wall_by_id(_id, _m = nil); :wall; end
  def frame_for(_w, _s); FR; end
end
room = [[0.0, 0.0], [100.0, 0.0], [100.0, 80.0], [0.0, 80.0]]
hs = FP.wall_tile_holes(room, 0.05)
ok('only the area standing on the floor, with real thickness, counts', hs.length == 1 && hs[0] == fp, hs)
ok('a room on the other side of the wall does not get it', FP.wall_tile_holes([[0.0, 0.0], [100.0, 0.0], [100.0, -80.0], [0.0, -80.0]], 0.05).empty?)

# ---- the real path -----------------------------------------------------------
$room = Sketchup::Group.new
$room.set_attribute('InteriorPro', 'id', 'R1')
$room.set_attribute('InteriorPro', 'boundary_xy', room.flatten)
module InteriorPro
  module RoomManager
    def self.rooms_in_model; [$room]; end
  end
  module MaterialLibraryDialog
    def self.material_from_card(model, _c); model.materials.add('Card_Tile'); end
  end
  def self.assign_tag(*); end unless respond_to?(:assign_tag)
end
module InteriorPro
  module FloorPattern
    class << self
      def floor_card(_f); { 'name' => 'Tile', 'tile_w_inches' => 12.0, 'tile_l_inches' => 12.0 }; end
      def build_grout_backing!(*); end # the stub face has no edges
      alias_method :__rt219_emit, :emit_plank_faces!
      def emit_plank_faces!(ge, planks, poly, mat, z = LINE_Z, holes = [])
        $emit_holes = holes
        __rt219_emit(ge, planks, poly, mat, z, holes)
      end
    end
  end
end
floor = Sketchup::Group.new
{ 'type' => 'floor', 'id' => 'F1', 'room_id' => 'R1', 'pattern' => 'Tile', 'unit_w' => 12.0, 'unit_l' => 12.0,
  'pattern_grout' => 0.125, 'floor_level' => 0.0 }.each { |k, v| floor.set_attribute('InteriorPro', k, v) }
$emit_holes = nil
FP.build_for_floor!(floor)
ok('the floor tiles are laid with the wall tile strip left out', $emit_holes.is_a?(Array) && $emit_holes.include?(fp), $emit_holes)
FP.send(:remove_const, :USE_WALL_TILE_STOP)
FP.const_set(:USE_WALL_TILE_STOP, false)
$emit_holes = nil
FP.build_for_floor!(floor)
ok('kill switch: the floor runs under the wall tile again', $emit_holes.is_a?(Array) && !$emit_holes.include?(fp), $emit_holes)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

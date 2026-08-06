# encoding: utf-8
# rt13 — per-level rooms (2026-08-04): each level is detected on its own,
# a level-2 room keeps its own identity right above a level-1 room, its
# label sits at the level base, and its floor defaults to the level base.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'

module Sketchup
  class Face
    attr_accessor :pts, :pulled, :material, :back_material
    def normal; Geom::Vector3d.new(0, 0, 1); end
    def pushpull(d); @pulled = d; end
  end
  class Entities
    def add_face(pts)
      f = Face.new
      f.pts = pts
      @list << f
      f
    end
  end
  class Texture
    attr_accessor :size
  end
  class Material
    def texture; @texture ||= Texture.new; end
    def texture=(_path); @texture = Texture.new; end
  end
end

require './room_manager'
require './level_manager'
require './floor_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
RM = InteriorPro::RoomManager
FM = InteriorPro::FloorManager

def make_wall(m, id, s, e, level = nil, cat = 'exterior')
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0]); w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0]);   w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', 96.0)
  w.set_attribute('InteriorPro', 'base_z', level && level > 1 ? 106.0 : 0.0)
  w.set_attribute('InteriorPro', 'wall_category', cat)
  w.set_attribute('InteriorPro', 'level', level) unless level.nil?
  w
end

def square(m, prefix, level, size)
  make_wall(m, "#{prefix}1", [0, 0], [size, 0], level)
  make_wall(m, "#{prefix}2", [size, 0], [size, size], level)
  make_wall(m, "#{prefix}3", [size, size], [0, size], level)
  make_wall(m, "#{prefix}4", [0, size], [0, 0], level)
end

# ---- detection is per level ---------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
square(m, 'a', nil, 240)          # level 1 (legacy walls, no level attr)
square(m, 'b', 2, 240)            # level 2, SAME footprint

r1 = RM.detect_rooms!(verbose: false, level: 1)
r2 = RM.detect_rooms!(verbose: false, level: 2)
ok('level 1 detects its room', r1.length == 1, r1.length)
ok('level 2 detects its room', r2.length == 1, r2.length)
ok('detected rooms carry their level', r1.first[:level] == 1 && r2.first[:level] == 2,
   [r1.first[:level], r2.first[:level]])

# ---- sync: one room entity per level, stacked footprints stay apart -----
RM.sync_rooms!
rooms = RM.rooms_in_model
ok('sync creates 2 rooms', rooms.length == 2, rooms.length)
lv1 = rooms.find { |g| RM.room_level(g) == 1 }
lv2 = rooms.find { |g| RM.room_level(g) == 2 }
ok('one room per level', !lv1.nil? && !lv2.nil?, rooms.map { |g| RM.room_level(g) })
ok('level-1 label sits near z=0', lv1.transformation.origin.z < 1.0, lv1.transformation.origin.z)
ok('level-2 label sits at the level base', (lv2.transformation.origin.z - 106.25).abs < 0.01,
   lv2.transformation.origin.z)

# re-sync: the level-2 room must keep its id (not steal the level-1 match)
id1 = lv1.get_attribute('InteriorPro', 'id')
id2 = lv2.get_attribute('InteriorPro', 'id')
ok('room ids differ', id1 != id2)
RM.sync_rooms!
rooms = RM.rooms_in_model
ok('re-sync keeps 2 rooms', rooms.length == 2, rooms.length)
ids = rooms.map { |g| g.get_attribute('InteriorPro', 'id') }.sort
ok('re-sync keeps both ids', ids == [id1, id2].sort, ids)

# ---- floors: a level-2 room floors at the level base --------------------
f1 = FM.build_floor_for_room!(lv1)
f2 = FM.build_floor_for_room!(lv2)
ok('level-1 floor built at 0', f1 && f1.get_attribute('InteriorPro', 'floor_level').to_f == 0.0,
   f1 && f1.get_attribute('InteriorPro', 'floor_level'))
ok('level-2 floor defaults to 106', f2 && f2.get_attribute('InteriorPro', 'floor_level').to_f == 106.0,
   f2 && f2.get_attribute('InteriorPro', 'floor_level'))
ok('level-2 floor carries level=2', f2 && f2.get_attribute('InteriorPro', 'level') == 2,
   f2 && f2.get_attribute('InteriorPro', 'level'))
z_top = f2 && f2.entities.grep(Sketchup::Face).first
ok('level-2 floor face sits at z=106', z_top && (z_top.pts.first.z - 106.0).abs < 0.01,
   z_top && z_top.pts.first.z)
# an explicit floor_level always wins over the default
f2b = FM.build_floor_for_room!(lv2, level: 100.0)
ok('explicit floor level wins', f2b && f2b.get_attribute('InteriorPro', 'floor_level').to_f == 100.0,
   f2b && f2b.get_attribute('InteriorPro', 'floor_level'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

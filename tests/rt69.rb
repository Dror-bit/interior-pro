# encoding: utf-8
# rt69 — the floor of an upper storey (2026-08-17).
#
# THE BUG THIS PINS: floor_dialog reads floor_level and, when the floor has
# none, hands the user's row a 0. It then sends that 0 back on every Apply.
# build_floor_for_room! stored the 0 as an absolute height, so a level-2
# floor was nailed to z=0 - and the "a level-2 room floors at 106" default
# could never run again, because it only ran when NOTHING was stored.
# Measured on the user's model: level-2 floor top at z=0 instead of 106.
#
# THE RULE NOW: the `level:` argument is an OFFSET from the room's own
# storey. What gets STORED stays an absolute height, because CeilingManager,
# build_patch!, FloorPattern and FoundationManager all read it as one.
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
LM = InteriorPro::LevelManager

def wall(m, id, s, e, level)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0]); w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0]);   w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', 96.0)
  w.set_attribute('InteriorPro', 'base_z', level > 1 ? 106.0 : 0.0)
  w.set_attribute('InteriorPro', 'wall_category', 'exterior')
  w.set_attribute('InteriorPro', 'level', level)
  w
end

def square(m, prefix, level, size = 240)
  wall(m, "#{prefix}1", [0, 0], [size, 0], level)
  wall(m, "#{prefix}2", [size, 0], [size, size], level)
  wall(m, "#{prefix}3", [size, size], [0, size], level)
  wall(m, "#{prefix}4", [0, size], [0, 0], level)
end

def top_z(f)
  fc = f && f.entities.grep(Sketchup::Face).first
  fc && fc.pts.first.z
end

Sketchup.reset_model!
m = Sketchup.active_model
square(m, 'a', 1)
square(m, 'b', 2)
RM.sync_rooms!
rooms = RM.rooms_in_model
lv1 = rooms.find { |g| RM.room_level(g) == 1 }
lv2 = rooms.find { |g| RM.room_level(g) == 2 }
ok('setup: a room on each level', !lv1.nil? && !lv2.nil?, rooms.length)
ok('setup: the storey base is 106', LM.level_base(2).to_f == 106.0, LM.level_base(2))

# ---- level_base_for -------------------------------------------------------
ok('level_base_for(1) is 0', FM.level_base_for(1) == 0.0, FM.level_base_for(1))
ok('level_base_for(2) is 106', FM.level_base_for(2) == 106.0, FM.level_base_for(2))
ok('level_base_for(nil) is 0', FM.level_base_for(nil) == 0.0, FM.level_base_for(nil))
ok('level_base_for("2") is 106', FM.level_base_for('2') == 106.0, FM.level_base_for('2'))

# ---- THE BUG: the dialog's 0 must not drag the floor to the ground --------
f2 = FM.build_floor_for_room!(lv2, nil, level: 0.0)
ok('a level-2 floor built with level:0 stores 106',
   f2 && f2.get_attribute('InteriorPro', 'floor_level').to_f == 106.0,
   f2 && f2.get_attribute('InteriorPro', 'floor_level'))
ok('a level-2 floor built with level:0 SITS at 106', (top_z(f2).to_f - 106.0).abs < 0.01, top_z(f2))

# and again, the way Apply does it - the second trip must not move it
f2 = FM.build_floor_for_room!(lv2, nil, level: 0.0)
f2 = FM.build_floor_for_room!(lv2, nil, level: 0.0)
ok('applying three times leaves it at 106', (top_z(f2).to_f - 106.0).abs < 0.01, top_z(f2))

# ---- level 1 is untouched -------------------------------------------------
f1 = FM.build_floor_for_room!(lv1, nil, level: 0.0)
ok('a level-1 floor with level:0 still stores 0',
   f1 && f1.get_attribute('InteriorPro', 'floor_level').to_f == 0.0,
   f1 && f1.get_attribute('InteriorPro', 'floor_level'))
ok('a level-1 floor with level:0 still sits at 0', top_z(f1).to_f.abs < 0.01, top_z(f1))

# the garage case the offset was invented for, on level 1: unchanged
f1b = FM.build_floor_for_room!(lv1, nil, level: -18.0)
ok('level-1 garage at -18 still lands on -18',
   f1b && f1b.get_attribute('InteriorPro', 'floor_level').to_f == -18.0,
   f1b && f1b.get_attribute('InteriorPro', 'floor_level'))

# ---- the offset really is an offset --------------------------------------
f2c = FM.build_floor_for_room!(lv2, nil, level: -18.0)
ok('level-2 dropped 18 lands on 88',
   f2c && f2c.get_attribute('InteriorPro', 'floor_level').to_f == 88.0,
   f2c && f2c.get_attribute('InteriorPro', 'floor_level'))
ok('level-2 dropped 18 SITS at 88', (top_z(f2c).to_f - 88.0).abs < 0.01, top_z(f2c))

f2d = FM.build_floor_for_room!(lv2, nil, level: 12.0)
ok('level-2 raised 12 lands on 118',
   f2d && f2d.get_attribute('InteriorPro', 'floor_level').to_f == 118.0,
   f2d && f2d.get_attribute('InteriorPro', 'floor_level'))

# ---- no level: at all keeps whatever is already stored -------------------
kept = FM.build_floor_for_room!(lv2)
ok('rebuilding without level: keeps the stored height',
   kept && kept.get_attribute('InteriorPro', 'floor_level').to_f == 118.0,
   kept && kept.get_attribute('InteriorPro', 'floor_level'))

# a brand-new level-2 floor, nothing stored and no level: given
FM.remove_floor_for_room!(lv2.get_attribute('InteriorPro', 'id'))
fresh = FM.build_floor_for_room!(lv2)
ok('a brand-new level-2 floor defaults to 106',
   fresh && fresh.get_attribute('InteriorPro', 'floor_level').to_f == 106.0,
   fresh && fresh.get_attribute('InteriorPro', 'floor_level'))

# ---- refresh! (what room sync calls) must not move it either -------------
FM.refresh!
again = FM.floors_in_model.find { |f| f.get_attribute('InteriorPro', 'room_id') == lv2.get_attribute('InteriorPro', 'id') }
ok('refresh! leaves the level-2 floor at 106',
   again && (top_z(again).to_f - 106.0).abs < 0.01, again && top_z(again))

# ---- what the dialog SHOWS is the offset, not the absolute ---------------
# floor_dialog.rb does: stored - level_base_for(room level)
shown = again.get_attribute('InteriorPro', 'floor_level').to_f - FM.level_base_for(2)
ok('the dialog shows 0 for a normal level-2 floor', shown == 0.0, shown)

# ---- the stored value stays ABSOLUTE for everyone else -------------------
# CeilingManager reads it straight as a height; if it ever became an offset
# the ceiling of a level-2 room would drop to the ground.
ok('stored floor_level is still an absolute height',
   again.get_attribute('InteriorPro', 'floor_level').to_f == 106.0,
   again.get_attribute('InteriorPro', 'floor_level'))

# ---- healing a model that ALREADY caught the bug -------------------------
# This is the user's model on 2026-08-17: a level-2 floor with floor_level
# stored as 0. Without the heal the window would offer -106 and Apply would
# write the 0 straight back, so the fix would never reach an existing house.
bad = FM.floors_in_model.find { |f| f.get_attribute('InteriorPro', 'room_id') == lv2.get_attribute('InteriorPro', 'id') }
bad.set_attribute('InteriorPro', 'floor_level', 0.0)
ok('setup: a level-2 floor stuck at 0', bad.get_attribute('InteriorPro', 'floor_level').to_f == 0.0)
ok('a level-2 floor stuck at 0 reads as 106', FM.stored_floor_level(bad, 2) == 106.0,
   FM.stored_floor_level(bad, 2))
ok('the window offers 0, not -106',
   (FM.stored_floor_level(bad, 2) - FM.level_base_for(2)) == 0.0,
   FM.stored_floor_level(bad, 2) - FM.level_base_for(2))
healed = FM.build_floor_for_room!(lv2)
ok('rebuilding lifts it back to 106', (top_z(healed).to_f - 106.0).abs < 0.01, top_z(healed))

# a level-1 floor at 0 is perfectly normal and must NOT be touched
lvl1_floor = FM.build_floor_for_room!(lv1, nil, level: 0.0)
ok('a level-1 floor at 0 is left alone', FM.stored_floor_level(lvl1_floor, 1) == 0.0,
   FM.stored_floor_level(lvl1_floor, 1))

# a real choice on level 2 survives - only an exact 0 is treated as unset
chosen = FM.build_floor_for_room!(lv2, nil, level: -18.0)
ok('a real level-2 choice is not healed away', FM.stored_floor_level(chosen, 2) == 88.0,
   FM.stored_floor_level(chosen, 2))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

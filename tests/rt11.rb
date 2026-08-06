# encoding: utf-8
# rt11 — the 2D editor knows about levels: the canvas payload shows only
# the active level, room labels/live areas only on level 1.
require './sketchup_stub'

# Level placement needs set_wall_base! (records the lift, like rt10).
module InteriorPro
  module WallTool
    def self.set_wall_base!(wall, z)
      wall.set_attribute('InteriorPro', 'base_z', z.to_f)
      true
    end
  end
end

require './level_manager'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PE = InteriorPro::PlanEditor
LM = InteriorPro::LevelManager

def make_wall(m, id, level)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', 0.0)
  w.set_attribute('InteriorPro', 'start_y', 0.0)
  w.set_attribute('InteriorPro', 'end_x', 100.0)
  w.set_attribute('InteriorPro', 'end_y', 0.0)
  w.set_attribute('InteriorPro', 'thickness', 4.5)
  w.set_attribute('InteriorPro', 'height', 96.0)
  w.set_attribute('InteriorPro', 'level', level) unless level.nil?
  w
end

# ---- the canvas shows ONLY the active level -----------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'a1', nil)   # legacy wall without a level attr = level 1
make_wall(m, 'a2', 1)
make_wall(m, 'b1', 2)

LM.set_active_level!(1)
ids = PE.send(:walls_payload).map { |h| h['id'] }.sort
ok('level 1 sees its walls (incl. legacy)', ids == %w[a1 a2], ids)

LM.set_active_level!(2)
ids = PE.send(:walls_payload).map { |h| h['id'] }
ok('level 2 sees only its wall', ids == %w[b1], ids)

# ---- room labels & live areas exist only on level 1 (for now) -----------
r = m.entities.add_group
r.set_attribute('InteriorPro', 'type', 'room')
r.set_attribute('InteriorPro', 'id', 'r1')
r.set_attribute('InteriorPro', 'name', 'Room 1')
r.set_attribute('InteriorPro', 'boundary_xy', [0, 0, 100, 0, 100, 100, 0, 100])

LM.set_active_level!(1)
ok('room labels show on level 1', PE.send(:rooms_payload).length == 1,
   PE.send(:rooms_payload))
LM.set_active_level!(2)
ok('room labels hidden on level 2', PE.send(:rooms_payload).empty?,
   PE.send(:rooms_payload))
ok('live areas off above level 1', PE.send(:preview_rooms, [{ 'sx' => 0, 'sy' => 0, 'ex' => 100, 'ey' => 0, 'th' => 4.5 }]).empty?)

# ---- the ghost underlay: level below, only when above level 1 ----------
LM.set_active_level!(1)
ok('no ghosts on level 1', PE.send(:ghost_walls_payload).empty?,
   PE.send(:ghost_walls_payload))
LM.set_active_level!(2)
gids = PE.send(:ghost_walls_payload).map { |h| h['id'] }.sort
ok('level-2 ghosts are the level-1 walls', gids == %w[a1 a2], gids)

# ---- ceilings of the level below build automatically --------------------
# (rt8-style stub enrichment so CeilingManager can build a face)
module Sketchup
  class Face
    attr_accessor :pts, :pulled, :material, :back_material
    def normal; Geom::Vector3d.new(0, 0, 1); end
    def pushpull(d); @pulled = d; end
  end
  class Entities
    def add_face(pts); f = Face.new; f.pts = pts; @list << f; f; end
  end
end
require './ceiling_manager'

def ceilings
  Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
    g.valid? && g.get_attribute('InteriorPro', 'type') == 'ceiling'
  end
end

LM.set_active_level!(2)
w9 = make_wall(m, 'c-w1', nil)
LM.place_wall_on_active_level!(w9)
ok('a level-2 wall auto-builds the ceiling below', ceilings.length == 1, ceilings.length)

w10 = make_wall(m, 'c-w2', nil)
LM.place_wall_on_active_level!(w10)
ok('an existing ceiling is not duplicated', ceilings.length == 1, ceilings.length)

InteriorPro::CeilingManager.remove_ceiling_for_room!('r1')
w11 = make_wall(m, 'c-w3', nil)
LM.place_wall_on_active_level!(w11)
ok('a removed ceiling comes back with the next level-2 wall', ceilings.length == 1, ceilings.length)

LM.set_active_level!(1)
w12 = make_wall(m, 'c-w4', nil)
InteriorPro::CeilingManager.remove_ceiling_for_room!('r1')
LM.place_wall_on_active_level!(w12)
ok('a level-1 wall does NOT build ceilings', ceilings.empty?, ceilings.length)

# back to 1 so a stray state never leaks into other suites
LM.set_active_level!(1)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

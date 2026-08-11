# encoding: utf-8
# rt10 — active level (part 1): new walls land on the level the user works
# on, miters stay inside one level, room detection ignores level-2 walls.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './room_manager'

# The stub WallTool is a module — give it the one class method the level
# placement needs, recording the lift like the real set_wall_base!.
module InteriorPro
  module WallTool
    def self.set_wall_base!(wall, z)
      wall.set_attribute('InteriorPro', 'base_z', z.to_f)
      true
    end
  end
end

require './level_manager'
require './foundation_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
LM = InteriorPro::LevelManager

def make_wall(m, id, level = nil)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'base_z', 0.0)
  w.set_attribute('InteriorPro', 'level', level) unless level.nil?
  w
end

# ---- the active level switch --------------------------------------------
Sketchup.reset_model!
ok('default active level is 1', LM.active_level == 1)
LM.set_active_level!(2)
ok('switching to level 2 sticks', LM.active_level == 2)
LM.set_active_level!(0)
ok('nonsense clamps back to 1', LM.active_level == 1)

# ---- placing walls on the active level ----------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
LM.set_active_level!(1)
w1 = make_wall(m, 'w1')
LM.place_wall_on_active_level!(w1)
ok('level-1 wall is tagged level 1', w1.get_attribute('InteriorPro', 'level') == 1)
ok('and stays on the ground', w1.get_attribute('InteriorPro', 'base_z') == 0.0,
   w1.get_attribute('InteriorPro', 'base_z'))

LM.set_active_level!(2)
w2 = make_wall(m, 'w2')
LM.place_wall_on_active_level!(w2)
ok('level-2 wall is tagged level 2', w2.get_attribute('InteriorPro', 'level') == 2)
ok('and is lifted to the level-2 base (106)', w2.get_attribute('InteriorPro', 'base_z') == 106.0,
   w2.get_attribute('InteriorPro', 'base_z'))

ok('wall_level reads the tag', LM.wall_level(w2) == 2)
ok('wall_level defaults to 1 without a tag', LM.wall_level(make_wall(m, 'w0')) == 1)

# ---- the foundation ignores level-2 walls --------------------------------
w1.set_attribute('InteriorPro', 'wall_category', 'exterior')
w2.set_attribute('InteriorPro', 'wall_category', 'exterior')
fnd_ids = InteriorPro::FoundationManager.exterior_walls.map { |g| g.get_attribute('InteriorPro', 'id') }
ok('foundation sees the level-1 exterior wall', fnd_ids.include?('w1'), fnd_ids)
ok('but NOT the level-2 exterior wall', !fnd_ids.include?('w2'), fnd_ids)

# ---- room detection ignores level-2 walls (temporary guard) --------------
ids = InteriorPro::RoomManager.wall_list.map { |g| g.get_attribute('InteriorPro', 'id') }
ok('room detection sees level-1 + untagged walls', ids.sort == %w[w0 w1], ids.sort)
ok('and NOT the level-2 wall', !ids.include?('w2'))

# ---- the wall_tool wiring exists in the source ---------------------------
src = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('create_wall places the wall on the active level',
   src.include?('InteriorPro::LevelManager.place_wall_on_active_level!(group)'))
# Corner joining now has two shapes: the plain one, and set_wall_sag! for a
# wall the Arc tool asked to bend (it joins the corners itself). The level
# must be set before EITHER of them.
ok('and it happens BEFORE join_corners',
   src.index('place_wall_on_active_level!(group)') < src.index('join_corners(group, model)'))
ok('and BEFORE the curved-wall corner join too',
   src.index('place_wall_on_active_level!(group)') <
   src.index('InteriorPro::WallTool.set_wall_sag!(group, @arc_sag.to_f'))
ok('find_neighbor_at filters by level',
   src.include?("excl_level = (exclude_group.get_attribute('InteriorPro', 'level') || 1).to_i") &&
   src.include?("next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == excl_level"))

# ---- drawing happens ON the active level's plane -------------------------
ok('the tool knows the active working plane', src.include?('def active_base'))
ok('free cursor points land on that plane', src.include?('def pick_point'))
ok('the preview is built at the plane height', src.include?('z1 = base') && src.include?('z2 = base + @height'))
ok('axis snapping stays on the plane', src =~ /def snap_to_axis\(pt\)\s*\n\s*base = active_base/)
ok('typed lengths stay on the plane', src.include?('Geom::Point3d.new(new_x, new_y, active_base)'))
ok('no drawing point is still pinned to z=0',
   !src.include?('pt_input = @ip.position') &&
   !src.include?('pt = Geom::Point3d.new(@ip.position.x, @ip.position.y, 0)'))

# ---- moving/stretching a wall must not drag the other level --------------
ui_src = File.read('ui_dialogs.rb', encoding: 'UTF-8')
ok('Move Wall detects partners only on the same level',
   ui_src.include?("moving_lvl = (group.get_attribute('InteriorPro', 'level') || 1).to_i") &&
   ui_src.include?("next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == moving_lvl"))
ok('Move Wall refreshes the foundation',
   ui_src.include?('InteriorPro::FoundationManager.refresh! if defined?(InteriorPro::FoundationManager)'))
st_src = File.read('wall_stretch_tool.rb', encoding: 'UTF-8')
ok('Stretch Wall partners only on the same level',
   st_src.include?("wall_lvl = (wall.get_attribute('InteriorPro', 'level') || 1).to_i") &&
   st_src.include?("next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == wall_lvl"))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

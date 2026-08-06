# encoding: utf-8
# rt9 — LevelManager: levels registry, exterior walls rising to the level-2
# floor (remembering their ceiling in 'ceiling_h'), and the subfloor deck.
# Uses the REAL room_manager for the building outline maths.
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
end

require './room_manager'
require './level_manager'
require './ceiling_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
LM = InteriorPro::LevelManager
CM = InteriorPro::CeilingManager

def make_wall(m, id, s, e, cat = 'exterior', height = 96.0, th = 6.0)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0]); w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0]);   w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', th)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', height)
  w.set_attribute('InteriorPro', 'base_z', 0.0)
  w.set_attribute('InteriorPro', 'wall_category', cat)
  w
end

def square_building(m)
  make_wall(m, 'e1', [0, 0], [240, 0])
  make_wall(m, 'e2', [240, 0], [240, 240])
  make_wall(m, 'e3', [240, 240], [0, 240])
  make_wall(m, 'e4', [0, 240], [0, 0])
  make_wall(m, 'i1', [120, 0], [120, 240], 'interior', 96.0, 4.0)
end

# ---- the registry --------------------------------------------------------
Sketchup.reset_model!
ok('level 1 starts at 0', LM.level_base(1) == 0.0)
ok('level 2 base = 96 + 9.25 + 0.75 = 106', LM.level_base(2) == 106.0, LM.level_base(2))
LM.set_structure!(joist: 11.25) # 2x12
ok('2x12 pushes level 2 to 108', LM.level_base(2) == 108.0, LM.level_base(2))
LM.set_structure!(joist: 9.25)
ok('and back to 106', LM.level_base(2) == 106.0)

# ---- build: exterior walls rise, interior walls do not -------------------
Sketchup.reset_model!
m = Sketchup.active_model
square_building(m)
n = LM.build_level2_structure!
ok('all 4 exterior walls rise', n == 4, n)
ext = LM.exterior_walls
ok('their height is now 106', ext.all? { |w| w.get_attribute('InteriorPro', 'height') == 106.0 },
   ext.map { |w| w.get_attribute('InteriorPro', 'height') })
ok('each remembers its ceiling at 96', ext.all? { |w| w.get_attribute('InteriorPro', 'ceiling_h') == 96.0 },
   ext.map { |w| w.get_attribute('InteriorPro', 'ceiling_h') })
int_wall = LM.all_walls.find { |w| w.get_attribute('InteriorPro', 'id') == 'i1' }
ok('the interior wall is untouched', int_wall.get_attribute('InteriorPro', 'height') == 96.0 &&
   int_wall.get_attribute('InteriorPro', 'ceiling_h').nil?)

# running it again must not eat the remembered ceiling
n2 = LM.build_level2_structure!
ok('second run raises nothing new', n2 == 0, n2)
ok('and the ceiling memory survives', ext.all? { |w| w.get_attribute('InteriorPro', 'ceiling_h') == 96.0 })

# ---- the subfloor deck ---------------------------------------------------
subs = LM.subfloors
ok('one subfloor deck exists', subs.length == 1, subs.length)
deck = subs.first
ok('deck level is 2', deck.get_attribute('InteriorPro', 'level') == 2)
face = deck.entities.grep(Sketchup::Face).first
ok('deck top sits at 106', face && face.pts.all? { |p| (p.z - 106.0).abs < 0.001 },
   face && face.pts.map(&:to_a))
ok('deck thickness goes DOWN 0.75', face && face.pulled == -0.75, face && face.pulled)
xs = face.pts.map(&:x)
ys = face.pts.map(&:y)
ok('deck reaches the interior faces of the exterior walls (3..237)',
   (xs.min - 3.0).abs < 0.1 && (xs.max - 237.0).abs < 0.1 &&
   (ys.min - 3.0).abs < 0.1 && (ys.max - 237.0).abs < 0.1,
   [xs.min, xs.max, ys.min, ys.max])
ok('the deck spans OVER the interior wall (one piece)', subs.length == 1)

# a rebuild replaces the deck instead of stacking a second one
LM.build_subfloor!
ok('rebuild keeps a single deck', LM.subfloors.length == 1, LM.subfloors.length)

# ---- level-2 walls shrink the deck to THEIR loop -------------------------
# (upper floor smaller than level 1 — the rest will get a roof, not a floor)
def make_l2_wall(m, id, s, e)
  w = make_wall(m, id, s, e)
  w.set_attribute('InteriorPro', 'level', 2)
  w
end
make_l2_wall(m, 'u1', [60, 60], [180, 60])
make_l2_wall(m, 'u2', [180, 60], [180, 180])
make_l2_wall(m, 'u3', [180, 180], [60, 180])
make_l2_wall(m, 'u4', [60, 180], [60, 60])
LM.build_subfloor!
deck2 = LM.subfloors.first
ok('still a single deck after level-2 walls', LM.subfloors.length == 1, LM.subfloors.length)
f2 = deck2.entities.grep(Sketchup::Face).first
xs2 = f2.pts.map(&:x)
ys2 = f2.pts.map(&:y)
ok('the deck shrinks to the level-2 walls (63..177)',
   (xs2.min - 63.0).abs < 0.1 && (xs2.max - 177.0).abs < 0.1 &&
   (ys2.min - 63.0).abs < 0.1 && (ys2.max - 177.0).abs < 0.1,
   [xs2.min, xs2.max, ys2.min, ys2.max])
# clean up the level-2 walls so the sections below keep their assumptions
%w[u1 u2 u3 u4].each do |uid|
  g = LM.all_walls.find { |w| w.get_attribute('InteriorPro', 'id') == uid }
  g.erase! if g
end
LM.build_subfloor!

# ---- the ceiling respects ceiling_h on raised walls ----------------------
room = m.entities.add_group
room.set_attribute('InteriorPro', 'type', 'room')
room.set_attribute('InteriorPro', 'id', 'r1')
room.set_attribute('InteriorPro', 'name', 'Room 1')
room.set_attribute('InteriorPro', 'boundary_xy', [3, 3, 117, 3, 117, 237, 3, 237])
room.set_attribute('InteriorPro', 'bounding_wall_ids', %w[e1 e4 i1])
room.set_attribute('InteriorPro', 'area_sqft', 180.0)
c = CM.build_ceiling_for_room!(room)
ok('flat ceiling stays at 96 even with raised walls',
   c.get_attribute('InteriorPro', 'ceiling_height_in') == 96.0,
   c.get_attribute('InteriorPro', 'ceiling_height_in'))

# ---- remove: everything goes back ---------------------------------------
n3 = LM.remove_level2_structure!
ok('remove lowers the 4 walls', n3 == 4, n3)
ok('heights are 96 again', LM.exterior_walls.all? { |w| w.get_attribute('InteriorPro', 'height') == 96.0 },
   LM.exterior_walls.map { |w| w.get_attribute('InteriorPro', 'height') })
ok('the ceiling memory is cleared', LM.all_walls.all? { |w| w.get_attribute('InteriorPro', 'ceiling_h').nil? })
ok('the deck is gone', LM.subfloors.empty?, LM.subfloors.length)

# ---- no closed loop = no deck, no crash ---------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'e1', [0, 0], [240, 0])
make_wall(m, 'e2', [240, 0], [240, 240]) # open shape
ok('an open shape skips the deck quietly', LM.build_subfloor!.nil?)

# ---- the crown cap source line exists in molding_tool --------------------
src = File.read('molding_tool.rb', encoding: 'UTF-8')
ok('molding reads ceiling_h', src.include?("wall.get_attribute('InteriorPro', 'ceiling_h')"))
ok('and caps the crown below a raised top', src.include?('wall_h = ch if ch > 12.0 && ch < wall_h'))
ok('the baseboard skips high openings (windows)',
   src.include?("openings.select { |o| o[:floor_offset].to_f < base_top }"))

# ---- ensure_structure_below!: the auto hook (2026-08-04) -----------------
Sketchup.reset_model!
m9 = Sketchup.active_model
square_building(m9)
LM.set_active_level!(1)
ok('on level 1 the hook does nothing', LM.ensure_structure_below! == 0,
   LM.ensure_structure_below!)
ok('walls untouched on level 1', LM.exterior_walls.all? { |w| w.get_attribute('InteriorPro', 'height') == 96.0 })
LM.set_active_level!(2)
n9 = LM.ensure_structure_below!
ok('on level 2 the hook builds the structure', n9 == 4, n9)
ok('exterior walls rose to 106', LM.exterior_walls.all? { |w| w.get_attribute('InteriorPro', 'height') == 106.0 },
   LM.exterior_walls.map { |w| w.get_attribute('InteriorPro', 'height') })
LM.set_active_level!(1)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

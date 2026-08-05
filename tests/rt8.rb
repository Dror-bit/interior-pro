# encoding: utf-8
# rt8 — CeilingManager: build/refresh/remove ceilings from room entities.
# Two styles: 'flat' (default, zero-thickness face) and 'framed' (thick,
# for under a second floor).
require './sketchup_stub'

# Enrich the stub just enough for ceiling geometry: faces remember their
# points, expose an upward normal and record pushpull calls.
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

require './ceiling_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
CM = InteriorPro::CeilingManager

def make_wall(m, id, height, base_z = 0.0)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'height', height)
  w.set_attribute('InteriorPro', 'base_z', base_z)
  w
end

def make_room(m, id, name, wall_ids, boundary = [0, 0, 120, 0, 120, 120, 0, 120])
  r = m.entities.add_group
  r.set_attribute('InteriorPro', 'type', 'room')
  r.set_attribute('InteriorPro', 'id', id)
  r.set_attribute('InteriorPro', 'name', name)
  r.set_attribute('InteriorPro', 'boundary_xy', boundary)
  r.set_attribute('InteriorPro', 'bounding_wall_ids', wall_ids)
  r.set_attribute('InteriorPro', 'area_sqft', 100.0)
  r.set_attribute('InteriorPro', 'level', 1)
  r
end

def make_floor(m, room_id, level)
  f = m.entities.add_group
  f.set_attribute('InteriorPro', 'type', 'floor')
  f.set_attribute('InteriorPro', 'room_id', room_id)
  f.set_attribute('InteriorPro', 'floor_level', level)
  f
end

# ---- default build: FLAT, height from the walls --------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0)
make_wall(m, 'w2', 96.0)
room = make_room(m, 'r1', 'Room 1', %w[w1 w2])

c = CM.build_ceiling_for_room!(room)
ok('a ceiling is built', !c.nil?)
ok('type is ceiling', c.get_attribute('InteriorPro', 'type') == 'ceiling')
ok('it remembers its room', c.get_attribute('InteriorPro', 'room_id') == 'r1')
ok('default style is flat', c.get_attribute('InteriorPro', 'ceiling_style') == 'flat',
   c.get_attribute('InteriorPro', 'ceiling_style'))
ok('height defaults to the wall height', c.get_attribute('InteriorPro', 'ceiling_height_in') == 96.0,
   c.get_attribute('InteriorPro', 'ceiling_height_in'))
ok('flat means zero thickness', c.get_attribute('InteriorPro', 'thickness_in') == 0.0,
   c.get_attribute('InteriorPro', 'thickness_in'))
face = c.entities.grep(Sketchup::Face).first
ok('the face sits at z=96', face && face.pts.all? { |p| (p.z - 96.0).abs < 0.001 },
   face && face.pts.map(&:to_a))
ok('flat is NOT extruded', face && face.pulled.nil?, face && face.pulled)
ok('painted on the front', face && !face.material.nil?)
ok('and on the back', face && !face.back_material.nil?)
ok('it carries the room area', c.get_attribute('InteriorPro', 'area_sqft') == 100.0)
ok('it carries a level', c.get_attribute('InteriorPro', 'level') == 1)

# ---- framed style: thickness comes back ----------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0)
room = make_room(m, 'r1', 'Room 1', %w[w1])
c = CM.build_ceiling_for_room!(room, style: 'framed')
ok('framed style is stored', c.get_attribute('InteriorPro', 'ceiling_style') == 'framed')
ok('framed has drywall thickness', c.get_attribute('InteriorPro', 'thickness_in') == 0.5,
   c.get_attribute('InteriorPro', 'thickness_in'))
face = c.entities.grep(Sketchup::Face).first
ok('framed is pulled UP by the thickness', face && face.pulled == 0.5, face && face.pulled)
c2 = CM.build_ceiling_for_room!(room)
ok('rebuild keeps the framed style', c2.get_attribute('InteriorPro', 'ceiling_style') == 'framed',
   c2.get_attribute('InteriorPro', 'ceiling_style'))

# ---- a pre-style ceiling (step-1 model) becomes flat on rebuild ----------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0)
room = make_room(m, 'r1', 'Room 1', %w[w1])
legacy = m.entities.add_group
legacy.set_attribute('InteriorPro', 'type', 'ceiling')
legacy.set_attribute('InteriorPro', 'room_id', 'r1')
legacy.set_attribute('InteriorPro', 'ceiling_height_in', 96.0)
legacy.set_attribute('InteriorPro', 'thickness_in', 0.5) # old default, no style attr
c = CM.build_ceiling_for_room!(room)
ok('a legacy ceiling turns flat', c.get_attribute('InteriorPro', 'ceiling_style') == 'flat',
   c.get_attribute('InteriorPro', 'ceiling_style'))
ok('and loses its thickness', c.get_attribute('InteriorPro', 'thickness_in') == 0.0)

# ---- the lowest wall wins ------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0)
make_wall(m, 'w2', 120.0) # one tall wall must not push the ceiling up
room = make_room(m, 'r1', 'Room 1', %w[w1 w2])
c = CM.build_ceiling_for_room!(room)
ok('the lowest wall top wins', c.get_attribute('InteriorPro', 'ceiling_height_in') == 96.0,
   c.get_attribute('InteriorPro', 'ceiling_height_in'))

# ---- dropped room (garage): height stays relative to ITS floor ----------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0, -16.0) # dropped wall: top at 80
make_wall(m, 'w2', 96.0, 0.0)   # shared wall with the house: top at 96
room = make_room(m, 'g1', 'Garage', %w[w1 w2])
make_floor(m, 'g1', -16.0)
c = CM.build_ceiling_for_room!(room)
ok('garage ceiling height is measured from ITS floor',
   c.get_attribute('InteriorPro', 'ceiling_height_in') == 96.0,
   c.get_attribute('InteriorPro', 'ceiling_height_in'))
face = c.entities.grep(Sketchup::Face).first
ok('garage ceiling sits at -16+96=80', face && face.pts.all? { |p| (p.z - 80.0).abs < 0.001 },
   face && face.pts.map(&:to_a))

# ---- rebuild keeps a custom height, replaces the old group ---------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0)
room = make_room(m, 'r1', 'Room 1', %w[w1])
c1 = CM.build_ceiling_for_room!(room, height: 108.0)
ok('custom height is stored', c1.get_attribute('InteriorPro', 'ceiling_height_in') == 108.0)
c2 = CM.build_ceiling_for_room!(room)
ok('rebuild keeps the custom height', c2.get_attribute('InteriorPro', 'ceiling_height_in') == 108.0,
   c2.get_attribute('InteriorPro', 'ceiling_height_in'))
ok('the old group is gone', !c1.valid? && CM.ceilings_in_model.length == 1,
   CM.ceilings_in_model.length)

# ---- build_ceilings! / refresh! / remove_all! ----------------------------
Sketchup.reset_model!
m = Sketchup.active_model
make_wall(m, 'w1', 96.0)
make_room(m, 'r1', 'Room 1', %w[w1])
make_room(m, 'r2', 'Room 2', %w[w1])
n = CM.build_ceilings!
ok('build_ceilings! covers every room', n == 2 && CM.ceilings_in_model.length == 2, n)

# a room disappears -> refresh! erases its ceiling only
gone = InteriorPro::RoomManager.rooms_in_model.find { |r| r.get_attribute('InteriorPro', 'id') == 'r2' }
gone.erase!
CM.refresh!
left = CM.ceilings_in_model
ok('refresh! drops the orphan ceiling', left.length == 1 && left.first.get_attribute('InteriorPro', 'room_id') == 'r1',
   left.map { |c3| c3.get_attribute('InteriorPro', 'room_id') })

# a room without a ceiling is NOT given one by refresh!
make_room(m, 'r3', 'Room 3', %w[w1])
CM.refresh!
ok('refresh! never builds uninvited', CM.ceilings_in_model.length == 1, CM.ceilings_in_model.length)

ok('remove_all! clears everything', CM.remove_all! == 1 && CM.ceilings_in_model.empty?)

# ---- degenerate input ----------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
bad = make_room(m, 'rb', 'Bad', [], [0, 0, 1, 1]) # 2 points only
ok('a broken boundary returns nil quietly', CM.build_ceiling_for_room!(bad).nil?)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

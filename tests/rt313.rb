# encoding: utf-8
# rt313 - ONLY THIS ROOM IN ITS PICTURES (2026-10-14, his "למה הוא מראה חלקים מחוץ לחדר"): a thing whose middle lies
# outside the room's outline is put aside for the shots; walls, doors, windows and the things already set aside are not.
require './sketchup_stub'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switch is there and on', ET::USE_ROOM_ONLY == true)
poly = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0), Geom::Point3d.new(100, 80, 0), Geom::Point3d.new(0, 80, 0)]
Th = Struct.new(:ent, :xf, :type)
Ent = Struct.new(:cx, :cy) do
  def transformation; Geom::Transformation.new; end
  def bounds; b = Object.new; c = Geom::Point3d.new(cx, cy, 10); b.define_singleton_method(:center) { c }; b; end
end
xf = Geom::Transformation.new
all = [Th.new(Ent.new(50, 40), xf, 'fixture'), Th.new(Ent.new(150, 40), xf, 'fixture'), Th.new(Ent.new(150, 40), xf, 'wall'),
       Th.new(Ent.new(150, 40), xf, 'door'), Th.new(Ent.new(150, 40), xf, 'electrical'), Th.new(Ent.new(150, 40), xf, 'floor'),
       Th.new(Ent.new(50, 40), xf, 'electrical')]
out = ET.outside_room(poly, all)
ok('the toilet, the outlet and the door of the next room are put aside', out.map(&:type).sort == %w[door electrical fixture], out.map { |t| [t.type, t.ent.cx] })
ok('the ones inside stay', out.none? { |t| t.ent.cx == 50 })
ok('a wall (no list) and a floor outside are not touched here', out.none? { |t| %w[wall floor].include?(t.type) })
# 19:51 "הוא חייב לעצור בגבול החדר הנבחר": only this room's walls, and the doors/windows on its outline
WEnt = Struct.new(:cx, :cy, :wid) do
  def transformation; Geom::Transformation.new; end
  def bounds; b = Object.new; c = Geom::Point3d.new(cx, cy, 10); b.define_singleton_method(:center) { c }; b; end
  def get_attribute(_d, k); k == 'id' ? wid : nil; end
end
own_w = Th.new(WEnt.new(100, 40, 'w1'), xf, 'wall')
next_w = Th.new(WEnt.new(150, 40, 'w9'), xf, 'wall')
own_d = Th.new(Ent.new(102.3, 40), xf, 'door')           # in its own wall, 2.3" past the line
own_win = Th.new(Ent.new(50, 83.8), xf, 'window')        # 3.8" past the far side
far_win = Th.new(Ent.new(103.8, -60), xf, 'window')      # same long wall line, past the corner
o2 = ET.outside_room(poly, [own_w, next_w, own_d, own_win, far_win], %w[w1 w2 w3 w4])
ok('the next room\'s wall is put aside, its own stays', o2.include?(next_w) && !o2.include?(own_w))
ok('its own door and window stay', !o2.include?(own_d) && !o2.include?(own_win))
ok('a window on the same wall line past the corner is put aside', o2.include?(far_win))
ok('kill switch for the frame is there', ET::USE_ROOM_ONLY_FRAME == true)
src = File.read('./elevation_tool.rb')
m = src[/def shoot!.*?sides\(poly\)\.each/m].to_s
ok('shoot! puts them aside with the floors (hidden, and back after)', m.include?("outside_room(poly, all, room.ent.get_attribute(D, 'bounding_wall_ids')).each") && m.include?('hidden << t.ent'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt191 - THE OTHER WALL AT AN INNER CORNER RUNS THROUGH, NOT INTO (2026-09-20).
#
# His words: "עדיין לא עבד בשתי פינות ... זה קורה כמעט בכל הפינות." Measured:
# at the two INNER corners of a tiled square the second wall runs THROUGH
# the clicked point mid-length - its end nowhere near - so wall_ending_at
# offered nothing, no alt was set, and the drag had nothing to switch to.
# other_wall_at finds any perpendicular wall whose face passes through the
# point, whether it ends there or carries on. HIS four Room-2 walls.
require './sketchup_stub'
require './tile_wall'
require './tile_wall_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

Sketchup.reset_model!
M = Sketchup.active_model
def wall(a)
  g = M.entities.add_group
  a.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  z0 = Struct.new(:z).new(0.0)
  g.define_singleton_method(:bounds) { Struct.new(:min).new(z0) }
  g
end

T  = InteriorPro::TileWallTool.allocate
TW = InteriorPro::TileWall
P  = Geom::Point3d
E  = wall(type: 'wall', id: 'east',  start_x: -438.0, start_y: 183.0,    end_x: -438.0, end_y: 407.5,    thickness: 5.0, height: 96.0, anchor: 'left')
N  = wall(type: 'wall', id: 'north', start_x: -438.0, start_y: 407.5,    end_x: -702.0, end_y: 407.5,    thickness: 5.0, height: 96.0, anchor: 'left')
IV = wall(type: 'wall', id: 'ivert', start_x: -534.6, start_y: 402.5,    end_x: -534.6, end_y: 327.918,  thickness: 4.5, height: 96.0, anchor: 'left')
IH = wall(type: 'wall', id: 'ihorz', start_x: -534.6, start_y: 327.918,  end_x: -443.0, end_y: 327.918,  thickness: 4.5, height: 96.0, anchor: 'left')
def idof(w); w.nil? ? nil : w.get_attribute('InteriorPro', 'id'); end

# NE inner corner: east wall picked, north wall RUNS THROUGH (its end is
# 264" away at -702). wall_ending_at found nothing here.
pos = P.new(-443.0, 402.5, 0.0)
mid = T.wall_mid_face_at(pos, M, P.new(-490.0, 360.0, 60.0))
ok('the picked wall at the NE inner corner is the east wall', idof(mid[:wall]) == 'east', idof(mid[:wall]))
ok('wall_ending_at finds nothing there - the north wall runs through',
   T.wall_ending_at(pos, mid[:wall], M).nil?)
ok('other_wall_at DOES find the north wall (the drag can now switch to it)',
   idof(T.other_wall_at(pos, mid[:wall], mid[:side], M)) == 'north',
   idof(T.other_wall_at(pos, mid[:wall], mid[:side], M)))

# SW inner corner: vertical interior picked, horizontal interior runs through.
pos2 = P.new(-530.1, 332.418, 0.0)
mid2 = T.wall_mid_face_at(pos2, M, P.new(-490.0, 360.0, 60.0))
ok('the other wall at the SW inner corner is found too',
   idof(T.other_wall_at(pos2, mid2[:wall], mid2[:side], M)) &&
   idof(T.other_wall_at(pos2, mid2[:wall], mid2[:side], M)) != idof(mid2[:wall]),
   idof(T.other_wall_at(pos2, mid2[:wall], mid2[:side], M)))

# A PARALLEL wall at the point is never the corner partner.
# (the far outside wall parallel to north, well away) - use east's own far
# point: no parallel wall should be returned as perpendicular partner.
ok('the partner is perpendicular, never the same direction',
   begin
     o = T.other_wall_at(pos, mid[:wall], mid[:side], M)
     ofr = TW.frame_for(o, 'a'); bfr = TW.frame_for(mid[:wall], mid[:side])
     (ofr[:ux] * bfr[:ux] + ofr[:uy] * bfr[:uy]).abs < 0.2
   end)

# A point out in open floor, on nobody's face, has no partner.
ok('open floor has no corner partner', T.other_wall_at(P.new(-480.0, 360.0, 0.0), E, 'a', M).nil?)

# The real path: face_point sets alt from other_wall_at, not wall_ending_at.
SRC = File.read('./tile_wall_tool.rb')
ok('face_point offers the alt via other_wall_at',
   SRC.include?('other = other_wall_at(pos, wall, mid[:side])') &&
   SRC.include?('alt = { wall: other, side: nil } if other'))

puts($fails.zero? ? 'rt191 all green' : "rt191 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

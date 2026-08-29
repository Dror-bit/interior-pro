# encoding: utf-8
# rt124 - THE GABLE TRIANGLE STOPS AT THE PLAN'S CORNERS (2026-09-08).
#
# His L-shaped house, the wing gabled at its outer end. The eave polygon
# runs one overhang PAST the corner walls, and the framed path handed the
# gable wall top an unclipped span - so a stub of "wall" stood out in the
# rake overhang, a few inches tall, poking past the rake boards. His
# photo, 2026-09-08: "הקיר המשולש שמתחת לגג צריך להיות תואם לגג ולא
# לעבור את הקווים".
#
# THE CLAIM: the wing's gable_wall_top spans exactly its corner walls'
# centrelines (878..999.5), not the deck (866..1011.5). The clip is taken
# off the owning RECT's span, so a wall that BRIDGES a wing mouth
# mid-edge (rt17/rt86) is untouched - those two suites guard that side.
#
# Against the old code: the span comes back 866..1011.5 and this fails.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
module Sketchup
  class Face
    attr_accessor :pts, :pulled, :material, :back_material
    def normal
      a, b, c = @pts[0], @pts[1], @pts[2]
      u = Geom::Vector3d.new(b.x - a.x, b.y - a.y, b.z - a.z)
      v = Geom::Vector3d.new(c.x - a.x, c.y - a.y, c.z - a.z)
      (u * v).normalize
    end
    def pushpull(d); @pulled = d; end
    def reverse!; @pts = @pts.reverse; self; end
  end
  class Entities
    def add_face(pts); f = Face.new; f.pts = pts; @list << f; f; end
  end
end
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

RM = InteriorPro::RoofManager

def wall(m, id, s, e, anchor)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 5.0,
    'anchor' => anchor, 'height' => 96.0, 'base_z' => 106.0,
    'level' => 2, 'wall_category' => 'exterior'
  }.each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

Sketchup.reset_model!
m = Sketchup.active_model
# his six walls (house_dump_report 2026-09-08), corner squared
wall(m, 'north', [1144.5, 520.0], [878.0, 520.0], 'bottom-left')
wall(m, 'east',  [1144.5, 270.0], [1144.5, 520.0], 'bottom-left')
wall(m, 'south-main', [994.5, 270.0], [1144.5, 270.0], 'bottom-left')
wall(m, 'east-wing',  [994.5, 141.5], [994.5, 270.0], 'bottom-right')
wall(m, 'south-wing', [878.0, 141.5], [994.5, 141.5], 'bottom-left')
wall(m, 'west', [878.0, 520.0], [878.0, 141.5], 'bottom-left')
m.set_attribute('InteriorPro', 'roof_gable_wall_ids', %w[south-wing west east])
m.set_attribute('InteriorPro', 'roof_gable_click_xy',
                [978.4, 141.5, 878.0, 299.8, 1144.5, 428.5])
roof = RM.build_roof!(style: 'hip', pitch: 5, overhang: 12.0, level: 2,
                      fascia: true, fascia_depth: 8.0, drip: true,
                      soffit: 'boxed', gable_walls: true,
                      roof_material: 'shingle', thickness: 0.5)
ok('his house builds framed (no fallback)', !roof.nil?)

# every gable_wall_top face, world coords
tris = []
walk = lambda do |ents, label, depth|
  ents.to_a.each do |e|
    if e.is_a?(Sketchup::Face) && e.pts
      tris << e.pts if label == 'gable_wall_top'
    elsif e.is_a?(Sketchup::Group)
      p = e.get_attribute('InteriorPro', 'part').to_s
      walk.call(e.entities, p.empty? ? label : p, depth + 1) if depth < 5
    end
  end
end
walk.call(roof.entities, 'roof', 0)
ok('three gable wall tops', !tris.empty?)

# the WING's: every face near y=141.5
wing = tris.select { |pts| pts.all? { |p| p.y > 138 && p.y < 150 } }
ok('the wing has one', !wing.empty?)
xs = wing.flatten.map(&:x)
ok('it STARTS on the west corner wall (878), not in the overhang (866)',
   (xs.min - 878.0).abs < 0.6, xs.min)
ok('it ENDS on the east corner wall (999.5), not in the overhang (1011.5)',
   (xs.max - 999.5).abs < 0.6, xs.max)

# the WEST gable's triangle spans its wall corners the same way
west = tris.select { |pts| pts.all? { |p| p.x > 875 && p.x < 886 } }
ok('the west gable has one', !west.empty?)
ys = west.flatten.map(&:y)
# the west line's owner is the MAIN rect (over the wing the west line
# is an EAVE, no triangle) - so its corner walls are south-main (270)
# and north (520).
ok('its ends sit on corner walls too (270 / 520)',
   (ys.min - 270.0).abs < 0.6 && (ys.max - 520.0).abs < 0.6,
   [ys.min, ys.max])

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

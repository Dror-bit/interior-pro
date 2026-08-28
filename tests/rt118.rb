# encoding: utf-8
# rt118 - THE RAISED HEEL (2026-09-06).
#
# He looked at his own eave and marked it in green: the roof's underside
# met the wall's top outer corner, so the whole eave tail hung BELOW the
# wall and the corner disappeared into the soffit. What he asked for:
# "אני רוצה שהגג יישב על הפינה של הקיר שהפינה כביכול חשופה והיא נוגעת
# בתחילת האיבס" - the tail lifted until its underside AT THE EAVE TIP is
# level with that corner. Builders call it a raised (energy) heel.
#
# THE NUMBER: the tail used to fall overhang x pitch over the overhang, so
# that is exactly the lift. Every other z on the roof rides up with it -
# the ridge, the apex, the fascia - because ONE line sets the base:
#   z0 = eave_z(walls) + heel_lift(s[:overhang], slope)
#
# Against the old code claims 2, 3 and 4 fail (there was no heel_lift, and
# the eave tip sat slope x overhang below the wall).
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
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager
WALL_TOP = 96.0

def make_wall(m, id, s, e)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0])
  w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0])
  w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', WALL_TOP)
  w.set_attribute('InteriorPro', 'base_z', 0.0)
  w.set_attribute('InteriorPro', 'level', 1)
  w.set_attribute('InteriorPro', 'wall_category', 'exterior')
  w
end

def a_box(m)
  make_wall(m, 'wS', [0, 0], [300, 0])
  make_wall(m, 'wE', [300, 0], [300, 200])
  make_wall(m, 'wN', [300, 200], [0, 200])
  make_wall(m, 'wW', [0, 200], [0, 0])
end

# ---- 1. the number itself -------------------------------------------
ok('1. the lift IS the eave drop - nothing else',
   RF.heel_lift(24.0, 6.0 / 12.0, 8.0) == 8.0,
   RF.heel_lift(24.0, 6.0 / 12.0, 8.0))
ok('1b. neither the overhang nor the pitch is in it any more',
   RF.heel_lift(96.0, 12.0 / 12.0, 8.0) == RF.heel_lift(0.0, 0.0, 8.0),
   [RF.heel_lift(96.0, 12.0 / 12.0, 8.0), RF.heel_lift(0.0, 0.0, 8.0)])
ok('1c. no fascia, no lift - the roof sits exactly where it always did',
   RF.heel_lift(24.0, 0.5, 0.0) == 0.0)
ok('1d. the drop is the fascia depth, and only when there IS a fascia',
   RF.eave_drop(fascia: true, fascia_depth: 8.0) == 8.0 &&
   RF.eave_drop(fascia: false, fascia_depth: 8.0) == 0.0,
   [RF.eave_drop(fascia: true, fascia_depth: 8.0),
    RF.eave_drop(fascia: false, fascia_depth: 8.0)])

# ---- 2/3. a real roof stands exactly one eave depth over the wall ----
def build(pitch, overhang, fd = 8.0)
  Sketchup.reset_model!
  m = Sketchup.active_model
  a_box(m)
  r = RF.build_roof!(style: 'hip', pitch: pitch, overhang: overhang,
                     fascia: fd > 0.0, fascia_depth: fd, drip: false,
                     soffit: 'boxed', thickness: 0.0, ridge_cap: false)
  [r, m]
end

r, = build(6.0, 24.0)
ok('2. the roof builds', !r.nil?)
ok('2b. it stands one eave depth over the wall top',
   r && (r.get_attribute('InteriorPro', 'eave_z').to_f - (WALL_TOP + 8.0)).abs < 0.001,
   r && r.get_attribute('InteriorPro', 'eave_z'))

# THE CLAIM HE ACTUALLY MADE: the eave's underside - the board that faces
# the house - lands ON the exterior wall. The eave hangs one fascia depth
# under the deck, so that is eave_z minus the fascia depth.
ok('3. the underside of the eave lands ON the wall, not inside it',
   r && ((r.get_attribute('InteriorPro', 'eave_z').to_f - 8.0) - WALL_TOP).abs < 0.001,
   r && r.get_attribute('InteriorPro', 'eave_z').to_f - 8.0)

# ---- 4. every eave depth, every pitch, same rule ---------------------
[[4.0, 12.0, 6.0], [8.0, 30.0, 10.0], [12.0, 18.0, 8.0]].each do |pitch, oh, fd|
  rr, = build(pitch, oh, fd)
  got = rr && rr.get_attribute('InteriorPro', 'eave_z').to_f
  ok("4. #{pitch.to_i}:12, #{oh.to_i}\" eave, #{fd.to_i}\" fascia -> stands #{fd.to_i}\" over the wall",
     got && (got - (WALL_TOP + fd)).abs < 0.001, [got, WALL_TOP + fd])
  ok('4b. ...and its eave underside is still on the wall',
     got && ((got - fd) - WALL_TOP).abs < 0.001, got && got - fd)
end

# ---- 4c. the lift is a MOVE, not a reshape ---------------------------
def all_z(r)
  zs = []
  walk = lambda do |g, d|
    g.entities.each do |e|
      if e.is_a?(Sketchup::Face) && e.respond_to?(:pts) && e.pts
        e.pts.each { |p| zs << p.z.round(4) }
      elsif e.is_a?(Sketchup::Group) && d < 4
        walk.call(e, d + 1)
      end
    end
  end
  walk.call(r, 0)
  zs.sort
end
def build_at(wall_h)
  Sketchup.reset_model!
  m = Sketchup.active_model
  %w[wS wE wN wW].each_with_index do |id, i|
    pts = [[[0, 0], [300, 0]], [[300, 0], [300, 200]],
           [[300, 200], [0, 200]], [[0, 200], [0, 0]]][i]
    w = make_wall(m, id, pts[0], pts[1])
    w.set_attribute('InteriorPro', 'height', wall_h)
  end
  RF.build_roof!(style: 'hip', pitch: 6.0, overhang: 24.0,
                 fascia: true, fascia_depth: 9.0, drip: false,
                 soffit: 'boxed', thickness: 0.0, ridge_cap: false)
end
a = all_z(build_at(WALL_TOP))
b = all_z(build_at(WALL_TOP + 9.0))
ok('4c. the whole roof is one rigid body on its base z - every single ' \
   'point moves by the same amount, nothing reshapes',
   a.length == b.length && !a.empty? &&
   a.zip(b).map { |x, y| (y - x).round(3) }.uniq == [9.0],
   [a.length, b.length,
    a.zip(b).map { |x, y| (y - x).round(3) }.uniq.first(4)])

# ---- 5. NOTHING is added under the eave ------------------------------
# A first round filled the space the lift opened with a wall-thick band
# built into the roof group. He refused it on sight - "נראה כאילו הוספת
# קירות נוספים מתחת לגג... תמחק את רצועת הקיר הזאת ובאל תוסיף כלום" - so
# the lift stands alone. This pins that: over a plain hip, where no gable
# triangle belongs, the roof adds no wall-shaped part at all.
def wall_tops(r)
  out = []
  walk = lambda do |g, d|
    g.entities.grep(Sketchup::Group).each do |e|
      out << e if e.get_attribute('InteriorPro', 'part').to_s == 'gable_wall_top'
      walk.call(e, d + 1) if d < 3
    end
  end
  walk.call(r, 0)
  out
end
r5, = build(6.0, 24.0)
ok('5. a lifted hip roof adds no wall band of its own',
   wall_tops(r5).empty?, wall_tops(r5).length)

# ---- 6. the kill switch ----------------------------------------------
ok('6. there is a kill switch to put every roof back',
   RF.const_defined?(:USE_RAISED_HEEL))

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"
exit($fails.zero? ? 0 : 1)

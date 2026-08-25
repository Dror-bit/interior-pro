# encoding: utf-8
# rt88 - THE GUTTER, step 2: wired into the roof (2026-08-28).
#
# WHAT THIS IS
# Step 1 (rt87) built the shape and the sweep and left them unused. This
# step hangs them on the roof. The user's two answers are what is pinned
# here: all three profiles, and "רק באיב" - never on a gable rake.
#
# THE CLAIMS PINNED HERE
# 1. OFF BY DEFAULT. A roof built without asking for a gutter is the SAME
#    roof it was yesterday - same faces, in the same places. If this ever
#    fails, every roof the user has already built has grown one behind
#    his back.
# 2. NOTHING THAT WAS THERE MOVES. Every face of the plain roof is still
#    in the gutter roof, point for point. The gutter can only ADD.
# 3. EAVES ONLY. The gutter reaches out past the two eave lines and NOT
#    past the two gable lines - and not past the building corner on a 45
#    degree diagonal either, which is what square_flags is for.
# 4. IT HANGS ON THE FASCIA, INSIDE ITS DEPTH. Below the roof edge, above
#    the bottom of the fascia board. A gutter poking above the drip or
#    dangling under the soffit is wrong on sight.
# 5. ALL THREE PROFILES BUILD, and they are not each other.
# 6. THE ROOF REMEMBERS. gutter / profile / width round trip on the group,
#    so Edit Roof reopens with what this roof was built with.
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
    def points; @pts; end
  end
  class Entities
    def add_face(pts); f = Face.new; f.pts = pts; @list << f; f; end
  end
end

require './room_manager'
require './level_manager'
require './roof_manager'
require './roof_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 1e-6)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

RF = InteriorPro::RoofManager

def make_wall(m, id, s, e)
  w = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => s[0], 'start_y' => s[1],
    'end_x' => e[0], 'end_y' => e[1], 'thickness' => 6.0,
    'anchor' => 'bottom-center', 'height' => 96.0, 'base_z' => 0.0,
    'level' => 1, 'wall_category' => 'exterior' }
    .each { |k, v| w.set_attribute('InteriorPro', k, v) }
  w
end

# 300 x 200 box, gabled on the two SHORT ends (edges 1 and 3, x = -21 and
# x = 321 once the 18" overhang is on). So the eaves are the long sides,
# y = -21 and y = 221.
def a_box
  Sketchup.reset_model!
  m = Sketchup.active_model
  make_wall(m, 'S', [0, 0],     [300, 0])
  make_wall(m, 'E', [300, 0],   [300, 200])
  make_wall(m, 'N', [300, 200], [0, 200])
  make_wall(m, 'W', [0, 200],   [0, 0])
  m
end

BASE = { style: 'gable', pitch: 4, overhang: 18, fascia: true, drip: true,
         soffit: 'none' }.freeze

def roof(**extra)
  a_box
  RF.build_roof!(**BASE.merge(extra))
end

def faces(r); r.entities.grep(Sketchup::Face); end
def pts(r); faces(r).flat_map(&:points); end
def sig(r)
  faces(r).map { |f| f.points.map { |p| [p.x.round(3), p.y.round(3), p.z.round(3)] }.sort }.sort
end

plain = roof(gutter: false)
gutt  = roof(gutter: true, gutter_profile: 'k', gutter_width: 5.0)

ok('the plain roof still builds', !plain.nil? && faces(plain).length > 20)
ok('the gutter roof builds too', !gutt.nil?)

# ---------------------------------------------- 1. off by default
deflt = roof
ok('DEFAULT IS OFF - asking for nothing gives the roof of yesterday',
   sig(deflt) == sig(plain), [faces(deflt).length, faces(plain).length])
ok('...and the model setting itself is off', RF.settings[:gutter] == false,
   RF.settings[:gutter])

# ------------------------------------- 2. it can only ADD, never move
have = sig(gutt)
ok('every face of the plain roof survives untouched',
   (sig(plain) - have).empty?, (sig(plain) - have).first)
ok('and the gutter really added something',
   faces(gutt).length > faces(plain).length,
   [faces(gutt).length, faces(plain).length])

# ================================================ 3. EAVES ONLY ===========
px = pts(plain)
gx = pts(gutt)
EAVE_LO = -21.0
EAVE_HI = 221.0
ok('the plain roof stops at the eave line',
   px.map(&:y).min >= EAVE_LO - 0.2 && px.map(&:y).max <= EAVE_HI + 0.2,
   [px.map(&:y).min, px.map(&:y).max])
ok('the gutter reaches out past BOTH eaves',
   close(gx.map(&:y).min, EAVE_LO - 5.0, 0.01) &&
   close(gx.map(&:y).max, EAVE_HI + 5.0, 0.01),
   [gx.map(&:y).min, gx.map(&:y).max])
ok('THE RAKES STAY BARE - nothing grew on the gable ends',
   close(gx.map(&:x).min, px.map(&:x).min, 1e-6) &&
   close(gx.map(&:x).max, px.map(&:x).max, 1e-6),
   [gx.map(&:x).min, px.map(&:x).min, gx.map(&:x).max, px.map(&:x).max])

# ------------------------- 4. on the fascia, inside its depth
BAND_TOP = 96.0 - 18.0 * (4.0 / 12.0)      # 90.0
# Point3d objects are never equal to each other, so the two sets are
# compared as rounded numbers - the same way sig does it.
def xyz(list); list.map { |p| [p.x.round(3), p.y.round(3), p.z.round(3)] }; end
old_set = xyz(px).uniq
new_pts = (xyz(gx).uniq - old_set)
ok('there is new geometry to look at', new_pts.length > 8, new_pts.length)
ok('the gutter hangs BELOW the roof edge',
   new_pts.map { |q| q[2] }.max <= BAND_TOP - RF::GUTTER_DROP + 1e-6,
   new_pts.map { |q| q[2] }.max)
ok('...and never below the bottom of the fascia board',
   new_pts.map { |q| q[2] }.min >= BAND_TOP - 8.0 - 1e-6,
   new_pts.map { |q| q[2] }.min)

# ------------------------------------------- 5. all three profiles
seen = {}
RF::GUTTER_PROFILES.each do |pr|
  r = roof(gutter: true, gutter_profile: pr, gutter_width: 5.0)
  seen[pr] = sig(r)
  ok("#{pr}: it builds on a real roof", faces(r).length > faces(plain).length,
     faces(r).length)
  ok("#{pr}: still eaves only",
     pts(r).map(&:x).max <= px.map(&:x).max + 1e-6, pts(r).map(&:x).max)
end
ok('the three profiles are three different shapes',
   seen.values.map(&:hash).uniq.length == 3)

# --------------------------------------------- 6. the roof remembers
r = roof(gutter: true, gutter_profile: 'round', gutter_width: 6.0)
got = RF.roof_settings(r)
ok('the roof carries its gutter on', got[:gutter] == true, got[:gutter])
ok('...its profile', got[:gutter_profile] == 'round', got[:gutter_profile])
ok('...its width', close(got[:gutter_width], 6.0), got[:gutter_width])
ok('a 6" gutter really is wider than a 5" one',
   pts(r).map(&:y).max > pts(gutt).map(&:y).max,
   [pts(r).map(&:y).max, pts(gutt).map(&:y).max])

# ================================================ 7. THE PANEL ============
# Step 3: the three controls. The one that matters is the LAST claim -
# every older call into apply_roof arrives with the three new arguments
# missing, and a missing argument must mean "leave it alone", never
# "switch it off". Get that wrong and any old console line, or a saved
# panel, silently strips the gutter off the user's house.
a_box
InteriorPro::RoofDialog.show
dlg = InteriorPro::RoofDialog.instance_variable_get(:@dialog)
ok('the panel opens', !dlg.nil? && dlg.callbacks.key?('apply_roof'))

html = InteriorPro::RoofDialog.build_html(RF.settings)
ok('there is a gutter switch on the panel', html.include?('id="gutter"'), nil)
ok('...a shape picker with all three', html.include?('id="gutterProfile"') &&
   html.include?('value="k"') && html.include?('value="round"') &&
   html.include?('value="box"'))
ok('...and one size box, not two', html.scan('id="gutterWidth"').length == 1)
ok('...and a colour of its own', html.include?('id="gutterColor"'))

OLD = ['hip', '4', 'true', '18', 'true', '8', 'true', '#336699', '#eeeeee',
       'color', '0', 'true', 'none', '', 'false', ''].freeze

# One model from here on: Sketchup.reset_model! would wipe the saved
# settings with it, and what is being tested IS what survives.
dlg.callbacks['apply_roof'].call(nil, *OLD, 'true', 'round', '6')
ok('Apply with the switch on builds the gutter', RF.settings[:gutter] == true,
   RF.settings[:gutter])
ok('...with the shape it was given', RF.settings[:gutter_profile] == 'round',
   RF.settings[:gutter_profile])
ok('...and the size', close(RF.settings[:gutter_width], 6.0),
   RF.settings[:gutter_width])

dlg.callbacks['apply_roof'].call(nil, *OLD)
ok('AN OLD CALL LEAVES THE GUTTER ALONE - it does not strip it off',
   RF.settings[:gutter] == true, RF.settings[:gutter])
ok('...and does not reset its shape either',
   RF.settings[:gutter_profile] == 'round', RF.settings[:gutter_profile])

dlg.callbacks['apply_roof'].call(nil, *OLD, 'false', 'round', '6')
ok('but the switch itself really turns it off', RF.settings[:gutter] == false,
   RF.settings[:gutter])

# ================================================= 8. ITS OWN COLOUR ======
# Default is '' - FOLLOW THE FASCIA. Every gutter built before the picker
# existed was painted by the trim pass with the fascia and the drip, and
# that has to stay true for anyone who never opens it.
FASCIA_C = '#eeeeee'
GUTTER_C = '#3b3b3b'

def gutter_faces(r, plain_sig)
  r.entities.grep(Sketchup::Face).reject do |f|
    plain_sig.include?(f.points.map { |p| [p.x.round(3), p.y.round(3), p.z.round(3)] }.sort)
  end
end

base_sig = sig(roof(gutter: false, fascia_color: FASCIA_C))
r1 = roof(gutter: true, gutter_profile: 'box', gutter_width: 5.0,
          fascia_color: FASCIA_C, gutter_color: '')
g1 = gutter_faces(r1, base_sig)
ok('no colour picked -> the gutter is painted with the fascia', 
   !g1.empty? && g1.all? { |f| f.material && f.material.name.include?('eeeeee') },
   g1.map { |f| f.material && f.material.name }.uniq)

r2 = roof(gutter: true, gutter_profile: 'box', gutter_width: 5.0,
          fascia_color: FASCIA_C, gutter_color: GUTTER_C)
g2 = gutter_faces(r2, base_sig)
ok('a picked colour lands on the gutter',
   !g2.empty? && g2.all? { |f| f.material && f.material.name.include?('3b3b3b') },
   g2.map { |f| f.material && f.material.name }.uniq)
rest = r2.entities.grep(Sketchup::Face) - g2
ok('...and on NOTHING else - the fascia keeps its own',
   rest.none? { |f| f.material && f.material.name.include?('3b3b3b') })

r3 = roof(gutter: true, gutter_profile: 'box', gutter_width: 5.0,
          fascia_color: FASCIA_C, gutter_color: '')
ok('clearing it sends the gutter back to the fascia',
   gutter_faces(r3, base_sig).all? { |f| f.material && f.material.name.include?('eeeeee') })
ok('the roof carries the colour it was built with',
   RF.roof_settings(r2)[:gutter_color] == GUTTER_C, RF.roof_settings(r2)[:gutter_color])

InteriorPro::RoofDialog.show
d2 = InteriorPro::RoofDialog.instance_variable_get(:@dialog)
d2.callbacks['apply_roof'].call(nil, *OLD, 'true', 'box', '5', GUTTER_C)
ok('the panel saves the picked colour', RF.settings[:gutter_color] == GUTTER_C,
   RF.settings[:gutter_color])
d2.callbacks['apply_roof'].call(nil, *OLD)
ok('AN OLD CALL LEAVES THE COLOUR ALONE TOO',
   RF.settings[:gutter_color] == GUTTER_C, RF.settings[:gutter_color])

puts($fails.zero? ? 'ALL OK' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

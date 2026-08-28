# encoding: utf-8
# rt85 - A ROOF CARRIES ITS OWN SETTINGS (2026-08-26).
#
# Step 1 of "Edit Roof". The user wants to click a roof and edit THAT roof,
# and he wants a second roof over the lower storey / the ADU. Both are the
# same blocker: one settings hash lives on the MODEL, so there is only ever
# one roof and every Apply rebuilds it from that hash.
#
# This step changes NOTHING that can be seen. It only stamps each roof with
# the settings it was built from, and reads them back. Nothing in
# build_roof! consults them yet - that is the next step - so this suite's
# real job is to prove the stamp is complete, that it round trips, and
# above all that a roof WITHOUT the stamp (every roof in every model the
# user has saved so far) still answers with the model's settings.
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

# THE RAISED HEEL IS OFF IN HERE (2026-09-06). Every z in this suite was
# measured when the roof's underside met the wall top exactly, and the
# eave tail fell slope x overhang BELOW it. He asked for that tail to be
# lifted level with the wall corner instead, which moves every roof up by
# that same amount - so the whole roof, not this suite's subject, would be
# under test. rt118 pins the heel itself; here it stays off, exactly the
# way rt85 already switches off the abut cap.
module InteriorPro
  module RoofManager
    def self.heel_lift(_overhang, _slope, _drop = 0.0)
      0.0
    end
  end
end

# THE ABUT HEIGHT CAP IS OFF IN HERE (2026-08-30). This suite is about
# the settings stamp and the eave end cap, and it builds its shed at
# 6:12 - which over this 153" reach ends 70" above the upper floor, so
# the new cap would flatten it to 4.09:12 and move every number below.
# The cap has its own suite (rt90); switching it off here keeps the two
# apart instead of rewriting numbers the user already approved.
module InteriorPro
  module RoofManager
    def self.abut_headroom
      0.0
    end
  end
end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager

def make_wall(m, id, s, e, level = 1, base = 0.0, height = 96.0)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', s[0])
  w.set_attribute('InteriorPro', 'start_y', s[1])
  w.set_attribute('InteriorPro', 'end_x', e[0])
  w.set_attribute('InteriorPro', 'end_y', e[1])
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-center')
  w.set_attribute('InteriorPro', 'height', height)
  w.set_attribute('InteriorPro', 'base_z', base)
  w.set_attribute('InteriorPro', 'level', level)
  w.set_attribute('InteriorPro', 'wall_category', 'exterior')
  w
end

def a_box(m, prefix = 'w')
  make_wall(m, "#{prefix}S", [0, 0], [300, 0])
  make_wall(m, "#{prefix}E", [300, 0], [300, 200])
  make_wall(m, "#{prefix}N", [300, 200], [0, 200])
  make_wall(m, "#{prefix}W", [0, 200], [0, 0])
end

# ---------------------------------------------------- the key list itself
KEYS = RF.roof_setting_keys
ok('the key list is a METHOD, so reload! re-reads it',
   RF.respond_to?(:roof_setting_keys))
ok('every key is a symbol', KEYS.all? { |k| k.is_a?(Symbol) }, KEYS)
ok('no key is listed twice', KEYS.uniq.length == KEYS.length, KEYS)
# THE ONE THAT MATTERS: a key the panel can set but the roof does not carry
# would come back wrong the moment Edit Roof reads it, and nobody would
# notice until a roof rebuilt itself with somebody else's colour.
model_keys = RF.settings.keys
ok('the roof carries EVERY setting the model holds',
   (model_keys - KEYS).empty?, model_keys - KEYS)
ok('...and invents none of its own', (KEYS - model_keys).empty?, KEYS - model_keys)

# ------------------------------------------------ nothing to read from yet
ok('no group at all -> the model answers', RF.roof_settings(nil) == RF.settings)

# --------------------------------------------------- a real build stamps it
Sketchup.reset_model!
m = Sketchup.active_model
a_box(m)
r = RF.build_roof!(style: 'gable', pitch: 7, overhang: 21, fascia: true,
                   fascia_depth: 9.5, drip: false, soffit: 'wood',
                   soffit_color: '#123456', soffit_slope: true,
                   roof_color: '#334455', fascia_color: '#fafafa',
                   roof_material: 'slate', thickness: 0.0, ridge_cap: false)
ok('the roof builds', !r.nil?)
ok('every key was stamped on the group',
   KEYS.all? { |k| !r.get_attribute('InteriorPro', "set_#{k}").nil? },
   KEYS.reject { |k| r.get_attribute('InteriorPro', "set_#{k}") })

got = RF.roof_settings(r)
ok('the roof reads back the style it was built with', got[:style] == 'gable', got[:style])
ok('...the pitch', got[:pitch] == 7.0, got[:pitch])
ok('...the overhang', got[:overhang] == 21.0, got[:overhang])
ok('...the fascia depth', got[:fascia_depth] == 9.5, got[:fascia_depth])
ok('...the soffit style and its colour',
   got[:soffit] == 'wood' && got[:soffit_color] == '#123456', got)
ok('...the sloped-soffit flag', got[:soffit_slope] == true, got[:soffit_slope])
ok('...the tile', got[:roof_material] == 'slate', got[:roof_material])
ok('...both colours',
   got[:roof_color] == '#334455' && got[:fascia_color] == '#fafafa', got)
# false must survive. It is a real answer, not a missing one - and the
# reader tests nil rather than truthiness for exactly this.
ok('a FALSE setting is remembered as false, not as missing',
   got[:drip] == false && got[:ridge_cap] == false, [got[:drip], got[:ridge_cap]])

# --------------------------------------------- the roof beats the model
# The point of the whole step: two roofs must be able to disagree, so the
# group's own answer has to win over the model's.
RF.save_settings!(RF.settings.merge(style: 'hip', pitch: 3.0,
                                    roof_material: 'shingle'))
again = RF.roof_settings(r)
ok('the roof keeps its OWN style when the model says another',
   again[:style] == 'gable' && RF.settings[:style] == 'hip',
   [again[:style], RF.settings[:style]])
ok('...its own pitch too', again[:pitch] == 7.0 && RF.settings[:pitch] == 3.0,
   [again[:pitch], RF.settings[:pitch]])
ok('...and its own tile', again[:roof_material] == 'slate', again[:roof_material])

# ------------------------------------------------- AN OLD ROOF STILL WORKS
# Every roof in every model the user has saved up to today has no stamp at
# all. It must answer with the model's settings, exactly as it does now -
# no migration, no rebuild, nothing for him to redo.
old = m.entities.add_group
old.set_attribute('InteriorPro', 'type', 'roof')
ok('an unstamped roof answers with the model, key for key',
   RF.roof_settings(old) == RF.settings, RF.roof_settings(old))
# ...and a HALF-stamped one - a roof from a model saved between two of
# these steps - takes what it has and falls back for the rest.
old.set_attribute('InteriorPro', 'set_pitch', 11.0)
half = RF.roof_settings(old)
ok('a half-stamped roof uses what it has', half[:pitch] == 11.0, half[:pitch])
ok('...and falls back for everything else',
   half[:style] == RF.settings[:style] &&
   half[:roof_material] == RF.settings[:roof_material], half)

# ------------------------------------------------------- nothing changed
# The whole promise of step 1: the model still builds exactly as it did.
# Same settings in, same geometry out, with the stamp now on the group.
Sketchup.reset_model!
m2 = Sketchup.active_model
a_box(m2)
r1 = RF.build_roof!(style: 'hip', pitch: 6, overhang: 24, fascia: true,
                    fascia_depth: 8.0, drip: true, soffit: 'boxed',
                    thickness: 0.0, ridge_cap: false)
n1 = r1.entities.grep(Sketchup::Face).length
r2 = RF.build_roof!
ok('a rebuild with no arguments still gives the same roof',
   r2.entities.grep(Sketchup::Face).length == n1,
   [n1, r2.entities.grep(Sketchup::Face).length])
ok('and there is still exactly ONE roof - step 3 is what changes that',
   RF.roofs.length == 1, RF.roofs.length)
ok('the rebuilt roof carries the stamp as well',
   RF.roof_settings(r2)[:soffit] == 'boxed', RF.roof_settings(r2)[:soffit])

# ==================================================================== STEP 2
# WHICH BUILDING THIS ROOF IS: its walls, its gable ends, and the click
# point on each. Settings say what a roof is; these say which one it is.
# A second roof over the ADU is a different set of walls, and the
# model-wide mark list cannot tell two roofs apart - it would gable both
# or neither. Still nothing reads these at build time; step 3 does that.
Sketchup.reset_model!
m3 = Sketchup.active_model
a_box(m3, 'x')
r3 = RF.build_roof!(style: 'hip', pitch: 6, overhang: 24, fascia: true,
                    drip: false, thickness: 0.0, ridge_cap: false)
own = RF.roof_wall_ids(r3)
ok('the roof writes down the walls it sits on',
   own.sort == %w[xE xN xS xW], own)
ok('no id is written twice', own.uniq.length == own.length, own)
ok('with nothing marked it claims no gables', RF.roof_gable_ids(r3).empty?,
   RF.roof_gable_ids(r3))

# mark two ends and rebuild
Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_wall_ids', %w[xS xN])
Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_click_xy',
                                    [150.0, 0.0, 150.0, 200.0])
r4 = RF.build_roof!
ok('the roof writes down its own gable ends',
   RF.roof_gable_ids(r4).sort == %w[xN xS], RF.roof_gable_ids(r4))
ok('...and the click point saved with each one',
   RF.roof_gable_points(r4).length == 2 &&
   RF.roof_gable_points(r4).all? { |p| p.length == 2 },
   RF.roof_gable_points(r4))
# the point has to travel WITH its id, not with its position in the list
i_s = RF.roof_gable_ids(r4).index('xS')
ok('each click point stays with ITS wall',
   RF.roof_gable_points(r4)[i_s] == [150.0, 0.0],
   [RF.roof_gable_ids(r4), RF.roof_gable_points(r4)])

# A MARK ON SOMEBODY ELSE'S WALL IS NOT THIS ROOF'S. This is the whole
# reason the marks move onto the group: with two buildings in one model
# the model-wide list holds both, and each roof must take only its own.
Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_wall_ids',
                                    %w[xS someone_elses_wall])
Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_click_xy',
                                    [150.0, 0.0, 9.0, 9.0])
r5 = RF.build_roof!
ok('a mark on a wall this roof does not own is left out',
   RF.roof_gable_ids(r5) == %w[xS], RF.roof_gable_ids(r5))
ok('...and so is its click point',
   RF.roof_gable_points(r5) == [[150.0, 0.0]], RF.roof_gable_points(r5))

# ---------------------------------------------- who owns this wall
ok('a wall finds its roof', RF.roof_of_wall_id('xS') == r5,
   RF.roof_of_wall_id('xS'))
ok('a wall no roof covers finds none', RF.roof_of_wall_id('nobody').nil?)
ok('nil finds none', RF.roof_of_wall_id(nil).nil?)

# ------------------------------------------------- old roofs, again
old2 = m3.entities.add_group
old2.set_attribute('InteriorPro', 'type', 'roof')
ok('an unstamped roof claims no walls', RF.roof_wall_ids(old2).empty?,
   RF.roof_wall_ids(old2))
ok('...but still reads the MODEL gable marks, as it always did',
   RF.roof_gable_ids(old2) == RF.gable_wall_ids, RF.roof_gable_ids(old2))
ok('...and the model click points with them',
   RF.roof_gable_points(old2) == RF.gable_click_points,
   RF.roof_gable_points(old2))
ok('no group at all is safe too',
   RF.roof_wall_ids(nil).empty? && RF.roof_gable_ids(nil) == RF.gable_wall_ids)

# ==================================================================== STEP 3
# A REBUILD REPLACES ONLY WHAT IT IS REBUILDING. The one line that erased
# every roof on every build is what kept this plugin at one roof; now it
# erases the named roof (`replace:`) or the storey's (`level:`), and the
# plain no-argument call still clears everything, as every old caller and
# console line expects.
Sketchup.reset_model!
m4 = Sketchup.active_model
# storey 1: the big box. storey 2: a smaller box on top of it.
make_wall(m4, 'aS', [0, 0], [400, 0], 1)
make_wall(m4, 'aE', [400, 0], [400, 240], 1)
make_wall(m4, 'aN', [400, 240], [0, 240], 1)
make_wall(m4, 'aW', [0, 240], [0, 0], 1)
make_wall(m4, 'bS', [60, 40], [300, 40], 2, 96.0)
make_wall(m4, 'bE', [300, 40], [300, 200], 2, 96.0)
make_wall(m4, 'bN', [300, 200], [60, 200], 2, 96.0)
make_wall(m4, 'bW', [60, 200], [60, 40], 2, 96.0)

top = RF.build_roof!(style: 'gable', pitch: 8, thickness: 0.0, ridge_cap: false)
ok('the default build still lands on the TOP storey',
   top.get_attribute('InteriorPro', 'level') == 2 &&
   RF.roof_wall_ids(top).sort == %w[bE bN bS bW],
   [top.get_attribute('InteriorPro', 'level'), RF.roof_wall_ids(top)])

low = RF.build_roof!(level: 1, style: 'hip', pitch: 4, thickness: 0.0,
                     ridge_cap: false)
ok('level: builds over the LOWER storey walls',
   RF.roof_wall_ids(low).sort == %w[aE aN aS aW], RF.roof_wall_ids(low))
ok('its eave starts at that storey wall top',
   (low.get_attribute('InteriorPro', 'eave_z').to_f - 96.0).abs < 0.01,
   low.get_attribute('InteriorPro', 'eave_z'))
ok('TWO ROOFS NOW STAND - the upper one survived',
   RF.roofs.length == 2 && top.valid?, RF.roofs.length)

low2 = RF.build_roof!(level: 1, pitch: 5)
ok('rebuilding a storey replaces ITS roof only',
   RF.roofs.length == 2 && top.valid? && !low.valid?, RF.roofs.length)
ok('...keeping that roof own style from its stamp',
   RF.roof_settings(low2)[:style] == 'hip' && RF.roof_settings(low2)[:pitch] == 5.0,
   RF.roof_settings(low2).values_at(:style, :pitch))

# replace: = Edit Roof's Apply. Its settings are the base, keywords override.
top2 = RF.build_roof!(replace: top, roof_material: 'seam')
ok('replace: rebuilds the named roof only',
   RF.roofs.length == 2 && low2.valid? && !top.valid?, RF.roofs.length)
ok('...on its own storey without being told',
   top2.get_attribute('InteriorPro', 'level') == 2,
   top2.get_attribute('InteriorPro', 'level'))
ok('...from its OWN settings plus the override',
   RF.roof_settings(top2)[:style] == 'gable' &&
   RF.roof_settings(top2)[:pitch] == 8.0 &&
   RF.roof_settings(top2)[:roof_material] == 'seam',
   RF.roof_settings(top2).values_at(:style, :pitch, :roof_material))
ok('a dead group as replace: is just a plain build, not a crash',
   !RF.build_roof!(replace: top).nil?, RF.roofs.length)
RF.roofs.each { |r| r.erase! } # the line above rebuilt everything; clean up

# --------------------------------------- the gable click follows its roof
r_top = RF.build_roof!(style: 'hip', thickness: 0.0, ridge_cap: false)
r_low = RF.build_roof!(level: 1, style: 'hip', thickness: 0.0, ridge_cap: false)
wS = m4.entities.grep(Sketchup::Group).find do |g|
  g.get_attribute('InteriorPro', 'id') == 'aS'
end
RF.toggle_gable_wall!(wS, [200.0, 0.0])
ok('a gable click rebuilds the roof that OWNS the wall',
   RF.roofs.length == 2 && r_top.valid? && !r_low.valid?,
   [RF.roofs.length, r_top.valid?])
r_low2 = RF.roofs.find { |r| r != r_top }
ok('...and that roof carries the new mark',
   RF.roof_gable_ids(r_low2) == %w[aS], RF.roof_gable_ids(r_low2))
ok('...while the other roof carries none',
   RF.roof_gable_ids(r_top).empty?, RF.roof_gable_ids(r_top))

# ------------------------------------------- the old call still means ALL
plain = RF.build_roof!
ok('a plain build_roof! still clears the board and leaves one roof',
   RF.roofs.length == 1 && plain.valid?, RF.roofs.length)

# ==================================================================== STEP 3b
# THE LOWER ROOF STOPS WHERE THE HOUSE ABOVE STANDS (2026-08-26, user:
# "הוא בנה על כל הקומה כולל בתוך הבית"). The upper wall that crosses the
# storey (the divider) cuts the loop: the roof gets no overhang there
# (it tucks into the wall body), no fascia/soffit, and rises AWAY from
# the wall like a shed. Upper walls merely stacked on the storey's own
# walls change nothing - only a crossing wall divides.
Sketchup.reset_model!
m5 = Sketchup.active_model
make_wall(m5, 'cS', [0, 0], [400, 0], 1)
make_wall(m5, 'cE', [400, 0], [400, 240], 1)
make_wall(m5, 'cN', [400, 240], [0, 240], 1)
make_wall(m5, 'cW', [0, 240], [0, 0], 1)
# the upper house on the back part, stacked on E/N/W, crossing at y=140
make_wall(m5, 'uS', [0, 140], [400, 140], 2, 96.0)
make_wall(m5, 'uE', [400, 140], [400, 240], 2, 96.0)
make_wall(m5, 'uN', [400, 240], [0, 240], 2, 96.0)
make_wall(m5, 'uW', [0, 240], [0, 140], 2, 96.0)

up_r = RF.build_roof!(style: 'hip', pitch: 6, overhang: 12, thickness: 0.0,
                      ridge_cap: false)
ok('the top roof is untouched by any of this',
   RF.roof_wall_ids(up_r).sort == %w[uE uN uS uW], RF.roof_wall_ids(up_r))

low_r = RF.build_roof!(level: 1)
ok('the lower roof builds at all', !low_r.nil?)
fx = low_r.get_attribute('InteriorPro', 'footprint_xy').each_slice(2).to_a
ok('it stops at the divider, not at the back of the storey',
   fx.map { |p| p[1] }.max < 150.0, fx.map { |p| p[1] }.max)
# ON THE WALL FACE, not an inch inside it (2026-09-01). It used to stop
# an inch in, to bury the end cuts; the user could see the shingles
# vanish into the stucco and asked for that inch back ("הגג נכנס לתוך
# הקיר של הקומה השניה באינץ... תחזיר אותו אינץ אחורה"). The wrap was
# taken off the abut corners in the same breath, so nothing pokes out
# there either - RoofManager::ABUT_TUCK is the one number that says so.
ok('...ON the wall exposed face, so nothing pokes into the stucco',
   (fx.map { |p| p[1] }.max - 137.0).abs < 0.5, fx.map { |p| p[1] }.max)
ok('...with its eaves still pushed out on its own three sides',
   fx.map { |p| p[1] }.min < -14.0 &&
   (fx.map { |p| p[0] }.min - -15.0).abs < 0.01 &&
   (fx.map { |p| p[0] }.max - 415.0).abs < 0.01, fx)
ok('the divider wall is NOT one of this roof walls',
   !RF.roof_wall_ids(low_r).include?('uS'), RF.roof_wall_ids(low_r))
ok('so a click on the divider finds the roof ABOVE',
   RF.roof_of_wall_id('uS') == up_r)
ok('both roofs stand', RF.roofs.length == 2 && up_r.valid?, RF.roofs.length)
# the shed: highest along the wall, never above the upper storey walls
zs5 = low_r.entities.grep(Sketchup::Face).flat_map(&:pts)
zmax_at_wall = zs5.select { |p| p.y > 130 }.map(&:z).max
zmax_out     = zs5.select { |p| p.y < 20 }.map(&:z).max
ok('the cut roof RISES toward the upper wall', zmax_at_wall > zmax_out + 30.0,
   [zmax_at_wall, zmax_out])
ok('...but stays below the upper storey top', zmax_at_wall < 192.0, zmax_at_wall)

# THE EAVE END CAP (2026-08-26B, the user's red circle): where a normal
# eave dies against the upper wall, its open cross section - the part of
# it standing outside that wall - is closed by a vertical plate in the
# abut plane, from the wall line out to the fascia's inner face, fascia
# bottom up to the roof underside.
low_cap = RF.build_roof!(level: 1, soffit: 'spanish', soffit_slope: true)
caps = low_cap.entities.grep(Sketchup::Face).select do |f|
  f.pts.all? { |p| (p.y - 137.0).abs < 0.05 } && f.pts.map(&:z).max > 89.0
end
ok('the eave gets an end cap at BOTH corners against the wall',
   caps.length == 2, caps.length)
ok('...spanning the overhang zone outside the wall face',
   caps.all? { |f| (f.pts.map(&:z).min - 82.0).abs < 0.5 &&
                   (f.pts.map(&:z).max - 96.0).abs < 0.5 },
   caps.map { |f| f.pts.map(&:z).minmax })
# the cap is a piece of the fascia: its colour, and with a SLOPED soffit
# its bottom climbs with the board - a tilted band, not a hanging plate
# (user 2026-08-26B). Rise here = 0.5 * 12 = 6.0 at the wall: measured
# from the ROOF EDGE, not from the fascia's inner face (2026-08-27, so
# the board meets the rake soffit at the gable corner).
ok('the cap wears the fascia colour', caps.all?(&:material), caps.length)
ok('...and its bottom climbs with the sloped soffit',
   caps.all? { |f| f.pts.any? { |p| (p.z - 88.0).abs < 0.3 } },
   caps.map { |f| f.pts.map(&:z).sort })

# THE CORNER LOOKOUT GOES WITH A SLOPED SOFFIT (2026-08-26B, the user's
# second red circle: "בפינה נשארה שארית כזאת - תוריד אותה"). The eave
# tails tilt up toward the wall; the horizontal lookout nearest each rake
# corner stays put and shows as a stray stub, so it is culled - ONLY when
# the slope is on. Level soffits keep the approved look untouched.
Sketchup.reset_model!
m5b = Sketchup.active_model
make_wall(m5b, 'gS', [0, 0], [240, 0], 1)
make_wall(m5b, 'gE', [240, 0], [240, 120], 1)
make_wall(m5b, 'gN', [240, 120], [0, 120], 1)
make_wall(m5b, 'gW', [0, 120], [0, 0], 1)
flat_n = RF.build_roof!(style: 'gable', pitch: 4, overhang: 12,
                        soffit: 'spanish', soffit_slope: false,
                        thickness: 0.0, ridge_cap: false)
              .entities.grep(Sketchup::Face).length
slop_n = RF.build_roof!(soffit_slope: true).entities.grep(Sketchup::Face).length
# 4 corner lookouts of 16 faces (64) plus the 4 corner steps and 4 skirts
# (8) = 72. A round that ALSO capped the gable corners was reverted the
# same day - it put back the very shape this cull removes.
ok('sloped soffit culls the corner lookouts and the corner closures',
   flat_n - slop_n == 72, [flat_n, slop_n])

# an L-shaped exposed part: the upper house only covers part of the width
Sketchup.reset_model!
m6 = Sketchup.active_model
make_wall(m6, 'dS', [0, 0], [400, 0], 1)
make_wall(m6, 'dE', [400, 0], [400, 240], 1)
make_wall(m6, 'dN', [400, 240], [0, 240], 1)
make_wall(m6, 'dW', [0, 240], [0, 0], 1)
make_wall(m6, 'vS', [0, 140], [250, 140], 2, 96.0)
make_wall(m6, 'vE', [250, 140], [250, 240], 2, 96.0)
make_wall(m6, 'vN', [250, 240], [0, 240], 2, 96.0)
make_wall(m6, 'vW', [0, 240], [0, 140], 2, 96.0)
RF.build_roof!(style: 'hip', pitch: 6, overhang: 12, thickness: 0.0,
               ridge_cap: false)
low_l = RF.build_roof!(level: 1)
ok('an L-shaped exposed part still builds', !low_l.nil?)
fxl = low_l.get_attribute('InteriorPro', 'footprint_xy').each_slice(2).to_a
ok('...as an L: six corners', fxl.length == 6, fxl.length)
ok('...cut on BOTH dividers, on each wall face',
   fxl.any? { |p| (p[1] - 137.0).abs < 0.5 } &&
   fxl.any? { |p| (p[0] - 253.0).abs < 0.5 }, fxl)

# nothing above -> nothing changes: the plain full loop, as always
Sketchup.reset_model!
m7 = Sketchup.active_model
a_box(m7, 'e')
solo = RF.build_roof!(style: 'hip', overhang: 12, thickness: 0.0, ridge_cap: false)
fx7 = solo.get_attribute('InteriorPro', 'footprint_xy').each_slice(2).to_a
ok('a storey with nothing above keeps its full loop',
   (fx7.map { |p| p[1] }.min - -15.0).abs < 0.01 &&
   (fx7.map { |p| p[1] }.max - 215.0).abs < 0.01, fx7.map { |p| p[1] }.minmax)

# ==================================================================== STEP 4
# THE EDIT PANEL. RoofDialog.show(roof) opens the panel ON that roof: its
# own settings fill the controls, Apply rebuilds it alone (and keeps
# following the new group, so a second Apply from the same panel works),
# and Remove erases it alone. The plain panel keeps its old life, except
# that its Apply now scopes to the top storey - a lower roof survives it.
require './roof_dialog'
Sketchup.reset_model!
m8 = Sketchup.active_model
make_wall(m8, 'fS', [0, 0], [400, 0], 1)
make_wall(m8, 'fE', [400, 0], [400, 240], 1)
make_wall(m8, 'fN', [400, 240], [0, 240], 1)
make_wall(m8, 'fW', [0, 240], [0, 0], 1)
make_wall(m8, 'gS', [0, 140], [400, 140], 2, 96.0)
make_wall(m8, 'gE', [400, 140], [400, 240], 2, 96.0)
make_wall(m8, 'gN', [400, 240], [0, 240], 2, 96.0)
make_wall(m8, 'gW', [0, 240], [0, 140], 2, 96.0)
up8 = RF.build_roof!(style: 'gable', pitch: 8, thickness: 0.0, ridge_cap: false)
lo8 = RF.build_roof!(level: 1, style: 'hip', pitch: 4, thickness: 0.0,
                     ridge_cap: false)

InteriorPro::RoofDialog.show(lo8)
dlg = InteriorPro::RoofDialog.instance_variable_get(:@dialog)
html = InteriorPro::RoofDialog.build_html(RF.roof_settings(lo8))
ok('the edit panel opens with THE ROOF pitch, not the model one',
   html.include?('<option value="4" selected>'), html[/<option value="4"[^>]*>/])
# Apply from the edit panel: pitch 5, everything else as the panel showed
dlg.callbacks['apply_roof'].call(nil, 'hip', '5', 'true', '12', 'true', '8',
                                 'true', '#111111', '#eeeeee', 'color', '0',
                                 'false', 'none', '', 'false')
ok('edit Apply rebuilt the low roof alone',
   RF.roofs.length == 2 && up8.valid? && !lo8.valid?,
   [RF.roofs.length, up8.valid?, lo8.valid?])
lo8b = RF.roofs.find { |r| r != up8 }
ok('...with the new pitch on it', RF.roof_settings(lo8b)[:pitch] == 5.0,
   RF.roof_settings(lo8b)[:pitch])
ok('...and the upper roof still has its own',
   RF.roof_settings(up8)[:pitch] == 8.0, RF.roof_settings(up8)[:pitch])
# the panel follows the new group: a SECOND Apply must hit it again
dlg.callbacks['apply_roof'].call(nil, 'hip', '6', 'true', '12', 'true', '8',
                                 'true', '#111111', '#eeeeee', 'color', '0',
                                 'false', 'none', '', 'false')
ok('a second Apply from the same open panel still edits the same roof',
   RF.roofs.length == 2 && up8.valid? && !lo8b.valid?, RF.roofs.length)
# Remove from the edit panel: this roof only
dlg.callbacks['remove_roof'].call(nil)
ok('edit Remove erases the edited roof alone',
   RF.roofs == [up8], RF.roofs.length)

# the PLAIN panel: its Apply is scoped to the top storey now
lo9 = RF.build_roof!(level: 1, style: 'hip', pitch: 4, thickness: 0.0,
                     ridge_cap: false)
InteriorPro::RoofDialog.show
dlg2 = InteriorPro::RoofDialog.instance_variable_get(:@dialog)
dlg2.callbacks['apply_roof'].call(nil, 'gable', '9', 'true', '12', 'true', '8',
                                  'true', '#111111', '#eeeeee', 'color', '0',
                                  'false', 'none', '', 'false')
ok('the plain panel Apply rebuilds the TOP roof and spares the lower one',
   RF.roofs.length == 2 && lo9.valid? && !up8.valid?,
   [RF.roofs.length, lo9.valid?])
ok('...and the top pitch went where it was aimed',
   RF.roofs.reject { |r| r == lo9 }.map { |r| RF.roof_settings(r)[:pitch] } == [9.0],
   RF.roofs.map { |r| RF.roof_settings(r)[:pitch] })

# ==================================================================== STEP 5
# THE STOREY PICKER (user: "איך אני בוחר קומה ראשונה או שניה או שניהם?").
# A 16th argument on apply_roof: a storey number, 'all', or nothing -
# and nothing is the top storey, which is every call made before today.
html_p = InteriorPro::RoofDialog.build_html(RF.settings)
ok('two storeys -> the picker is drawn', html_p.include?('id="roofLevel"'))
ok('...All storeys preselected (user 2026-08-26)',
   html_p.include?('<option value="all" selected>'))
ok('...with an all-storeys choice', html_p.include?('value="all"'))
html_e = InteriorPro::RoofDialog.build_html(RF.settings, edit: true)
ok('the EDIT panel has no picker - its roof knows its storey',
   !html_e.include?('id="roofLevel"'))

# storey 1 by number
dlg2.callbacks['apply_roof'].call(nil, 'hip', '4', 'true', '12', 'true', '8',
                                  'true', '#111111', '#eeeeee', 'color', '0',
                                  'false', 'none', '', 'false', '1')
ok('picking storey 1 rebuilds the LOWER roof alone',
   RF.roofs.length == 2 &&
   RF.roofs.count { |r| r.get_attribute('InteriorPro', 'level') == 1 } == 1,
   RF.roofs.map { |r| r.get_attribute('InteriorPro', 'level') })

# 'all' = one roof per storey
RF.roofs.each(&:erase!)
dlg2.callbacks['apply_roof'].call(nil, 'hip', '4', 'true', '12', 'true', '8',
                                  'true', '#111111', '#eeeeee', 'color', '0',
                                  'false', 'none', '', 'false', 'all')
ok("'all' builds one roof per storey from nothing",
   RF.roofs.map { |r| r.get_attribute('InteriorPro', 'level') }.sort == [1, 2],
   RF.roofs.map { |r| r.get_attribute('InteriorPro', 'level') })
lower_all = RF.roofs.find { |r| r.get_attribute('InteriorPro', 'level') == 1 }
fx_all = lower_all.get_attribute('InteriorPro', 'footprint_xy').each_slice(2).to_a
ok('...and the lower one is still cut at the storey above',
   fx_all.map { |p| p[1] }.max < 150.0, fx_all.map { |p| p[1] }.max)

# a model with ONE storey draws no picker at all
Sketchup.reset_model!
m9 = Sketchup.active_model
a_box(m9, 'h')
ok('one storey -> no picker row',
   !InteriorPro::RoofDialog.build_html(RF.settings).include?('id="roofLevel"'))

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

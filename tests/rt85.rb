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

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

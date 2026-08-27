# encoding: utf-8
# rt103 - DORMERS SURVIVE A ROOF REBUILD (2026-09-02).
#
# WHY
# A dormer is built INTO its roof's group, and RoofManager rebuilds a
# roof by ERASING that whole group. So until today one Apply in the roof
# panel silently took every dormer with it - the user was told about the
# trap the moment it was found, and this is the fix pinned down.
#
# THE CLAIMS PINNED HERE
# 1. HARVEST reads a dormer off a roof about to be erased: its sizes,
#    and the plan point it stood over.
# 2. IT DROPS THE OLD FRAME. z0, slope, the base and the two axes all go,
#    because the NEW roof supplies its own - which is what makes a
#    dormer come back sitting on a changed pitch instead of floating
#    over the shape of the roof that used to be there.
# 3. REPLANT puts it back by PLACING it again, so everything the placing
#    click checks is checked again.
# 4. ONE THAT NO LONGER FITS IS NOT PUT BACK, and says so, instead of
#    being built through the new ridge.
# 5. A ROOF WITH NO DORMERS harvests nothing and costs nothing.
#
# Against yesterday's code claims 1-4 fail: there was nothing to call.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def close(a, b, tol = 0.01)
  !a.nil? && !b.nil? && (a - b).abs < tol
end

DM = InteriorPro::DormerManager
Z0 = 100.0
SLOPE = 8.0 / 12.0

def make_roof(m, z0, slope, len = 400.0)
  r = m.entities.add_group
  r.set_attribute('InteriorPro', 'type', 'roof')
  tp = lambda { |x, y| Geom::Point3d.new(x, y, z0 + y * slope) }
  top = [tp.call(-200, 0), tp.call(200, 0), tp.call(200, len), tp.call(-200, len)]
  r.entities.add_face(top)
  r.entities.add_face(top.map { |p| Geom::Point3d.new(p.x, p.y, p.z - 0.5) })
  r
end

Sketchup.reset_model!
m = Sketchup.active_model
roof = make_roof(m, Z0, SLOPE)
DM.save_settings!(width: 48.0, length: 96.0, setback: 36.0, overhang: 6.0,
                  pitch12: 0.0, fascia_depth: 0.0, height: 0.0, style: 'gable')
g = DM.place_on_roof!(roof, 0.0, 120.0, DM.spec_from_settings)
ok('a dormer stands on the roof', !g.nil?)

# ---- 1 + 2. HARVEST ---------------------------------------------------
saved = DM.harvest([roof])
ok('it is harvested off the roof', saved.length == 1, saved.length)
d = saved.first
ok('...with its sizes', d && close(d[:spec][:width], 48.0) &&
   close(d[:spec][:setback], 36.0), d && d[:spec])
ok('...and the plan point it stood over',
   d && close(d[:y], 36.0 + 96.0 / 2.0, 1.0), d && [d[:x], d[:y]])
ok('IT KEEPS ITS HEIGHT, not its length - the new pitch decides the reach',
   d[:spec].key?(:height) && !d[:spec].key?(:length),
   [d[:spec][:height], d[:spec][:length]])
ok('THE OLD FRAME IS DROPPED - the new roof supplies its own',
   %i[z0 slope base along into z_top].none? { |k| d[:spec].key?(k) },
   d[:spec].keys.sort)

# ---- 3. REPLANT -------------------------------------------------------
Sketchup.reset_model!
m2 = Sketchup.active_model
roof2 = make_roof(m2, Z0, SLOPE)
back = DM.replant!(roof2, saved)
ok('it is put back on the new roof', back == 1, back)
found = roof2.entities.grep(Sketchup::Group)
             .select { |x| x.get_attribute('InteriorPro', 'type') == 'dormer' }
ok('...as a real dormer inside that roof', found.length == 1, found.length)
sp2 = DM.dormer_spec(found.first)
ok('...at the same setback, the same size',
   close(sp2[:setback], 36.0, 0.5) && close(sp2[:width], 48.0),
   [sp2[:setback], sp2[:width]])

# a roof with a DIFFERENT pitch: it comes back on the new slope
Sketchup.reset_model!
m3 = Sketchup.active_model
roof3 = make_roof(m3, Z0, 4.0 / 12.0)
ok('a changed pitch still takes it back', DM.replant!(roof3, saved) == 1)
sp3 = DM.dormer_spec(roof3.entities.grep(Sketchup::Group)
                          .find { |x| x.get_attribute('InteriorPro', 'type') == 'dormer' })
ok('...and it sits on the NEW slope, not the old one',
   close(sp3[:slope], 4.0 / 12.0, 0.001), sp3[:slope])

# ---- 4. IT STAYS, EVEN IF IT HAS TO COME DOWN ------------------------
# (2026-09-02, the user: "אם אני משנה זווית לגג הוא נעלם, אני צריך
# שהוא יישאר איך שהוא")
Sketchup.reset_model!
m4 = Sketchup.active_model
short = make_roof(m4, Z0, SLOPE, 130.0)  # not enough run for the full height
ok('a roof too short for it does NOT throw it away', DM.replant!(short, saved) == 1)
kept = short.entities.grep(Sketchup::Group)
            .find { |x| x.get_attribute('InteriorPro', 'type') == 'dormer' }
ok('...it is really there', !kept.nil?)
h4 = kept && kept.get_attribute('InteriorPro', 'height').to_f
ok('...brought down to what fits, not left at the old height',
   h4 && h4 >= DM::MIN_FACE_HEIGHT && h4 < saved.first[:spec][:height].to_f, h4)
ok('...and it keeps its width', close(DM.dormer_spec(kept)[:width], 48.0))

# only a roof that cannot hold even the shortest one loses it
Sketchup.reset_model!
m4b = Sketchup.active_model
tiny = make_roof(m4b, Z0, SLOPE, 50.0)
ok('a roof that can hold no dormer at all says so', DM.replant!(tiny, saved).zero?)
ok('...and is left clean, with no half dormer in it',
   tiny.entities.grep(Sketchup::Group)
       .none? { |x| x.get_attribute('InteriorPro', 'type') == 'dormer' })

# ---- 5. NOTHING TO DO -------------------------------------------------
Sketchup.reset_model!
m5 = Sketchup.active_model
bare = make_roof(m5, Z0, SLOPE)
ok('a roof with no dormers harvests nothing', DM.harvest([bare]).empty?)
ok('replanting nothing does nothing', DM.replant!(bare, []).zero?)
ok('...and neither does replanting onto nothing', DM.replant!(nil, saved).zero?)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

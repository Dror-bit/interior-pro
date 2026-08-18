# encoding: utf-8
# rt64 - landscape/garden_wall_tool.rb: the garden wall (חומה), step 1, the body.
#
# What has to be proved before he looks at it in SketchUp:
#
#   * it is stored under LandscapePro, NOT InteriorPro - because everything in
#     the plugin that hunts for building walls (rooms, floors, molding, roofs,
#     the 2D plan, the wall edit/move/split tools) finds them by exactly the
#     'InteriorPro' dictionary and type 'wall'. This is THE thing that keeps a
#     garden wall out of the house.
#   * the solid lands where he clicked: centred on the line, the right
#     thickness across, the right height up - whichever way he drew it.
#   * it is built UP, not down into the ground, no matter the click order.
#   * the finish is painted on every face but the underside.
#   * a mis-click builds nothing and does not raise.
require './sketchup_stub'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

$magnet_calls = 0
module InteriorPro
  PLUGIN_DIR = File.expand_path('..', __dir__) unless const_defined?(:PLUGIN_DIR)
  module WallTool
    def self.apply_axis_magnet(a, b, _model = nil)
      $magnet_calls += 1
      [a, b]
    end
  end
  $tags = []
  def self.assign_tag(_e, name); $tags << name; true; end
end

require './garden_wall_tool'
GW = InteriorPro::Landscape::GardenWallTool

def pt(x, y); Geom::Point3d.new(x, y, 0); end
def fresh(t = 8.0, h = 36.0, m = 'Stucco', cw = 0.0, ch = 0.0, cm = 'Stucco',
          mode = 'Continuous', unit = 24.0, joint = 0.25, nose = 'None',
          over = 'Both sides', line = false)
  Sketchup.reset_model!
  $magnet_calls = 0
  $tags = []
  GW.new(t, h, m, cw, ch, cm, mode, unit, joint, nose, over, line)
end
def line_of(g)
  g.entities.grep(Sketchup::Group)
   .find { |x| x.get_attribute('LandscapePro', 'type') == 'garden_wall_back_line' }
end
def cap_of(g)
  g.entities.grep(Sketchup::Group).find { |x| x.name == 'LandscapePro_GardenWallCap' }
end
def stones_of(g)
  c = cap_of(g)
  c ? c.entities.grep(Sketchup::Group).sort_by { |x| x.name } : []
end
# Since the bullnose (step 3) a cap piece is its CROSS-SECTION extruded along
# the wall: the face stands at the piece's start, and how long the piece is
# comes out of the pushpull, not out of the face.
def sect(g)
  g.entities.grep(Sketchup::Face).first
end
def run_len(g)
  sect(g).pushpulls.first.abs
end
# Where a stone sits along a wall drawn down the x axis: start .. start+length.
def x_span(stone)
  x0 = sect(stone).points.map(&:x).min
  [x0, x0 + run_len(stone)]
end
def walls
  Sketchup.active_model.entities.grep(Sketchup::Group)
          .select { |g| g.get_attribute('LandscapePro', 'type') == 'garden_wall' }
end

# --------------------------------------------------- the footprint, as numbers

t = fresh(8.0, 36.0)
fp = t.footprint(pt(0, 0), pt(120, 0))
ok('four floor corners', fp.length == 4, fp.length)
ok('the wall is CENTRED on the line - 4" each side of a 8" wall',
   fp.map { |p| p.y.round(6) }.sort == [-4.0, -4.0, 4.0, 4.0],
   fp.map { |p| [p.x.round(2), p.y.round(2)] })
ok('it runs the full length he clicked',
   fp.map { |p| p.x.round(6) }.sort == [0.0, 0.0, 120.0, 120.0],
   fp.map(&:x))
ok('the footprint sits on the ground', fp.all? { |p| close(p.z, 0.0) }, fp.map(&:z))

# Drawn the other way round, the wall must occupy the SAME ground.
back = t.footprint(pt(120, 0), pt(0, 0))
ok('drawing it right-to-left covers the same ground',
   back.map { |p| [p.x.round(4), p.y.round(4)] }.sort ==
   fp.map { |p| [p.x.round(4), p.y.round(4)] }.sort,
   back.map { |p| [p.x.round(2), p.y.round(2)] })

# On a diagonal the thickness is measured ACROSS the run, not along the axes.
d = t.footprint(pt(0, 0), pt(100, 100))
mid_a = Geom::Point3d.new((d[0].x + d[3].x) / 2.0, (d[0].y + d[3].y) / 2.0, 0)
ok('a diagonal wall still starts on the line he clicked',
   close(mid_a.x, 0.0, 1e-9) && close(mid_a.y, 0.0, 1e-9), [mid_a.x, mid_a.y])
w = Math.sqrt((d[0].x - d[3].x)**2 + (d[0].y - d[3].y)**2)
ok('a diagonal wall is 8" thick across the run, not 8" in x', close(w, 8.0, 1e-9), w)

ok('a zero-length line has no footprint', t.footprint(pt(5, 5), pt(5, 5)).nil?)

# A thicker wall is thicker, and the thickness comes from the tool.
ok('thickness follows the setting',
   begin
     f2 = fresh(16.0).footprint(pt(0, 0), pt(50, 0))
     close((f2[0].y - f2[3].y).abs, 16.0, 1e-9)
   end)

# ---------------------------------------------------------------- building it

t = fresh(8.0, 36.0, 'Stucco')
g = t.build!(pt(0, 0), pt(120, 0))
ok('a group is created', !g.nil?)
ok('there is exactly one garden wall in the model', walls.length == 1, walls.length)
ok('it carries the Landscape Pro group name',
   g.name == 'LandscapePro_GardenWall', g.name)
ok('it is tagged LP/Walls', $tags.first == 'LP/Walls', $tags)

# THE important one.
ok('type garden_wall lives under the LandscapePro dictionary',
   g.get_attribute('LandscapePro', 'type') == 'garden_wall',
   g.get_attribute('LandscapePro', 'type'))
ok('NOTHING is written under InteriorPro - the house tools must never see it',
   g.get_attribute('InteriorPro', 'type').nil?,
   g.get_attribute('InteriorPro', 'type'))
ok('it is not called a wall anywhere',
   g.get_attribute('LandscapePro', 'type') != 'wall')

ok('thickness stored', close(g.get_attribute('LandscapePro', 'thickness'), 8.0))
ok('height stored',    close(g.get_attribute('LandscapePro', 'height'), 36.0))
ok('finish stored',    g.get_attribute('LandscapePro', 'material') == 'Stucco')
ok('both ends stored', close(g.get_attribute('LandscapePro', 'start_x'), 0.0) &&
                       close(g.get_attribute('LandscapePro', 'end_x'), 120.0))
ok('length stored',    close(g.get_attribute('LandscapePro', 'length_in'), 120.0))
ok('BOTH ground numbers are stored, ready for terrain',
   g.get_attribute('LandscapePro', 'ground_start') == 0.0 &&
   g.get_attribute('LandscapePro', 'ground_end') == 0.0)

faces = g.entities.grep(Sketchup::Face)
ok('one footprint face was drawn', faces.length == 1, faces.length)
ok('with no cap asked for, no cap group was made', cap_of(g).nil?)
f = faces.first
ok('it was pushed exactly once', f.pushpulls.length == 1, f.pushpulls)
# The sign has to come out positive-upwards WHICHEVER way the face happened
# to face. That is the whole point of asking face.normal instead of assuming.
signed = f.pushpulls.first * (f.normal.z < 0 ? -1.0 : 1.0)
ok('the wall was pushed UP by its height, not down into the ground',
   close(signed, 36.0, 1e-9), [f.pushpulls.first, f.normal.z])

# Drawn the other way, it still goes up.
t = fresh(8.0, 36.0)
g2 = t.build!(pt(120, 40), pt(0, 40))
f2 = g2.entities.grep(Sketchup::Face).first
signed2 = f2.pushpulls.first * (f2.normal.z < 0 ? -1.0 : 1.0)
ok('drawn right-to-left it STILL goes up', close(signed2, 36.0, 1e-9),
   [f2.pushpulls.first, f2.normal.z])

# ------------------------------------------------------------------- finishes

t = fresh(8.0, 36.0, 'Stucco')
g = t.build!(pt(0, 0), pt(120, 0))
painted = g.entities.grep(Sketchup::Face).reject { |x| x.material.nil? }
ok('the finish was painted', painted.length >= 1, painted.length)
ok('the material is namespaced so it cannot collide with a house material',
   painted.first.material.name == 'LandscapePro_Stucco', painted.first.material.name)
ok('back_material is cleared', painted.all? { |x| x.back_material.nil? })

# A finish with no .jpg yet must still come out looking like something.
ok('a finish with no texture file gets a stand-in colour, not flat white',
   begin
     m = GW.finish_material('Stack Stone')
     !m.nil? && (!m.color.nil? || !m.texture.nil?)
   end)
ok('every listed finish can be made',
   GW::MATERIALS.all? { |n| !GW.finish_material(n).nil? }, GW::MATERIALS)
ok('the same finish is reused, not remade',
   GW.finish_material('Stucco').equal?(GW.finish_material('Stucco')))
ok('his list is his own, not the house wall list',
   GW::MATERIALS == ['Stucco', 'Stack Stone', 'Block Wall'], GW::MATERIALS)


# ------------------------------------------------------------------- the cap
#
# His words (2026-08-17): the cap is given as a WIDTH, side to side - "האם זה
# פיט אחד או 6" או 4"" - not as an overhang. And cap thickness 0 is the off
# switch; there is no separate checkbox.

t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stack Stone')
ok('cap? is true when both numbers are given', t.cap?)
g = t.build!(pt(0, 0), pt(120, 0))
cap = cap_of(g)
ok('the cap is its own nested group, so it cannot merge into the wall', !cap.nil?)
ok('the wall body is still one face - the cap did not land in it',
   g.entities.grep(Sketchup::Face).length == 1,
   g.entities.grep(Sketchup::Face).length)

cf = cap.entities.grep(Sketchup::Face)
ok('the cap has its own footprint face', cf.length == 1, cf.length)
capf = cf.first
ok('the cap SITS ON the wall: its section runs 36" to 38"',
   close(capf.points.map(&:z).min, 36.0, 1e-9) &&
   close(capf.points.map(&:z).max, 38.0, 1e-9),
   [capf.points.map(&:z).min, capf.points.map(&:z).max])
ok('the cap is 2" thick', close(capf.points.map(&:z).max - capf.points.map(&:z).min, 2.0, 1e-9))
ok('and it was extruded the full 120" of the wall',
   close(capf.pushpulls.first.abs, 120.0, 1e-9), capf.pushpulls)

# WIDTH, not overhang: a 12" cap on an 8" wall is 12" across, overhanging 2"
# a side. That is the number he types, so it is the number that must appear.
ys = capf.points.map { |p| p.y.round(9) }
ok('the cap is 12" side to side, exactly what he typed',
   close(ys.max - ys.min, 12.0, 1e-9), ys.max - ys.min)
ok('so it overhangs 2" each side of an 8" wall',
   close(ys.max, 6.0, 1e-9) && close(ys.min, -6.0, 1e-9), [ys.min, ys.max])
ok('and it is centred on the same line as the wall',
   close((ys.max + ys.min) / 2.0, 0.0, 1e-9))

ok('cap width stored',    close(g.get_attribute('LandscapePro', 'cap_width'), 12.0))
ok('cap thickness stored', close(g.get_attribute('LandscapePro', 'cap_height'), 2.0))
ok('cap finish stored',   g.get_attribute('LandscapePro', 'cap_material') == 'Stack Stone')
ok('overall height is the wall PLUS the cap, worked out for him',
   close(g.get_attribute('LandscapePro', 'overall_height'), 38.0),
   g.get_attribute('LandscapePro', 'overall_height'))

# The cap wears its own finish, not the wall's.
ok('the cap is painted in the CAP finish',
   capf.material && capf.material.name == 'LandscapePro_Stack Stone',
   capf.material && capf.material.name)
ok('the wall body is still painted in the WALL finish',
   g.entities.grep(Sketchup::Face).first.material.name == 'LandscapePro_Stucco')

# A cap NARROWER than the wall is a real detail, not an error.
t = fresh(12.0, 30.0, 'Stucco', 6.0, 3.0, 'Stucco')
g = t.build!(pt(0, 0), pt(60, 0))
cys = cap_of(g).entities.grep(Sketchup::Face).first.points.map { |p| p.y.round(9) }
ok('a cap narrower than the wall is built, recessed, not refused',
   close(cys.max - cys.min, 6.0, 1e-9), cys.max - cys.min)

# On a diagonal the cap width is measured across the run, like the wall.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco')
g = t.build!(pt(0, 0), pt(100, 100))
cp = sect(cap_of(g)).points
wide = cp.combination(2).map { |q, r|
  Math.sqrt((q.x - r.x)**2 + (q.y - r.y)**2)
}.max
ok('a diagonal cap is still 12" across the run', close(wide, 12.0, 1e-9), wide)
ok('and it was extruded the whole diagonal',
   close(sect(cap_of(g)).pushpulls.first.abs, Math.sqrt(100.0**2 + 100.0**2), 1e-6),
   sect(cap_of(g)).pushpulls)

# ---- the off switch --------------------------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 0.0, 'Stucco')
ok('cap thickness 0 means no cap', !t.cap?)
g = t.build!(pt(0, 0), pt(120, 0))
ok('and none is built', cap_of(g).nil?)
ok('and the stored cap numbers are zeroed, not left lying around',
   g.get_attribute('LandscapePro', 'cap_width') == 0.0 &&
   g.get_attribute('LandscapePro', 'cap_height') == 0.0 &&
   g.get_attribute('LandscapePro', 'cap_material') == '',
   [g.get_attribute('LandscapePro', 'cap_width'),
    g.get_attribute('LandscapePro', 'cap_material')])
ok('overall height is then just the wall',
   close(g.get_attribute('LandscapePro', 'overall_height'), 36.0))

t = fresh(8.0, 36.0, 'Stucco', 0.0, 2.0, 'Stucco')
ok('cap width 0 also means no cap', !t.cap?)
ok('and none is built', cap_of(t.build!(pt(0, 0), pt(120, 0))).nil?)


# ------------------------------------------------- the cap split into stones
#
# His words (2026-08-17): "הקאפ יכול להיות יחידה אחת שרצה אבל הוא גם יכול
# להיות מפוצל כמו בריקס או פייברס שיושבים על החומה וכל אחת מהם נפרד מהשני -
# זה יהיה לנו גם בקופינג של בריכות". And the end: "תעשה את האחרונה נחתכת".

# ---- the layout, as plain numbers -----------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 24.0, 0.0)
ok('split mode is on', t.split_cap?)
runs = t.cap_runs(120.0)
ok('120" of wall, 24" stones, no joint -> 5 stones', runs.length == 5, runs.length)
ok('they start where the last one ended',
   runs.each_cons(2).all? { |(_, e), (s2, _)| close(e, s2, 1e-9) }, runs)
ok('and they finish exactly at the end', close(runs.last[1], 120.0, 1e-9), runs.last)

# With a joint the stones are shorter apart than the pitch.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 24.0, 0.5)
runs = t.cap_runs(122.0)
ok('a joint opens a real gap between stones',
   runs.each_cons(2).all? { |(_, e), (s2, _)| close(s2 - e, 0.5, 1e-9) }, runs)
ok('every stone but the last is a full 24"',
   runs[0..-2].all? { |(d0, d1)| close(d1 - d0, 24.0, 1e-9) },
   runs.map { |(d0, d1)| (d1 - d0).round(3) })

# THE END: cut short, not shared out. 100" of wall, 24" stones, no joint ->
# 4 x 24 = 96, and a 4" piece. He chose the cut over four 25" stones.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 24.0, 0.0)
runs = t.cap_runs(100.0)
ok('100" / 24" -> five pieces, the last one short', runs.length == 5, runs.length)
ok('the first four are FULL size, not shrunk to fit',
   runs[0..3].all? { |(d0, d1)| close(d1 - d0, 24.0, 1e-9) },
   runs.map { |(d0, d1)| (d1 - d0).round(3) })
ok('and the last one is the 4" offcut', close(runs.last[1] - runs.last[0], 4.0, 1e-9),
   runs.last[1] - runs.last[0])
ok('nothing runs off the end of the wall', close(runs.last[1], 100.0, 1e-9), runs.last[1])

# An exact fit leaves no crumb behind.
runs = t.cap_runs(96.0)
ok('an exact fit is four whole stones and no chip', runs.length == 4, runs.length)
ok('all four full size', runs.all? { |(d0, d1)| close(d1 - d0, 24.0, 1e-9) })

# A stone longer than the wall is one cut stone, not zero and not a loop.
runs = t.cap_runs(10.0)
ok('a wall shorter than one stone gets one cut stone',
   runs.length == 1 && close(runs[0][1], 10.0, 1e-9), runs)

# The crumb guard: a sliver at the end is dropped, not left standing.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 24.0, 0.0)
runs = t.cap_runs(96.05)
ok('a 0.05" crumb at the end is dropped, not built', runs.length == 4, runs.length)

# Continuous is one run, whatever the stone length says.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.25)
ok('continuous mode is NOT split', !t.split_cap?)
ok('continuous is one run the whole length',
   t.cap_runs(120.0) == [[0.0, 120.0]], t.cap_runs(120.0))

# Split with no stone length must not loop forever laying nothing.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 0.0, 0.25)
ok('split with no stone length falls back to one run, it does not hang',
   !t.split_cap? && t.cap_runs(120.0) == [[0.0, 120.0]], t.cap_runs(120.0))

# ---- and now in the model --------------------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stack Stone', 'Split', 24.0, 0.5)
g = t.build!(pt(0, 0), pt(100, 0))
cap = cap_of(g)
ok('split: there is still one cap group', !cap.nil?)
stones = stones_of(g)
ok('split: every stone is its OWN group, so he can grab one',
   stones.length == t.cap_runs(100.0).length && stones.length > 1,
   [stones.length, t.cap_runs(100.0).length])
ok('split: the cap group itself holds no loose faces that could weld the joints',
   cap.entities.grep(Sketchup::Face).empty?,
   cap.entities.grep(Sketchup::Face).length)
ok('split: each stone is one section face extruded along the wall',
   stones.all? { |st| st.entities.grep(Sketchup::Face).length == 1 })
ok('split: every stone sits on the wall, 36" to 38"',
   stones.all? { |st|
     zs = sect(st).points.map(&:z)
     close(zs.min, 36.0, 1e-9) && close(zs.max, 38.0, 1e-9)
   })
ok('split: each full stone was extruded exactly 24"',
   stones[0..-2].all? { |st| close(run_len(st), 24.0, 1e-9) },
   stones.map { |st| run_len(st).round(3) })

spans = stones.map { |st| x_span(st) }.sort_by(&:first)
ok('split: the first stone starts at the start of the wall',
   close(spans.first[0], 0.0, 1e-9), spans.first)
ok('split: the last stone ends at the end of the wall',
   close(spans.last[1], 100.0, 1e-9), spans.last)
ok('split: there is a real 0.5" gap between every pair',
   spans.each_cons(2).all? { |(_, e), (s2, _)| close(s2 - e, 0.5, 1e-9) },
   spans.map { |a2, b2| [a2.round(2), b2.round(2)] })
ok('split: the last stone is the short one',
   (spans.last[1] - spans.last[0]) < 24.0 - 1e-9,
   spans.last[1] - spans.last[0])
ok('split: every stone is still 12" across, like the cap width he typed',
   stones.all? { |st|
     ys = sect(st).points.map(&:y)
     close(ys.max - ys.min, 12.0, 1e-9)
   })
ok('split: every stone is painted in the cap finish',
   stones.all? { |st|
     m = sect(st).material
     m && m.name == 'LandscapePro_Stack Stone'
   })
ok('split: the wall body still wears the WALL finish',
   g.entities.grep(Sketchup::Face).first.material.name == 'LandscapePro_Stucco')

ok('split: the mode is stored', g.get_attribute('LandscapePro', 'cap_mode') == 'Split')
ok('split: the stone length is stored', close(g.get_attribute('LandscapePro', 'cap_unit'), 24.0))
ok('split: the joint is stored', close(g.get_attribute('LandscapePro', 'cap_joint'), 0.5))

# Continuous, in the model: one slab, no nested stones.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.25)
g = t.build!(pt(0, 0), pt(100, 0))
ok('continuous: no stones, one slab',
   stones_of(g).empty? && cap_of(g).entities.grep(Sketchup::Face).length == 1,
   [stones_of(g).length, cap_of(g).entities.grep(Sketchup::Face).length])
ok('continuous: the slab runs the whole 100"',
   begin
     f3 = sect(cap_of(g))
     close(f3.points.map(&:x).min, 0.0, 1e-9) && close(f3.pushpulls.first.abs, 100.0, 1e-9)
   end)
ok('continuous: the stone length is NOT stored, it did not apply',
   g.get_attribute('LandscapePro', 'cap_unit') == 0.0,
   g.get_attribute('LandscapePro', 'cap_unit'))

# A split cap on a diagonal still lays its stones along the run.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 24.0, 0.0)
g = t.build!(pt(0, 0), pt(100, 100))
st = stones_of(g)
ok('split: a diagonal wall gets stones too', st.length >= 5, st.length)
ok('split: each diagonal stone is 24" ALONG the run, not 24" in x',
   close(run_len(st.first), 24.0, 1e-6), run_len(st.first))


# --------------------------------------------------------------- the bullnose
#
# One control, three answers (2026-08-17, his words: "אפשרי לעשות אופציה של
# סימון וי עם בול נוז או בלי ובצד אחד או שתי צדדים"). ONE SIDE is the RIGHT
# of the way he draws it; to nose the other face he draws the wall the other
# way round.
#
# A bullnose is a HALF-ROUND: radius = half the cap thickness, always. It eats
# into the width he typed rather than adding to it, exactly like a real stone.

t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stucco', 'Continuous', 24.0, 0.0, 'None')
sq = t.cap_profile
ok('no bullnose: the section is a plain four-corner rectangle', sq.length == 4, sq.length)
ok('no bullnose: 12" across', close(sq.map(&:first).max - sq.map(&:first).min, 12.0, 1e-9))
ok('no bullnose: 3" tall', close(sq.map(&:last).max - sq.map(&:last).min, 3.0, 1e-9))
ok('no bullnose: centred on the wall line',
   close(sq.map(&:first).max, 6.0, 1e-9) && close(sq.map(&:first).min, -6.0, 1e-9), sq)
ok('bullnose? is false', !t.bullnose?)

# ---- one side --------------------------------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stucco', 'Continuous', 24.0, 0.0, 'One side')
one = t.cap_profile
ok('one side: bullnose? is true', t.bullnose?)
ok('one side: the section grew corners for the arc', one.length > 4, one.length)
ok('one side: it is STILL 12" across - the nose ate in, it did not stick out',
   close(one.map(&:first).max - one.map(&:first).min, 12.0, 1e-9),
   one.map(&:first).max - one.map(&:first).min)
ok('one side: still 3" tall', close(one.map(&:last).max - one.map(&:last).min, 3.0, 1e-9))

# Every arc point must sit exactly one radius from the nose centre. That is
# what makes it a half-round rather than a chamfer that looks like one.
r = 1.5
cx = 6.0 - r
nose_pts = one.select { |(v, _w)| v > cx - 1e-9 }
ok('one side: the nose is made of at least 8 pieces', nose_pts.length >= 8, nose_pts.length)
ok('one side: every one of them is exactly 1.5" from the nose centre',
   nose_pts.all? { |(v, w)| close(Math.sqrt((v - cx)**2 + (w - r)**2), r, 1e-9) },
   nose_pts.map { |(v, w)| Math.sqrt((v - cx)**2 + (w - r)**2).round(6) }.uniq)
ok('one side: the nose reaches the full 6" out and no further',
   close(one.map(&:first).max, 6.0, 1e-9), one.map(&:first).max)
ok('one side: the nose is at mid-height, 1.5" up',
   close(one.max_by(&:first)[1], 1.5, 1e-9), one.max_by(&:first))

# The OTHER side is left square.
ok('one side: the left edge is still a square corner',
   one.count { |(v, _w)| close(v, -6.0, 1e-9) } == 2,
   one.select { |(v, _w)| close(v, -6.0, 1e-9) })

# ---- both sides ------------------------------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stucco', 'Continuous', 24.0, 0.0, 'Both sides')
both = t.cap_profile
ok('both sides: more corners again', both.length > one.length, [one.length, both.length])
ok('both sides: still 12" across', close(both.map(&:first).max - both.map(&:first).min, 12.0, 1e-9))
ok('both sides: neither edge is a square corner',
   both.count { |(v, _w)| close(v.abs, 6.0, 1e-9) } == 2,
   both.select { |(v, _w)| close(v.abs, 6.0, 1e-9) })
ok('both sides: it is symmetric about the wall line',
   both.map { |(v, w)| [(-v).round(6), w.round(6)] }.sort ==
   both.map { |(v, w)| [v.round(6), w.round(6)] }.sort)
lcx = -6.0 + r
lnose = both.select { |(v, _w)| v < lcx + 1e-9 }
ok('both sides: the left nose is a half-round too',
   lnose.length >= 8 && lnose.all? { |(v, w)| close(Math.sqrt((v - lcx)**2 + (w - r)**2), r, 1e-9) },
   lnose.length)

# ---- the guard: a nose that cannot fit falls back to a square edge ---------
#
# A half-round is radius = half the thickness, full stop. On a 2" wide, 40"
# tall cap that nose does not fit, and forcing it produced a 1"-radius bump on
# a 40" slab with the section folded over itself. Square edge instead.
t = fresh(8.0, 36.0, 'Stucco', 2.0, 40.0, 'Stucco', 'Continuous', 24.0, 0.0, 'Both sides')
weird = t.cap_profile
ok('a cap too thin for a half-round falls back to a square edge',
   weird.length == 4, weird.length)
ok('and it is still exactly the size he typed',
   close(weird.map(&:first).max - weird.map(&:first).min, 2.0, 1e-9) &&
   close(weird.map(&:last).max - weird.map(&:last).min, 40.0, 1e-9),
   [weird.map(&:first).max - weird.map(&:first).min,
    weird.map(&:last).max - weird.map(&:last).min])

# The exact boundary: two noses need height <= width, one needs height <= 2x.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 12.0, 'Stucco', 'Continuous', 24.0, 0.0, 'Both sides')
ok('both noses fit exactly when the cap is as tall as it is wide',
   t.cap_profile.length > 4, t.cap_profile.length)
t = fresh(8.0, 36.0, 'Stucco', 12.0, 12.5, 'Stucco', 'Continuous', 24.0, 0.0, 'Both sides')
ok('a hair taller than that and both go square', t.cap_profile.length == 4, t.cap_profile.length)
t = fresh(8.0, 36.0, 'Stucco', 12.0, 12.5, 'Stucco', 'Continuous', 24.0, 0.0, 'One side')
ok('but ONE nose still fits there - it only eats one end',
   t.cap_profile.length > 4, t.cap_profile.length)

# ---- in the model ----------------------------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stack Stone', 'Continuous', 24.0, 0.0, 'One side')
g = t.build!(pt(0, 0), pt(120, 0))
cf2 = sect(cap_of(g))
ok('model: the nosed cap is one section face, extruded 120"',
   !cf2.nil? && close(cf2.pushpulls.first.abs, 120.0, 1e-9), cf2 && cf2.pushpulls)
ok('model: the section carries the arc points', cf2.points.length > 4, cf2.points.length)
ok('model: the whole nosed cap is painted', !cf2.material.nil?)
ok('model: the nose is on the RIGHT of the way he drew it',
   close(cf2.points.map(&:y).max, 6.0, 1e-9) &&
   cf2.points.select { |q| close(q.y, 6.0, 1e-9) }.length == 1,
   cf2.points.select { |q| close(q.y, 6.0, 1e-9) }.length)
ok('model: and the left edge still has its two square corners',
   cf2.points.select { |q| close(q.y, -6.0, 1e-9) }.length == 2,
   cf2.points.select { |q| close(q.y, -6.0, 1e-9) }.length)
ok('model: the bullnose setting is stored',
   g.get_attribute('LandscapePro', 'bullnose') == 'One side',
   g.get_attribute('LandscapePro', 'bullnose'))

# Drawn the other way round, the nose lands on the other face - which is how
# he flips it, and why there is no left/right control.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stucco', 'Continuous', 24.0, 0.0, 'One side')
g = t.build!(pt(120, 0), pt(0, 0))
cf3 = sect(cap_of(g))
ok('drawing it the other way puts the nose on the other face',
   cf3.points.select { |q| close(q.y, -6.0, 1e-9) }.length == 1 &&
   cf3.points.select { |q| close(q.y, 6.0, 1e-9) }.length == 2,
   [cf3.points.select { |q| close(q.y, -6.0, 1e-9) }.length,
    cf3.points.select { |q| close(q.y, 6.0, 1e-9) }.length])

# Every stone of a split cap gets the same nose.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stucco', 'Split', 24.0, 0.5, 'Both sides')
g = t.build!(pt(0, 0), pt(100, 0))
st2 = stones_of(g)
ok('split + bullnose: every stone is nosed, not just the first',
   st2.length > 1 && st2.all? { |x| sect(x).points.length > 4 },
   st2.map { |x| sect(x).points.length })
ok('split + bullnose: the stones are still 24" long with 0.5" joints',
   st2[0..-2].all? { |x| close(run_len(x), 24.0, 1e-9) },
   st2.map { |x| run_len(x).round(3) })

# No cap, no bullnose - the setting cannot conjure one.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 0.0, 'Stucco', 'Continuous', 24.0, 0.0, 'Both sides')
ok('no cap means no bullnose, whatever the dropdown says', !t.bullnose?)
g = t.build!(pt(0, 0), pt(120, 0))
ok('and none is stored', g.get_attribute('LandscapePro', 'bullnose') == 'None',
   g.get_attribute('LandscapePro', 'bullnose'))


# ------------------------------------------------------------- the overhang
#
# He looked at the first build and asked for it (2026-08-17): "שאני בוחר
# אוברהנג צריכה להיות האפשרות לבחור רק צד אחד יבלוט החוצה, כי לא תמיד ובדרך
# כלל לא שניהם יבלטו החוצה, הרבה פעמים יושב פלאש עם הקו של החומה."
#
# BOTH = centred. ONE = flush with the LEFT face, all the overhang on the
# right - the same right the bullnose uses, so the shown face gets both.

# 12" cap on an 8" wall = 4" of overhang to place.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0, 'None', 'Both sides')
ok('both sides: the coping is not slid at all', close(t.cap_shift, 0.0, 1e-9), t.cap_shift)
g = t.build!(pt(0, 0), pt(120, 0))
ys = sect(cap_of(g)).points.map(&:y)
ok('both sides: it hangs over 2" each side of an 8" wall',
   close(ys.min, -6.0, 1e-9) && close(ys.max, 6.0, 1e-9), [ys.min, ys.max])

t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0, 'None', 'One side')
ok('one side: the coping is slid by half the difference',
   close(t.cap_shift, 2.0, 1e-9), t.cap_shift)
g = t.build!(pt(0, 0), pt(120, 0))
ys = sect(cap_of(g)).points.map(&:y)
ok('one side: FLUSH with the left face of the wall, at -4"',
   close(ys.min, -4.0, 1e-9), ys.min)
ok('one side: and the whole 4" of overhang is on the right',
   close(ys.max, 8.0, 1e-9), ys.max)
ok('one side: the coping is still 12" wide, nothing was lost',
   close(ys.max - ys.min, 12.0, 1e-9), ys.max - ys.min)
ok('one side: the overhang setting is stored',
   g.get_attribute('LandscapePro', 'overhang') == 'One side',
   g.get_attribute('LandscapePro', 'overhang'))

# A cap the same width as the wall is flush either way - no overhang to place.
t = fresh(8.0, 36.0, 'Stucco', 8.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0, 'None', 'One side')
ok('a cap as wide as the wall has nothing to slide', close(t.cap_shift, 0.0, 1e-9))

# A cap NARROWER than the wall goes flush left, inset right.
t = fresh(12.0, 36.0, 'Stucco', 8.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0, 'None', 'One side')
g = t.build!(pt(0, 0), pt(120, 0))
ys = sect(cap_of(g)).points.map(&:y)
ok('a recessed cap on one side is flush left and inset right',
   close(ys.min, -6.0, 1e-9) && close(ys.max, 2.0, 1e-9), [ys.min, ys.max])

# The overhang and the nose land on the SAME face - the one that shows.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 3.0, 'Stucco', 'Continuous', 24.0, 0.0, 'One side', 'One side')
g = t.build!(pt(0, 0), pt(120, 0))
f4 = sect(cap_of(g))
ok('the nose is on the same face as the overhang - the one that shows',
   close(f4.points.map(&:y).max, 8.0, 1e-9) &&
   f4.points.select { |q| close(q.y, 8.0, 1e-9) }.length == 1,
   [f4.points.map(&:y).max, f4.points.select { |q| close(q.y, 8.0, 1e-9) }.length])

# Split stones follow the shift too.
t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Split', 24.0, 0.5, 'None', 'One side')
g = t.build!(pt(0, 0), pt(100, 0))
ok('every stone of a split cap is flush on the same side',
   stones_of(g).all? { |x| close(sect(x).points.map(&:y).min, -4.0, 1e-9) },
   stones_of(g).map { |x| sect(x).points.map(&:y).min.round(3) }.uniq)

# ------------------------------------------------- the facet lines come off
#
# The first screenshot showed a ribbed nose - SketchUp draws a line on every
# facet of the arc. Soften+smooth anything that is a facet; leave real
# corners alone.

up_v   = Geom::Vector3d.new(0, 0, 1)
side_v = Geom::Vector3d.new(0, 1, 0)
ok('a 90 degree corner is NOT softened', !GW.soften?(up_v, side_v))
ok('two faces pointing the same way ARE', GW.soften?(up_v, up_v))
# One facet of a 12-piece half-round turns 15 degrees.
a15 = Geom::Vector3d.new(0, Math.sin(15 * Math::PI / 180), Math.cos(15 * Math::PI / 180))
ok('a 15 degree facet - one piece of the arc - is softened', GW.soften?(up_v, a15))
a45 = Geom::Vector3d.new(0, Math.sin(45 * Math::PI / 180), Math.cos(45 * Math::PI / 180))
ok('a 45 degree fold is left alone - that is a chamfer, not a facet', !GW.soften?(up_v, a45))
ok('a missing normal is not a crash', !GW.soften?(nil, up_v) && !GW.soften?(up_v, nil))
ok('the arc has enough pieces to read as round', GW::BULLNOSE_SEGMENTS >= 12,
   GW::BULLNOSE_SEGMENTS)
# The facet turn must stay under the softening threshold, or the lines come
# back the day someone changes the segment count.
ok('every facet turn is under the softening angle',
   (180.0 / GW::BULLNOSE_SEGMENTS) < GW::SOFTEN_DEGREES,
   [180.0 / GW::BULLNOSE_SEGMENTS, GW::SOFTEN_DEGREES])


# --------------------------------------------- the elevation line, along the back
#
# His words (2026-08-17): "אני גם רוצה שבתור התחלה יהיה קו מקביל לחלק האחורי
# שלה שזז איתה כשהיא עיגול או יורדת למטה או עולה למעלה, כדי שאני אוכל לקחת את
# הקו הזה ולייצא איתו אלווישן עד שנכין את המוצר לאלווישן." And when asked
# where exactly: "לאורך הקצה העליון אבל מתחת לקאפ."

t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0,
          'One side', 'One side', true)
pts = t.back_line_points(pt(0, 0), pt(120, 0))
ok('the line has two ends', pts && pts.length == 2, pts && pts.length)
ok('it runs at the top of the WALL, 36" - under the cap, not on it',
   pts.all? { |p| close(p.z, 36.0, 1e-9) }, pts.map(&:z))
ok('it is NOT at the top of the cap (38")', !close(pts[0].z, 38.0, 1e-9))
ok('it runs along the BACK face - the left, opposite the nose and the overhang',
   pts.all? { |p| close(p.y, -4.0, 1e-9) }, pts.map(&:y))
ok('it runs the full length of the wall',
   close(pts[0].x, 0.0, 1e-9) && close(pts[1].x, 120.0, 1e-9), pts.map(&:x))

# Drawn the other way, the back swaps with the front - same rule as the nose.
back2 = t.back_line_points(pt(120, 0), pt(0, 0))
ok('drawn the other way the line moves to the other face',
   back2.all? { |p| close(p.y, 4.0, 1e-9) }, back2.map(&:y))

# It hugs the wall, not the coping: a wider cap must not move it.
wide = fresh(8.0, 36.0, 'Stucco', 24.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0,
             'None', 'Both sides', true).back_line_points(pt(0, 0), pt(120, 0))
ok('a wider cap does not drag the line out with it',
   wide.all? { |p| close(p.y, -4.0, 1e-9) }, wide.map(&:y))

# On a diagonal it stays half a thickness off the line he drew.
dg = t.back_line_points(pt(0, 0), pt(100, 100))
mid = Geom::Point3d.new((dg[0].x + dg[1].x) / 2.0, (dg[0].y + dg[1].y) / 2.0, 0)
# distance from the wall's own centre line (0,0)->(100,100)
off = ((mid.x * 100.0 - mid.y * 100.0) / Math.sqrt(100.0**2 + 100.0**2)).abs
ok('on a diagonal it sits exactly half a thickness off the centre line',
   close(off, 4.0, 1e-6), off)

ok('a zero-length wall has no line', t.back_line_points(pt(3, 3), pt(3, 3)).nil?)

# ---- in the model ----------------------------------------------------------

g = t.build!(pt(0, 0), pt(120, 0))
ln = line_of(g)
ok('the line is built, in its own group he can click once', !ln.nil?)
ok('it is one edge, no faces', ln.entities.grep(Sketchup::Edge).length == 1 &&
                               ln.entities.grep(Sketchup::Face).empty?,
   [ln.entities.grep(Sketchup::Edge).length, ln.entities.grep(Sketchup::Face).length])
ok('it has its OWN tag, so every elevation line switches off together',
   $tags.include?('LP/Wall Elevation Lines'), $tags)
ok('and that tag is not the wall tag', 'LP/Wall Elevation Lines' != 'LP/Walls')
e = ln.entities.grep(Sketchup::Edge).first
ends = [e.start.position, e.end.position]
ok('the built edge is exactly where the numbers said',
   ends.all? { |p| close(p.z, 36.0, 1e-9) && close(p.y, -4.0, 1e-9) },
   ends.map { |p| [p.x.round(2), p.y.round(2), p.z.round(2)] })
ok('the setting is stored', g.get_attribute('LandscapePro', 'back_line') == true)

# The wall body and the cap are untouched by it.
ok('the body is still one face', g.entities.grep(Sketchup::Face).length == 1)
ok('the cap is still there', !cap_of(g).nil?)

# ---- the off switch --------------------------------------------------------

t = fresh(8.0, 36.0, 'Stucco', 12.0, 2.0, 'Stucco', 'Continuous', 24.0, 0.0,
          'None', 'Both sides', false)
g = t.build!(pt(0, 0), pt(120, 0))
ok('turned off, no line is built', line_of(g).nil?)
ok('and the model is not tagged for elevation lines',
   !$tags.include?('LP/Wall Elevation Lines'), $tags)
ok('and the setting says so', g.get_attribute('LandscapePro', 'back_line') == false)

# A wall with no cap still gets its line - it is the top of the WALL.
t = fresh(8.0, 36.0, 'Stucco', 0.0, 0.0, 'Stucco', 'Continuous', 24.0, 0.0,
          'None', 'Both sides', true)
g = t.build!(pt(0, 0), pt(120, 0))
ok('no cap, still a line, still at the top of the wall',
   line_of(g) &&
   line_of(g).entities.grep(Sketchup::Edge).first.start.position.z.round(6) == 36.0)

# ------------------------------------------------------------- the mis-clicks

t = fresh
ok('a zero-length click builds nothing and does not raise',
   t.build!(pt(10, 10), pt(10, 10)).nil?)
ok('and left no group behind', walls.length.zero?, walls.length)

# ---------------------------------------------------------- the mouse, end to end

view = Object.new
def view.invalidate; true; end
def view.inputpoint(x, y); Struct.new(:position).new(Geom::Point3d.new(x, y, 0)); end

t = fresh(10.0, 48.0, 'Block Wall', 14.0, 2.5, 'Stack Stone')
t.onLButtonDown(0, 0, 0, view)
ok('one click builds nothing yet', walls.length.zero?, walls.length)
t.onLButtonDown(0, 200, 0, view)
ok('the second click builds it', walls.length == 1, walls.length)
ok('the axis magnet was borrowed from the wall tool, once', $magnet_calls == 1, $magnet_calls)
gw = walls.first
ok('the settings he picked are the ones that got built',
   close(gw.get_attribute('LandscapePro', 'thickness'), 10.0) &&
   close(gw.get_attribute('LandscapePro', 'height'), 48.0) &&
   gw.get_attribute('LandscapePro', 'material') == 'Block Wall',
   [gw.get_attribute('LandscapePro', 'thickness'),
    gw.get_attribute('LandscapePro', 'height'),
    gw.get_attribute('LandscapePro', 'material')])
ok('and the cap he picked came through the mouse too',
   close(gw.get_attribute('LandscapePro', 'cap_width'), 14.0) &&
   close(gw.get_attribute('LandscapePro', 'cap_height'), 2.5) &&
   gw.get_attribute('LandscapePro', 'cap_material') == 'Stack Stone' &&
   !cap_of(gw).nil?,
   [gw.get_attribute('LandscapePro', 'cap_width'),
    gw.get_attribute('LandscapePro', 'cap_material')])

ops = Sketchup.active_model.ops
ok('one wall = one undo step',
   ops.count { |o| o[0] == :start } == 1 && ops.count { |o| o[0] == :commit } == 1, ops)

# A second click on the same spot must not build a zero-length wall.
t = fresh
t.onLButtonDown(0, 50, 50, view)
t.onLButtonDown(0, 50, 50, view)
ok('clicking the same spot twice builds nothing', walls.length.zero?, walls.length)

# ------------------------------------------------------- length typed, not clicked

t = fresh(8.0, 36.0)
t.onLButtonDown(0, 0, 0, view)
t.onMouseMove(0, 10, 0, view)
t.onUserText("10'", view)
ok('a typed length builds the wall', walls.length == 1, walls.length)
ok("10' came out as 120 inches along the direction of the cursor",
   close(walls.first.get_attribute('LandscapePro', 'length_in'), 120.0, 1e-6),
   walls.first.get_attribute('LandscapePro', 'length_in'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

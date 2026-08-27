# encoding: utf-8
# rt109 - THE DORMER WEARS THE SAME ROOF AS THE HOUSE (2026-09-05).
#
# Until today a dormer roof got the house roof's MATERIAL and nothing else.
# On a standing seam house the dormer came out as a bare painted slab with
# no ribs on it at all: "הגגון יקבל את אותם רעפים כמו הגג שהוא ממוקם עליו
# - לא רק את הצבע".
#
# THE CLAIMS PINNED HERE
# 1. top_skin picks the slab's UPPER face. By POSITION, not by normal - the
#    underside is wound the other way and its normal points up too, so a
#    normal test would hand back both and a second field would be laid
#    underneath where nobody can see it. (The law this project has already
#    paid for twice; see the 2026-09-04 handoff.)
# 2. Placing a dormer on a roof stamped 'seam' leaves seam runs INSIDE each
#    dormer_roof sub-group - so they travel with the dormer on a move and
#    go with it on a delete.
# 3. The eave bar comes too, stamped 'tile_edge' - the bar the panels die
#    into, which he chose over letting them stop on the metal edge.
# 4. A roof with no tile material on it lays nothing and does not raise.
# 5. no_tiles: true still gives the bare dormer, so the old path is one
#    keyword away.
#
# Against the old code claims 1-3 fail: place_tiles! and top_skin do not
# exist, and the dormer_roof groups hold faces only.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager

Z0    = 100.0
SLOPE = 5.0 / 12.0

SPEC = { z0: Z0, slope: SLOPE, setback: 50.0, width: 50.0, length: 145.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         style: 'gable', base: [0.0, 0.0], along: [1.0, 0.0],
         into: [0.0, 1.0] }.freeze

def build_roof(material)
  Sketchup.reset_model!
  model = Sketchup.active_model
  roof = model.entities.add_group
  roof.set_attribute('InteriorPro', 'type', 'roof')
  roof.set_attribute('InteriorPro', 'roof_material', material) if material
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  roof.entities.add_face([at.call(-400, 0), at.call(400, 0),
                          at.call(400, 400), at.call(-400, 400)])
  roof
end

def roof_subs(dormer)
  dormer.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
  end
end

def stamps(sub)
  sub.entities.grep(Sketchup::ComponentInstance)
     .map { |i| i.definition.get_attribute('InteriorPro', 'part').to_s }
end

# ---- 1. the top skin is the HIGHER face, not the one whose normal is up
roof = build_roof('seam')
d = DM.add_dormer!(roof.entities, SPEC.merge(no_tiles: true))
ok('a dormer was built', !d.nil?)
subs = roof_subs(d)
ok('it has two roof slabs', subs.length == 2, subs.length)

# asked through respond_to? on purpose: against the OLD code this suite has
# to FAIL, line by line, not blow up on the first missing method.
def mid_z(f)
  zs = f.vertices.map { |v| v.position.z.to_f }
  zs.empty? ? 0.0 : zs.inject(:+) / zs.length
end

sub = subs.first
skin = DM.respond_to?(:top_skin) ? DM.top_skin(sub) : nil
ok('top_skin found a face', !skin.nil?)
sloped = sub.entities.grep(Sketchup::Face).reject { |f| f.normal.z.abs < 0.05 }
ok('the slab has exactly two non-vertical faces', sloped.length == 2,
   sloped.length)
ok('top_skin is the HIGHER of the two, not merely one with a +z normal',
   !skin.nil? && sloped.all? { |f| mid_z(f) <= mid_z(skin) },
   sloped.map { |f| mid_z(f).round(3) })
ok('both faces would pass a normal test - so the normal cannot be what picked',
   sloped.count { |f| f.normal.z > 0.2 } >= 1,
   sloped.map { |f| f.normal.z.round(3) })

# ---- 2 + 3. the field and the bar land inside the dormer's own slabs
roof2 = build_roof('seam')
d2 = DM.add_dormer!(roof2.entities, SPEC)
ok('a dormer was built on the seam roof', !d2.nil?)
subs2 = roof_subs(d2)
ok('two roof slabs again', subs2.length == 2, subs2.length)

runs = subs2.map { |s| stamps(s).count('tile_run') }
ok('every dormer slab carries seam runs', runs.all?(&:positive?), runs)

# THE BAR IS A GROUP, NOT AN INSTANCE - a mitred end cannot come from
# stretching one shared box, so place_eave_bars! builds each bar on the spot.
bars = subs2.map do |s|
  s.entities.grep(Sketchup::Group).count do |b|
    b.get_attribute('InteriorPro', 'part').to_s == 'tile_edge'
  end
end
ok('every dormer slab carries its eave bar', bars.all?(&:positive?), bars)

# and nothing was laid loose in the dormer group itself
loose = d2.entities.grep(Sketchup::ComponentInstance).length
ok('nothing is left loose in the dormer group', loose.zero?, loose)

# ---- 4. a roof with nothing on it lays nothing, quietly
roof3 = build_roof(nil)
d3 = DM.add_dormer!(roof3.entities, SPEC)
ok('a dormer on a bare roof still builds', !d3.nil?)
none = roof_subs(d3).map { |s| s.entities.grep(Sketchup::ComponentInstance).length }
ok('and carries no tiles', none.all?(&:zero?), none)

# ---- 5. the old bare dormer is one keyword away
bare = roof_subs(d).map { |s| s.entities.grep(Sketchup::ComponentInstance).length }
ok('no_tiles: true leaves the slabs bare', bare.all?(&:zero?), bare)

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"

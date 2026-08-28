# encoding: utf-8
# rt113 - A CLAY RIDGE IS A HALF ROUND, AN INCH APART (2026-09-05).
#
# He looked at the Roman cap and said the shape is wrong: "זה כמו חצי עיגול
# ואז קו... אם תוריד את הקו ותשאיר רק חצי עיגול ותקבע שיש רווח של אינצ בין
# כל אחד זה יהיה הרבה יותר פשוט".
#
# THE LINE WAS THE LAP. The pieces were laid 15" long every 12", so each one
# rode over the last on a head lift - and that lift is what drew the straight
# run along the top of the arch. The arch itself was not a half round either:
# its crown came from the tile's own number, 1.42" on a 13" wide cap.
#
# THE CLAIMS PINNED HERE
# 1. Roman is the round cap; nothing else is, so nothing else moves.
# 2. The gap is his number, and it is a METHOD - a constant behind
#    const_defined? does not come back on reload!.
# 3. The section is a TRUE semicircle: the cap stands half its own width
#    above the ridge, on top of whatever it is lifted by.
# 4. The materials that were never round keep the crown they had.
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

RM = InteriorPro::RoofManager
DM = InteriorPro::DormerManager

# ---- 1 + 2 -----------------------------------------------------------
round = InteriorPro::RoofTileMath.shapes.keys.map(&:to_s).select { |n| RM.cap_round_for(n) }
ok('roman is the one round cap', round == ['roman'], round)
ok('the gap is an inch', RM.respond_to?(:cap_gap) && RM.cap_gap == 1.0,
   RM.respond_to?(:cap_gap) ? RM.cap_gap : nil)
ok('and it is a method, so reload! re-reads it',
   RM.methods.include?(:cap_gap))

# ---- 3. a true semicircle -------------------------------------------
Z0 = 100.0
SLOPE = 5.0 / 12.0
SPEC = { z0: Z0, slope: SLOPE, setback: 50.0, width: 50.0, length: 130.0,
         thickness: 5.0, roof_thickness: 0.5, overhang: 6.0,
         style: 'gable', base: [0.0, 0.0], along: [1.0, 0.0],
         into: [0.0, 1.0] }.freeze

def dormer_on(material)
  Sketchup.reset_model!
  m = Sketchup.active_model
  roof = m.entities.add_group
  roof.set_attribute('InteriorPro', 'type', 'roof')
  roof.set_attribute('InteriorPro', 'roof_material', material)
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  roof.entities.add_face([at.call(-400, 0), at.call(400, 0),
                          at.call(400, 400), at.call(-400, 400)])
  DM.add_dormer!(roof.entities, SPEC)
end

def cap_peak_over_ridge(d)
  subs = d.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
  end
  ridge_z = subs.flat_map do |s|
    DM.top_skin(s).vertices.map { |v| v.position.transform(s.transformation).z.to_f }
  end.max
  caps = d.entities.grep(Sketchup::Group).select do |s|
    s.get_attribute('InteriorPro', 'part').to_s == 'ridge_cap'
  end
  zs = caps.flat_map { |c| c.entities.grep(Sketchup::Face) }
           .flat_map { |f| f.vertices.map { |v| v.position.z.to_f } }
  return nil if zs.empty? || ridge_z.nil?
  zs.max - ridge_z
end

dr = dormer_on('roman')
ok('a roman dormer was built', !dr.nil?)
peak = dr && cap_peak_over_ridge(dr)
# AND IT SITS ON THE ROOF, NOT ON STILTS. The lift was there because the old
# 1.42" arch could not clear a 4.17" tile; a 6.5" half round clears it on its
# own, and the lift was only two upright walls between the arc and the deck -
# "יש כמו קרשים מתחת לטייל... ואני רוצה להוריד אותו".
want = RM.cap_width_for('roman') / 2.0
ok('the roman cap stands half its own width above the ridge, and no more',
   !peak.nil? && (peak - want).abs < 0.6, [peak && peak.round(2), want.round(2)])
ok('a half round clears the tile it caps without any lift',
   want > RM.cap_lift_for('roman'), [want, RM.cap_lift_for('roman')])

# ---- 4. the others are exactly where they were ------------------------
ok('the seam still states a flat crown', RM.cap_crown_for('seam').zero?,
   RM.cap_crown_for('seam'))
ds = dormer_on('seam')
ps = ds && cap_peak_over_ridge(ds)
ok('and its cap is nothing like half its width',
   !ps.nil? && ps < RM.cap_width_for('seam') / 4.0,
   [ps && ps.round(2), RM.cap_width_for('seam')])

puts $fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***"

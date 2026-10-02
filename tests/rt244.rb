# encoding: utf-8
# rt244 - THE VALLEY CUT STOPS WHERE THE HOUSE STOPS (2026-10-01).
#
# His Aetna garage is WIDER than the house: 83.5" of it stand past the
# house's east wall (roof_low_report.txt). valley_inside_regions asked only
# "is this past the house's wall LINE" - a line runs for ever - so with the
# valley on, the garage roof was cut back and a 72" wall triangle was built
# east of the house, with no house behind either (his picture: "פתרת משהו
# אחד אבל יצרת בעיה אחרת"). The region is now also held between the two
# ends of the house roof's facing edge.
#
# The numbers are his: house roof x -749..-134, garage roof x -334.5..-50.5,
# both gables, as built by tests/rt243.rb. rt153 keeps pinning his FIRST
# model, where the garage is flush with the end of the house and nothing
# may change.
require './sketchup_stub'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager
RF.send(:remove_const, :USE_ROOF_VALLEY)
RF.const_set(:USE_ROOF_VALLEY, true)

HOUSE = [[-134.0, 452.5], [-134.0, 822.5], [-749.0, 822.5], [-749.0, 452.5]].freeze
GAR   = [[-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0], [-50.5, 481.5]].freeze

def roof(m, fp, gables, eave_z, ridge_z, pitch)
  g = m.entities.add_group
  { 'type' => 'roof', 'footprint_xy' => fp.flatten, 'gable_edges' => gables,
    'eave_z' => eave_z, 'ridge_z' => ridge_z, 'pitch' => pitch,
    'overhang_in' => 12.0, 'level' => 1 }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end

def regions(pitch, house_eave, house_ridge, gar_eave, gar_ridge)
  Sketchup.reset_model!
  m = Sketchup.active_model
  roof(m, HOUSE, [0, 2], house_eave, house_ridge, pitch)
  lg = roof(m, GAR, [1], gar_eave, gar_ridge, pitch)
  g = RF.roof_geom(lg)
  RF.valley_inside_regions(g[:pts], [false, true, false, false], g[:slope], g[:deck_z], g[:ridge_z], 1, lg)
end

# ---- 3:12, the pitch on the stamped plan ---------------------------------------
rs = regions(3.0, 104.0, 147.25, 86.0, 118.5)
ok('3:12 - two regions, one per garage slope', rs.length == 2, rs.length)
west = rs.find { |r| r[:poly].map { |p| p[0] }.min < -300.0 }
east = rs.find { |r| r[:poly].map { |p| p[0] }.min > -300.0 }
ok('the west region is the trapezoid against the house, wall line to roof edge',
   west && west[:poly].map { |p| [p[0].round(1), p[1].round(1)] } ==
     [[-334.5, 481.5], [-334.5, 464.5], [-250.5, 464.5], [-233.5, 481.5]], west && west[:poly])
ok('the east region stops at the END OF THE HOUSE ROOF (x = -134), not at the garage eave',
   east && east[:poly].map { |p| p[0] }.max <= -134.0 + 0.01, east && east[:poly])
tw = west && RF.valley_wall_end_tri(west, 12.0)
ok('west: the wall triangle over the garage roof is still closed - 72" long, 18" tall',
   tw && (tw[1][0] - tw[0][0]).abs.round(1) == 72.0 && (tw[2][2] - tw[0][2]).round(1) == 18.0, tw)
ok('east: NO wall triangle - there is no house wall there to continue',
   east.nil? || RF.valley_wall_end_tri(east, 12.0).nil?, east && RF.valley_wall_end_tri(east, 12.0))

# ---- 6:12, the pitch his model had: the east leg lands past the house ---------
rs6 = regions(6.0, 104.0, 190.5, 86.0, 151.0)
ok('6:12 - only the west region is left; nothing is cut east of the house',
   rs6.length == 1 && rs6[0][:poly].map { |p| p[0] }.max < -200.0, rs6.map { |r| r[:poly] })

# ---- the kill switch: the old endless half plane ---------------------------------
RF.send(:remove_const, :USE_VALLEY_SPAN_CLIP)
RF.const_set(:USE_VALLEY_SPAN_CLIP, false)
old = regions(3.0, 104.0, 147.25, 86.0, 118.5)
oe = old.find { |r| r[:poly].map { |p| p[0] }.min > -300.0 }
ok('kill switch: the east region runs out to the garage eave again (x = -50.5)',
   oe && (oe[:poly].map { |p| p[0] }.max - -50.5).abs < 0.01, oe && oe[:poly])
ok('kill switch: and the triangle in the air is back',
   oe && !RF.valley_wall_end_tri(oe, 12.0).nil?)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt241 - A WALL MERGED INTO A LONGER ONE STILL BELONGS TO ITS ROOF
# (2026-10-01). Measured twice on his Aetna house the same day
# (roof_low_report.txt and the roof audit he ran): where an interior wall
# closes a roof's loop, a short exterior wall lying on the same line is
# merged into it by drop_flat_corners - and after that no roof claimed it.
# The garage's back wall (4b76..., 83.5") and the house's 68ea wall (84.5")
# both answered roof_of_wall_id = nil, so a Gable click on either said
# "this wall has no roof over it" and the mark never reached the builder.
#
# This step is OWNERSHIP ONLY: the outline, and so the roof that is built,
# must come out exactly as before. The walls below are his, inch for inch.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager

WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],   # his 4b76e4cc
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],     # his 68ea3160
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def build_house
  Sketchup.reset_model!
  m = Sketchup.active_model
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = m.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  m
end

# ---- 1. the outline says who was merged away, and is itself unchanged ----
build_house
bl = RF.storeys_of(RF.buildings_of(RF.walls_of(1)), InteriorPro::LevelManager.walls_of_level(1))
gar = bl.find { |b| b[:abut] }
hse = bl.find { |b| !b[:abut] }
ok('the storey is two buildings: the house and the dropped garage', bl.length == 2 && gar && hse, bl.length)
eg = RF.eave_polygon(gar[:walls] + gar[:closers], 12.0, 3.0)
ok('the garage outline is the same four corners as before',
   eg[:pts].map { |p| p.map { |v| v.round(2) } } == [[-334.5, 481.5], [-334.5, 201.0], [-50.5, 201.0], [-50.5, 481.5]], eg[:pts])
ok('...with the same wall on each edge', eg[:wall_ids] == %w[gW gS gE div], eg[:wall_ids])
ok('the garage back wall is reported as merged into the divider', eg[:swallowed] == { 'div' => ['gN'] }, eg[:swallowed])
eh = RF.eave_polygon(hse[:walls] + hse[:closers], 12.0, 3.0)
ok('the house wall 68ea is reported as merged into the divider', eh[:swallowed] == { 'div' => ['h5'] }, eh[:swallowed])
plain = RF.eave_polygon(hse[:walls] + hse[:closers], 12.0)
ok('a caller that asks for no merging gets the old two-key hash', plain.nil? || plain.keys == %i[pts wall_ids], plain && plain.keys)

# ---- 2. the pure rule: only this roof's OWN walls are claimed ------------
ok('an own wall that was merged away is claimed', RF.swallowed_own_ids({ 'div' => ['gN'] }, %w[gW gS gE gN]) == ['gN'])
ok('a merged CLOSER is not - it is the other building\'s wall', RF.swallowed_own_ids({ 'div' => ['h5'] }, %w[gW gS gE gN]).empty?)
ok('nothing merged, nothing claimed', RF.swallowed_own_ids(nil, %w[a b]).empty?)

# ---- 3. the real path: build both roofs, then ask whose wall it is -------
m = build_house
m.set_attribute('InteriorPro', 'roof_style', 'hip')
RF.build_roof!(level: 1)
roofs = RF.roofs
ok('two roofs were built', roofs.length == 2, roofs.length)
groof = RF.roof_of_wall_id('gS')
hroof = RF.roof_of_wall_id('h2')
ok('the garage roof and the house roof are two different roofs', groof && hroof && !groof.equal?(hroof))
ok('the garage back wall belongs to the garage roof', RF.roof_of_wall_id('gN').equal?(groof), RF.roof_wall_ids(groof))
ok('the house wall 68ea belongs to the house roof', RF.roof_of_wall_id('h5').equal?(hroof), RF.roof_wall_ids(hroof))
ok('the garage roof does not claim the house wall it dies into', !RF.roof_wall_ids(groof).include?('h5') && !RF.roof_wall_ids(groof).include?('h7'), RF.roof_wall_ids(groof))
fp = Array(groof && groof.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.round(2), y.round(2)] }
ok('the garage roof is built on the same footprint as before',
   fp.sort == [[-334.5, 201.0], [-334.5, 481.5], [-50.5, 201.0], [-50.5, 481.5]].sort, fp)

# ---- 4. the kill switch ---------------------------------------------------
RF.send(:remove_const, :USE_SWALLOWED_OWNERS)
RF.const_set(:USE_SWALLOWED_OWNERS, false)
m = build_house
m.set_attribute('InteriorPro', 'roof_style', 'hip')
RF.build_roof!(level: 1)
ok('kill switch: the merged walls have no roof again, as before', RF.roof_of_wall_id('gN').nil? && RF.roof_of_wall_id('h5').nil?)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

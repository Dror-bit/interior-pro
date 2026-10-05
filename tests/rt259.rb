# encoding: utf-8
# rt259 - WHEN ONE ROOF CHANGES, THE ROOFS IT MEETS FOLLOW (2026-10-04).
#
# "עכשיו החזרתי את הגג להיפ וגג הגראג שוב לא משתלב טוב" - and his law of two days
# before: "קודם אנחנו קובעים את גג האמא, הגג הגדול, ואליו הגג של הגראג' מתחבר
# ומשתנה לפי גג האמא".
#
# MEASURED on his Aetna model (roof_meet_report.txt + pictures 20:26, then
# foreign_mark_report.txt 20:27): he took the Gable end off the wall in the
# middle of the house roof. The click rebuilt the roof that owns that wall and
# only it; the garage roof still stood as built for the gable that was gone
# (eave 81.125, stopped on the gable's line) and the floor showed through the
# gap from above. Garage rebuilt, then the house: eave 84.0, "2 plane(s)
# carried on to the roof above", no gap.
#
# WHAT IS PINNED HERE:
#   * the pure rule: which standing roofs meet the one that changed;
#   * the real path, the Gable Ends click, on his walls, BOTH ways: the gable
#     in the middle taken off, and put on - after the click the two roofs are
#     face for face the roofs one Apply builds from nothing;
#   * a click on the LOWER roof's wall: the taller roof is built again too;
#   * the Edit Roof panel's Apply takes the same path;
#   * the kill switch: only the clicked roof is rebuilt, as before.
ENV['REAL_ROOMS'] = '1'
require 'stringio'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'
require './roof_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager

# ---- 1. the pure rule ---------------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:meet_follow!) && RF.respond_to?(:meet_partner_indices) &&
                         RF.const_defined?(:USE_MEET_FOLLOW, false))
if RF.respond_to?(:meet_partner_indices)
  sq = ->(x0, y0, x1, y1, rz, lv = 1) { { pts: [[x0, y0], [x1, y0], [x1, y1], [x0, y1]], ridge_z: rz, level: lv } }
  big = sq.call(0.0, 100.0, 600.0, 400.0, 145.0)
  r = RF.meet_partner_indices(big, [sq.call(300.0, -180.0, 580.0, 100.0, 113.0)])
  ok('a lower roof that reaches it', r == [[0], []], r)
  r = RF.meet_partner_indices(sq.call(300.0, -180.0, 580.0, 100.0, 113.0), [big])
  ok('a taller roof that reaches it', r == [[], [0]], r)
  r = RF.meet_partner_indices(big, [sq.call(300.0, -180.0, 580.0, 100.0, 145.2)])
  ok('the same height: no valley between them, nobody follows', r == [[], []], r)
  r = RF.meet_partner_indices(big, [sq.call(900.0, -180.0, 1200.0, 100.0, 113.0)])
  ok('standing apart: nobody follows', r == [[], []], r)
  r = RF.meet_partner_indices(big, [sq.call(300.0, -180.0, 580.0, 100.0, 113.0, 2)])
  ok('another storey: nobody follows', r == [[], []], r)
  r = RF.meet_partner_indices(big, [nil, sq.call(300.0, -180.0, 580.0, 100.0, 113.0), sq.call(0.0, 400.0, 200.0, 600.0, 160.0)])
  ok('an unreadable roof is left alone; lower and taller are told apart', r == [[1], [2]], r)
  ok('no roof: nothing', RF.meet_partner_indices(nil, [big]) == [[], []])
end

# ---- his walls, as in rt257 ------------------------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],   # his 68ea3160
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']   # his 4743a286
].freeze

def quiet
  old = $stdout
  $stdout = StringIO.new
  begin
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end

# one Apply from nothing, with these marks saved
def build(gable, hip = [])
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_wall_ids', gable)
  Sketchup.active_model.set_attribute('InteriorPro', 'roof_hip_wall_ids', hip)
  quiet { RF.build_roof!(level: 1, style: 'gable', pitch: 3.0) }
end

def wall(id)
  Sketchup.active_model.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == id }
end

def house
  RF.roof_of_wall_id('h2')
end

def garage
  RF.roof_of_wall_id('gS')
end

def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(1), p.y.to_f.round(1), p.z.to_f.round(1)] }.sort }.sort
end

def shape(r)
  [r.get_attribute('InteriorPro', 'eave_z').to_f.round(3), r.get_attribute('InteriorPro', 'ridge_z').to_f.round(3),
   Array(r.get_attribute('InteriorPro', 'gable_edges')), Array(r.get_attribute('InteriorPro', 'cross_edges')),
   Array(r.get_attribute('InteriorPro', 'footprint_xy')).map { |v| v.to_f.round(2) }]
end

# the two roofs one Apply builds from nothing: without the gable in the middle, and with it
build([], %w[h5])
PLAIN = { house: faces(house), garage: faces(garage), hs: shape(house), gs: shape(garage) }.freeze
build(%w[h5])
CROSS = { house: faces(house), garage: faces(garage), hs: shape(house), gs: shape(garage) }.freeze
ok('from nothing: the gable in the middle sets the garage roof 2.875" lower',
   (PLAIN[:gs][0] - CROSS[:gs][0] - 2.875).abs < 0.01 && CROSS[:hs][3] != [] && PLAIN[:hs][3] == [], [PLAIN[:gs], CROSS[:gs], CROSS[:hs][3]])
ok('...and the two garage roofs really are different roofs', PLAIN[:garage] != CROSS[:garage])

# ---- 2. the click that takes the gable in the middle OFF --------------------------------
build(%w[h5])
g_before = garage
log = quiet { RF.set_roof_end!(wall('h5'), :hip) }
ok('the mark is gone', RF.gable_wall_ids == [] && RF.hip_wall_ids == %w[h5], [RF.gable_wall_ids, RF.hip_wall_ids])
ok('the builder says the lower roof follows, and the house is built once more',
   log =~ /the roof above changed - this roof is built again to meet it/ &&
   log =~ /the roof below was built again - this roof is built once more, cut for it/, log.lines.grep(/valley: the roof/))
ok('the garage roof is a new one', !g_before.valid? && garage && garage.valid?)
ok('the garage roof is back where one Apply from nothing puts it', shape(garage) == PLAIN[:gs], [shape(garage), PLAIN[:gs]])
ok('...face for face', faces(garage) == PLAIN[:garage])
ok('the house roof too, face for face', shape(house) == PLAIN[:hs] && faces(house) == PLAIN[:house], [shape(house), PLAIN[:hs]])
ok('two roofs stand, no more', RF.roofs.length == 2, RF.roofs.length)

# ---- 3. the click that puts it ON --------------------------------------------------------
build([], %w[h5])
log = quiet { RF.set_roof_end!(wall('h5'), :gable) }
ok('put on: the garage roof meets the gable, as one Apply from nothing builds it',
   shape(garage) == CROSS[:gs] && faces(garage) == CROSS[:garage], [shape(garage), CROSS[:gs]])
ok('put on: the house roof too', shape(house) == CROSS[:hs] && faces(house) == CROSS[:house], [shape(house), CROSS[:hs]])
ok('put on: the garage says it ends on the gable', log =~ /stands a gable here/)

# ---- 4. a click on the LOWER roof's wall: the taller roof is built again ------------------
build(%w[h5])
h_before = house
g_before = garage
log = quiet { RF.set_roof_end!(wall('gS'), :hip) }
ok('the lower roof changed: the taller one is built again, cut for it',
   log =~ /the roof below changed - this roof is built again, cut for it/ && !h_before.valid? && house.valid?, log.lines.grep(/valley: the roof/))
ok('...and the lower roof is built ONCE (nothing under it)', log.lines.grep(/over level 1: eave 8/).length == 1, log.lines.grep(/over level 1/))
ok('...the house roof is the roof it was', shape(house) == CROSS[:hs], [shape(house), CROSS[:hs]])

# ---- 5. the Edit Roof panel takes the same path ---------------------------------------------
build(%w[h5])
InteriorPro::RoofDialog.show(house)
dlg = InteriorPro::RoofDialog.instance_variable_get(:@dialog)
g_before = garage
log = quiet do
  dlg.callbacks['apply_roof'].call(nil, 'hip', '3', 'true', '12', 'true', '8', 'true', '#584e4a', '#ffffff',
                                   'color', '0', 'true', 'none', '', 'false', '')
end
tgt = InteriorPro::RoofDialog.instance_variable_get(:@target)
ok('the panel: Hip on the house drops her marks and the garage roof follows',
   RF.gable_wall_ids == [] && !g_before.valid? && log =~ /the roof above changed - this roof is built again to meet it/,
   [RF.gable_wall_ids, log.lines.grep(/valley: the roof/)])
ok('the panel keeps editing the house roof that stands now', tgt && tgt.valid? && tgt == house &&
                                                           tgt.get_attribute('InteriorPro', 'roof_style') == 'hip')
ok('the garage no longer ends on a gable that is gone', Array(house.get_attribute('InteriorPro', 'cross_edges')) == [] &&
                                                      log !~ /stands a gable here/)

# ---- 6. a roof that meets nobody is built once -----------------------------------------------
Sketchup.reset_model!
[['a', 0.0, 0.0, 300.0, 0.0], ['b', 300.0, 0.0, 300.0, 200.0], ['c', 300.0, 200.0, 0.0, 200.0], ['d', 0.0, 200.0, 0.0, 0.0]].each do |id, sx, sy, ex, ey|
  g = Sketchup.active_model.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey, 'thickness' => 5.0, 'base_z' => 0.0,
    'height' => 96.0, 'level' => 1, 'wall_category' => 'exterior', 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
end
quiet { RF.build_roof!(level: 1, style: 'hip', pitch: 4.0) }
log = quiet { RF.set_roof_end!(wall('b'), :gable) }
ok('one roof alone: built once, no word about following', log.lines.grep(/over level 1/).length == 1 && log !~ /valley: the roof/, log.lines.grep(/over level|valley: the roof/))

# ---- 7. the kill switch -----------------------------------------------------------------------
RF.send(:remove_const, :USE_MEET_FOLLOW)
RF.const_set(:USE_MEET_FOLLOW, false)
build(%w[h5])
g_before = garage
log = quiet { RF.set_roof_end!(wall('h5'), :hip) }
ok('switched off: only the clicked roof is rebuilt, as before', g_before.valid? && garage == g_before && shape(garage) == CROSS[:gs] &&
                                                               log !~ /valley: the roof (above|below)/ && log.lines.grep(/over level 1/).length == 1)
RF.send(:remove_const, :USE_MEET_FOLLOW)
RF.const_set(:USE_MEET_FOLLOW, true)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

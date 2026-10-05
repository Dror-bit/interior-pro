# encoding: utf-8
# rt260 - THE FOOT OF A GABLE IN THE MIDDLE OF A ROOF HAS NO BOX (2026-10-04).
#
# His picture of the entry of the Aetna house: "בדיקה למה זה לא מתחבר סמוך הפשייה
# כאן - במקרה הזה לא צריך כאן קובייה אם הם ממשיכים אפילו שיפוע שונה וצריך לסגור את
# החור שם".
#
# MEASURED on his model (fascia_corner_report.txt, corner -419.0,452.5, eave 102):
# the eave of the house roof and the rake of the gable in its middle lie on one
# line. The flat soffit ended square on the corner at z 93.0; the rake's soffit
# began one overhang further on, at x -407 and z 96.0, behind the step and the
# skirt of a box return; from under the 12" between them the rays went straight up
# to the deck (99.8 - 101.8). The box return is for a corner of the building,
# where the eave's board turns the corner and fills the square under the rake.
#
# WHAT IS PINNED HERE:
#   * the pure rule: which ends of a rake have a neighbour that runs straight on;
#   * rake_returns: no box return at such an end - and still nil ("both allowed")
#     when nothing is special, so every other roof is the roof it was;
#   * the real path, on his walls with a boxed soffit: no step at x -407, the
#     rake's soffit starts on the corner at the flat one's height, and the 12"
#     that were open are covered;
#   * the other foot (a real corner of the house) and the garage roof are face
#     for face what they were; so is the whole house with no gable in the middle;
#   * the kill switch brings the box, and the gap, back.
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

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager

# ---- 1. the pure rules ----------------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:rake_straight_ends) && RF.const_defined?(:USE_STRAIGHT_RAKE_FOOT, false))
SQ = [[0.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
# the south side cut in three: eave | gable in the middle | eave
MID = [[0.0, 0.0], [200.0, 0.0], [400.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
# ...and the gable reaching the east corner of the house (his roof)
HIS = [[0.0, 0.0], [330.0, 0.0], [600.0, 0.0], [600.0, 300.0], [0.0, 300.0]].freeze
if RF.respond_to?(:rake_straight_ends)
  ok('an edge between two corners of the building: neither end', RF.rake_straight_ends(SQ, 0) == [false, false] &&
                                                                 RF.rake_straight_ends(SQ, 3) == [false, false])
  ok('a stretch in the middle of a straight side: both ends', RF.rake_straight_ends(MID, 1) == [true, true], RF.rake_straight_ends(MID, 1))
  ok('his gable: straight on at its west foot, a corner at its east', RF.rake_straight_ends(HIS, 1) == [true, false], RF.rake_straight_ends(HIS, 1))
  ok('the eave beside it: a corner at its start, straight on at its end', RF.rake_straight_ends(HIS, 0) == [false, true], RF.rake_straight_ends(HIS, 0))
  ok('a turn back on the same line is not straight on', RF.rake_straight_ends([[0.0, 0.0], [100.0, 0.0], [50.0, 0.0], [50.0, 80.0]], 0)[1] == false)
  ok('a slight angle is a corner', RF.rake_straight_ends([[0.0, 0.0], [300.0, 0.0], [600.0, 3.0], [600.0, 300.0], [0.0, 300.0]], 0)[1] == false)
  ok('fewer than three corners: nothing, no error', RF.rake_straight_ends([[0.0, 0.0], [1.0, 0.0]], 0) == [false, false])
  ok('rake_returns: nothing special -> nil, both allowed, as before', RF.rake_returns(SQ, 0, nil).nil?)
  ok('rake_returns: abut flags alone answer as before', RF.rake_returns(SQ, 0, [false, true, false, false]) == [true, false] &&
                                                       RF.rake_returns(SQ, 0, [false, false, false, true]) == [false, true])
  ok('rake_returns: no box at the foot that runs straight on', RF.rake_returns(HIS, 1, nil) == [false, true] &&
                                                             RF.rake_returns(MID, 1, nil) == [false, false], [RF.rake_returns(HIS, 1, nil), RF.rake_returns(MID, 1, nil)])
  ok('rake_returns: an abut end stays without one too', RF.rake_returns(HIS, 1, [false, false, true, false, false]) == [false, false])
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

def build(marks)
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  old = $stdout
  $stdout = StringIO.new
  begin
    # his panel: boxed soffit, 12" overhang, 6" fascia, drip
    RF.build_roof!(level: 1, style: 'gable', pitch: 3.0, overhang: 12.0, fascia: true, fascia_depth: 6.0, drip: true, soffit: 'boxed')
    $stdout.string
  ensure
    $stdout = old
  end
end

def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } }
end

def norm(fs)
  fs.map(&:sort).sort
end

# the lowest face over plan point (x, y), by its own corners (nil = open)
def lowest_over(fs, x, y)
  best = nil
  fs.each do |ps|
    next if ps.map { |p| p[0] }.uniq.length < 2 || ps.map { |p| p[1] }.uniq.length < 2 # stands upright
    inside = false
    ps.each_with_index do |a, k|
      b = ps[(k + 1) % ps.length]
      next unless (a[1] > y) != (b[1] > y)
      inside = !inside if x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
    end
    next unless inside
    # the height of the face's own plane over the point
    p0 = ps[0]
    z = nil
    ps.each_cons(2) do |p1, p2|
      nx = (p1[1] - p0[1]) * (p2[2] - p0[2]) - (p1[2] - p0[2]) * (p2[1] - p0[1])
      ny = (p1[2] - p0[2]) * (p2[0] - p0[0]) - (p1[0] - p0[0]) * (p2[2] - p0[2])
      nz = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0])
      next if nz.abs < 1.0e-6
      z = p0[2] - (nx * (x - p0[0]) + ny * (y - p0[1])) / nz
      break
    end
    next if z.nil?
    best = z if best.nil? || z < best
  end
  best
end

def step_faces(fs, x)
  fs.select { |ps| ps.all? { |p| (p[0] - x).abs < 0.01 } && ps.map { |p| p[1] }.minmax.reduce { |a, b| b - a } > 10.0 && ps.all? { |p| p[2] < 97.0 } }
end

log = build(%w[h5])
house = RF.roof_of_wall_id('h2')
garage = RF.roof_of_wall_id('gS')
ez = house.get_attribute('InteriorPro', 'eave_z').to_f
fp = Array(house.get_attribute('InteriorPro', 'footprint_xy')).each_slice(2).map { |x, y| [x.round(1), y.round(1)] }
ok('his roof: eave 102, the gable in the middle starts at -419.0,452.5', (ez - 102.0).abs < 0.01 && fp.include?([-419.0, 452.5]), [ez, fp])
on = faces(house)
on_g = faces(garage)

# ---- 2. the foot that runs straight on -----------------------------------------------------
ok('no step and no end of a board one overhang past the corner (x -407)', step_faces(on, -407.0).empty?, step_faces(on, -407.0))
ok('the flat soffit still ends square on the corner, at z 93.0',
   on.any? { |ps| ps.map(&:sort) && ps.sort == [[-419.0, 453.25, 93.0], [-419.0, 453.25, 93.75], [-419.0, 464.5, 93.0], [-419.0, 464.5, 93.75]] })
rake = on.find { |ps| ps.length == 4 && ps.map { |p| p[0] }.min == -419.0 && ps.map { |p| p[2] }.min == 93.0 && ps.map { |p| p[2] }.max > 100.0 &&
                      ps.map { |p| p[1] }.sort.uniq == [453.25, 464.5] }
ok('the rake s soffit starts ON the corner, at the height the flat one ends at', !rake.nil?, on.select { |ps| ps.map { |p| p[0] }.min == -419.0 }.first(6))
[[-417.0, 455.0], [-413.0, 459.0], [-409.0, 463.0]].each do |x, y|
  z = lowest_over(on, x, y)
  want = 93.0 + (x + 419.0) * 0.25
  ok(format('under (%.0f,%.0f): the rake s soffit, %.2f - nothing is open', x, y, want), z && (z - want).abs < 0.02, z)
end
ok('under the eave side nothing moved: the flat soffit at 93.0', lowest_over(on, -425.0, 459.0) == 93.0, lowest_over(on, -425.0, 459.0))
ok('past the old step the rake s soffit is where it was', (lowest_over(on, -395.0, 459.0).to_f - 99.0).abs < 0.02, lowest_over(on, -395.0, 459.0))

# ---- 3. the kill switch: the box, and the gap --------------------------------------------------
RF.send(:remove_const, :USE_STRAIGHT_RAKE_FOOT)
RF.const_set(:USE_STRAIGHT_RAKE_FOOT, false)
build(%w[h5])
off = faces(RF.roof_of_wall_id('h2'))
off_g = faces(RF.roof_of_wall_id('gS'))
build([])
plain_off = faces(RF.roof_of_wall_id('h2'))
RF.send(:remove_const, :USE_STRAIGHT_RAKE_FOOT)
RF.const_set(:USE_STRAIGHT_RAKE_FOOT, true)
ok('switched off: the step stands one overhang past the corner again', !step_faces(off, -407.0).empty?)
z = lowest_over(off, -413.0, 459.0)
ok('switched off: the 12" under it are open up to the deck, as measured on his model', z.nil? || z > 98.0, z)

# ---- 4. nothing else moved --------------------------------------------------------------------
far = ->(fs) { norm(fs.reject { |ps| ps.any? { |p| p[0] > -420.0 && p[0] < -406.0 && p[1] < 465.0 && p[2] < 100.0 } }) }
ok('everything away from that foot is face for face what it was - the other foot, a real corner, too', far.call(on) == far.call(off),
   [(far.call(on) - far.call(off)).first(3), (far.call(off) - far.call(on)).first(3)])
ok('the box at the other foot (-134) still stands', !on.select { |ps| ps.all? { |p| (p[0] + 146.0).abs < 0.01 } && ps.all? { |p| p[2] < 97.0 } }.empty? ||
                                                    norm(on.select { |ps| ps.all? { |p| p[0] > -160.0 } }) == norm(off.select { |ps| ps.all? { |p| p[0] > -160.0 } }))
ok('the garage roof is face for face what it was', norm(on_g) == norm(off_g))
build([])
ok('no gable in the middle: the whole house roof is face for face what it was', norm(faces(RF.roof_of_wall_id('h2'))) == norm(plain_off))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt137 - THE GABLE TRIANGLE IS A CONTINUATION OF THE WALL (2026-09-12).
#
# WHY
# MEASURED on his model (gable_wall_mat_report.txt, 2026-09-12):
#   * the material named "Board and Batten" was NO TEXTURE, rgb(0,0,0) -
#     there is no board_and_batten.jpg, so load_or_create_material made an
#     empty BLACK material and the wall under the roof was painted with it
#   * every gable wall top in the model had ZERO sub-groups inside - not a
#     single board - while the wall below it carried real 3D strips
# His words: "הוא צריך להיות המשך של הקיר של הבית וגם הסיידינג אותו דבר".
#
# WHAT IS PINNED HERE
# 1. A 3D-siding wall paints its face WHITE and gets real boards. The
#    triangle now does the same: white, never the empty black material.
# 2. A flat-texture wall (Stucco, Brick...) is untouched - it still gets
#    its own material and no boards.
# 3. The lap-siding courses are cut to the rake: no board ever stands
#    taller than the roof above it, and a course clear of the roof is ONE
#    board, not a row of stubs.
# 4. The battens line up with the wall underneath - same origin, same
#    16" spacing - so the strips do not step sideways at the eave.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

RF = InteriorPro::RoofManager

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}#{extra.nil? ? '' : "   << #{extra.inspect}"}"
    FAILS << name
  end
end

# --- 1. which materials are real boards, not textures -----------------
ok('Board and Batten is known to be 3D', RF::SIDING_3D_NAMES.include?('Board and Batten'))
ok('Horizontal Siding is known to be 3D', RF::SIDING_3D_NAMES.include?('Horizontal Siding'))
ok('Stucco is NOT', !RF::SIDING_3D_NAMES.include?('Stucco'))
ok('Brick is NOT', !RF::SIDING_3D_NAMES.include?('Brick'))

src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('THE BLACK BUG: a 3D-siding name is painted white, not by its name',
   src.include?("face_name = siding ? '#ffffff' : ext_name"), nil)
ok('...on the mitred shed corner too',
   src.include?("face_name = SIDING_3D_NAMES.include?(ext_name.to_s) ? '#ffffff' : ext_name"),
   nil)

# --- 2. the outline of a gable triangle, as (t, z) --------------------
# 240 wide, wall top at z=96, ridge at z=156 in the middle
TZ = [[0.0, 96.0], [120.0, 156.0], [240.0, 96.0], [240.0, 0.0], [0.0, 0.0]].freeze

ok('at the left end the wall is 96 tall', (RF.tz_top_at(TZ, 0.0) - 96.0).abs < 1e-6,
   RF.tz_top_at(TZ, 0.0))
ok('under the ridge it is 156', (RF.tz_top_at(TZ, 120.0) - 156.0).abs < 1e-6,
   RF.tz_top_at(TZ, 120.0))
ok('half way up the rake it is 126', (RF.tz_top_at(TZ, 60.0) - 126.0).abs < 1e-6,
   RF.tz_top_at(TZ, 60.0))

# --- 3. the courses are cut to the rake -------------------------------
# a course that is clear of the roof all the way across = ONE board
low = RF.gable_course_runs(TZ, 0.0, 240.0, 60.0, 66.0, 6.0)
ok('a course clear of the roof is one long board', low.length == 1, low)
ok('...and it spans the whole gable',
   low[0] && (low[0][0] - 0.0).abs < 1e-6 && (low[0][1] - 240.0).abs < 1e-6, low)
ok('...at its full height', low[0] && (low[0][2] - 66.0).abs < 1e-6, low)

# a course up in the triangle is stepped, and never taller than the roof
high = RF.gable_course_runs(TZ, 0.0, 240.0, 132.0, 138.0, 6.0)
ok('a course inside the triangle is broken into steps', high.length > 1, high.length)
ok('NO BOARD POKES THROUGH THE ROOF',
   high.all? { |ta, tb, zt| zt <= [RF.tz_top_at(TZ, ta), RF.tz_top_at(TZ, tb)].min + 1e-6 },
   high)
ok('...and it stays inside the gable',
   high.all? { |ta, tb, _z| ta >= 0.0 - 1e-6 && tb <= 240.0 + 1e-6 }, high)
ok('a course above the ridge builds nothing',
   RF.gable_course_runs(TZ, 0.0, 240.0, 160.0, 166.0, 6.0).empty?, nil)

# --- 4. the battens line up with the wall below -----------------------
st = RF.gable_batten_stations(0.0, 240.0, 0.0, 16.0, 0.75)
ok('the first batten is half a spacing in, like the wall',
   st.first && (st.first - 8.0).abs < 1e-6, st.first)
ok('and they are 16 apart', st.each_cons(2).all? { |a, b| (b - a - 16.0).abs < 1e-6 }, st)
ok('none of them hangs off the end',
   st.all? { |t| t >= 0.75 && t <= 240.0 - 0.75 }, st)

# the wall below starts 30 further back: the gable must follow IT, not its
# own left edge, or the strips step sideways at the eave line
sh = RF.gable_batten_stations(0.0, 240.0, -30.0, 16.0, 0.75)
ok('THE ALIGNMENT: the stations follow the wall origin, not the gable edge',
   sh.all? { |t| ((t + 30.0 - 8.0) % 16.0).abs < 1e-6 ||
                 (((t + 30.0 - 8.0) % 16.0) - 16.0).abs < 1e-6 }, sh)
ok('...and still none hangs off the end',
   sh.all? { |t| t >= 0.75 && t <= 240.0 - 0.75 }, sh)

# --- 5. the crash: no two boards share a plane inside one group -------
# MEASURED 2026-09-12 (apply_probe_log.txt): the roof rebuilt clean with
# the boards off and killed SketchUp with them on. Stepped neighbours in
# one group touch face to face, SketchUp merges them, and push-pull into
# that merge takes the whole application down.
ok('each lap board gets a group of its own',
   src =~ /bg = sg\.entities\.add_group.*?builder\.build_siding_board!\(\s*\n\s*bg,/m, nil)
ok('...and an empty one is thrown away',
   src.include?('bg.erase!'), nil)
ok('one bad board cannot take the roof down with it',
   src =~ /rescue StandardError => e\s*\n\s*puts "\[Roof\] gable board skipped/, nil)

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

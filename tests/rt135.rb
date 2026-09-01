# encoding: utf-8
# rt135 - AN END HE SET TO HIP STAYS HIP, EVEN ON THE GABLE STYLE (2026-09-12).
#
# WHY
# He clicked a wall with the Gable Ends tool, chose Hip from the menu, and
# the roof did not change: "אם אני רוצה לשנות צלע של גג מסויים להיפ
# בכפתור ה-ROOF HIP זה לא עובד". MEASURED on his model (roof_end_report.txt,
# 2026-09-12): both roofs style="gable", seven of his eight walls reported
# end=hip, and both roofs were built with gables anyway.
#
# THE CAUSE the report showed: a hip was only the ABSENCE of a gable mark.
# assemble_framed_plan, on the Gable style, gables every wing and both main
# ends by itself when it finds no marks - so there was nothing for the hip
# choice to switch off, and pick_gable_edges did the same in the fallback.
#
# WHAT IS PINNED HERE
# 1. Gable style with NO hip marks builds exactly what it built before.
# 2. One end marked hip: that end stops gabling, the opposite one keeps its
#    gable. This is the line that fails on yesterday's code.
# 3. A hip mark on a wing's end leaves that wing hipped.
# 4. Hip marks change NOTHING on the Hip style with explicit gable marks -
#    a mark he made himself still wins there.
# 5. set_roof_end! stores the three states exclusively: hip / gable / dutch,
#    one wall never lands in two lists.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './level_manager'

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

# a plain 480 x 300 rectangle, CCW, one wall id per edge
#   edge 0 = south (y=0), 1 = east (x=480), 2 = north (y=300), 3 = west
RECT = [[0.0, 0.0], [480.0, 0.0], [480.0, 300.0], [0.0, 300.0]].freeze
IDS = %w[s e n w].freeze

# --- 1. nothing marked: the Gable style is untouched ------------------
g0 = RF.framed_plan(RECT, IDS, [], 'gable')
ok('gable style with no marks still gables the two short ends',
   g0 && g0[:g][:e] && g0[:g][:w], g0 && g0[:g])
ok('...and leaves the long sides alone',
   g0 && !g0[:g][:n] && !g0[:g][:s], g0 && g0[:g])

# --- 2. one end set to hip -------------------------------------------
g1 = RF.framed_plan(RECT, IDS, [], 'gable', [], ['e'])
ok('THE BUG: the end he set to hip does not gable', g1 && !g1[:g][:e],
   g1 && g1[:g])
ok('and the opposite end still gables', g1 && g1[:g][:w], g1 && g1[:g])
ok('only one poly edge is left gabled', g1 && g1[:edges] == [3], g1 && g1[:edges])

# --- 3. both ends set to hip: no gable end is left --------------------
g2 = RF.framed_plan(RECT, IDS, [], 'gable', [], %w[e w])
ok('hipping both ends leaves the gable style with nothing to gable',
   g2.nil? || g2[:edges].empty?, g2 && g2[:edges])

# --- 4. a hip mark cannot cancel a gable he made himself --------------
h1 = RF.framed_plan(RECT, IDS, %w[e w], 'hip', [], ['e'])
ok('an explicit gable mark still wins on the hip style',
   h1 && h1[:g][:e] && h1[:g][:w], h1 && h1[:g])

# --- 5. an L-shaped plan: the wing keeps its hip ----------------------
# main 480x300 with a 120-deep wing off the north side, x 120..300
L = [[0.0, 0.0], [480.0, 0.0], [480.0, 300.0], [300.0, 300.0],
     [300.0, 420.0], [120.0, 420.0], [120.0, 300.0], [0.0, 300.0]].freeze
LIDS = %w[a b c d e f g h].freeze
w0 = RF.framed_plan(L, LIDS, [], 'gable')
ok('gable style gables the wing end by itself',
   w0 && w0[:wings].any? { |w| w[:gabled] }, w0 && w0[:wings])
w1 = RF.framed_plan(L, LIDS, [], 'gable', [], ['e'])
ok('...but not the wing end he set to hip',
   w1 && w1[:wings].none? { |w| w[:gabled] }, w1 && w1[:wings])

# --- 6. the three states are stored exclusively -----------------------
model = Sketchup.active_model
wall = model.entities.add_group
wall.set_attribute('InteriorPro', 'type', 'wall')
wall.set_attribute('InteriorPro', 'id', 'w1')

RF.set_roof_end!(wall, :gable)
ok('gable: in the gable list, not in the hip list',
   RF.gable_wall_ids.include?('w1') && !RF.hip_wall_ids.include?('w1'),
   [RF.gable_wall_ids, RF.hip_wall_ids])

RF.set_roof_end!(wall, :dutch)
ok('dutch: still a gable, and still not a hip',
   RF.gable_wall_ids.include?('w1') && RF.dutch_wall_ids.include?('w1') &&
     !RF.hip_wall_ids.include?('w1'),
   [RF.gable_wall_ids, RF.dutch_wall_ids, RF.hip_wall_ids])

RF.set_roof_end!(wall, :hip)
ok('hip: REMEMBERED in the hip list',
   RF.hip_wall_ids.include?('w1'), RF.hip_wall_ids)
ok('...and gone from the gable and dutch lists',
   !RF.gable_wall_ids.include?('w1') && !RF.dutch_wall_ids.include?('w1'),
   [RF.gable_wall_ids, RF.dutch_wall_ids])
ok('roof_end_of agrees', RF.roof_end_of('w1') == :hip, RF.roof_end_of('w1'))

RF.set_roof_end!(wall, :gable)
ok('back to gable: the hip mark is dropped again',
   !RF.hip_wall_ids.include?('w1') && RF.gable_wall_ids.include?('w1'),
   [RF.hip_wall_ids, RF.gable_wall_ids])

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

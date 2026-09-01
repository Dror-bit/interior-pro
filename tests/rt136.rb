# encoding: utf-8
# rt136 - SHED IS THE FOURTH ROOF END, NOT A BUTTON OF ITS OWN (2026-09-12).
#
# WHY
# MEASURED on his model (roof_end_report.txt, 2026-09-12): wall 817ec169
# was in the shed list AND the gable list AND the dutch list at the same
# time, one roof was style "shed", and neither Hip nor Gable would take.
# Two separate ways to mark the same wall is what allowed it - the UI rule
# in CLAUDE.md ("no duplicate ways to do the same thing") written the hard
# way. His call: fold shed into the Roof End menu and drop the button.
#
# WHAT IS PINNED HERE
# 1. Shed is one of the four states roof_end_of can answer, and it is
#    answered FIRST - it owns the whole roof, not just this end.
# 2. Picking Shed makes THIS wall the only shed eave and clears the gable,
#    dutch and hip marks on it. One wall is never in two lists again.
# 3. Picking Hip/Gable/Dutch on the shed eave takes the shed mark off AND
#    moves the style off 'shed'. Leaving the style behind is the exact trap
#    he hit: mark gone, style still shed, nothing happened.
# 4. The Shed Roof button is off the toolbar and the Roof Ends button says
#    all four.
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

model = Sketchup.active_model
def wall(model, id)
  g = model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', id)
  g
end
w1 = wall(model, 'w1')
w2 = wall(model, 'w2')

# --- 1. shed is a state of its own, asked first ----------------------
RF.set_roof_end!(w1, :shed)
ok('shed: roof_end_of says shed', RF.roof_end_of('w1') == :shed, RF.roof_end_of('w1'))
ok('shed: it is the only shed eave', RF.shed_wall_ids == ['w1'], RF.shed_wall_ids)

# --- 2. one wall is never in two lists -------------------------------
RF.set_roof_end!(w1, :dutch)
ok('dutch: the shed mark is gone', !RF.shed_wall_ids.include?('w1'), RF.shed_wall_ids)
ok('dutch: and it is a dutch gable now', RF.roof_end_of('w1') == :dutch,
   RF.roof_end_of('w1'))

RF.set_roof_end!(w1, :shed)
ok('back to shed: the gable mark is dropped',
   !RF.gable_wall_ids.include?('w1'), RF.gable_wall_ids)
ok('back to shed: the dutch mark is dropped',
   !RF.dutch_wall_ids.include?('w1'), RF.dutch_wall_ids)
ok('back to shed: and it is not a hip either',
   !RF.hip_wall_ids.include?('w1'), RF.hip_wall_ids)
ok('THE MEASURED BUG: no wall sits in two lists at once',
   ([RF.shed_wall_ids, RF.gable_wall_ids, RF.dutch_wall_ids,
     RF.hip_wall_ids].flatten.tally.values.max || 0) <= 1,
   [RF.shed_wall_ids, RF.gable_wall_ids, RF.dutch_wall_ids, RF.hip_wall_ids])

# --- 3. a second wall picking shed takes the eave over ----------------
RF.set_roof_end!(w2, :shed)
ok('the shed eave moves, it does not pile up', RF.shed_wall_ids == ['w2'],
   RF.shed_wall_ids)

# --- 4. leaving shed also leaves the shed STYLE -----------------------
RF.set_roof_end!(w2, :gable)
ok('off shed: the mark is gone', RF.shed_wall_ids.empty?, RF.shed_wall_ids)
ok('off shed: and it is a gable end', RF.roof_end_of('w2') == :gable,
   RF.roof_end_of('w2'))

# the style is only pushed when there IS a roof to rebuild, so this checks
# the decision itself, in the source: gable/dutch -> 'gable', hip -> 'hip'
src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('picking Shed rebuilds with the shed style',
   src.include?("style_override = 'shed'"), nil)
ok('picking anything else moves the style OFF shed',
   src.include?("style_override = (kind == :hip ? 'hip' : 'gable')"), nil)

# --- 5. the toolbar has no Shed button any more -----------------------
tb = File.read('toolbar.rb', encoding: 'UTF-8')
ok('the Shed Roof button is gone', !tb.include?("UI::Command.new('Shed Roof')"))
ok('...and nothing adds it', !tb.include?('tb.add_item(shed_cmd)'))
ok('the Roof Ends button names all four',
   tb =~ /gable_cmd\.tooltip.*hip, gable, Dutch gable or shed/, nil)

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

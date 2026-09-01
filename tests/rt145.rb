# encoding: utf-8
# rt145 - ANY OTHER END ON A SHED ROOF ENDS THE SHED (2026-09-13).
#
# "יצרתי גג שד מהתחלה וסימנתי צלע של הגג כדי להפוך אותה לגג אחר (גייבל
# לצורך העניין) והוא לא משנה אותה שאני לוחץ APPLY."
#
# THE CAUSE, read off set_roof_end!: only picking Hip/Gable/Dutch on the
# shed's OWN low eave took the style off 'shed' (rt136). Marking a
# DIFFERENT edge stored the mark and left the style alone - and a shed
# roof INVERTS every mark it is given (one eave, everything else a rake),
# so the new gable mark did nothing at all. A shed has exactly one eave,
# so asking for any other end anywhere on it is a decision to stop being
# a shed.
#
# rt136 still pins the eave's own case; this pins the other edges.
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
w1 = wall(model, 'w1')   # the shed's low eave
w2 = wall(model, 'w2')   # another edge of the SAME roof
w3 = wall(model, 'w3')   # a wall on a different roof

# a standing shed roof that owns w1 and w2
roof = model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
roof.set_attribute('InteriorPro', 'roof_style', 'shed')
roof.set_attribute('InteriorPro', 'set_walls', %w[w1 w2])

# a second roof, so the fix cannot reach across and clear someone else's
other = model.entities.add_group
other.set_attribute('InteriorPro', 'type', 'roof')
other.set_attribute('InteriorPro', 'roof_style', 'shed')
other.set_attribute('InteriorPro', 'set_walls', %w[w3])

RF.set_roof_end!(w1, :shed)
ok('the shed eave is w1', RF.shed_wall_ids == ['w1'], RF.shed_wall_ids)

# --- the bug: gable on a DIFFERENT edge of the shed --------------------
RF.set_roof_end!(w2, :gable)
ok('w2 is now a gable end', RF.roof_end_of('w2') == :gable, RF.roof_end_of('w2'))
ok("and the roof's shed eave is released, so the mark can take effect",
   RF.shed_wall_ids.empty?, RF.shed_wall_ids)
ok('w1 is no longer a shed', RF.roof_end_of('w1') != :shed, RF.roof_end_of('w1'))

# --- it must not reach across to another roof -------------------------
RF.set_roof_end!(w3, :shed)
ok('w3 is the other roof s shed eave', RF.shed_wall_ids == ['w3'],
   RF.shed_wall_ids)
RF.set_roof_end!(w2, :gable)
ok('marking this roof again leaves the OTHER roof s shed alone',
   RF.shed_wall_ids == ['w3'], RF.shed_wall_ids)

# --- the decision itself ----------------------------------------------
src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('the style is asked off the roof that owns the wall',
   src.include?("cur_style = own ? own.get_attribute('InteriorPro', 'roof_style').to_s : ''"),
   nil)
ok('and a shed roof leaves shed for any other end',
   src.include?("elsif sheds.include?(id) || cur_style == 'shed'"), nil)

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

# encoding: utf-8
# rt146 - A WALL WITH NO ROOF OVER IT (2026-09-13).
#
# "מסמן את הקיר הזה ולוחץ על שד הוא מסמן לי את השד הצידה במקום לכיוון
# שבחרתי" / "זה עושה קפיצה ונשאר אותו הדבר".
#
# MEASURED, off his own Ruby Console:
#   [Roof] wall 12e16034...: GABLE end (1 gable, 1 dutch)
#   [Roof] ignoring 1 stale/off-loop gable mark(s)
#   [Roof] shed over level 2: ...
# He marked a GROUND FLOOR wall. That storey had no roof at all, so
# roof_of_wall_id found no owner - and the fallback rebuilt the TOP
# storey's roof instead. Hence the jump somewhere else on the screen,
# nothing changing where he was looking, and no style to move off 'shed'
# because there was no owner roof to read one from.
#
# WHAT IS PINNED HERE: with roofs that DO claim walls, a wall no roof
# owns rebuilds NOTHING - and the mark is still saved, so it takes effect
# as soon as a roof is built over that storey. An old model whose roofs
# claim no walls keeps the whole-model rebuild it always had.
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

up   = wall(model, 'up1')     # upstairs, has a roof
down = wall(model, 'down1')   # ground floor, no roof at all

roof = model.entities.add_group
roof.set_attribute('InteriorPro', 'type', 'roof')
roof.set_attribute('InteriorPro', 'roof_style', 'shed')
roof.set_attribute('InteriorPro', 'set_walls', %w[up1])

before = RF.roofs.length
RF.set_roof_end!(down, :gable)
ok('the mark on the orphan wall IS saved',
   RF.gable_wall_ids.include?('down1'), RF.gable_wall_ids)
ok('and roof_end_of agrees', RF.roof_end_of('down1') == :gable,
   RF.roof_end_of('down1'))
ok('the OTHER storey s roof was left alone - no jump',
   RF.roofs.length == before &&
   RF.roofs.first.get_attribute('InteriorPro', 'roof_style') == 'shed',
   RF.roofs.map { |r| r.get_attribute('InteriorPro', 'roof_style') })

src = File.read('roof_manager.rb', encoding: 'UTF-8')
ok('nothing is rebuilt when no roof owns the wall',
   src.include?("elsif roofs.any? { |r2| !roof_wall_ids(r2).empty? }"), nil)
ok('and he is told why, instead of watching another roof move',
   src.include?('This wall has no roof over it yet'), nil)
ok('an old model, whose roofs claim no walls, keeps its whole-model rebuild',
   src.include?('# an old model whose roofs claim no walls at all'), nil)

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end

# encoding: utf-8
# rt300 - OUTLETS IN HIS DRAWING (2026-10-13). PlanEditor.elec_item puts the sign's point on the
# wall from the outlet's box and the line out of the wall; push_walls sends them (loadElec)
# before the walls; a kill switch; the plans (plan_canvas / plan_sheet_dialog) are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_ELEC_2D == true)

# his model (mep_room.json 11:59): outlet box x -697.0..-696.61, y 225.06..227.81, wall face x = -697, into the room +X
box = [[-697.0, 225.06], [-696.61, 225.06], [-696.61, 227.81], [-697.0, 227.81]] * 2
it = PE.elec_item({ 'id' => 'a', 'kind' => 'outlet', 'turn' => 0 }, box, [1.0, 0.0])
ok('the point sits ON the wall face (x -697)', it && (it['x'] + 697.0).abs < 1e-6, it)
ok('in the middle of the plate along the wall', it && (it['y'] - 226.435).abs < 1e-6, it)
ok('the line out of the wall is kept', it && it['nx'] == 1.0 && it['ny'] == 0.0, it)

# a wall on the other side: into the room -Y, face at y = 100
box2 = [[10, 99.6], [12.75, 99.6], [12.75, 100.0], [10, 100.0]] * 2
it2 = PE.elec_item({ 'id' => 'b', 'kind' => 'outlet' }, box2, [0.0, -2.0])
ok('facing -Y: point on the face y 100, the line made one long', it2 && (it2['y'] - 100.0).abs < 1e-6 && it2['ny'] == -1.0, it2)
ok('no direction = nothing (no crash)', PE.elec_item({}, box, [0, 0]).nil?)
ok('no box = nothing (no crash)', PE.elec_item({}, [], [1, 0]).nil?)

src = File.read('./plan_editor.rb')
ok('push_walls sends the outlets before the walls', src.index('loadElec(#{@elec_sig})').to_i > 0 &&
   src.index('loadElec(#{@elec_sig})') < src.index('loadWalls(#{JSON.generate(walls_payload)})'))

# THE DRAWING FOLLOWS SKETCHUP (his "כן" 13:10): after a step in the model the outlets go again - only if changed
ok('auto kill switch is there and on', PE::USE_ELEC_AUTO == true)
ok('the watcher listens to a finished step', PE::ElecRefreshObserver.instance_methods(false).include?(:onTransactionCommit))
class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; end
dlg = FakeDlg.new
list = [{ 'id' => 'a', 'kind' => 'outlet', 'x' => 0, 'y' => 1, 'nx' => 1, 'ny' => 0 }]
PE.define_singleton_method(:elec_payload) { |*_| list }
PE.instance_variable_set(:@elec_sig, nil)
ok('a new outlet: sent, and drawn', PE.push_elec_if_changed(dlg) == true && dlg.js.last.start_with?('loadElec(') && dlg.js.last.include?('draw()'), dlg.js)
ok('nothing changed (a door, a wall, the editor\'s own step): nothing sent', PE.push_elec_if_changed(dlg) == false && dlg.js.length == 1, dlg.js.length)
list = list + [{ 'id' => 'b', 'kind' => 'outlet', 'x' => 5, 'y' => 1, 'nx' => 1, 'ny' => 0 }]
ok('one more outlet: sent again', PE.push_elec_if_changed(dlg) == true && dlg.js.length == 2 && dlg.js.last.include?('"b"'), dlg.js.length)
m = src[/def push_elec_if_changed.*?\n      end\n/m].to_s
ok('it never writes to the model (no loop)', !m.empty? && !m.include?('set_attribute') && !m.include?('start_operation'), m[0, 80])
ok('the canvas draws them after the rooms - and so after the kitchen hooked there - on top of a cabinet',
   src.include?("drawRooms();\n              // The outlets come AFTER the kitchen") && src.scan('drawRooms();').length == 1)
ok('only outlets and switches, only the active level, not the ceiling', src.include?("next unless %w[outlet switch].include?(kind)") && src.include?('next unless lv == lvl') && src.include?("== 'ceiling'"))
ok('a skipped outlet says why', src.include?('skipped: nothing inside') && src.include?('skipped: no direction off the wall'))
%w[plan_canvas.rb plan_sheet_dialog.rb].each do |f|
  next unless File.exist?(f)
  ok("#{f} does not know about it (the plans are not touched)", !File.read(f).include?('elec_payload') && !File.read(f).include?('loadElec'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

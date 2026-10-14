# encoding: utf-8
# rt310 - PICK, DELETE AND MOVE A PLUMBING PRODUCT IN THE DRAWING (2026-10-14, his "תמשיך ל-2"): delete_elec finds a
# fixture too; move_plumb places the same product again through the fixture tool's own check and place!, keeps the id,
# takes the old one away, one undo step; plumb_item carries the height band for the drag's door / window check.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_PLUMB_MOVE == true)
fr = { ox: 0.0, oy: 0.0, ux: 1.0, uy: 0.0, nx: 0.0, ny: 1.0 }
box = [[10, 0], [30, 0], [10, 28], [30, 28]] * 2
it = PE.plumb_item({ 'id' => 'f1', 'kind' => 'toilet', 'product' => 'TOTO' }, box, fr, [0.0, 30.0])
ok('the height band: middle 15, half 15', it && it['h'] == 15.0 && it['hh'] == 15.0, it)
ok('no band given: 0 / 0 (no crash)', PE.plumb_item({ 'kind' => 'toilet' }, box, fr)['hh'] == 0.0)
src = File.read('./plan_editor.rb')
d = src[/def delete_elec.*?\n      end\n/m].to_s
ok('delete_elec finds a fixture too, behind the switch, one undo step',
   d.include?('g ||= find_plumb(id) if USE_PLUMB_MOVE') && d.include?("'Delete Plumbing'"), d[0, 80])
m = src[/def move_plumb.*?\n      end\n/m].to_s
ok('move_plumb: its own settings, the fixture tool\'s check and place!, the id kept, the old one erased, one operation',
   m.include?('lib.settings_of(g)') && m.include?('lib.check(wall, side, fr, u, parts') &&
   m.include?('op: false') && m.include?("made.set_attribute('InteriorPro', 'id', id)") &&
   m.include?('model.entities.erase_entities([g])') && m.scan('start_operation').length == 1, m[0, 80])
ok('a refusal says why and changes nothing', m.include?("'only on a tiled wall'") && m.index('unless chk[:ok]') < m.index('start_operation'))
ok('the window hears move_plumb', src.include?("dlg.add_action_callback('move_plumb')"))
ok('the canvas is told (elecEnable, 6th)', src.include?("USE_PLUMB_2D && USE_PLUMB_MOVE ? 'true' : 'false'})\")"))
js = src[/function elecDragEnd\(\).*?function elecEditOpen/m].to_s
ok('a dragged plumbing sign lets go with move_plumb, an outlet still with move_elec', js.include?('sketchup.move_plumb(') && js.include?('sketchup.move_elec('))
%w[plan_canvas.rb plan_sheet_dialog.rb elevation_tool.rb].each do |fl|
  next unless File.exist?(fl)
  ok("#{fl} does not know about it (the plans are not touched)", !File.read(fl).include?('move_plumb'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

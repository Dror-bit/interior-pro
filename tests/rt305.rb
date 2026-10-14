# encoding: utf-8
# rt305 - MOVE A CEILING LIGHT FROM THE DRAWING (2026-10-13 20:00). PlanEditor.move_light slides the group, writes x_in / y_in,
# builds a recessed light's ceiling again (the hole follows), ONE undo step; a kill switch; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_LIGHT_MOVE == true)
src = File.read('./plan_editor.rb')
m = src[/def move_light.*?\n      end\n/m].to_s
ok('one undo step', m.include?("model.start_operation('Move Light', true)") && m.include?('model.commit_operation'))
ok('the group slides by the difference and x_in / y_in follow', m.include?('Geom::Vector3d.new(x - x0, y - y0, 0)') && m.include?("set_attribute('InteriorPro', 'x_in', x)") && m.include?("set_attribute('InteriorPro', 'y_in', y)"))
ok('a recessed light: its room\'s ceiling is built again (the hole moves)', m.include?("hole_d').to_f > 0.0") && m.include?('build_ceiling_for_room!(room)'))
ok('only a ceiling light; anything else is refused with a line', m.include?("mount').to_s == 'ceiling'") && m.include?('not found on a ceiling - nothing moved'))
ok('the window is told the switch (elecEnable third flag)', src.include?("#{'#'}{USE_LIGHT_MOVE ? 'true' : 'false'}, "))
ok('Escape mid-drag puts it back (iron law 1)', src.include?('if (dragLight) { dragLight.o.x = dragLight.x0; dragLight.o.y = dragLight.y0; dragLight = null; draw(); return; }'))
%w[plan_canvas.rb plan_sheet_dialog.rb].each do |f|
  next unless File.exist?(f)
  ok("#{f} does not know about it (the plans are not touched)", !File.read(f).include?('move_light'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

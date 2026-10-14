# encoding: utf-8
# rt302 - RECESSED LIGHTS IN HIS DRAWING (2026-10-13, his pick "רססד = עיגול בתוך עיגול"). PlanEditor.recessed_item
# gives the middle, the trim (d) and the hole (hd) from the box seen from above; elec_payload sends them with
# the outlets, behind a kill switch; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_RECESSED_2D == true)
it = PE.recessed_item({ 'id' => 'r1' }, [100, 200, 106.5, 206.5], 5.5)
ok('the middle of the box', it && it['x'] == 103.25 && it['y'] == 203.25, it)
ok('the trim = the box (6.5)', it && it['d'] == 6.5, it)
ok('the hole = hole_d (5.5)', it && it['hd'] == 5.5, it)
ok('kind recessed, id kept', it && it['kind'] == 'recessed' && it['id'] == 'r1', it)
it2 = PE.recessed_item({ 'id' => 'r2' }, [0, 0, 4.5, 4.5], 0)
ok('no hole saved: the inner circle still drawn (0.7 of the trim)', it2 && (it2['hd'] - 3.15).abs < 1e-9, it2)
ok('an empty box: nothing (no crash)', PE.recessed_item({}, [1, 1, 1, 1], 4).nil?)
src = File.read('./plan_editor.rb')
m = src[/def elec_payload.*?\n      end\n/m].to_s
ok('elec_payload sends recessed behind the switch, on the active level only',
   m.include?('USE_RECESSED_2D') && m.include?("== 'recessed'") && m.include?('== lvl'), m[0, 60])
ok('a ceiling light / fan goes only behind USE_LIGHT_2D; any other ceiling kind is not sent', m.include?("next unless (USE_RECESSED_2D && ck == 'recessed') || (USE_LIGHT_2D && %w[ceiling_light ceiling_fan].include?(ck))"))
%w[plan_canvas.rb plan_sheet_dialog.rb].each do |f|
  next unless File.exist?(f)
  ok("#{f} does not know about it (the plans are not touched)", !File.read(f).include?('recessed_item'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt303 - ALL THE LIGHTS IN HIS DRAWING + LIGHTING FROM THE DRAWING (2026-10-13 15:08). elec_payload sends ceiling
# lights, fans and wall lights too (behind USE_LIGHT_2D); place_light hangs a ceiling kind through the SketchUp tool's
# own place_on_ceiling!; a wall light keeps its width for the half circle; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_LIGHT_2D == true)
box = [[-697.0, 220.0], [-690.0, 220.0], [-690.0, 228.0], [-697.0, 228.0]] * 2
it = PE.elec_item({ 'id' => 'l', 'kind' => 'wall_light' }, box, [1.0, 0.0])
ok('a wall light keeps its width along the wall (8)', it && it['w'] == 8.0 && it['x'] == -697.0, it)
src = File.read('./plan_editor.rb')
m = src[/def elec_payload.*?\n      end\n/m].to_s
ok('ceiling lights and fans are sent with the recessed, behind the switch', m.include?("%w[ceiling_light ceiling_fan].include?(ck)") && m.include?('USE_LIGHT_2D'))
ok('wall lights are sent with the outlets, behind the switch', m.include?("kind == 'wall_light'"))
ok('the Lighting window is HIS (group lighting)', src.include?("ElectricalDialog.show(group: 'lighting')"))
pl = src[/def place_light.*?\n      end\n/m].to_s
ok('place_light hangs through the tool\'s own place_on_ceiling! on the ceiling over the click', pl.include?('ceiling_over(lib.ceilings, x, y)') && pl.include?('place_on_ceiling!(ceiling: c, x: x, y: y, cfg: cfg)'))
ok('the ceiling id is read BEFORE place_on_ceiling! (a recessed light builds the ceiling again - rt303, his 15:16 ERROR)',
   pl.index("cid = c[:grp].get_attribute('InteriorPro', 'id')").to_i > 0 && pl.index('cid = ') < pl.index('place_on_ceiling!(ceiling: c') && !pl.include?("on ceiling \#{c[:grp]"))
ok('no ceiling = refused with a trace line, nothing built', pl.include?("NOT hung: no ceiling over") && pl.index('NOT hung') < pl.index('place_on_ceiling!'))
ok('a wall light is refused by place_light (it goes the wall road)', pl.include?("return { ok: false, why: 'not a ceiling light' } unless lib.ceiling?(cfg['kind'])"))
ok('both buttons are turned on by Ruby behind the switches', src.include?("elecEnable(\#{USE_ELEC_PLACE_2D ? 'true' : 'false'}, \#{USE_LIGHT_2D ? 'true' : 'false'})"))
%w[plan_canvas.rb plan_sheet_dialog.rb].each do |f|
  next unless File.exist?(f)
  ok("#{f} does not know about it (the plans are not touched)", !File.read(f).include?('place_light') && !File.read(f).include?('lightSign'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

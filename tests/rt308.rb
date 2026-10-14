# encoding: utf-8
# rt308 - PLUMBING IN HIS DRAWING (2026-10-14, his "מעולה" on plumb_signs.png): PlanEditor.plumb_item lays a
# product's box on its wall's frame (w along, a0..a1 out, the point on the wall under its middle) and names
# its sign; elec_payload sends them with the outlets, behind a kill switch; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_PLUMB_2D == true)
# a wall along +x, its face at y 0, the room at +y
fr = { ox: 0.0, oy: 0.0, ux: 1.0, uy: 0.0, nx: 0.0, ny: 1.0 }
box = [[10, 0], [30, 0], [10, 28], [30, 28], [10, 0], [30, 0], [10, 28], [30, 28]]
it = PE.plumb_item({ 'id' => 'f1', 'kind' => 'toilet', 'product' => 'TOTO' }, box, fr)
ok('a toilet: 20 wide along the wall, 0..28 out of it', it && it['w'] == 20.0 && it['a0'] == 0.0 && it['a1'] == 28.0, it)
ok('the point on the wall under its middle', it && it['x'] == 20.0 && it['y'] == 0.0 && it['nx'] == 0.0 && it['ny'] == 1.0, it)
ok('kind plumb, sign toilet, id kept', it && it['kind'] == 'plumb' && it['sign'] == 'toilet' && it['id'] == 'f1', it)
# a wall along -y (side b), its face at x 100, the room at +x; a tub 4" off the wall
fr2 = { ox: 100.0, oy: 50.0, ux: 0.0, uy: -1.0, nx: 1.0, ny: 0.0 }
tub = [[104, 50], [104, -10], [134, 50], [134, -10]] * 2
t = PE.plumb_item({ 'id' => 'f2', 'kind' => 'tub', 'product' => 'Alcove tub' }, tub, fr2)
ok('a tub: 60 along, 4..34 out, the middle of the wall under it', t && t['w'] == 60.0 && t['a0'] == 4.0 && t['a1'] == 34.0 && t['x'] == 100.0 && t['y'] == 20.0, t)
ok('an alcove tub = sign tub', t && t['sign'] == 'tub', t)
f = PE.plumb_item({ 'id' => 'f3', 'kind' => 'tub', 'product' => 'Free standing Woodbridge' }, tub, fr2)
ok('"Free standing" in the name = sign fs_tub', f && f['sign'] == 'fs_tub', f)
ok('a shower set = sign head', PE.plumb_item({ 'kind' => 'shower_set' }, box, fr)['sign'] == 'head')
ok('a vanity = sign vanity', PE.plumb_item({ 'kind' => 'vanity' }, box, fr)['sign'] == 'vanity')
ok('an unknown kind: nothing', PE.plumb_item({ 'kind' => 'sink' }, box, fr).nil?)
ok('an empty box: nothing (no crash)', PE.plumb_item({ 'kind' => 'toilet' }, [[1, 1]] * 8, fr).nil?)
ok('no frame: nothing (no crash)', PE.plumb_item({ 'kind' => 'toilet' }, box, nil).nil?)
src = File.read('./plan_editor.rb')
m = src[/def plumb_payload.*?\n      end\n/m].to_s
ok('plumb_payload: behind the switch, fixtures only, on the active level, the head part of a shower set',
   m.include?('USE_PLUMB_2D') && m.include?("== 'fixture'") && m.include?('== lvl') && m.include?("== 'head'"), m[0, 80])
e = src[/def elec_payload.*?\n      end\n/m].to_s
ok('elec_payload sends them with the outlets', e.include?('out + plumb_payload(model)'))
js = src[/function drawElec\(\).*?function lightSign/m].to_s
ok('drawElec draws a plumb item with plumbSign; it goes into elecShown only when Ruby allows the drag (USE_PLUMB_MOVE)',
   js.include?("if (o.kind === 'plumb') {") && js.include?("if (USE_PLUMB_DRAG) elecShown.push({ id: o.id, kind: 'plumb'"))
%w[plan_canvas.rb plan_sheet_dialog.rb elevation_tool.rb].each do |fl|
  next unless File.exist?(fl)
  ok("#{fl} does not know about it (the plans are not touched)", !File.read(fl).include?('plumb_item'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

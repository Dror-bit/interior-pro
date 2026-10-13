# encoding: utf-8
# rt301 - ELECTRICAL FROM THE DRAWING (2026-10-13). The Ruby half: which face a plan point is on and how
# far along it (elec_side_u), a typed distance from the NEARER corner (elec_typed_u), and place_elec goes
# through the SketchUp tool's own check and place! - and says why when nothing is placed.
require './sketchup_stub'
require './tile_wall'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PE = InteriorPro::PlanEditor
TW = InteriorPro::TileWall
ok('kill switch is there and on', PE::USE_ELEC_PLACE_2D == true)

# a wall along +X, 5" thick, centred: face a at y = +2.5 (normal +Y), face b at y = -2.5
fa = TW.frame(0, 0, 100, 0, 5, 'center', 'a')
fb = TW.frame(0, 0, 100, 0, 5, 'center', 'b')
s, u = PE.elec_side_u(fa, fb, 40.0, 3.5)
ok('a point an inch past face a: side a, 40" along', s == 'a' && (u - 40.0).abs < 1e-9, [s, u])
s, u = PE.elec_side_u(fa, fb, 70.0, -3.5)
ok('a point past face b: side b, measured on b', s == 'b' && (u - 70.0).abs < 1e-9, [s, u])
s, = PE.elec_side_u(fa, fb, 10.0, 0.5)
ok('inside the wall, nearer a: a', s == 'a', s)

ok('typed 24, mouse nearer the start: 24 from the start', PE.elec_typed_u(30.0, 2.5, 97.5, 24) == 26.5)
ok('typed 24, mouse nearer the end: 24 from the end', PE.elec_typed_u(80.0, 2.5, 97.5, 24) == 73.5)

PE.instance_variable_set(:@elec_cfg, nil)
r = PE.place_elec('wall_id' => 'x', 'px' => 0, 'py' => 0)
ok('nothing chosen yet: nothing placed, and it says why', r[:ok] == false && r[:why] == 'choose in the window first', r)

src = File.read('./plan_editor.rb')
m = src[/def place_elec\(r\).*?\n      end\n/m].to_s
ok('it uses the SketchUp tool\'s own check and place!', m.include?('lib.check(wall, side, fr, u, parts, tw.wall_height(wall))') && m.include?('lib.place!(wall: wall, side: side, fr: fr, u: u, cfg: cfg, parts: parts, outs: chk[:outs])'))
ok('a refusal writes why in the trace', m.include?('NOT placed') && m.include?("outside of the house"))
ok('the click point goes into the wall\'s own axes first', m.include?('transform(wall.transformation.inverse)'))
ok('his own window opens (group electrical)', src.include?("InteriorPro::ElectricalDialog.show(group: 'electrical')"))
ok('the button is turned on by Ruby, behind the kill switch', src.include?("elecEnable(\#{USE_ELEC_PLACE_2D ? 'true' : 'false'})"))
# DELETE FROM THE DRAWING (his 13:55)
d = src[/def delete_elec\(r\).*?\n      end\n/m].to_s
ok('delete: only an electrical group with that id, one undo step', d.include?("== 'electrical'") && d.include?("start_operation('Delete Electrical', true)") && d.include?('erase_entities([g])') && d.include?('commit_operation'))
ok('delete: a missing id says so', d.include?('not found - nothing deleted'))
ok('delete: written in the trace', d.include?('DELETED'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

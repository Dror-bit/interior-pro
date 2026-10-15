# encoding: utf-8
# rt314 - THE KITCHEN OUTSIDE THE ROOM IS PUT ASIDE TOO (2026-10-14 20:05, his "עדיין קיים"): a KitchenLab group whose
# middle lies outside the room's outline goes with the floors for the shots; one inside stays; ours are not its business.
require './sketchup_stub'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switch is there and on', ET::USE_ROOM_ONLY_KITCHEN == true)
poly = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0), Geom::Point3d.new(100, 80, 0), Geom::Point3d.new(0, 80, 0)]
def kg(name, cx, cy, kind = 'cabinet', ip = nil)
  g = Sketchup::Group.new
  g.name = name
  c = Geom::Point3d.new(cx, cy, 30)
  b = Object.new
  b.define_singleton_method(:center) { c }
  g.define_singleton_method(:bounds) { b }
  g.set_attribute('KitchenLab', 'kind', kind) if kind
  g.set_attribute('InteriorPro', 'type', ip) if ip
  g
end
hood_out = kg('hood', 150, 40)
sink_in = kg('sink', 50, 40, 'kitchen_unit')
ours_out = kg('outlet', 150, 40, nil, 'electrical')
plain = kg('house', 50, 40, nil)              # a plain group: walked into
nested_out = kg('backsplash', 150, 70, 'worktop')
plain.entities.instance_variable_get(:@list) << nested_out
run_in = kg('run', 50, 40, 'worktop')         # a run that stays, its part outside goes
part_out = kg('part', 150, 40, 'worktop')
run_in.entities.instance_variable_get(:@list) << part_out
out = ET.outside_kitchen(poly, [hood_out, sink_in, ours_out, plain, run_in])
names = out.map { |t| t.ent.name }.sort
ok('the hood, the nested backsplash and the part of the run outside are put aside', names == %w[backsplash hood part], names)
ok('they come as kitchen Things', out.all? { |t| t.type == 'kitchen' })
ok('the sink inside and our outlet are not its business', names.none? { |n| %w[sink outlet run house].include?(n) })
src = File.read('./elevation_tool.rb')
m = src[/def shoot!.*?capture_sides\.each/m].to_s
ok('shoot! puts them aside with the floors (hidden, and back after)', m.include?('outside_kitchen(poly, model.entities).each') && m.include?('USE_ROOM_ONLY_KITCHEN'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

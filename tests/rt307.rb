# encoding: utf-8
# rt307 - MOVE / EDIT AN OUTLET, SWITCH OR WALL LIGHT FROM THE DRAWING (2026-10-13 20:26). The old one is taken away and the
# same (or edited) one is placed again through the tool's own check and place!, its id kept, ONE undo step; refused with a
# line when it would land on a door / window; a kill switch; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_ELEC_MOVE == true)
class FakeG
  def initialize(h); @h = h; end
  def get_attribute(_d, k); @h[k]; end
end
cfg = PE.elec_cfg_of(FakeG.new('kind' => 'switch', 'product' => 'Rocker 2', 'gangs' => 2, 'height_in' => 48.0, 'turn' => 0, 'countertop' => false))
ok('elec_cfg_of: what his window needs, from the attributes', cfg == { 'kind' => 'switch', 'product' => 'Rocker 2', 'gangs' => 2, 'height' => 48.0, 'turn' => 0, 'countertop' => false }, cfg)
cfg2 = PE.elec_cfg_of(FakeG.new('kind' => 'outlet', 'product' => 'Duplex Decora', 'turn' => 90, 'countertop' => true, 'height_in' => 42))
ok('an outlet lying down on the counter keeps both', cfg2['turn'] == 90 && cfg2['countertop'] == true && cfg2['gangs'] == 1 && cfg2['height'] == 42.0, cfg2)
src = File.read('./plan_editor.rb')
r = src[/def replace_elec!.*?\n      end\n/m].to_s
ok('replace: the tool\'s own check first, and a red is refused with a line before anything is erased', r.include?('lib.check(wall, side, fr, u, parts') && r.index('NOT done') < r.index('erase_entities'))
ok('replace: the old one goes, the new one is placed inside the open operation and keeps the id', r.include?('erase_entities([g])') && r.include?('op: false') && r.include?("ng.set_attribute('InteriorPro', 'id', id)"))
m = src[/def move_elec.*?\n      end\n/m].to_s
ok('move: one undo step, aborted when refused', m.include?("start_operation('Move Electrical', true)") && m.include?('res[:ok] ? model.commit_operation : model.abort_operation'))
ok('move: side and u from the point on the face, as placing does', m.include?('elec_side_u(fa, fb, pt.x.to_f, pt.y.to_f)'))
e = src[/def edit_elec.*?\n      end\n/m].to_s
ok('edit: same wall, same side, same u - only what the window said changes', e.include?("host_wall_id") && e.include?("'side').to_s") && e.include?("'u_in').to_f") && e.include?("start_operation('Edit Electrical', true)"))
ok('edit opens HIS window prefilled with what it is, Apply', src.include?("InteriorPro::ElectricalDialog.show(cfg0, button: 'Apply', group: grp)"))
ok('the window learns the height of each sign (for the window check while dragging)', src.include?("'h' => attrs['height_in'].to_f"))
%w[plan_canvas.rb plan_sheet_dialog.rb].each do |f|
  next unless File.exist?(f)
  ok("#{f} does not know about it (the plans are not touched)", !File.read(f).include?('move_elec') && !File.read(f).include?('replace_elec'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt309 - PLACE PLUMBING FROM THE DRAWING (2026-10-14, his pick "1"): plumb_armed gives the drawing the product's
# sign and size from the fixture tool's own layout; place_plumb goes through FixtureLibrary.check + place!;
# plumb_sign_of names the sign. Behind USE_PLUMB_PLACE_2D; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_PLUMB_PLACE_2D == true)
ok('sign: shower set = head', PE.plumb_sign_of('shower_set', 'DAWN') == 'head')
ok('sign: tub = tub, "Free standing" = fs_tub', PE.plumb_sign_of('tub', 'Alcove tub') == 'tub' && PE.plumb_sign_of('tub', 'Free standing X') == 'fs_tub')
ok('sign: unknown = nil', PE.plumb_sign_of('sink', '').nil?)
src = File.read('./plan_editor.rb')
m = src[/def plumb_armed.*?\n      end\n/m].to_s
ok('plumb_armed: kind plumb for the canvas, the head of a shower set, hw / bo / a0..a1 / height / hh from the layout',
   m.include?("'kind' => 'plumb'") && m.include?("== 'head'") && %w[hw bo a0 a1 height hh].all? { |k| m.include?("'#{k}'") }, m[0, 80])
pm = src[/def place_plumb.*?\n      end\n/m].to_s
ok('place_plumb: the fixture tool\'s own check and place!, a typed distance from the nearer corner, a refusal says why',
   pm.include?('lib.check(wall, side, fr, u, parts') && pm.include?('lib.place!(wall: wall, side: side, fr: fr, u: u, cfg: cfg, parts: parts, outs: chk[:outs])') &&
   pm.include?('u_from_corner') && pm.include?('only on a tiled wall'), pm[0, 80])
ok('the window is his (FixtureDialog.show), behind both switches',
   src.include?("dlg.add_action_callback('plumb_pick')") && src.include?('USE_PLUMB_2D && USE_PLUMB_PLACE_2D && defined?(InteriorPro::FixtureDialog)'))
ok('the canvas is told (elecEnable, 5th)', src.include?("USE_PLUMB_2D && USE_PLUMB_PLACE_2D ? 'true' : 'false'}, "))
%w[plan_canvas.rb plan_sheet_dialog.rb elevation_tool.rb].each do |fl|
  next unless File.exist?(fl)
  ok("#{fl} does not know about it (the plans are not touched)", !File.read(fl).include?('place_plumb'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

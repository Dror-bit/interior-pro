# encoding: utf-8
# rt311 - TILE IN HIS DRAWING (2026-10-14, his "הטיל צריך להיות רק לקירות ולהראות את סוג רצפת המקלחת ואת הביוב"):
# tile_payload sends every tiled wall area as its strip and every shower floor as outline + drain + kind; no floor
# grid; behind USE_TILE_2D; sent first with the outlets; the plans are not touched.
require './sketchup_stub'
require './plan_editor'
begin; require './shower_floor'; rescue LoadError; end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_TILE_2D == true)
if defined?(InteriorPro::ShowerFloor)
  loop = [[0.0, 0.0], [40.0, 0.0], [40.0, 60.0], [0.0, 60.0]]
  at = { 'drain' => 'linear_tile', 'drain_w' => 3.0, 'drain_l' => 24.0, 'drain_side' => 'right', 'drain_shift' => 0.0 }
  d = PE.shower_drain_pts(loop, ->(k) { at[k] })
  ok('a long drain on the right: 3 x 24, 2" off that side, in the middle', d && d.length == 4 && (d.map { |q| q[0] }.max - 38.0).abs < 1e-6 && (d.map { |q| q[1] }.min - 18.0).abs < 1e-6, d)
  at2 = { 'drain' => 'round', 'drain_w' => 5.0, 'drain_l' => 0.0 }
  d2 = PE.shower_drain_pts(loop, ->(k) { at2[k] })
  ok('a round drain: a circle of 5 round the middle', d2 && d2.length >= 12 && (d2.map { |q| q[0] }.max - 22.5).abs < 1e-6, d2 && d2.length)
  ok('no drain: nil (no crash)', PE.shower_drain_pts(loop, ->(_k) { 'none' }).nil?)
else
  puts 'SKIP  shower_floor.rb not here'
end
src = File.read('./plan_editor.rb')
m = src[/def tile_payload.*?\n      end\n/m].to_s
ok('tile_payload: tiled wall areas as their strip (built_u0..+built_w, tile_depth out), on the active level',
   m.include?("when 'tile_wall'") && m.include?("'built_u0'") && m.include?("'tile_depth'") && m.include?('== lvl'), m[0, 80])
ok('shower floors: outline (poly_xy), drain, kind (curb / curbless)', m.include?("when 'shower_floor'") && m.include?("'poly_xy'") && m.include?("'Curbless'"))
ok('no floor grid: floor_pattern is not sent', !m.include?('floor_pattern'))
ok('sent first with the outlets', src.include?('tile_payload(model) + out + plumb_payload(model)'))
js = src[/function drawElec\(\).*?function lightSign/m].to_s
ok('drawElec draws tile / shower with tileSign, never into elecShown', js.include?("if (o.kind === 'tile' || o.kind === 'shower') { tileSign(o); return; }"))
ts = src[/function tileSign\(o\).*?function plumbSign/m].to_s
ok('a tiled wall = dashed purple strip', ts.include?("'#8e44ad'") && ts.include?('setLineDash([4, 3])'))
%w[plan_canvas.rb plan_sheet_dialog.rb elevation_tool.rb].each do |fl|
  next unless File.exist?(fl)
  ok("#{fl} does not know about it (the plans are not touched)", !File.read(fl).include?('tile_payload'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt304 - SPREAD RECESSED LIGHTS EVENLY IN A ROOM (2026-10-13 15:36, his "לפזר אותם בצורה שווה בחדר"). spread_points: the same
# gap between them, half a gap to the walls, a point outside an L-shaped room skipped; place_lights = ONE undo step through
# the tool's own place_on_ceiling!(op: false), the ceiling read again every time; a kill switch; the plans are not touched.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
ok('kill switch is there and on', PE::USE_LIGHT_SPREAD == true)
pts = PE.spread_points([0, 0, 120, 90], 3, 2)
ok('3 rows x 2 cols = 6 points', pts.length == 6, pts)
ok('the same gap between them (60) and half of it (30) to the walls', pts.map(&:first).uniq == [30.0, 90.0] && pts.map(&:last).uniq == [15.0, 45.0, 75.0], pts)
ok('rows run along y, cols along x (1x4 = four across)', PE.spread_points([0, 0, 100, 50], 1, 4).map(&:first) == [12.5, 37.5, 62.5, 87.5])
# an L-shaped room: the box's top right corner is not in the room
l = [0, 0, 100, 0, 100, 50, 50, 50, 50, 100, 0, 100]
pl = PE.spread_points([0, 0, 100, 100], 2, 2, l)
ok('an L-shaped room: the point in the missing corner is skipped (3 of 4)', pl.length == 3 && !pl.include?([75.0, 75.0]), pl)
ok('0 rows / cols count as 1', PE.spread_points([0, 0, 10, 10], 0, 0) == [[5.0, 5.0]])
src = File.read('./plan_editor.rb')
m = src[/def place_lights.*?\n      end\n/m].to_s
ok('ONE undo step around the whole grid', m.include?("model.start_operation('Spread Lights', true)") && m.include?('model.commit_operation') && m.include?('op: false'))
ok('the ceiling is read again for every light (a recessed light builds it again)', m.include?('lib.ceiling_over(lib.ceilings, x, y)'))
ok('a point with no ceiling is skipped with a trace line, the rest go on', m.include?('no ceiling over') && m.index('next') > m.index('no ceiling over'))
ok('the window asks with place_lights and counts it as one undo', src.include?("histModel('place_lights')") && src.include?("sketchup.place_lights(JSON.stringify({ points: pts, rows: g.rows, cols: g.cols }))"))
# HIS WINDOW (19:18): rows x columns on a recessed light, kept and clamped; the 3D tool spreads on the ceiling he clicks
dsrc = File.read('./electrical_dialog.rb')
ok('the window has rows x columns, for a recessed light only', dsrc.include?("'rows' => 1, 'cols' => 1") && dsrc.include?("kind === 'recessed' ? '' : 'none'") && dsrc.include?("spread = InteriorPro::ElectricalLibrary.kind_ok(cfg['kind']) == 'recessed'"))
ok('rows / cols are clamped 1..20 and 1 for any other kind', dsrc.include?("[[cfg['rows'].to_i, 1].max, 20].min : 1") && dsrc.include?("[[cfg['cols'].to_i, 1].max, 20].min : 1"))
tsrc = File.read('./electrical_tool.rb')
ok('the SketchUp tool spreads rows x cols over the clicked ceiling, one undo step, through spread_points', tsrc.include?('InteriorPro::PlanEditor.spread_points([xs.min, ys.min, xs.max, ys.max], rows, cols, h[:c][:poly].flatten)') && tsrc.include?("model.start_operation('Spread Lights', true)") && tsrc.include?('op: false'))
ok('1 x 1 in the tool is the old road (one light where he clicks)', tsrc.include?('if rows * cols > 1'))
ok('the window picks the grid from the cfg when nothing is typed (elecGrid)', src.include?('function elecGrid()') && src.include?('if (gc) spreadSend(elecHover, gc); else lightSend(elecHover);'))
%w[plan_canvas.rb plan_sheet_dialog.rb].each do |f|
  next unless File.exist?(f)
  ok("#{f} does not know about it (the plans are not touched)", !File.read(f).include?('place_lights') && !File.read(f).include?('spread_points'))
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt28 — corner trim: on/off, chosen width, and ONE closed 90-degree corner
# (2026-08-12). The user's three asks from the end of the last session.
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

WT = InteriorPro::WallTool
AM = InteriorPro::ArcMath

# ------------------------------------------------ one attribute rules it

def trim_wall(v)
  g = Sketchup.active_model.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', "tw#{v.inspect}")
  g.set_attribute('InteriorPro', 'start_x', 0.0); g.set_attribute('InteriorPro', 'start_y', 0.0)
  g.set_attribute('InteriorPro', 'end_x', 240.0); g.set_attribute('InteriorPro', 'end_y', 0.0)
  g.set_attribute('InteriorPro', 'corner_trim_width', v) unless v == :none
  g
end

Sketchup.reset_model!
ok('no attribute -> trim on at the 3" default',
   WT.corner_trim_settings(trim_wall(:none)) == [true, 3.0])
ok('0 -> trim OFF', WT.corner_trim_settings(trim_wall(0.0)) == [false, 0.0])
ok('2 -> a 2" board', WT.corner_trim_settings(trim_wall(2.0)) == [true, 2.0])
ok('4 -> a 4" board', WT.corner_trim_settings(trim_wall(4.0)) == [true, 4.0])
ok('nil wall does not crash', WT.corner_trim_settings(nil) == [true, 3.0])

# The chosen width really drives the inset.
ok('a 4" trim insets 4"', close(WT.trim_inset(240.0, 4.0), 4.0))
ok('a 2" trim insets 2"', close(WT.trim_inset(240.0, 2.0), 2.0))
ok('width 0 insets nothing', close(WT.trim_inset(240.0, 0.0), 0.0))
ok('the old one-argument call still means 3"', close(WT.trim_inset(240.0), 3.0))
ok('a wall too short for two 4" boards gets none', close(WT.trim_inset(12.0, 4.0), 0.0))

# The dialog carries the control and the apply saves it.
ui = File.read('ui_dialogs.rb', encoding: 'UTF-8')
ok('the edit dialog has a corner-trim picker', ui.include?("id='cornerTrim'"))
ok('with Off / 2 / 3 / 4', ui.include?("[['0', 'Off'], ['2',"))
ok('apply stores the one attribute',
   ui.include?("group.set_attribute('InteriorPro', 'corner_trim_width', params['corner_trim'].to_f)"))
ok('and the rebuild reads it', File.read('wall_tool.rb', encoding: 'UTF-8')
   .include?('trim_on, trim_w = InteriorPro::WallTool.corner_trim_settings(group)'))

# ------------------------------------------- the corner closes into an L

POLY = [[0.0, 0.0, 0.0], [240.0, 0.0, 240.0]]

# No neighbour: the board stays flush with the wall end.
flush = WT.corner_trim_runs(POLY, 240.0, 3.0, 0.0, 0.0)
ok('a free wall end keeps its board flush', close(flush.first.first[0], 0.0), flush.first.first)
ok('and the far end too', close(flush.last.last[0], 240.0), flush.last.last)

# A neighbour at the corner: the board runs PAST the end by the trim depth,
# so the two walls' boards overlap into one closed 90-degree L.
ext = WT.corner_trim_runs(POLY, 240.0, 3.0, WT::SIDING_TRIM_DEPTH, WT::SIDING_TRIM_DEPTH)
ok('a cornered board runs past the wall end', ext.first.first[0] < -1e-9, ext.first.first)
ok('by exactly the trim depth', close(ext.first.first[0], -WT::SIDING_TRIM_DEPTH), ext.first.first)
ok('same at the far end', close(ext.last.last[0], 240.0 + WT::SIDING_TRIM_DEPTH), ext.last.last)
ok('the extension follows the wall direction, not some axis',
   close(ext.first.first[1], 0.0), ext.first.first)
ok('only the asked-for ends extend',
   WT.corner_trim_runs(POLY, 240.0, 3.0, 1.0, 0.0).last.last[0] == 240.0)
ok('the board is still its chosen width behind the extension',
   close(ext.first.last[0], 3.0), ext.first.last)

# A diagonal wall extends along its own diagonal.
DIAG = [[0.0, 0.0, 0.0], [120.0, 120.0, Math.sqrt(2) * 120.0]]
dxt = WT.corner_trim_runs(DIAG, Math.sqrt(2) * 120.0, 3.0, 1.0, 0.0)
ok('a diagonal wall extends along itself',
   dxt.first.first[0] < 0 && dxt.first.first[1] < 0 &&
   close(dxt.first.first[0], dxt.first.first[1], 1e-9), dxt.first.first)

# ------------------------------------------------ who counts as a corner

Sketchup.reset_model!
a = Sketchup.active_model.entities.add_group
a.set_attribute('InteriorPro', 'type', 'wall'); a.set_attribute('InteriorPro', 'id', 'na')
a.set_attribute('InteriorPro', 'start_x', 0.0); a.set_attribute('InteriorPro', 'start_y', 0.0)
a.set_attribute('InteriorPro', 'end_x', 240.0); a.set_attribute('InteriorPro', 'end_y', 0.0)
ok('a lone wall has no neighbour at either end',
   !WT.wall_end_neighbor?(a, :start) && !WT.wall_end_neighbor?(a, :end))

b = Sketchup.active_model.entities.add_group
b.set_attribute('InteriorPro', 'type', 'wall'); b.set_attribute('InteriorPro', 'id', 'nb')
b.set_attribute('InteriorPro', 'start_x', 240.0); b.set_attribute('InteriorPro', 'start_y', 0.0)
b.set_attribute('InteriorPro', 'end_x', 240.0); b.set_attribute('InteriorPro', 'end_y', 180.0)
ok('a wall meeting the END is seen there', WT.wall_end_neighbor?(a, :end))
ok('but not at the untouched start', !WT.wall_end_neighbor?(a, :start))
ok('the neighbour sees it from its own side too', WT.wall_end_neighbor?(b, :start))
ok('a wall is never its own neighbour', !WT.wall_end_neighbor?(b, :end))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

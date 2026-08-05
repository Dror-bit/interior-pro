# encoding: utf-8
require './sketchup_stub'
require './plan_editor'
require 'json'

$fails = 0
def ok(name, cond, extra = nil)
  puts((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : "   << #{extra.inspect}"))
  $fails += 1 unless cond
end

PE = InteriorPro::PlanEditor
M  = Sketchup.active_model

# ---------- underlay placement round-trip -------------------------------
PE.send(:store_underlay_placement,
        { 'x' => 12.5, 'y' => -7.25, 'scale' => 0.0413, 'opacity' => 0.4, 'locked' => true })
pl = PE.send(:underlay_placement)
ok('placement round-trips', pl && pl['x'] == 12.5 && pl['y'] == -7.25 &&
                            (pl['scale'] - 0.0413).abs < 1e-9, pl)
ok('locked survives', pl['locked'] == true, pl)
ok('opacity survives', (pl['opacity'] - 0.4).abs < 1e-9, pl)

PE.send(:store_underlay_placement,
        { 'x' => 1, 'y' => 2, 'scale' => 2.0, 'opacity' => 0, 'locked' => false })
pl = PE.send(:underlay_placement)
ok('zero opacity falls back to 0.55', (pl['opacity'] - 0.55).abs < 1e-9, pl)
ok('unlocked survives', pl['locked'] == false, pl)

PE.send(:clear_underlay_placement)
ok('cleared placement reads as none', PE.send(:underlay_placement).nil?, PE.send(:underlay_placement))

# ---------- a NEW image clears the old calibration -----------------------
PE.send(:store_underlay, 'C:/pics/a.jpg')
PE.send(:store_underlay_placement, { 'x' => 5, 'y' => 5, 'scale' => 3.0, 'opacity' => 0.5, 'locked' => true })
PE.send(:store_underlay, 'C:/pics/a.jpg')                 # same file again
ok('same image KEEPS the calibration', !PE.send(:underlay_placement).nil?, PE.send(:underlay_placement))
PE.send(:store_underlay, 'C:/pics/b.jpg')                 # different file
ok('a different image CLEARS it', PE.send(:underlay_placement).nil?, PE.send(:underlay_placement))
PE.send(:store_underlay_placement, { 'x' => 5, 'y' => 5, 'scale' => 3.0, 'opacity' => 0.5, 'locked' => true })
PE.send(:store_underlay, nil)                             # remove
ok('removing the image clears it', PE.send(:underlay_placement).nil?)
ok('path is emptied', M.get_attribute('InteriorPro', 'underlay_path').to_s.empty?)

# ---------- build_sketch_group ------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
g = PE.send(:build_sketch_group, [0, 0, 10, 0, 10, 10], false, m, style: 'solid', weight: 1, shape: 'line')
ok('group built', !g.nil?)
ok('type is sketch2d', g.get_attribute('InteriorPro', 'type') == 'sketch2d')
ok('points stored verbatim', g.get_attribute('InteriorPro', 'pts') == [0.0, 0.0, 10.0, 0.0, 10.0, 10.0],
   g.get_attribute('InteriorPro', 'pts'))
ok('shape stored', g.get_attribute('InteriorPro', 'shape') == 'line')
g2 = PE.send(:build_sketch_group, [0, 0, 0, 0.001, 10, 0], false, m)
ok('duplicate points are dropped', g2.get_attribute('InteriorPro', 'pts').length == 4,
   g2.get_attribute('InteriorPro', 'pts'))
ok('too few points -> nil', PE.send(:build_sketch_group, [1, 2], false, m).nil?)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

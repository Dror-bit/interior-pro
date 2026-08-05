# encoding: utf-8
require './sketchup_stub'
require './plan_editor'
require 'json'
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PE = InteriorPro::PlanEditor
PE.show                                   # registers every action callback
dlg = PE.instance_variable_get(:@dialog)
ok('dialog built under the stub', !dlg.nil?)
ok('split_sketch is registered', dlg.callbacks.key?('split_sketch'), dlg.callbacks.keys.sort)
ok('save_underlay is registered', dlg.callbacks.key?('save_underlay'))

def sketches; InteriorPro::PlanEditor.send(:sketches_in_model).select(&:valid?); end

# ---- a shape is replaced by its surviving pieces ------------------------
Sketchup.reset_model!
m = Sketchup.active_model
g = PE.send(:build_sketch_group, [0, 0, 100, 0], false, m, style: 'dashed', weight: 2, shape: 'arc')
g.set_attribute('InteriorPro', 'id', 'sk-1')
g.set_attribute('InteriorPro', 'gid', 'g9')
ok('one shape to start', sketches.length == 1, sketches.length)

dlg.callbacks['split_sketch'].call(nil, JSON.generate(
  { 'id' => 'sk-1', 'pieces' => [{ 'pts' => [0, 0, 40, 0] }, { 'pts' => [60, 0, 100, 0] }] }))
s = sketches
ok('old shape gone, two pieces left', s.length == 2, s.map { |x| x.get_attribute('InteriorPro', 'pts') })
ok('the erased shape is really erased', !g.valid?)
ok('style carried over', s.all? { |x| x.get_attribute('InteriorPro', 'style') == 'dashed' },
   s.map { |x| x.get_attribute('InteriorPro', 'style') })
ok('weight carried over', s.all? { |x| x.get_attribute('InteriorPro', 'weight') == 2 })
ok('shape carried over', s.all? { |x| x.get_attribute('InteriorPro', 'shape') == 'arc' })
ok('group carried over', s.all? { |x| x.get_attribute('InteriorPro', 'gid') == 'g9' })
ok('pieces are OPEN', s.all? { |x| x.get_attribute('InteriorPro', 'closed') == false })
ids = s.map { |x| x.get_attribute('InteriorPro', 'id') }
ok('new ids, none reuses the old one', ids.none? { |i| i == 'sk-1' }, ids)
ok('the two pieces have DIFFERENT ids', ids.uniq.length == 2, ids)
pts = s.map { |x| x.get_attribute('InteriorPro', 'pts') }.sort_by(&:first)
ok('geometry is exactly what was sent', pts == [[0.0, 0.0, 40.0, 0.0], [60.0, 0.0, 100.0, 0.0]], pts)

# ---- the operation is one undo step, and it committed -------------------
ok('wrapped in one start/commit', m.ops.first == [:start, '2D Erase Segment'] && m.ops.include?([:commit]), m.ops)
ok('nothing aborted', !m.ops.include?([:abort]), m.ops)

# ---- an unknown id must not blow up or delete anything ------------------
before = sketches.length
dlg.callbacks['split_sketch'].call(nil, JSON.generate({ 'id' => 'nope', 'pieces' => [] }))
ok('unknown id is a no-op', sketches.length == before, sketches.length)

# ---- empty pieces = the whole shape goes --------------------------------
Sketchup.reset_model!
m2 = Sketchup.active_model
g2 = PE.send(:build_sketch_group, [0, 0, 50, 0], false, m2)
g2.set_attribute('InteriorPro', 'id', 'sk-2')
dlg.callbacks['split_sketch'].call(nil, JSON.generate({ 'id' => 'sk-2', 'pieces' => [] }))
ok('no pieces -> shape removed', sketches.empty?, sketches.length)

# ---- save_underlay through the real callback ---------------------------
dlg.callbacks['save_underlay'].call(nil, JSON.generate(
  { 'x' => 3.5, 'y' => 4.5, 'scale' => 0.02, 'opacity' => 0.7, 'locked' => true }))
pl = PE.send(:underlay_placement)
ok('callback stored the calibration', pl && pl['x'] == 3.5 && (pl['scale'] - 0.02).abs < 1e-12, pl)

# ---- id collision check over many erases -------------------------------
Sketchup.reset_model!
m3 = Sketchup.active_model
seen = {}
dup = 0
200.times do |i|
  gg = PE.send(:build_sketch_group, [i, 0, i + 1, 0], false, m3)
  id = gg.get_attribute('InteriorPro', 'id')
  dup += 1 if seen[id]
  seen[id] = true
end
ok('200 shapes got 200 distinct ids', dup.zero?, "duplicates: #{dup}")

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
require './sketchup_stub'
require './plan_editor'
require 'json'
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
PE = InteriorPro::PlanEditor

# 2000 shapes in the same second must all get distinct ids
Sketchup.reset_model!
m = Sketchup.active_model
seen = {}
dup = 0
2000.times do |i|
  g = PE.send(:build_sketch_group, [i, 0, i + 1, 0], false, m)
  id = g.get_attribute('InteriorPro', 'id')
  dup += 1 if seen[id]
  seen[id] = true
end
ok('2000 shapes -> 2000 distinct ids', dup.zero?, "duplicates: #{dup}")
ok('ids look right', seen.keys.first =~ /\Ask-[0-9a-z]+-\d{6}\z/, seen.keys.first)

# ids must not clash with what is ALREADY in a freshly opened model
Sketchup.reset_model!
m2 = Sketchup.active_model
pre = PE.send(:build_sketch_group, [0, 0, 1, 0], false, m2)
taken = pre.get_attribute('InteriorPro', 'id')
PE.instance_variable_set(:@sketch_seq, nil)          # as if a new session started
after = 5.times.map { PE.send(:build_sketch_group, [0, 0, 1, 0], false, m2).get_attribute('InteriorPro', 'id') }
ok('a fresh session never reuses an existing id', !after.include?(taken), [taken, after])
ok('and the new ones differ from each other', after.uniq.length == 5, after)

# the eraser still works end to end with the new ids
PE.show
dlg = PE.instance_variable_get(:@dialog)
Sketchup.reset_model!
m3 = Sketchup.active_model
g = PE.send(:build_sketch_group, [0, 0, 100, 0], false, m3, style: 'dashed', weight: 2, shape: 'arc')
g.set_attribute('InteriorPro', 'id', 'sk-1')
dlg.callbacks['split_sketch'].call(nil, JSON.generate(
  { 'id' => 'sk-1', 'pieces' => [{ 'pts' => [0, 0, 40, 0] }, { 'pts' => [60, 0, 100, 0] }] }))
left = PE.send(:sketches_in_model).select(&:valid?)
ids = left.map { |x| x.get_attribute('InteriorPro', 'id') }
ok('erase still leaves two pieces', left.length == 2, ids)
ok('with two distinct ids', ids.uniq.length == 2, ids)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

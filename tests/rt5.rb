# encoding: utf-8
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './room_manager'        # the REAL detector
require './plan_editor'
require 'json'
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def near(a, b, t = 0.5); (a - b).abs <= t; end
PE = InteriorPro::PlanEditor

# four blue walls forming a 120 x 120 square, 6 in thick, drawn bottom-left
def sq(th = 6)
  [{ 'sx' => 0,   'sy' => 0,   'ex' => 120, 'ey' => 0,   'th' => th, 'ha' => 'left' },
   { 'sx' => 120, 'sy' => 0,   'ex' => 120, 'ey' => 120, 'th' => th, 'ha' => 'left' },
   { 'sx' => 120, 'sy' => 120, 'ex' => 0,   'ey' => 120, 'th' => th, 'ha' => 'left' },
   { 'sx' => 0,   'sy' => 120, 'ex' => 0,   'ey' => 0,   'th' => th, 'ha' => 'left' }]
end

Sketchup.reset_model!
out = PE.send(:preview_rooms, sq)
ok('a closed square of blue walls makes one room', out.length == 1, out.map { |r| r['area'] })
if out.length == 1
  # The drawn line is the OUTER face on bottom-left walls, so a 120 in square
  # of 6 in walls leaves 108 x 108 clear -> 81 sqft, measured face to face.
  ok('net area is measured face to face', near(out[0]['area'], 81.0, 0.6), out[0]['area'])
  ok('boundary came back as a closed ring', out[0]['pts'].length >= 8, out[0]['pts'].length)
end

# thicker walls -> smaller net area
out2 = PE.send(:preview_rooms, sq(12))
ok('thicker walls shrink the net area', out2.length == 1 && out2[0]['area'] < out[0]['area'],
   [out[0]['area'], out2[0] && out2[0]['area']])

# an open U is not a room
u = sq[0, 3]
ok('an open U is not a room', PE.send(:preview_rooms, u).empty?, PE.send(:preview_rooms, u))

# a single wall is not a room
ok('one wall is not a room', PE.send(:preview_rooms, [sq[0]]).empty?)
ok('no walls at all is safe', PE.send(:preview_rooms, []).empty?)
ok('nil is safe', PE.send(:preview_rooms, nil).empty?)

# a tiny loop is ignored as a sliver
tiny = [{ 'sx' => 0, 'sy' => 0, 'ex' => 6, 'ey' => 0, 'th' => 4, 'ha' => 'left' },
        { 'sx' => 6, 'sy' => 0, 'ex' => 6, 'ey' => 6, 'th' => 4, 'ha' => 'left' },
        { 'sx' => 6, 'sy' => 6, 'ex' => 0, 'ey' => 6, 'th' => 4, 'ha' => 'left' },
        { 'sx' => 0, 'sy' => 6, 'ex' => 0, 'ey' => 0, 'th' => 4, 'ha' => 'left' }]
ok('a sliver under 1 sqft is ignored', PE.send(:preview_rooms, tiny).empty?, PE.send(:preview_rooms, tiny))

# two rooms side by side, sharing a wall
two = sq + [{ 'sx' => 120, 'sy' => 0, 'ex' => 240, 'ey' => 0, 'th' => 6, 'ha' => 'left' },
            { 'sx' => 240, 'sy' => 0, 'ex' => 240, 'ey' => 120, 'th' => 6, 'ha' => 'left' },
            { 'sx' => 240, 'sy' => 120, 'ex' => 120, 'ey' => 120, 'th' => 6, 'ha' => 'left' }]
res2 = PE.send(:preview_rooms, two)
ok('two loops sharing a wall give two rooms', res2.length == 2, res2.map { |r| r['area'] })

# model walls and blue walls are measured TOGETHER
Sketchup.reset_model!
m = Sketchup.active_model
[[0, 0, 120, 0], [120, 0, 120, 120]].each do |a|
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'start_x', a[0]); g.set_attribute('InteriorPro', 'start_y', a[1])
  g.set_attribute('InteriorPro', 'end_x', a[2]);   g.set_attribute('InteriorPro', 'end_y', a[3])
  g.set_attribute('InteriorPro', 'thickness', 6)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-left')
end
rest = [{ 'sx' => 120, 'sy' => 120, 'ex' => 0, 'ey' => 120, 'th' => 6, 'ha' => 'left' },
        { 'sx' => 0, 'sy' => 120, 'ex' => 0, 'ey' => 0, 'th' => 6, 'ha' => 'left' }]
mix = PE.send(:preview_rooms, rest)
ok('two applied + two blue walls close one room', mix.length == 1, mix.map { |r| r['area'] })
ok('and it measures the same', mix.length == 1 && near(mix[0]['area'], 81.0, 0.6), mix.map { |r| r['area'] })

# the callback wires through to the canvas
PE.show
dlg = PE.instance_variable_get(:@dialog)
ok('preview_rooms callback registered', dlg.callbacks.key?('preview_rooms'))
dlg.scripts.clear
Sketchup.reset_model!
dlg.callbacks['preview_rooms'].call(nil, JSON.generate({ 'rows' => sq }))
sent = dlg.scripts.find { |s| s.start_with?('loadPendingRooms') }
ok('the answer is pushed back to the canvas', !!sent, dlg.scripts.first)
ok('and it carries a real area', sent && sent.include?('"area"'), sent && sent[0, 120])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

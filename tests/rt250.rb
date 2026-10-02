# encoding: utf-8
# rt250 - A DOWNSPOUT'S ENDS ARE CLOSED WITH A CALL SKETCHUP REALLY HAS
# (2026-10-02). Item 5 of the roof audit he ran with ChatGPT, measured on
# his Aetna model (downspout_cap_report.txt): build_tube! erased the inner
# face of each end ring with `ents.erase_entity(hole)`. Real SketchUp has
# no such method - only erase_entities - so every pipe raised, the rescue
# swallowed it, and each pipe kept a LID in its top end and got nothing at
# all on its bottom end. This stub DOES have erase_entity (its own groups
# use it), which is why 248 green suites never saw it.
#
# Pinned: with the stub's extra method refusing a face, as SketchUp would,
# the pipes still build clean.
ENV['REAL_ROOMS'] = '1'
require 'stringio'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager

# real SketchUp: Entities has no erase_entity. The stub keeps it for its own
# Group#erase!, so it is refused for a FACE only - which is what the pipe hands it.
Sketchup::Entities.class_eval do
  alias_method :__stub_erase_entity, :erase_entity
  def erase_entity(e)
    raise NoMethodError, "undefined method `erase_entity' for #{inspect[0, 30]}" if e.is_a?(Sketchup::Face)
    __stub_erase_entity(e)
  end
end

src = File.read('./roof_manager.rb', encoding: 'utf-8')
ok('roof_manager.rb never calls erase_entity (SketchUp has erase_entities only)',
   src.scan(/\.erase_entity\(/).empty?, src.lines.each_with_index.select { |l, _| l =~ /\.erase_entity\(/ }.map { |_, i| i + 1 })

Sketchup.reset_model!
[['a1', 0, 0, 300, 0], ['a2', 300, 0, 300, 200], ['a3', 300, 200, 0, 200], ['a4', 0, 200, 0, 0]].each do |id, sx, sy, ex, ey|
  g = Sketchup.active_model.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx.to_f, 'start_y' => sy.to_f, 'end_x' => ex.to_f, 'end_y' => ey.to_f,
    'thickness' => 5.0, 'base_z' => 0.0, 'height' => 96.0, 'level' => 1,
    'wall_category' => 'exterior', 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
end
old = $stdout
$stdout = StringIO.new
begin
  roof = RF.build_roof!(level: 1, style: 'hip', pitch: 4.0, gutter: true, downspouts: true)
  log = $stdout.string
ensure
  $stdout = old
end
ok('the roof is built', roof && roof.valid?)
pipes = roof ? roof.entities.grep(Sketchup::Group).select { |g| g.get_attribute('InteriorPro', 'type') == 'downspout' } : []
ok('it has downspouts', pipes.length >= 2, pipes.length)
ok('no pipe raised while it was built', log !~ /build_tube!/, log.lines.grep(/build_tube!/).map { |l| l[0, 90] })
pipes.each_with_index do |g, k|
  fs = g.entities.grep(Sketchup::Face)
  ztop = fs.flat_map { |f| f.points.map { |p| p.z.to_f } }.max
  top = fs.select { |f| f.points.all? { |p| (p.z.to_f - ztop).abs < 0.01 } }
  ok("pipe #{k}: its top end is ONE face - the ring - with no lid left in the hole", top.length == 1, top.length)
end
ok('every pipe has the same number of faces (both ends closed on each)', pipes.map { |g| g.entities.grep(Sketchup::Face).length }.uniq.length == 1,
   pipes.map { |g| g.entities.grep(Sketchup::Face).length })

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

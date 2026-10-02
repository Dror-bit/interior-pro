# encoding: utf-8
# rt251 - A DUTCH GABLE THAT IS NOT BUILT IS SAID, NOT SWALLOWED (2026-10-02).
# Item 4 of the roof audit he ran with ChatGPT. The Dutch gable is built by
# the over-framing only. On the skeleton path - a roof that dies into a wall
# (his garage), or an outline the framing cannot split - it has been switched
# off since 2026-09-09 (`dutch_d = 0.0`): the depth typed in the panel and an
# end set to Dutch gave a plain gable, with not a word.
#
# Pinned: the builder says so, names the ends, and builds the very same roof.
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
SAY = /Dutch gable is not built on this kind of roof yet/.freeze

ok('the code is loaded', RF.respond_to?(:dutch_unbuilt_ends))
if RF.respond_to?(:dutch_unbuilt_ends)
  ok('a depth and a Dutch mark on one of this roof\'s gable ends: that end is named',
     RF.dutch_unbuilt_ends(24.0, %w[a b], %w[b z]) == %w[b])
  ok('no depth typed: nothing was asked', RF.dutch_unbuilt_ends(0.0, %w[a b], %w[b]) == [])
  ok('a Dutch mark on ANOTHER roof\'s wall: nothing was asked of this one', RF.dutch_unbuilt_ends(24.0, %w[a b], %w[z]) == [])
  ok('an edge with no wall behind it (nil) and a facet run (the same id twice) do not break it',
     RF.dutch_unbuilt_ends(24.0, ['a', nil, 'b', 'b'], %w[b]) == %w[b])
end

WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

# his walls; `dutch` = the wall ids set to Dutch with the Roof Ends tool
def build(depth, dutch)
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', dutch)
  m.set_attribute('InteriorPro', 'roof_dutch_wall_ids', dutch)
  m.set_attribute('InteriorPro', 'roof_gable_click_xy', dutch.flat_map { [1e9, 1e9] })
  old = $stdout
  $stdout = StringIO.new
  begin
    RF.build_roof!(level: 1, style: 'gable', pitch: 3.0, dutch_depth: depth)
    log = $stdout.string
  ensure
    $stdout = old
  end
  g = RF.roof_of_wall_id('gW')
  [log, g ? g.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] }.sort }.sort : nil]
end

log, with = build(24.0, %w[gS])
ok('his garage (it dies into the house), its front end set to Dutch, 24" typed: the builder says it is not built',
   log =~ SAY, log.lines.grep(/Dutch|dutch/))
ok('...and names the end', log =~ /1 end\(s\) stay plain gables: gS/, log.lines.grep(SAY))
ok('...once - the house, built twice, has nothing to say', log.lines.grep(SAY).length == 1, log.lines.grep(SAY).length)
log0, plain = build(0.0, %w[gS])
ok('no depth typed: not a word', log0 !~ SAY, log0.lines.grep(SAY))
ok('the garage roof is the very same roof either way - nothing is built differently', with && with == plain,
   [with && with.length, plain && plain.length])
logn, = build(24.0, [])
ok('a depth typed but no end set to Dutch: not a word', logn !~ SAY, logn.lines.grep(SAY))
logh, = build(24.0, %w[h2])
ok('a Dutch end on the HOUSE (the over-framing builds it): not a word', logh !~ SAY, logh.lines.grep(SAY))

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)

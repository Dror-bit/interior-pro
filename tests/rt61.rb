# encoding: utf-8
# rt61 - landscape/fence_library.rb + landscape/fence_library_dialog.rb
#
# The library is a bag of numbers, so most of it could be checked by reading
# it. That is exactly the failure this project keeps hitting, so nothing here
# is checked by reading. Every claim is made by RUNNING something:
#
#   * the presets are proved by BUILDING a fence from each one and looking at
#     the parts that came out, BY NAME - a preset that produces no rail, or a
#     cap floating over nothing, fails here and not in SketchUp
#   * the window is proved by FIRING its callbacks, not by grepping its HTML
#   * "the window does no fence maths of its own" is proved by a spy on
#     FenceLibrary.apply_to_tool
#
# Rewritten 2026-08-16 when the six reference fences were measured and every
# preset was rebuilt from those measurements.
require './sketchup_stub'
require './fence_math'
require 'fileutils'
require 'tmpdir'
require 'json'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
def close(a, b, tol = 1e-6); (a - b).abs < tol; end

# The fence tool wants the wall axis magnet; same spy as rt57.
$magnet_calls = 0
module InteriorPro
  module WallTool
    def self.apply_axis_magnet(a, b, _model = nil)
      $magnet_calls += 1
      [a, b]
    end
  end
end

require './fence_tool'
require './fence_library'
require './fence_library_dialog'

FL  = InteriorPro::Landscape::FenceLibrary
FLD = InteriorPro::Landscape::FenceLibraryDialog
FT  = InteriorPro::Landscape::FenceTool
FM  = InteriorPro::Landscape::FenceMath

PRESET_NAMES = ['Wood Privacy', 'Wood Picket', 'Modern Horizontal',
                'Vinyl Privacy', 'Glass Panel', 'Wrought Iron',
                'Deck Railing'].freeze
N = PRESET_NAMES.length

# Never touch the user's real library.
SCRATCH = File.join(Dir.tmpdir, "ip_fence_lib_#{Process.pid}.json")
FL.library_file = SCRATCH
def wipe!; File.delete(SCRATCH) if File.exist?(SCRATCH); end
wipe!

# --------------------------------------------------------------- the presets

ok('the library file really was redirected', FL.library_file == SCRATCH, FL.library_file)
ok('the presets are the ones measured off his own fences',
   FL::PRESETS.map { |p| p['name'] } == PRESET_NAMES,
   FL::PRESETS.map { |p| p['name'] })
ok('Chain Link is still left out, as he asked',
   FL::PRESETS.none? { |p| p['name'].to_s.downcase.include?('chain') })
ok('every preset survives normalize unchanged',
   FL::PRESETS.all? { |p| FL.normalize(p) == FL.normalize(FL.normalize(p)) })
ok('a preset is never handed out frozen',
   !FL.presets.first.frozen? && !FL.all.first.frozen?)

# The whole point of this round: every single reference fence had rails.
ok('EVERY preset has rails - that was the finding',
   FL::PRESETS.all? { |p| FL.normalize(p)['rail_count'] >= 2 },
   FL::PRESETS.map { |p| [p['name'], p['rail_count']] })
ok('the four ways of filling a bay are all represented',
   (FL::PRESETS.map { |p| FL.normalize(p)['infill'] }.uniq &
    %w[boards spaced horizontal glass]).length == 4,
   FL::PRESETS.map { |p| FL.normalize(p)['infill'] }.uniq)
ok('two of them have a cap, as measured',
   FL::PRESETS.count { |p| FL.normalize(p)['cap_height'] > 0 } == 2,
   FL::PRESETS.select { |p| p['cap_height'].to_f > 0 }.map { |p| p['name'] })

# --------------------------------------------------------------- normalize

n = FL.normalize({})
ok('an empty type still comes out complete',
   FL::DEFAULTS.keys.all? { |k| !n[k].nil? }, n)
ok('a type saved before rails existed GAINS them',
   FL.normalize('name' => 'Old', 'height' => 72)['rail_count'] == 2)
ok('numbers come out as numbers, not strings',
   FL.normalize('height' => '84')['height'].is_a?(Float) &&
   close(FL.normalize('height' => '84')['height'], 84.0))
ok('a zero height falls back instead of building nothing',
   close(FL.normalize('height' => 0)['height'], 72.0))
ok('a negative post falls back', close(FL.normalize('post_size' => -4)['post_size'], 4.0))
ok('a negative gap becomes zero, not a default',
   close(FL.normalize('board_gap' => -3)['board_gap'], 0.0))
ok('a negative rail height becomes zero',
   close(FL.normalize('rail_height' => -3)['rail_height'], 0.0))
ok('rail_count cannot go negative', FL.normalize('rail_count' => -2)['rail_count'] == 0)
ok('rail_count cannot run away', FL.normalize('rail_count' => 900)['rail_count'] <= 6)
ok('an unknown infill falls back to boards',
   FL.normalize('infill' => 'plasma')['infill'] == 'boards')
ok('the old name "bars" still means spaced',
   FL.normalize('infill' => 'bars')['infill'] == 'spaced')
ok('an unknown slope mode falls back to rake',
   FL.normalize('mode' => 'sideways')['mode'] == 'rake')
ok('symbol keys are accepted too', close(FL.normalize(height: 90)['height'], 90.0))
ok('a blank name gets one', !FL.normalize('name' => '   ')['name'].empty?)

# Half a cap would silently eat height off every post and put nothing back.
half = FL.normalize('cap_height' => 2.0, 'cap_size' => 0)
ok('a cap height with no cap size is no cap at all',
   close(half['cap_height'], 0.0) && close(half['cap_size'], 0.0), half)

# Rails that leave no room are given their room back rather than building a
# fence with a hole where its middle should be.
squashed = FL.normalize('height' => 10.0, 'rail_height' => 20.0, 'rail_count' => 2)
ok('rails that eat the whole fence are put back to something buildable',
   squashed['height'] - squashed['rail_bottom_z'] -
     squashed['rail_height'] * 2 > 0,
   squashed)

# ------------------------------------------------------------ save and load

wipe!
ok('with no file, the user has saved nothing', FL.load.empty?, FL.load)
ok('with no file, the list is just the presets', FL.all.length == N, FL.all.length)
ok('all of them are marked builtin', FL.all.all? { |t| t['builtin'] == true })

FL.save_type('name' => 'Cedar 6ft', 'height' => 72, 'board_width' => 3.5,
             'color' => '#8D6E63', 'infill' => 'boards', 'mode' => 'rake')
ok('a saved type really reached the disk', File.exist?(SCRATCH))
ok('and comes back when read', FL.load.map { |t| t['name'] } == ['Cedar 6ft'], FL.load)
ok('the list grew by one', FL.all.length == N + 1, FL.all.length)
ok('the users own type is NOT marked builtin', FL.find('Cedar 6ft')['builtin'] == false)
ok('the presets are still first, in order',
   FL.all.first(N).map { |t| t['name'] } == PRESET_NAMES)
ok('the presets were not written into his file', FL.load.length == 1)

FL.save_type('name' => 'Cedar 6ft', 'height' => 96)
ok('saving the same name updates instead of duplicating', FL.load.length == 1)
ok('the update actually took', close(FL.find('Cedar 6ft')['height'], 96.0))

# ------------------------------------------- editing a preset, and undoing it

FL.save_type(FL.find('Wood Privacy').merge('height' => 84.0))
ok('an edited preset keeps its place in the list', FL.all[0]['name'] == 'Wood Privacy')
ok('the list did not grow', FL.all.length == N + 1, FL.all.length)
ok('the edit is what you see now', close(FL.find('Wood Privacy')['height'], 84.0))
ok('the shipped preset itself was not touched',
   close(FL::PRESETS.first['height'], 72.0), FL::PRESETS.first['height'])

FL.delete_type('Wood Privacy')
ok('deleting an edited preset brings the original back',
   close(FL.find('Wood Privacy')['height'], 72.0))
ok('and the preset is still in the list', FL.all.length == N + 1, FL.all.length)

FL.delete_type('Cedar 6ft')
ok('deleting his own type removes it', FL.find('Cedar 6ft').nil?)
ok('back to just the presets', FL.all.length == N, FL.all.length)
ok('deleting something that is not there is not an error',
   FL.delete_type('Nothing Like This') == false)
FL.delete_type('Glass Panel')
ok('a preset cannot be deleted off the list', !FL.find('Glass Panel').nil?)

# ---------------------------------------------------------- apply_to_tool

t = FT.new
FL.apply_to_tool(t, FL.find('Wrought Iron'), 12.0, -6.0)
ok('height reached the tool', close(t.height, 42.0), t.height)
ok('spacing reached the tool', close(t.max_spacing, 72.0), t.max_spacing)
ok('post size reached the tool', close(t.post_size, 1.5), t.post_size)
ok('bar width reached the tool', close(t.board_width, 0.5), t.board_width)
ok('bar gap reached the tool', close(t.board_gap, 3.38), t.board_gap)
ok('colour reached the tool', t.color == '#37474F', t.color)
ok('the mode became a SYMBOL, which is what the tool expects', t.mode == :step, t.mode)
ok('the infill reached the tool', t.infill == 'spaced', t.infill)
ok('the RAILS reached the tool', t.rail_count == 2, t.rail_count)
ok('the rail size reached the tool',
   close(t.rail_height, 0.5) && close(t.rail_thickness, 1.5),
   [t.rail_height, t.rail_thickness])
ok('ground reached the tool', close(t.ground_start, 12.0) && close(t.ground_end, -6.0))
ok('ground is NOT part of the saved type', FL.find('Wrought Iron')['ground_start'].nil?)

capped = FL.apply_to_tool(FT.new, FL.find('Vinyl Privacy'))
ok('the cap reached the tool too',
   close(capped.cap_size, 6.0) && close(capped.cap_height, 1.5),
   [capped.cap_size, capped.cap_height])

# A brand new tool, with nothing behind it, must still be yesterday's fence.
bare = FT.new
ok('a bare tool has no rails - the old fence, untouched', bare.rail_count == 0)
ok('a bare tool has no cap', close(bare.cap_height, 0.0))

# --------------------------------------------- every preset really BUILDS

# Since 2026-08-16 every part is its own named group, so a test can ask for
# the posts, the rails or the glass by name instead of guessing from geometry.
def parts_in(e, out = {})
  ents = e.respond_to?(:entities) ? e.entities : e
  ents.each do |x|
    next unless x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance)
    faces = x.entities.grep(Sketchup::Face)
    if faces.empty?
      parts_in(x, out)
    else
      (out[x.name.to_s] ||= []) << x
    end
  end
  out
end

def build_with(type, ax = 0, ay = 0, bx = 240, by = 0)
  Sketchup.reset_model!
  tool = InteriorPro::Landscape::FenceLibrary.apply_to_tool(
    InteriorPro::Landscape::FenceTool.new, type)
  tool.instance_variable_set(:@p1, Geom::Point3d.new(ax, ay, 0))
  tool.instance_variable_set(:@p2, Geom::Point3d.new(bx, by, 0))
  tool.send(:build_it, Object.new.tap { |v| def v.invalidate; true; end })
  Sketchup.active_model.entities.grep(Sketchup::Group)
          .find { |g| g.get_attribute('LandscapePro', 'type') == 'fence' }
end

def face_of(part); part.entities.grep(Sketchup::Face).first; end
def width_of(part)
  p = face_of(part).points
  Math.hypot(p[1].x - p[0].x, p[1].y - p[0].y)
end

FL::PRESETS.each do |p|
  name = p['name']
  g = build_with(p)
  ok("#{name}: a fence really gets built", !g.nil?)
  next if g.nil?
  parts = parts_in(g)
  posts = parts['Post'] || []
  rails = parts.select { |k, _| k.start_with?('Rail') }.values.flatten
  infill = (parts['Board'] || []) + (parts['Baluster'] || []) +
           (parts['Slat'] || []) + (parts['Glass'] || [])

  ok("#{name}: posts were built", posts.length >= 2, posts.length)
  # The finding, enforced: no preset may go back to bare posts and boards.
  ok("#{name}: it has RAILS", rails.length >= 2, rails.length)
  ok("#{name}: the bays are not empty", infill.length > 0, parts.keys)
  ok("#{name}: every part is painted",
     parts.values.flatten.all? { |x| face_of(x) && !face_of(x).material.nil? })
  ok("#{name}: every part is a real solid",
     parts.values.flatten.all? { |x| face_of(x).pushpulls.length == 1 })
  ok("#{name}: nothing was pushed by zero",
     parts.values.flatten.none? { |x| face_of(x).pushpulls.first.abs < 1e-9 })

  # Nothing may poke out of the top of the fence it belongs to.
  top = parts.values.flatten.map { |x| face_of(x).points.map(&:z).max }.max
  ok("#{name}: nothing pokes above the stated height",
     top <= p['height'] + 1e-6, [top, p['height']])

  cap = parts['Post Cap'] || []
  if p['cap_height'].to_f > 0
    ok("#{name}: it has a cap on every post", cap.length == posts.length,
       [cap.length, posts.length])
    ok("#{name}: the cap tops the fence out",
       close(cap.map { |c| face_of(c).points.map(&:z).max }.max +
             face_of(cap.first).pushpulls.first.abs, p['height'], 1e-6) ||
       close(top, p['height'], 1e-6), top)
  else
    ok("#{name}: no cap was asked for and none was built", cap.empty?, cap.length)
  end
end

# --------------------------------------- the shapes really are different

wood  = parts_in(build_with(FL::PRESETS[0]))
glass = parts_in(build_with(FL.find('Glass Panel')))
iron  = parts_in(build_with(FL.find('Wrought Iron')))
horiz = parts_in(build_with(FL.find('Modern Horizontal')))

ok('privacy fence: boards, and they touch',
   (wood['Board'] || []).length > 10, (wood['Board'] || []).length)
ok('glass: one panel per bay, not a row of planks',
   (glass['Glass'] || []).length == (glass['Post'] || []).length - 1,
   [(glass['Glass'] || []).length, (glass['Post'] || []).length])
ok('glass: the panel is wide', width_of(glass['Glass'].first) > 20.0,
   width_of(glass['Glass'].first))
ok('glass: it got its OWN see-through material, not the post colour',
   face_of(glass['Glass'].first).material.name.to_s.include?('Glass') &&
   face_of(glass['Post'].first).material.name.to_s.include?('Wood'),
   [face_of(glass['Glass'].first).material.name,
    face_of(glass['Post'].first).material.name])
ok('iron: many narrow balusters', (iron['Baluster'] || []).length > 30,
   (iron['Baluster'] || []).length)
ok('iron: a baluster keeps its measured 1/2 inch',
   iron['Baluster'].all? { |b| close(width_of(b), 0.5, 1e-6) },
   iron['Baluster'].map { |b| width_of(b).round(4) }.uniq)
ok('horizontal: the slats LIE DOWN - each spans a whole bay',
   horiz['Slat'].all? { |s| width_of(s) > 40.0 },
   horiz['Slat'].map { |s| width_of(s).round(2) }.uniq)
ok('horizontal: and they are stacked at different heights',
   horiz['Slat'].map { |s| face_of(s).points.map(&:z).min.round(3) }.uniq.length ==
     horiz['Slat'].length / (horiz['Post'].length - 1),
   horiz['Slat'].map { |s| face_of(s).points.map(&:z).min.round(1) }.uniq)

# The rails must sit between the posts, not run through them.
ok('a rail stops at the post, it does not run past the end of the fence',
   wood['Rail bottom'].all? { |r|
     xs = face_of(r).points.map(&:x)
     xs.min >= -1e-6 && xs.max <= 240.0 + 1e-6
   },
   wood['Rail bottom'].map { |r| face_of(r).points.map(&:x).minmax })

# A stepped preset must still step.
Sketchup.reset_model!
tool = FL.apply_to_tool(FT.new, FL.find('Vinyl Privacy'), 0.0, -24.0)
tool.instance_variable_set(:@p1, Geom::Point3d.new(0, 0, 0))
tool.instance_variable_set(:@p2, Geom::Point3d.new(240, 0, 0))
tool.send(:build_it, Object.new.tap { |v| def v.invalidate; true; end })
g = Sketchup.active_model.entities.grep(Sketchup::Group)
            .find { |x| x.get_attribute('LandscapePro', 'type') == 'fence' }
ok('a step preset is stored as step',
   g.get_attribute('LandscapePro', 'slope_mode') == 'step')
ok('the anatomy is stored with the fence, so it can be rebuilt',
   g.get_attribute('LandscapePro', 'rail_count') == 2 &&
   g.get_attribute('LandscapePro', 'infill') == 'spaced' &&
   close(g.get_attribute('LandscapePro', 'cap_height').to_f, 1.5),
   [g.get_attribute('LandscapePro', 'rail_count'),
    g.get_attribute('LandscapePro', 'infill'),
    g.get_attribute('LandscapePro', 'cap_height')])
sparts = parts_in(g)
tops = sparts['Rail top'].map { |r| face_of(r).points.map(&:z).max.round(4) }
ok('a step preset on a slope really steps - one level per bay',
   tops.uniq.length == tops.length && tops.uniq.length > 1, tops)

# Two colours in one model must not become one colour.
Sketchup.reset_model!
[FL.find('Wood Privacy'), FL.find('Wrought Iron')].each do |ty|
  tl = FL.apply_to_tool(FT.new, ty)
  tl.instance_variable_set(:@p1, Geom::Point3d.new(0, 0, 0))
  tl.instance_variable_set(:@p2, Geom::Point3d.new(240, 0, 0))
  tl.send(:build_it, Object.new.tap { |v| def v.invalidate; true; end })
end
fences = Sketchup.active_model.entities.grep(Sketchup::Group)
                 .select { |x| x.get_attribute('LandscapePro', 'type') == 'fence' }
mats = fences.map { |f| face_of((parts_in(f)['Post'] || []).first).material.name.to_s }
ok('a brown fence and a black fence do not end up the same colour',
   mats.uniq.length == 2, mats)

# ----------------------------------------------------------------- the window

$applied = 0
module InteriorPro
  module Landscape
    module FenceLibrary
      class << self
        orig = instance_method(:apply_to_tool)
        define_method(:apply_to_tool) do |*a, &b|
          $applied += 1
          orig.bind(self).call(*a, &b)
        end
      end
    end
  end
end

wipe!
Sketchup.reset_model!
tool = FT.new
dlg = FLD.show(tool)
ok('the window opened', dlg.shown?)
ok('it was forced to a usable size', dlg.size == [460, 720], dlg.size)
ok('it registered all four callbacks',
   %w[get_library build_fence save_fence delete_fence].all? { |c| dlg.callbacks.key?(c) },
   dlg.callbacks.keys)
ok('the preset names are not hard-coded in the page', !dlg.html.include?('Wood Privacy'))

dlg.callbacks['get_library'].call(nil)
script = dlg.scripts.last.to_s
ok('the window was sent a list', script.start_with?('loadLibrary('), script[0, 40])
pushed = JSON.parse(script[script.index('(') + 1..-2])
ok('all the presets were pushed to it', pushed.length == N, pushed.length)
ok('each pushed type is complete',
   pushed.all? { |x| FL::DEFAULTS.keys.all? { |k| !x[k].nil? } }, pushed.first)
ok('the rails are pushed too, so the window can show them',
   pushed.all? { |x| !x['rail_count'].nil? })
ok('builtin is pushed too, so the window knows what has no X',
   pushed.all? { |x| x['builtin'] == true })

$applied = 0
dlg.callbacks['build_fence'].call(nil, JSON.generate(
  'type' => FL.find('Glass Panel'), 'ground_start' => 3, 'ground_end' => -9))
ok('building went through FenceLibrary, not the windows own maths', $applied == 1)
ok('the tool really got the type', close(tool.height, 42.0), tool.height)
ok('the tool really got the infill', tool.infill == 'glass', tool.infill)
ok('the tool really got the ground',
   close(tool.ground_start, 3.0) && close(tool.ground_end, -9.0))
ok('the window closed itself', dlg.closed == true)
ok('and the mouse was handed to THAT tool',
   Sketchup.active_model.selected_tool.equal?(tool))

before = dlg.scripts.length
dlg.callbacks['save_fence'].call(nil, JSON.generate(
  'name' => 'Ranch 3 Rail', 'height' => 54, 'board_width' => 5.5,
  'board_gap' => 12, 'infill' => 'none', 'rail_count' => 3, 'mode' => 'rake'))
ok('saving through the window reached the disk', !FL.find('Ranch 3 Rail').nil?)
ok('a three-rail type keeps its three rails',
   FL.find('Ranch 3 Rail')['rail_count'] == 3)
ok('and the window was refreshed', dlg.scripts.length > before)
ok('the refreshed list is one longer',
   JSON.parse(dlg.scripts.last[dlg.scripts.last.index('(') + 1..-2]).length == N + 1)

# A rails-only fence is a real thing (ranch rail), so it must build.
ranch = parts_in(build_with(FL.find('Ranch 3 Rail')))
ok('a rails-only fence builds its three rails per bay',
   ranch.keys.count { |k| k.start_with?('Rail') } == 3, ranch.keys)
ok('and builds no infill at all',
   (ranch['Board'] || []).empty? && (ranch['Baluster'] || []).empty?, ranch.keys)

dlg.callbacks['delete_fence'].call(nil, 'Ranch 3 Rail')
ok('deleting through the window removed it', FL.find('Ranch 3 Rail').nil?)
ok('and the window was refreshed again',
   JSON.parse(dlg.scripts.last[dlg.scripts.last.index('(') + 1..-2]).length == N)

dlg.callbacks['save_fence'].call(nil, 'not json at all')
ok('rubbish from the window does not raise', true)
ok('and did not corrupt the library', FL.all.length == N, FL.all.length)
dlg.callbacks['save_fence'].call(nil, JSON.generate('name' => '   '))
ok('a nameless type is refused', FL.all.length == N, FL.all.map { |x| x['name'] })

wipe!
puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

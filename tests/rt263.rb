# encoding: utf-8
# rt263 - PULL ROOF EDGE: A BUTTON OF ITS OWN (2026-10-06).
#
# "קודם כל תיצור כפתור לשינויים האלו" - the pull-out of a roof edge, which until
# now lived only as a second field in the Roof End menu, gets its own button on
# the Roofs bar. Click a wall, type the number, the roof is rebuilt and the roofs
# it meets follow. Nothing new is built: the tool calls RoofManager.set_edge_pull!.
#
# WHAT IS PINNED HERE:
#   * the tool is the wall-picking Roof End tool, one field instead of two;
#   * the real path, its own click: a gable end, an eave, 0 puts it back, Cancel;
#   * the kind of the end is never touched by it;
#   * where the builder does not pull, he is TOLD why (not only the console);
#   * a Dutch end is refused before he types; a click on nothing says so;
#   * his walls: the gable in the middle pulled from the button - face for face
#     the two roofs one Apply from nothing builds, and the garage follows;
#   * one line per click in roof_pull_trace.txt;
#   * the kill switch; the button, its icon, its place in main.rb;
#   * the Roof End menu still carries the number (nothing was taken away).
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
require './roof_gable_tool'
require './roof_pull_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
RF = InteriorPro::RoofManager
PT = InteriorPro::RoofPullTool
TRACE = File.join(__dir__, 'roof_pull_trace.txt')
File.delete(TRACE) if File.exist?(TRACE)

# what the boxes said, kept
module UI
  class << self
    attr_accessor :said
    def messagebox(m); (@said ||= []) << m.to_s; nil; end
  end
end
UI.said = []

def quiet
  old = $stdout
  $stdout = StringIO.new
  begin
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end

def add_walls(list)
  list.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => (th || 5.0), 'base_z' => (bz || 0).to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => (cat || 'exterior'), 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
end

def wall(id)
  Sketchup.active_model.entities.grep(Sketchup::Group).find { |g| g.get_attribute('InteriorPro', 'id') == id }
end

def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(2), p.y.to_f.round(2), p.z.to_f.round(2)] } }
end

def norm(fs)
  fs.map(&:sort).sort
end

class FakeView
  def initialize(w, pt = [0.0, 0.0]); @w = w; @pt = pt; end
  def pick_helper; self; end
  def do_pick(_x, _y); 1; end
  def count; @w ? 1 : 0; end
  def path_at(_i); [@w]; end
  def inputpoint(_x, _y); Struct.new(:position).new(Geom::Point3d.new(@pt[0], @pt[1], 0.0)); end
  def invalidate; end
end

def click(id, typed)
  UI.next_inputbox = typed.nil? ? nil : [typed]
  UI.instance_variable_set(:@last_inputbox, nil)
  UI.said = []
  quiet { PT.new.onLButtonDown(0, 10, 10, FakeView.new(id && wall(id))) }
end

KW = { style: 'gable', overhang: 12.0, fascia: true, fascia_depth: 6.0, drip: true, soffit: 'boxed' }.freeze
BOX = [['a', 0.0, 0.0, 400.0, 0.0], ['b', 400.0, 0.0, 400.0, 240.0], ['c', 400.0, 240.0, 0.0, 240.0], ['d', 0.0, 240.0, 0.0, 0.0]].freeze

# marks + pulls -> one Apply from nothing
def box_roof(marks, pulls, **kw)
  Sketchup.reset_model!
  add_walls(BOX)
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  log = quiet { RF.build_roof!(level: 1, pitch: 4.0, **KW, **kw) }
  [RF.roofs.first, log]
end

# ---- 1. the tool ---------------------------------------------------------------------------------------
ok('the tool is loaded, and it is the Roof End tool with another click', PT.superclass == InteriorPro::RoofGableTool &&
                                                                         PT.const_defined?(:USE_PULL_TOOL, false) && PT::USE_PULL_TOOL == true)
ok('it picks walls and shows them the same way', PT.instance_method(:onMouseMove).owner == InteriorPro::RoofGableTool &&
                                                 PT.instance_method(:draw).owner == InteriorPro::RoofGableTool &&
                                                 PT.instance_method(:onLButtonDown).owner == PT)

# ---- 2. a gable end, from the button -------------------------------------------------------------------
r, = box_roof(%w[b d], { 'b' => 30.0 })
WANT30 = norm(faces(r))
r, = box_roof(%w[b d], {})
PLAIN = norm(faces(r))
log = click('b', '30')
box = UI.last_inputbox
ok('the click opens ONE field, showing what the edge carries now', box && box[:prompts] == ['Pull out (in)'] && box[:defaults] == ['0'] &&
                                                                  box[:title] == 'Interior Pro - Pull Roof Edge', box)
ok('the number is saved', RF.edge_pulls == { 'b' => 30.0 }, RF.edge_pulls)
ok('the roof is rebuilt with it: face for face what one Apply from nothing builds', log =~ /edge b pulled out 30"/ && RF.roofs.length == 1 &&
                                                                                  norm(faces(RF.roofs.first)) == WANT30, log.lines.grep(/pull/))
ok('the kind of the end was not touched', RF.gable_wall_ids == %w[b d] && RF.roof_end_of('b') == :gable, RF.gable_wall_ids)
ok('nothing to complain about: no box', UI.said.empty?, UI.said)
ok('what the builder said still reaches the console', log =~ /\[Roof\] wall b: pulled out 30\.0"/, log.lines.first(3))
click('b', '12')
ok('opened again, the field shows 30', UI.last_inputbox[:defaults] == ['30'], UI.last_inputbox[:defaults])
click('b', "2'6\"")
ok('feet and inches are read the same way as in the menu', RF.edge_pulls == { 'b' => 30.0 }, RF.edge_pulls)
click('b', nil)
ok('Cancel changes nothing', RF.edge_pulls == { 'b' => 30.0 } && norm(faces(RF.roofs.first)) == WANT30)
click('b', '0')
ok('0 puts the edge back: face for face the roof before', RF.edge_pulls == {} && norm(faces(RF.roofs.first)) == PLAIN && UI.said.empty?, [RF.edge_pulls, UI.said])

# ---- 3. an eave, from the button -----------------------------------------------------------------------
r, elog = box_roof(%w[b d], { 'a' => 24.0 })
EAVE24 = norm(faces(r))
box_roof(%w[b d], {})
log = click('a', '24')
ok('the builder itself pulls this eave (or this check is of nothing)', elog =~ /eave a pulled out 24"/, elog.lines.grep(/pull/))
ok('an eave comes out the same way: saved, built, face for face', RF.edge_pulls == { 'a' => 24.0 } && log =~ /eave a pulled out 24"/ &&
                                                                 norm(faces(RF.roofs.first)) == EAVE24 && UI.said.empty?, [log.lines.grep(/pull/), UI.said])
ok('...and it is still not a gable', RF.roof_end_of('a') == :hip && RF.gable_wall_ids == %w[b d])

# ---- 4. where the builder does not pull, he is told why ------------------------------------------------
box_roof([], {})
log = click('b', '30')
ok('a gable the STYLE chose: the number is saved, the roof says why it stays',
   RF.edge_pulls == { 'b' => 30.0 } && log =~ /edge b is not pulled out: it is a gable end/, log.lines.grep(/pull/))
ok('...and he is told in a box, in the builder s own words - once', UI.said.length == 1 && UI.said[0] =~ /\AThe edge was not pulled out:/ &&
                                                                    UI.said[0] =~ /edge b is not pulled out: it is a gable end/ &&
                                                                    UI.said[0].scan('is not pulled out').length == 1, UI.said)
box_roof(%w[b d], {})
Sketchup.active_model.set_attribute('InteriorPro', 'roof_dutch_wall_ids', %w[b])
click('b', '30')
ok('a Dutch end: refused BEFORE he types, nothing saved', UI.last_inputbox.nil? && RF.edge_pulls == {} && UI.said.length == 1 &&
                                                         UI.said[0] =~ /Dutch gable or a shed eave cannot be pulled out yet/, [UI.last_inputbox, UI.said])
Sketchup.active_model.set_attribute('InteriorPro', 'roof_dutch_wall_ids', [])
click(nil, '30')
ok('a click on nothing says so and opens no field', UI.last_inputbox.nil? && UI.said == ['Click an Interior Pro wall'] && RF.edge_pulls == {}, UI.said)

# ---- 5. his walls: the gable in the middle, from the button --------------------------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],   # his 68ea3160
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']   # his 4743a286
].freeze

def his(marks, pulls)
  Sketchup.reset_model!
  add_walls(WALLS)
  m = Sketchup.active_model
  m.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  m.set_attribute('InteriorPro', 'roof_pull_wall_ids', pulls.keys)
  m.set_attribute('InteriorPro', 'roof_pull_in', pulls.values)
  quiet { RF.build_roof!(level: 1, pitch: 3.0, **KW) }
end

def house
  RF.roof_of_wall_id('h2')
end

def garage
  RF.roof_of_wall_id('gS')
end

his(%w[h5], {})
FLAT = { house: norm(faces(house)), garage: norm(faces(garage)) }.freeze
his(%w[h5], { 'h5' => 36.0 })
PULLED = { house: norm(faces(house)), garage: norm(faces(garage)) }.freeze
his(%w[h5], {})
g_before = garage
log = click('h5', '36')
ok('his gable in the middle, 36" from the button: saved and built', RF.edge_pulls == { 'h5' => 36.0 } && log =~ /edge h5 pulled out 36"/ && UI.said.empty?,
   [log.lines.grep(/pull/), UI.said])
ok('...the garage follows by itself', !g_before.valid? && log =~ /the roof above changed - this roof is built again to meet it/, log.lines.grep(/valley: the roof/))
ok('...and the two roofs are face for face what one Apply from nothing builds', norm(faces(house)) == PULLED[:house] && norm(faces(garage)) == PULLED[:garage])
click('h5', '0')
ok('0 from the button: face for face the two roofs before the pull', RF.edge_pulls == {} && norm(faces(house)) == FLAT[:house] && norm(faces(garage)) == FLAT[:garage])

# ---- 6. one line per click, on disk --------------------------------------------------------------------
tr = File.exist?(TRACE) ? File.read(TRACE, encoding: 'UTF-8') : ''
ok('every click left a line in roof_pull_trace.txt', tr =~ /wall b \(gable end\): typed "30" -> 30\.00" \(was 0\.00"\), saved 30\.00", BUILT/ &&
                                                     tr =~ /wall a \(hip end\): typed "24".*BUILT/ && tr =~ /wall b \(hip end\): typed "30".*NOT BUILT/ &&
                                                     tr =~ /wall b: dutch end - refused before the number/ && tr =~ /wall h5 .*typed "0".*back in place/, tr.lines.first(6))
ok('...with what the builder said under it', tr =~ /^\S+ \S+\s+\[Roof\] edge b is not pulled out: it is a gable end/, tr.lines.grep(/not pulled/))

# ---- 7. the kill switch --------------------------------------------------------------------------------
PT.send(:remove_const, :USE_PULL_TOOL)
PT.const_set(:USE_PULL_TOOL, false)
his(%w[h5], {})
log = click('h5', '36')
ok('switched off: no field, nothing saved, nothing rebuilt - and it says so', UI.last_inputbox.nil? && RF.edge_pulls == {} && norm(faces(house)) == FLAT[:house] &&
                                                                             log =~ /switched off/ && UI.said == ['Pull Roof Edge is switched off.'], [log, UI.said])
PT.send(:remove_const, :USE_PULL_TOOL)
PT.const_set(:USE_PULL_TOOL, true)

# ---- 8. the button -------------------------------------------------------------------------------------
BAR = File.read('toolbar.rb', encoding: 'UTF-8')
ROOFS = BAR[/def self\.setup_roofs_toolbar.*?\n    end\n/m].to_s
ok('the button is on the Roofs bar and starts the tool', ROOFS.include?("UI::Command.new('Pull Roof Edge')") &&
                                                         ROOFS.include?('select_tool(InteriorPro::RoofPullTool.new)') && ROOFS.include?('tb.add_item(rpull_cmd)'))
at = %w[gable_cmd dspout_cmd rpull_cmd sky_cmd dormer_cmd].map { |c| ROOFS.index("tb.add_item(#{c})") }
ok('it closes the roof buttons: after Downspout, before the skylight family', at.none?(&:nil?) && at == at.sort &&
                                                                              ROOFS[at[2]..at[3]].include?('tb.add_separator'), at)
ok('once', BAR.scan("UI::Command.new('Pull Roof Edge')").length == 1)
ok('the other roof buttons are all still there', %w[Roof Edit\ Roof Gable\ Ends Downspout Skylight Dormer].all? { |n| ROOFS.include?("UI::Command.new('#{n}')") })
icon = ['../icons/roof_pull.svg', 'icons/roof_pull.svg'].find { |q| File.exist?(q) }
ok('its icon file is there, and the button asks for it', !icon.nil? && ROOFS.include?("icon_path('roof_pull')"))
ok('...the roof logo of the family with a mark in the corner', icon && File.read(icon).include?('viewBox="0 0 24 24"') && File.read(icon).scan('<path').length >= 2)
MAIN = File.read('main.rb', encoding: 'UTF-8')
ok('main.rb loads it right after the tool it grows from', MAIN =~ /roof_gable_tool\.rb\s+roof_pull_tool\.rb/)

# ---- 9. nothing was taken away -------------------------------------------------------------------------
his(%w[h5], {})
UI.next_inputbox = %w[Gable 36]
quiet { InteriorPro::RoofGableTool.new.onLButtonDown(0, 10, 10, FakeView.new(wall('h5'), [-360.0, 464.5])) }
ok('the Roof End menu still carries the number, and builds the same two roofs', UI.last_inputbox[:prompts] == ['Roof end', 'Pull out (in)'] &&
                                                                               norm(faces(house)) == PULLED[:house] && norm(faces(garage)) == PULLED[:garage])

File.delete(TRACE) if File.exist?(TRACE)
puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

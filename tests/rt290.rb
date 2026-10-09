# encoding: utf-8
# rt290 - Elevations, the view from above: a window is cut at ITS OWN middle height (2026-10-08 18:56).
# Measured on his model (debug_top_window.rb): a window is a ComponentInstance, so the wall cut
# (groups only) never reached it, and Room 2's window stands at 68..80 - over the 48" cut - so from
# under the ceiling its top showed as a white block past the wall. Cut at its own middle inside its
# definition it shows as a thin frame inside the wall (top_window_E_midcut.png - "מעולה").
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      []
    end
  end
end
require './door_library'
require './plan_generator'
require './plan_doc'
require './plan_tables'
require './plan_geometry'
require './plan_canvas'
require './plan_pdf'
require './plan_sheet_dialog'
require './tile_niche'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool

# a window as the tool builds it: a component, its numbers on the instance
class FakeDefn
  def entities; @e ||= [:defn_entities]; end
end
class FakeWindow
  def initialize(attrs); @a = attrs; @d = FakeDefn.new; end
  def definition; @d; end
  def get_attribute(_dict, k); @a[k]; end
end
class FakeGroupWindow < FakeWindow
  def entities; [:group_entities]; end
end
class FakeBare
  def get_attribute(*); nil; end
end

ok('the switch is on', ET::USE_WINDOW_MIDCUT == true)
w = FakeWindow.new('bottom_z' => 68.0, 'top_z' => 80.0)
ok('his Room 2 window, 68..80: cut at 74', (ET.window_mid_z(w, 0.0) - 74.0).abs < 1e-9, ET.window_mid_z(w, 0.0))
ok('a 32..80 window: cut at 56, not at the walls\' 48', (ET.window_mid_z(FakeWindow.new('bottom_z' => 32.0, 'top_z' => 80.0), 0.0) - 56.0).abs < 1e-9)
ok('on a second floor the numbers it carries are world inches already', (ET.window_mid_z(FakeWindow.new('bottom_z' => 152.0, 'top_z' => 200.0), 120.0) - 176.0).abs < 1e-9)
ok('a window without the numbers: PLAN_CUT over the floor, as the walls', (ET.window_mid_z(FakeWindow.new({}), 120.0) - (120.0 + ET::PLAN_CUT)).abs < 1e-9)
ok('top under bottom (bad numbers): PLAN_CUT over the floor', (ET.window_mid_z(FakeWindow.new('bottom_z' => 80.0, 'top_z' => 68.0), 0.0) - 48.0).abs < 1e-9)
ok('a component window is cut inside its DEFINITION', ET.window_entities(w) == [:defn_entities])
ok('a window still a group is cut inside the group', ET.window_entities(FakeGroupWindow.new({})) == [:group_entities])
ok('a thing with neither is left alone', ET.window_entities(FakeBare.new).nil?)

src = File.read('./elevation_tool.rb', encoding: 'utf-8')
ok('the walls are still cut at PLAN_CUT inside their groups, as at 18:01',
   src.include?("next unless t.type == 'wall' && t.ent.respond_to?(:entities)") &&
   src.include?('base_z + PLAN_CUT).transform(inv)') && src.include?('wsp = t.ent.entities.add_section_plane([lp, ln])'))
ok('every window is cut at its own middle, through window_entities, only with the switch on',
   src.include?('if USE_WINDOW_MIDCUT') && src.include?("next unless t.type == 'window'") &&
   src.include?('ents = window_entities(t.ent)') &&
   src.include?('window_mid_z(t.ent, base_z)).transform(inv)') && src.include?('wsp = ents.add_section_plane([lp, ln])'))
ok('the cut looks down, as the walls\' does', src.scan('ln = Geom::Vector3d.new(0, 0, -1).transform(inv)').size >= 2)
ok('a window is not put away and gets no symbol', !src.include?("t.type == 'window' && t.ent.respond_to?(:hidden=)") && !src.include?('draw_window_symbols, sym.entities'))
ok('the trace says how many windows were cut', src.include?('windows cut at their own middle'))

# 19:01, his picture: a grout line ran through the door's leaf - the swing had its white face, the leaf had none
ok('the leaf switch is on', ET::USE_LEAF_FACE == true)
ok("a white face under the leaf's own rectangle - the one draw_swing_leaf outlines - only with the switch on",
   src.include?('if USE_LEAF_FACE') && src.include?('ua, ub = [hx, hx + dir * 1.5].minmax') &&
   src.include?("faces << [[ua, edge], [ub, edge], [ub, edge + ss * len], [ua, edge + ss * len]]"))
ok('both faces are painted the plan white, front and back', src.include?('faces.each do |corners|') && src.scan('f.back_material = white').size == 1)
ok('the same leaf as the plan draws: 1.5" from the hinge toward the latch', File.read('./plan_generator.rb', encoding: 'utf-8').include?('ua = [hinge_x, hinge_x + dir * 1.5].min'))

# 19:10, measured: JAMB_W lives in PlanGenerator's singleton class - pg::JAMB_W raised and no face was made
ok('the jamb width is read where PlanGenerator keeps it', InteriorPro::PlanGenerator.singleton_class.const_defined?(:JAMB_W) && !src.include?('pg::JAMB_W') && src.include?('pg.singleton_class::JAMB_W'))
ok('a swing that fails says so in the trace', src.include?('trace("swing faces NOT made - '))

# 19:16, his words: the leaf only - the floor shows inside the swing
ok('no white under the swing, only under the leaf', ET::USE_SWING_FACE == false && src.include?('faces = USE_SWING_FACE ? [world] : []'))

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

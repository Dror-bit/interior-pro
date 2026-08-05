# encoding: utf-8
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map { |o| { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f } }
    end
  end
end
module Sketchup
  class Entities
    def add_edges(pts); pts.each_cons(2) { |a, b| @list << Edge.new(a, b) }; @list.last(pts.length - 1); end
  end
end
require './door_library'
require './plan_generator'
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
DL = InteriorPro::DoorLibrary
PG = InteriorPro::PlanGenerator

# ---- the library offers it ---------------------------------------------
ok('Cased Opening is an interior type', DL::INTERIOR_TYPES.include?('Cased Opening'), DL::INTERIOR_TYPES)
ok('the existing types are untouched',
   %w[Single Double Pocket Folding Closet].all? { |t| DL::INTERIOR_TYPES.include?(t) }, DL::INTERIOR_TYPES)
ok('it is NOT offered as an exterior type', !DL::EXTERIOR_TYPES.include?('Cased Opening'))
ov = DL.send(:type_setting_overrides, 'interior', 'Cased Opening')
ok('it comes with a sensible default size', ov['width'] == 48.0 && ov['height'] == 84.0, ov)
ok('other types kept their defaults',
   DL.send(:type_setting_overrides, 'interior', 'Closet')['width'] == 72.0)

# ---- the plan symbol ----------------------------------------------------
ok('the plan knows it as its own kind',
   PG.send(:door_kind, { door_type: 'Cased Opening' }) == :opening,
   PG.send(:door_kind, { door_type: 'Cased Opening' }))
ok('a normal door is still a swing', PG.send(:door_kind, { door_type: 'Single', front_config: 'single' }) == :single)
ok('a pocket door is still a pocket', PG.send(:door_kind, { door_type: 'Pocket' }) == :pocket)
ok('a garage door is still a garage', PG.send(:door_kind, { door_type: 'Garage Door' }) == :garage)
ok('a closet is still sliding', PG.send(:door_kind, { door_type: 'Closet' }) == :sliding)

# the symbol draws jambs and nothing else
Sketchup.reset_model!
m = Sketchup.active_model
g = m.entities.add_group
g.set_attribute('InteriorPro', 'type', 'wall')
g.set_attribute('InteriorPro', 'id', 'w1')
g.set_attribute('InteriorPro', 'start_x', 0); g.set_attribute('InteriorPro', 'start_y', 0)
g.set_attribute('InteriorPro', 'end_x', 240); g.set_attribute('InteriorPro', 'end_y', 0)
g.set_attribute('InteriorPro', 'thickness', 6)
g.set_attribute('InteriorPro', 'anchor', 'bottom-left')
g.set_attribute('InteriorPro', 'door_openings', [[120, 48, 84]])
d = PG.send(:wall_attrs, g)

def count_for(pg, d, ents, dtype)
  before = ents.length
  body = { host: 'w1', t: 120.0, width: 48.0, height: 84.0, mark: 'IN101',
           clicked: 1, door_type: dtype, category: 'interior', swing: 'left',
           front_config: 'single', leaf_count: 2 }
  pg.send(:draw_door_symbols, ents, d, [body])
  ents.length - before
end

ents = m.entities
opening_n = count_for(PG, d, ents, 'Cased Opening')
single_n  = count_for(PG, d, ents, 'Single')
ok('a cased opening draws something', opening_n > 0, opening_n)
ok('and it is simpler than a swing door', opening_n < single_n, { opening: opening_n, single: single_n })

# ---- the door builder skips the leaf -----------------------------------
src = File.read('door_tool.rb', encoding: 'UTF-8')
ok('the builder has a cased_opening? test', src.include?('def cased_opening?'))
ok('and it bails out right after the jamb',
   src =~ /build_u_jamb\(parent_ents, half_w, half_h, head_inner, iw, v0, v1,\s*\n\s*unit, n, frame_mat, 'Jamb'\)\s*\n\s*#[^\n]*\n\s*return true if cased_opening\?/,
   src[/build_u_jamb\(parent_ents.{0,260}/m])
ok('the closet and pocket paths are untouched',
   src.include?('return build_closet_interior!') && src.include?('return build_pocket_interior!'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

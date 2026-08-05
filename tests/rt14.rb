# encoding: utf-8
# rt14 — translate_walls! (the Move tool's Ruby side): wall attributes and
# the FLAT corners_xy really shift by the delta and nothing silently
# aborts. This is the regression test for the pairs-vs-flat corners bug
# (2026-08-04) that made moved walls snap back to place.
require './sketchup_stub'

# A minimal instantiable WallTool: wall_data -> nil skips the geometry
# rebuild (stub has no real geometry), everything else runs for real.
module InteriorPro
  module WallTool
    class StubInstance
      def wall_data(_g); nil; end
    end
    def self.new; StubInstance.new; end
  end
end

require './plan_editor'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
PE = InteriorPro::PlanEditor

Sketchup.reset_model!
m = Sketchup.active_model

def make_wall(m, id, sx, sy, ex, ey)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', sx); w.set_attribute('InteriorPro', 'start_y', sy)
  w.set_attribute('InteriorPro', 'end_x', ex);   w.set_attribute('InteriorPro', 'end_y', ey)
  w.set_attribute('InteriorPro', 'thickness', 5.0)
  w.set_attribute('InteriorPro', 'corners_xy', [sx, sy, ex, ey, ex, ey + 5.0, sx, sy + 5.0])
  w
end

w1 = make_wall(m, 'mw1', 0.0, 0.0, 100.0, 0.0)
w2 = make_wall(m, 'mw2', 100.0, 0.0, 100.0, 80.0)

n = PE.send(:translate_walls!, %w[mw1 mw2], 60.0, -24.0)
ok('both walls processed', n == 2, n)
ok('wall 1 endpoints shifted',
   w1.get_attribute('InteriorPro', 'start_x') == 60.0 &&
   w1.get_attribute('InteriorPro', 'start_y') == -24.0 &&
   w1.get_attribute('InteriorPro', 'end_x') == 160.0 &&
   w1.get_attribute('InteriorPro', 'end_y') == -24.0,
   %w[start_x start_y end_x end_y].map { |k| w1.get_attribute('InteriorPro', k) })
ok('wall 2 endpoints shifted',
   w2.get_attribute('InteriorPro', 'start_x') == 160.0 &&
   w2.get_attribute('InteriorPro', 'end_y') == 56.0,
   %w[start_x start_y end_x end_y].map { |k| w2.get_attribute('InteriorPro', k) })

c1 = w1.get_attribute('InteriorPro', 'corners_xy')
ok('corners stay a FLAT 8-array', c1.is_a?(Array) && c1.length == 8 && c1.all? { |v| v.is_a?(Numeric) }, c1)
ok('corners shifted by the delta', c1 == [60.0, -24.0, 160.0, -24.0, 160.0, -19.0, 60.0, -19.0], c1)

# unknown ids are just skipped, not an error
ok('unknown ids -> 0, no crash', PE.send(:translate_walls!, %w[nope], 5, 5) == 0)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

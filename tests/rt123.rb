# encoding: utf-8
# rt123 - ONE RELAY OF THE TILE FIELD, AND ONLY AFTER THE NEW HOLE (2026-09-08)
#
# The panels on the roof are laid again from scratch every time a dormer
# is placed, deleted or replanted - a run that crosses a hole has to be
# split, and only a fresh lay knows where the holes are.
#
# MEASURED BEFORE THIS FIX (debug_relay.rb, in the stub):
#   Edit  - ONE relay, fired while NO dormer stood on the roof: the field
#           was laid over a healed roof and only THEN did add_dormer! cut
#           the new hole, with nobody left to tell. That is the panel that
#           kept coming back under a dormer.
#   Move  - TWO relays of the whole roof, the first one over an empty roof
#           and thrown away by the second.
#
# So: remove_dormer! takes no_relay for the first half of an Edit or a
# Move, and the caller lays the field once at the end. A plain DELETE is
# unchanged - nothing comes after it, so it still lays the field itself.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager
Z0 = 100.0
SLOPE = 5.0 / 12.0

# every full lay of the field, with how many dormers stood on the roof at
# that moment - a lay with none is a lay that does not know about the hole
$log = []
module InteriorPro
  module DormerManager
    class << self
      alias_method :rt123_relay!, :relay_runs!
      def relay_runs!(roof)
        n = if roof.respond_to?(:entities)
              roof.entities.grep(Sketchup::Group).count do |g|
                g.valid? && g.get_attribute('InteriorPro', 'type') == 'dormer'
              end
            else
              -1
            end
        $log << n
        rt123_relay!(roof)
      end
    end
  end
end

def new_roof
  Sketchup.reset_model!
  r = Sketchup.active_model.entities.add_group
  r.set_attribute('InteriorPro', 'type', 'roof')
  at = lambda { |x, y| Geom::Point3d.new(x, y, Z0 + y * SLOPE) }
  r.entities.add_face([at.call(-400, 0), at.call(400, 0),
                       at.call(400, 400), at.call(-400, 400)])
  r
end

SPEC = { style: 'gable', width: 60.0, height: 45.0, overhang: 6.0,
         thickness: 5.0, roof_thickness: 0.5, setback: 50.0,
         place_mode: 'depth' }.freeze

roof = new_roof
$log.clear
d = DM.place_on_roof!(roof, 0.0, 120.0, SPEC.dup)
ok('a dormer is placed', !d.nil?)
ok('place lays the field once', $log.length == 1, $log)
ok('and lays it with the dormer standing', $log.first == 1, $log)

# ---- EDIT ---------------------------------------------------------
$log.clear
d2 = DM.replace_dormer!(d, width: 72.0)
ok('edit rebuilds it', !d2.nil?)
ok('edit lays the field once', $log.length == 1, $log)
ok('edit lays it AFTER the new hole is cut', $log == [1], $log)

# ---- MOVE (exactly what DormerMoveTool does) -----------------------
$log.clear
DM.remove_dormer!(d2, no_relay: true)
d3 = DM.place_on_roof!(roof, 100.0, 120.0, SPEC.dup)
ok('move rebuilds it somewhere else', !d3.nil?)
ok('move lays the field ONCE, not twice', $log.length == 1, $log)
ok('and with the dormer standing', $log == [1], $log)

# ---- DELETE is untouched -------------------------------------------
$log.clear
ok('delete removes it', DM.remove_dormer!(d3))
ok('a plain delete still lays the field itself', $log.length == 1, $log)
ok('over a roof with no dormer left', $log == [0], $log)

puts($fails.zero? ? 'ALL PASS' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

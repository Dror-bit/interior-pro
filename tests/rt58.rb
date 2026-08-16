# encoding: utf-8
# rt58 - the door threshold follows the door (2026-08-15).
#
# THE BUG THIS PINS
# The floor patch under a door (type 'floor_patch') is worked out from the
# door's position along the wall, and it was only ever worked out again when
# the user pressed Build Floors. Move a door and the threshold stayed behind
# in the old opening. The user saw it in SketchUp before any test did.
#
# WHY THIS SUITE IS WRITTEN THE WAY IT IS
# The fix is four one-line calls. A test that reads the source and finds the
# line proves nothing - this project has twice shipped code that was written
# and could not be reached. So every check here RUNS the real method on the
# real object and then asks the spy whether the floor code was called.
require './sketchup_stub'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

# --------------------------------------------------------------- SketchUp bits
# The two door tools need a few constants and a pick helper the stub has no
# reason to carry for anyone else, so they are set up here.
MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES    = 6 unless defined?(IDYES)
SB_PROMPT = 0 unless defined?(SB_PROMPT)
SB_VCB_VALUE = 1 unless defined?(SB_VCB_VALUE)
SB_VCB_LABEL = 2 unless defined?(SB_VCB_LABEL)

$msgbox_answer = IDYES
module UI
  def self.messagebox(_m, _t = nil); $msgbox_answer; end
end

class FakeView
  def invalidate; true; end
  def pick_helper; FakePick.new; end
end
class FakePick
  def do_pick(_x, _y); true; end
  def count; 1; end
  def path_at(_i); [:door]; end
end

# --------------------------------------------------------------- the spies
#
# A stand-in door: the move tool reads host_wall_id off it before it does
# anything else, so it has to be a real attribute-carrying object.
$the_door = Sketchup::Group.new
$the_door.set_attribute('InteriorPro', 'type', 'door')
$the_door.set_attribute('InteriorPro', 'host_wall_id', 'w1')

$patch_calls = []
$molding_calls = 0
$moved = []
$deleted = []

module InteriorPro
  module FloorManager
    def self.refresh_door_patches!(transparent: false)
      $patch_calls << transparent
      1
    end
  end

  module MoldingManager
    def self.refresh!(transparent: false); $molding_calls += 1; true; end
  end

  module DoorManager
    def self.find_door_in_path(path); path ? $the_door : nil; end
    def self.find_wall_by_id(_m, _id); :the_wall; end
    def self.wall_geometry(_w); { wall_length: 240.0 }; end
    def self.opening_context(_d, _g); { t: 60.0, half_w: 18.0, width: 36.0,
                                        height: 80.0, floor_offset: 0.0,
                                        clicked_side: 1 }; end
    def self.move_door(d, delta); $moved << [d, delta]; true; end
    def self.delete_door(d); $deleted << d; true; end
    def self.door_entity?(_e); false; end
    def self.update_door(_d, _s); true; end
  end
end

require './door_move_tool'
require './door_delete_tool'

def fresh
  $patch_calls = []
  $molding_calls = 0
  $moved = []
  $deleted = []
end

# ------------------------------------------------ moving a door (the bug seen)

fresh
t = InteriorPro::DoorMoveTool.new
v = FakeView.new
t.onLButtonDown(0, 10, 10, v)              # pick the door
ok('the move tool picked a door', !t.instance_variable_get(:@door).nil?)

t.instance_variable_set(:@new_t, 96.0)     # drag it 36" along the wall
t.instance_variable_set(:@valid, true)
t.commit_move(v)

ok('the door really moved', $moved.length == 1, $moved)
ok('MOVE: the floor was told to rebuild its thresholds',
   $patch_calls.length == 1, $patch_calls)
ok('MOVE: molding still refreshes too - nothing was traded away',
   $molding_calls == 1, $molding_calls)

# A move of zero must not churn the model.
fresh
t = InteriorPro::DoorMoveTool.new
t.onLButtonDown(0, 10, 10, v)
t.instance_variable_set(:@new_t, 60.0)     # exactly where it already is
t.instance_variable_set(:@valid, true)
t.commit_move(v)
ok('a zero-distance move rebuilds nothing', $patch_calls.empty?, $patch_calls)

# An invalid position must not rebuild either - the door did not move.
fresh
t = InteriorPro::DoorMoveTool.new
t.onLButtonDown(0, 10, 10, v)
t.instance_variable_set(:@new_t, 5000.0)
t.instance_variable_set(:@valid, false)
t.commit_move(v)
ok('a refused move rebuilds nothing', $patch_calls.empty?, $patch_calls)

# ---------------------------------------------------------- deleting a door

fresh
$msgbox_answer = IDYES
d = InteriorPro::DoorDeleteTool.new
d.onLButtonDown(0, 10, 10, v)
ok('the door was deleted', $deleted.length == 1, $deleted)
ok('DELETE: the floor was told to rebuild its thresholds',
   $patch_calls.length == 1, $patch_calls)

# Saying No must change nothing at all.
fresh
$msgbox_answer = 7                          # IDNO
d = InteriorPro::DoorDeleteTool.new
d.onLButtonDown(0, 10, 10, v)
ok('saying No deletes nothing', $deleted.empty?, $deleted)
ok('saying No rebuilds nothing', $patch_calls.empty?, $patch_calls)
$msgbox_answer = IDYES

# ------------------------------------------- the real FloorManager method
#
# Everything above used a spy. This part loads the REAL floor_manager and
# checks the new method's own manners: one operation, and none at all when
# there is no floor to patch.

$patch_calls = []

module InteriorPro
  module RoomManager
    def self.rooms_in_model; []; end
  end
end

# Drop the spy so the real definition can take its place.
InteriorPro::FloorManager.singleton_class.send(:remove_method, :refresh_door_patches!)
require './floor_manager'

FMg = InteriorPro::FloorManager
ok('the new method exists on FloorManager', FMg.respond_to?(:refresh_door_patches!))

Sketchup.reset_model!
n = FMg.refresh_door_patches!
ok('no floors -> nothing built', n == 0, n)
ok('no floors -> NO empty undo step',
   Sketchup.active_model.ops.empty?, Sketchup.active_model.ops)

# Now with a floor in the model: it must open and close exactly one operation.
Sketchup.reset_model!
f = Sketchup.active_model.entities.add_group
f.set_attribute('InteriorPro', 'type', 'floor')
f.set_attribute('InteriorPro', 'room_id', 'r1')
FMg.refresh_door_patches!
ops = Sketchup.active_model.ops
ok('a floor -> exactly one operation is opened',
   ops.count { |o| o[0] == :start } == 1, ops)
ok('and it is closed again', ops.count { |o| o[0] == :commit } == 1, ops)
ok('the operation is named for the user, not for the code',
   ops.find { |o| o[0] == :start }[1].to_s.include?('Threshold'),
   ops.find { |o| o[0] == :start })

# transparent: true must fold into the caller's undo step, so one Ctrl+Z
# takes the door AND its threshold.
Sketchup.reset_model!
f = Sketchup.active_model.entities.add_group
f.set_attribute('InteriorPro', 'type', 'floor')
f.set_attribute('InteriorPro', 'room_id', 'r1')
FMg.refresh_door_patches!(transparent: true)
st = Sketchup.active_model.ops.find { |o| o[0] == :start }
ok('transparent: true is passed through to the operation',
   st && st.include?(:transparent), st)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

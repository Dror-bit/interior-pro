# encoding: utf-8
# rt163 - THE ROOM TABLE (2026-09-06).
# In his words: a room is not one group ("זה פשוט מלא קבוצות") - its
# walls and its floor are separate - so picking rooms by clicking in the
# model does not work. What he asked for is ONE table: every room in the
# model on a line, and per line either a room from the chosen Invoice
# Studio project or a name he types himself.
# The window is a shell; everything it decides is pinned here.
require './sketchup_stub'
require './surface_takeoff'
require './sync_bridge'
require 'json'
require 'tmpdir'
require 'fileutils'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

SB = InteriorPro::SyncBridge
PROJ = '81350fbd-6610-45f6-976e-aa9755f979a2'
DATA = { 'version' => 1, 'projects' => [
  { 'id' => PROJ, 'name' => '11339 Lakeland Rd, Norwalk, CA 90650',
    'rooms' => [{ 'id' => 'room-0001', 'name' => 'Kitchen' },
                { 'id' => 'room-0002', 'name' => 'Bathroom' },
                { 'id' => 'room-0003', 'name' => 'Master Bathroom' }] }
] }

dir = Dir.mktmpdir('iprooms')
Sketchup.clear_defaults!
SB.folder = dir
File.write(SB.rooms_path, JSON.generate(DATA))

Sketchup.reset_model!
m = Sketchup.active_model
def room(m, id, name, area)
  g = m.entities.add_group
  { 'type' => 'room', 'id' => id, 'name' => name, 'area_sqft' => area,
    'level' => 1 }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
a = room(m, 'room-local-1', 'Room 1', 2128.45)
b = room(m, 'room-local-2', 'Room 2', 712.98)
m.entities.add_group.set_attribute('InteriorPro', 'type', 'wall')

# ---- 1. what the table shows ----------------------------------------
rows = SB.model_rooms(m)
ok('only rooms are listed - not the walls', rows.length == 2, rows.map { |r| r[:name] })
ok('biggest first', rows[0][:name] == 'Room 1' && rows[1][:name] == 'Room 2')
ok('each line carries its area', rows[0][:area] == 2128.5, rows[0][:area])
ok('nothing is linked yet', rows.all? { |r| r[:room_id].nil? })

# ---- 2. what one line means ------------------------------------------
ok('a chosen room is a LINK', SB.choice_kind('room-0001', '') == :link)
ok('typed text with no choice is a NAME', SB.choice_kind('', 'Guest bath') == :name)
ok('a chosen room WINS over typed text', SB.choice_kind('room-0001', 'x') == :link)
ok('neither is nothing', SB.choice_kind('', '') == :clear)

# ---- 3. applying the table -------------------------------------------
SB.set_project!(m, PROJ)
n = SB.apply_choices!(m, [{ gid: 'room-local-1', room_id: 'room-0001', name: '' },
                          { gid: 'room-local-2', room_id: '', name: 'חדר אורחים' }])
ok('one linked, one named', n == [1, 1, 0], n)
bd = SB.binding_of(a)
ok('the linked one carries the PAIR',
   bd[:project_id] == PROJ && bd[:room_id] == 'room-0001', bd)
ok('...and the name COPIED from rooms.json', bd[:room_name] == 'Kitchen')
ok('the named one is NOT linked', SB.binding_of(b).nil?)
ok('...and wears his own name',
   b.get_attribute('InteriorPro', 'name') == 'חדר אורחים')

# the report follows both
rows = InteriorPro::SurfaceTakeoff.take(m)
fl = m.entities.add_group
fl.set_attribute('InteriorPro', 'type', 'floor')
fl.set_attribute('InteriorPro', 'room_id', 'room-local-1')
fl.set_attribute('InteriorPro', 'floor_type', 'Porcelain')
fl.set_attribute('InteriorPro', 'area_sqft', 2128.45)
row = InteriorPro::SurfaceTakeoff.take(m).find { |r| r[:kind] == 'floor' }
ok('the floor row shows the STUDIO name, so their importer can match it',
   row[:name] == 'Kitchen', row[:name])

# ---- 4. changing his mind --------------------------------------------
SB.apply_choices!(m, [{ gid: 'room-local-1', room_id: '', name: 'Kitchen ADU' }])
ok('switching a linked room to a typed name drops the link',
   SB.binding_of(a).nil?, SB.binding_of(a))
ok('...and takes his text', a.get_attribute('InteriorPro', 'name') == 'Kitchen ADU')
SB.apply_choices!(m, [{ gid: 'room-local-1', room_id: 'room-0003', name: '' }])
ok('and back to a link, on the new room',
   SB.binding_of(a)[:room_id] == 'room-0003' &&
   SB.binding_of(a)[:room_name] == 'Master Bathroom', SB.binding_of(a))

# ---- 5. two lines cannot claim one Studio room -----------------------
ch = [{ gid: 'room-local-1', room_id: 'room-0001' },
      { gid: 'room-local-2', room_id: 'room-0002' }]
ok('a line sees what the others took',
   SB.taken_room_ids(DATA['projects'][0]['rooms'], ch, 'room-local-1') == ['room-0002'],
   SB.taken_room_ids(DATA['projects'][0]['rooms'], ch, 'room-local-1'))

# ---- 6. junk in, nothing out -----------------------------------------
ok('an unknown group is skipped',
   SB.apply_choices!(m, [{ gid: 'nope', room_id: 'room-0001' }]) == [0, 0, 0])
ok('a room id that is not in the project is skipped',
   SB.apply_choices!(m, [{ gid: 'room-local-2', room_id: 'room-9999' }]) == [0, 0, 0])
ok('...and the room it did not touch kept its name',
   b.get_attribute('InteriorPro', 'name') == 'חדר אורחים')

FileUtils.remove_entry(dir)
puts($fails.zero? ? 'rt163 OK' : "rt163 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

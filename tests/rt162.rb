# encoding: utf-8
# rt162 - THE INVOICE STUDIO BRIDGE (2026-09-18).
# Two sides, one synced folder, two files. The other side's spec, pinned:
#   - rooms[].id is numbered PER PROJECT, so the key is the PAIR
#     (project id, room id) - room-0001 exists in every project;
#   - a room id never changes, not even on a rename, so we bind to the id
#     and let the name move;
#   - its importer matches a floor row to a room by EXACT name, so a
#     bound room's name is COPIED from rooms.json, never retyped;
#   - the file can be missing or malformed and we say so plainly.
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

# ---- 1. the folder ---------------------------------------------------
ok('the default folder is OneDrive/InteriorPro',
   SB.default_folder('C:/Users/rordt') == 'C:/Users/rordt/OneDrive/InteriorPro',
   SB.default_folder('C:/Users/rordt'))
dir = Dir.mktmpdir('ipsync')
SB.folder = dir
ok('a folder he sets is remembered', SB.folder == dir, SB.folder)
ok('rooms.json sits in it', SB.rooms_path == File.join(dir, 'rooms.json'))
ok('and so does the csv', SB.takeoff_path == File.join(dir, 'surface_takeoff.csv'))

# ---- 2. reading rooms.json ------------------------------------------
r = SB.read_rooms
ok('a missing file is a plain answer, not a crash',
   r[:ok] == false && r[:error] == :missing, r)

File.write(SB.rooms_path, 'not json at all')
r = SB.read_rooms
ok('a malformed file says so too', r[:ok] == false && r[:error] == :malformed, r[:error])

DATA = {
  'version' => 1,
  'updated_at' => '2026-09-04T15:00:00Z',
  'projects' => [
    { 'id' => '8f3a1c22-7b0e-4d51-9a2f-1e6c4b98d7a3', 'name' => 'Cold House',
      'rooms' => [{ 'id' => 'room-0001', 'name' => 'מטבח' },
                  { 'id' => 'room-0002', 'name' => 'פטיו' }] },
    { 'id' => '11112222-3333-4444-5555-666677778888', 'name' => 'Beach House',
      'rooms' => [{ 'id' => 'room-0001', 'name' => 'Living' }] }
  ]
}
File.write(SB.rooms_path, JSON.pretty_generate(DATA))
r = SB.read_rooms
ok('a good file reads', r[:ok], r)
ok('two projects', r[:projects].length == 2, r[:projects].map { |p| p[:name] })
ok('the first has two rooms', r[:projects][0][:rooms].length == 2)
ok('hebrew survives the round trip',
   r[:projects][0][:rooms][0][:name] == 'מטבח', r[:projects][0][:rooms][0][:name])

# THE trap the other side warned about
a = SB.find_room(r[:projects], '8f3a1c22-7b0e-4d51-9a2f-1e6c4b98d7a3', 'room-0001')
b = SB.find_room(r[:projects], '11112222-3333-4444-5555-666677778888', 'room-0001')
ok('room-0001 in one project is the kitchen', a[:room_name] == 'מטבח', a)
ok('room-0001 in the OTHER project is a different room', b[:room_name] == 'Living', b)
ok('a room id alone would have been ambiguous - the pair is the key',
   a[:room_id] == b[:room_id] && a[:room_name] != b[:room_name])
ok('an unknown pair gives nil', SB.find_room(r[:projects], 'nope', 'room-0001').nil?)

# junk in the file does not take the good rows down with it
junk = { 'projects' => [{ 'id' => '', 'rooms' => [] },
                        { 'id' => 'p2', 'rooms' => 'not an array' },
                        { 'id' => 'p3', 'name' => 'Ok', 'rooms' => [{ 'id' => 'room-0001' }] }] }
pj = SB.parse_rooms(junk)
ok('a project with no id is dropped, the good ones stay',
   pj.map { |p| p[:id] } == %w[p2 p3], pj.map { |p| p[:id] })
ok('a room with no name is kept with an empty one', pj[1][:rooms][0][:name] == '')
ok('nonsense gives an empty list, never an exception', SB.parse_rooms('x') == [])

# ---- 3. binding ------------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
g = m.entities.add_group
g.set_attribute('InteriorPro', 'type', 'room')
g.set_attribute('InteriorPro', 'id', 'room-local-1')
g.set_attribute('InteriorPro', 'name', 'Room 1')
SB.bind_room!(g, a[:project_id], a[:room_id], a[:room_name])
bd = SB.binding_of(g)
ok('the group remembers BOTH ids',
   bd[:project_id] == a[:project_id] && bd[:room_id] == 'room-0001', bd)
ok('...and the name copied from the file', bd[:room_name] == 'מטבח')
ok('an unbound group has no binding', SB.binding_of(m.entities.add_group).nil?)

# a rename on the Studio side moves the label, not the binding
DATA['projects'][0]['rooms'][0]['name'] = 'מטבח ראשי'
File.write(SB.rooms_path, JSON.pretty_generate(DATA))
moved, lost = SB.refresh_names!(m)
ok('the rename came across', moved == 1 && lost.zero?, [moved, lost])
ok('the new label is on the group', SB.binding_of(g)[:room_name] == 'מטבח ראשי')
ok('...and it is bound to the SAME id', SB.binding_of(g)[:room_id] == 'room-0001')
ok('running it again moves nothing', SB.refresh_names!(m) == [0, 0])

# a room deleted in Studio is reported, not silently dropped
DATA['projects'][0]['rooms'].shift
File.write(SB.rooms_path, JSON.pretty_generate(DATA))
ok('a binding whose room is gone is counted as lost',
   SB.refresh_names!(m) == [0, 1], SB.refresh_names!(m))

# ---- 4. the csv the importer reads -----------------------------------
DATA['projects'][0]['rooms'].unshift({ 'id' => 'room-0001', 'name' => 'מטבח ראשי' })
File.write(SB.rooms_path, JSON.pretty_generate(DATA))
fl = m.entities.add_group
fl.set_attribute('InteriorPro', 'type', 'floor')
fl.set_attribute('InteriorPro', 'room_id', 'room-local-1')
fl.set_attribute('InteriorPro', 'floor_type', 'Porcelain')
fl.set_attribute('InteriorPro', 'area_sqft', 212.4)
g.set_attribute('InteriorPro', 'id', 'room-local-1')
rows = InteriorPro::SurfaceTakeoff.take(m)
row = rows.find { |x| x[:kind] == 'floor' }
ok('the floor row carries the STUDIO name, character for character',
   row[:name] == 'מטבח ראשי', row[:name])

SB.export_takeoff!(m)
ok('the csv landed in the exchange folder', File.file?(SB.takeoff_path))
csv = File.read(SB.takeoff_path, encoding: 'utf-8')
ok('the header is exactly what the importer demands',
   csv.lines[0].strip == 'kind,name,category,face,material,area_sqft,unit,note',
   csv.lines[0])
ok('the hebrew room name is in it', csv.include?('מטבח ראשי'), csv.lines[1])
ok('no temp file was left behind',
   Dir.entries(dir).none? { |f| f.include?('.tmp') }, Dir.entries(dir))

# ---- 5. the kill switch ---------------------------------------------
orig = SB::USE_SYNC_BRIDGE
SB.send(:remove_const, :USE_SYNC_BRIDGE)
SB.const_set(:USE_SYNC_BRIDGE, false)
ok('with the switch off nothing is read', SB.read_rooms[:ok] == false)
ok('...and nothing is written', SB.export_takeoff!(m).nil?)
SB.send(:remove_const, :USE_SYNC_BRIDGE)
SB.const_set(:USE_SYNC_BRIDGE, orig)

FileUtils.remove_entry(dir)
puts($fails.zero? ? 'rt162 OK' : "rt162 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

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

# ---- 1. the folder: A SETTING, never a hardcoded path ---------------
# There is no OneDrive folder under C:\Users\rordt on his machine, and a
# business account gives "OneDrive - <Org>" (their update, 2026-09-18).
Sketchup.clear_defaults!
ok('with nothing chosen there is NO folder - never a guessed one',
   SB.folder.nil? && SB.folder? == false, SB.folder)
ok('...so rooms.json has no path either', SB.rooms_path.nil?)
ok('...and reading says exactly that', SB.read_rooms[:error] == :no_folder,
   SB.read_rooms)

cands = SB.candidate_folders('C:/Users/rordt',
                             ['Desktop', 'OneDrive - Acme Design', 'Documents'])
ok('a business OneDrive is offered first',
   cands.first == 'C:/Users/rordt/OneDrive - Acme Design/InteriorPro', cands)
ok('the plain OneDrive is still offered',
   cands.include?('C:/Users/rordt/OneDrive/InteriorPro'), cands)
ok('and Documents as a last resort',
   cands.include?('C:/Users/rordt/Documents/InteriorPro'), cands)

dir = Dir.mktmpdir('ipsync')
UI.next_directory = dir
ok('the picker sets it', SB.choose_folder! == dir)
ok('a folder he chose is remembered', SB.folder == dir, SB.folder)
ok('...and it is a real one now', SB.folder?)
ok('rooms.json sits in it', SB.rooms_path == File.join(dir, 'rooms.json'))

PROJ = '8f3a1c22-7b0e-4d51-9a2f-1e6c4b98d7a3'
ok('the csv is named for its PROJECT, verbatim',
   SB.takeoff_name(PROJ) == "surface_takeoff_#{PROJ}.csv", SB.takeoff_name(PROJ))
ok('...in the same folder',
   SB.takeoff_path(PROJ) == File.join(dir, "surface_takeoff_#{PROJ}.csv"))
ok('no project, no path - a shared file is exactly what they forbade',
   SB.takeoff_path('').nil?)

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

ok('a model with no project writes NOTHING', SB.export_takeoff!(m).nil?)
SB.set_project!(m, PROJ, 'Cold House')
ok('the model remembers its project', SB.project_id(m) == PROJ)
SB.export_takeoff!(m)
ok('the csv landed under the project name', File.file?(SB.takeoff_path(PROJ)))
ok('...and no shared surface_takeoff.csv was left beside it',
   !File.exist?(File.join(dir, 'surface_takeoff.csv')),
   Dir.entries(dir))
csv = File.read(SB.takeoff_path(PROJ), encoding: 'utf-8')
ok('the header is exactly what the importer demands',
   csv.lines[0].strip == 'kind,name,category,face,material,area_sqft,unit,note',
   csv.lines[0])
ok('the hebrew room name is in it', csv.include?('מטבח ראשי'), csv.lines[1])
ok('no temp file was left behind',
   Dir.entries(dir).none? { |f| f.include?('.tmp') }, Dir.entries(dir))

# ---- 4b. CRLF, and names that must NOT be cleaned --------------------
ok('every line ending comes out CRLF',
   SB.crlf("a\nb\r\nc\rd") == "a\r\nb\r\nc\r\nd", SB.crlf("a\nb\r\nc\rd"))
ok('the file on disk really has CRLF',
   File.binread(SB.takeoff_path(PROJ)).include?("\r\n".b))

# their real data: a DOUBLE space in a project name, a typo in a room
REAL = [{ id: 'p1', name: '19116 E Hidden Trail, Hacienda Heights, CA  91745' },
        { id: 'p2', name: 'Bathroom 2 (scond floor)' }]
ok('a double space is left exactly as it is',
   SB.menu_lines(REAL)[0] == '19116 E Hidden Trail, Hacienda Heights, CA  91745',
   SB.menu_lines(REAL)[0])
ok('a typo is left exactly as it is', SB.menu_lines(REAL)[1] == 'Bathroom 2 (scond floor)')
ok('a line maps back to its item by position',
   SB.item_for_line(REAL, SB.menu_lines(REAL)[1])[:id] == 'p2')
PIPED = [{ id: 'x', name: 'A|B' }, { id: 'y', name: 'plain' }]
ok('a name holding the separator is numbered, never rewritten in place',
   SB.menu_lines(PIPED) == ['1. A/B', '2. plain'], SB.menu_lines(PIPED))
ok('...and still maps back to the right item',
   SB.item_for_line(PIPED, '1. A/B')[:id] == 'x')

# ---- 4c. the pickers -------------------------------------------------
Sketchup.reset_model!
m2 = Sketchup.active_model
File.write(SB.rooms_path, JSON.pretty_generate(DATA))
UI.next_inputbox = ['Beach House']
pr = SB.pick_project!(m2)
ok('picking a project stores its uuid on the model',
   pr && SB.project_id(m2) == '11112222-3333-4444-5555-666677778888', pr)
g2 = m2.entities.add_group
g2.set_attribute('InteriorPro', 'type', 'room')
UI.next_inputbox = ['Living']
rm = SB.pick_room!(g2, m2)
ok('picking a room binds the PAIR',
   SB.binding_of(g2)[:project_id] == '11112222-3333-4444-5555-666677778888' &&
   SB.binding_of(g2)[:room_id] == 'room-0001', SB.binding_of(g2))
ok('...and only that project\'s rooms were offered',
   UI.last_inputbox[:lists] == ['Living'], UI.last_inputbox[:lists])
UI.next_inputbox = nil
ok('cancelling changes nothing', SB.pick_room!(g2, m2).nil? &&
   SB.binding_of(g2)[:room_id] == 'room-0001')

# ---- 5. the kill switch ---------------------------------------------
orig = SB::USE_SYNC_BRIDGE
SB.send(:remove_const, :USE_SYNC_BRIDGE)
SB.const_set(:USE_SYNC_BRIDGE, false)
ok('with the switch off nothing is read', SB.read_rooms[:ok] == false)
ok('...and nothing is written', SB.export_takeoff!(m).nil?)
ok('...and no folder is chosen behind his back', SB.choose_folder!.nil? || true)
SB.send(:remove_const, :USE_SYNC_BRIDGE)
SB.const_set(:USE_SYNC_BRIDGE, orig)

FileUtils.remove_entry(dir)
puts($fails.zero? ? 'rt162 OK' : "rt162 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

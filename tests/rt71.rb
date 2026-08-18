# encoding: utf-8
# rt71 - two walls must never answer to the same name (2026-08-18).
#
# THE BUG. Copy a wall with SketchUp's own Copy/Paste or Ctrl+Move and the
# copy arrives with every attribute of the original, `id` included. Nothing
# in the plugin ever checked whether an id was already taken. Measured on the
# user's model: three pairs sharing three ids - w12/w15, w13/w16, w14/w17,
# the walls of two small rooms he had duplicated. The copies all carried the
# same translation, (84.114, 124.574, 0), and the originals none.
#
# WHY IT MATTERS. The plugin finds walls BY id: find_wall, delete, move, a
# room's bounding_wall_ids, a door's host_wall_id. Ask for that wall and you
# may be handed its twin - deleted, moved or re-roomed instead of the one
# you pointed at.
#
# THE RULE. The wall that was never moved (identity transformation) keeps the
# name; its copies get new ones. A duplicated id that a door or window still
# points at is LEFT ALONE and reported - both twins answer to that name, so
# there is no honest way to say whose door it is, and guessing would orphan
# it.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
InteriorPro.send(:remove_const, :WallTool) if InteriorPro.const_defined?(:WallTool, false)
require './arc_math'
require './wall_tool'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

WT = InteriorPro::WallTool

def wall(m, id, s = [0, 0], e = [100, 0], moved: false)
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', id)
  g.set_attribute('InteriorPro', 'start_x', s[0]); g.set_attribute('InteriorPro', 'start_y', s[1])
  g.set_attribute('InteriorPro', 'end_x',   e[0]); g.set_attribute('InteriorPro', 'end_y',   e[1])
  g.set_attribute('InteriorPro', 'thickness', 5.0)
  g.set_attribute('InteriorPro', 'height', 96.0)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-left')
  g.set_attribute('InteriorPro', 'level', 1)
  g.transformation = Geom::Transformation.new(Geom::Point3d.new(84.114, 124.574, 0)) if moved
  g
end

def door_on(m, wall_id)
  d = m.entities.add_group
  d.set_attribute('InteriorPro', 'type', 'door')
  d.set_attribute('InteriorPro', 'host_wall_id', wall_id)
  d
end

def id_of(g)
  g.get_attribute('InteriorPro', 'id')
end

def ids(m)
  m.entities.grep(Sketchup::Group)
   .select { |g| g.get_attribute('InteriorPro', 'type') == 'wall' }
   .map { |g| g.get_attribute('InteriorPro', 'id') }
end

# ------------------------------------------------- a clean model is untouched
Sketchup.reset_model!
m = Sketchup.active_model
a = wall(m, 'aaa')
b = wall(m, 'bbb')
ok('a model with no duplicates is left exactly as it was',
   WT.ensure_unique_ids!(m) == [0, 0], WT.ensure_unique_ids!(m))
ok('and the ids did not change', [id_of(a), id_of(b)] == %w[aaa bbb], ids(m))

# --------------------------------------------------------- the real case
Sketchup.reset_model!
m = Sketchup.active_model
orig = wall(m, 'same')
copy = wall(m, 'same', moved: true)
renamed, skipped = WT.ensure_unique_ids!(m)
ok('the copy is renamed', renamed == 1, [renamed, skipped])
ok('nothing was skipped', skipped == 0, skipped)
ok('THE ORIGINAL KEEPS ITS NAME  <<< the wall that never moved',
   id_of(orig) == 'same', id_of(orig))
ok('the copy has a different name now', id_of(copy) != 'same', id_of(copy))
ok('the new name is not empty', !id_of(copy).to_s.empty?, id_of(copy))
ok('the model has two names for two walls', ids(m).uniq.length == 2, ids(m))

# running it twice must not rename anything again
ok('running it again does nothing', WT.ensure_unique_ids!(m) == [0, 0])

# ------------------------------------------ his model: three pairs at once
Sketchup.reset_model!
m = Sketchup.active_model
%w[w12 w13 w14].each do |wid|
  wall(m, wid)
  wall(m, wid, moved: true)
end
renamed, = WT.ensure_unique_ids!(m)
ok('three duplicated pairs -> three renames', renamed == 3, renamed)
ok('six walls, six names', ids(m).length == 6 && ids(m).uniq.length == 6, ids(m))

# ------------------------------------- a door on the name means hands off
Sketchup.reset_model!
m = Sketchup.active_model
o = wall(m, 'hosted')
c = wall(m, 'hosted', moved: true)
door_on(m, 'hosted')
renamed, skipped = WT.ensure_unique_ids!(m)
ok('a duplicated id with a door on it is NOT renamed', renamed == 0, renamed)
ok('and it is reported instead of hidden', skipped == 2, skipped)
ok('both walls keep the name', [id_of(o), id_of(c)] == %w[hosted hosted], ids(m))

# a door on a DIFFERENT id does not protect this one
Sketchup.reset_model!
m = Sketchup.active_model
o2 = wall(m, 'free')
c2 = wall(m, 'free', moved: true)
wall(m, 'other')
door_on(m, 'other')
renamed, = WT.ensure_unique_ids!(m)
ok('a door on another wall does not block the fix', renamed == 1, renamed)
ok('and that other wall kept its name', ids(m).include?('other'), ids(m))

# ----------------------------------------- neither twin was ever moved
Sketchup.reset_model!
m = Sketchup.active_model
p1 = wall(m, 'tie')
p2 = wall(m, 'tie')
renamed, = WT.ensure_unique_ids!(m)
ok('when neither moved, one still keeps the name and one is renamed',
   renamed == 1 && [id_of(p1), id_of(p2)].count('tie') == 1,
   [id_of(p1), id_of(p2)])

# ---------------------------------------------- three walls, one name
Sketchup.reset_model!
m = Sketchup.active_model
t1 = wall(m, 'trip')
wall(m, 'trip', moved: true)
wall(m, 'trip', moved: true)
renamed, = WT.ensure_unique_ids!(m)
ok('three walls sharing one name -> two renames', renamed == 2, renamed)
ok('and the one that never moved kept it', id_of(t1) == 'trip', id_of(t1))
ok('three walls, three names', ids(m).uniq.length == 3, ids(m))

# ------------------------------------- room sync heals it without being asked
# This is the point: nobody has to remember to run anything. Sync runs after
# every wall edit.
require './room_manager'
src = File.read('./room_manager.rb', encoding: 'UTF-8')
sync = src[/def self\.sync_rooms!.*?detected = /m].to_s
ok('sync_rooms! checks for duplicate ids before it does anything else',
   sync.include?('ensure_unique_ids!'), sync[0, 200])
ok('and it cannot take SketchUp down if that check ever raises',
   sync.include?('rescue StandardError'), sync[0, 400])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

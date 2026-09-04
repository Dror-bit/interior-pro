# encoding: utf-8
# rt159 - A NEW MATERIAL IS STAMPED THE MOMENT IT IS BORN (2026-09-18).
#
# The plugin makes materials in 17 places. Rather than edit seven working
# files, one SketchUp hook notes every new material and a drain stamps
# them a moment LATER - never inside the observer callback, because
# changing the model from inside one is a known way to push SketchUp
# over. This pins the note/drain pair, which is the part that carries
# the logic; the hook itself only calls note_new and asks for a drain.
require './sketchup_stub'
require './material_ids'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

MI = InteriorPro::MaterialIds
Sketchup.reset_model!
m = Sketchup.active_model
MI.clear_pending!

# ---- 1. noting changes nothing on the material ----------------------
a = m.materials.add('Roof')
MI.note_new(a)
ok('one material is waiting', MI.pending_count == 1, MI.pending_count)
ok('noting does NOT stamp it - no model change in the callback',
   MI.id_of(a).nil?)
MI.note_new(a)
ok('noting the same one twice does not queue it twice', MI.pending_count == 1)

# ---- 2. the drain stamps, once ---------------------------------------
made = MI.drain!(m)
ok('the drain stamped it', made == 1, made)
ok('...with the first id', MI.id_of(a) == 'IP_MAT_0001', MI.id_of(a))
ok('the list is empty after a drain', MI.pending_count.zero?)
ok('draining again does nothing', MI.drain!(m).zero?)

# ---- 3. a whole build adds several at once ---------------------------
b = m.materials.add('Fascia')
c = m.materials.add('Gutter')
d = m.materials.add('Tile')
[b, c, d].each { |x| MI.note_new(x) }
ok('three waiting', MI.pending_count == 3)
ok('one drain takes all three', MI.drain!(m) == 3)
ok('and they got 2, 3, 4 in order',
   [MI.id_of(b), MI.id_of(c), MI.id_of(d)] ==
   %w[IP_MAT_0002 IP_MAT_0003 IP_MAT_0004],
   [MI.id_of(b), MI.id_of(c), MI.id_of(d)])

# ---- 4. one that already has an id is not touched --------------------
MI.note_new(a)
ok('a material that already has an id is not re-stamped', MI.drain!(m).zero?)
ok('...and keeps the id it had', MI.id_of(a) == 'IP_MAT_0001')

# ---- 5. the kill switch ---------------------------------------------
orig = MI::USE_MATERIAL_IDS
MI.send(:remove_const, :USE_MATERIAL_IDS)
MI.const_set(:USE_MATERIAL_IDS, false)
e = m.materials.add('Off')
ok('with the switch off nothing is even queued', MI.note_new(e).zero?)
ok('...and a drain does nothing', MI.drain!(m).zero?)
ok('...and watch! attaches nothing', MI.watch!(m) == false)
MI.send(:remove_const, :USE_MATERIAL_IDS)
MI.const_set(:USE_MATERIAL_IDS, orig)

# ---- 6. nothing was lost along the way -------------------------------
au = MI.audit(m)
ok('four materials carry an id', au[:count] == 4, au)
ok('no duplicates', au[:duplicates].empty?, au[:duplicates])
ok('only the one made while the switch was off has none',
   au[:without_id] == ['Off'], au[:without_id])

puts($fails.zero? ? 'rt159 OK' : "rt159 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

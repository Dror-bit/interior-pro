# encoding: utf-8
# rt158 - A PERMANENT ID ON A MATERIAL (2026-09-18, step 1.2 of
# VRAY_POC_PLAN.md).
#
# A SketchUp material is identified by its NAME, and a name moves - the
# user renames it, SketchUp appends "#1", an import brings its own. On
# his model (vray_api_report.txt) 106 materials carried no attribute at
# all, so there was no handle. This pins the one we now write:
#   dictionary "InteriorPro_Material", key "id", value "IP_MAT_0001".
# Nothing here may ever depend on a name.
require './sketchup_stub'
require './material_ids'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

MI = InteriorPro::MaterialIds

# ---- 1. the shape of an id, with no model at all --------------------
ok('the first id reads IP_MAT_0001', MI.format_id(1) == 'IP_MAT_0001', MI.format_id(1))
ok('the 42nd reads IP_MAT_0042', MI.format_id(42) == 'IP_MAT_0042')
ok('it keeps growing past four digits', MI.format_id(12345) == 'IP_MAT_12345')
ok('an id of ours is recognised', MI.id?('IP_MAT_0007'))
ok('a material NAME is not an id', !MI.id?('Stucco'))
ok('nor is something that only starts like one', !MI.id?('IP_MAT_x'))

# ---- 2. stamping ----------------------------------------------------
Sketchup.reset_model!
m = Sketchup.active_model
a = m.materials.add('Stucco')
b = m.materials.add('#ffffff')

ok('a fresh material has no id - nothing is stamped behind our back',
   MI.id_of(a).nil?)
ida = MI.ensure_id!(a, m)
ok('stamping gives the first id', ida == 'IP_MAT_0001', ida)
ok('...and it can be read back', MI.id_of(a) == 'IP_MAT_0001')
ok('stamping again does NOT change it', MI.ensure_id!(a, m) == 'IP_MAT_0001')
idb = MI.ensure_id!(b, m)
ok('the next material gets the next number', idb == 'IP_MAT_0002', idb)

# ---- 3. the name is not the handle ----------------------------------
a.name = 'Stucco #1'
ok('renaming the material does not touch its id', MI.id_of(a) == 'IP_MAT_0001')
ok('find() gets it back by id, whatever it is called now',
   MI.find('IP_MAT_0001', m).equal?(a))
ok('an id nobody has gives nil', MI.find('IP_MAT_9999', m).nil?)
ok('nil and empty give nil', MI.find(nil, m).nil? && MI.find('', m).nil?)

# ---- 4. a number is never handed out twice --------------------------
m.materials.remove(b)
c = m.materials.add('Tile')
idc = MI.ensure_id!(c, m)
ok('after a material is deleted the counter does NOT go back',
   idc == 'IP_MAT_0003', idc)

# ---- 5. stamp_all! fills in blanks only -----------------------------
d = m.materials.add('Wood')
e = m.materials.add('Glass')
made, had = MI.stamp_all!(m)
ok('stamp_all! stamped the two new ones', made == 2, [made, had])
ok('...and left the two that already had an id alone', had == 2, [made, had])
ok('running it again stamps nothing', MI.stamp_all!(m) == [0, 4], MI.stamp_all!(m))
ok('every material now has an id',
   [a, c, d, e].all? { |x| MI.id?(MI.id_of(x)) },
   [a, c, d, e].map { |x| MI.id_of(x) })

# ---- 6. the audit ---------------------------------------------------
au = MI.audit(m)
ok('the audit counts four ids', au[:count] == 4, au)
ok('nothing is without an id', au[:without_id].empty?, au[:without_id])
ok('and there are no duplicates', au[:duplicates].empty?, au[:duplicates])

# ---- 7. the kill switch ---------------------------------------------
orig = MI::USE_MATERIAL_IDS
MI.send(:remove_const, :USE_MATERIAL_IDS)
MI.const_set(:USE_MATERIAL_IDS, false)
f = m.materials.add('Off')
ok('with the switch off nothing is stamped', MI.ensure_id!(f, m).nil?)
ok('...nothing is read either', MI.id_of(a).nil?)
ok('...and find() finds nothing', MI.find('IP_MAT_0001', m).nil?)
ok('...but the id is still ON the material, untouched',
   a.get_attribute('InteriorPro_Material', 'id') == 'IP_MAT_0001')
MI.send(:remove_const, :USE_MATERIAL_IDS)
MI.const_set(:USE_MATERIAL_IDS, orig)
ok('switching back on brings it straight back', MI.id_of(a) == 'IP_MAT_0001')

puts($fails.zero? ? 'rt158 OK' : "rt158 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

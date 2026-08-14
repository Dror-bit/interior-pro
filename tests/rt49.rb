# encoding: utf-8
# rt49 - a new setting must survive InteriorPro.reload! (2026-08-14).
#
# The bug this exists for, in the user's words: "I picked a folder, it says 18
# pictures added, and nothing shows up."
#
# The pictures were fine. The settings list was not. It was written as
#
#     DEFAULT_STATE = { ... } unless const_defined?(:DEFAULT_STATE, false)
#
# which is the correct way to write a constant you reload - but it also means
# reload! keeps the hash from the FIRST load, forever. save_state throws away
# any key not in that hash, so on the day 'images' was added, every picture the
# user chose was deleted on its way to the model. Only a full SketchUp restart
# would have fixed it, and nothing said so.
#
# So: the defaults are a METHOD now, and this suite loads the file twice - the
# way reload! does - and demands that a setting added after the first load
# still gets through.
require 'json'
require './sketchup_stub'
require './plan_doc'
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PSD = InteriorPro::PlanSheetDialog

# ------------------------------------------------------- the trap, reproduced
ok('the defaults are a method, not a frozen constant',
   PSD.respond_to?(:default_state))
ok('and nothing is left calling the old constant',
   !PSD.const_defined?(:DEFAULT_STATE, false) ||
   !File.read('./plan_sheet_dialog.rb').match?(/^\s*DEFAULT_STATE\.(keys|merge|dup)/),
   'DEFAULT_STATE is still being read')

# Load the file a second time. This is exactly what InteriorPro.reload! does,
# and it is the moment the old code went stale.
load './plan_sheet_dialog.rb'
ok('a second load still knows about pictures',
   PSD.default_state.key?('images'), PSD.default_state.keys)
ok('the defaults can be built twice without freezing',
   PSD.default_state.equal?(PSD.default_state) == false,
   'the same frozen object came back twice')

# ------------------------------------------------------ a picture is kept
Sketchup.reset_model!
PSD.save_state(PSD.default_state.merge(
  'images' => ['C:/renders/a.jpg', 'C:/renders/b.jpg'],
  'sheet_number' => 'A-101'
))
st = PSD.load_state
ok('the pictures reach the model and come back',
   st['images'] == ['C:/renders/a.jpg', 'C:/renders/b.jpg'], st['images'])
ok('and so does everything that was already working',
   st['sheet_number'] == 'A-101' && st['size'] == 'ARCH D', st)

PSD.save_state(st.merge('images' => []))
ok('clearing them clears them', PSD.load_state['images'] == [],
   PSD.load_state['images'])

# ------------------------------------- every setting the layout reads is known
# If layout_pages! asks for a key the defaults have never heard of, save_state
# silently drops it and the feature dies the same quiet death as the pictures.
src  = File.read('./plan_canvas.rb')
used = src.scan(/\bst\[['"]([a-z_]+)['"]\]/).flatten.uniq
known = PSD.default_state.keys + PSD.extra_state_keys
missing = used - known
ok('every setting the page layout reads is in the defaults', missing.empty?, missing)

# ------------------------------------------------------ nothing else moved
ok('a fresh model still opens on ARCH D, quarter inch',
   PSD.default_state['size'] == 'ARCH D' && PSD.default_state['scale'] == '1/4"')
ok('the free geometry settings are still there',
   %w[site_pids site_z_max site_soft].all? { |k| PSD.default_state.key?(k) })
ok('where the plan sits is still remembered',
   %w[origin_x origin_y active zoom].all? { |k| PSD.extra_state_keys.include?(k) })

# and a stray key from the window is not written to the model
Sketchup.reset_model!
PSD.save_state(PSD.default_state.merge('site_count' => 7, 'nonsense' => 1))
ok('junk from the window is not saved',
   !PSD.load_state.key?('nonsense') && PSD.load_state['site_count'].nil?,
   PSD.load_state.keys)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

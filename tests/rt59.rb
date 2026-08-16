# encoding: utf-8
# rt59 - state_backup.rb: nothing the user made can be lost to one write.
#
# THE DAY THIS WAS WRITTEN
# The user traced a whole site over a photo in the 2D editor and saved. The
# next day he pressed "Apply to Model". The build produced nothing, and the
# window wrote an EMPTY draft straight over the good one. There was no second
# copy anywhere. A day's work, gone in one attribute write.
#
# So this suite is not really about a module. It is about one promise: a
# write NEVER destroys what it replaces. Every check below is a way that
# promise could be broken.
require './sketchup_stub'
require 'json'
require 'tmpdir'
require './state_backup'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

SB = InteriorPro::StateBackup
def m; Sketchup.active_model; end
def live(k); m.get_attribute('InteriorPro', k).to_s; end

# ------------------------------------------------------------ the promise

Sketchup.reset_model!
SB.write!('plan_draft', 'THE REAL WORK')
ok('a first write just writes', live('plan_draft') == 'THE REAL WORK', live('plan_draft'))
ok('nothing to back up yet', SB.history('plan_draft').empty?, SB.history('plan_draft'))

# THE disaster: an empty value written over good work.
SB.write!('plan_draft', '')
ok('the empty write did land', live('plan_draft') == '', live('plan_draft'))
ok('THE PROMISE: the real work is still recoverable',
   SB.history('plan_draft').first['json'] == 'THE REAL WORK',
   SB.history('plan_draft'))

SB.restore!('plan_draft')
ok('and restoring really brings it back', live('plan_draft') == 'THE REAL WORK',
   live('plan_draft'))

# An EMPTY value is not worth a backup slot - it is the thing we are
# protecting against, not something anyone wants back.
ok('an empty value is never kept as a backup',
   SB.history('plan_draft').none? { |h| h['json'].to_s.empty? },
   SB.history('plan_draft').map { |h| h['json'] })

# But restoring over REAL work must not be a second disaster: whatever was
# live at the moment of the restore has to be recoverable too.
Sketchup.reset_model!
SB.write!('plan_draft', 'OLD GOOD')
SB.write!('plan_draft', 'NEW WORK')          # OLD GOOD -> history
SB.restore!('plan_draft')                    # brings OLD GOOD back
ok('restoring put the old one back', live('plan_draft') == 'OLD GOOD', live('plan_draft'))
ok('and the work the restore overwrote is itself recoverable',
   SB.history('plan_draft').first['json'] == 'NEW WORK',
   SB.history('plan_draft').map { |h| h['json'] })

# ------------------------------------------ the autosave must not flood it
#
# The editor saves the draft every 1.5 seconds. Without this, one minute of
# sitting still would push every real earlier version out of the history.

Sketchup.reset_model!
SB.write!('plan_draft', 'V1')
SB.write!('plan_draft', 'V2')
40.times { SB.write!('plan_draft', 'V2') }        # the autosave, ticking away
ok('an unchanged write adds no backup', SB.history('plan_draft').length == 1,
   SB.history('plan_draft').length)
ok('and V1 is still the one being held',
   SB.history('plan_draft').first['json'] == 'V1',
   SB.history('plan_draft').map { |h| h['json'] })
ok('the live value is untouched by all that', live('plan_draft') == 'V2')

# ------------------------------------------------------------- the depth

Sketchup.reset_model!
(1..10).each { |i| SB.write!('plan_draft', "V#{i}") }
h = SB.history('plan_draft')
ok('the history is capped', h.length == InteriorPro::StateBackup::KEEP, h.length)
ok('the newest backup is the version just replaced',
   h.first['json'] == 'V9', h.map { |e| e['json'] })
ok('the oldest kept is as far back as the cap allows',
   h.last['json'] == 'V4', h.map { |e| e['json'] })
ok('every backup remembers when it was taken',
   h.all? { |e| e['at'].to_s.length > 8 }, h.map { |e| e['at'] })

ok('restore! takes a depth', SB.restore!('plan_draft', 3))
ok('and depth 3 is the third one back', live('plan_draft') == 'V7', live('plan_draft'))

ok('asking past the end refuses instead of crashing',
   SB.restore!('plan_draft', 99) == false)
ok('and refusing changed nothing', live('plan_draft') == 'V7', live('plan_draft'))
ok('asking for a key that has none refuses',
   SB.restore!('never_seen') == false)

# ------------------------------------------------------- more than one key
#
# The sheet window keeps its own state. One key's history must never touch
# another's.

Sketchup.reset_model!
SB.write!('plan_draft', 'draft A')
SB.write!('sheet_state', 'sheet A')
SB.write!('plan_draft', 'draft B')
SB.write!('sheet_state', 'sheet B')
ok('two keys keep two separate histories',
   SB.history('plan_draft').first['json'] == 'draft A' &&
   SB.history('sheet_state').first['json'] == 'sheet A',
   [SB.history('plan_draft').first['json'], SB.history('sheet_state').first['json']])
SB.restore!('plan_draft')
ok('restoring one does not disturb the other', live('sheet_state') == 'sheet B',
   live('sheet_state'))

# ------------------------------------------------------------- the .skp size
#
# A backup that makes the file unopenable is not a backup.

Sketchup.reset_model!
big = 'x' * (InteriorPro::StateBackup::MAX_ONE + 10)
SB.write!('plan_draft', big)
SB.write!('plan_draft', 'small')
ok('a value too big to copy is not copied', SB.history('plan_draft').empty?,
   SB.history('plan_draft').map { |e| e['bytes'] })
ok('but the write itself still went through', live('plan_draft') == 'small')

Sketchup.reset_model!
chunk = 'y' * 800_000
(1..6).each { |i| SB.write!('plan_draft', chunk + i.to_s) }
total = SB.history('plan_draft').map { |e| e['bytes'].to_i }.inject(0) { |a, b| a + b }
ok('the history stays inside its byte budget',
   total <= InteriorPro::StateBackup::MAX_BYTES, total)
ok('and at least the newest backup survives the trim',
   SB.history('plan_draft').length >= 1, SB.history('plan_draft').length)

# ------------------------------------------------------------- finding it
#
# In an emergency nobody remembers the key names.

Sketchup.reset_model!
SB.write!('plan_draft', 'A')
SB.write!('plan_draft', 'B')
SB.write!('sheet_state', 'S1')
SB.write!('sheet_state', 'S2')
SB.write!('something_nobody_told_it_about', 'Q1')
SB.write!('something_nobody_told_it_about', 'Q2')

l = SB.list
byk = {}
l.each { |r| byk[r[:key]] = r }
ok('list finds the draft', byk['plan_draft'] && byk['plan_draft'][:backups] == 1,
   byk['plan_draft'])
ok('list finds the sheet', byk['sheet_state'] && byk['sheet_state'][:backups] == 1,
   byk['sheet_state'])
ok('list finds a key it was never told about',
   byk['something_nobody_told_it_about'] &&
   byk['something_nobody_told_it_about'][:backups] == 1,
   byk.keys)
ok('list says how big the live value is',
   byk['plan_draft'][:now] == 1, byk['plan_draft'][:now])

path = SB.report(File.join(Dir.tmpdir, 'rt59_backup_report.txt'))
ok('the report writes a file', path && File.file?(path), path)
txt = File.read(path.to_s)
ok('the report names the draft', txt.include?('plan_draft'))
ok('the report tells you how to get it back', txt.include?('restore!'))

# ------------------------------------------------------- it never explodes
#
# A backup mechanism that can raise is worse than none: it would take the
# save down with it.

Sketchup.reset_model!
ok('a nil value is survivable', SB.write!('plan_draft', nil))
ok('a nil model refuses quietly', SB.write!('plan_draft', 'x', nil) == false)
m.set_attribute('InteriorPro', 'plan_draft__history', 'not json at all')
ok('a corrupt history reads as empty, not as a crash',
   SB.history('plan_draft') == [], SB.history('plan_draft'))
ok('and a write over a corrupt history still works',
   SB.write!('plan_draft', 'after corruption'))
ok('the value really landed', live('plan_draft') == 'after corruption')

# ------------------------------------- the traced image and its calibration
#
# He loads a photo and fits it against one known length. That measurement is
# the reason the tracing is to scale, and three different actions used to
# throw it away with no copy anywhere: loading a different image, removing
# the image, and re-placing it. This is the part he actually lost.
require './plan_editor'
PE = InteriorPro::PlanEditor

ok('the editor exposes a way to put an underlay back',
   PE.respond_to?(:restore_underlay!))
ok('and a way to take a snapshot', PE.respond_to?(:snapshot_underlay!))

Sketchup.reset_model!
PE.store_underlay('C:/pics/site.jpg')
PE.store_underlay_placement({ 'x' => 12.5, 'y' => -7.25, 'scale' => 0.0413,
                              'opacity' => 0.55, 'locked' => true, 'rot' => 0.0 })
ok('the calibration is live', (live('underlay_scale').to_f - 0.0413).abs < 1e-9,
   live('underlay_scale'))

# THE moment it used to vanish: a different picture wipes the calibration.
PE.store_underlay('C:/pics/other.jpg')
ok('a new image really does clear the calibration (unchanged behaviour)',
   PE.send(:underlay_placement).nil?, PE.send(:underlay_placement))
h = SB.history('underlay_state')
ok('BUT the calibration is now recoverable', h.any?, h.length)
ok('and the backup holds the real numbers',
   h.any? { |e| (JSON.parse(e['json'])['scale'].to_f - 0.0413).abs < 1e-9 },
   h.map { |e| JSON.parse(e['json'])['scale'] })
ok('and it remembers which picture it belonged to',
   h.any? { |e| JSON.parse(e['json'])['path'].to_s.include?('site.jpg') },
   h.map { |e| JSON.parse(e['json'])['path'] })

# Removing the image entirely - the other way it used to go.
Sketchup.reset_model!
PE.store_underlay('C:/pics/site.jpg')
PE.store_underlay_placement({ 'x' => 1, 'y' => 2, 'scale' => 0.02,
                              'opacity' => 0.5, 'locked' => false, 'rot' => 3.0 })
PE.store_underlay(nil)
ok('removing the image clears it (unchanged behaviour)',
   PE.send(:underlay_placement).nil?)
ok('and that is recoverable too', SB.history('underlay_state').any?)

n = PE.restore_underlay!
ok('restore_underlay! reports success', n)
ok('the picture came back', live('underlay_path').include?('site.jpg'),
   live('underlay_path'))
ok('the scale came back', (live('underlay_scale').to_f - 0.02).abs < 1e-9,
   live('underlay_scale'))
ok('the rotation came back', (live('underlay_rot').to_f - 3.0).abs < 1e-9,
   live('underlay_rot'))

Sketchup.reset_model!
ok('nothing to restore refuses quietly', PE.restore_underlay! == false)
ok('and an empty model is not worth a snapshot', PE.snapshot_underlay! == false)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

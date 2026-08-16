# encoding: utf-8
# rt60 - auto_backup.rb: a copy of the whole project, by itself.
#
# WHAT THE USER SAID
# "I go out and take measurements, I trace the whole thing, I come home and
# everything is deleted. That's it."
#
# So the promise here is not a feature, it is a floor: at any moment there is
# a complete .skp from a few minutes ago sitting on the disk, and nobody had
# to press anything for that to be true.
#
# The naming and pruning are pure string work and are checked as such. The
# rest RUNS - a real tick, a real file on disk, a real timer fired.
require './sketchup_stub'
require 'tmpdir'
require 'fileutils'
require './auto_backup'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

AB = InteriorPro::AutoBackup
T1 = Time.new(2026, 8, 16, 14, 47, 3)

# --------------------------------------------------------------- the names

ok('the stamp sorts as text the way time runs',
   AB.stamp_for(T1) == '2026-08-16_144703', AB.stamp_for(T1))
ok('two times an hour apart sort in the right order',
   AB.stamp_for(Time.new(2026, 8, 16, 9, 0, 0)) <
   AB.stamp_for(Time.new(2026, 8, 16, 14, 0, 0)))
ok('and so do two DAYS apart',
   AB.stamp_for(Time.new(2026, 8, 9, 23, 0, 0)) <
   AB.stamp_for(Time.new(2026, 8, 10, 1, 0, 0)))

ok('the project name is taken without its extension',
   AB.base_for('C:/jobs/6 Bronco Lane.skp') == '6 Bronco Lane',
   AB.base_for('C:/jobs/6 Bronco Lane.skp'))
ok('a name with dots in it survives',
   AB.base_for('/x/site.v2.skp') == 'site.v2', AB.base_for('/x/site.v2.skp'))
ok('an unsaved project still gets a name', AB.base_for('') == 'Untitled')
ok('and so does a nil path', AB.base_for(nil) == 'Untitled')

ok('the copy is named for the project and the moment',
   AB.backup_name('C:/jobs/6 Bronco Lane.skp', T1) ==
   '6 Bronco Lane_2026-08-16_144703.skp',
   AB.backup_name('C:/jobs/6 Bronco Lane.skp', T1))

# --------------------------------------------------------------- the folder

ok('copies sit BESIDE the project, not somewhere he has to hunt for',
   AB.backup_dir('C:/jobs/site.skp') == 'C:/jobs/InteriorPro_backups',
   AB.backup_dir('C:/jobs/site.skp'))
d = AB.backup_dir('', Dir.tmpdir)
ok('an unsaved project has somewhere to go too',
   d.to_s.end_with?('InteriorPro_backups'), d)

# --------------------------------------------------------------- the pruning

names = (1..25).map { |i| format('site_2026-08-16_1400%02d.skp', i) }
kill = AB.prune_list(names, 'site', 20)
ok('only the excess is deleted', kill.length == 5, kill.length)
ok('and it is the OLDEST that go',
   kill.sort == names.sort.first(5), kill.sort)
ok('the newest is never touched', !kill.include?(names.max), kill)

ok('fewer copies than the limit means nothing is deleted',
   AB.prune_list(names.first(3), 'site', 20) == [], AB.prune_list(names.first(3), 'site', 20))

# The folder can hold two different projects. One must not eat the other's.
mixed = names.first(25) + (1..25).map { |i| format('other_2026-08-16_1400%02d.skp', i) }
kill2 = AB.prune_list(mixed, 'site', 20)
ok('another project\'s copies are never deleted',
   kill2.none? { |n| n.start_with?('other_') }, kill2)
ok('and the right number of ours still go', kill2.length == 5, kill2.length)

# Nothing else in the folder is fair game either.
junk = names + ['readme.txt', 'site_notes.docx', 'site_2026-08-16_140001.skp.bak']
kill3 = AB.prune_list(junk, 'site', 20)
ok('only .skp copies are considered',
   kill3.all? { |n| n.end_with?('.skp') }, kill3)
ok('a stray text file is left alone', !kill3.include?('readme.txt'))

# ------------------------------------------------------- a real backup runs

dir = Dir.mktmpdir('rt60')
proj = File.join(dir, 'bronco.skp')
File.write(proj, 'pretend project')

Sketchup.reset_model!
m = Sketchup.active_model
m.path = proj

ok('an EMPTY model is not worth copying', AB.tick!(m).nil?, AB.tick!(m))

m.entities.add_group        # now there is work in it
out = AB.tick!(m)
ok('a real backup was written', out && File.file?(out), out)
ok('it landed in the backups folder beside the project',
   out.to_s.include?('InteriorPro_backups'), out)
ok('it is named for the project', File.basename(out.to_s).start_with?('bronco_'), out)
ok('save_copy was used, so the project itself was not re-pointed',
   m.path == proj, m.path)
ok('the model recorded exactly one copy', m.copies.length == 1, m.copies)

# ------------------------------------------------ pruning happens for real

bdir = File.join(dir, 'InteriorPro_backups')
(1..30).each { |i| File.write(File.join(bdir, format('bronco_2026-01-01_0000%02d.skp', i)), 'x') }
AB.prune!(bdir, 'bronco', 20)
left = Dir.entries(bdir).select { |n| n.start_with?('bronco_') && n.end_with?('.skp') }
ok('the folder is trimmed to the limit', left.length == 20, left.length)
ok('and what is left is the newest', left.include?(left.max), left.length)

# ------------------------------------------------------------- the timer
#
# The whole promise rests on this running by itself. A backup that has to be
# started by hand is the button he told us to take away.

UI.reset_timers!
AB.stop!
id = AB.start!(300)
ok('starting really schedules a timer', !id.nil?, id)
ok('and it reports itself as running', AB.running?)
t = UI.timers[id]
ok('it repeats - not a one-off', t && t[:repeat] == true, t && t[:repeat])
ok('at the interval it was given', t && t[:secs].to_i == 300, t && t[:secs])

# Fire it and check a copy really comes out - proving the block is wired to
# tick! and not to nothing.
#
# The copy made earlier in this suite carries the same second in its name, and
# tick! refuses to write over a name that already exists. That guard is right
# (two backups in the same second say nothing), but it would make this check
# pass for the wrong reason, so the earlier copy is cleared out first.
Dir.entries(bdir).select { |n| n.start_with?('bronco_2026-08') }
   .each { |n| File.delete(File.join(bdir, n)) }
before = m.copies.length
UI.fire_timer!(id)
ok('the timer really makes a backup when it fires',
   m.copies.length == before + 1, [before, m.copies.length])
ok('and the file it fired really exists on disk',
   AB.last && File.file?(AB.last), AB.last)

# reload! calls start! again. Two timers would halve the history.
id2 = AB.start!(300)
ok('starting again replaces the timer instead of adding one',
   UI.timers.length == 1, UI.timers.keys)
ok('and the old one is gone', UI.timers[id].nil?, id)

ok('it can be turned off', AB.stop!)
ok('and then it is not running', !AB.running?)
ok('turning it off twice is harmless', AB.stop! == false)

# ------------------------------------------------------------- it never bites

Sketchup.reset_model!
ok('a model with no path and no entities is skipped, not crashed on',
   AB.tick!(Sketchup.active_model).nil?)
ok('a nil model is survivable', AB.tick!(nil).nil?)

FileUtils.remove_entry(dir) rescue nil

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)

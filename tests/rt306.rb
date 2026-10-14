# encoding: utf-8
# rt306 - THE DRAWING STAYS AWAKE WHEN THE WINDOW IS OPENED AGAIN (2026-10-13 20:23, his "הוא מציב אותו ב-3D אבל לא מראה אותו
# בתוכנית סירטוט"). Measured: "watcher: NilClass" with the window open - the OLD window's on_closed fired after the new
# window hung its watchers and took them down. Now only the current window takes them down.
require './sketchup_stub'
require './plan_editor'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PE = InteriorPro::PlanEditor
src = File.read('./plan_editor.rb')
ok('the on_closed of a window takes the watchers down only while it is the current window',
   src.include?('dlg.set_on_closed { detach_undo_observer if @dialog.equal?(dlg) }'))
ok('watchers_on? reports both watchers', src.include?('def watchers_on?') && src.include?('!@elec_obs.nil?'))
# play it: open, open again (the first is closed by show), then the FIRST window's on_closed fires late
begin
  PE.show
  d1 = PE.instance_variable_get(:@dialog)
  ok('first window: watchers on', PE.watchers_on?)
  PE.show
  d2 = PE.instance_variable_get(:@dialog)
  ok('a second show makes a new window', !d1.equal?(d2))
  ok('second window: watchers on', PE.watchers_on?)
  late = d1.instance_variable_get(:@on_closed)
  late.call if late
  ok('the first window\'s late on_closed leaves the new window\'s watchers alone', PE.watchers_on?)
  d2.instance_variable_get(:@on_closed)&.call
  ok('the current window closing does take them down', !PE.watchers_on?)
rescue StandardError => e
  ok("the play-through runs in the stub (#{e.class}: #{e.message.to_s[0, 80]})", false)
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)

# encoding: utf-8
# rt43 - the sheet is reachable without hunting through a menu (2026-08-12).
#
# The user asked for two things and this suite pins both:
#   1. a BUTTON on the 2D toolbar, with its own icon, not a menu item
#   2. a button inside the 2D editor that opens the sheet straight away
#
# It reads the real files, so it fails the day someone deletes the wiring.
$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

DIR = File.dirname(__FILE__)
tb  = File.read(File.join(DIR, 'toolbar.rb'), encoding: 'UTF-8')
pe  = File.read(File.join(DIR, 'plan_editor.rb'), encoding: 'UTF-8')

# ------------------------------------------------------- the toolbar button
ok('the 2D toolbar has a Sheet command', tb.include?("UI::Command.new('Sheet')"))
ok('it opens the sheet window', tb =~ /UI::Command\.new\('Sheet'\)\s*\{\s*InteriorPro::PlanSheetDialog\.show/m,
   tb[/UI::Command\.new\('Sheet'\).{0,120}/m])
ok('it is added to the toolbar', tb.include?('tb.add_item(sheet_cmd)'))
ok('it has its own icon', tb.include?("icon_path('sheet_pdf')"))
ok('the 2D editor button is still there', tb.include?('tb.add_item(editor_cmd)'))
ok('the toolbar makes room for two buttons now',
   tb =~ /Interior Pro 2D'\)\n.*\n\s*return if tb\.length >= 2/, tb[/Interior Pro 2D.{0,160}/m])
ok('it still has a tooltip and a status line',
   tb.include?('sheet_cmd.tooltip') && tb.include?('sheet_cmd.status_bar_text'))

# the icon file really exists, in the form this platform loads
icon = File.join(DIR, '..', 'icons', 'sheet_pdf.svg')
icon = File.join(DIR, 'icons', 'sheet_pdf.svg') unless File.exist?(icon)
ok('the icon file is on disk', File.exist?(icon), icon)
if File.exist?(icon)
  svg = File.read(icon)
  ok('the icon is a real svg', svg.include?('<svg') && svg.include?('viewBox'))
  ok('and it is drawn on the 24 grid the other icons use', svg.include?('0 0 24 24'))
end

# --------------------------------------------------- the button in the editor
ok('the 2D editor has a button that opens the sheet',
   pe.include?('sketchup.open_sheet()'), pe[/sketchup\.open_sheet\(\).{0,60}/])
ok('the button carries a picture, not just a word', pe =~ /open_sheet\(\)".*?>\s*\S*[\u{1F300}-\u{1FAFF}\u{2190}-\u{27BF}]/,
   pe[/onclick="sketchup\.open_sheet\(\)".{0,90}/])
ok('the editor answers that button', pe.include?("add_action_callback('open_sheet')"))
ok('and the answer is the sheet window',
   pe =~ /add_action_callback\('open_sheet'\).{0,200}PlanSheetDialog\.show/m,
   pe[/add_action_callback\('open_sheet'\).{0,200}/m])
ok('a failure there cannot take the editor down with it',
   pe =~ /add_action_callback\('open_sheet'\).{0,300}rescue StandardError/m)

# nothing that already worked was taken away
ok('Apply to Model is untouched', pe.include?('applyPending()'))
ok('the Plans (2D) button is untouched', pe.include?('sketchup.build_plan()'))
ok('the menu item still exists as well', tb.include?("menu.add_item('Sheet: Page + PDF')"))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
